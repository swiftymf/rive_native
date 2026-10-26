// GPU-canvas and frame-boundary exports for Dart FFI.
#ifdef RIVE_CANVAS
#include "rive_native/external.hpp"
#include "rive/lua/rive_lua_libs.hpp"
#include "rive/renderer/render_context.hpp"
#include "rive/renderer/render_canvas.hpp"
#ifdef RIVE_ORE
#include "rive/renderer/ore/ore_context.hpp"
#include "rive/renderer/render_context_impl.hpp"
#include <memory>
#endif

using namespace rive;

#ifdef RIVE_ORE
static std::unique_ptr<rive::ore::Context> g_ownedOreContext;
// RenderContext identity the cached ore::Context was minted for. Re-mint when
// the RenderContext changes (plugin teardown / hot restart) to avoid handing
// out a stale ore::Context whose GPU/queue is gone.
static void* g_ownedOreContextForRC = nullptr;

EXPORT void* riveInitGPUScripting(void* renderContextPtr)
{
    if (g_ownedOreContext && g_ownedOreContextForRC == renderContextPtr)
        return g_ownedOreContext.get();
    g_ownedOreContext.reset();
    g_ownedOreContextForRC = nullptr;
    auto* rc = static_cast<rive::gpu::RenderContext*>(renderContextPtr);
    if (rc == nullptr || rc->impl() == nullptr)
        return nullptr;
    g_ownedOreContext = rc->impl()->makeOreContext();
    if (g_ownedOreContext)
        g_ownedOreContextForRC = renderContextPtr;
    return g_ownedOreContext.get();
}

EXPORT void riveShutdownGPUScripting()
{
    g_ownedOreContext.reset();
    g_ownedOreContextForRC = nullptr;
}
#endif

// ---------------------------------------------------------------------------
// riveLuaPushCanvas — create a 2D Canvas, push onto Lua stack.
// ---------------------------------------------------------------------------
EXPORT int riveLuaPushCanvas(lua_State* L, uint32_t width, uint32_t height)
{
    auto* scriptingCtx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    auto* renderCtx =
        static_cast<gpu::RenderContext*>(scriptingCtx->renderContext());
    if (renderCtx == nullptr)
    {
        lua_pushnil(L);
        return 1;
    }

    auto* handle = lua_newrive<ScriptedCanvas>(L);
    handle->m_L = L;
    handle->renderCtx = renderCtx;

    if (width == 0 || height == 0)
    {
        return 1;
    }

    auto canvas = renderCtx->makeRenderCanvas(width, height);
    if (!canvas)
    {
        lua_pop(L, 1);
        lua_pushnil(L);
        return 1;
    }
    handle->canvas = std::move(canvas);
    // Create a ScriptedImage backed by canvas->renderImage() so
    // the script can composite it with renderer:drawImage()
    auto* img = lua_newrive<ScriptedImage>(L);
    img->image =
        ref_rcp(static_cast<RenderImage*>(handle->canvas->renderImage()));
    handle->m_imageRef = lua_ref(L, -1);
    lua_pop(L, 1); // pop image, handle remains on top
    return 1;
}

// ---------------------------------------------------------------------------
// riveLuaPushGPUCanvas — create a GPUCanvas, push onto Lua stack.
// ---------------------------------------------------------------------------
EXPORT int riveLuaPushGPUCanvas(lua_State* L, uint32_t width, uint32_t height)
{
#ifdef RIVE_ORE
    auto* scriptingCtx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    auto* renderCtx =
        static_cast<gpu::RenderContext*>(scriptingCtx->renderContext());
    auto* oreCtx = static_cast<ore::Context*>(scriptingCtx->oreContext());
    if (renderCtx == nullptr || oreCtx == nullptr)
    {
        lua_pushnil(L);
        return 1;
    }

    auto* handle = lua_newrive<ScriptedGPUCanvas>(L);
    handle->m_L = L;
    handle->renderCtx = renderCtx;

    if (width == 0 || height == 0)
    {
        return 1;
    }

    auto canvas = renderCtx->makeRenderCanvas(width, height);
    if (!canvas)
    {
        lua_pop(L, 1);
        lua_pushnil(L);
        return 1;
    }
    auto colorView = oreCtx->wrapCanvasTexture(canvas.get());
    if (!colorView)
    {
        lua_pop(L, 1);
        lua_pushnil(L);
        return 1;
    }
    handle->canvas = std::move(canvas);
    handle->oreColorView = std::move(colorView);

    auto* img = lua_newrive<ScriptedImage>(L);
    img->image =
        ref_rcp(static_cast<RenderImage*>(handle->canvas->renderImage()));
    handle->m_imageRef = lua_ref(L, -1);
    lua_pop(L, 1); // pop image; handle remains on top
    return 1;
#else
    (void)width;
    (void)height;
    lua_pushnil(L);
    return 1;
#endif
}

// ---------------------------------------------------------------------------
// riveGPUBeginFrame / riveGPUEndFrame — frame boundaries for GPU scripting.
// ---------------------------------------------------------------------------
EXPORT void riveGPUBeginFrame(lua_State* L)
{
#ifdef RIVE_ORE
    auto* scriptingCtx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    auto* ctx = static_cast<ore::Context*>(scriptingCtx->oreContext());

    if (ctx)
    {
        ctx->beginFrame({});
    }
#endif
}

EXPORT void riveGPUEndFrame(lua_State* L)
{
#ifdef RIVE_ORE
    auto* scriptingCtx = static_cast<ScriptingContext*>(lua_getthreaddata(L));
    auto* ctx = static_cast<ore::Context*>(scriptingCtx->oreContext());
    if (!ctx)
        return;

    // Safety net: auto-finish any render pass the Lua script left open.
    if (ctx->activeRenderPass() && !ctx->activeRenderPass()->isFinished())
    {
        ctx->activeRenderPass()->finish();
        ctx->setActiveRenderPass(nullptr);
    }

    ctx->endFrame();
#endif
}
#endif // RIVE_CANVAS
