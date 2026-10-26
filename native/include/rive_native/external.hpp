#ifndef _SBS_EXTERNAL_H_
#define _SBS_EXTERNAL_H_
#include <cstdint>
#if defined(_MSC_VER)
#include "rive_native/swapchain.hpp"
#include <d3d11.h>
#include <wrl/client.h>
typedef void (*RendererEndCallback)(void*);
#else
#include "rive_native/read_write_ring.hpp"
#endif

namespace rive
{
class Renderer;
}

#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
#define EXPORT extern "C" EMSCRIPTEN_KEEPALIVE
#define PLUGIN_API extern "C" EMSCRIPTEN_KEEPALIVE
#elif defined(_MSC_VER)
#define EXPORT extern "C" __declspec(dllexport)
#if defined(RIVE_NATIVE_SHARED)
#define PLUGIN_API __declspec(dllexport)
#else
#define PLUGIN_API __declspec(dllimport)
#endif
#else
#define PLUGIN_API                                                             \
    extern "C" __attribute__((visibility("default"))) __attribute__((used))
#define EXPORT                                                                 \
    extern "C" __attribute__((visibility("default"))) __attribute__((used))
#endif

#if defined(__EMSCRIPTEN__)
using WasmPtr = uint32_t;
using SizeType = uint32_t;
#define CAST_POINTER (WasmPtr)
#define CAST_SIZE (uint32_t)
#define CALLBACK_VALID(v) (!v.isNull())
#define RESET_CALLBACK(v) v = val::null()
#else
using SizeType = uint64_t;
#define CAST_POINTER
#define CAST_SIZE
#define CALLBACK_VALID(v) (v != nullptr)
#define RESET_CALLBACK(v) v = nullptr
#endif

#if defined(_MSC_VER)
struct FlutterWindowsTexture
{
    Microsoft::WRL::ComPtr<ID3D11Texture2D> nativeTexture;
    size_t flutterSurfaceDescIdx;
};
using FlutterWindowsSwapchain =
    Swapchain<std::unique_ptr<FlutterWindowsTexture>>;
#endif

// Provided to the host.
PLUGIN_API void* createRiveRenderer(
#if defined(_MSC_VER) || defined(__APPLE__)
    void* nativeRenderTexture,
#endif
#ifndef __ANDROID__
    void* textureRegistry,
    void* riveRendererContext,
#endif
#if defined(_MSC_VER)
    FlutterWindowsSwapchain*,
    RendererEndCallback rendererEndCallback,
#else
    void* queue,
    ReadWriteRing* ring,
    void* texture0,
    void* texture1,
    void* texture2,
#endif
    uint32_t width,
    uint32_t height);
PLUGIN_API void destroyRiveRenderer(void* renderer);
PLUGIN_API void riveLock();
PLUGIN_API void riveUnlock();

PLUGIN_API void* createRiveRendererContext(
#if defined(_MSC_VER)
    Microsoft::WRL::ComPtr<ID3D11Device> gpu,
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> gpuContext,
    bool isIntel
#else
    void* gpu
#endif
);
PLUGIN_API void* factoryFromRiveRendererContext(void* context);
PLUGIN_API void destroyRiveRendererContext(void* context);
PLUGIN_API void setGPU(void* gpu, void* queue);

// Headless rendering for tests (no Flutter plugin required).
// Only available on Apple platforms (Metal).
#if defined(__APPLE__) && !defined(__EMSCRIPTEN__)
EXPORT void* createHeadlessContext(bool disableFramebufferReads);
EXPORT void* headlessContextFactory(void* headlessContext);
EXPORT void* createHeadlessRenderer(void* headlessContext,
                                    uint32_t width,
                                    uint32_t height);
EXPORT bool headlessClear(void* renderer, bool doClear, uint32_t color);
EXPORT bool headlessFlush(void* renderer, float devicePixelRatio);
EXPORT rive::Renderer* headlessMakeRenderer(void* renderer);
EXPORT bool headlessReadPixels(void* renderer, uint8_t* buffer);
EXPORT void destroyHeadlessRenderer(void* renderer);
EXPORT void destroyHeadlessContext(void* headlessContext);
#endif

#endif
