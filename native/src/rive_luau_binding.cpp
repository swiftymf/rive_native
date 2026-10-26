#include "rive_native/rive_binding.hpp"
#include "rive_native/external.hpp"
#include "lua.h"
#include "lualib.h"
#include "rive/lua/rive_lua_libs.hpp"
#include "rive/async/work_pool.hpp"
#include "rive/input/gamepad_snapshot.hpp"
#include "rive/input/standard_gamepad.hpp"
#include "rive/renderer.hpp"
#include "rive/viewmodel/viewmodel_instance_viewmodel.hpp"
#include "rive/core/binary_writer.hpp"
#include "rive/core/vector_binary_stream.hpp"
#include "rive/assets/blob_asset.hpp"
#include "luau_error_parser.hpp"
#ifdef RIVE_CANVAS
#include "rive/renderer/render_context.hpp"
#include <optional>
#endif

const rive::RawPath& renderPathToRawPath(rive::Factory* factory,
                                         rive::RenderPath* renderPath);

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <emscripten/html5.h>
#endif

#include <string>
#include <vector>
#include <chrono>
#include <cstring>

using namespace rive;

#ifdef __EMSCRIPTEN__
// Forward-declare GPU scripting functions from lua_gpu.cpp and
// webgl_factory.cpp. Both translation units are linked into the same WASM
// module.
extern "C" void riveGPUBeginFrame(lua_State* L);
extern "C" void riveGPUEndFrame(lua_State* L);
extern "C" void riveInvalidateGLState(uintptr_t renderContextPtr);

using namespace emscripten;
using ExternalPointer = WasmPtr;
using VoidCallback = emscripten::val;
#else
using ExternalPointer = void*;
typedef void (*VoidCallback)();
#endif

static int riveErrorHandler(lua_State* L);
static void interrupt(lua_State* L, int gc);

class DartExposedScriptingContext : public ScriptingContext
{
public:
#ifdef __EMSCRIPTEN__
    std::vector<emscripten::val> closures;
#endif
    VectorBinaryStream console;
    int timeoutMs = 1000;

    DartExposedScriptingContext(Factory* factory,
                                VoidCallback consoleHasDataCallback) :
        ScriptingContext(factory),
        m_consoleHasDataCallback(consoleHasDataCallback)
    {}

    // The editor builds the Lua `Data` global itself in Dart
    // (ScriptingWorkspaceManager._setupDataGlobal), so File must not also
    // call initializeLuaData on this VM.
    bool initializesDataGlobalExternally() const override { return true; }

    int pCall(lua_State* state, int nargs, int nresults) override
    {
        // calculate stack position for message handler
        int hpos = lua_gettop(state) - nargs;
        // Push the error handler from a cached registry ref instead of minting
        // a fresh CClosure every pcall. The handler is registered lazily on the
        // first call and lives for the lua_State's lifetime; lua_close tears
        // the registry down for us when the VM is destroyed.
        //
        if (m_errorHandlerRef == LUA_NOREF)
        {
            lua_pushcfunction(state, riveErrorHandler, "riveErrorHandler");
            m_errorHandlerRef = lua_ref(state, -1);
            lua_pop(state, 1);
        }
        lua_getref(state, m_errorHandlerRef);
        lua_insert(state, hpos);

#ifdef __EMSCRIPTEN__
        // Ensure we're in the correct WebGL context before executing any Lua
        // code. This covers both the Dart-exported riveLuaPCall path (which
        // already switches, making this a no-op) and C++ internal
        // rive_lua_pcall calls (e.g. scriptInit, scriptAdvance) that bypass
        // the Dart wrapper.
        int vmGL = this->glHandle();
        int prevGL = vmGL ? emscripten_webgl_get_current_context() : 0;
        if (vmGL && vmGL != prevGL)
        {
            emscripten_webgl_make_context_current(vmGL);
        }
#endif

        startTimedExecution(state);
        int ret = lua_pcall(state, nargs, nresults, hpos);
        endTimedExecution(state);
        lua_remove(state, hpos);

#ifdef __EMSCRIPTEN__
        if (vmGL && vmGL != prevGL)
            emscripten_webgl_make_context_current(prevGL);
#endif

        return ret;
    }

    void printError(lua_State* state) override
    {
        const char* error = lua_tostring(state, -1);
        bool pushed = false;
        if (error == nullptr)
        {
            // The value on top of the stack isn't a string or number (e.g. a
            // table, nil, or an error object). luaL_tolstring always yields a
            // string representation (honoring __tostring) so the user sees a
            // real message instead of an empty console line.
            size_t len = 0;
            error = luaL_tolstring(state, -1, &len);
            pushed = true;
        }
        auto parsed = ErrorParser::parse(error);
        writeError(parsed);
        if (pushed)
        {
            lua_pop(state, 1); // balance luaL_tolstring's pushed string
        }
    }

    void printBeginLine(lua_State* state) override
    {
        BinaryWriter writer(&console);
        lua_Debug ar;
        lua_getinfo(state, 1, "sl", &ar);
        writer.write((uint8_t)0);
        writer.write(ar.source);
        writer.writeVarUint((uint32_t)ar.currentline);
    }

    void writeError(const ErrorParser::ParsedError& error)
    {
        BinaryWriter writer(&console);
        writer.write((uint8_t)1);

        writer.writeVarUint((uint64_t)error.filename.size());
        writer.write((const uint8_t*)error.filename.data(),
                     (size_t)error.filename.size());

        writer.writeVarUint((uint32_t)error.line_number.value_or(0));

        // The reader treats a zero-length span as the span-list terminator,
        // and printEndLine() writes that terminator below. Only emit the
        // message as a span when it's non-empty; otherwise a 0-length span
        // here plus the terminator would write two consecutive zero bytes,
        // desyncing the reader for every subsequent console entry.
        if (error.message.size() > 0)
        {
            writer.writeVarUint((uint64_t)error.message.size());
            writer.write((const uint8_t*)error.message.data(),
                         (size_t)error.message.size());
        }
        printEndLine();
    }

    void print(Span<const char> data) override
    {
        if (data.size() == 0)
        {
            return;
        }
        BinaryWriter writer(&console);
        writer.writeVarUint((uint64_t)data.size());
        writer.write((const uint8_t*)data.data(), (size_t)data.size());
    }

    void printEndLine() override
    {
        BinaryWriter writer(&console);
        writer.writeVarUint((uint32_t)0);
        // Fires inside lua_pcall's setjmp scope. The Dart-side dispatcher
        // must be NativeCallable.listener (async); sync re-entry corrupts
        // Dart's GC stack walk.
        if (!m_calledConsoleCallback)
        {
            m_calledConsoleCallback = true;
            m_consoleHasDataCallback();
        }
    }

    void clearConsole()
    {
        console.clear();
        m_calledConsoleCallback = false;
    }

    Span<uint8_t> consoleMemory() { return console.memory(); }

    void startTimedExecution(lua_State* state)
    {
        if (timeoutMs == 0)
        {
            return; // No timeout
        }
        lua_Callbacks* cb = lua_callbacks(state);
        cb->interrupt = interrupt;
        executionTime = std::chrono::steady_clock::now();
    }

    void endTimedExecution(lua_State* state)
    {
        lua_Callbacks* cb = lua_callbacks(state);
        cb->interrupt = nullptr;
    }

    std::chrono::time_point<std::chrono::steady_clock> executionTime;

private:
    VoidCallback m_consoleHasDataCallback;
    bool m_calledConsoleCallback = false;
    // Lua registry ref to a cached riveErrorHandler CClosure. Populated on the
    // first pCall and reused for the lua_State's lifetime. See pCall() above.
    int m_errorHandlerRef = LUA_NOREF;
};

static void interrupt(lua_State* L, int gc)
{
    if (gc >= 0)
    {
        return;
    }

    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(L));

    if (context == nullptr)
    {
        return;
    }

    const auto now = std::chrono::steady_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                  now - context->executionTime)
                  .count();
    if (ms > context->timeoutMs)
    {
        lua_Callbacks* cb = lua_callbacks(L);
        cb->interrupt = nullptr;
        // reserve space for error string
        lua_rawcheckstack(L, 1);

        // Format human-readable error message
        char errorMsg[128];
        if (context->timeoutMs >= 1000)
        {
            double seconds = context->timeoutMs / 1000.0;
            snprintf(errorMsg,
                     sizeof(errorMsg),
                     "execution exceeded %.1f second%s timeout",
                     seconds,
                     seconds == 1.0 ? "" : "s");
        }
        else
        {
            snprintf(errorMsg,
                     sizeof(errorMsg),
                     "execution exceeded %d millisecond%s timeout",
                     context->timeoutMs,
                     context->timeoutMs == 1 ? "" : "s");
        }
        luaL_error(L, "%s", errorMsg);
    }
}

struct RiveLuauBufferResponse
{
#ifdef __EMSCRIPTEN__
    WasmPtr data;
#else
    uint8_t* data;
#endif
    size_t size;
};

EXPORT RiveLuauBufferResponse riveLuaConsole(lua_State* state)
{
    if (state == nullptr)
    {
        return {
#ifdef __EMSCRIPTEN__
            (WasmPtr) nullptr,
#else
            nullptr,
#endif
            0};
    }
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));
    auto memory = context->consoleMemory();

    return {
#ifdef __EMSCRIPTEN__
        (WasmPtr)memory.data(),
#else
        memory.data(),
#endif
        memory.size()};
}

EXPORT void riveLuaConsoleClear(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));
    context->clearConsole();
}

// Creates a ScriptingVM that owns both the lua_State and context.
EXPORT ExternalPointer riveVMCreate(ExternalPointer factory,
                                    VoidCallback consoleHasDataCallback)
{
    auto context =
        std::make_unique<DartExposedScriptingContext>((Factory*)factory,
                                                      consoleHasDataCallback);
    auto* vm = new ScriptingVM(std::move(context));
    return (ExternalPointer)vm;
}

// Releases a reference to a ScriptingVM. The VM will be destroyed when
// all references (including those held by ScriptedObjects) are released.
EXPORT void riveVMDestroy(ExternalPointer vmPtr)
{
    if (!vmPtr)
    {
        return;
    }
    static_cast<ScriptingVM*>((void*)vmPtr)->unref();
}

// Gets the lua_State* from a ScriptingVM (for operations that need it).
EXPORT lua_State* riveVMGetState(ExternalPointer vmPtr)
{
    if (!vmPtr)
    {
        return nullptr;
    }
    return static_cast<ScriptingVM*>((void*)vmPtr)->state();
}

// Gets console output from a ScriptingVM.
EXPORT RiveLuauBufferResponse riveVMConsole(ExternalPointer vmPtr)
{
    if (!vmPtr)
    {
        return {
#ifdef __EMSCRIPTEN__
            (WasmPtr) nullptr,
#else
            nullptr,
#endif
            0};
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);
    auto* context = static_cast<DartExposedScriptingContext*>(vm->context());
    auto memory = context->consoleMemory();
    return {
#ifdef __EMSCRIPTEN__
        (WasmPtr)memory.data(),
#else
        memory.data(),
#endif
        memory.size()};
}

// Clears console output from a ScriptingVM.
EXPORT void riveVMConsoleClear(ExternalPointer vmPtr)
{
    if (!vmPtr)
    {
        return;
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);
    auto* context = static_cast<DartExposedScriptingContext*>(vm->context());
    context->clearConsole();
}

// Calls a function in the ScriptingVM.
EXPORT void riveVMCall(ExternalPointer vmPtr, int nargs, int nresults)
{
    if (!vmPtr)
    {
        return;
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);
    try
    {
        lua_call(vm->state(), nargs, nresults);
    }
    catch (const std::exception& ex)
    {
        fprintf(stderr, "got lua exception %s\n", ex.what());
    }
}

// Registers a module in the ScriptingVM.
EXPORT bool riveVMRegisterModule(ExternalPointer vmPtr,
                                 const char* name,
                                 const char* data,
                                 size_t size)
{
    if (!vmPtr)
    {
        return false;
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);
    auto* context = static_cast<DartExposedScriptingContext*>(vm->context());
    context->startTimedExecution(vm->state());
    auto result =
        ScriptingVM::registerModule(vm->state(),
                                    name,
                                    Span<uint8_t>((uint8_t*)data, size));
    context->endTimedExecution(vm->state());
    return result;
}

// Unregisters a module from the ScriptingVM.
EXPORT void riveVMUnregisterModule(ExternalPointer vmPtr, const char* name)
{
    if (!vmPtr)
    {
        return;
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);
    ScriptingVM::unregisterModule(vm->state(), name);
}

// Adopts a ScriptingVM from ScriptingWorkspace, replacing its context with
// a DartExposedScriptingContext. The old context is properly cleaned up.
// On emscripten, glHandle is the WebGL context handle for this VM's renderer.
EXPORT void riveVMAdopt(ExternalPointer vmPtr,
                        ExternalPointer factory,
                        VoidCallback consoleHasDataCallback
#ifdef __EMSCRIPTEN__
                        ,
                        int glHandle
#endif
)
{
    if (!vmPtr)
    {
        return;
    }
    auto* vm = static_cast<ScriptingVM*>((void*)vmPtr);

    // Create a DartExposedScriptingContext with the factory and console
    // callback. replaceContext handles cleanup of old context and updates
    // lua thread data.
    auto newContext =
        std::make_unique<DartExposedScriptingContext>((Factory*)factory,
                                                      consoleHasDataCallback);

#ifdef WITH_RIVE_TOOLS
    // Transfer compiled WGSL→RSTB blobs, ore context, and render context from
    // the old context before it is destroyed by replaceContext. Without this,
    // loadShader() / context:gpuCanvas() would find an empty map and null
    // contexts in the new DartExposedScriptingContext.
    if (auto* oldCtx = vm->context())
    {
        auto rstbs = oldCtx->takeShaderRstbs();
        for (auto& kv : rstbs)
        {
            newContext->registerShaderRstb(kv.first, std::move(kv.second));
        }
        newContext->setRenderContext(oldCtx->renderContext());
    }
#endif
#ifdef __EMSCRIPTEN__
    newContext->setGLHandle(glHandle);
#endif

    vm->replaceContext(std::move(newContext));
}

#ifdef RIVE_CANVAS
// Return the ore::Context* stored on the Lua VM's ScriptingContext.
// Used by the JS pcall wrapper to look up which GL context to activate
// before executing Lua — the ore context IS the RenderTexture identity.
EXPORT ExternalPointer riveLuaGetVMOreCtxPtr(lua_State* L)
{
    auto* ctx = static_cast<rive::ScriptingContext*>(lua_getthreaddata(L));
    return ctx ? reinterpret_cast<ExternalPointer>(ctx->oreContext()) : 0;
}

#endif // RIVE_CANVAS

EXPORT void riveLuaCall(lua_State* state, int nargs, int nresults)
{
    try
    {
        lua_call(state, nargs, nresults);
    }
    catch (const std::exception& ex)
    {
        fprintf(stderr, "got lua exception %s\n", ex.what());
    }
}

EXPORT bool riveLuaRegisterModule(lua_State* state,
                                  const char* name,
                                  const char* data,
                                  size_t size)
{
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));
    context->startTimedExecution(state);
    auto result =
        ScriptingVM::registerModule(state,
                                    name,
                                    Span<uint8_t>((uint8_t*)data, size));
    context->endTimedExecution(state);
    return result;
}

EXPORT void riveLuaUnregisterModule(lua_State* state, const char* name)
{
    ScriptingVM::unregisterModule(state, name);
}

EXPORT void riveLuaCreateMetaTable(lua_State* state, const char* name)
{
    // create metatable for T
    luaL_newmetatable(state, name);
    lua_pop(state, 1);
}

EXPORT int riveLuaCreateViewModelInstance(lua_State* state,
                                          File* file,
                                          const char* viewModelName)
{
    if (file == nullptr)
    {
        return 0;
    }
    rcp<ViewModelInstance> vmi = file->createViewModelInstance(viewModelName);
    if (vmi)
    {

        lua_newrive<ScriptedViewModel>(state,
                                       state,
                                       ref_rcp(vmi->viewModel()),
                                       vmi);
        return 1;
    }
    return 0;
}

EXPORT int riveLuaCreateViewModelInstanceFromInstance(
    lua_State* state,
    File* file,
    const char* viewModelName,
    const char* viewModelInstanceName)
{
    if (file == nullptr)
    {
        return 0;
    }
    rcp<ViewModelInstance> vmi =
        file->createViewModelInstance(viewModelName, viewModelInstanceName);
    if (vmi)
    {

        lua_newrive<ScriptedViewModel>(state,
                                       state,
                                       ref_rcp(vmi->viewModel()),
                                       vmi);
        return 1;
    }
    return 0;
}

EXPORT bool riveLuaRegisterScript(lua_State* state,
                                  const char* name,
                                  const char* data,
                                  size_t size)
{
    return ScriptingVM::registerScript(state,
                                       name,
                                       Span<uint8_t>((uint8_t*)data, size));
}

EXPORT void riveStackDump(lua_State* state);
// Example C function to serve as an error handler
static int riveErrorHandler(lua_State* L)
{
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(L));
    context->printError(L);

    // lua_Debug ar;
    // lua_getinfo(L, 1, "sl", &ar);
    // // writer.write(ar.source);
    // // writer.writeVarUint((uint32_t)ar.currentline);
    // fprintf(stderr,
    //         "the source and line: %s %i\n",
    //         ar.source,
    //         (uint32_t)ar.currentline);
    // DartExposedScriptingContext* context =
    //     static_cast<DartExposedScriptingContext*>(lua_getthreaddata(L));
    // auto memory = context->consoleMemory();

    // Optionally, you can push a new value onto the stack to be returned by
    // lua_pcall For example, push a specific error code or a more detailed
    // message
    const char* error = lua_tostring(L, -1);
    lua_pushstring(L, error);
    return 1; // Number of return values
    // return 0;
}

EXPORT int riveLuaPCall(lua_State* state, int nargs, int nresults)
{
    auto* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));

#ifdef __EMSCRIPTEN__
    int vmGL = context->glHandle();
    int prevGL = emscripten_webgl_get_current_context();
    if (vmGL && vmGL != prevGL)
    {
        emscripten_webgl_make_context_current(vmGL);
    }

    // Auto-open a mini-frame if a Lua callback fires outside the normal render
    // boundary (e.g. a Coop stream event between endFrame and next beginFrame).
    // Without an open frame, ore resources are freed and GL IDs recycled by
    // the wrong context, causing "object does not belong to this context".
    bool autoFrameOpened = false;
    if (vmGL && !context->oreFrameOpen())
    {
        context->setOreFrameOpen(true);
        riveGPUBeginFrame(state);
        autoFrameOpened = true;
    }

    int result = context->pCall(state, nargs, nresults);

    if (autoFrameOpened)
    {
        riveGPUEndFrame(state);
        context->setOreFrameOpen(false);
        if (context->renderContext())
            riveInvalidateGLState((uintptr_t)context->renderContext());
    }
    if (vmGL && vmGL != prevGL)
        emscripten_webgl_make_context_current(prevGL);
    return result;
#else
    return context->pCall(state, nargs, nresults);
#endif
}

EXPORT void riveLuaPushArtboard(lua_State* state,
                                WrappedArtboard* wrappedArtboard,
                                DataContext* dataContext)
{
    if (state == nullptr || wrappedArtboard == nullptr)
    {
        return;
    }
    // Carry the wrapped artboard's bound view model to the new instance,
    // otherwise a host-bound default instance is silently replaced by a
    // blank auto-created one.
    rcp<ViewModelInstance> viewModelInstance;
    if (auto boundContext = wrappedArtboard->artboard()->dataContext())
    {
        viewModelInstance = boundContext->mainViewModelInstance();
    }
    // The pin keeps the host's file alive while the script holds the
    // artboard; the host may swap its own reference out underneath us.
    lua_newrive<ScriptedArtboard>(state,
                                  state,
                                  wrappedArtboard->file().get(),
                                  wrappedArtboard->artboard()->instance(),
                                  std::move(viewModelInstance),
                                  ref_rcp(dataContext)
#ifdef WITH_RIVE_TOOLS
                                      ,
                                  wrappedArtboard->file()
#endif
    );
}

EXPORT void riveLuaPushPath(lua_State* state,
                            Factory* factory,
                            RenderPath* renderPath)
{
    if (state == nullptr || renderPath == nullptr)
    {
        return;
    }
    const rive::RawPath& rawPath = renderPathToRawPath(factory, renderPath);
    lua_newrive<ScriptedPathData>(state, &rawPath);
}

EXPORT ScriptedRenderer* riveLuaPushRenderer(lua_State* state,
                                             Renderer* renderer)
{
    if (state == nullptr || renderer == nullptr)
    {
        return nullptr;
    }
    return lua_newrive<ScriptedRenderer>(state, renderer);
}

EXPORT ScriptedMat2D* riveLuaPushFullMatrix(lua_State* state,
                                            float x1,
                                            float x2,
                                            float y1,
                                            float y2,
                                            float tx,
                                            float ty)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    return lua_newrive<ScriptedMat2D>(state, x1, x2, y1, y2, tx, ty);
}

EXPORT ScriptedMat2D* riveLuaPushMatrix(lua_State* state)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    return lua_newrive<ScriptedMat2D>(state);
}

EXPORT void riveLuaPushMatrixX(ScriptedMat2D* scriptedMat,
                               float x1,
                               float x2,
                               float tx)
{
    if (scriptedMat == nullptr)
    {
        return;
    }
    scriptedMat->value.xx(x1);
    scriptedMat->value.xy(x2);
    scriptedMat->value.tx(tx);
}

EXPORT void riveLuaPushMatrixY(ScriptedMat2D* scriptedMat,
                               float y1,
                               float y2,
                               float ty)
{
    if (scriptedMat == nullptr)
    {
        return;
    }
    scriptedMat->value.yx(y1);
    scriptedMat->value.yy(y2);
    scriptedMat->value.ty(ty);
}

EXPORT ScriptedDataValue* riveLuaDataValue(lua_State* state, int index)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto scriptedDataValue = (ScriptedDataValue*)lua_touserdata(state, index);
    return scriptedDataValue;
}

EXPORT ScriptedPathData* riveLuaPath(lua_State* state, int index)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto scriptedPath = (ScriptedPathData*)lua_touserdata(state, index);
    return scriptedPath;
}

EXPORT RenderPath* riveLuaRenderPath(lua_State* state, ScriptedPathData* path)
{
    auto renderPath = path->renderPath(state);
    renderPath->ref();
    return renderPath;
}

EXPORT ScriptedDataValueNumber* riveLuaPushDataValueNumber(lua_State* state,
                                                           float value)
{
    if (state == nullptr)
    {
        return nullptr;
    }

    return lua_newrive<ScriptedDataValueNumber>(state, state, value);
}

EXPORT ScriptedDataValueString* riveLuaPushDataValueString(lua_State* state,
                                                           const char* value)
{
    if (state == nullptr)
    {
        return nullptr;
    }

    return lua_newrive<ScriptedDataValueString>(state, state, value);
}

EXPORT ScriptedDataValueBoolean* riveLuaPushDataValueBoolean(lua_State* state,
                                                             bool value)
{
    if (state == nullptr)
    {
        return nullptr;
    }

    return lua_newrive<ScriptedDataValueBoolean>(state, state, value);
}

EXPORT ScriptedDataValueColor* riveLuaPushDataValueColor(lua_State* state,
                                                         int value)

{
    if (state == nullptr)
    {
        return nullptr;
    }

    return lua_newrive<ScriptedDataValueColor>(state, state, value);
}

EXPORT ScriptedPointerEvent* riveLuaPushPointerEvent(lua_State* state,
                                                     uint8_t id,
                                                     float x,
                                                     float y)
{
    return lua_newrive<ScriptedPointerEvent>(state, id, Vec2D(x, y));
}

EXPORT ScriptedInvocation* riveLuaPushPointerListenerInvocation(
    lua_State* state,
    uint8_t id,
    float x,
    float y,
    float prevX,
    float prevY,
    int hitType,
    float timeStamp)
{
    auto p = ListenerInvocation::pointer(Vec2D(x, y),
                                         Vec2D(prevX, prevY),
                                         id,
                                         (ListenerType)(hitType),
                                         timeStamp);
    return lua_newrive<ScriptedInvocation>(state, p);
}

EXPORT ScriptedInvocation* riveLuaPushKeyboardListenerInvocation(
    lua_State* state,
    uint32_t key,
    uint8_t modifiers,
    uint8_t isPressed,
    uint8_t isRepeat)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto k = ListenerInvocation::keyboard(static_cast<Key>(key),
                                          static_cast<KeyModifiers>(modifiers),
                                          isPressed != 0,
                                          isRepeat != 0);
    return lua_newrive<ScriptedInvocation>(state, k);
}

/// Scripted node `keyboardEvent` callback (KeyboardInvocation userdata), not
/// listener ScriptedInvocation.
EXPORT ScriptedKeyboardInvocation* riveLuaPushScriptedKeyboardInvocation(
    lua_State* state,
    uint32_t key,
    uint8_t modifiers,
    uint8_t isPressed,
    uint8_t isRepeat)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    return lua_newrive<ScriptedKeyboardInvocation>(
        state,
        static_cast<Key>(key),
        static_cast<KeyModifiers>(modifiers),
        isPressed != 0,
        isRepeat != 0);
}

/// Scripted node `textEvent` callback (TextInputInvocation userdata).
EXPORT ScriptedTextInputInvocation* riveLuaPushScriptedTextInputInvocation(
    lua_State* state,
    const char* utf8Text)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    return lua_newrive<ScriptedTextInputInvocation>(
        state,
        std::string(utf8Text ? utf8Text : ""));
}

EXPORT ScriptedInvocation* riveLuaPushTextInputListenerInvocation(
    lua_State* state,
    const char* utf8Text)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto t = ListenerInvocation::textInput(utf8Text ? utf8Text : "");
    return lua_newrive<ScriptedInvocation>(state, std::move(t));
}

EXPORT ScriptedInvocation* riveLuaPushFocusListenerInvocation(lua_State* state,
                                                              uint8_t isFocus)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto f = ListenerInvocation::focus(nullptr, isFocus != 0);
    return lua_newrive<ScriptedInvocation>(state, f);
}

EXPORT ScriptedInvocation* riveLuaPushReportedEventListenerInvocation(
    lua_State* state,
    float delaySeconds)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto e = ListenerInvocation::reportedEvent(nullptr, delaySeconds);
    return lua_newrive<ScriptedInvocation>(state, e);
}

EXPORT ScriptedInvocation* riveLuaPushViewModelChangeListenerInvocation(
    lua_State* state)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto v = ListenerInvocation::viewModelChange(nullptr);
    return lua_newrive<ScriptedInvocation>(state, v);
}

EXPORT ScriptedInvocation* riveLuaPushNoneListenerInvocation(lua_State* state)
{
    if (state == nullptr)
    {
        return nullptr;
    }
    auto n = ListenerInvocation::none();
    return lua_newrive<ScriptedInvocation>(state, n);
}

/// Push the `ScriptedInvocation` userdata that backs a Luau listener action's
/// `performAction(self, listenerContext)` for gamepad events. [kind] selects
/// the underlying variant (0 = connected, 1 = event, 2 = disconnected) so
/// `isGamepad*` / `asGamepad*` on the Luau side report the right kind and the
/// event variant carries the per-change metadata + derived standard intent.
EXPORT ScriptedInvocation* riveLuaPushGamepadListenerInvocation(
    lua_State* state,
    uint8_t kind, // 0 = connected, 1 = event, 2 = disconnected
    int32_t deviceId,
    uint64_t buttonMask,
    const float* buttonValues,
    size_t buttonCount,
    const float* axes,
    size_t axisCount,
    uint8_t mapping,
    uint8_t changeKind, // 0 = button, 1 = axis (event-only)
    uint8_t changeIndex,
    float changeValue)
{
    if (state == nullptr)
    {
        return nullptr;
    }

    if (kind == 2)
    {
        auto d = ListenerInvocation::gamepadDisconnected(deviceId);
        return lua_newrive<ScriptedInvocation>(state, d);
    }

    GamepadSnapshot snapshot;
    snapshot.deviceId = deviceId;
    snapshot.buttonMask = buttonMask;
    if (buttonValues != nullptr && buttonCount > 0)
    {
        snapshot.buttonValues.assign(buttonValues, buttonValues + buttonCount);
    }
    if (axes != nullptr && axisCount > 0)
    {
        snapshot.axes.assign(axes, axes + axisCount);
    }
    snapshot.mapping = static_cast<GamepadMappingKind>(mapping);

    if (kind == 0)
    {
        auto c = ListenerInvocation::gamepadConnected(snapshot);
        return lua_newrive<ScriptedInvocation>(state, c);
    }

    // kind == 1 (event) — mirror fillStandardIntent in gamepad_batch.cpp.
    GamepadEventInvocation ev;
    ev.fullState = snapshot;
    ev.change.kind = changeKind == 0 ? GamepadInputChangeKind::button
                                     : GamepadInputChangeKind::axis;
    ev.change.index = changeIndex;
    ev.change.value = changeValue;
    ev.hasStandardButtonIntent = false;
    ev.hasStandardAxisIntent = false;
    if (snapshot.mapping == GamepadMappingKind::standard)
    {
        if (ev.change.kind == GamepadInputChangeKind::button)
        {
            if (ev.change.index <=
                static_cast<uint8_t>(StandardGamepadButton::start))
            {
                ev.hasStandardButtonIntent = true;
                ev.standardButton =
                    static_cast<StandardGamepadButton>(ev.change.index);
            }
        }
        else
        {
            if (ev.change.index <=
                static_cast<uint8_t>(StandardGamepadAxis::rightTrigger))
            {
                ev.hasStandardAxisIntent = true;
                ev.standardAxis =
                    static_cast<StandardGamepadAxis>(ev.change.index);
            }
        }
    }
    auto e = ListenerInvocation::gamepadEvent(std::move(ev));
    return lua_newrive<ScriptedInvocation>(state, e);
}

/// Push the Lua userdata expected by a `ScriptedDrawable`'s
/// `gamepadConnected` / `gamepadEvent` / `gamepadDisconnected` method.
/// Mirrors the userdata construction in
/// `runtime/src/scripted/scripted_drawable.cpp:108-120` and applies the
/// same `fillStandardIntent` rule as `gamepad_batch.cpp:26-54` for
/// event-kind dispatches.
EXPORT void* riveLuaPushScriptedGamepadInvocation(
    lua_State* state,
    uint8_t kind, // 0 = connected, 1 = event, 2 = disconnected
    int32_t deviceId,
    uint64_t buttonMask,
    const float* buttonValues,
    size_t buttonCount,
    const float* axes,
    size_t axisCount,
    uint8_t mapping,
    uint8_t changeKind, // 0 = button, 1 = axis (event-only)
    uint8_t changeIndex,
    float changeValue)
{
    if (state == nullptr)
    {
        return nullptr;
    }

    if (kind == 2)
    {
        return lua_newrive<ScriptedGamepadDisconnected>(state, deviceId);
    }

    GamepadSnapshot snapshot;
    snapshot.deviceId = deviceId;
    snapshot.buttonMask = buttonMask;
    if (buttonValues != nullptr && buttonCount > 0)
    {
        snapshot.buttonValues.assign(buttonValues, buttonValues + buttonCount);
    }
    if (axes != nullptr && axisCount > 0)
    {
        snapshot.axes.assign(axes, axes + axisCount);
    }
    snapshot.mapping = static_cast<GamepadMappingKind>(mapping);

    if (kind == 0)
    {
        return lua_newrive<ScriptedGamepadConnected>(state, snapshot);
    }

    // kind == 1 (event)
    GamepadEventInvocation ev;
    ev.fullState = snapshot;
    ev.change.kind = changeKind == 0 ? GamepadInputChangeKind::button
                                     : GamepadInputChangeKind::axis;
    ev.change.index = changeIndex;
    ev.change.value = changeValue;
    ev.hasStandardButtonIntent = false;
    ev.hasStandardAxisIntent = false;
    if (snapshot.mapping == GamepadMappingKind::standard)
    {
        if (ev.change.kind == GamepadInputChangeKind::button)
        {
            if (ev.change.index <=
                static_cast<uint8_t>(StandardGamepadButton::start))
            {
                ev.hasStandardButtonIntent = true;
                ev.standardButton =
                    static_cast<StandardGamepadButton>(ev.change.index);
            }
        }
        else
        {
            if (ev.change.index <=
                static_cast<uint8_t>(StandardGamepadAxis::rightTrigger))
            {
                ev.hasStandardAxisIntent = true;
                ev.standardAxis =
                    static_cast<StandardGamepadAxis>(ev.change.index);
            }
        }
    }
    return lua_newrive<ScriptedGamepadEvent>(state, ev);
}

EXPORT uint8_t riveLuaPointerEventHitResult(ScriptedPointerEvent* pointerEvent)
{
    if (pointerEvent == nullptr)
    {
        return 0;
    }
    return (uint8_t)pointerEvent->m_hitResult;
}

EXPORT const char* riveLuaScriptedDataValueType(
    ScriptedDataValue* scriptedDataValue)
{
    if (scriptedDataValue == nullptr)
    {
        return toCString("");
    }
    if (scriptedDataValue->isNumber())
    {
        return toCString("DataValueNumber");
    }
    if (scriptedDataValue->isString())
    {
        return toCString("DataValueString");
    }
    if (scriptedDataValue->isBoolean())
    {
        return toCString("DataValueBoolean");
    }
    if (scriptedDataValue->isColor())
    {
        return toCString("DataValueColor");
    }
    return toCString("");
}

EXPORT const float riveLuaScriptedDataValueNumberValue(
    ScriptedDataValue* scriptedDataValue)
{
    if (scriptedDataValue != nullptr &&
        scriptedDataValue->dataValue() != nullptr &&
        scriptedDataValue->dataValue()->is<DataValueNumber>())
    {
        return scriptedDataValue->dataValue()->as<DataValueNumber>()->value();
    }
    return 0;
}

EXPORT const char* riveLuaScriptedDataValueStringValue(
    ScriptedDataValue* scriptedDataValue)
{
    if (scriptedDataValue != nullptr &&
        scriptedDataValue->dataValue() != nullptr &&
        scriptedDataValue->dataValue()->is<DataValueString>())
    {
        return toCString(
            scriptedDataValue->dataValue()->as<DataValueString>()->value());
    }
    return toCString("");
}

EXPORT bool riveLuaScriptedDataValueBooleanValue(
    ScriptedDataValue* scriptedDataValue)
{
    if (scriptedDataValue != nullptr &&
        scriptedDataValue->dataValue() != nullptr &&
        scriptedDataValue->dataValue()->is<DataValueBoolean>())
    {
        return scriptedDataValue->dataValue()->as<DataValueBoolean>()->value();
    }
    return false;
}

EXPORT int riveLuaScriptedDataValueColorValue(
    ScriptedDataValue* scriptedDataValue)
{
    if (scriptedDataValue != nullptr &&
        scriptedDataValue->dataValue() != nullptr &&
        scriptedDataValue->dataValue()->is<DataValueColor>())
    {
        return scriptedDataValue->dataValue()->as<DataValueColor>()->value();
    }
    return false;
}

EXPORT void riveLuaPushViewModelInstanceValue(
    lua_State* state,
    ViewModelInstanceValue* viewModelInstanceValue)
{
    if (state == nullptr || viewModelInstanceValue == nullptr)
    {
        return;
    }
    switch (viewModelInstanceValue->coreType())
    {
        case ViewModelInstanceViewModelBase::typeKey:
        {
            auto vm = viewModelInstanceValue->as<ViewModelInstanceViewModel>();
            auto vmi = vm->referenceViewModelInstance();
            if (vmi == nullptr)
            {
                fprintf(stderr,
                        "riveLuaPushViewModelInstanceValue - passed in a "
                        "ViewModelInstanceViewModel with no associated "
                        "ViewModelInstance.\n");
                return;
            }

            lua_newrive<ScriptedViewModel>(state,
                                           state,
                                           ref_rcp(vmi->viewModel()),
                                           vmi);
            break;
        }
        default:
            fprintf(stderr,
                    "riveLuaPushViewModelInstanceValue - passed in an "
                    "unhandled ViewModelInstanceValue type: %i\n",
                    viewModelInstanceValue->coreType());
            break;
    }
    // lua_newrive<ScriptedRenderer>(state, renderer);
}

EXPORT void riveLuaScriptedRendererEnd(ScriptedRenderer* renderer)
{
    if (renderer == nullptr)
    {
        return;
    }
    renderer->end();
}

EXPORT void riveStackDump(lua_State* state)
{
    int i;
    int top = lua_gettop(state);
    for (i = 1; i <= top; i++)
    { /* repeat for each level */
        int t = lua_type(state, i);
        switch (t)
        {

            case LUA_TSTRING: /* strings */
                fprintf(stderr,
                        "  (%i)[STRING] %s\n",
                        i,
                        lua_tostring(state, i));
                break;

            case LUA_TBOOLEAN: /* booleans */
                fprintf(stderr,
                        "  (%i)[BOOLEAN] %s\n",
                        i,
                        lua_toboolean(state, i) ? "true" : "false");
                break;

            case LUA_TNUMBER: /* numbers */
                fprintf(stderr,
                        "  (%i)[NUMBER] %g\n",
                        i,
                        lua_tonumber(state, i));
                break;

            default: /* other values */
                fprintf(stderr, "  (%i)[%s]\n", i, lua_typename(state, t));
                break;
        }
    }
    fprintf(stderr, "\n"); /* end the listing */
}

EXPORT void clearScriptingVM(File* file)
{
    if (file == nullptr)
    {
        return;
    }
    file->clearScriptingVM();
}

EXPORT int riveLuaPushDataContext(lua_State* state, DataContext* dataContext)
{
    if (state == nullptr || dataContext == nullptr)
    {
        return 0;
    }
    lua_newrive<ScriptedDataContext>(state, state, ref_rcp(dataContext));
    return 1;
}

EXPORT int riveLuaPushDataContextViewModel(lua_State* state,
                                           DataContext* dataContext)
{
    if (state == nullptr || dataContext == nullptr)
    {
        return 0;
    }
    auto viewModelInstance = dataContext->mainViewModelInstance();
    if (viewModelInstance == nullptr)
    {
        return 0;
    }
    lua_newrive<ScriptedViewModel>(state,
                                   state,
                                   ref_rcp(viewModelInstance->viewModel()),
                                   viewModelInstance);
    return 1;
}

EXPORT void riveLuaPushBlob(lua_State* state,
                            const char* name,
                            const uint8_t* data,
                            size_t size)
{
    if (state == nullptr)
    {
        return;
    }
    lua_push_blob(state, name, data, size);
}

// Poll for completed async tasks (image decodes, etc.) and invoke callbacks.
// maxCallbacks of 0 defaults to 256 as a safety cap. Returns number processed.
EXPORT uint32_t riveLuaPollAsyncWork(lua_State* state, uint32_t maxCallbacks)
{
    if (state == nullptr)
    {
        return 0;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context == nullptr)
    {
        return 0;
    }
    WorkPool* wp = context->workPool();
    if (wp == nullptr)
    {
        return 0;
    }
    return wp->pollCompletedWork(maxCallbacks == 0 ? 256 : maxCallbacks);
}

// Check if there are any pending async tasks.
EXPORT bool riveLuaHasPendingAsyncWork(lua_State* state)
{
    if (state == nullptr)
    {
        return false;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context == nullptr)
    {
        return false;
    }
    WorkPool* wp = context->workPool();
    if (wp == nullptr)
    {
        return false;
    }
    return wp->hasPendingWork();
}

// C++ linkage — defined in lua_image_decode.cpp outside any namespace.
extern int context_decodeImage_impl(lua_State* L);

// Forwards to context_decodeImage_impl which reads the buffer from Lua stack
// position 2 and returns a Promise. Called from the Dart-side context table.
EXPORT int riveLuaDecodeImage(lua_State* state)
{
    if (state == nullptr)
    {
        return 0;
    }
    return context_decodeImage_impl(state);
}

// Look up a shader by name from the per-VM ScriptingContext (editor path) or
// file assets (runtime path) and push the resulting ScriptedShader onto the
// Lua stack. Returns 1 on success, 0 if not found or compile failed.
EXPORT int riveLuaPushShader(lua_State* state, const char* name)
{
#if defined(RIVE_CANVAS) && defined(RIVE_ORE)
    if (state == nullptr || name == nullptr)
    {
        return 0;
    }
    return lua_gpu_push_shader_by_name(state, name);
#else
    return 0;
#endif
}

// Push a GPU features table onto the Lua stack. Proxies through to the same
// implementation used by context_namecall's features case.
EXPORT int riveLuaPushGPUFeatures(lua_State* state)
{
    if (state == nullptr)
    {
        return 0;
    }
    return lua_push_gpu_features(state);
}

// On WASM we need wrappers around riveGPUBeginFrame / riveGPUEndFrame that add
// WebGL context switching.  On native, those functions (in
// rive_luau_binding_gpu.cpp) are EXPORT'd and Dart FFI looks them up directly.
#ifdef __EMSCRIPTEN__
EXPORT void riveGPUBeginFrameExport(lua_State* L)
{
    auto* ctx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    int vmGL = ctx->glHandle();
    if (vmGL)
    {
        int prevGL = emscripten_webgl_get_current_context();
        ctx->setPrevGLContext(prevGL);
        if (vmGL != prevGL)
            emscripten_webgl_make_context_current(vmGL);
        ctx->setOreFrameOpen(true);
    }
    riveGPUBeginFrame(L);
}

EXPORT void riveGPUEndFrameExport(lua_State* L)
{
    auto* ctx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    int vmGL = ctx->glHandle();
    if (vmGL)
    {
        int currentGL = emscripten_webgl_get_current_context();
        if (vmGL != currentGL)
            emscripten_webgl_make_context_current(vmGL);
    }
    riveGPUEndFrame(L);
    if (vmGL)
    {
        ctx->setOreFrameOpen(false);
        if (ctx->renderContext())
            riveInvalidateGLState((uintptr_t)ctx->renderContext());
        int prevGL = (int)ctx->prevGLContext();
        if (prevGL && prevGL != vmGL)
            emscripten_webgl_make_context_current(prevGL);
    }
}
#endif

#ifdef WITH_RIVE_AUDIO

// Push an AudioSource onto the Lua stack as a ScriptedAudioSource userdata.
// Returns 1 if successful, 0 if the image is null.
#ifndef __EMSCRIPTEN__
EXPORT int riveLuaPushAudioSource(lua_State* state, AudioSource* audioSource)
#else
EXPORT int riveLuaPushAudioSource(WasmPtr state, WasmPtr audioSource)
#endif
{
#ifdef __EMSCRIPTEN__
    lua_State* L = (lua_State*)state;
    AudioSource* audio = (AudioSource*)audioSource;
#else
    lua_State* L = state;
    AudioSource* audio = audioSource;
#endif
    if (L == nullptr || audio == nullptr)
    {
        return 0;
    }
    auto scriptedAudioSource = lua_newrive<ScriptedAudioSource>(L);
    scriptedAudioSource->source(ref_rcp(audio));
    return 1;
}
#endif

EXPORT void riveLuaEnableDrawCanvasPhase(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    auto* context = static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context)
    {

        context->setCanvasDrawingPhase(true);
    }
}

EXPORT void riveLuaDisableDrawCanvasPhase(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    auto* context = static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context)
    {

        context->setCanvasDrawingPhase(false);
    }
}

EXPORT void riveLuaAdvanceDetachedViewModels(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    auto* context = static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context)
    {
        context->advanceDetachedViewModels();
    }
}

EXPORT void riveLuaSetExecutionTimeout(lua_State* state, int timeoutMs)
{
    if (state == nullptr)
    {
        return;
    }
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));
    context->timeoutMs = timeoutMs;
}

EXPORT int riveLuaGetExecutionTimeout(lua_State* state)
{
    if (state == nullptr)
    {
        return 50;
    }
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(state));
    return context->timeoutMs;
}

// Editor-only: Store generator ref in context for direct ScriptedObject
// reinitialization without genRuntimeFile.
EXPORT void riveLuaSetGeneratorRef(lua_State* state, uint32_t assetId, int ref)
{
    if (state == nullptr)
    {
        return;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context != nullptr)
    {
        context->setGeneratorRef(assetId, ref);
    }
}

EXPORT int riveLuaGetGeneratorRef(lua_State* state, uint32_t assetId)
{
    if (state == nullptr)
    {
        return 0;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context == nullptr)
    {
        return 0;
    }
    return context->getGeneratorRef(assetId);
}

EXPORT void riveLuaClearGeneratorRefs(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context != nullptr)
    {
        context->clearGeneratorRefs();
    }
}

#ifdef WITH_RIVE_TOOLS
EXPORT void riveLuaStopPlayback(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context)
    {
        context->isPlaying(false);
        context->disposeOrphanScriptedProperties();
    }
}

EXPORT void riveLuaStartPlayback(lua_State* state)
{
    if (state == nullptr)
    {
        return;
    }
    ScriptingContext* context =
        static_cast<ScriptingContext*>(lua_getthreaddata(state));
    if (context)
    {
        context->isPlaying(true);
    }
}
#endif

// Update a File's scripting state to point to a ScriptingVM.
// The VM's refcount is incremented, so the caller should call riveVMDestroy
// when they no longer need their reference.
#ifndef __EMSCRIPTEN__
EXPORT void riveFileSetScriptingVM(File* file, ScriptingVM* vm)
#else
EXPORT void riveFileSetScriptingVM(WasmPtr filePtr, WasmPtr vmPtr)
#endif
{
#ifdef __EMSCRIPTEN__
    File* file = (File*)filePtr;
    ScriptingVM* vm = (ScriptingVM*)vmPtr;
#endif
    if (file == nullptr)
    {
        return;
    }
    file->setScriptingVM(ref_rcp(vm));
}

// Push a RenderImage onto the Lua stack as a ScriptedImage userdata.
// Returns 1 if successful, 0 if the image is null.
#ifndef __EMSCRIPTEN__
EXPORT int riveLuaPushImage(lua_State* state, RenderImage* renderImage)
#else
EXPORT int riveLuaPushImage(WasmPtr state, WasmPtr renderImage)
#endif
{
#ifdef __EMSCRIPTEN__
    lua_State* L = (lua_State*)state;
    RenderImage* img = (RenderImage*)renderImage;
#else
    lua_State* L = state;
    RenderImage* img = renderImage;
#endif

    if (L == nullptr || img == nullptr)
    {
        return 0;
    }

    auto scriptedImage = ScriptedImage::luaNew(L);
    // ref_rcp increments ref count, rcp<> destructor will decrement when
    // ScriptedImage is GC'd
    scriptedImage->image = ref_rcp(img);
    return 1;
}

#ifndef __EMSCRIPTEN__
EXPORT int riveLuaPushFont(lua_State* state, rive::Font* font)
#else
EXPORT int riveLuaPushFont(WasmPtr state, WasmPtr font)
#endif
{
#ifdef __EMSCRIPTEN__
    lua_State* L = (lua_State*)state;
    rive::Font* f = (rive::Font*)font;
#else
    lua_State* L = state;
    rive::Font* f = font;
#endif

    if (L == nullptr || f == nullptr)
    {
        return 0;
    }

    auto scriptedFont = lua_newrive<ScriptedFont>(L);
    scriptedFont->font = ref_rcp(f);
    return 1;
}

#ifdef __EMSCRIPTEN__

static int lua_callback(lua_State* L)
{
    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(L));
    unsigned functionIndex = lua_tounsignedx(L, lua_upvalueindex(1), nullptr);
    emscripten::val result =
        context->closures[functionIndex]((WasmPtr)L, functionIndex);
    return result.as<int>();
}

EXPORT void riveLuaPushClosure(WasmPtr state,
                               emscripten::val fn,
                               WasmPtr debugname)
{
    lua_State* L = (lua_State*)state;
    const char* name = (const char*)debugname;

    if (L == nullptr)
    {
        return;
    }

    DartExposedScriptingContext* context =
        static_cast<DartExposedScriptingContext*>(lua_getthreaddata(L));

    int upvalue = (int)context->closures.size();
    context->closures.push_back(fn);

    lua_pushinteger(L, upvalue);
    lua_pushcclosurek(L, lua_callback, name, 1, nullptr);
}

EMSCRIPTEN_BINDINGS(RiveLuauBinding)
{
    function("riveLuaPushClosure", &riveLuaPushClosure);

    value_array<RiveLuauBufferResponse>("RiveLuauBufferResponse")
        .element(&RiveLuauBufferResponse::data)
        .element(&RiveLuauBufferResponse::size);

    function("riveLuaConsole",
             optional_override([](WasmPtr state) -> RiveLuauBufferResponse {
                 return riveLuaConsole((lua_State*)state);
             }));
    function("riveLuaPushImage", &riveLuaPushImage);
    function("riveLuaPushFont", &riveLuaPushFont);

    // VM lifecycle functions - must be in EMSCRIPTEN_BINDINGS because they take
    // emscripten::val callbacks
    function("riveVMCreate",
             optional_override(
                 [](WasmPtr factory,
                    emscripten::val consoleHasDataCallback) -> WasmPtr {
                     return (WasmPtr)riveVMCreate((ExternalPointer)factory,
                                                  consoleHasDataCallback);
                 }));
    function("riveVMDestroy", optional_override([](WasmPtr vmPtr) -> void {
                 riveVMDestroy((ExternalPointer)vmPtr);
             }));
    function("riveVMGetState", optional_override([](WasmPtr vmPtr) -> WasmPtr {
                 return (WasmPtr)riveVMGetState((ExternalPointer)vmPtr);
             }));
    function("riveVMAdopt",
             optional_override([](WasmPtr vmPtr,
                                  WasmPtr factory,
                                  emscripten::val consoleHasDataCallback,
                                  int glHandle) -> void {
                 riveVMAdopt((ExternalPointer)vmPtr,
                             (ExternalPointer)factory,
                             consoleHasDataCallback,
                             glHandle);
             }));
}
#endif