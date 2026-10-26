#include "rive_native/rive_binding.hpp"
#include "rive_native/external.hpp"
#include <stdio.h>
#include <chrono>
#include "rive/advance_flags.hpp"
#include "rive/artboard.hpp"
#include "rive/transform_component.hpp"
#include "rive/animation/listener_invocation.hpp"
#include "rive/animation/state_machine_instance.hpp"
#include "rive/animation/state_machine_input_instance.hpp"
#include "rive/input/gamepad_snapshot.hpp"
#include "rive/input/standard_gamepad.hpp"
#include "rive/animation/layer_state.hpp"
#include "rive/animation/animation_state.hpp"
#include "rive/animation/entry_state.hpp"
#include "rive/animation/exit_state.hpp"
#include "rive/animation/any_state.hpp"
#include "rive/animation/blend_state.hpp"
#include "rive/animation/blend_state_1d.hpp"
#include "rive/animation/blend_state_direct.hpp"
#include "rive/animation/linear_animation.hpp"
#include "rive/animation/linear_animation_instance.hpp"
#include "rive/data_bind/data_bind.hpp"
#include "rive/viewmodel/viewmodel_instance.hpp"
#include "rive/viewmodel/viewmodel_instance_artboard.hpp"
#include "rive/viewmodel/viewmodel_instance_number.hpp"
#include "rive/viewmodel/viewmodel_instance_boolean.hpp"
#include "rive/viewmodel/viewmodel_instance_color.hpp"
#include "rive/viewmodel/viewmodel_instance_enum.hpp"
#include "rive/viewmodel/viewmodel_instance_list.hpp"
#include "rive/viewmodel/viewmodel_instance_string.hpp"
#include "rive/viewmodel/viewmodel_instance_trigger.hpp"
#include "rive/viewmodel/viewmodel_instance_symbol_list_index.hpp"
#include "rive/viewmodel/viewmodel_instance_asset_image.hpp"
#include "rive/viewmodel/viewmodel_instance_asset_font.hpp"
#include "rive/viewmodel/viewmodel_property_enum.hpp"
#include "rive/viewmodel/viewmodel_property_enum_custom.hpp"
#include "rive/math/transform_components.hpp"
#include "rive/node.hpp"
#include "rive/constraints/constraint.hpp"
#include "rive/bones/root_bone.hpp"
#include "rive/nested_artboard.hpp"
#include "rive/animation/nested_state_machine.hpp"
#include "rive/animation/state_machine_bool.hpp"
#include "rive/animation/state_machine_number.hpp"
#include "rive/animation/state_machine_trigger.hpp"
#include "rive/animation/cubic_ease_interpolator.hpp"
#include "rive/animation/cubic_value_interpolator.hpp"
#include "rive/animation/elastic_interpolator.hpp"
#include "rive/animation/keyframe_interpolator.hpp"
#include "rive/assets/file_asset.hpp"
#include "rive/assets/image_asset.hpp"
#include "rive/assets/font_asset.hpp"
#include "rive/assets/audio_asset.hpp"
#include "rive/text/text_value_run.hpp"
#include "rive/text/raw_text.hpp"
#include "rive/text/raw_text_input.hpp"
#include "rive/open_url_event.hpp"
#include "rive/audio_event.hpp"
#include "rive/custom_property.hpp"
#include "rive/custom_property_boolean.hpp"
#include "rive/custom_property_number.hpp"
#include "rive/custom_property_string.hpp"
#include "rive/custom_property.hpp"
#include "rive/layout/layout_data.hpp"
#include "rive/viewmodel/runtime/viewmodel_runtime.hpp"
#include "rive/core/vector_binary_writer.hpp"
#ifdef WITH_RIVE_SCRIPTING
#include "rive/lua/scripting_vm.hpp"
#endif
#ifdef RIVE_MICROPROFILE
#include "rive/profiler/rive_profile.hpp"
#include "rive/core/vector_binary_writer.hpp"

static std::vector<uint8_t> g_profileBuffer;

// Event buffer for state transition records (written by RiveProfile callback,
// merged into g_profileBuffer during flush).
static std::mutex g_eventBufferMutex;
static std::vector<uint8_t> g_eventBuffer;

static void writeUint64(rive::VectorBinaryWriter& writer, uint64_t value)
{
    writer.write(reinterpret_cast<const uint8_t*>(&value), sizeof(value));
}
static void writeInt64(rive::VectorBinaryWriter& writer, int64_t value)
{
    writer.write(reinterpret_cast<const uint8_t*>(&value), sizeof(value));
}
#endif
#include <map>
#include <memory>
#include "rive/focus_data.hpp"
#include "rive/input/focusable.hpp"
#include "rive/input/focus_manager.hpp"
#include "rive/math/aabb.hpp"
#include "rive/semantic/semantic_manager.hpp"
#include "rive/semantic/semantic_snapshot.hpp"
#include "rive/file.hpp"
#include <limits>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

using namespace rive;

std::mutex g_deleteMutex;

#if defined(__EMSCRIPTEN__) && defined(WITH_RIVE_TOOLS)
#include <emscripten/val.h>
// Forward declarations for WASM callback cleanup
extern std::unordered_map<rive::FocusManager*, emscripten::val>
    g_focusChangedCallbacksWasm;
extern std::unordered_map<rive::FocusManager*, emscripten::val>
    g_scrollIntoViewCallbacksWasm;
#endif

#ifdef WITH_RIVE_TOOLS
class ViewModelInstanceRegistrarImpl : public ViewModelInstanceRegistrar
{
public:
    void registerInstance(ViewModelInstance* ptr,
                          rcp<ViewModelInstance> ref) override
    {
        if (ptr != nullptr)
        {
            m_map[ptr] = std::move(ref);
        }
    }
    bool contains(ViewModelInstance* ptr) const override
    {
        return ptr != nullptr && m_map.find(ptr) != m_map.end();
    }
    void clear() override { m_map.clear(); }

private:
    std::unordered_map<ViewModelInstance*, rcp<ViewModelInstance>> m_map;
};

struct FileViewModelContext
{
    ViewModelInstanceRegistrarImpl registrar;
};

static std::unordered_map<File*, std::unique_ptr<FileViewModelContext>>
    g_fileViewModelContexts;
#endif

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <emscripten/html5.h>
using namespace emscripten;

static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webLayoutChangedCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webLayoutDirtyCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webTransformDirtyCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val> _webEventCallbacks;
static std::unordered_map<StateMachineInstance*, emscripten::val>
    _webInputChangedCallbacks;
static std::unordered_map<StateMachineInstance*, emscripten::val>
    _webDataBindChangedCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webTestBoundsCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webIsAncestorCallbacks;
static std::unordered_map<WrappedArtboard*, emscripten::val>
    _webRootTransformCallbacks;
#endif

#if defined(__EMSCRIPTEN__)

emscripten::val g_viewModelUpdateNumber = val::null();
emscripten::val g_viewModelUpdateBoolean = val::null();
emscripten::val g_viewModelUpdateColor = val::null();
emscripten::val g_viewModelUpdateString = val::null();
emscripten::val g_viewModelUpdateTrigger = val::null();
emscripten::val g_viewModelUpdateEnum = val::null();
emscripten::val g_viewModelUpdateSymbolListIndex = val::null();
emscripten::val g_viewModelUpdateAsset = val::null();
emscripten::val g_viewModelUpdateArtboard = val::null();
emscripten::val g_viewModelUpdateList = val::null();
emscripten::val g_viewModelUpdateViewModel = val::null();
emscripten::val g_viewModelInstanceSerialized = val::null();
using ViewModelUpdateNumber = emscripten::val;
using ViewModelUpdateBoolean = emscripten::val;
using ViewModelUpdateColor = emscripten::val;
using ViewModelUpdateString = emscripten::val;
using ViewModelUpdateTrigger = emscripten::val;
using ViewModelUpdateEnum = emscripten::val;
using ViewModelUpdateSymbolListIndex = emscripten::val;
using ViewModelUpdateAsset = emscripten::val;
using ViewModelUpdateArtboard = emscripten::val;
using ViewModelUpdateList = emscripten::val;
using ViewModelUpdateViewModel = emscripten::val;
using ViewModelInstanceSerialized = emscripten::val;
#else
typedef void (*ViewModelUpdateNumber)(uint64_t pointer, float value);
typedef void (*ViewModelUpdateBoolean)(uint64_t pointer, bool value);
typedef void (*ViewModelUpdateColor)(uint64_t pointer, int value);
typedef void (*ViewModelUpdateString)(uint64_t pointer, const char* value);
typedef void (*ViewModelUpdateTrigger)(uint64_t pointer, uint32_t value);
typedef void (*ViewModelUpdateEnum)(uint64_t pointer, uint32_t value);
typedef void (*ViewModelUpdateSymbolListIndex)(uint64_t pointer,
                                               uint32_t value);
typedef void (*ViewModelUpdateAsset)(uint64_t pointer, uint32_t value);
typedef void (*ViewModelUpdateArtboard)(uint64_t pointer, uint32_t value);
typedef void (*ViewModelUpdateList)(uint64_t pointer);
typedef void (*ViewModelUpdateViewModel)(uint64_t pointer);
typedef void (*ViewModelInstanceSerialized)(uint64_t pointer,
                                            const uint8_t* data,
                                            size_t size);
ViewModelUpdateNumber g_viewModelUpdateNumber = nullptr;
ViewModelUpdateBoolean g_viewModelUpdateBoolean = nullptr;
ViewModelUpdateColor g_viewModelUpdateColor = nullptr;
ViewModelUpdateString g_viewModelUpdateString = nullptr;
ViewModelUpdateTrigger g_viewModelUpdateTrigger = nullptr;
ViewModelUpdateEnum g_viewModelUpdateEnum = nullptr;
ViewModelUpdateSymbolListIndex g_viewModelUpdateSymbolListIndex = nullptr;
ViewModelUpdateAsset g_viewModelUpdateAsset = nullptr;
ViewModelUpdateArtboard g_viewModelUpdateArtboard = nullptr;
ViewModelUpdateList g_viewModelUpdateList = nullptr;
ViewModelInstanceSerialized g_viewModelInstanceSerialized = nullptr;
ViewModelUpdateViewModel g_viewModelUpdateViewModel = nullptr;
#endif

using namespace rive;

typedef bool (*AssetLoaderCallback)(FileAsset* asset,
                                    const uint8_t* bytes,
                                    const size_t size);

#ifndef WITH_RIVE_TOOLS
// Runtime builds compile without WITH_RIVE_TOOLS, but we still export
// callback setter symbols that use these types in their signatures.
typedef void (*ArtboardCallback)(void* artboardPtr);
typedef uint8_t (*TestBoundsCallback)(void* artboardPtr,
                                      float x,
                                      float y,
                                      bool skip);
typedef uint8_t (*IsAncestorCallback)(void* artboardPtr, uint16_t artboardId);
typedef float (*RootTransformCallback)(void* artboardPtr,
                                       float x,
                                       float y,
                                       bool xAxis);
typedef void (*InputChanged)(StateMachineInstance* stateMachine,
                             uint64_t index);
typedef void (*DataBindChanged)();
#endif

#ifdef DEBUG
uint32_t g_artboardCount = 0;
uint32_t g_stateMachineCount = 0;
uint32_t g_animationCount = 0;
uint32_t g_viewModelRuntimeCount = 0;
uint32_t g_viewModelInstanceRuntimeCount = 0;
uint32_t g_viewModelInstanceValueRuntimeCount = 0;
uint32_t g_bindableArtboardCount = 0;
EXPORT uint32_t debugFileCount() { return (uint32_t)File::debugTotalFileCount; }
EXPORT uint32_t debugArtboardCount() { return g_artboardCount; }
EXPORT uint32_t debugStateMachineCount() { return g_stateMachineCount; }
EXPORT uint32_t debugAnimationCount() { return g_animationCount; }
EXPORT uint32_t debugViewModelRuntimeCount() { return g_viewModelRuntimeCount; }
EXPORT uint32_t debugViewModelInstanceRuntimeCount()
{
    return g_viewModelInstanceRuntimeCount;
}
EXPORT uint32_t debugViewModelInstanceValueRuntimeCount()
{
    return g_viewModelInstanceValueRuntimeCount;
}
EXPORT uint32_t debugBindableArtboardCount() { return g_bindableArtboardCount; }
#endif

WrappedDataBind::WrappedDataBind(DataBind* dataBind) : m_dataBind(dataBind) {}

WrappedDataBind::~WrappedDataBind() { m_dataBind = nullptr; }

void WrappedDataBind::deleteDataBind() { m_dataBind = nullptr; }

DataBind* WrappedDataBind::dataBind() { return m_dataBind; }

// Used in data binding artboards. Essentially just an Artboard, but we don't
// distinguish between an Artboard and an ArtboardInstance in rive_native, and
// this is solely used for data binding purposes. In the future, this wrapped
// class might be more complex, at least at the higher level.
class WrappedBindableArtboard
{
public:
    WrappedBindableArtboard(rcp<BindableArtboard> artboard, rcp<File> file) :
        m_file(file), m_artboard(artboard)
    {
#ifdef DEBUG
        g_bindableArtboardCount++;
#endif
    }

#ifdef DEBUG
    ~WrappedBindableArtboard() { g_bindableArtboardCount--; }
#endif

    rcp<BindableArtboard> artboard()
    {
        assert(m_artboard);
        return m_artboard;
    }

private:
    rcp<File> m_file;
    rcp<BindableArtboard> m_artboard;
};

WrappedArtboard::WrappedArtboard(
    std::unique_ptr<ArtboardInstance>&& artboardInstance,
    rcp<File> file) :
    m_file(file), m_artboard(std::move(artboardInstance))
{
#ifdef WITH_RIVE_TOOLS
    // Events should call back with the wrapper.
    m_artboard->callbackUserData = this;
#endif
#ifdef DEBUG
    g_artboardCount++;
#endif
}

WrappedArtboard::~WrappedArtboard()
{
    // Make sure artboard is deleted before file.
    m_artboard = nullptr;
    m_file = nullptr;

#if defined(__EMSCRIPTEN__)
    _webLayoutChangedCallbacks.erase(this);
    _webLayoutDirtyCallbacks.erase(this);
    _webTransformDirtyCallbacks.erase(this);
    _webEventCallbacks.erase(this);
    _webTestBoundsCallbacks.erase(this);
    _webIsAncestorCallbacks.erase(this);
    _webRootTransformCallbacks.erase(this);
#endif

#ifdef DEBUG
    g_artboardCount--;
#endif
}

void WrappedArtboard::notify(const std::vector<EventReport>& events,
                             NestedArtboard* context)
{
    if (m_eventCallback == nullptr || context != nullptr)
    {
        // No callback or it came from a nested artboard, don't report up.
        return;
    }
    for (auto report : events)
    {
        uint32_t id = m_artboard->idOf(report.event());
        if (id == 0)
        {
            // Couldn't find id.
            continue;
        }
        m_eventCallback(this, id);
    }
}

void WrappedArtboard::monitorEvents(LinearAnimationInstance* animation)
{
    animation->addNestedEventListener(this);
}

void WrappedArtboard::monitorEvents(StateMachineInstance* stateMachine)
{
    stateMachine->addNestedEventListener(this);
}

void WrappedArtboard::addDataBind(WrappedDataBind* dataBind)
{
    m_dataBinds.push_back(dataBind);
}

void WrappedArtboard::deleteDataBinds()
{

    for (auto dataBind : m_dataBinds)
    {
        dataBind->deleteDataBind();
    }
    m_dataBinds.clear();
}

ArtboardInstance* WrappedArtboard::artboard()
{
    assert(m_artboard);
    return m_artboard.get();
}

class WrappedStateMachine : public RefCnt<WrappedStateMachine>
{
public:
    WrappedStateMachine(
        rcp<WrappedArtboard> artboard,
        std::unique_ptr<StateMachineInstance>&& stateMachineInstance) :
        m_wrappedArtboard(std::move(artboard)),
        m_stateMachine(std::move(stateMachineInstance))
    {
#ifdef DEBUG
        g_stateMachineCount++;
#endif
    }

    ~WrappedStateMachine()
    {
        // Clean up the focus tree BEFORE the StateMachineInstance (and its
        // FocusManager) is destroyed. The artboard and its nested artboards
        // store raw pointers to the FocusManager, which would become dangling
        // when m_stateMachine is implicitly destroyed.
        if (m_stateMachine != nullptr && m_wrappedArtboard != nullptr)
        {
#ifdef WITH_RIVE_TOOLS
            // Clear the focus changed callback before cleanup to prevent
            // invoking Dart callbacks during destruction. This is critical
            // during Dart finalizer execution where calling back into Dart
            // is not allowed ("leaf call" error).
            //
            // IMPORTANT: Only clear the callback on the INTERNAL FocusManager.
            // If an external FocusManager is set, its lifecycle is managed by
            // Dart (via FocusManagerFFI), and it may have already been disposed
            // before this destructor runs. Touching it would cause a
            // use-after-free.
            if (!m_stateMachine->hasExternalFocusManager())
            {
                auto* fm = m_stateMachine->internalFocusManager();
                if (fm != nullptr)
                {
                    fm->setFocusChangedCallback(nullptr);
                }
            }
#endif
            auto* artboard = m_wrappedArtboard->artboard();
            if (artboard != nullptr)
            {
                artboard->cleanupFocusTree();
            }
        }
#ifdef DEBUG
        g_stateMachineCount--;
#endif
    }

    StateMachineInstance* stateMachine() { return m_stateMachine.get(); }

    WrappedArtboard* wrappedArtboard()
    {
        assert(m_wrappedArtboard);
        return m_wrappedArtboard.get();
    };

private:
    rcp<WrappedArtboard> m_wrappedArtboard;
    std::unique_ptr<StateMachineInstance> m_stateMachine;
};

class WrappedInput
{
public:
    WrappedInput(rcp<WrappedStateMachine> stateMachineInstance,
                 SMIInput* input) :
        m_input(input), m_wrappedMachine(stateMachineInstance)
    {}

    ~WrappedInput() {}

    SMIInput* input() { return m_input; }
    SMINumber* number()
    {
        if (m_input->inputCoreType() != StateMachineNumberBase::typeKey)
        {
            return nullptr;
        }
        return static_cast<SMINumber*>(m_input);
    }

    SMIBool* boolean()
    {
        if (m_input->inputCoreType() != StateMachineBoolBase::typeKey)
        {
            return nullptr;
        }
        return static_cast<SMIBool*>(m_input);
    }

    void fire()
    {
        if (m_input->inputCoreType() != StateMachineTriggerBase::typeKey)
        {
            return;
        }
        static_cast<SMITrigger*>(m_input)->fire();
    }

private:
    rive::SMIInput* m_input;
    rcp<WrappedStateMachine> m_wrappedMachine;
};

class WrappedTextValueRun
{
public:
    WrappedTextValueRun(rcp<WrappedArtboard> artboard,
                        TextValueRun* textValueRun,
                        const std::string& path = "") :
        m_textValueRun(textValueRun), m_wrappedArtboard(artboard), m_path(path)
    {}

    ~WrappedTextValueRun() {}

    TextValueRun* textValueRun() { return m_textValueRun; }

    const std::string& path() const { return m_path; }

private:
    rive::TextValueRun* m_textValueRun;
    rcp<WrappedArtboard> m_wrappedArtboard;
    std::string m_path;
};

class WrappedEvent : public RefCnt<WrappedEvent>
{
public:
    WrappedEvent(rcp<WrappedStateMachine> stateMachineInstance, Event* event) :
        m_event(event), m_wrappedMachine(stateMachineInstance)
    {}

    ~WrappedEvent() {}

    Event* event() { return m_event; }

private:
    rive::Event* m_event;
    rcp<WrappedStateMachine> m_wrappedMachine;
};

class WrappedCustomProperty
{
public:
    WrappedCustomProperty(rcp<WrappedEvent> event,
                          CustomProperty* customProperty) :
        m_customProperty(customProperty), m_wrappedEvent(event)
    {}

    ~WrappedCustomProperty() {}

    CustomProperty* customProperty() { return m_customProperty; }

private:
    rive::CustomProperty* m_customProperty;
    rcp<WrappedEvent> m_wrappedEvent;
};

class WrappedComponent
{
public:
    WrappedComponent(rcp<WrappedArtboard> wrappedArtboard,
                     TransformComponent* component) :
        m_component(component), m_wrappedArtboard(std::move(wrappedArtboard))
    {}

    TransformComponent* component() { return m_component; }

private:
    TransformComponent* m_component;
    rcp<WrappedArtboard> m_wrappedArtboard;
};

class WrappedLinearAnimation : public RefCnt<WrappedLinearAnimation>
{
public:
    WrappedLinearAnimation(
        rcp<WrappedArtboard> artboard,
        std::unique_ptr<LinearAnimationInstance>&& linearAnimation) :
        m_linearAnimation(std::move(linearAnimation)),
        m_wrappedArtboard(artboard)
    {
#ifdef DEBUG
        g_animationCount++;
#endif
    }
    ~WrappedLinearAnimation()
    {
        m_linearAnimation = nullptr;
        m_wrappedArtboard = nullptr;
#ifdef DEBUG
        g_animationCount--;
#endif
    }
    LinearAnimationInstance* animation() { return m_linearAnimation.get(); }

    WrappedArtboard* wrappedArtboard()
    {
        assert(m_wrappedArtboard);
        return m_wrappedArtboard.get();
    }

private:
    std::unique_ptr<LinearAnimationInstance> m_linearAnimation;
    rcp<WrappedArtboard> m_wrappedArtboard;
};

#pragma region ViewModelRuntime Classes

class WrappedViewModelRuntime
{
public:
    WrappedViewModelRuntime(ViewModelRuntime* viewModelRuntime,
                            rcp<File> file) :
        m_file(file), m_viewModelRuntime(viewModelRuntime)
    {
#ifdef DEBUG
        g_viewModelRuntimeCount++;
#endif
    }

    ~WrappedViewModelRuntime()
    {
        // Make sure viewModelRuntime is deleted before file.
        m_viewModelRuntime = nullptr;
        m_file = nullptr;

#ifdef DEBUG
        g_viewModelRuntimeCount--;
#endif
    }

    ViewModelRuntime* viewModel() { return m_viewModelRuntime; }

private:
    rcp<File> m_file;
    ViewModelRuntime* m_viewModelRuntime;
};

class WrappedVMIRuntime : public RefCnt<WrappedVMIRuntime>
{
public:
    WrappedVMIRuntime(rcp<ViewModelInstanceRuntime> viewModelInstanceRuntime) :
        m_viewModelInstanceRuntime(viewModelInstanceRuntime)
    {
#ifdef DEBUG
        g_viewModelInstanceRuntimeCount++;
#endif
    }

    ~WrappedVMIRuntime()
    {
#ifdef DEBUG
        g_viewModelInstanceRuntimeCount--;
#endif
    }

    ViewModelInstanceRuntime* instance()
    {
        assert(m_viewModelInstanceRuntime);
        return m_viewModelInstanceRuntime.get();
    }

private:
    rcp<ViewModelInstanceRuntime> m_viewModelInstanceRuntime;
};

template <typename T = ViewModelInstanceValueRuntime>
class WrappedVMIValueRuntime
{
public:
    WrappedVMIValueRuntime(rcp<WrappedVMIRuntime> viewModelInstanceRuntime,
                           T* value) :
        m_viewModelInstanceRuntime(viewModelInstanceRuntime), m_value(value)
    {
#ifdef DEBUG
        g_viewModelInstanceValueRuntimeCount++;
#endif
    }

    ~WrappedVMIValueRuntime()
    {
#ifdef DEBUG
        g_viewModelInstanceValueRuntimeCount--;
#endif
    }

    T* instance() { return m_value; }

private:
    rcp<WrappedVMIRuntime> m_viewModelInstanceRuntime;
    T* m_value;
};

using WrappedVMINumberRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceNumberRuntime>;
using WrappedVMIStringRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceStringRuntime>;
using WrappedVMIBooleanRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceBooleanRuntime>;
using WrappedVMIEnumRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceEnumRuntime>;
using WrappedVMIColorRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceColorRuntime>;
using WrappedVMITriggerRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceTriggerRuntime>;
using WrappedVMIAssetImageRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceAssetImageRuntime>;
using WrappedVMIAssetFontRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceAssetFontRuntime>;
using WrappedVMIListRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceListRuntime>;
using WrappedVMIArtboardRuntime =
    WrappedVMIValueRuntime<ViewModelInstanceArtboardRuntime>;

#pragma endregion

EXPORT bool builtWithRiveTools()
{
#ifdef WITH_RIVE_TOOLS
    return true;
#else
    return false;
#endif
}

EXPORT void freeString(const char* str) { std::free((void*)str); }

#pragma region File

#if defined(__EMSCRIPTEN__)
EXPORT WasmPtr loadRiveFile(WasmPtr bufferPtr,
                            WasmPtr lengthPtr,
                            WasmPtr factoryPtr,
                            emscripten::val assetLoader,
                            WasmPtr vmPtr)
{
    auto bytes = (uint8_t*)bufferPtr;
    if (bytes == nullptr)
    {
        return (WasmPtr)(File*)(0x2);
    }

    auto factory = (rive::Factory*)factoryPtr;
    auto length = (SizeType)lengthPtr;
    auto vm = (ScriptingVM*)vmPtr;

    class FlutterFileAssetLoader : public rive::FileAssetLoader
    {
    private:
        emscripten::val m_callback;

    public:
        FlutterFileAssetLoader(emscripten::val callback) : m_callback(callback)
        {}

        bool loadContents(rive::FileAsset& asset,
                          Span<const uint8_t> inBandBytes,
                          rive::Factory* factory) override
        {
            if (!m_callback.isNull())
            {
                asset.ref();
                return m_callback((WasmPtr)(&asset),
                                  (WasmPtr)(inBandBytes.data()),
                                  inBandBytes.size())
                    .as<bool>();
            }
            return false;
        }
    };

    rcp<File> file;
    auto loader = make_rcp<FlutterFileAssetLoader>(assetLoader);
    if ((file = File::import(Span(bytes, length),
                             factory,
                             nullptr, // TODO: Handle results
                             loader,
                             vm)))
    {
#ifdef WITH_RIVE_TOOLS
        auto context = std::make_unique<FileViewModelContext>();
        file->setViewModelInstanceRegistrar(&context->registrar);
        g_fileViewModelContexts[file.get()] = std::move(context);
#endif
        return (WasmPtr)(file.release());
    }
    return (WasmPtr) nullptr;
}

#else
EXPORT void* loadRiveFile(const uint8_t* bytes,
                          SizeType length,
                          rive::Factory* factory,
                          AssetLoaderCallback assetLoader,
                          void* vmPtr)
{
    if (bytes == nullptr)
    {
        return (File*)(0x2);
    }

    class FlutterFileAssetLoader : public rive::FileAssetLoader
    {
    private:
        AssetLoaderCallback m_callback;

    public:
        FlutterFileAssetLoader(AssetLoaderCallback callback) :
            m_callback(callback)
        {}

        bool loadContents(rive::FileAsset& asset,
                          Span<const uint8_t> inBandBytes,
                          rive::Factory* factory) override
        {
            if (m_callback != nullptr)
            {
                asset.ref();
                return m_callback(&asset,
                                  inBandBytes.data(),
                                  inBandBytes.size());
            }
            return false;
        }
    };

    rcp<File> file;
    auto loader = make_rcp<FlutterFileAssetLoader>(assetLoader);
    auto vm = static_cast<ScriptingVM*>(vmPtr);
    if ((file = File::import(Span(bytes, length),
                             factory,
                             nullptr, // TODO: Handle results
                             loader,
                             vm)))
    {
#ifdef WITH_RIVE_TOOLS
        auto context = std::make_unique<FileViewModelContext>();
        file->setViewModelInstanceRegistrar(&context->registrar);
        g_fileViewModelContexts[file.get()] = std::move(context);
#endif
        return file.release();
    }

    return nullptr;
}
#endif

EXPORT void deleteFileAsset(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    fileAsset->unref();
}

EXPORT void deleteRiveFile(File* file)
{
    if (file == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    file->setViewModelInstanceRegistrar(nullptr);
    g_fileViewModelContexts.erase(file);
#endif
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    file->unref();
}

EXPORT WrappedArtboard* riveFileArtboardDefault(File* file, bool frameOrigin)
{
    if (file == nullptr || file->artboardCount() == 0)
    {
        return nullptr;
    }

    auto artboard = file->artboardDefault();
    if (!artboard)
    {
        return nullptr;
    }
    artboard->frameOrigin(frameOrigin);
    return new WrappedArtboard(std::move(artboard), ref_rcp(file));
}

EXPORT WrappedArtboard* riveFileArtboardNamed(File* file,
                                              const char* name,
                                              bool frameOrigin)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    auto artboardInstance = file->artboardNamed(name);
    if (artboardInstance == nullptr)
    {
        return nullptr;
    }

    AdvanceFlags advancingFlags;
    advancingFlags |= AdvanceFlags::AdvanceNested;
    artboardInstance->frameOrigin(frameOrigin);
    artboardInstance->advance(0.0f, advancingFlags);
    return new WrappedArtboard(std::move(artboardInstance), ref_rcp(file));
}

EXPORT WrappedBindableArtboard* riveFileArtboardToBindNamed(File* file,
                                                            const char* name)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    rcp<BindableArtboard> artboard = file->bindableArtboardNamed(name);
    if (artboard == nullptr)
    {
        return nullptr;
    }

    return new WrappedBindableArtboard(artboard, ref_rcp(file));
}

EXPORT void deleteBindableArtboard(WrappedBindableArtboard* artboardToBind)
{
    if (artboardToBind == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete artboardToBind;
}

EXPORT WrappedArtboard* riveFileArtboardByIndex(File* file,
                                                uint32_t index,
                                                bool frameOrigin)
{
    if (file == nullptr)
    {
        return nullptr;
    }

    auto artboardInstance = file->artboardAt(index);
    if (!artboardInstance)
    {
        return nullptr;
    }
    AdvanceFlags advancingFlags;
    advancingFlags |= AdvanceFlags::AdvanceNested;
    artboardInstance->frameOrigin(frameOrigin);
    artboardInstance->advance(0.0f, advancingFlags);
    return new WrappedArtboard(std::move(artboardInstance), ref_rcp(file));
}

#pragma endregion

#pragma region FileAsset

EXPORT const char* riveFileAssetName(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return nullptr;
    }

    return fileAsset->name().c_str();
}

EXPORT const char* riveFileAssetFileExtension(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return nullptr;
    }
    return toCString(fileAsset->fileExtension());
}

EXPORT const char* riveFileAssetCdnBaseUrl(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return nullptr;
    }

    return fileAsset->cdnBaseUrl().c_str();
}

EXPORT const char* riveFileAssetCdnUuid(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return nullptr;
    }
    return toCString(fileAsset->cdnUuidStr());
}

EXPORT uint32_t riveFileAssetId(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return 0;
    }

    return fileAsset->assetId();
}

EXPORT uint16_t riveFileAssetCoreType(FileAsset* fileAsset)
{
    if (fileAsset == nullptr)
    {
        return 0;
    }
    return fileAsset->coreType();
}

EXPORT bool riveFileAssetSetRenderImage(FileAsset* fileAsset,
                                        RenderImage* renderImage)
{
    if (fileAsset == nullptr || renderImage == nullptr ||
        !fileAsset->is<ImageAsset>())
    {
        return false;
    }
    ImageAsset* imageAsset = static_cast<ImageAsset*>(fileAsset);
    imageAsset->renderImage(ref_rcp(renderImage));
    return true;
}

EXPORT float imageAssetGetWidth(FileAsset* fileAsset)
{
    if (fileAsset == nullptr || !fileAsset->is<ImageAsset>())
    {
        return 0.0f;
    }
    ImageAsset* imageAsset = static_cast<ImageAsset*>(fileAsset);
    return imageAsset->width();
}

EXPORT float imageAssetGetHeight(FileAsset* fileAsset)
{
    if (fileAsset == nullptr || !fileAsset->is<ImageAsset>())
    {
        return 0.0f;
    }
    ImageAsset* imageAsset = static_cast<ImageAsset*>(fileAsset);
    return imageAsset->height();
}

EXPORT bool riveFileAssetSetAudioSource(FileAsset* fileAsset,
                                        AudioSource* audioSource)
{
#ifdef WITH_RIVE_AUDIO
    if (fileAsset == nullptr || audioSource == nullptr ||
        !fileAsset->is<AudioAsset>())
    {
        return false;
    }
    AudioAsset* audioAsset = static_cast<AudioAsset*>(fileAsset);
    audioAsset->audioSource(ref_rcp(audioSource));
    return true;
#endif
    return false;
}

EXPORT bool riveFileAssetSetFont(FileAsset* fileAsset, Font* font)
{
    if (fileAsset == nullptr || font == nullptr || !fileAsset->is<FontAsset>())
    {
        return false;
    }
    FontAsset* fontAsset = static_cast<FontAsset*>(fileAsset);
    fontAsset->font(ref_rcp(font));
    return true;
}

#pragma endregion

#pragma region ViewModelRuntime
EXPORT SizeType riveFileViewModelCount(File* file)
{
    if (file == nullptr)
    {
        return 0;
    }
    return file->viewModelCount();
}

EXPORT WrappedViewModelRuntime* riveFileViewModelRuntimeByIndex(File* file,
                                                                SizeType index)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    auto vmi = file->viewModelByIndex(index);
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedViewModelRuntime(vmi, ref_rcp(file));
}

EXPORT WrappedViewModelRuntime* riveFileViewModelRuntimeByName(File* file,
                                                               const char* name)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    auto vmi = file->viewModelByName(name);
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedViewModelRuntime(vmi, ref_rcp(file));
}

EXPORT WrappedViewModelRuntime* riveFileDefaultArtboardViewModelRuntime(
    File* file,
    WrappedArtboard* artboard)
{
    if (file == nullptr || artboard == nullptr)
    {
        return nullptr;
    }
    auto vmi = file->defaultArtboardViewModel(artboard->artboard());
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedViewModelRuntime(vmi, ref_rcp(file));
}

EXPORT SizeType
viewModelRuntimePropertyCount(WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return 0;
    }
    return wrappedViewModel->viewModel()->propertyCount();
}

EXPORT SizeType
viewModelRuntimeInstanceCount(WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return 0;
    }
    return wrappedViewModel->viewModel()->instanceCount();
}

EXPORT void riveAdvanceFrameId()
{
#if defined(TESTING) || defined(WITH_RIVE_TOOLS)
    Artboard::incFrameId();
#endif
}

EXPORT const char* viewModelRuntimeName(
    WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    return wrappedViewModel->viewModel()->name().c_str();
}

EXPORT const char* vmiRuntimeName(WrappedVMIRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    return wrappedViewModel->instance()->name().c_str();
}

#ifdef __EMSCRIPTEN__
emscripten::val buildProperties(std::vector<rive::PropertyData>& properties)
{
    emscripten::val jsProperties = emscripten::val::array();
    for (const auto& prop : properties)
    {
        emscripten::val jsProp = emscripten::val::object();
        jsProp.set("name", prop.name);
        int val = static_cast<int>(prop.type);
        jsProp.set("type", val);
        jsProperties.call<void>("push", jsProp);
    }
    return jsProperties;
}

emscripten::val viewModelRuntimeProperties(WasmPtr wrappedViewModelPtr)
{
    WrappedViewModelRuntime* wrappedViewModel =
        (WrappedViewModelRuntime*)wrappedViewModelPtr;
    if (wrappedViewModel == nullptr)
    {
        return emscripten::val::null();
    }
    auto props = wrappedViewModel->viewModel()->properties();

    return buildProperties(props);
}

emscripten::val vmiRuntimeProperties(WasmPtr wrappedVMIPtr)
{
    WrappedVMIRuntime* wrappedVMI = (WrappedVMIRuntime*)wrappedVMIPtr;
    if (wrappedVMI == nullptr)
    {
        return emscripten::val::null();
    }
    auto props = wrappedVMI->instance()->properties();

    return buildProperties(props);
}

emscripten::val createDataEnumObject(rive::DataEnum* dataEnum)
{
    emscripten::val dataEnumObject = emscripten::val::object();
    dataEnumObject.set("name", dataEnum->enumName());
    emscripten::val dataEnumValues = emscripten::val::array();
    for (auto& value : dataEnum->values())
    {
        auto name = value->key();
        dataEnumValues.call<void>("push", name);
    }
    dataEnumObject.set("values", dataEnumValues);
    return dataEnumObject;
}

emscripten::val fileEnums(WasmPtr filePtr)
{
    File* file = (File*)filePtr;
    if (file == nullptr)
    {
        return emscripten::val::null();
    }
    auto enums = file->enums();
    emscripten::val jsProperties = emscripten::val::array();
    for (auto& dataEnum : enums)
    {
        auto enumObject = createDataEnumObject(dataEnum);
        jsProperties.call<void>("push", enumObject);
    }
    return jsProperties;
}
#else

struct ViewModelPropertyDataFFI
{
    int type;
    const char* name;
};

struct ViewModelPropertyDataArray
{
    ViewModelPropertyDataFFI* data;
    int length;
};

ViewModelPropertyDataArray generateViewModelPropertyDataArray(
    std::vector<PropertyData>& props)
{
    ViewModelPropertyDataFFI* out = (ViewModelPropertyDataFFI*)malloc(
        sizeof(ViewModelPropertyDataFFI) * props.size());

    for (size_t i = 0; i < props.size(); ++i)
    {
        // The string is only valid for the duration of the
        // call. In Flutter, we would get invalid data or errors when trying
        // to access the string: return
        // viewModel->properties().at(index).name.c_str();

        // We copy the string to the heap and return a pointer to it,
        // because the string is only valid for the duration of the call. We
        // free up the memory in the `deleteViewModelPropertyDataArray`
        // function.
        const std::string& name = props[i].name;
        char* cstr = (char*)malloc(name.size() + 1);
        std::memcpy(cstr, name.c_str(), name.size() + 1);

        out[i].type = static_cast<int>(props[i].type);
        out[i].name = cstr;
    }

    return {out, static_cast<int>(props.size())};
}

EXPORT ViewModelPropertyDataArray
viewModelRuntimeProperties(WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return {nullptr, 0};
    }
    auto props = wrappedViewModel->viewModel()->properties();
    return generateViewModelPropertyDataArray(props);
}

EXPORT ViewModelPropertyDataArray
vmiRuntimeProperties(WrappedVMIRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return {nullptr, 0};
    }
    auto props = wrappedViewModel->instance()->properties();
    return generateViewModelPropertyDataArray(props);
}

EXPORT void deleteViewModelPropertyDataArray(ViewModelPropertyDataArray arr)
{
    for (int i = 0; i < arr.length; i++)
    {
        free((void*)arr.data[i].name);
    }
    free(arr.data);
}

struct DataEnumFFI
{
    const char* name;
    const char** values;
    int length;
};
struct DataEnumArray
{
    DataEnumFFI* data;
    int length;
};

EXPORT DataEnumArray fileEnums(File* file)
{
    if (file == nullptr)
    {
        return {nullptr, 0};
    }
    auto enums = file->enums();
    DataEnumFFI* out = (DataEnumFFI*)malloc(sizeof(DataEnumFFI) * enums.size());

    for (size_t i = 0; i < enums.size(); ++i)
    {
        auto dataEnum = enums[i];
        auto valueSize = dataEnum->values().size();
        const char** c_values = new const char*[valueSize];
        for (size_t j = 0; j < valueSize; ++j)
        {
            auto value = dataEnum->values()[j];
            c_values[j] = value->key().c_str();
        }
        out[i].name = dataEnum->enumName().c_str();
        out[i].values = c_values;
        out[i].length = static_cast<int>(valueSize);
    }
    return {out, static_cast<int>(enums.size())};
}

EXPORT void deleteDataEnumArray(DataEnumArray enums)
{
    if (enums.data == nullptr)
    {
        return;
    }

    for (int i = 0; i < enums.length; ++i)
    {
        delete[] enums.data[i].values;
    }
    free(enums.data);
}
#endif

EXPORT WrappedVMIRuntime* createVMIRuntimeFromIndex(
    WrappedViewModelRuntime* wrappedViewModel,
    size_t index)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    auto vmi = wrappedViewModel->viewModel()->createInstanceFromIndex(index);
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(vmi);
}

EXPORT WrappedVMIRuntime* createVMIRuntimeFromName(
    WrappedViewModelRuntime* wrappedViewModel,
    const char* name)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    auto vmi = wrappedViewModel->viewModel()->createInstanceFromName(name);
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(vmi);
}

EXPORT WrappedVMIRuntime* createDefaultVMIRuntime(
    WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    auto vmi = wrappedViewModel->viewModel()->createDefaultInstance();
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(vmi);
}

EXPORT WrappedVMIRuntime* createVMIRuntime(
    WrappedViewModelRuntime* wrappedViewModel)
{
    if (wrappedViewModel == nullptr)
    {
        return nullptr;
    }
    auto vmi = wrappedViewModel->viewModel()->createInstance();
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(vmi);
}

EXPORT WrappedVMIRuntime* vmiRuntimeGetViewModelProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto vmi = viewModelInstance->propertyViewModel(path);
    if (vmi == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(vmi);
}

EXPORT WrappedVMINumberRuntime* vmiRuntimeGetNumberProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto numberProperty = viewModelInstance->propertyNumber(path);
    if (numberProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMINumberRuntime(ref_rcp(wrappedViewModelInstance),
                                       numberProperty);
}

EXPORT float getVMINumberRuntimeValue(
    WrappedVMINumberRuntime* wrappedNumberProperty)
{
    if (wrappedNumberProperty == nullptr)
    {
        return 0.0f;
    }
    return wrappedNumberProperty->instance()->value();
}

EXPORT void setVMINumberRuntimeValue(
    WrappedVMINumberRuntime* wrappedNumberProperty,
    float value)
{
    if (wrappedNumberProperty == nullptr)
    {
        return;
    }
    wrappedNumberProperty->instance()->value(value);
}

EXPORT WrappedVMIStringRuntime* vmiRuntimeGetStringProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto stringProperty = viewModelInstance->propertyString(path);
    if (stringProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIStringRuntime(ref_rcp(wrappedViewModelInstance),
                                       stringProperty);
}

EXPORT const char* getVMIStringRuntimeValue(
    WrappedVMIStringRuntime* wrappedStringProperty)
{
    if (wrappedStringProperty == nullptr)
    {
        return nullptr;
    }
    return wrappedStringProperty->instance()->value().c_str();
}

EXPORT void setVMIStringRuntimeValue(
    WrappedVMIStringRuntime* wrappedStringProperty,
    const char* value)
{
    if (wrappedStringProperty == nullptr)
    {
        return;
    }
    wrappedStringProperty->instance()->value(value);
}

EXPORT WrappedVMIBooleanRuntime* vmiRuntimeGetBooleanProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto booleanProperty = viewModelInstance->propertyBoolean(path);
    if (booleanProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIBooleanRuntime(ref_rcp(wrappedViewModelInstance),
                                        booleanProperty);
}

EXPORT bool getVMIBooleanRuntimeValue(
    WrappedVMIBooleanRuntime* wrappedBooleanProperty)
{
    if (wrappedBooleanProperty == nullptr)
    {
        return false;
    }
    return wrappedBooleanProperty->instance()->value();
}

EXPORT void setVMIBooleanRuntimeValue(
    WrappedVMIBooleanRuntime* wrappedBooleanProperty,
    bool value)
{
    if (wrappedBooleanProperty == nullptr)
    {
        return;
    }
    wrappedBooleanProperty->instance()->value(value);
}

EXPORT WrappedVMIColorRuntime* vmiRuntimeGetColorProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto colorProperty = viewModelInstance->propertyColor(path);
    if (colorProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIColorRuntime(ref_rcp(wrappedViewModelInstance),
                                      colorProperty);
}

EXPORT int getVMIColorRuntimeValue(WrappedVMIColorRuntime* wrappedColorProperty)
{
    if (wrappedColorProperty == nullptr)
    {
        return 0x000000FF;
    }
    return wrappedColorProperty->instance()->value();
}

EXPORT void setVMIColorRuntimeValue(
    WrappedVMIColorRuntime* wrappedColorProperty,
    int value)
{
    if (wrappedColorProperty == nullptr)
    {
        return;
    }
    wrappedColorProperty->instance()->value(value);
}

EXPORT WrappedVMIEnumRuntime* vmiRuntimeGetEnumProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto enumProperty = viewModelInstance->propertyEnum(path);
    if (enumProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIEnumRuntime(ref_rcp(wrappedViewModelInstance),
                                     enumProperty);
}

EXPORT const char* getVMIEnumRuntimeValue(
    WrappedVMIEnumRuntime* wrappedEnumProperty)
{
    if (wrappedEnumProperty == nullptr)
    {
        return nullptr;
    }
    return toCString(wrappedEnumProperty->instance()->value());
}

EXPORT void setVMIEnumRuntimeValue(WrappedVMIEnumRuntime* wrappedEnumProperty,
                                   const char* value)
{
    if (wrappedEnumProperty == nullptr)
    {
        return;
    }
    wrappedEnumProperty->instance()->value(value);
}

EXPORT const char* getVMIEnumRuntimeEnumType(
    WrappedVMIEnumRuntime* wrappedEnumProperty)
{
    if (wrappedEnumProperty == nullptr)
    {
        return nullptr;
    }
    return toCString(wrappedEnumProperty->instance()->enumType());
}

EXPORT WrappedVMITriggerRuntime* vmiRuntimeGetTriggerProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto triggerProperty = viewModelInstance->propertyTrigger(path);
    if (triggerProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMITriggerRuntime(ref_rcp(wrappedViewModelInstance),
                                        triggerProperty);
}

EXPORT void triggerVMITriggerRuntime(
    WrappedVMITriggerRuntime* wrappedTriggerProp)
{
    if (wrappedTriggerProp == nullptr)
    {
        return;
    }
    return wrappedTriggerProp->instance()->trigger();
}

EXPORT WrappedVMIAssetImageRuntime* vmiRuntimeGetAssetImageProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto imageProperty = viewModelInstance->propertyImage(path);
    if (imageProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIAssetImageRuntime(ref_rcp(wrappedViewModelInstance),
                                           imageProperty);
}

EXPORT void setVMIAssetImageRuntimeValue(
    WrappedVMIAssetImageRuntime* wrappedAssetImageProperty,
    RenderImage* value)
{
    if (wrappedAssetImageProperty == nullptr)
    {
        return;
    }
    wrappedAssetImageProperty->instance()->value(value);
}

EXPORT WrappedVMIAssetFontRuntime* vmiRuntimeGetAssetFontProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto fontProperty = viewModelInstance->propertyFont(path);
    if (fontProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIAssetFontRuntime(ref_rcp(wrappedViewModelInstance),
                                          fontProperty);
}

EXPORT void setVMIAssetFontRuntimeValue(
    WrappedVMIAssetFontRuntime* wrappedAssetFontProperty,
    Font* value)
{
    if (wrappedAssetFontProperty == nullptr)
    {
        return;
    }
    wrappedAssetFontProperty->instance()->value(value);
}

EXPORT WrappedVMIListRuntime* vmiRuntimeGetListProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto listProperty = viewModelInstance->propertyList(path);
    if (listProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIListRuntime(ref_rcp(wrappedViewModelInstance),
                                     listProperty);
}

EXPORT size_t getVMIListRuntimeSize(WrappedVMIListRuntime* wrappedListProperty)
{
    if (wrappedListProperty == nullptr)
    {
        return 0;
    }
    return wrappedListProperty->instance()->size();
}

EXPORT void vmiListRuntimeAddInstance(
    WrappedVMIListRuntime* wrappedListProperty,
    WrappedVMIRuntime* wrappedViewModelInstance)
{
    if (wrappedListProperty == nullptr || wrappedViewModelInstance == nullptr)
    {
        return;
    }
    wrappedListProperty->instance()->addInstance(
        wrappedViewModelInstance->instance());
}

EXPORT bool vmiListRuntimeAddInstanceAt(
    WrappedVMIListRuntime* wrappedListProperty,
    WrappedVMIRuntime* wrappedViewModelInstance,
    int index)
{
    if (wrappedListProperty == nullptr || wrappedViewModelInstance == nullptr)
    {
        return false;
    }
    return wrappedListProperty->instance()->addInstanceAt(
        wrappedViewModelInstance->instance(),
        index);
}

EXPORT void vmiListRuntimeRemoveInstance(
    WrappedVMIListRuntime* wrappedListProperty,
    WrappedVMIRuntime* wrappedViewModelInstance)
{
    if (wrappedListProperty == nullptr || wrappedViewModelInstance == nullptr)
    {
        return;
    }
    wrappedListProperty->instance()->removeInstance(
        wrappedViewModelInstance->instance());
}

EXPORT void vmiListRuntimeRemoveInstanceAt(
    WrappedVMIListRuntime* wrappedListProperty,
    int index)
{
    if (wrappedListProperty == nullptr)
    {
        return;
    }
    wrappedListProperty->instance()->removeInstanceAt(index);
}

EXPORT WrappedVMIRuntime* vmiListRuntimeInstanceAt(
    WrappedVMIListRuntime* wrappedListProperty,
    int index)
{
    if (wrappedListProperty == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedListProperty->instance()->instanceAt(index);
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIRuntime(viewModelInstance);
}

EXPORT void vmiListRuntimeSwap(WrappedVMIListRuntime* wrappedListProperty,
                               uint32_t a,
                               uint32_t b)
{
    if (wrappedListProperty == nullptr)
    {
        return;
    }
    wrappedListProperty->instance()->swap(a, b);
}

EXPORT bool vmiValueRuntimeHasChanged(
    WrappedVMIValueRuntime<ViewModelInstanceValueRuntime>* wrappedValue)
{
    if (wrappedValue == nullptr)
    {
        return false;
    }
    return wrappedValue->instance()->hasChanged();
}

EXPORT void vmiValueRuntimeClearChanges(
    WrappedVMIValueRuntime<ViewModelInstanceValueRuntime>* wrappedValue)
{
    if (wrappedValue == nullptr)
    {
        return;
    }
    return wrappedValue->instance()->clearChanges();
}

EXPORT WrappedVMIArtboardRuntime* vmiRuntimeGetArtboardProperty(
    WrappedVMIRuntime* wrappedViewModelInstance,
    const char* path)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    auto artboardProperty = viewModelInstance->propertyArtboard(path);
    if (artboardProperty == nullptr)
    {
        return nullptr;
    }
    return new WrappedVMIArtboardRuntime(ref_rcp(wrappedViewModelInstance),
                                         artboardProperty);
}

EXPORT void setVMIArtboardRuntimeValue(
    WrappedVMIArtboardRuntime* wrappedArtboardProperty,
    WrappedBindableArtboard* wrappedBindableArtboard,
    WrappedVMIRuntime* wrappedViewModelInstance)
{
    if (wrappedArtboardProperty == nullptr ||
        wrappedBindableArtboard == nullptr)
    {
        return;
    }
    wrappedArtboardProperty->instance()->value(
        wrappedBindableArtboard->artboard());
    wrappedArtboardProperty->instance()->viewModelInstance(
        wrappedViewModelInstance
            ? wrappedViewModelInstance->instance()->instance()
            : nullptr);
}

EXPORT void artboardSetVMIRuntime(WrappedArtboard* wrappedArtboard,
                                  WrappedVMIRuntime* wrappedViewModelInstance)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (wrappedArtboard == nullptr || viewModelInstance == nullptr)
    {
        return;
    }
    if (viewModelInstance->instance() == nullptr)
    {
        return;
    }

    wrappedArtboard->artboard()->bindViewModelInstance(
        viewModelInstance->instance());
}

EXPORT void stateMachineSetVMIRuntime(
    WrappedStateMachine* wrappedMachine,
    WrappedVMIRuntime* wrappedViewModelInstance)
{
    if (wrappedViewModelInstance == nullptr)
    {
        return;
    }
    auto viewModelInstance = wrappedViewModelInstance->instance();
    if (wrappedMachine == nullptr || viewModelInstance == nullptr ||
        viewModelInstance->instance() == nullptr)
    {
        return;
    }
    wrappedMachine->stateMachine()->bindViewModelInstance(
        viewModelInstance->instance());
}

EXPORT void deleteVMIValueRuntime(
    WrappedVMIValueRuntime<ViewModelInstanceValueRuntime>* wrappedValue)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedValue;
}

EXPORT void deleteVMIRuntime(WrappedVMIRuntime* wrappedVMIRuntime)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    wrappedVMIRuntime->unref();
}

EXPORT void deleteViewModelRuntime(
    WrappedViewModelRuntime* wrappedViewModelRuntime)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedViewModelRuntime;
}

#pragma endregion

EXPORT DataContext* riveDataContext(File* file,
                                    SizeType index,
                                    SizeType indexInstance)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    auto instance = file->createViewModelInstance(index, indexInstance);
    if (instance == nullptr)
    {
        return nullptr;
    }
    auto dataContext = new DataContext(instance);
    return dataContext;
}

EXPORT void deleteDataContext(DataContext* dataContext)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    dataContext->unref();
}

EXPORT DataContext* riveDataContextFromInstances(File* file,
                                                 SizeType* viewModelIndices,
                                                 SizeType* instanceIndices,
                                                 SizeType count)
{
    if (file == nullptr || count == 0)
    {
        return nullptr;
    }
    std::vector<rcp<ViewModelInstance>> instances;
    instances.reserve(count);
    for (SizeType i = 0; i < count; i++)
    {
        auto instance = file->createViewModelInstance(viewModelIndices[i],
                                                      instanceIndices[i]);
        if (instance != nullptr)
        {
            instances.push_back(std::move(instance));
        }
    }
    if (instances.empty())
    {
        return nullptr;
    }
    auto dataContext = new DataContext(std::move(instances));
    return dataContext;
}

EXPORT ViewModelInstance* riveDataContextViewModelInstance(
    DataContext* dataContext)
{
    if (dataContext == nullptr)
    {
        return nullptr;
    }
    rcp<ViewModelInstance> vmi = dataContext->mainViewModelInstance();
    return vmi.release();
}

EXPORT ViewModelInstance* dataContextViewModelInstanceAt(
    DataContext* dataContext,
    SizeType index)
{
    if (dataContext == nullptr)
    {
        return nullptr;
    }
    auto& instances = dataContext->viewModelInstances();
    if (index >= instances.size())
    {
        return nullptr;
    }
    rcp<ViewModelInstance> vmi = instances[index];
    return vmi.release();
}

// Creates a DataContext from existing native ViewModelInstance pointers.
// Each instance is ref'd so the DataContext shares ownership with the caller.
// If parentDataContext is non-null it becomes the new context's parent.
EXPORT DataContext* dataContextFromViewModelInstancePointers(
    ViewModelInstance** instances,
    SizeType count,
    DataContext* parentDataContext)
{
    if (instances == nullptr || count == 0)
    {
        return nullptr;
    }
    std::vector<rcp<ViewModelInstance>> vec;
    vec.reserve(count);
    for (SizeType i = 0; i < count; i++)
    {
        if (instances[i] != nullptr)
        {
            vec.push_back(ref_rcp(instances[i]));
        }
    }
    if (vec.empty())
    {
        return nullptr;
    }
    auto dataContext = new DataContext(std::move(vec));
    if (parentDataContext != nullptr)
    {
        dataContext->parent(ref_rcp(parentDataContext));
    }
    return dataContext;
}

EXPORT ViewModelInstance* copyViewModelInstance(File* file,
                                                SizeType index,
                                                SizeType indexInstance)
{
    if (file == nullptr)
    {
        return nullptr;
    }
    rcp<ViewModelInstance> instance =
        file->createViewModelInstance(index, indexInstance);
    // no need to ref as we got a full (non ref& rcp)
    return instance.release();
}

EXPORT void createViewModelInstance(File* file, std::string viewModelName)
{
    if (file == nullptr)
    {
        return;
    }
    file->createViewModelInstance(viewModelName);
}

EXPORT void artboardDataContextFromInstance(
    WrappedArtboard* wrappedArtboard,
    ViewModelInstance* viewModelInstance,
    DataContext* dataContext,
    bool isRoot)
{
    if (wrappedArtboard == nullptr || viewModelInstance == nullptr)
    {
        return;
    }

    wrappedArtboard->artboard()->bindViewModelInstance(
        ref_rcp(viewModelInstance),
        ref_rcp(dataContext));
}

EXPORT void artboardUpdateDataBinds(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }

    wrappedArtboard->artboard()->updateDataBinds();
}

EXPORT DataContext* artboardDataContext(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto dataContext = wrappedArtboard->artboard()->dataContext();
    if (dataContext == nullptr)
    {
        return nullptr;
    }
    dataContext->ref();
    return dataContext.get();
}

EXPORT void artboardInternalDataContext(WrappedArtboard* wrappedArtboard,
                                        DataContext* dataContext)
{
    if (wrappedArtboard == nullptr || dataContext == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->internalDataContext(ref_rcp(dataContext));
}

EXPORT void artboardClearDataContext(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->clearDataContext();
}

EXPORT void artboardUnbind(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->unbind();
}

EXPORT void stateMachineDataContextFromInstance(
    WrappedStateMachine* wrappedMachine,
    ViewModelInstance* viewModelInstance)
{
    if (wrappedMachine == nullptr || viewModelInstance == nullptr)
    {
        return;
    }
    wrappedMachine->stateMachine()->bindViewModelInstance(
        ref_rcp(viewModelInstance));
}

EXPORT void stateMachineDataContext(WrappedStateMachine* wrappedMachine,
                                    DataContext* dataContext)
{
    if (dataContext == nullptr)
    {
        return;
    }
    wrappedMachine->stateMachine()->dataContext(ref_rcp(dataContext));
}

EXPORT ViewModelInstanceValue* viewModelInstancePropertyValue(
    ViewModelInstance* viewModelInstance,
    SizeType index,
    const char* name,
    uint32_t propertyType)
{
    if (viewModelInstance == nullptr || name == nullptr)
    {
        return nullptr;
    }

    std::string nameStr(name);
    auto propertyValues = viewModelInstance->propertyValues();

    // Collect all property values whose name matches AND whose associated
    // ViewModelProperty coreType matches the requested propertyType.
    std::vector<std::pair<size_t, ViewModelInstanceValue*>> matches;
    for (size_t i = 0; i < propertyValues.size(); i++)
    {
        auto* value = propertyValues[i].get();
        if (value == nullptr)
        {
            continue;
        }
        auto* prop = value->viewModelProperty();
        if (prop != nullptr && prop->constName() == nameStr)
        {
            // Enums are treated as a special case because they get converted
            // during export
            if (prop->coreType() == propertyType ||
                (prop->coreType() == ViewModelPropertyEnumCustomBase::typeKey &&
                 propertyType == ViewModelPropertyEnumBase::typeKey))
                matches.push_back({i, value});
        }
    }

    ViewModelInstanceValue* result = nullptr;
    if (matches.size() == 1)
    {
        result = matches[0].second;
    }
    else if (matches.size() > 1)
    {
        // Multiple matches — break the tie using the provided index.
        result = matches[0].second;
        for (auto& [idx, value] : matches)
        {
            if (idx == index)
            {
                result = value;
                break;
            }
        }
    }

    if (result == nullptr)
    {
        return nullptr;
    }

    // Make sure to increase ref count and release as propertyValue returns a
    // bare pointer.
    return ref_rcp(result).release();
}

// Prunes a view model instance down to only the property ids in keepIds,
// removing every other property value. Used to turn a full editor-time copy of
// a nested-artboard override instance into a sparse instance that contains only
// the explicitly-overridden properties, so data-context resolution falls
// through to the parent context for non-overridden properties. The keep ids are
// runtime property ids (matching ViewModelInstanceValue::viewModelPropertyId).
EXPORT void pruneViewModelInstanceToProperties(
    ViewModelInstance* viewModelInstance,
    const uint32_t* keepIds,
    SizeType keepCount)
{
    if (viewModelInstance == nullptr)
    {
        return;
    }
    std::unordered_set<uint32_t> keep;
    for (SizeType i = 0; i < keepCount; i++)
    {
        keep.insert(keepIds[i]);
    }
    // Snapshot the ids to remove first; removeValue mutates m_PropertyValues.
    std::vector<uint32_t> toRemove;
    for (auto& value : viewModelInstance->propertyValues())
    {
        auto id = value->viewModelPropertyId();
        if (keep.find(id) == keep.end())
        {
            toRemove.push_back(id);
        }
    }
    for (auto id : toRemove)
    {
        viewModelInstance->removeValue(id);
    }
}

EXPORT void deleteViewModelInstance(ViewModelInstance* viewModelInstance)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    viewModelInstance->unref();
}

EXPORT void deleteViewModelInstanceValue(ViewModelInstanceValue* value)
{
    if (value == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    value->unref();
}

EXPORT ViewModelInstance* viewModelInstanceReferenceViewModel(
    ViewModelInstanceValue* viewModelInstanceValue)
{
    if (viewModelInstanceValue == nullptr)
    {
        return nullptr;
    }
    rcp<ViewModelInstance> viewModelInstance =
        viewModelInstanceValue->as<ViewModelInstanceViewModel>()
            ->referenceViewModelInstance();
    return viewModelInstance.release();
}

EXPORT ViewModelInstance* viewModelInstanceListItemViewModel(
    ViewModelInstanceValue* viewModelInstanceValue,
    SizeType index)
{
    if (viewModelInstanceValue == nullptr)
    {
        return nullptr;
    }
    auto vmList = viewModelInstanceValue->as<ViewModelInstanceList>();
    if (vmList != nullptr && index < vmList->listItems().size())
    {
        auto vmListItem = vmList->item(index);
        if (vmListItem != nullptr && vmListItem->viewModelInstance() != nullptr)
        {
            rcp<ViewModelInstance>& vmi = vmListItem->viewModelInstance();
            return ref_rcp(vmi.get()).release();
        }
    }
    return nullptr;
}

EXPORT size_t
viewModelInstanceListSize(ViewModelInstanceList* viewModelInstanceList)
{
    if (viewModelInstanceList == nullptr)
    {
        return 0;
    }
    return viewModelInstanceList->listItems().size();
}

EXPORT void setViewModelInstanceNumberValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    float value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceNumber>())
    {
        return;
    }
    auto viewModelInstanceNumber =
        viewModelInstanceValue->as<ViewModelInstanceNumber>();
    viewModelInstanceNumber->propertyValue(value);
}

EXPORT void setViewModelInstanceTriggerValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    uint32_t value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceTrigger>())
    {
        return;
    }
    auto viewModelInstanceTrigger =
        viewModelInstanceValue->as<ViewModelInstanceTrigger>();
    viewModelInstanceTrigger->propertyValue(value);
}

EXPORT void setViewModelInstanceEnumValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    uint32_t value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceEnum>())
    {
        return;
    }
    auto viewModelInstanceEnum =
        viewModelInstanceValue->as<ViewModelInstanceEnum>();
    viewModelInstanceEnum->propertyValue(value);
}

EXPORT void setViewModelInstanceAssetValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    uint32_t value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceAsset>())
    {
        return;
    }
    auto viewModelInstanceAsset =
        viewModelInstanceValue->as<ViewModelInstanceAsset>();
    viewModelInstanceAsset->propertyValue(value);
}

uint32_t assetImageResolveRuntimeIndex(File* file,
                                       ViewModelInstanceAssetImage* vmi)
{
    if (file == nullptr || vmi == nullptr)
    {
        return std::numeric_limits<uint32_t>::max();
    }
    RenderImage* ri = vmi->asset()->renderImage();
    if (ri == nullptr)
    {
        return std::numeric_limits<uint32_t>::max();
    }
    auto span = file->assets();
    for (size_t i = 0; i < span.size(); ++i)
    {
        FileAsset* fa = span[i].get();
        if (fa != nullptr && fa->is<ImageAsset>())
        {
            auto faImg = fa->as<ImageAsset>();
            auto faRi = faImg->renderImage();
            if (faRi == ri)
            {
                return static_cast<uint32_t>(i);
            }
        }
    }
    return std::numeric_limits<uint32_t>::max();
}

EXPORT uint32_t viewModelInstanceAssetImageResolveRuntimeIndex(
    File* file,
    ViewModelInstanceValue* viewModelInstanceValue)
{
    if (file == nullptr || viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceAssetImage>())
    {
        return std::numeric_limits<uint32_t>::max();
    }
    return assetImageResolveRuntimeIndex(
        file,
        viewModelInstanceValue->as<ViewModelInstanceAssetImage>());
}

uint32_t assetFontResolveRuntimeIndex(File* file,
                                      ViewModelInstanceAssetFont* vmi)
{
    if (file == nullptr || vmi == nullptr)
    {
        return std::numeric_limits<uint32_t>::max();
    }
    Font* font = vmi->asset()->font().get();
    if (font == nullptr)
    {
        return std::numeric_limits<uint32_t>::max();
    }
    auto span = file->assets();
    for (size_t i = 0; i < span.size(); ++i)
    {
        FileAsset* fa = span[i].get();
        if (fa != nullptr && fa->is<FontAsset>())
        {
            auto faFont = fa->as<FontAsset>();
            if (faFont->font().get() == font)
            {
                return static_cast<uint32_t>(i);
            }
        }
    }
    return std::numeric_limits<uint32_t>::max();
}

EXPORT uint32_t viewModelInstanceAssetFontResolveRuntimeIndex(
    File* file,
    ViewModelInstanceValue* viewModelInstanceValue)
{
    if (file == nullptr || viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceAssetFont>())
    {
        return std::numeric_limits<uint32_t>::max();
    }
    return assetFontResolveRuntimeIndex(
        file,
        viewModelInstanceValue->as<ViewModelInstanceAssetFont>());
}

EXPORT void setViewModelInstanceBooleanValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    bool value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceBoolean>())
    {
        return;
    }
    auto viewModelInstanceBoolean =
        viewModelInstanceValue->as<ViewModelInstanceBoolean>();
    viewModelInstanceBoolean->propertyValue(value);
}

EXPORT void setViewModelInstanceColorValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    int value)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceColor>())
    {
        return;
    }
    auto viewModelInstanceColor =
        viewModelInstanceValue->as<ViewModelInstanceColor>();
    viewModelInstanceColor->propertyValue(value);
}

EXPORT void setViewModelInstanceStringValue(
    ViewModelInstanceValue* viewModelInstance,
    const char* value)
{
    if (viewModelInstance == nullptr ||
        !viewModelInstance->is<ViewModelInstanceString>())
    {
        return;
    }
    auto viewModelInstanceString =
        viewModelInstance->as<ViewModelInstanceString>();
    // Copy string so we never hold the Dart-allocated pointer; avoids
    // use-after-free if Dart frees the buffer after this returns.
    std::string valueCopy(value != nullptr ? value : "");
    viewModelInstanceString->propertyValue(valueCopy);
}

EXPORT void setViewModelInstanceSymbolListIndexValue(
    ViewModelInstanceValue* viewModelInstance,
    uint32_t value)
{
    if (viewModelInstance == nullptr ||
        !viewModelInstance->is<ViewModelInstanceSymbolListIndex>())
    {
        return;
    }
    auto viewModelInstanceListIndex =
        viewModelInstance->as<ViewModelInstanceSymbolListIndex>();
    viewModelInstanceListIndex->propertyValue(value);
}

EXPORT void setViewModelInstanceArtboardValue(
    ViewModelInstanceValue* viewModelInstance,
    uint32_t value)
{
    if (viewModelInstance == nullptr ||
        !viewModelInstance->is<ViewModelInstanceArtboard>())
    {
        return;
    }
    auto viewModelInstanceArtboard =
        viewModelInstance->as<ViewModelInstanceArtboard>();
    viewModelInstanceArtboard->propertyValue(value);
}

EXPORT void setViewModelInstanceViewModelValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    ViewModelInstance* viewModelInstance)
{
    if (viewModelInstance == nullptr || viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceViewModel>())
    {
        return;
    }
    auto viewModelInstanceViewModel =
        viewModelInstanceValue->as<ViewModelInstanceViewModel>();
    viewModelInstanceViewModel->updateViewModel(viewModelInstance);
}

EXPORT void setViewModelInstanceListValue(
    ViewModelInstanceValue* viewModelInstanceValue,
    ViewModelInstance* const* instances,
    size_t count)
{
    if (viewModelInstanceValue == nullptr ||
        !viewModelInstanceValue->is<ViewModelInstanceList>())
    {
        return;
    }
    auto list = viewModelInstanceValue->as<ViewModelInstanceList>();
    if (list == nullptr)
    {
        return;
    }
    // Build a pool of existing wrappers keyed by the ViewModelInstance
    // they wrap. Using a multimap so that duplicate VMI entries each get
    // their own wrapper and a given wrapper is reused at most once.
    std::unordered_multimap<ViewModelInstance*, rcp<ViewModelInstanceListItem>>
        pool;
    for (auto& existing : list->listItems())
    {
        pool.emplace(existing->viewModelInstance().get(), existing);
    }
    std::vector<rcp<ViewModelInstanceListItem>> items;
    items.reserve(count);
    for (size_t i = 0; i < count; ++i)
    {
        if (instances != nullptr && instances[i] != nullptr)
        {
            // Reuse an existing wrapper if one is still available in
            // the pool, to preserve pointer identity.
            auto it = pool.find(instances[i]);
            if (it != pool.end())
            {
                items.push_back(std::move(it->second));
                pool.erase(it);
            }
            else
            {
                auto item = rcp(new ViewModelInstanceListItem());
                item->viewModelInstance(ref_rcp(instances[i]));
                items.push_back(std::move(item));
            }
        }
    }
    list->updateList(&items);
}

// Buffer response structure for serialized data
struct ViewModelInstanceBufferResponse
{
#ifdef __EMSCRIPTEN__
    WasmPtr data;
#else
    uint8_t* data;
#endif
    size_t size;
};

// Forward declaration
static void serializeViewModelInstance(ViewModelInstance* instance,
                                       VectorBinaryWriter& writer);
static void serializeViewModelInstanceToBytesInternal(
    ViewModelInstance* viewModelInstance,
    VectorBinaryWriter& writer);

// Helper function to serialize a ViewModelInstanceValue
static void serializeViewModelInstanceValue(ViewModelInstanceValue* value,
                                            VectorBinaryWriter& writer)
{
    if (value == nullptr)
    {
        return;
    }

    // Write property ID
    writer.writeVarUint(value->viewModelPropertyId());

    // Write property type based on coreType
    uint16_t propertyType = value->coreType();
    if (value->is<ViewModelInstanceNumber>())
    {
        auto numberValue = value->as<ViewModelInstanceNumber>();
        writer.write(propertyType);
        writer.writeDouble(numberValue->propertyValue());
    }
    else if (value->is<ViewModelInstanceString>())
    {
        auto stringValue = value->as<ViewModelInstanceString>();
        writer.write(propertyType);
        writer.write(stringValue->propertyValue());
    }
    else if (value->is<ViewModelInstanceBoolean>())
    {
        auto boolValue = value->as<ViewModelInstanceBoolean>();
        writer.write(propertyType);
        writer.write(static_cast<uint8_t>(boolValue->propertyValue() ? 1 : 0));
    }
    else if (value->is<ViewModelInstanceColor>())
    {
        auto colorValue = value->as<ViewModelInstanceColor>();
        writer.write(propertyType);
        writer.writeVarUint(static_cast<uint32_t>(colorValue->propertyValue()));
    }
    else if (value->is<ViewModelInstanceEnum>())
    {
        auto enumValue = value->as<ViewModelInstanceEnum>();
        writer.write(propertyType);
        writer.writeVarUint(static_cast<uint32_t>(enumValue->propertyValue()));
    }
    else if (value->is<ViewModelInstanceTrigger>())
    {
        writer.write(propertyType);
        // Triggers don't have a persistent value, just the type
    }
    else if (value->is<ViewModelInstanceList>())
    {
        auto listValue = value->as<ViewModelInstanceList>();
        writer.write(propertyType);
        auto listItems = listValue->listItems();
        writer.writeVarUint(static_cast<uint32_t>(listItems.size()));
        for (auto& item : listItems)
        {
            if (item->viewModelInstance() != nullptr)
            {
                // Write 1 to indicate non-null, then serialize
                writer.writeVarUint(static_cast<uint32_t>(1));
                serializeViewModelInstance(item->viewModelInstance().get(),
                                           writer);
            }
            else
            {
                // Write 0 to indicate null
                writer.writeVarUint(static_cast<uint32_t>(0));
            }
        }
    }
    else if (value->is<ViewModelInstanceViewModel>())
    {
        auto viewModelValue = value->as<ViewModelInstanceViewModel>();
        writer.write(propertyType);
        auto refInstance = viewModelValue->referenceViewModelInstance();
        if (refInstance != nullptr)
        {
            // Write 1 to indicate non-null, then serialize
            writer.writeVarUint(static_cast<uint32_t>(1));
            serializeViewModelInstance(refInstance.get(), writer);
        }
        else
        {
            // Write 0 to indicate null
            writer.writeVarUint(static_cast<uint32_t>(0));
        }
    }
    else if (value->is<ViewModelInstanceSymbolListIndex>())
    {
        auto indexValue = value->as<ViewModelInstanceSymbolListIndex>();
        writer.write(propertyType);
        writer.writeVarUint(static_cast<uint32_t>(indexValue->propertyValue()));
    }
    else if (value->is<ViewModelInstanceAssetImage>())
    {
        auto assetValue = value->as<ViewModelInstanceAssetImage>();
        writer.write(propertyType);
        writer.writeVarUint(static_cast<uint32_t>(assetValue->propertyValue()));
    }
    else if (value->is<ViewModelInstanceAssetFont>())
    {
        auto assetValue = value->as<ViewModelInstanceAssetFont>();
        writer.write(propertyType);
        writer.writeVarUint(static_cast<uint32_t>(assetValue->propertyValue()));
    }
    else if (value->is<ViewModelInstanceArtboard>())
    {
        auto artboardValue = value->as<ViewModelInstanceArtboard>();
        writer.write(propertyType);
        writer.writeVarUint(
            static_cast<uint32_t>(artboardValue->propertyValue()));
    }
}

// Helper function to serialize a ViewModelInstance
static void serializeViewModelInstance(ViewModelInstance* instance,
                                       VectorBinaryWriter& writer)
{
    if (instance == nullptr)
    {
        return;
    }

    // Write viewModel ID
    writer.writeVarUint(static_cast<uint32_t>(instance->viewModelId()));

    // Write property count
    auto propertyValues = instance->propertyValues();
    writer.writeVarUint(static_cast<uint32_t>(propertyValues.size()));

    // Write each property value
    for (auto& value : propertyValues)
    {
        serializeViewModelInstanceValue(value.get(), writer);
    }
}

static void serializeViewModelInstanceToBytesInternal(
    ViewModelInstance* viewModelInstance,
    VectorBinaryWriter& writer)
{
    if (viewModelInstance == nullptr)
    {
        return;
    }

    // Serialize the instance
    serializeViewModelInstance(viewModelInstance, writer);
}

EXPORT void freeViewModelInstanceSerializedData(
    ViewModelInstanceBufferResponse* response)
{
    if (response == nullptr)
    {
        return;
    }
#ifdef __EMSCRIPTEN__
    if (response->data != 0)
#else
    if (response->data != nullptr)
#endif
    {
#ifdef __EMSCRIPTEN__
        free(reinterpret_cast<void*>(response->data));
        response->data = 0;
#else
        free(response->data);
        response->data = nullptr;
#endif
    }
    response->size = 0;
}

#ifdef WITH_RIVE_TOOLS
EXPORT bool serializeViewModelInstanceByPointer(
    File* file,
    ViewModelInstance* instance,
    ViewModelInstanceBufferResponse* response)
{
    if (file == nullptr || instance == nullptr || response == nullptr)
    {
        return false;
    }
    if (!file->containsViewModelInstance(instance))
    {
        return false;
    }
    std::vector<uint8_t> buffer;
    VectorBinaryWriter writer(&buffer);
    serializeViewModelInstanceToBytesInternal(instance, writer);
    if (buffer.empty())
    {
        return false;
    }
    void* buf = malloc(buffer.size());
    if (buf == nullptr)
    {
        return false;
    }
    memcpy(buf, buffer.data(), buffer.size());
#ifdef __EMSCRIPTEN__
    response->data = reinterpret_cast<WasmPtr>(buf);
#else
    response->data = static_cast<uint8_t*>(buf);
#endif
    response->size = buffer.size();
    return true;
}
#endif

EXPORT void clearRuntimeViewModelInstances(File* file)
{
    if (file == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    file->clearRuntimeViewModelInstances();
#endif
}

EXPORT uint32_t riveDataBindDirt(WrappedDataBind* wrappedDataBind)
{
    if (wrappedDataBind == nullptr || wrappedDataBind->dataBind() == nullptr)
    {
        return 0;
    }
    return static_cast<uint32_t>(wrappedDataBind->dataBind()->dirt());
}

EXPORT void riveDataBindSetDirt(WrappedDataBind* wrappedDataBind, uint32_t dirt)
{
    if (wrappedDataBind == nullptr || wrappedDataBind->dataBind() == nullptr)
    {
        return;
    }
    wrappedDataBind->dataBind()->dirt(static_cast<ComponentDirt>(dirt));
}

EXPORT uint32_t riveDataBindFlags(WrappedDataBind* wrappedDataBind)
{
    if (wrappedDataBind == nullptr || wrappedDataBind->dataBind() == nullptr)
    {
        return 0;
    }
    return static_cast<uint32_t>(wrappedDataBind->dataBind()->flags());
}

EXPORT void riveDataBindUpdate(WrappedDataBind* wrappedDataBind, uint32_t dirt)
{
    if (wrappedDataBind == nullptr || wrappedDataBind->dataBind() == nullptr)
    {
        return;
    }
    wrappedDataBind->dataBind()->update(static_cast<ComponentDirt>(dirt));
}

EXPORT void riveDataBindUpdateSourceBinding(WrappedDataBind* wrappedDataBind)
{
    if (wrappedDataBind == nullptr || wrappedDataBind->dataBind() == nullptr)
    {
        return;
    }
    wrappedDataBind->dataBind()->updateSourceBinding();
}

EXPORT void artboardDraw(WrappedArtboard* wrappedArtboard, Renderer* renderer)
{
    if (wrappedArtboard == nullptr || renderer == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->draw(renderer);
}

EXPORT void artboardDrawCanvases(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->drawCanvases();
}

#ifdef WITH_RIVE_SCRIPTING
EXPORT void* artboardGetDrawCanvasLuauState(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    return wrappedArtboard->artboard()->findDrawCanvasLuauState();
}
#endif

EXPORT void artboardDrawInternal(WrappedArtboard* wrappedArtboard,
                                 Renderer* renderer)
{
    if (wrappedArtboard == nullptr || renderer == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->drawInternal(renderer);
}

EXPORT void artboardReset(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->reset();
}

EXPORT SizeType artboardAnimationCount(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0;
    }
    return (SizeType)wrappedArtboard->artboard()->animationCount();
}

EXPORT SizeType artboardStateMachineCount(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0;
    }
    return (SizeType)wrappedArtboard->artboard()->stateMachineCount();
}

EXPORT WrappedLinearAnimation* artboardAnimationAt(
    WrappedArtboard* wrappedArtboard,
    SizeType index)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    std::unique_ptr<LinearAnimationInstance> animation =
        wrappedArtboard->artboard()->animationAt(index);
    if (animation)
    {
        wrappedArtboard->monitorEvents(animation.get());
        return new WrappedLinearAnimation(ref_rcp(wrappedArtboard),
                                          std::move(animation));
    }
    return nullptr;
}

EXPORT WrappedComponent* artboardComponentNamed(
    WrappedArtboard* wrappedArtboard,
    const char* name)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto component =
        wrappedArtboard->artboard()->find<TransformComponent>(name);
    if (component == nullptr)
    {
        return nullptr;
    }
    return new WrappedComponent(ref_rcp(wrappedArtboard), component);
}

EXPORT void deleteComponent(WrappedComponent* wrappedComponent)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedComponent;
}

EXPORT void componentGetWorldTransform(WrappedComponent* wrappedComponent,
                                       float* out)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    const Mat2D& wt = wrappedComponent->component()->worldTransform();
    memcpy(out, &wt, sizeof(float) * 6);
}

EXPORT void componentGetLocalBounds(WrappedComponent* wrappedComponent,
                                    float* out)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    AABB bounds = wrappedComponent->component()->localBounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void componentSetWorldTransform(WrappedComponent* wrappedComponent,
                                       float xx,
                                       float xy,
                                       float yx,
                                       float yy,
                                       float tx,
                                       float ty)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    Mat2D& wt = wrappedComponent->component()->mutableWorldTransform();
    wt[0] = xx;
    wt[1] = xy;
    wt[2] = yx;
    wt[3] = yy;
    wt[4] = tx;
    wt[5] = ty;
}

EXPORT void artboardGetRenderTransform(WrappedArtboard* artboard, float* out)
{
    const Mat2D& wt = artboard->renderTransform;
    memcpy(out, &wt, sizeof(float) * 6);
}

EXPORT void artboardSetRenderTransform(WrappedArtboard* artboard,
                                       float xx,
                                       float xy,
                                       float yx,
                                       float yy,
                                       float tx,
                                       float ty)
{
    Mat2D& wt = artboard->renderTransform;
    wt[0] = xx;
    wt[1] = xy;
    wt[2] = yx;
    wt[3] = yy;
    wt[4] = tx;
    wt[5] = ty;
}

EXPORT float componentGetScaleX(WrappedComponent* wrappedComponent)
{
    if (wrappedComponent == nullptr)
    {
        return 1.0f;
    }
    return wrappedComponent->component()->scaleX();
}

EXPORT void componentSetScaleX(WrappedComponent* wrappedComponent, float value)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    wrappedComponent->component()->scaleX(value);
}

EXPORT float componentGetX(WrappedComponent* wrappedComponent)
{
    if (wrappedComponent == nullptr)
    {
        return 0.0f;
    }
    return wrappedComponent->component()->x();
}

EXPORT void componentSetX(WrappedComponent* wrappedComponent, float value)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    if (wrappedComponent->component()->is<Node>())
    {
        Node* node = wrappedComponent->component()->as<Node>();
        node->x(value);
    }
    else if (wrappedComponent->component()->is<RootBone>())
    {
        RootBone* bone = wrappedComponent->component()->as<RootBone>();
        bone->x(value);
    }
}

EXPORT float componentGetY(WrappedComponent* wrappedComponent)
{
    if (wrappedComponent == nullptr)
    {
        return 0.0f;
    }
    return wrappedComponent->component()->y();
}

EXPORT void componentSetY(WrappedComponent* wrappedComponent, float value)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    auto component = wrappedComponent->component();
    if (component->is<Node>())
    {
        Node* node = component->as<Node>();
        node->y(value);
    }
    else if (component->is<RootBone>())
    {
        RootBone* bone = component->as<RootBone>();
        bone->y(value);
    }
}

EXPORT float componentGetScaleY(WrappedComponent* wrappedComponent)
{
    if (wrappedComponent == nullptr)
    {
        return 1.0f;
    }
    return wrappedComponent->component()->scaleY();
}

EXPORT void componentSetScaleY(WrappedComponent* wrappedComponent, float value)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    wrappedComponent->component()->scaleY(value);
}

EXPORT float componentGetRotation(WrappedComponent* wrappedComponent)
{
    if (wrappedComponent == nullptr)
    {
        return 0.0f;
    }
    return wrappedComponent->component()->rotation();
}

EXPORT void componentSetRotation(WrappedComponent* wrappedComponent,
                                 float value)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    wrappedComponent->component()->rotation(value);
}

EXPORT void componentSetLocalFromWorld(WrappedComponent* wrappedComponent,
                                       float xx,
                                       float xy,
                                       float yx,
                                       float yy,
                                       float tx,
                                       float ty)
{
    if (wrappedComponent == nullptr)
    {
        return;
    }
    auto component = wrappedComponent->component();
    Mat2D world = getParentWorld(*component).invertOrIdentity() *
                  Mat2D(xx, xy, yx, yy, tx, ty);
    TransformComponents components = world.decompose();
    if (component->is<Node>())
    {
        Node* node = component->as<Node>();
        node->x(components.x());
        node->y(components.y());
    }
    else if (component->is<RootBone>())
    {
        RootBone* bone = component->as<RootBone>();
        bone->x(components.x());
        bone->y(components.y());
    }
    component->scaleX(components.scaleX());
    component->scaleY(components.scaleY());
    component->rotation(components.rotation());
}

EXPORT const char* artboardName(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto name = wrappedArtboard->artboard()->name();
    return toCString(name);
}

EXPORT void* artboardGetInnerPointer(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    return static_cast<void*>(wrappedArtboard->artboard());
}

EXPORT WrappedLinearAnimation* artboardAnimationNamed(
    WrappedArtboard* wrappedArtboard,
    const char* name)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    std::unique_ptr<LinearAnimationInstance> animation =
        wrappedArtboard->artboard()->animationNamed(name);
    if (animation)
    {
        wrappedArtboard->monitorEvents(animation.get());
        return new WrappedLinearAnimation(ref_rcp(wrappedArtboard),
                                          std::move(animation));
    }
    return nullptr;
}

EXPORT void artboardSetFrameOrigin(WrappedArtboard* wrappedArtboard,
                                   bool frameOrigin)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->frameOrigin(frameOrigin);
}

EXPORT bool artboardGetFrameOrigin(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return false;
    }
    return wrappedArtboard->artboard()->frameOrigin();
}

// Origin override: a ComponentOrigin child of a nested artboard replaces the
// mounted artboard instance's own origin, mirroring the C++ runtime's
// NestedArtboard::applyOriginOverride.
EXPORT float riveArtboardGetOriginX(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->originX();
}

EXPORT void riveArtboardSetOriginX(WrappedArtboard* wrappedArtboard,
                                   float value)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    auto artboard = wrappedArtboard->artboard();
    artboard->originX(value);
}

EXPORT float riveArtboardGetOriginY(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->originY();
}

EXPORT void riveArtboardSetOriginY(WrappedArtboard* wrappedArtboard,
                                   float value)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    auto artboard = wrappedArtboard->artboard();
    artboard->originY(value);
}

EXPORT const char* animationInstanceName(
    WrappedLinearAnimation* wrappedAnimation)
{
    if (wrappedAnimation == nullptr)
    {
        return nullptr;
    }
    auto name = wrappedAnimation->animation()->name();
    return toCString(name);
}

EXPORT bool animationInstanceAdvance(WrappedLinearAnimation* wrappedAnimation,
                                     float elapsedSeconds,
                                     bool nested)
{
    if (wrappedAnimation == nullptr)
    {
        return false;
    }
    return wrappedAnimation->animation()->advance(elapsedSeconds);
}

EXPORT void animationInstanceApply(WrappedLinearAnimation* wrappedAnimation,
                                   float mix)
{
    if (wrappedAnimation == nullptr)
    {
        return;
    }
    wrappedAnimation->animation()->apply(mix);
}

EXPORT bool animationInstanceAdvanceAndApply(
    WrappedLinearAnimation* wrappedAnimation,
    float elapsedSeconds)
{
    if (wrappedAnimation == nullptr)
    {
        return false;
    }
    return wrappedAnimation->animation()->advanceAndApply(elapsedSeconds);
}

EXPORT float animationInstanceGetLocalSeconds(
    WrappedLinearAnimation* wrappedAnimation,
    float seconds)
{
    if (wrappedAnimation == nullptr)
    {
        return 0.0f;
    }
    return wrappedAnimation->animation()->animation()->globalToLocalSeconds(
        seconds);
}

EXPORT float animationInstanceGetDuration(
    WrappedLinearAnimation* wrappedAnimation,
    float seconds)
{
    if (wrappedAnimation == nullptr)
    {
        return 0.0f;
    }
    return wrappedAnimation->animation()->durationSeconds();
}

EXPORT float animationInstanceGetTime(WrappedLinearAnimation* wrappedAnimation)
{
    if (wrappedAnimation == nullptr)
    {
        return 0.0f;
    }
    return wrappedAnimation->animation()->time();
}

EXPORT void animationInstanceSetTime(WrappedLinearAnimation* wrappedAnimation,
                                     float time)
{
    if (wrappedAnimation == nullptr)
    {
        return;
    }
    wrappedAnimation->animation()->time(time);
}

EXPORT void animationInstanceDelete(WrappedLinearAnimation* wrappedAnimation)
{
    if (wrappedAnimation == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    wrappedAnimation->unref();
}

EXPORT void artboardAddToRenderPath(WrappedArtboard* wrappedArtboard,
                                    RenderPath* renderPath,
                                    float xx,
                                    float xy,
                                    float yx,
                                    float yy,
                                    float tx,
                                    float ty)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->addToRenderPath(renderPath,
                                                 Mat2D(xx, xy, yx, yy, tx, ty));
}

EXPORT void artboardBounds(WrappedArtboard* wrappedArtboard, float* out)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    AABB bounds = wrappedArtboard->artboard()->bounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void artboardLayoutBounds(WrappedArtboard* wrappedArtboard, float* out)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    AABB bounds = wrappedArtboard->artboard()->layoutBounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void artboardWorldBounds(WrappedArtboard* wrappedArtboard, float* out)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    AABB bounds = wrappedArtboard->artboard()->worldBounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void* artboardTakeLayoutNode(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto node = wrappedArtboard->artboard()->takeLayoutData();
#ifdef WITH_RIVE_TOOLS
    node->ref();
#endif
    return node;
}

EXPORT void artboardAddedToHost(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->addedToHost();
}

EXPORT void artboardSyncStyleChanges(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->syncStyleChangesWithUpdate();
}

EXPORT void artboardWidthOverride(WrappedArtboard* wrappedArtboard,
                                  float width,
                                  int widthUnitValue,
                                  bool isRow)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->widthOverride(width, widthUnitValue, isRow);
}

EXPORT void artboardHeightOverride(WrappedArtboard* wrappedArtboard,
                                   float height,
                                   int heightUnitValue,
                                   bool isRow)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->heightOverride(height, heightUnitValue, isRow);
}

EXPORT void artboardParentIsRow(WrappedArtboard* wrappedArtboard, bool isRow)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->parentIsRow(isRow);
}

EXPORT void artboardWidthIntrinsicallySizeOverride(
    WrappedArtboard* wrappedArtboard,
    bool intrinsic)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->widthIntrinsicallySizeOverride(intrinsic);
}

EXPORT void artboardHeightIntrinsicallySizeOverride(
    WrappedArtboard* wrappedArtboard,
    bool intrinsic)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->heightIntrinsicallySizeOverride(intrinsic);
}

EXPORT void updateLayoutBounds(WrappedArtboard* wrappedArtboard, bool animate)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->artboard()->updateLayoutBounds(animate);
}

// Resolves the inherited interpolator for one artboard and applies the cascade.
// The single-artboard export reuses an existing interpolator when the type
// hasn't changed (avoids allocation on repeated calls). The batch export always
// creates fresh, so it passes reuseExisting=false.
static void applyCascadeLayoutStyle(rive::Artboard* artboard,
                                    int direction,
                                    int interpolationType,
                                    float interpolationTime,
                                    int interpolatorTypeKey,
                                    float p0,
                                    float p1,
                                    float p2,
                                    float p3,
                                    bool reuseExisting)
{
    auto& owned = artboard->ownedInheritedInterpolator();

    // Only build the interpolator when the artboard inherits — otherwise the
    // cascade discards inherited values immediately, so the work is wasted.
    KeyFrameInterpolator* interpolator = nullptr;
    if (interpolatorTypeKey != 0 &&
        artboard->animationStyle() == LayoutAnimationStyle::inherit)
    {
        if (!reuseExisting || owned == nullptr ||
            static_cast<int>(owned->coreType()) != interpolatorTypeKey)
        {
            if (interpolatorTypeKey == CubicEaseInterpolatorBase::typeKey ||
                interpolatorTypeKey == CubicInterpolatorBase::typeKey ||
                interpolatorTypeKey == CubicValueInterpolatorBase::typeKey)
            {
                owned = std::make_unique<CubicEaseInterpolator>();
                auto cubic = owned->as<CubicInterpolator>();
                cubic->x1(p0);
                cubic->y1(p1);
                cubic->x2(p2);
                cubic->y2(p3);
                cubic->initialize();
            }
            else if (interpolatorTypeKey == ElasticInterpolatorBase::typeKey)
            {
                owned = std::make_unique<ElasticInterpolator>();
                auto elastic = owned->as<ElasticInterpolator>();
                elastic->easingValue((uint32_t)p0);
                elastic->amplitude(p1);
                elastic->period(p2);
                elastic->initialize();
            }
        }
        else
        {
            // Same type — update values in-place if they changed.
            if (owned->is<CubicInterpolator>())
            {
                auto cubic = owned->as<CubicInterpolator>();
                if (cubic->x1() != p0 || cubic->y1() != p1 ||
                    cubic->x2() != p2 || cubic->y2() != p3)
                {
                    cubic->x1(p0);
                    cubic->y1(p1);
                    cubic->x2(p2);
                    cubic->y2(p3);
                    cubic->initialize();
                }
            }
            else if (owned->is<ElasticInterpolator>())
            {
                auto elastic = owned->as<ElasticInterpolator>();
                if (elastic->easingValue() != (uint32_t)p0 ||
                    elastic->amplitude() != p1 || elastic->period() != p2)
                {
                    elastic->easingValue((uint32_t)p0);
                    elastic->amplitude(p1);
                    elastic->period(p2);
                    elastic->initialize();
                }
            }
        }
        interpolator = owned.get();
    }
    else
    {
        owned = nullptr;
    }

    artboard->cascadeLayoutStyle((LayoutStyleInterpolation)interpolationType,
                                 interpolator,
                                 interpolationTime,
                                 (LayoutDirection)direction);
}

EXPORT void cascadeLayoutStyle(WrappedArtboard* wrappedArtboard,
                               int direction,
                               int interpolationType,
                               float interpolationTime,
                               int interpolatorTypeKey,
                               float p0,
                               float p1,
                               float p2,
                               float p3)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    applyCascadeLayoutStyle(wrappedArtboard->artboard(),
                            direction,
                            interpolationType,
                            interpolationTime,
                            interpolatorTypeKey,
                            p0,
                            p1,
                            p2,
                            p3,
                            /*reuseExisting=*/true);
}

// Batch version: crosses the FFI/WASM boundary once for N artboards.
// artboards is a pointer-to-pointer array of WrappedArtboard instances
// (Pointer<Pointer<Void>> on the Dart side).
EXPORT void cascadeLayoutStyleBatch(void** artboards,
                                    int count,
                                    int direction,
                                    int interpolationType,
                                    float interpolationTime,
                                    int interpolatorTypeKey,
                                    float p0,
                                    float p1,
                                    float p2,
                                    float p3)
{
    for (int i = 0; i < count; i++)
    {
        auto* wrappedArtboard = static_cast<WrappedArtboard*>(artboards[i]);
        if (wrappedArtboard == nullptr)
        {
            continue;
        }
        applyCascadeLayoutStyle(wrappedArtboard->artboard(),
                                direction,
                                interpolationType,
                                interpolationTime,
                                interpolatorTypeKey,
                                p0,
                                p1,
                                p2,
                                p3,
                                /*reuseExisting=*/false);
    }
}

#ifdef WITH_RIVE_TOOLS
// Resolves the collapse for one artboard and applies the cascade.
static void applyCascadeCollapse(rive::Artboard* artboard, bool collapse)
{
    artboard->collapseSingle(collapse);
}

EXPORT void cascadeCollapse(WrappedArtboard* wrappedArtboard, bool collapse)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    applyCascadeCollapse(wrappedArtboard->artboard(), collapse);
}

// Batch version: crosses the FFI/WASM boundary once for N artboards.
// artboards is a pointer-to-pointer array of WrappedArtboard instances
// (Pointer<Pointer<Void>> on the Dart side).
EXPORT void cascadeCollapseBatch(void** artboards, int count, bool collapse)
{
    for (int i = 0; i < count; i++)
    {
        auto* wrappedArtboard = static_cast<WrappedArtboard*>(artboards[i]);
        if (wrappedArtboard == nullptr)
        {
            continue;
        }
        applyCascadeCollapse(wrappedArtboard->artboard(), collapse);
    }
}
#endif

EXPORT bool riveArtboardAdvance(WrappedArtboard* wrappedArtboard,
                                float seconds,
                                int flags)
{
    if (wrappedArtboard == nullptr)
    {
        return false;
    }
    return wrappedArtboard->artboard()->advanceInternal(seconds,
                                                        (AdvanceFlags)flags);
}

EXPORT float riveArtboardGetOpacity(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->opacity();
}

EXPORT bool riveArtboardUpdatePass(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return false;
    }
    return wrappedArtboard->artboard()->updatePass(false);
}

EXPORT bool riveArtboardHasComponentDirt(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return false;
    }
    return wrappedArtboard->artboard()->hasDirt(ComponentDirt::Components);
}

EXPORT void riveArtboardSetOpacity(WrappedArtboard* wrappedArtboard,
                                   float opacity)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    return wrappedArtboard->artboard()->opacity(opacity);
}

EXPORT void riveArtboardSetHostOpacity(WrappedArtboard* wrappedArtboard,
                                       float hostOpacity)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    return wrappedArtboard->artboard()->hostOpacity(hostOpacity);
}

EXPORT float riveArtboardGetWidth(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->width();
}

EXPORT void riveArtboardSetWidth(WrappedArtboard* wrappedArtboard, float width)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    return wrappedArtboard->artboard()->width(width);
}

EXPORT float riveArtboardGetHeight(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->height();
}

EXPORT void riveArtboardSetHeight(WrappedArtboard* wrappedArtboard,
                                  float height)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    return wrappedArtboard->artboard()->height(height);
}

EXPORT float riveArtboardGetOriginalWidth(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->originalWidth();
}

EXPORT float riveArtboardGetOriginalHeight(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return 0.0f;
    }
    return wrappedArtboard->artboard()->originalHeight();
}

EXPORT WrappedStateMachine* riveArtboardStateMachineDefault(
    WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto smi = wrappedArtboard->artboard()->defaultStateMachine();
    if (smi == nullptr)
    {
        smi = wrappedArtboard->artboard()->stateMachineAt(0);
    }
    if (smi != nullptr)
    {
        wrappedArtboard->monitorEvents(smi.get());
        return new WrappedStateMachine(ref_rcp(wrappedArtboard),
                                       std::move(smi));
    }
    return nullptr;
}

EXPORT WrappedStateMachine* riveArtboardStateMachineNamed(
    WrappedArtboard* wrappedArtboard,
    const char* name)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }
    auto smi = wrappedArtboard->artboard()->stateMachineNamed(name);
    if (smi != nullptr)
    {
        wrappedArtboard->monitorEvents(smi.get());
        return new WrappedStateMachine(ref_rcp(wrappedArtboard),
                                       std::move(smi));
    }
    return nullptr;
}

EXPORT WrappedStateMachine* riveArtboardStateMachineAt(
    WrappedArtboard* wrappedArtboard,
    SizeType index)
{
    if (wrappedArtboard == nullptr)
    {
        return nullptr;
    }

    auto smi = wrappedArtboard->artboard()->stateMachineAt(index);
    if (smi != nullptr)
    {
        wrappedArtboard->monitorEvents(smi.get());
        return new WrappedStateMachine(ref_rcp(wrappedArtboard),
                                       std::move(smi));
    }
    return nullptr;
}

EXPORT bool artboardSetText(WrappedArtboard* wrappedArtboard,
                            const char* name,
                            const char* value,
                            const char* path)
{
    if (wrappedArtboard == nullptr || name == nullptr || value == nullptr)
    {
        return false;
    }
    auto textRun = (path != nullptr)
                       ? wrappedArtboard->artboard()->getTextRun(name, path)
                       : wrappedArtboard->artboard()->find<TextValueRun>(name);
    if (textRun == nullptr)
    {
        return false;
    }
    textRun->text(value);
    return true;
}

EXPORT const char* artboardGetText(WrappedArtboard* wrappedArtboard,
                                   const char* name,
                                   const char* path)
{
    if (wrappedArtboard == nullptr || name == nullptr)
    {
        return nullptr;
    }
    auto textRun = (path != nullptr)
                       ? wrappedArtboard->artboard()->getTextRun(name, path)
                       : wrappedArtboard->artboard()->find<TextValueRun>(name);
    if (textRun == nullptr)
    {
        return nullptr;
    }
    return textRun->text().c_str();
}

struct TextRunWithPath
{
    TextValueRun* textRun;
    std::string path;
};

// Helper to recursively collect text runs from an artboard and all nested
// artboards
static void collectTextRunsRecursive(ArtboardInstance* artboard,
                                     WrappedArtboard* wrappedArtboard,
                                     std::vector<TextRunWithPath>& allTextRuns,
                                     const std::string& currentPath)
{
    if (!artboard)
    {
        return;
    }
    std::vector<TextValueRun*> textRuns = artboard->find<TextValueRun>();
    for (auto* textRun : textRuns)
    {
        allTextRuns.push_back({textRun, currentPath});
    }
    std::vector<NestedArtboard*> nestedArtboards =
        artboard->find<NestedArtboard>();
    for (auto* nestedArtboard : nestedArtboards)
    {
        if (nestedArtboard)
        {
            ArtboardInstance* nestedInstance =
                nestedArtboard->artboardInstance();
            if (nestedInstance)
            {
                std::string nestedPath = currentPath;
                if (!nestedPath.empty())
                {
                    nestedPath += "/";
                }
                nestedPath += nestedArtboard->name();

                collectTextRunsRecursive(nestedInstance,
                                         wrappedArtboard,
                                         allTextRuns,
                                         nestedPath);
            }
        }
    }
}

static WrappedTextValueRun** getAllTextRunsImpl(
    WrappedArtboard* wrappedArtboard,
    int* count)
{
    if (wrappedArtboard == nullptr || count == nullptr)
    {
        if (count)
            *count = 0;
        return nullptr;
    }

    auto artboard = wrappedArtboard->artboard();
    if (!artboard)
    {
        *count = 0;
        return nullptr;
    }

    std::vector<TextRunWithPath> allTextRuns;
    collectTextRunsRecursive(artboard, wrappedArtboard, allTextRuns, "");

    *count = static_cast<int>(allTextRuns.size());
    if (allTextRuns.empty())
    {
        return nullptr;
    }

    // Caller is responsible for freeing the array and deleting each wrapper
    WrappedTextValueRun** arr = (WrappedTextValueRun**)std::malloc(
        sizeof(WrappedTextValueRun*) * allTextRuns.size());
    if (!arr)
    {
        *count = 0;
        return nullptr;
    }
    for (size_t i = 0; i < allTextRuns.size(); ++i)
    {
        arr[i] = new WrappedTextValueRun(ref_rcp(wrappedArtboard),
                                         allTextRuns[i].textRun,
                                         allTextRuns[i].path);
    }
    return arr;
}

#ifdef __EMSCRIPTEN__
// WASM-specific struct to return array pointer and count together
struct TextRunArrayResult
{
    WasmPtr array;
    int count;
};

EXPORT TextRunArrayResult artboardGetAllTextRuns(WasmPtr artboardPtr)
{
    WrappedArtboard* wrappedArtboard = (WrappedArtboard*)artboardPtr;
    int count = 0;
    WrappedTextValueRun** arr = getAllTextRunsImpl(wrappedArtboard, &count);
    TextRunArrayResult result;
    result.array = (WasmPtr)arr;
    result.count = count;
    return result;
}
#else
// Native FFI version: Uses output parameter for count
EXPORT WrappedTextValueRun** artboardGetAllTextRuns(
    WrappedArtboard* wrappedArtboard,
    int* count)
{
    return getAllTextRunsImpl(wrappedArtboard, count);
}
#endif

// Frees the array allocated by artboardGetAllTextRuns (but not the individual
// wrappers)
EXPORT void freeTextRunsArray(WrappedTextValueRun** arr)
{
    if (arr != nullptr)
    {
        std::free(arr);
    }
}

// Helper function for WASM to get an element from the text runs array
EXPORT WrappedTextValueRun* getTextRunFromArray(WrappedTextValueRun** arr,
                                                int index)
{
    if (arr == nullptr)
    {
        return nullptr;
    }
    return arr[index];
}

EXPORT void deleteTextValueRun(WrappedTextValueRun* wrappedTextRun)
{
    if (wrappedTextRun == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedTextRun;
}

EXPORT const char* textValueRunName(WrappedTextValueRun* wrappedTextRun)
{
    if (wrappedTextRun == nullptr)
    {
        return nullptr;
    }
    return wrappedTextRun->textValueRun()->name().c_str();
}

EXPORT const char* textValueRunText(WrappedTextValueRun* wrappedTextRun)
{
    if (wrappedTextRun == nullptr)
    {
        return nullptr;
    }
    return wrappedTextRun->textValueRun()->text().c_str();
}

EXPORT void textValueRunSetText(WrappedTextValueRun* wrappedTextRun,
                                const char* text)
{
    if (wrappedTextRun == nullptr || text == nullptr)
    {
        return;
    }
    wrappedTextRun->textValueRun()->text(std::string(text));
}

EXPORT const char* textValueRunPath(WrappedTextValueRun* wrappedTextRun)
{
    if (wrappedTextRun == nullptr)
    {
        return nullptr;
    }
    return wrappedTextRun->path().c_str();
}

EXPORT const char* stateMachineInstanceName(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
    {
        return nullptr;
    }
    auto name = wrappedMachine->stateMachine()->name();
    return toCString(name);
}

EXPORT bool stateMachineInstanceAdvance(WrappedStateMachine* wrappedMachine,
                                        float elapsedSeconds,
                                        bool newFrame)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return wrappedMachine->stateMachine()->advance(elapsedSeconds, newFrame);
}

// ---------------------------------------------------------------------------
// State-transition record flush: serialize RiveProfile's collected records
// into g_eventBuffer as 0x04 (string table delta) + 0x03 records (grouped by
// artboard+SM, id-based). Callback is set in profilerStart().
// ---------------------------------------------------------------------------
#ifdef RIVE_MICROPROFILE
static size_t g_lastSentStringTableSize = 0;

static void flushTransitionRecordsToEventBuffer(
    const std::vector<rive::TransitionRecord>& records)
{
    if (records.empty())
    {
        return;
    }
    const std::vector<std::string>& stringTable =
        rive::RiveProfile::instance().getStringTable();
    std::lock_guard<std::mutex> lock(g_eventBufferMutex);
    rive::VectorBinaryWriter ew(&g_eventBuffer);

    // Emit 0x04 string table with new entries only
    if (stringTable.size() > g_lastSentStringTableSize)
    {
        const size_t count = stringTable.size();
        ew.write(static_cast<uint8_t>(0x04));
        std::vector<uint8_t> stPayload;
        rive::VectorBinaryWriter stw(&stPayload);
        stw.writeVarUint(static_cast<uint32_t>(count));
        for (size_t i = 0; i < stringTable.size(); i++)
        {
            stw.write(stringTable[i]);
        }
        ew.writeVarUint(static_cast<uint32_t>(stPayload.size()));
        ew.write(stPayload.data(), stPayload.size());
        g_lastSentStringTableSize = stringTable.size();
    }

    // Group by (artboardId, smId)
    std::map<std::pair<uint32_t, uint32_t>, std::vector<size_t>> groups;
    for (size_t i = 0; i < records.size(); ++i)
    {
        const auto& rec = records[i];
        groups[{rec.artboardId, rec.smId}].push_back(i);
    }
    for (const auto& kv : groups)
    {
        const auto& indices = kv.second;
        std::vector<uint8_t> payload;
        rive::VectorBinaryWriter pw(&payload);
        writeInt64(pw, static_cast<int64_t>(records[indices[0]].tick));
        pw.writeVarUint(static_cast<uint32_t>(indices.size()));
        for (size_t idx : indices)
        {
            const auto& rec = records[idx];
            std::vector<uint8_t> recPayload;
            rive::VectorBinaryWriter rpw(&recPayload);
            rpw.writeVarUint(rec.artboardId);
            rpw.writeVarUint(rec.smId);
            rpw.writeVarUint(rec.layerId);
            rpw.writeVarUint(rec.fromStateId);
            rpw.writeVarUint(rec.toStateId);
            // Path: segment count, then per segment [segmentLength, type,
            // nameId, optional index]
            rpw.writeVarUint(static_cast<uint32_t>(rec.path.size()));
            for (const auto& seg : rec.path)
            {
                std::vector<uint8_t> segPayload;
                rive::VectorBinaryWriter spw(&segPayload);
                spw.write(static_cast<uint8_t>(seg.type));
                spw.writeVarUint(seg.nameId);
                if (seg.type == 1)
                {
                    // Encode index: 0 = -1, otherwise index+1
                    spw.writeVarUint(
                        seg.index < 0 ? 0u
                                      : static_cast<uint32_t>(seg.index + 1));
                }
                rpw.writeVarUint(static_cast<uint32_t>(segPayload.size()));
                rpw.write(segPayload.data(), segPayload.size());
            }
            pw.writeVarUint(static_cast<uint32_t>(recPayload.size()));
            pw.write(recPayload.data(), recPayload.size());
        }
        ew.write(static_cast<uint8_t>(0x03));
        ew.writeVarUint(static_cast<uint32_t>(payload.size()));
        ew.write(payload.data(), payload.size());
    }
}

static void flushListenerPerformChangeRecordsToEventBuffer(
    const std::vector<rive::ListenerPerformChangeRecord>& records)
{
    if (records.empty())
    {
        return;
    }
    std::lock_guard<std::mutex> lock(g_eventBufferMutex);
    rive::VectorBinaryWriter ew(&g_eventBuffer);

    // 0x04 string table is already emitted by
    // flushTransitionRecordsToEventBuffer when needed; we use the same table.
    // Emit 0x05 listener perform change batch (length+content per entry).
    std::vector<uint8_t> payload;
    rive::VectorBinaryWriter pw(&payload);
    writeInt64(pw, static_cast<int64_t>(records[0].tick));
    pw.writeVarUint(static_cast<uint32_t>(records.size()));
    for (const auto& rec : records)
    {
        std::vector<uint8_t> recPayload;
        rive::VectorBinaryWriter rpw(&recPayload);
        rpw.writeVarUint(rec.artboardId);
        rpw.writeVarUint(rec.smId);
        rpw.writeVarUint(rec.listenerNameId);
        rpw.writeVarUint(rec.listenerType);
        rpw.writeVarUint(rec.hitEvent);
        rpw.writeVarUint(rec.pointerId);
        pw.writeVarUint(static_cast<uint32_t>(recPayload.size()));
        pw.write(recPayload.data(), recPayload.size());
    }
    ew.write(static_cast<uint8_t>(0x05));
    ew.writeVarUint(static_cast<uint32_t>(payload.size()));
    ew.write(payload.data(), payload.size());
}
#endif

EXPORT bool stateMachineInstanceAdvanceAndApply(
    WrappedStateMachine* wrappedMachine,
    float elapsedSeconds)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    auto result =
        wrappedMachine->stateMachine()->advanceAndApply(elapsedSeconds);
#ifdef RIVE_MICROPROFILE
    if (rive::RiveProfile::instance().isActive())
    {
        rive::RiveProfile::instance().flushTransitionRecords();
        rive::RiveProfile::instance().flushListenerPerformChangeRecords();
    }
#endif
    return result;
}

EXPORT SizeType
stateMachineInstanceStateChangedCount(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
    {
        return 0;
    }
    return (SizeType)wrappedMachine->stateMachine()->stateChangedCount();
}

// Return state name/type string for the Nth changed state. Caller must free
// (freeString). Only AnimationState has a name (from its animation); Entry,
// Exit, Any, and Blend states have no name in the runtime, so we use type
// labels for those.
EXPORT const char* stateMachineInstanceStateChangedNameByIndex(
    WrappedStateMachine* wrappedMachine,
    SizeType index)
{
    if (wrappedMachine == nullptr)
    {
        return nullptr;
    }
    const LayerState* state =
        wrappedMachine->stateMachine()->stateChangedByIndex(index);
    if (state == nullptr)
    {
        return toCString(std::string("unknown"));
    }
    if (state->is<AnimationState>())
    {
        const AnimationState* animState = state->as<AnimationState>();
        const LinearAnimation* animation = animState->animation();
        if (animation != nullptr)
        {
            return toCString(animation->name());
        }
        return toCString(std::string("Unknown"));
    }
    if (state->is<EntryState>())
        return toCString(std::string("entry"));
    if (state->is<ExitState>())
        return toCString(std::string("exit"));
    if (state->is<AnyState>())
        return toCString(std::string("any"));
    if (state->is<BlendStateDirect>())
        return toCString(std::string("blendDirect"));
    if (state->is<BlendState1D>())
        return toCString(std::string("blend1d"));
    if (state->is<BlendState>())
        return toCString(std::string("blend"));
    return toCString(std::string("unknown"));
}

EXPORT bool stateMachineInstanceHitTest(WrappedStateMachine* wrappedMachine,
                                        float x,
                                        float y)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return wrappedMachine->stateMachine()->hitTest(Vec2D(x, y));
}

EXPORT uint8_t
stateMachineInstancePointerDown(WrappedStateMachine* wrappedMachine,
                                float x,
                                float y,
                                int pointerId)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->pointerDown(Vec2D(x, y),
                                                                pointerId);
}

EXPORT uint8_t
stateMachineInstancePointerExit(WrappedStateMachine* wrappedMachine,
                                float x,
                                float y,
                                int pointerId)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->pointerExit(Vec2D(x, y),
                                                                pointerId);
}

EXPORT uint8_t
stateMachineInstancePointerMove(WrappedStateMachine* wrappedMachine,
                                float x,
                                float y,
                                float timeStamp,
                                int pointerId)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->pointerMove(Vec2D(x, y),
                                                                timeStamp,
                                                                pointerId);
}

EXPORT uint8_t
stateMachineInstancePointerUp(WrappedStateMachine* wrappedMachine,
                              float x,
                              float y,
                              int pointerId)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->pointerUp(Vec2D(x, y),
                                                              pointerId);
}

EXPORT uint8_t
stateMachineInstanceDragStart(WrappedStateMachine* wrappedMachine,
                              float x,
                              float y,
                              float timeStamp)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->dragStart(Vec2D(x, y),
                                                              timeStamp);
}

EXPORT uint8_t stateMachineInstanceDragEnd(WrappedStateMachine* wrappedMachine,
                                           float x,
                                           float y,
                                           float timeStamp)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return (uint8_t)wrappedMachine->stateMachine()->dragEnd(Vec2D(x, y),
                                                            timeStamp);
}

EXPORT bool stateMachineInstanceSubmitGamepadsFromBuffer(
    WrappedStateMachine* wrappedMachine,
    const uint8_t* data,
    uint64_t length)
{
    if (wrappedMachine == nullptr || data == nullptr)
    {
        return false;
    }
    return wrappedMachine->stateMachine()->submitGamepadsFromBuffer(
        data,
        static_cast<size_t>(length));
}

// Build a heap-owned `ListenerInvocation` from raw gamepad fields so the
// embedder can dispatch the same invocation to multiple state machine
// instances without re-decoding the wire format. Mirrors the
// fillStandardIntent logic from `gamepad_batch.cpp:26-54` for event-kind
// invocations.
EXPORT void* makeGamepadInvocation(uint8_t kind,
                                   int32_t deviceId,
                                   uint64_t buttonMask,
                                   const float* buttonValues,
                                   uint64_t buttonCount,
                                   const float* axes,
                                   uint64_t axisCount,
                                   uint8_t mapping,
                                   uint8_t changeKind,
                                   uint8_t changeIndex,
                                   float changeValue)
{
    if (kind == 2)
    {
        return new ListenerInvocation(
            ListenerInvocation::gamepadDisconnected(deviceId));
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
        return new ListenerInvocation(
            ListenerInvocation::gamepadConnected(snapshot));
    }

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
    return new ListenerInvocation(
        ListenerInvocation::gamepadEvent(std::move(ev)));
}

EXPORT void deleteGamepadInvocation(void* invocation)
{
    if (invocation == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete static_cast<ListenerInvocation*>(invocation);
}

// Dispatch a pre-built gamepad invocation to a state machine using the
// same focus-bubble + scripted-drawable broadcast that
// `submitGamepadsFromBuffer` performs internally, but without touching
// `m_embedderGamepads`. Lets the embedder build a single invocation and
// fan it out to many nested instances.
EXPORT void stateMachineInstanceDispatchGamepadInvocation(
    WrappedStateMachine* wrappedMachine,
    void* invocation)
{
    if (wrappedMachine == nullptr || invocation == nullptr)
    {
        return;
    }
    auto* smi = wrappedMachine->stateMachine();
    if (smi == nullptr)
    {
        return;
    }
    auto* inv = static_cast<ListenerInvocation*>(invocation);
    ScriptedDrawable* dispatched = nullptr;
    if (auto* fm = smi->focusManager())
    {
        fm->gamepadDispatch(*inv, &dispatched);
    }
    smi->broadcastGamepadToScriptedDrawables(*inv, dispatched);
}

EXPORT size_t
stateMachineGetReportedEventCount(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
    {
        return 0;
    }
    return wrappedMachine->stateMachine()->reportedEventCount();
}

#ifdef __EMSCRIPTEN__
struct FlutterRuntimeReportedEvent
{
    WasmPtr event;
    float secondsDelay;
    uint16_t type;
};
struct FlutterRuntimeCustomProperty
{
    WasmPtr property;
    WasmPtr name;
    uint16_t type;
};

FlutterRuntimeReportedEvent stateMachineReportedEventAt(WasmPtr machinePtr,
                                                        const size_t index)
{
    WrappedStateMachine* wrappedMachine = (WrappedStateMachine*)machinePtr;
    if (wrappedMachine == nullptr || wrappedMachine->stateMachine() == nullptr)
    {
        return {(WasmPtr) nullptr, 0.0f, 0};
    }

    auto eventReport = wrappedMachine->stateMachine()->reportedEventAt(index);
    auto wrappedEvent =
        new WrappedEvent(ref_rcp(wrappedMachine), eventReport.event());
    return {(WasmPtr)(wrappedEvent),
            eventReport.secondsDelay(),
            eventReport.event()->coreType()};
}

EXPORT FlutterRuntimeCustomProperty getEventCustomProperty(WasmPtr eventPtr,
                                                           std::size_t index)
{
    WrappedEvent* wrappedEvent = (WrappedEvent*)eventPtr;
    if (wrappedEvent == nullptr || wrappedEvent->event() == nullptr)
    {
        return {(WasmPtr) nullptr, (WasmPtr) nullptr, 0};
    }
    Event* event = wrappedEvent->event();
    std::size_t count = 0;
    for (auto child : event->children())
    {
        if (child->is<CustomProperty>() && count++ == index)
        {
            CustomProperty* property = child->as<CustomProperty>();
            auto wrappedProperty =
                new WrappedCustomProperty(ref_rcp(wrappedEvent), property);
            return {(WasmPtr)(wrappedProperty),
                    (WasmPtr)(property->name().c_str()),
                    property->coreType()};
        }
    }
    return {(WasmPtr) nullptr, (WasmPtr) nullptr, 0};
}
#else
struct FlutterRuntimeReportedEvent
{
    WrappedEvent* event;
    float secondsDelay;
    uint16_t type;
};
struct FlutterRuntimeCustomProperty
{
    WrappedCustomProperty* property;
    const char* name;
    uint16_t type;
};

EXPORT FlutterRuntimeReportedEvent
stateMachineReportedEventAt(WrappedStateMachine* wrappedMachine,
                            const size_t index)
{
    if (wrappedMachine == nullptr || wrappedMachine->stateMachine() == nullptr)
    {
        return {nullptr, 0.0f, 0};
    }

    auto eventReport = wrappedMachine->stateMachine()->reportedEventAt(index);
    auto wrappedEvent =
        new WrappedEvent(ref_rcp(wrappedMachine), eventReport.event());
    return {wrappedEvent,
            eventReport.secondsDelay(),
            eventReport.event()->coreType()};
}

EXPORT FlutterRuntimeCustomProperty
getEventCustomProperty(WrappedEvent* wrappedEvent, std::size_t index)
{
    std::size_t count = 0;
    for (auto child : wrappedEvent->event()->children())
    {
        if (child->is<CustomProperty>() && count++ == index)
        {
            CustomProperty* property = child->as<CustomProperty>();
            auto wrappedPropety =
                new WrappedCustomProperty(ref_rcp(wrappedEvent), property);
            return {wrappedPropety,
                    property->name().c_str(),
                    property->coreType()};
        }
    }
    return {nullptr, nullptr, 0};
}
#endif

EXPORT void deleteEvent(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    wrappedEvent->unref();
}

EXPORT void deleteCustomProperty(WrappedCustomProperty* wrappedCustomProperty)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedCustomProperty;
}

EXPORT const char* getEventName(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr)
    {
        return nullptr;
    }
    return wrappedEvent->event()->name().c_str();
}

EXPORT uint32_t getOpenUrlEventTarget(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr)
    {
        return 0;
    }
    auto openUrlEvent = static_cast<rive::OpenUrlEvent*>(wrappedEvent->event());
    if (openUrlEvent)
    {
        return openUrlEvent->targetValue();
    }
    return 0;
}

EXPORT const char* getOpenUrlEventUrl(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr)
    {
        return nullptr;
    }
    auto openUrlEvent = static_cast<rive::OpenUrlEvent*>(wrappedEvent->event());
    if (openUrlEvent)
    {
        return openUrlEvent->url().c_str();
    }
    return nullptr;
}

EXPORT uint32_t getAudioEventAssetId(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr || wrappedEvent->event() == nullptr ||
        !wrappedEvent->event()->is<rive::AudioEvent>())
    {
        return 0;
    }
    return wrappedEvent->event()->as<rive::AudioEvent>()->assetId();
}

EXPORT const char* getAudioEventAssetName(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr || wrappedEvent->event() == nullptr ||
        !wrappedEvent->event()->is<rive::AudioEvent>())
    {
        return nullptr;
    }
    auto asset = wrappedEvent->event()->as<rive::AudioEvent>()->asset();
    if (asset == nullptr)
    {
        return nullptr;
    }
    return asset->name().c_str();
}

EXPORT float getAudioEventVolume(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr || wrappedEvent->event() == nullptr ||
        !wrappedEvent->event()->is<rive::AudioEvent>())
    {
        return 0.0f;
    }
    auto asset = wrappedEvent->event()->as<rive::AudioEvent>()->asset();
    if (asset == nullptr || !asset->is<rive::AudioAsset>())
    {
        return 0.0f;
    }
    return asset->as<rive::AudioAsset>()->volume();
}

EXPORT std::size_t getEventCustomPropertyCount(WrappedEvent* wrappedEvent)
{
    if (wrappedEvent == nullptr || wrappedEvent->event() == nullptr)
    {
        return 0;
    }
    std::size_t count = 0;
    for (auto child : wrappedEvent->event()->children())
    {
        if (child->is<CustomProperty>())
        {
            count++;
        }
    }
    return count;
}

EXPORT float getCustomPropertyNumber(WrappedCustomProperty* wrappedProperty)
{
    if (wrappedProperty == nullptr)
    {
        return 0.0f;
    }
    auto property = wrappedProperty->customProperty();
    if (property->is<CustomPropertyNumber>())
    {
        return property->as<CustomPropertyNumber>()->propertyValue();
    }
    return 0.0f;
}

EXPORT bool getCustomPropertyBoolean(WrappedCustomProperty* wrappedProperty)
{
    if (wrappedProperty == nullptr)
    {
        return false;
    }
    auto property = wrappedProperty->customProperty();
    if (property->is<CustomPropertyBoolean>())
    {
        return property->as<CustomPropertyBoolean>()->propertyValue();
    }
    return false;
}

EXPORT const char* getCustomPropertyString(
    WrappedCustomProperty* wrappedProperty)
{
    if (wrappedProperty == nullptr)
    {
        return nullptr;
    }
    auto property = wrappedProperty->customProperty();
    if (property->is<CustomPropertyString>())
    {
        return property->as<CustomPropertyString>()->propertyValue().c_str();
    }
    return nullptr;
}

#if defined(__EMSCRIPTEN__)
static void _webLayoutChanged(void* artboardPtr)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webLayoutChangedCallbacks.find(artboard);
    if (itr != _webLayoutChangedCallbacks.end())
    {
        itr->second();
    }
}

static void _webLayoutDirty(void* artboardPtr)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webLayoutDirtyCallbacks.find(artboard);
    if (itr != _webLayoutDirtyCallbacks.end())
    {
        itr->second();
    }
}

static void _webTransformDirty(void* artboardPtr)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webTransformDirtyCallbacks.find(artboard);
    if (itr != _webTransformDirtyCallbacks.end())
    {
        itr->second();
    }
}

static void _webEvent(WrappedArtboard* artboard, uint32_t id)
{
    auto itr = _webEventCallbacks.find(artboard);
    if (itr != _webEventCallbacks.end())
    {
        itr->second(id);
    }
}

static void _webInputChanged(StateMachineInstance* stateMachine, uint64_t index)
{
    auto itr = _webInputChangedCallbacks.find(stateMachine);
    if (itr != _webInputChangedCallbacks.end())
    {
        itr->second((uint32_t)index);
    }
}

static void _webDataBindChanged()
{
    for (auto it : _webDataBindChangedCallbacks)
    {
        it.second();
    }
}

static uint8_t _webTestBounds(void* artboardPtr, float x, float y, bool skip)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webTestBoundsCallbacks.find(artboard);
    if (itr != _webTestBoundsCallbacks.end())
    {
        auto result = itr->second(x, y, skip);
        return result.as<uint8_t>();
    }
    return 1;
}

static uint8_t _webIsAncestor(void* artboardPtr, uint16_t artboardId)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webIsAncestorCallbacks.find(artboard);
    if (itr != _webIsAncestorCallbacks.end())
    {
        auto result = itr->second(artboardId);
        return result.as<uint8_t>();
    }
    return 1;
}

static float _webRootTransform(void* artboardPtr, float x, float y, bool xAxis)
{
    auto artboard = static_cast<WrappedArtboard*>(artboardPtr);
    auto itr = _webRootTransformCallbacks.find(artboard);
    if (itr != _webRootTransformCallbacks.end())
    {
        auto result = itr->second(x, y, xAxis);
        return result.as<float>();
    }
    return 0.0f;
}

EXPORT void setArtboardLayoutChangedCallback(
    WasmPtr artboardPtr,
    emscripten::val layoutChangedCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (layoutChangedCallback.isNull())
    {
        _webLayoutChangedCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onLayoutChanged(nullptr);
#endif
    }
    else
    {
        _webLayoutChangedCallbacks[wrappedArtboard] = layoutChangedCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onLayoutChanged(_webLayoutChanged);
#endif
    }
}

EXPORT void setArtboardTestBoundsCallback(WasmPtr artboardPtr,
                                          emscripten::val testBoundsCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (testBoundsCallback.isNull())
    {
        _webTestBoundsCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onTestBounds(nullptr);
#endif
    }
    else
    {
        _webTestBoundsCallbacks[wrappedArtboard] = testBoundsCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onTestBounds(_webTestBounds);
#endif
    }
}

EXPORT void setArtboardIsAncestorCallback(WasmPtr artboardPtr,
                                          emscripten::val isAncestorCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (isAncestorCallback.isNull())
    {
        _webIsAncestorCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onIsAncestor(nullptr);
#endif
    }
    else
    {
        _webIsAncestorCallbacks[wrappedArtboard] = isAncestorCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onIsAncestor(_webIsAncestor);
#endif
    }
}

EXPORT void setArtboardRootTransformCallback(
    WasmPtr artboardPtr,
    emscripten::val rootTransformCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (rootTransformCallback.isNull())
    {
        _webRootTransformCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onRootTransform(nullptr);
#endif
    }
    else
    {
        _webRootTransformCallbacks[wrappedArtboard] = rootTransformCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onRootTransform(_webRootTransform);
#endif
    }
}

EXPORT void setArtboardLayoutDirtyCallback(WasmPtr artboardPtr,
                                           emscripten::val layoutDirtyCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (layoutDirtyCallback.isNull())
    {
        _webLayoutDirtyCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onLayoutDirty(nullptr);
#endif
    }
    else
    {
        _webLayoutDirtyCallbacks[wrappedArtboard] = layoutDirtyCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onLayoutDirty(_webLayoutDirty);
#endif
    }
}

EXPORT void setArtboardTransformDirtyCallback(
    WasmPtr artboardPtr,
    emscripten::val transformDirtyCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    if (transformDirtyCallback.isNull())
    {
        _webTransformDirtyCallbacks.erase(wrappedArtboard);
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onTransformDirty(nullptr);
#endif
    }
    else
    {
        _webTransformDirtyCallbacks[wrappedArtboard] = transformDirtyCallback;
#ifdef WITH_RIVE_TOOLS
        wrappedArtboard->artboard()->onTransformDirty(_webTransformDirty);
#endif
    }
}

EXPORT void setArtboardEventCallback(WasmPtr artboardPtr,
                                     emscripten::val eventCallback)
{
    auto wrappedArtboard = (WrappedArtboard*)artboardPtr;
    if (wrappedArtboard == nullptr)
    {
        return;
    }

    if (eventCallback.isNull())
    {
        _webEventCallbacks.erase(wrappedArtboard);
        wrappedArtboard->m_eventCallback = nullptr;
    }
    else
    {
        _webEventCallbacks[wrappedArtboard] = eventCallback;
        wrappedArtboard->m_eventCallback = _webEvent;
    }
}

EXPORT void setStateMachineInputChangedCallback(WasmPtr smiPtr,
                                                emscripten::val changedCallback)
{
    auto wrappedMachine = (WrappedStateMachine*)smiPtr;
    if (wrappedMachine == nullptr)
    {
        return;
    }
    auto smi = wrappedMachine->stateMachine();
    if (changedCallback.isNull())
    {
        _webInputChangedCallbacks.erase(smi);
#ifdef WITH_RIVE_TOOLS
        smi->onInputChanged(nullptr);
#endif
    }
    else
    {
        _webInputChangedCallbacks[smi] = changedCallback;
#ifdef WITH_RIVE_TOOLS
        smi->onInputChanged(_webInputChanged);
#endif
    }
}

static void setStateMachineDataBindChangedCallback(
    WasmPtr smiPtr,
    emscripten::val changedCallback)
{
    auto wrappedMachine = (WrappedStateMachine*)smiPtr;
    if (wrappedMachine == nullptr)
    {
        return;
    }
    auto smi = wrappedMachine->stateMachine();
    if (changedCallback.isNull())
    {
        _webDataBindChangedCallbacks.erase(smi);
#ifdef WITH_RIVE_TOOLS
        smi->onDataBindChanged(nullptr);
#endif
    }
    else
    {
        _webDataBindChangedCallbacks[smi] = changedCallback;
#ifdef WITH_RIVE_TOOLS
        smi->onDataBindChanged(_webDataBindChanged);
#endif
    }
}
#else
EXPORT void setArtboardEventCallback(WrappedArtboard* wrappedArtboard,
                                     EventCallback eventCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
    wrappedArtboard->m_eventCallback = eventCallback;
}

EXPORT void setArtboardLayoutChangedCallback(
    WrappedArtboard* wrappedArtboard,
    ArtboardCallback layoutChangedCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onLayoutChanged(layoutChangedCallback);
#endif
}

EXPORT void setArtboardTestBoundsCallback(WrappedArtboard* wrappedArtboard,
                                          TestBoundsCallback testBoundsCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onTestBounds(testBoundsCallback);
#endif
}

EXPORT void setArtboardIsAncestorCallback(WrappedArtboard* wrappedArtboard,
                                          IsAncestorCallback isAncestorCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onIsAncestor(isAncestorCallback);
#endif
}

EXPORT void setArtboardRootTransformCallback(
    WrappedArtboard* wrappedArtboard,
    RootTransformCallback rootTransformCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onRootTransform(rootTransformCallback);
#endif
}

EXPORT void setArtboardLayoutDirtyCallback(WrappedArtboard* wrappedArtboard,
                                           ArtboardCallback layoutDirtyCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onLayoutDirty(layoutDirtyCallback);
#endif
}

EXPORT void setArtboardTransformDirtyCallback(
    WrappedArtboard* wrappedArtboard,
    ArtboardCallback transformDirtyCallback)
{
    if (wrappedArtboard == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedArtboard->artboard()->onTransformDirty(transformDirtyCallback);
#endif
}

EXPORT void setStateMachineInputChangedCallback(
    WrappedStateMachine* wrappedMachine,
    InputChanged changedCallback)
{
    if (wrappedMachine == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedMachine->stateMachine()->onInputChanged(changedCallback);
#endif
}

EXPORT void setStateMachineDataBindChangedCallback(
    WrappedStateMachine* wrappedMachine,
    DataBindChanged changedCallback)
{
    if (wrappedMachine == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    wrappedMachine->stateMachine()->onDataBindChanged(changedCallback);
#endif
}
#endif

static void vmiNumberCallback(ViewModelInstanceNumber* vmi, float value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateNumber))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateNumber(pointer, value);
}

static void vmiBooleanCallback(ViewModelInstanceBoolean* vmi, bool value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateBoolean))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateBoolean(pointer, value);
}

static void vmiColorCallback(ViewModelInstanceColor* vmi, int value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateColor))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateColor(pointer, value);
}

static void vmiStringCallback(ViewModelInstanceString* vmi, const char* value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateString))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
#if defined(__EMSCRIPTEN__)
    g_viewModelUpdateString(pointer, std::string(value));
#else
    g_viewModelUpdateString(pointer, value);
#endif
}

static void vmiTriggerCallback(ViewModelInstanceTrigger* vmi, uint32_t value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateTrigger))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateTrigger(pointer, value);
}

static void vmiListCallback(ViewModelInstanceList* vmi)
{
    if (!CALLBACK_VALID(g_viewModelUpdateList))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateList(pointer);
}

static void vmiEnumCallback(ViewModelInstanceEnum* vmi, uint32_t value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateEnum))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateEnum(pointer, value);
}

static void vmiSymbolListIndexCallback(ViewModelInstanceSymbolListIndex* vmi,
                                       uint32_t value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateSymbolListIndex))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateSymbolListIndex(pointer, value);
}

static void vmiAssetCallback(ViewModelInstanceAsset* vmi, uint32_t value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateAsset))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateAsset(pointer, value);
}

static void vmiArtboardCallback(ViewModelInstanceArtboard* vmi, uint32_t value)
{
    if (!CALLBACK_VALID(g_viewModelUpdateArtboard))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateArtboard(pointer, value);
}

static void vmiViewModelCallback(ViewModelInstanceViewModel* vmi)
{
    if (!CALLBACK_VALID(g_viewModelUpdateViewModel))
    {
        return;
    }
    auto pointer = reinterpret_cast<std::uintptr_t>(vmi);
    g_viewModelUpdateViewModel(pointer);
}

EXPORT ViewModelInstanceNumber* setViewModelInstanceNumberCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceNumber* viewModelInstanceNumber =
        viewModelInstance->as<ViewModelInstanceNumber>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceNumber->onChanged(vmiNumberCallback);
#endif
    return viewModelInstanceNumber;
}

EXPORT ViewModelInstanceBoolean* setViewModelInstanceBooleanCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceBoolean* viewModelInstanceBoolean =
        viewModelInstance->as<ViewModelInstanceBoolean>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceBoolean->onChanged(vmiBooleanCallback);
#endif
    return viewModelInstanceBoolean;
}

EXPORT ViewModelInstanceColor* setViewModelInstanceColorCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceColor* viewModelInstanceColor =
        viewModelInstance->as<ViewModelInstanceColor>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceColor->onChanged(vmiColorCallback);
#endif
    return viewModelInstanceColor;
}

EXPORT ViewModelInstanceString* setViewModelInstanceStringCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceString* viewModelInstanceString =
        viewModelInstance->as<ViewModelInstanceString>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceString->onChanged(vmiStringCallback);
#endif
    return viewModelInstanceString;
}

EXPORT ViewModelInstanceTrigger* setViewModelInstanceTriggerCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceTrigger* viewModelInstanceTrigger =
        viewModelInstance->as<ViewModelInstanceTrigger>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceTrigger->onChanged(vmiTriggerCallback);
#endif
    return viewModelInstanceTrigger;
}

EXPORT ViewModelInstanceList* setViewModelInstanceListCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceList* viewModelInstanceList =
        viewModelInstance->as<ViewModelInstanceList>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceList->onChanged(vmiListCallback);
#endif
    return viewModelInstanceList;
}

EXPORT ViewModelInstanceViewModel* setViewModelInstanceViewModelCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceViewModel* viewModelInstanceViewModel =
        viewModelInstance->as<ViewModelInstanceViewModel>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceViewModel->onChanged(vmiViewModelCallback);
#endif
    return viewModelInstanceViewModel;
}

EXPORT void setViewModelInstanceAdvanced(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return;
    }
    viewModelInstance->advanced();
}

EXPORT ViewModelInstanceEnum* setViewModelInstanceEnumCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceEnum* viewModelInstanceEnum =
        viewModelInstance->as<ViewModelInstanceEnum>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceEnum->onChanged(vmiEnumCallback);
#endif
    return viewModelInstanceEnum;
}

EXPORT ViewModelInstanceSymbolListIndex*
setViewModelInstanceSymbolListIndexCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceSymbolListIndex* viewModelInstanceSymbolListIndex =
        viewModelInstance->as<ViewModelInstanceSymbolListIndex>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceSymbolListIndex->onChanged(vmiSymbolListIndexCallback);
#endif
    return viewModelInstanceSymbolListIndex;
}

EXPORT ViewModelInstanceAsset* setViewModelInstanceAssetCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceAsset* viewModelInstanceAsset =
        viewModelInstance->as<ViewModelInstanceAsset>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceAsset->onChanged(vmiAssetCallback);
#endif
    return viewModelInstanceAsset;
}

EXPORT ViewModelInstanceArtboard* setViewModelInstanceArtboardCallback(
    ViewModelInstanceValue* viewModelInstance)
{
    if (viewModelInstance == nullptr)
    {
        return nullptr;
    }
    ViewModelInstanceArtboard* viewModelInstanceArtboard =
        viewModelInstance->as<ViewModelInstanceArtboard>();
#ifdef WITH_RIVE_TOOLS
    viewModelInstanceArtboard->onChanged(vmiArtboardCallback);
#endif
    return viewModelInstanceArtboard;
}

EXPORT void deleteArtboardInstance(WrappedArtboard* artboardInstance)
{
    if (artboardInstance == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    artboardInstance->deleteDataBinds();
    artboardInstance->unref();
}

EXPORT void deleteStateMachineInstance(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
    {
        return;
    }
    std::unique_lock<std::mutex> lock(g_deleteMutex);
#if defined(__EMSCRIPTEN__)
    _webInputChangedCallbacks.erase(wrappedMachine->stateMachine());
#endif
    wrappedMachine->unref();
}

EXPORT WrappedInput* stateMachineInput(WrappedStateMachine* wrappedMachine,
                                       SizeType index)
{
    if (wrappedMachine == nullptr)
    {
        return nullptr;
    }
    auto input = wrappedMachine->stateMachine()->input((size_t)index);
    if (input == nullptr)
    {
        return nullptr;
    }
    return new WrappedInput(ref_rcp(wrappedMachine), input);
}

EXPORT const char* stateMachineInputName(WrappedInput* wrappedInput)
{
    if (wrappedInput == nullptr)
    {
        return nullptr;
    }
    return wrappedInput->input()->name().c_str();
}

EXPORT uint16_t stateMachineInputType(WrappedInput* wrappedInput)
{
    if (wrappedInput == nullptr)
    {
        return 0;
    }
    return wrappedInput->input()->inputCoreType();
}

EXPORT WrappedInput* stateMachineInstanceNumber(
    WrappedStateMachine* wrappedMachine,
    const char* name,
    const char* path)
{
    if (wrappedMachine == nullptr || name == nullptr)
    {
        return nullptr;
    }
    auto number =
        (path != nullptr)
            ? wrappedMachine->wrappedArtboard()->artboard()->getNumber(name,
                                                                       path)
            : wrappedMachine->stateMachine()->getNumber(name);
    if (number == nullptr)
    {
        return nullptr;
    }
    return new WrappedInput(ref_rcp(wrappedMachine), number);
}

EXPORT bool stateMachineInstanceDone(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
    {
        return false;
    }
    return !wrappedMachine->stateMachine()->needsAdvance();
}

EXPORT float getNumberValue(WrappedInput* wrappedInput)
{
    if (wrappedInput == nullptr)
    {
        return 0.0f;
    }
    auto number = wrappedInput->number();
    if (number == nullptr)
    {
        return 0.0f;
    }
    return number->value();
}

EXPORT void setNumberValue(WrappedInput* wrappedInput, float value)
{
    if (wrappedInput == nullptr)
    {
        return;
    }
    auto number = wrappedInput->number();
    if (number == nullptr)
    {
        return;
    }
    number->value(value);
}

EXPORT WrappedInput* stateMachineInstanceBoolean(
    WrappedStateMachine* wrappedMachine,
    const char* name,
    const char* path)
{
    if (wrappedMachine == nullptr || name == nullptr)
    {
        return nullptr;
    }
    auto boolean =
        (path != nullptr)
            ? wrappedMachine->wrappedArtboard()->artboard()->getBool(name, path)
            : wrappedMachine->stateMachine()->getBool(name);
    if (boolean == nullptr)
    {
        return nullptr;
    }
    return new WrappedInput(ref_rcp(wrappedMachine), boolean);
}

EXPORT bool getBooleanValue(WrappedInput* wrappedInput)
{
    if (wrappedInput == nullptr)
    {
        return false;
    }
    auto boolean = wrappedInput->boolean();
    if (boolean == nullptr)
    {
        return false;
    }
    return boolean->value();
}

EXPORT void setBooleanValue(WrappedInput* wrappedInput, bool value)
{
    if (wrappedInput == nullptr)
    {
        return;
    }
    auto boolean = wrappedInput->boolean();
    if (boolean == nullptr)
    {
        return;
    }
    boolean->value(value);
}

EXPORT WrappedInput* stateMachineInstanceTrigger(
    WrappedStateMachine* wrappedMachine,
    const char* name,
    const char* path)
{
    if (wrappedMachine == nullptr || name == nullptr)
    {
        return nullptr;
    }
    auto trigger =
        (path != nullptr)
            ? wrappedMachine->wrappedArtboard()->artboard()->getTrigger(name,
                                                                        path)
            : wrappedMachine->stateMachine()->getTrigger(name);
    if (trigger == nullptr)
    {
        return nullptr;
    }
    return new WrappedInput(ref_rcp(wrappedMachine), trigger);
}

EXPORT void fireTrigger(WrappedInput* wrappedInput)
{
    if (wrappedInput == nullptr)
    {
        return;
    }
    wrappedInput->fire();
}

EXPORT void deleteInput(WrappedInput* wrappedInput)
{
    std::unique_lock<std::mutex> lock(g_deleteMutex);
    delete wrappedInput;
}

/// Factory callbacks to allow native to create and destroy Flutter
/// resources.
EXPORT void initBindingCallbacks(
    ViewModelUpdateNumber viewModelUpdateNumber,
    ViewModelUpdateBoolean viewModelUpdateBoolean,
    ViewModelUpdateColor viewModelUpdateColor,
    ViewModelUpdateString viewModelUpdateString,
    ViewModelUpdateTrigger viewModelUpdateTrigger,
    ViewModelUpdateEnum viewModelUpdateEnum,
    ViewModelUpdateSymbolListIndex viewModelUpdateSymbolListIndex,
    ViewModelUpdateAsset viewModelUpdateAsset,
    ViewModelUpdateArtboard viewModelUpdateArtboard,
    ViewModelUpdateList viewModelUpdateList,
    ViewModelUpdateViewModel viewModelUpdateViewModel)
{
    g_viewModelUpdateNumber = viewModelUpdateNumber;
    g_viewModelUpdateBoolean = viewModelUpdateBoolean;
    g_viewModelUpdateColor = viewModelUpdateColor;
    g_viewModelUpdateString = viewModelUpdateString;
    g_viewModelUpdateTrigger = viewModelUpdateTrigger;
    g_viewModelUpdateEnum = viewModelUpdateEnum;
    g_viewModelUpdateSymbolListIndex = viewModelUpdateSymbolListIndex;
    g_viewModelUpdateAsset = viewModelUpdateAsset;
    g_viewModelUpdateArtboard = viewModelUpdateArtboard;
    g_viewModelUpdateList = viewModelUpdateList;
    g_viewModelUpdateViewModel = viewModelUpdateViewModel;
}

#ifdef WITH_RIVE_WORKER
#include <condition_variable>
#include <deque>
#include <thread>

struct Work
{
    rcp<WrappedStateMachine> smi;
    bool done;
};

class RiveWorker
{
private:
    static const int threadCount = 6;
    static RiveWorker* sm_instance;
    static bool sm_exiting;
    std::vector<Work> m_work;
    std::condition_variable m_haveWork;
    std::condition_variable m_didSomeWork;
    std::vector<std::thread> m_workThreads;
    std::mutex m_mutex;
    float m_elapsedSeconds;
    uint64_t m_workIndex = 0;
    uint64_t m_completed = 0;
    uint64_t m_toComplete = 0;

    RiveWorker()
    {
        std::atexit(atExit);
        for (int i = 0; i < threadCount; i++)
        {
            m_workThreads.emplace_back(std::thread(staticWorkThread, this));
        }
    }

    void workThread()
    {
        while (!sm_exiting)
        {
            Work* work = nullptr;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                if (m_workIndex < m_work.size())
                {
                    work = &m_work[m_workIndex++];
                }
                else
                {
                    m_haveWork.wait_for(lock, std::chrono::milliseconds(100));
                }
            }
            if (work != nullptr)
            {
                work->smi->stateMachine()->advanceAndApply(m_elapsedSeconds);
                std::unique_lock<std::mutex> lock(m_mutex);
                work->done = true;
                m_completed++;
            }
            m_didSomeWork.notify_all();
        }
    }

    static void staticWorkThread(void* w)
    {
        RiveWorker* worker = static_cast<RiveWorker*>(w);
        worker->workThread();
    }

    static void atExit() { sm_exiting = true; }

public:
    static RiveWorker* get()
    {
        if (sm_instance == nullptr)
        {
            sm_instance = new RiveWorker();
        }

        return sm_instance;
    }

    void add(float elapsedSeconds, WrappedStateMachine** smi, uint64_t count)
    {
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_elapsedSeconds = elapsedSeconds;
            m_toComplete = count;
            m_completed = 0;
            m_workIndex = 0;
            m_work.clear();
            for (uint64_t i = 0; i < count; i++)
            {
                m_work.push_back({ref_rcp(smi[i]), false});
            }
        }
        m_haveWork.notify_all();
    }

    void complete(
        std::function<void(rcp<WrappedStateMachine>)> callback = nullptr)
    {
        int completedIndex = 0;
        while (!sm_exiting)
        {
            // Keep rendering artboards that are done.
            std::unique_lock<std::mutex> lock(m_mutex);
            if (callback != nullptr)
            {
                // Any artboards ready to draw?
                if (completedIndex < m_toComplete &&
                    m_work[completedIndex].done)
                {
                    // While locked, count how many we can draw unlocked.
                    uint64_t completedFrom = completedIndex;
                    while (++completedIndex < m_toComplete &&
                           m_work[completedIndex].done)
                    {
                        // Intentionally empty.
                    }
                    lock.unlock();
                    while (completedFrom < completedIndex)
                    {
                        callback(m_work[completedFrom].smi);
                        completedFrom++;
                    }
                    continue;
                }
            }
            if (m_toComplete == m_completed)
            {
                break;
            }
            m_didSomeWork.wait_for(lock, std::chrono::milliseconds(100));
        }
    }
};

RiveWorker* RiveWorker::sm_instance = nullptr;
bool RiveWorker::sm_exiting = false;
#endif

EXPORT void stateMachineInstanceBatchAdvance(WrappedStateMachine** smi,
                                             SizeType count,
                                             float elapsedSeconds)
{
#ifdef WITH_RIVE_WORKER
    RiveWorker* worker = RiveWorker::get();
    worker->add(elapsedSeconds, smi, count);
    worker->complete();
#else
    for (int i = 0; i < count; i++)
    {
        smi[i]->stateMachine()->advanceAndApply(elapsedSeconds);
#ifdef RIVE_MICROPROFILE
        if (rive::RiveProfile::instance().isActive())
        {
            rive::RiveProfile::instance().flushTransitionRecords();
            rive::RiveProfile::instance().flushListenerPerformChangeRecords();
        }
#endif
    }
#endif
}

EXPORT void stateMachineInstanceBatchAdvanceAndRender(WrappedStateMachine** smi,
                                                      SizeType count,
                                                      float elapsedSeconds,
                                                      Renderer* renderer)
{
    if (renderer == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_WORKER
    RiveWorker* worker = RiveWorker::get();
    worker->add(elapsedSeconds, smi, count);
    worker->complete([&](rcp<WrappedStateMachine> smi) {
        WrappedArtboard* wrappedArtboard = smi->wrappedArtboard();
        renderer->save();
        renderer->transform(wrappedArtboard->renderTransform);
        wrappedArtboard->artboard()->draw(renderer);
        renderer->restore();
    });
#else
    for (int i = 0; i < count; i++)
    {
        smi[i]->stateMachine()->advanceAndApply(elapsedSeconds);
        WrappedArtboard* wrappedArtboard = smi[i]->wrappedArtboard();
#ifdef RIVE_MICROPROFILE
        if (rive::RiveProfile::instance().isActive())
        {
            rive::RiveProfile::instance().flushTransitionRecords();
            rive::RiveProfile::instance().flushListenerPerformChangeRecords();
        }
#endif
        renderer->save();
        renderer->transform(wrappedArtboard->renderTransform);
        wrappedArtboard->artboard()->draw(renderer);
        renderer->restore();
    }
    return;
#endif
}

EXPORT void wasmStateMachineInstanceBatchAdvance(uint32_t wasmPtr,
                                                 uint32_t count,
                                                 float elapsedSeconds)
{
    WrappedStateMachine** smi =
        reinterpret_cast<WrappedStateMachine**>(wasmPtr);
    stateMachineInstanceBatchAdvance(smi, count, elapsedSeconds);
}

EXPORT void wasmStateMachineInstanceBatchAdvanceAndRender(uint32_t wasmPtr,
                                                          uint32_t count,
                                                          float elapsedSeconds,
                                                          Renderer* renderer)
{
    WrappedStateMachine** smi =
        reinterpret_cast<WrappedStateMachine**>(wasmPtr);
    stateMachineInstanceBatchAdvanceAndRender(smi,
                                              count,
                                              elapsedSeconds,
                                              renderer);
}

EXPORT RawText* makeRawText(Factory* factory)
{
    assert(factory != nullptr);
    return new RawText(factory);
}

EXPORT void deleteRawText(RawText* rawText) { delete rawText; }

EXPORT void rawTextAppend(RawText* rawText,
                          const char* text,
                          RenderPaint* paint,
                          Font* font,
                          float size,
                          float lineHeight,
                          float letterSpacing)
{
    if (rawText == nullptr)
    {
        return;
    }
    std::string textString = text;
    rawText->append(textString,
                    ref_rcp(paint),
                    ref_rcp(font),
                    size,
                    lineHeight,
                    letterSpacing);
}

EXPORT void rawTextClear(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->clear();
}

EXPORT bool rawTextIsEmpty(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return true;
    }
    return rawText->empty();
}

EXPORT uint8_t rawTextGetSizing(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawText->sizing();
}

EXPORT void rawTextSetSizing(RawText* rawText, uint8_t sizing)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->sizing((TextSizing)sizing);
}

EXPORT uint8_t rawTextGetOverflow(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawText->overflow();
}

EXPORT void rawTextSetOverflow(RawText* rawText, uint8_t overflow)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->overflow((TextOverflow)overflow);
}

EXPORT uint8_t rawTextGetAlign(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawText->align();
}

EXPORT void rawTextSetAlign(RawText* rawText, uint8_t align)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->align((TextAlign)align);
}

EXPORT float rawTextGetMaxWidth(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return rawText->maxWidth();
}

EXPORT void rawTextSetMaxWidth(RawText* rawText, float maxWidth)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->maxWidth(maxWidth);
}

EXPORT float rawTextGetMaxHeight(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return rawText->maxHeight();
}

EXPORT void rawTextSetMaxHeight(RawText* rawText, float maxHeight)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->maxHeight(maxHeight);
}

EXPORT float rawTextGetParagraphSpacing(RawText* rawText)
{
    if (rawText == nullptr)
    {
        return 0;
    }
    return rawText->paragraphSpacing();
}

EXPORT void rawTextSetParagraphSpacing(RawText* rawText, float paragraphSpacing)
{
    if (rawText == nullptr)
    {
        return;
    }
    rawText->paragraphSpacing(paragraphSpacing);
}

EXPORT void rawTextBounds(RawText* rawText, float* out)
{
    if (rawText == nullptr)
    {
        return;
    }
    AABB bounds = rawText->bounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void rawTextRender(RawText* rawText,
                          Renderer* renderer,
                          RenderPaint* renderPaint)
{
    if (rawText == nullptr || renderer == nullptr)
    {
        return;
    }
    // null render paint is allowed
    rawText->render(renderer, ref_rcp(renderPaint));
}

EXPORT RawTextInput* makeRawTextInput() { return new RawTextInput(); }

EXPORT void deleteRawTextInput(RawTextInput* rawTextInput)
{
    delete rawTextInput;
}

EXPORT float rawTextInputGetFontSize(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->fontSize();
}

EXPORT void rawTextInputSetFontSize(RawTextInput* rawTextInput, float value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->fontSize(value);
}

EXPORT void rawTextInputSetFont(RawTextInput* rawTextInput, Font* font)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->font(ref_rcp(font));
}

EXPORT float rawTextInputGetMaxWidth(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->maxWidth();
}

EXPORT void rawTextInputSetMaxWidth(RawTextInput* rawTextInput, float value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->maxWidth(value);
}

EXPORT float rawTextInputGetMaxHeight(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->maxHeight();
}

EXPORT void rawTextInputSetMaxHeight(RawTextInput* rawTextInput, float value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->maxHeight(value);
}

EXPORT float rawTextInputGetParagraphSpacing(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->paragraphSpacing();
}

EXPORT void rawTextInputSetParagraphSpacing(RawTextInput* rawTextInput,
                                            float value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->paragraphSpacing(value);
}

EXPORT float rawTextInputGetSelectionCornerRadius(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->selectionCornerRadius();
}

EXPORT void rawTextInputSetSelectionCornerRadius(RawTextInput* rawTextInput,
                                                 float value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->selectionCornerRadius(value);
}

EXPORT bool rawTextInputGetSeparateSelectionText(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0.0f;
    }
    return rawTextInput->separateSelectionText();
}

EXPORT void rawTextInputSetText(RawTextInput* rawTextInput, const char* value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->text(value);
}

EXPORT void rawTextInputSetTextPreserveCursor(RawTextInput* rawTextInput,
                                              const char* value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->textPreserveCursor(value);
}

EXPORT const char* rawTextInputGetText(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto text = rawTextInput->text();
    return toCString(text);
}

EXPORT size_t rawTextInputLength(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0;
    }
    return rawTextInput->length();
}

EXPORT void rawTextInputSetSeparateSelectionText(RawTextInput* rawTextInput,
                                                 bool value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->separateSelectionText(value);
}

EXPORT uint8_t rawTextInputGetSizing(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawTextInput->sizing();
}

EXPORT void rawTextInputSetSizing(RawTextInput* rawTextInput, uint8_t value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->sizing((TextSizing)value);
}

EXPORT uint8_t rawTextInputGetOverflow(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawTextInput->overflow();
}

EXPORT void rawTextInputSetOverflow(RawTextInput* rawTextInput, uint8_t value)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->overflow((TextOverflow)value);
}

EXPORT void rawTextInputBounds(RawTextInput* rawTextInput, float* out)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    AABB bounds = rawTextInput->bounds();
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT void rawTextInputMeasure(RawTextInput* rawTextInput,
                                float maxWidth,
                                float maxHeight,
                                float* out)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    AABB bounds = rawTextInput->measure(maxWidth, maxHeight);
    memcpy(out, &bounds, sizeof(float) * 4);
}

EXPORT uint8_t rawTextInputUpdate(RawTextInput* rawTextInput,
                                  rive::Factory* factory)
{
    if (rawTextInput == nullptr)
    {
        return 0;
    }
    return (uint8_t)rawTextInput->update(factory);
}

EXPORT rive::RenderPath* rawTextTextPath(RawTextInput* rawTextInput,
                                         rive::Factory* factory)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto path = rawTextInput->textPath()->renderPath(factory);
    path->ref();
    return path;
}

EXPORT rive::RenderPath* rawTextSelectedTextPath(RawTextInput* rawTextInput,
                                                 rive::Factory* factory)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto path = rawTextInput->selectedTextPath()->renderPath(factory);
    path->ref();
    return path;
}

EXPORT rive::RenderPath* rawTextCursorPath(RawTextInput* rawTextInput,
                                           rive::Factory* factory)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto path = rawTextInput->cursorPath()->renderPath(factory);
    path->ref();
    return path;
}

EXPORT rive::RenderPath* rawTextSelectionPath(RawTextInput* rawTextInput,
                                              rive::Factory* factory)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto path = rawTextInput->selectionPath()->renderPath(factory);
    path->ref();
    return path;
}

EXPORT rive::RenderPath* rawTextClipPath(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return nullptr;
    }
    auto path = rawTextInput->clipRenderPath().get();
    path->ref();
    return path;
}

EXPORT void rawTextInsertText(RawTextInput* rawTextInput, const char* text)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->insert(text);
}

EXPORT void rawTextInsertCodePoint(RawTextInput* rawTextInput,
                                   uint32_t codePoint)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->insert((Unichar)codePoint);
}

EXPORT void rawTextErase(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->erase();
}

EXPORT void rawTextBackspace(RawTextInput* rawTextInput, int32_t direction)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->backspace(direction);
}

EXPORT void rawTextCursorLeft(RawTextInput* rawTextInput,
                              uint8_t boundary,
                              bool select)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->cursorLeft((rive::CursorBoundary)boundary, select);
}

EXPORT void rawTextCursorRight(RawTextInput* rawTextInput,
                               uint8_t boundary,
                               bool select)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->cursorRight((rive::CursorBoundary)boundary, select);
}

EXPORT void rawTextCursorUp(RawTextInput* rawTextInput, bool select)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->cursorUp(select);
}

EXPORT void rawTextCursorDown(RawTextInput* rawTextInput, bool select)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->cursorDown(select);
}

EXPORT void rawTextSelectWord(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->selectWord();
}

EXPORT bool rawTextHasSelection(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return false;
    }
    return rawTextInput->cursor().hasSelection();
}

EXPORT void rawTextClearSelection(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->clearSelection();
}

EXPORT void rawTextUndo(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->undo();
}

EXPORT void rawTextRedo(RawTextInput* rawTextInput)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->redo();
}

EXPORT void rawTextMoveCursorTo(RawTextInput* rawTextInput,
                                float x,
                                float y,
                                bool select)
{
    if (rawTextInput == nullptr)
    {
        return;
    }
    rawTextInput->moveCursorTo(Vec2D(x, y), select);
}

EXPORT bool rawTextInputCursorPosition(RawTextInput* rawTextInput, float* out)
{
    if (rawTextInput == nullptr)
    {
        return false;
    }
    auto position = rawTextInput->cursorVisualPosition();
    out[0] = position.x();
    out[1] = position.top();
    out[2] = position.bottom();
    return position.found();
}

// ============================================================================
// Profiler FFI bindings (RiveProfile abstracts MicroProfile)
// ============================================================================

#ifdef RIVE_MICROPROFILE

static void flushProfileAndMergeTransitionBuffer()
{
    rive::RiveProfile::instance().flushFrameDataTo(g_profileBuffer);
    std::lock_guard<std::mutex> lock(g_eventBufferMutex);
    if (!g_eventBuffer.empty())
    {
        g_profileBuffer.insert(g_profileBuffer.end(),
                               g_eventBuffer.begin(),
                               g_eventBuffer.end());
        g_eventBuffer.clear();
    }
}

EXPORT bool profilerStop()
{
    if (!rive::RiveProfile::instance().isActive())
    {
        return false;
    }
    rive::RiveProfile::instance().stop();
    flushProfileAndMergeTransitionBuffer();
    g_profileBuffer.push_back(0x00);
    return true;
}

EXPORT bool profilerStart()
{
    if (rive::RiveProfile::instance().isActive())
    {
        return false;
    }
    g_profileBuffer.clear();
    {
        std::lock_guard<std::mutex> lock(g_eventBufferMutex);
        g_eventBuffer.clear();
    }
    g_lastSentStringTableSize = 0;
    rive::RiveProfile::instance().setFlushCallback(
        flushTransitionRecordsToEventBuffer);
    rive::RiveProfile::instance().setListenerPerformChangeFlushCallback(
        flushListenerPerformChangeRecordsToEventBuffer);
    rive::RiveProfile::instance().start();
    return true;
}

EXPORT bool profilerIsActive()
{
    return rive::RiveProfile::instance().isActive();
}

EXPORT size_t profilerDump()
{
    if (rive::RiveProfile::instance().isActive())
    {
        flushProfileAndMergeTransitionBuffer();
    }
    return g_profileBuffer.size();
}

EXPORT const uint8_t* profilerGetBufferPtr() { return g_profileBuffer.data(); }

EXPORT size_t profilerGetBufferSize() { return g_profileBuffer.size(); }

EXPORT void profilerFreeBuffer()
{
    g_profileBuffer.clear();
    g_profileBuffer.shrink_to_fit();
}

EXPORT void profilerEndFrame() { rive::RiveProfile::instance().endFrame(); }

#else // Stubs when RIVE_MICROPROFILE not defined

EXPORT bool profilerStart() { return false; }
EXPORT bool profilerStop() { return false; }
EXPORT bool profilerIsActive() { return false; }
EXPORT size_t profilerDump() { return 0; }
EXPORT const uint8_t* profilerGetBufferPtr() { return nullptr; }
EXPORT size_t profilerGetBufferSize() { return 0; }
EXPORT void profilerFreeBuffer() {}
EXPORT void profilerEndFrame() {}

#endif // RIVE_MICROPROFILE

#if defined(__EMSCRIPTEN__) && defined(WITH_RIVE_TOOLS)
static ViewModelInstanceBufferResponse requestSerializedViewModelInstanceWasm(
    File* file,
    ViewModelInstance* instance)
{
    ViewModelInstanceBufferResponse r = {0, 0};
    serializeViewModelInstanceByPointer(file, instance, &r);
    return r;
}

static void freeViewModelInstanceSerializedDataWasm(
    ViewModelInstanceBufferResponse response)
{
    if (response.data != 0)
    {
        free(reinterpret_cast<void*>(response.data));
    }
}
#endif

// =============================================================================
// FocusNode and FocusManager FFI
// =============================================================================

#include "dart_focus_node.hpp"
#include "rive/input/focus_manager.hpp"

using rive_native::DartFocusCallback;
using rive_native::DartFocusNode;
using rive_native::DartKeyInputCallback;
using rive_native::DartTextInputCallback;

// FocusNode creation/disposal
EXPORT void* makeFocusNode(DartKeyInputCallback keyInput,
                           DartTextInputCallback textInput,
                           DartFocusCallback focused,
                           DartFocusCallback blurred)
{
    // DartFocusNode starts with refcount=1, which Dart owns
    return new DartFocusNode(keyInput, textInput, focused, blurred);
}

// Simple version without callbacks (for WASM where callbacks are handled in JS)
EXPORT void* makeFocusNodeSimple() { return new DartFocusNode(); }

EXPORT void disposeFocusNode(void* node)
{
    if (node == nullptr)
        return;
    // Unref instead of delete - the node may still be held by FocusManager
    static_cast<DartFocusNode*>(node)->unref();
}

// FocusNode properties
// Note: DartFocusNode IS a FocusNode, so we cast directly
EXPORT void focusNodeSetCanFocus(void* node, bool value)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->canFocus(value);
}

EXPORT bool focusNodeCanFocus(void* node)
{
    if (node == nullptr)
        return false;
    return static_cast<DartFocusNode*>(node)->canFocus();
}

EXPORT void focusNodeSetCanTouch(void* node, bool value)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->canTouch(value);
}

EXPORT bool focusNodeCanTouch(void* node)
{
    if (node == nullptr)
        return false;
    return static_cast<DartFocusNode*>(node)->canTouch();
}

EXPORT void focusNodeSetCanTraverse(void* node, bool value)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->canTraverse(value);
}

#ifdef WITH_RIVE_TOOLS
EXPORT void focusNodeSetIsCollapsed(void* node, bool value)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->isCollapsed(value);
}
#endif

EXPORT bool focusNodeCanTraverse(void* node)
{
    if (node == nullptr)
        return false;
    return static_cast<DartFocusNode*>(node)->canTraverse();
}

EXPORT void focusNodeSetTabIndex(void* node, int value)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->tabIndex(value);
}

EXPORT int focusNodeTabIndex(void* node)
{
    if (node == nullptr)
        return 0;
    return static_cast<DartFocusNode*>(node)->tabIndex();
}

EXPORT void focusNodeSetEdgeBehavior(void* node, uint8_t edgeBehavior)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->edgeBehavior(
        static_cast<rive::EdgeBehavior>(edgeBehavior));
}

EXPORT uint8_t focusNodeGetEdgeBehavior(void* node)
{
    if (node == nullptr)
        return 0;
    return static_cast<uint8_t>(
        static_cast<DartFocusNode*>(node)->edgeBehavior());
}

// FocusNode world bounds (for directional navigation)
// Bounds are stored directly on FocusNode and updated during update cycle
EXPORT void focusNodeSetWorldBounds(void* node,
                                    float minX,
                                    float minY,
                                    float maxX,
                                    float maxY)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->worldBounds(
        rive::AABB(minX, minY, maxX, maxY));
}

EXPORT void focusNodeClearWorldBounds(void* node)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->clearWorldBounds();
}

// FocusNode name (for debugging)
EXPORT const char* focusNodeGetName(void* node)
{
    if (node == nullptr)
        return "";
    return static_cast<DartFocusNode*>(node)->name().c_str();
}

EXPORT void focusNodeSetName(void* node, const char* name)
{
    if (node == nullptr)
        return;
    static_cast<DartFocusNode*>(node)->name(name ? name : "");
}

// FocusManager creation/disposal
EXPORT void* makeFocusManager() { return new rive::FocusManager(); }

EXPORT void disposeFocusManager(void* manager)
{
    std::lock_guard<std::mutex> lock(g_deleteMutex);
    auto* fm = static_cast<rive::FocusManager*>(manager);
#if defined(__EMSCRIPTEN__) && defined(WITH_RIVE_TOOLS)
    // Clean up WASM callback maps
    g_focusChangedCallbacksWasm.erase(fm);
    g_scrollIntoViewCallbacksWasm.erase(fm);
#endif
    delete fm;
}

// FocusManager - focus state
EXPORT void* focusManagerGetPrimaryFocus(void* manager)
{
    if (manager == nullptr)
        return nullptr;
    return static_cast<rive::FocusManager*>(manager)->primaryFocus().get();
}

#ifdef __EMSCRIPTEN__
/// WASM-specific struct to return primary focus bounds
struct FocusBoundsResult
{
    int valid; // 1 if bounds are valid, 0 otherwise
    float minX;
    float minY;
    float maxX;
    float maxY;
};

/// Get the world bounds of the primary focus (WASM version).
/// Returns a struct with valid flag and bounds. Takes WasmPtr, embind can
/// never bind a void* parameter and throws UnboundTypeError at call time.
EXPORT FocusBoundsResult focusManagerGetPrimaryFocusBounds(WasmPtr managerPtr)
{
    auto* manager = reinterpret_cast<rive::FocusManager*>(managerPtr);
    FocusBoundsResult result = {0, 0, 0, 0, 0};
    if (manager == nullptr)
        return result;
    rive::AABB bounds;
    if (!manager->primaryFocusBounds(bounds))
    {
        return result;
    }
    result.valid = 1;
    result.minX = bounds.minX;
    result.minY = bounds.minY;
    result.maxX = bounds.maxX;
    result.maxY = bounds.maxY;
    return result;
}
#else
/// Get the world bounds of the primary focus.
/// Returns true if bounds are valid. Outputs are set only if true.
EXPORT bool focusManagerGetPrimaryFocusBounds(void* manager,
                                              float* outMinX,
                                              float* outMinY,
                                              float* outMaxX,
                                              float* outMaxY)
{
    if (manager == nullptr)
        return false;
    rive::AABB bounds;
    if (!static_cast<rive::FocusManager*>(manager)->primaryFocusBounds(bounds))
    {
        return false;
    }
    *outMinX = bounds.minX;
    *outMinY = bounds.minY;
    *outMaxX = bounds.maxX;
    *outMaxY = bounds.maxY;
    return true;
}
#endif

/// Get the root artboard that contains the primary focus (walks up nested
/// chain). Returns nullptr if there is no focus or the focusable has no
/// artboard.
EXPORT void* focusManagerGetPrimaryFocusArtboard(void* manager)
{
    if (manager == nullptr)
        return nullptr;
    return static_cast<rive::FocusManager*>(manager)->primaryFocusArtboard();
}

/// Get the immediate artboard that contains the primary focus (no walk-up).
/// Returns nullptr if there is no focus or the focusable has no artboard.
EXPORT void* focusManagerGetPrimaryFocusImmediateArtboard(void* manager)
{
    if (manager == nullptr)
        return nullptr;
    return static_cast<rive::FocusManager*>(manager)
        ->primaryFocusImmediateArtboard();
}

/// Check if the primary focus is inside the given artboard (or a nested
/// artboard within it). Returns true if the focused element's artboard is the
/// given artboard or a descendant of it.
EXPORT bool focusManagerIsFocusInArtboard(void* manager, void* artboard)
{
    if (manager == nullptr || artboard == nullptr)
        return false;

    auto* focusManager = static_cast<rive::FocusManager*>(manager);
    auto* targetArtboard = static_cast<rive::Artboard*>(artboard);

    // Get the immediate artboard containing the focused element
    rive::Artboard* focusedArtboard =
        focusManager->primaryFocusImmediateArtboard();
    if (focusedArtboard == nullptr)
        return false;

    // Walk up the chain from the focused artboard to see if we hit the target
    rive::Artboard* current = focusedArtboard;
    while (current != nullptr)
    {
        if (current == targetArtboard)
            return true;

        // Move to parent artboard via host
        if (current->host() == nullptr)
            break;
        current = current->host()->parentArtboard();
    }

    return false;
}

EXPORT void focusManagerSetFocus(void* manager, void* node)
{
    if (manager == nullptr)
        return;
    auto* focusManager = static_cast<rive::FocusManager*>(manager);
    if (node == nullptr)
    {
        focusManager->clearFocus();
    }
    else
    {
        focusManager->setFocus(
            rive::ref_rcp(static_cast<DartFocusNode*>(node)));
    }
}

EXPORT void focusManagerClearFocus(void* manager)
{
    if (manager == nullptr)
        return;
    static_cast<rive::FocusManager*>(manager)->clearFocus();
}

EXPORT bool focusManagerHasFocus(void* manager, void* node)
{
    if (manager == nullptr || node == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->hasFocus(
        rive::ref_rcp(static_cast<DartFocusNode*>(node)));
}

EXPORT bool focusManagerHasPrimaryFocus(void* manager, void* node)
{
    if (manager == nullptr || node == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->hasPrimaryFocus(
        rive::ref_rcp(static_cast<DartFocusNode*>(node)));
}

EXPORT void dropFocusIfFocusTargetHidden(void* manager)
{
    if (manager == nullptr)
    {
        return;
    }
    static_cast<rive::FocusManager*>(manager)->dropFocusIfFocusTargetHidden();
}

// FocusManager - hierarchy
EXPORT void focusManagerAddChild(void* manager, void* parent, void* child)
{
    if (manager == nullptr || child == nullptr)
        return;
    auto* focusManager = static_cast<rive::FocusManager*>(manager);
    rive::rcp<rive::FocusNode> parentNode =
        parent ? rive::ref_rcp(static_cast<DartFocusNode*>(parent)) : nullptr;
    rive::rcp<rive::FocusNode> childNode =
        rive::ref_rcp(static_cast<DartFocusNode*>(child));
    focusManager->addChild(parentNode, childNode);
}

EXPORT void focusManagerRemoveChild(void* manager, void* child)
{
    if (manager == nullptr || child == nullptr)
        return;
    auto* focusManager = static_cast<rive::FocusManager*>(manager);
    rive::rcp<rive::FocusNode> childNode =
        rive::ref_rcp(static_cast<DartFocusNode*>(child));
    focusManager->removeChild(childNode);
}

EXPORT void focusManagerDetachChild(void* manager, void* child)
{
    if (manager == nullptr || child == nullptr)
        return;
    auto* focusManager = static_cast<rive::FocusManager*>(manager);
    rive::rcp<rive::FocusNode> childNode =
        rive::ref_rcp(static_cast<DartFocusNode*>(child));
    focusManager->detachChild(childNode);
}

// FocusManager - traversal
EXPORT bool focusManagerFocusNext(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusNext();
}

EXPORT bool focusManagerFocusPrevious(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusPrevious();
}

// FocusManager - directional navigation
EXPORT bool focusManagerFocusLeft(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusLeft();
}

EXPORT bool focusManagerFocusRight(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusRight();
}

EXPORT bool focusManagerFocusUp(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusUp();
}

EXPORT bool focusManagerFocusDown(void* manager)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->focusDown();
}

// FocusManager - input routing
EXPORT bool focusManagerKeyInput(void* manager,
                                 uint16_t key,
                                 uint8_t modifiers,
                                 bool isPressed,
                                 bool isRepeat)
{
    if (manager == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->keyInput(
        static_cast<rive::Key>(key),
        static_cast<rive::KeyModifiers>(modifiers),
        isPressed,
        isRepeat);
}

EXPORT bool focusManagerTextInput(void* manager, const char* text)
{
    if (manager == nullptr || text == nullptr)
        return false;
    return static_cast<rive::FocusManager*>(manager)->textInput(text);
}

#if defined(__EMSCRIPTEN__)
// =============================================================================
// WASM FocusNode callbacks - per-node emscripten::val callback storage
// =============================================================================

struct WasmFocusNodeCallbacks
{
    emscripten::val onKeyInput = emscripten::val::null();
    emscripten::val onTextInput = emscripten::val::null();
    emscripten::val onFocused = emscripten::val::null();
    emscripten::val onBlurred = emscripten::val::null();
};

std::unordered_map<void*, WasmFocusNodeCallbacks> g_focusNodeCallbacksWasm;

// Static thunks that look up the per-node JS callback and invoke it
static bool wasmKeyInputThunk(void* nodePtr,
                              uint16_t key,
                              uint8_t modifiers,
                              bool isPressed,
                              bool isRepeat)
{
    auto it = g_focusNodeCallbacksWasm.find(nodePtr);
    if (it != g_focusNodeCallbacksWasm.end() &&
        !it->second.onKeyInput.isNull() && !it->second.onKeyInput.isUndefined())
    {
        return it->second
            .onKeyInput(static_cast<int>(key),
                        static_cast<int>(modifiers),
                        isPressed,
                        isRepeat)
            .as<bool>();
    }
    return false;
}

static bool wasmTextInputThunk(void* nodePtr, const char* text)
{
    auto it = g_focusNodeCallbacksWasm.find(nodePtr);
    if (it != g_focusNodeCallbacksWasm.end() &&
        !it->second.onTextInput.isNull() &&
        !it->second.onTextInput.isUndefined())
    {
        return it->second.onTextInput(std::string(text)).as<bool>();
    }
    return false;
}

static void wasmFocusedThunk(void* nodePtr)
{
    auto it = g_focusNodeCallbacksWasm.find(nodePtr);
    if (it != g_focusNodeCallbacksWasm.end() &&
        !it->second.onFocused.isNull() && !it->second.onFocused.isUndefined())
    {
        it->second.onFocused();
    }
}

static void wasmBlurredThunk(void* nodePtr)
{
    auto it = g_focusNodeCallbacksWasm.find(nodePtr);
    if (it != g_focusNodeCallbacksWasm.end() &&
        !it->second.onBlurred.isNull() && !it->second.onBlurred.isUndefined())
    {
        it->second.onBlurred();
    }
}

WasmPtr makeFocusNodeWasm(emscripten::val onKeyInput,
                          emscripten::val onTextInput,
                          emscripten::val onFocused,
                          emscripten::val onBlurred)
{
    bool hasCallbacks = (!onKeyInput.isNull() && !onKeyInput.isUndefined()) ||
                        (!onTextInput.isNull() && !onTextInput.isUndefined()) ||
                        (!onFocused.isNull() && !onFocused.isUndefined()) ||
                        (!onBlurred.isNull() && !onBlurred.isUndefined());

    DartFocusNode* node;
    if (hasCallbacks)
    {
        node = new DartFocusNode(wasmKeyInputThunk,
                                 wasmTextInputThunk,
                                 wasmFocusedThunk,
                                 wasmBlurredThunk);
        g_focusNodeCallbacksWasm[static_cast<void*>(node)] = {
            onKeyInput,
            onTextInput,
            onFocused,
            onBlurred,
        };
    }
    else
    {
        node = new DartFocusNode();
    }
    return reinterpret_cast<WasmPtr>(node);
}

// Clean up WASM callbacks when a FocusNode is disposed
static void disposeFocusNodeWasm(WasmPtr nodePtr)
{
    auto* node = reinterpret_cast<DartFocusNode*>(nodePtr);
    if (node == nullptr)
        return;
    g_focusNodeCallbacksWasm.erase(static_cast<void*>(node));
    node->unref();
}
#endif

#ifdef WITH_RIVE_TOOLS
using FocusChangedCallback = void (*)();
EXPORT void focusManagerSetFocusChangedCallback(void* manager,
                                                FocusChangedCallback callback)
{
    if (manager == nullptr)
        return;
    static_cast<rive::FocusManager*>(manager)->setFocusChangedCallback(
        callback);
}

// Callback for scroll-into-view requests from Dart-mounted artboards.
// Parameters passed to Dart:
// - minX, minY, maxX, maxY: world bounds of the focused element
// - rootArtboard: pointer to the root artboard (host == null)
using ScrollIntoViewCallback = void (*)(float minX,
                                        float minY,
                                        float maxX,
                                        float maxY,
                                        void* rootArtboard);

// Static thunk that converts AABB to individual floats for Dart FFI
static ScrollIntoViewCallback g_scrollIntoViewCallback = nullptr;
static void scrollIntoViewThunk(const rive::AABB& bounds,
                                rive::Artboard* rootArtboard)
{
    if (g_scrollIntoViewCallback)
    {
        g_scrollIntoViewCallback(bounds.minX,
                                 bounds.minY,
                                 bounds.maxX,
                                 bounds.maxY,
                                 static_cast<void*>(rootArtboard));
    }
}

#if defined(__EMSCRIPTEN__)
// =============================================================================
// WASM FocusManager callbacks
// =============================================================================

// WASM-specific: Store per-manager emscripten::val callbacks for focus-changed
// Uses broadcast approach like FFI - all managers share the same static thunk
std::unordered_map<rive::FocusManager*, emscripten::val>
    g_focusChangedCallbacksWasm;

// Broadcast thunk: calls ALL registered callbacks when any manager fires
// This matches FFI behavior where a single trampoline notifies all managers
static void focusChangedBroadcastThunk()
{
    for (auto& pair : g_focusChangedCallbacksWasm)
    {
        if (!pair.second.isNull() && !pair.second.isUndefined())
        {
            pair.second();
        }
    }
}

void focusManagerSetFocusChangedCallbackWasm(WasmPtr managerPtr,
                                             emscripten::val callback)
{
    auto* manager = reinterpret_cast<rive::FocusManager*>(managerPtr);
    if (manager == nullptr)
        return;

    if (!callback.isNull() && !callback.isUndefined())
    {
        g_focusChangedCallbacksWasm[manager] = callback;
        // All managers share the same broadcast thunk
        manager->setFocusChangedCallback(focusChangedBroadcastThunk);
    }
    else
    {
        g_focusChangedCallbacksWasm.erase(manager);
        manager->setFocusChangedCallback(nullptr);
    }
}

// WASM-specific: Store per-manager emscripten::val callbacks for
// scroll-into-view
std::unordered_map<rive::FocusManager*, emscripten::val>
    g_scrollIntoViewCallbacksWasm;

// Broadcast thunk for scroll-into-view
static void scrollIntoViewBroadcastThunk(const rive::AABB& bounds,
                                         rive::Artboard* rootArtboard)
{
    for (auto& pair : g_scrollIntoViewCallbacksWasm)
    {
        if (!pair.second.isNull() && !pair.second.isUndefined())
        {
            pair.second(bounds.minX,
                        bounds.minY,
                        bounds.maxX,
                        bounds.maxY,
                        reinterpret_cast<uintptr_t>(rootArtboard));
        }
    }
}

void focusManagerSetScrollIntoViewCallback(WasmPtr managerPtr,
                                           emscripten::val callback)
{
    auto* manager = reinterpret_cast<rive::FocusManager*>(managerPtr);
    if (manager == nullptr)
        return;

    if (!callback.isNull() && !callback.isUndefined())
    {
        g_scrollIntoViewCallbacksWasm[manager] = callback;
        manager->setScrollIntoViewCallback(scrollIntoViewBroadcastThunk);
    }
    else
    {
        g_scrollIntoViewCallbacksWasm.erase(manager);
        manager->setScrollIntoViewCallback(nullptr);
    }
}
#else
EXPORT void focusManagerSetScrollIntoViewCallback(
    void* manager,
    ScrollIntoViewCallback callback)
{
    if (manager == nullptr)
        return;
    g_scrollIntoViewCallback = callback;
    static_cast<rive::FocusManager*>(manager)->setScrollIntoViewCallback(
        callback != nullptr ? scrollIntoViewThunk : nullptr);
}
#endif
#else
using ScrollIntoViewCallback = void (*)(float minX,
                                        float minY,
                                        float maxX,
                                        float maxY,
                                        void* rootArtboard);
EXPORT void focusManagerSetScrollIntoViewCallback(
    void* manager,
    ScrollIntoViewCallback callback)
{}
using FocusChangedCallback = void (*)();
EXPORT void focusManagerSetFocusChangedCallback(void* manager,
                                                FocusChangedCallback callback)
{}
#endif

#ifdef WITH_RIVE_TOOLS
// Artboard - root FocusData access
// These allow Dart to get FocusNodes from native FocusData objects in an
// artboard

EXPORT SizeType artboardRootFocusDataCount(WrappedArtboard* wrappedArtboard)
{
    if (wrappedArtboard == nullptr)
        return 0;
    return wrappedArtboard->artboard()->rootFocusDataCount();
}

EXPORT void* artboardRootFocusNodeAt(WrappedArtboard* wrappedArtboard,
                                     SizeType index)
{
    if (wrappedArtboard == nullptr)
        return nullptr;
    auto* focusData = wrappedArtboard->artboard()->rootFocusDataAt(index);
    if (focusData == nullptr)
        return nullptr;
    // Return the raw FocusNode pointer - it's compatible with FocusNode* FFI
    return focusData->focusNode().get();
}

// Set an external parent FocusNode on an artboard.
// This allows focus nodes in nested artboards to be children of a FocusData
// in the host artboard, even across artboard boundaries.
EXPORT void artboardSetExternalParentFocusNode(WrappedArtboard* wrappedArtboard,
                                               void* focusNode)
{
    if (wrappedArtboard == nullptr)
        return;
    rive::rcp<rive::FocusNode> node =
        focusNode ? rive::ref_rcp(static_cast<DartFocusNode*>(focusNode))
                  : nullptr;
    wrappedArtboard->artboard()->setExternalParentFocusNode(std::move(node));
}
#endif

// Build focus tree for an artboard using a parent FocusNode.
// The FocusManager is derived from the parent node's manager() reference.
// This is a convenience method for nested artboards.
EXPORT void artboardBuildFocusTreeWithParent(WrappedArtboard* wrappedArtboard,
                                             void* parentFocusNodePtr)
{
    if (wrappedArtboard == nullptr)
        return;
    rive::rcp<rive::FocusNode> parentNode =
        parentFocusNodePtr
            ? rive::ref_rcp(static_cast<DartFocusNode*>(parentFocusNodePtr))
            : nullptr;
    wrappedArtboard->artboard()->buildFocusTree(parentNode);
}

// Get the focus manager from a state machine instance.
// This returns the active focus manager (external if set, internal otherwise).
EXPORT FocusManager* stateMachineGetFocusManager(
    WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
        return nullptr;
    return wrappedMachine->stateMachine()->focusManager();
}

// Set an external focus manager on a state machine instance.
// This allows nested artboards to share focus with their parent.
EXPORT void stateMachineSetExternalFocusManager(
    WrappedStateMachine* wrappedMachine,
    FocusManager* focusManager)
{
    if (wrappedMachine == nullptr)
        return;
    wrappedMachine->stateMachine()->setExternalFocusManager(focusManager);
}

// ============================================================
// Semantics diff FFI
// ============================================================

struct SemanticsDiffNodeFFI
{
    uint32_t id;
    uint32_t role;
    const char* label; // null-terminated, valid until freeSemanticDiff
    const char* value; // null-terminated, valid until freeSemanticDiff
    const char* hint;  // null-terminated, valid until freeSemanticDiff
    uint32_t stateFlags;
    uint32_t traitFlags;
    float minX, minY, maxX, maxY;
    int32_t parentId;
    uint32_t siblingIndex;
    uint32_t headingLevel;
};

struct SemanticsChildrenUpdateFFI
{
    int32_t parentId;
    const uint32_t* childIds;
    uint32_t childCount;
};

struct SemanticsBoundsUpdateFFI
{
    uint32_t id;
    float minX, minY, maxX, maxY;
};

struct SemanticsDiffFFI
{
    uint64_t treeVersion;
    uint32_t frameNumber;
    uint32_t rootId;

    const SemanticsDiffNodeFFI* added;
    uint32_t addedCount;
    const uint32_t* removed;

    uint32_t removedCount;
    const SemanticsDiffNodeFFI* moved;
    uint32_t movedCount;
    const SemanticsDiffNodeFFI* updatedSemantic;
    uint32_t updatedSemanticCount;
    const SemanticsBoundsUpdateFFI* updatedGeometry;
    uint32_t updatedGeometryCount;
    const SemanticsChildrenUpdateFFI* childrenUpdated;
    uint32_t childrenUpdatedCount;
};

// Pointer-free structs have identical layout on 32-bit WASM and 64-bit native,
// so this assert is universal.
static_assert(sizeof(SemanticsBoundsUpdateFFI) == 20,
              "SemanticsBoundsUpdateFFI must match Dart/WASM readers");

// Structs containing pointers differ between 32-bit WASM and 64-bit native.
// The Dart-side layout is hand-maintained in two places:
//   - rive_semantic_web.dart (WASM): hardcoded DataView offsets for 32-bit.
//   - rive_semantic_ffi.dart (native): @Struct fields that Dart FFI lays out
//     per the host C ABI.
// Dart does NOT validate either layout against the C side at link time, so we
// assert the C struct sizes here as a tripwire: if a field is added/reordered
// in C++ without a matching edit to the Dart mirror, the C++ build fails
// loudly instead of silently returning wrong field values at runtime.
#if defined(__EMSCRIPTEN__)
static_assert(
    sizeof(SemanticsDiffNodeFFI) == 56,
    "WASM SemanticsDiffNodeFFI layout drifted from rive_semantic_web.dart");
static_assert(
    sizeof(SemanticsChildrenUpdateFFI) == 12,
    "WASM SemanticsChildrenUpdateFFI layout drifted from rive_semantic_web.dart");
static_assert(
    sizeof(SemanticsDiffFFI) == 64,
    "WASM SemanticsDiffFFI layout drifted from rive_semantic_web.dart");
#elif UINTPTR_MAX == UINT64_MAX
// 64-bit native (LP64/LLP64). 32-bit native is not exercised; if ever
// added, verify sizes against rive_semantic_ffi.dart and add a branch.
static_assert(
    sizeof(SemanticsDiffNodeFFI) == 72,
    "Native SemanticsDiffNodeFFI layout drifted from rive_semantic_ffi.dart");
static_assert(
    sizeof(SemanticsChildrenUpdateFFI) == 24,
    "Native SemanticsChildrenUpdateFFI layout drifted from rive_semantic_ffi.dart");
static_assert(
    sizeof(SemanticsDiffFFI) == 112,
    "Native SemanticsDiffFFI layout drifted from rive_semantic_ffi.dart");
#endif

// Null-on-empty avoids allocating a 1-byte "\0" buffer for every empty
// value/hint; the Dart/WASM decoders map nullptr to ''.
static const char* toCStringOrNull(const std::string& s)
{
    return s.empty() ? nullptr : toCString(s);
}

static SemanticsDiffNodeFFI toSemanticsDiffNodeFFI(
    const SemanticsDiffNode& node)
{
    SemanticsDiffNodeFFI ffi;
    ffi.id = node.id;
    ffi.role = node.role;
    ffi.label = toCStringOrNull(node.label);
    ffi.value = toCStringOrNull(node.value);
    ffi.hint = toCStringOrNull(node.hint);
    ffi.stateFlags = node.stateFlags;
    ffi.traitFlags = node.traitFlags;
    ffi.minX = node.minX;
    ffi.minY = node.minY;
    ffi.maxX = node.maxX;
    ffi.maxY = node.maxY;
    ffi.parentId = node.parentId;
    ffi.siblingIndex = node.siblingIndex;
    ffi.headingLevel = node.headingLevel;
    return ffi;
}

static SemanticsDiffFFI* toSemanticsDiffFFI(const SemanticsDiff& diff)
{
    auto* ffi = new SemanticsDiffFFI();
    ffi->treeVersion = diff.treeVersion;
    ffi->frameNumber = static_cast<uint32_t>(diff.frameNumber);
    ffi->rootId = diff.rootId;

    // added
    ffi->addedCount = static_cast<uint32_t>(diff.added.size());
    if (ffi->addedCount > 0)
    {
        auto* arr = new SemanticsDiffNodeFFI[ffi->addedCount];
        for (uint32_t i = 0; i < ffi->addedCount; ++i)
            arr[i] = toSemanticsDiffNodeFFI(diff.added[i]);
        ffi->added = arr;
    }
    else
    {
        ffi->added = nullptr;
    }

    // removed
    ffi->removedCount = static_cast<uint32_t>(diff.removed.size());
    if (ffi->removedCount > 0)
    {
        auto* arr = new uint32_t[ffi->removedCount];
        for (uint32_t i = 0; i < ffi->removedCount; ++i)
        {
            arr[i] = diff.removed[i];
        }
        ffi->removed = arr;
    }
    else
    {
        ffi->removed = nullptr;
    }

    // moved
    ffi->movedCount = static_cast<uint32_t>(diff.moved.size());
    if (ffi->movedCount > 0)
    {
        auto* arr = new SemanticsDiffNodeFFI[ffi->movedCount];
        for (uint32_t i = 0; i < ffi->movedCount; ++i)
            arr[i] = toSemanticsDiffNodeFFI(diff.moved[i]);
        ffi->moved = arr;
    }
    else
    {
        ffi->moved = nullptr;
    }

    // updatedSemantic
    ffi->updatedSemanticCount =
        static_cast<uint32_t>(diff.updatedSemantic.size());
    if (ffi->updatedSemanticCount > 0)
    {
        auto* arr = new SemanticsDiffNodeFFI[ffi->updatedSemanticCount];
        for (uint32_t i = 0; i < ffi->updatedSemanticCount; ++i)
            arr[i] = toSemanticsDiffNodeFFI(diff.updatedSemantic[i]);
        ffi->updatedSemantic = arr;
    }
    else
    {
        ffi->updatedSemantic = nullptr;
    }

    // updatedGeometry
    ffi->updatedGeometryCount =
        static_cast<uint32_t>(diff.updatedGeometry.size());
    if (ffi->updatedGeometryCount > 0)
    {
        auto* arr = new SemanticsBoundsUpdateFFI[ffi->updatedGeometryCount];
        for (uint32_t i = 0; i < ffi->updatedGeometryCount; ++i)
        {
            const auto& b = diff.updatedGeometry[i];
            arr[i].id = b.id;
            arr[i].minX = b.minX;
            arr[i].minY = b.minY;
            arr[i].maxX = b.maxX;
            arr[i].maxY = b.maxY;
        }
        ffi->updatedGeometry = arr;
    }
    else
    {
        ffi->updatedGeometry = nullptr;
    }

    // childrenUpdated
    ffi->childrenUpdatedCount =
        static_cast<uint32_t>(diff.childrenUpdated.size());
    if (ffi->childrenUpdatedCount > 0)
    {
        auto* arr = new SemanticsChildrenUpdateFFI[ffi->childrenUpdatedCount];
        for (uint32_t i = 0; i < ffi->childrenUpdatedCount; ++i)
        {
            const auto& cu = diff.childrenUpdated[i];
            arr[i].parentId = cu.parentId;
            arr[i].childCount = static_cast<uint32_t>(cu.childIds.size());
            if (arr[i].childCount > 0)
            {
                auto* ids = new uint32_t[arr[i].childCount];
                for (uint32_t j = 0; j < arr[i].childCount; ++j)
                    ids[j] = cu.childIds[j];
                arr[i].childIds = ids;
            }
            else
            {
                arr[i].childIds = nullptr;
            }
        }
        ffi->childrenUpdated = arr;
    }
    else
    {
        ffi->childrenUpdated = nullptr;
    }

    return ffi;
}

EXPORT void stateMachineEnableSemantics(WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
        return;
    wrappedMachine->stateMachine()->enableSemantics();
}

EXPORT SemanticsDiffFFI* stateMachineDrainSemanticsDiff(
    WrappedStateMachine* wrappedMachine)
{
    if (wrappedMachine == nullptr)
        return nullptr;
    auto* manager = wrappedMachine->stateMachine()->semanticManager();
    if (manager == nullptr)
        return nullptr;
    auto diff = manager->drainDiff();
    if (diff.empty())
        return nullptr;
    return toSemanticsDiffFFI(diff);
}

EXPORT bool stateMachineFocusSemanticNode(WrappedStateMachine* wrappedMachine,
                                          uint32_t semanticNodeId)
{
    if (wrappedMachine == nullptr)
        return false;
    auto* manager = wrappedMachine->stateMachine()->semanticManager();
    if (manager == nullptr)
        return false;
    return manager->requestFocus(semanticNodeId);
}

EXPORT void stateMachineFireSemanticAction(WrappedStateMachine* wrappedMachine,
                                           uint32_t semanticNodeId,
                                           uint8_t actionType)
{
    if (wrappedMachine == nullptr)
        return;
    wrappedMachine->stateMachine()->fireSemanticAction(
        semanticNodeId,
        static_cast<rive::SemanticActionType>(actionType));
}

EXPORT void freeSemanticDiff(SemanticsDiffFFI* diff)
{
    if (diff == nullptr)
        return;

    auto freeNodes = [](const SemanticsDiffNodeFFI* arr, uint32_t count) {
        if (arr == nullptr)
            return;
        for (uint32_t i = 0; i < count; ++i)
        {
            // Strings were allocated by toCString (malloc), free with std::free
            if (arr[i].label != nullptr)
                std::free((void*)arr[i].label);
            if (arr[i].value != nullptr)
                std::free((void*)arr[i].value);
            if (arr[i].hint != nullptr)
                std::free((void*)arr[i].hint);
        }
        delete[] arr;
    };

    freeNodes(diff->added, diff->addedCount);
    delete[] diff->removed;
    freeNodes(diff->moved, diff->movedCount);
    freeNodes(diff->updatedSemantic, diff->updatedSemanticCount);
    // updatedGeometry is POD (no heap strings) — simple delete[] suffices.
    delete[] diff->updatedGeometry;

    if (diff->childrenUpdated != nullptr)
    {
        for (uint32_t i = 0; i < diff->childrenUpdatedCount; ++i)
        {
            delete[] diff->childrenUpdated[i].childIds;
        }
        delete[] diff->childrenUpdated;
    }

    delete diff;
}

#ifdef __EMSCRIPTEN__
EMSCRIPTEN_BINDINGS(RiveBinding)
{
    function("loadRiveFile", &loadRiveFile, allow_raw_pointers());
    function("stateMachineReportedEventAt", &stateMachineReportedEventAt);
    function("viewModelRuntimeProperties", &viewModelRuntimeProperties);
    function("fileEnums", &fileEnums);
    function("vmiRuntimeProperties", &vmiRuntimeProperties);
    function("getEventCustomProperty", &getEventCustomProperty);
    function("setArtboardLayoutChangedCallback",
             &setArtboardLayoutChangedCallback);
    function("setArtboardLayoutDirtyCallback", &setArtboardLayoutDirtyCallback);
    function("setArtboardTransformDirtyCallback",
             &setArtboardTransformDirtyCallback);
    function("setStateMachineInputChangedCallback",
             &setStateMachineInputChangedCallback);
    function("setArtboardEventCallback", &setArtboardEventCallback);
    function("setStateMachineDataBindChangedCallback",
             &setStateMachineDataBindChangedCallback);
    function("initBindingCallbacks", &initBindingCallbacks);
    function("setArtboardTestBoundsCallback", &setArtboardTestBoundsCallback);
    function("setArtboardIsAncestorCallback", &setArtboardIsAncestorCallback);
    function("setArtboardRootTransformCallback",
             &setArtboardRootTransformCallback);
    function("artboardGetAllTextRuns", &artboardGetAllTextRuns);
    // Profiler functions (stubs unless built with RIVE_MICROPROFILE)
    function("profilerStart", &profilerStart);
    function("profilerStop", &profilerStop);
    function("profilerIsActive", &profilerIsActive);
    function("profilerDump", &profilerDump);
    // Return the buffer address as an integer so embind doesn't need to bind
    // `const uint8_t*` (which triggers UnboundTypeError at call time).
    function(
        "profilerGetBufferPtr",
        +[]() -> uintptr_t {
            return reinterpret_cast<uintptr_t>(profilerGetBufferPtr());
        });
    function("profilerGetBufferSize", &profilerGetBufferSize);
    function("profilerFreeBuffer", &profilerFreeBuffer);
    function("profilerEndFrame", &profilerEndFrame);

    // FocusNode creation with WASM callbacks
    function("makeFocusNodeWasm", &makeFocusNodeWasm);
    function("disposeFocusNodeWasm", &disposeFocusNodeWasm);

    function("focusManagerGetPrimaryFocusBounds",
             &focusManagerGetPrimaryFocusBounds);

    // FocusBoundsResult struct for WASM (used by
    // focusManagerGetPrimaryFocusBounds)
    value_object<FocusBoundsResult>("FocusBoundsResult")
        .field("valid", &FocusBoundsResult::valid)
        .field("minX", &FocusBoundsResult::minX)
        .field("minY", &FocusBoundsResult::minY)
        .field("maxX", &FocusBoundsResult::maxX)
        .field("maxY", &FocusBoundsResult::maxY);

#ifdef WITH_RIVE_TOOLS
    // FocusManager callbacks — the runtime's setFocusChangedCallback /
    // setScrollIntoViewCallback only exist WITH_RIVE_TOOLS.
    function("focusManagerSetFocusChangedCallback",
             &focusManagerSetFocusChangedCallbackWasm);
    function("focusManagerSetScrollIntoViewCallback",
             &focusManagerSetScrollIntoViewCallback);
#endif

    value_object<TextRunArrayResult>("TextRunArrayResult")
        .field("array", &TextRunArrayResult::array)
        .field("count", &TextRunArrayResult::count);

    value_object<FlutterRuntimeReportedEvent>("FlutterRuntimeReportedEvent")
        .field("event", &FlutterRuntimeReportedEvent::event)
        .field("secondsDelay", &FlutterRuntimeReportedEvent::secondsDelay)
        .field("type", &FlutterRuntimeReportedEvent::type);

    value_object<FlutterRuntimeCustomProperty>("FlutterRuntimeCustomProperty")
        .field("property", &FlutterRuntimeCustomProperty::property)
        .field("name", &FlutterRuntimeCustomProperty::name)
        .field("type", &FlutterRuntimeCustomProperty::type);

#ifdef WITH_RIVE_TOOLS
    value_object<ViewModelInstanceBufferResponse>(
        "ViewModelInstanceBufferResponse")
        .field("data", &ViewModelInstanceBufferResponse::data)
        .field("size", &ViewModelInstanceBufferResponse::size);
    function("requestSerializedViewModelInstanceWasm",
             optional_override([](WasmPtr file, WasmPtr viewModelInstance)
                                   -> ViewModelInstanceBufferResponse {
                 return requestSerializedViewModelInstanceWasm(
                     (rive::File*)file,
                     (rive::ViewModelInstance*)viewModelInstance);
             }));
    function("freeViewModelInstanceSerializedDataWasm",
             &freeViewModelInstanceSerializedDataWasm);
#endif
}
#endif