#include "rive_native/rive_native_plugin.hpp"
#pragma warning(push)
#pragma warning(disable : 4702)
#include "spdlog/spdlog.h"
#pragma warning(pop)
#include "spdlog/sinks/win_eventlog_sink.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <cstdint>

using namespace spdlog;

static void onRendererEnd(void* userData)
{
    auto renderer = (RiveNativeRenderTexture*)userData;
    renderer->end();
}

static std::string convertWindowsString(WCHAR* wideString)
{
    int buffer_size = WideCharToMultiByte(CP_UTF8,
                                          0,
                                          wideString,
                                          -1,
                                          nullptr,
                                          0,
                                          nullptr,
                                          nullptr);
    char* narrow_buffer = new char[buffer_size];
    WideCharToMultiByte(CP_UTF8,
                        0,
                        wideString,
                        -1,
                        narrow_buffer,
                        buffer_size,
                        nullptr,
                        nullptr);
    std::string narrow_str(narrow_buffer);
    delete[] narrow_buffer;
    return narrow_str;
}

RiveNativeRenderTexture::RiveNativeRenderTexture(
    ID3D11Device* gpu,
    void* riveRendererContext,
    uint32_t width,
    uint32_t height,
    flutter::TextureRegistrar* textureRegistrar) :
    m_flutterSurfaceDescs(),
    m_swapchain(
        // Since we don't have control over synchronization with the Flutter
        // compositor, create a swapchain of *FOUR* textures in order to reduce
        // the likelihood of drawing on top of a texture while it's still being
        // read.
        makeSwapchainTexture(gpu,
                             width,
                             height,
                             /*doClear=*/true), // presentingTexture
        makeSwapchainTexture(gpu,
                             width,
                             height,
                             /*doClear=*/false), // renderTextures
        makeSwapchainTexture(gpu, width, height, /*doClear=*/false),
        makeSwapchainTexture(gpu, width, height, /*doClear=*/false)),
    m_textureRegistrar(textureRegistrar)
{
    m_textureVariant =
        std::make_unique<flutter::TextureVariant>(flutter::GpuSurfaceTexture(
            kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
            [this](auto, auto) {
                FlutterWindowsSwapchain::PresentingTextureLock
                    presentingTextureLock(&m_swapchain);
                return &m_flutterSurfaceDescs[presentingTextureLock.texture()
                                                  ->flutterSurfaceDescIdx];
            }));

    m_id = m_textureRegistrar->RegisterTexture(m_textureVariant.get());
    m_riveRenderer = createRiveRenderer(this,
                                        (void*)textureRegistrar,
                                        riveRendererContext,
                                        &m_swapchain,
                                        &onRendererEnd,
                                        width,
                                        height);
}

std::unique_ptr<FlutterWindowsTexture> RiveNativeRenderTexture::
    makeSwapchainTexture(ID3D11Device* gpu,
                         UINT width,
                         UINT height,
                         bool doClear)
{
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS | D3D11_BIND_SHADER_RESOURCE |
                     D3D11_BIND_RENDER_TARGET;
    desc.CPUAccessFlags = 0;
    desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

    auto swapchainTexture = std::make_unique<FlutterWindowsTexture>();

    const D3D11_SUBRESOURCE_DATA* initialData = nullptr;
    std::vector<UINT> pixelData;
    D3D11_SUBRESOURCE_DATA initialDataStorage;
    if (doClear)
    {
        pixelData.resize(height * width);
        memset(pixelData.data(), 0, pixelData.size() * sizeof(UINT));
        initialDataStorage.pSysMem = pixelData.data();
        initialDataStorage.SysMemPitch = width * sizeof(UINT);
        initialData = &initialDataStorage;
    }
    gpu->CreateTexture2D(
        &desc,
        initialData,
        swapchainTexture->nativeTexture.ReleaseAndGetAddressOf());

    swapchainTexture->flutterSurfaceDescIdx = m_flutterSurfaceDescs.size();
    auto& flutterSurfaceDesc =
        m_flutterSurfaceDescs.emplace_back(FlutterDesktopGpuSurfaceDescriptor{
            .struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor),
            .handle = nullptr,
            .width = width,
            .height = height,
            .visible_width = width,
            .visible_height = height,
            .format = kFlutterDesktopPixelFormatBGRA8888,
            .release_callback = [](void* release_context) {},
            .release_context = nullptr,
        });
    ComPtr<IDXGIResource> asDxgiResource;
    swapchainTexture->nativeTexture.As(&asDxgiResource);
    asDxgiResource->GetSharedHandle(&flutterSurfaceDesc.handle);
    return swapchainTexture;
}

void RiveNativeRenderTexture::end()
{
    m_textureRegistrar->MarkTextureFrameAvailable(m_id);
}

RiveNativeRenderTexture::~RiveNativeRenderTexture()
{
    destroyRiveRenderer(m_riveRenderer);
}

void RiveNativePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar)
{
    auto plugin = std::make_unique<RiveNativePlugin>(
        registrar,
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(),
            "rive_native",
            &flutter::StandardMethodCodec::GetInstance()),
        registrar->texture_registrar());
    plugin->channel()->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });
    registrar->AddPlugin(std::move(plugin));
}

// Dart API
bool usePLS = true;

class FlutterRenderer;
namespace rive
{
class Font;
class RenderPath;
class AudioEngine;
} // namespace rive

EXPORT void rewindRenderPath(rive::RenderPath* path);

RiveNativePlugin::RiveNativePlugin(
    flutter::PluginRegistrarWindows* registrar,
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel,
    flutter::TextureRegistrar* texture_registrar) :
    m_registrar(registrar),
    m_channel(std::move(channel)),
    m_textureRegistrar(texture_registrar)
{
    // Setup spdlog to use the windows event log
    auto sink =
        std::make_shared<spdlog::sinks::win_eventlog_sink_mt>("rive_native");
    sink->set_pattern("%v");
    auto logger = std::make_shared<spdlog::logger>("eventlog", sink);
    logger->set_level(spdlog::level::trace);
    spdlog::set_default_logger(logger);

    trace("RiveNativePlugin::RiveNativePlugin");

    ComPtr<IDXGIFactory2> factory;
    CreateDXGIFactory(
        __uuidof(IDXGIFactory2),
        reinterpret_cast<void**>(factory.ReleaseAndGetAddressOf()));

    auto view =
        static_cast<flutter::PluginRegistrarWindows*>(registrar)->GetView();
    if (view == nullptr)
    {
        error("Rive failed to find a Flutter View.");
        return;
    }
    auto desiredAdapter =
        static_cast<flutter::PluginRegistrarWindows*>(registrar)
            ->GetView()
            ->GetGraphicsAdapter();
    if (desiredAdapter == nullptr)
    {
        error("Rive failed to find a Graphics Adapter.");
        return;
    }
    DXGI_ADAPTER_DESC desiredDesc{};
    desiredAdapter->GetDesc(&desiredDesc);
    bool isIntel = desiredDesc.VendorId == 0x163C ||
                   desiredDesc.VendorId == 0x8086 ||
                   desiredDesc.VendorId == 0x8087;
    info("Trying to use D3D device: {}",
         convertWindowsString(desiredDesc.Description));

    ComPtr<ID3D11Device> gpu;
    ComPtr<ID3D11DeviceContext> gpuContext;
    D3D_FEATURE_LEVEL featureLevels[] = {D3D_FEATURE_LEVEL_11_1};
    UINT creationFlags = 0;

    HRESULT result = D3D11CreateDevice(desiredAdapter,
                                       D3D_DRIVER_TYPE_UNKNOWN,
                                       NULL,
                                       creationFlags,
                                       featureLevels,
                                       (UINT)std::size(featureLevels),
                                       D3D11_SDK_VERSION,
                                       gpu.ReleaseAndGetAddressOf(),
                                       NULL,
                                       gpuContext.ReleaseAndGetAddressOf());
    if (result != S_OK)
    {
        info("Failed to init device with adapter, will try default: {}",
             convertWindowsString(desiredDesc.Description));
        D3D11CreateDevice(NULL,
                          D3D_DRIVER_TYPE_UNKNOWN,
                          NULL,
                          creationFlags,
                          featureLevels,
                          (UINT)std::size(featureLevels),
                          D3D11_SDK_VERSION,
                          gpu.ReleaseAndGetAddressOf(),
                          NULL,
                          gpuContext.ReleaseAndGetAddressOf());
    }
    if (gpu && gpuContext)
    {
        info("Got D3D device!");
    }
    else
    {
        error("Failed to init D3D device.");
        return;
    }

    m_factory = std::move(factory);
    m_gpu = std::move(gpu);
    m_gpuContext = std::move(gpuContext);
    m_isIntelGpu = isIntel;
    trace("Making renderer context");
    m_riveRendererContext =
        createRiveRendererContext(m_gpu, m_gpuContext, isIntel);
    trace("Made renderer context: {}", m_riveRendererContext);
}

RiveNativePlugin::~RiveNativePlugin()
{
    // Engine shutdown: async unregister callbacks would never run, so delete
    // synchronously to join each fence thread before the registrar dies.
    for (auto& [id, renderTexture] : m_renderTextures)
    {
        m_textureRegistrar->UnregisterTexture(id);
        delete renderTexture;
    }
    m_renderTextures.clear();
    if (m_riveRendererContext != nullptr)
    {
        destroyRiveRendererContext(m_riveRendererContext);
    }
}

void RiveNativePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
{
    if (method_call.method_name().compare("createTexture") == 0)
    {
        if (m_riveRendererContext == nullptr)
        {
            result->Error("Rive Renderer is not suppored on this device.",
                          nullptr);
            return;
        }
        auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args == nullptr)
        {
            result->Error("CreateTexture error",
                          "No arguments received by the native part of "
                          "RiveNative.createTexture",
                          nullptr);
            return;
        }
        auto widthItr = args->find(flutter::EncodableValue("width"));
        if (widthItr == args->end())
        {
            result->Error("CreateTexture error",
                          "No width received by the native part of "
                          "RiveNative.createTexture",
                          nullptr);
            return;
        }
        int64_t width = widthItr->second.LongValue();

        auto heightItr = args->find(flutter::EncodableValue("height"));
        if (heightItr == args->end())
        {
            result->Error("CreateTexture error",
                          "No height received by the native part of "
                          "RiveNative.createTexture",
                          nullptr);
            return;
        }
        int64_t height = heightItr->second.LongValue();

        auto renderTexture =
            new RiveNativeRenderTexture(m_gpu.Get(),
                                        m_riveRendererContext,
                                        static_cast<uint32_t>(width),
                                        static_cast<uint32_t>(height),
                                        m_textureRegistrar);
        m_renderTextures[renderTexture->id()] = renderTexture;

        flutter::EncodableMap map;
        map[flutter::EncodableValue("textureId")] = renderTexture->id();

        char buff[255];
        snprintf(buff, 255, "%p", (void*)renderTexture->riveRenderer());
        map[flutter::EncodableValue("renderer")] = std::string(buff);
        result->Success(flutter::EncodableValue(map));
    }
    else if (method_call.method_name().compare("getRenderContext") == 0)
    {
        flutter::EncodableMap map;
        char buff[255];
        snprintf(buff,
                 255,
                 "%p",
                 factoryFromRiveRendererContext(m_riveRendererContext));
        map[flutter::EncodableValue("rendererContext")] = std::string(buff);
        result->Success(flutter::EncodableValue(map));
    }
    else if (method_call.method_name().compare("removeTexture") == 0)
    {
        auto args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args == nullptr)
        {
            result->Error("removeTexture error",
                          "no arguments received by the native part of "
                          "RiveNative.removeTexture",
                          nullptr);
            return;
        }
        auto idItr = args->find(flutter::EncodableValue("id"));
        if (idItr == args->end())
        {
            result->Error(
                "removeTexture error",
                "no id received by the native part of RiveNative.removeTexture",
                nullptr);
            return;
        }
        int64_t id = idItr->second.LongValue();

        auto itr = m_renderTextures.find(id);
        if (itr != m_renderTextures.end())
        {
            auto renderTexture = itr->second;
            m_renderTextures.erase(itr);
            // Unregistration completes asynchronously; deleting sooner would
            // free the texture variant while the engine can still touch it.
            m_textureRegistrar->UnregisterTexture(
                renderTexture->id(),
                [renderTexture] { delete renderTexture; });
        }
        result->Success();
    }
    else
    {
        result->NotImplemented();
    }
}
