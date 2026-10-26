#include "rive_native/external.hpp"
#include "rive_native/fence_wait_thread.hpp"
#include "rive_native/rive_binding.hpp"
#include "rive/renderer/d3d11/render_context_d3d_impl.hpp"
#include "rive/renderer/rive_renderer.hpp"
#include <unordered_map>
#include <d3d11_4.h>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN 1
#endif
#include <Windows.h>

class WindowsContextPLS;

class RiveNativeRendererContext : public rive::RefCnt<RiveNativeRendererContext>
{
public:
    RiveNativeRendererContext(
        std::unique_ptr<rive::gpu::RenderContext>&& context) :
        actual(std::move(context))
    {}

    std::unique_ptr<rive::gpu::RenderContext> actual;
};

class WindowsContextPLS
{
public:
    WindowsContextPLS(void* userData,
                      RiveNativeRendererContext* rendererContext,
                      FlutterWindowsSwapchain* swapchain,
                      uint32_t width,
                      uint32_t height,
                      RendererEndCallback rendererEndCallback) :
        m_swapchain(swapchain),
        m_renderContext(rive::ref_rcp(rendererContext)),
        m_width(width),
        m_height(height),
        m_userData(userData),
        m_rendererEndCallback(rendererEndCallback)
    {
        auto renderCtxImpl =
            m_renderContext->actual
                ->static_impl_cast<rive::gpu::RenderContextD3DImpl>();
        m_renderTarget = renderCtxImpl->makeRenderTarget(width, height);
        m_renderer =
            std::make_unique<rive::RiveRenderer>(m_renderContext->actual.get());

        // Attempt to acquire the interfaces necessary for working with fences.
        renderCtxImpl->gpu()->QueryInterface(__uuidof(ID3D11Device5), &m_gpu5);
        renderCtxImpl->gpuContext()->QueryInterface(
            __uuidof(ID3D11DeviceContext4),
            &m_gpuContext4);
        if (m_gpu5 != nullptr && m_gpuContext4 != nullptr)
        {
            // Fences are supported. Create one to track the end of frames.
            VERIFY_OK(m_gpu5->CreateFence(m_lastFrameIndex,
                                          D3D11_FENCE_FLAG_NONE,
                                          __uuidof(ID3D11Fence),
                                          (void**)&m_lastFrameFence));
            m_fenceWaitThread =
                std::make_unique<FenceWaitThread>([this](uint64_t frameIndex) {
                    // Wait until the fence completes.
                    VERIFY_OK(m_lastFrameFence->SetEventOnCompletion(frameIndex,
                                                                     nullptr));

                    // Present the last texture now that the GPU has finished
                    // rendering it.
                    m_swapchain->presentTexture(std::move(m_lastFrameTexture));
                    m_rendererEndCallback(m_userData);
                });
        }
        else
        {
            // Fences are NOT supported. Create a query instead to track when
            // frames complete.
            D3D11_QUERY_DESC queryDesc{};
            queryDesc.Query = D3D11_QUERY_EVENT;
            renderCtxImpl->gpu()->CreateQuery(
                &queryDesc,
                m_fallbackCompletionQuery.ReleaseAndGetAddressOf());
        }
    }

    ~WindowsContextPLS()
    {
        // Drains any in-flight frame and joins before other members go away.
        m_fenceWaitThread.reset();
    }

    void begin(bool clear, uint32_t color)
    {
        m_renderContext->actual->beginFrame({
            .renderTargetWidth = m_width,
            .renderTargetHeight = m_height,
            .loadAction = clear ? rive::gpu::LoadAction::clear
                                : rive::gpu::LoadAction::preserveRenderTarget,
            .clearColor = color,
            .disableRasterOrdering = true,
        });
    }

    void end(float devicePixelRatio)
    {
        auto renderContext = m_renderContext->actual.get();
        if (renderContext == nullptr)
        {
            return;
        }

        auto renderContextImpl =
            renderContext->static_impl_cast<rive::gpu::RenderContextD3DImpl>();
        auto swapchainTexture = m_swapchain->acquireRenderTexture();

        m_renderTarget->setTargetTexture(swapchainTexture->nativeTexture.Get());

        if (m_lastFrameFence == nullptr)
        {
            // Fences are not supported. Begin a query track the current frame.
            renderContextImpl->gpuContext()->Begin(
                m_fallbackCompletionQuery.Get());
        }

        renderContext->flush({.renderTarget = m_renderTarget.get()});

        if (m_lastFrameFence != nullptr)
        {
            // Block until m_fenceWaitThread has finished waiting on the
            // fence and has presented the previous frame texture.
            m_fenceWaitThread->waitForIdle();

            // Insert a fence for this frame.
            VERIFY_OK(m_gpuContext4->Signal(m_lastFrameFence.Get(),
                                            ++m_lastFrameIndex));
        }
        else
        {
            // End the query for this frame.
            renderContextImpl->gpuContext()->End(
                m_fallbackCompletionQuery.Get());
        }

        renderContextImpl->gpuContext()->Flush();
        m_lastFrameTexture = std::move(swapchainTexture);

        if (m_lastFrameFence != nullptr)
        {
            // Kick off m_fenceWaitThread to wait on this frame's fence and then
            // present the texture.
            m_fenceWaitThread->kick(m_lastFrameIndex);
        }
        else
        {
            // Query if the GPU has finished rendering this frame.
            while (renderContextImpl->gpuContext()->GetData(
                       m_fallbackCompletionQuery.Get(),
                       nullptr,
                       0,
                       0) == S_FALSE)
            {
                // Poll m_fallbackCompletionQuery until the GPU is done. This is
                // a blocking operation that will hurt performance, but we only
                // have to do it when fences aren't supported. Fences have been
                // in D3D11 since the Windows 10 Creators Update (Version 1703),
                // released April 2017.
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }

            // Present the frame here since we don't have a background thread to
            // do it.
            m_swapchain->presentTexture(std::move(m_lastFrameTexture));
            m_rendererEndCallback(m_userData);
        }
    }

    rive::RiveRenderer* renderer() { return m_renderer.get(); }

    uint32_t width() { return m_width; }
    uint32_t height() { return m_height; }
    RiveNativeRendererContext* renderContext() { return m_renderContext.get(); }

private:
    FlutterWindowsSwapchain* m_swapchain;
    rive::rcp<RiveNativeRendererContext> m_renderContext;
    rive::rcp<rive::gpu::RenderTargetD3D> m_renderTarget;
    std::unique_ptr<rive::RiveRenderer> m_renderer;
    uint32_t m_width;
    uint32_t m_height;
    void* m_userData;

    // Data for waiting on frame fences, if supported by the hardware.
    ComPtr<ID3D11Device5> m_gpu5;
    ComPtr<ID3D11DeviceContext4> m_gpuContext4;
    ComPtr<ID3D11Fence> m_lastFrameFence;
    std::unique_ptr<FenceWaitThread> m_fenceWaitThread;
    std::unique_ptr<FlutterWindowsTexture> m_lastFrameTexture;
    uint64_t m_lastFrameIndex = 0;

    // Used as a fallback when fences aren't supported.
    ComPtr<ID3D11Query> m_fallbackCompletionQuery;
    RendererEndCallback m_rendererEndCallback;
};

PLUGIN_API void* createRiveRendererContext(
    ComPtr<ID3D11Device> gpu,
    ComPtr<ID3D11DeviceContext> gpuContext,
    bool isIntel)
{
    rive::gpu::D3DContextOptions contextOptions;
    contextOptions.isIntel = isIntel;
    auto context = new RiveNativeRendererContext(
        rive::gpu::RenderContextD3DImpl::MakeContext(gpu,
                                                     gpuContext,
                                                     contextOptions));
    return (void*)context;
}

PLUGIN_API void destroyRiveRendererContext(void* contextPtr)
{
    RiveNativeRendererContext* context = (RiveNativeRendererContext*)contextPtr;
    if (context == nullptr)
    {
        return;
    }
    context->unref();
}

PLUGIN_API void* factoryFromRiveRendererContext(void* context)
{
    if (context == nullptr)
    {
        return nullptr;
    }
    return ((RiveNativeRendererContext*)context)->actual.get();
}

PLUGIN_API void* createRiveRenderer(void* userData,
                                    void* textureRegistrar,
                                    void* riveRendererContext,
                                    FlutterWindowsSwapchain* swapchain,
                                    RendererEndCallback rendererEndCallback,
                                    uint32_t width,
                                    uint32_t height)
{
    return new WindowsContextPLS(
        userData,
        (RiveNativeRendererContext*)riveRendererContext,
        swapchain,
        width,
        height,
        rendererEndCallback);
}

PLUGIN_API void destroyRiveRenderer(void* renderer)
{
    if (renderer == nullptr)
    {
        return;
    }
    WindowsContextPLS* pls = static_cast<WindowsContextPLS*>(renderer);
    delete pls;
}

EXPORT rive::Renderer* makeRenderer(WindowsContextPLS* pls)
{
    if (pls == nullptr)
    {
        return nullptr;
    }
    return pls->renderer();
}

EXPORT bool clear(WindowsContextPLS* pls, bool clear, uint32_t color)
{
    if (pls == nullptr)
    {
        return false;
    }
    pls->begin(clear, color);
    return true;
}

EXPORT bool flush(WindowsContextPLS* pls, float devicePixelRatio)
{
    if (pls == nullptr)
    {
        return false;
    }
    pls->end(devicePixelRatio);
    return true;
}
