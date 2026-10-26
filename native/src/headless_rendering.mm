// Headless Metal rendering for test environments.
// This file is NOT compiled into flutter_runtime (end-user) builds.

#include "rive_native/external.hpp"
#include "renderer_context.hpp"
#include "rive/renderer/metal/render_context_metal_impl.h"
#include "rive/renderer/rive_renderer.hpp"
#include <memory>

/// Holds a Metal device, command queue, and Rive render context for headless
/// rendering in test environments.
struct HeadlessContext
{
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    RiveNativeRendererContext* rendererContext; // ref-counted
};

/// A simplified Metal renderer for headless test rendering.
/// Uses a single render target (no triple-buffering) with a shared-mode buffer
/// for CPU-side pixel readback. Modeled after TestingWindowMetalTexture in the
/// runtime tests.
class HeadlessMetalRenderer
{
public:
    HeadlessMetalRenderer(HeadlessContext* ctx,
                          uint32_t width,
                          uint32_t height) :
        m_ctx(ctx), m_width(width), m_height(height)
    {
        auto renderCtxImpl =
            ctx->rendererContext->actual
                ->static_impl_cast<rive::gpu::RenderContextMetalImpl>();
        m_renderTarget = renderCtxImpl->makeRenderTarget(
            MTLPixelFormatBGRA8Unorm, width, height);

        // Create a private texture for GPU rendering.
        MTLTextureDescriptor* desc = [[MTLTextureDescriptor alloc] init];
        desc.pixelFormat = MTLPixelFormatBGRA8Unorm;
        desc.width = width;
        desc.height = height;
        desc.usage = MTLTextureUsageRenderTarget;
        desc.textureType = MTLTextureType2D;
        desc.mipmapLevelCount = 1;
        desc.storageMode = MTLStorageModePrivate;
        m_renderTarget->setTargetTexture(
            [ctx->device newTextureWithDescriptor:desc]);

        // Create a shared buffer for CPU pixel readback.
        m_pixelReadBuff =
            [ctx->device newBufferWithLength:height * width * 4
                                     options:MTLResourceStorageModeShared];

        m_renderer = std::make_unique<rive::RiveRenderer>(
            ctx->rendererContext->actual.get());
    }

    void begin(bool doClear, uint32_t color)
    {
        m_ctx->rendererContext->actual->beginFrame({
            .renderTargetWidth = m_width,
            .renderTargetHeight = m_height,
            .loadAction = doClear ? rive::gpu::LoadAction::clear
                                  : rive::gpu::LoadAction::preserveRenderTarget,
            .clearColor = color,
        });
    }

    void end()
    {
        m_flushCommandBuffer = [m_ctx->queue commandBuffer];
        m_ctx->rendererContext->actual->flush(
            {.renderTarget = m_renderTarget.get(),
             .externalCommandBuffer = (__bridge void*)m_flushCommandBuffer});
        [m_flushCommandBuffer commit];
        [m_flushCommandBuffer waitUntilCompleted];
        m_flushCommandBuffer = nil;
    }

    /// Reads pixels from the GPU texture into the provided buffer.
    /// Buffer must be at least width * height * 4 bytes.
    /// Output format is RGBA8 (converted from BGRA8).
    bool readPixels(uint8_t* outputBuffer)
    {
        if (outputBuffer == nullptr)
        {
            return false;
        }

        id<MTLCommandBuffer> cmdBuf = [m_ctx->queue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [cmdBuf blitCommandEncoder];

        [blitEncoder copyFromTexture:m_renderTarget->targetTexture()
                         sourceSlice:0
                         sourceLevel:0
                        sourceOrigin:MTLOriginMake(0, 0, 0)
                          sourceSize:MTLSizeMake(m_width, m_height, 1)
                            toBuffer:m_pixelReadBuff
                   destinationOffset:0
              destinationBytesPerRow:m_width * 4
            destinationBytesPerImage:m_height * m_width * 4];

        [blitEncoder endEncoding];
        [cmdBuf commit];
        [cmdBuf waitUntilCompleted];

        // Copy from shared buffer to output, converting BGRA → RGBA.
        const uint8_t* src =
            reinterpret_cast<const uint8_t*>(m_pixelReadBuff.contents);
        const size_t rowBytes = m_width * 4;
        for (uint32_t y = 0; y < m_height; ++y)
        {
            const uint8_t* srcRow = &src[y * rowBytes];
            uint8_t* dstRow = &outputBuffer[y * rowBytes];
            for (size_t x = 0; x < rowBytes; x += 4)
            {
                dstRow[x + 0] = srcRow[x + 2]; // R <- B
                dstRow[x + 1] = srcRow[x + 1]; // G
                dstRow[x + 2] = srcRow[x + 0]; // B <- R
                dstRow[x + 3] = srcRow[x + 3]; // A
            }
        }
        return true;
    }

    rive::RiveRenderer* renderer() { return m_renderer.get(); }

    uint32_t width() const { return m_width; }
    uint32_t height() const { return m_height; }

private:
    HeadlessContext* m_ctx;
    rive::rcp<rive::gpu::RenderTargetMetal> m_renderTarget;
    std::unique_ptr<rive::RiveRenderer> m_renderer;
    id<MTLBuffer> m_pixelReadBuff;
    id<MTLCommandBuffer> m_flushCommandBuffer;
    uint32_t m_width;
    uint32_t m_height;
};

// --- Headless FFI functions ---

EXPORT void* createHeadlessContext(bool disableFramebufferReads)
{
    @autoreleasepool
    {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (device == nil)
        {
            return nullptr;
        }
        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil)
        {
            return nullptr;
        }

        // Create the Rive render context. We __bridge_retained the device so
        // RiveNativeRendererContext can CFRelease it in its destructor.
        void* deviceRetained = (__bridge_retained void*)device;
        rive::gpu::RenderContextMetalImpl::ContextOptions options;
        options.disableFramebufferReads = disableFramebufferReads;
        auto ctx =
            rive::gpu::RenderContextMetalImpl::MakeContext(device, options);
        auto* rendererContext =
            new RiveNativeRendererContext(std::move(ctx), deviceRetained);

        auto* headless = new HeadlessContext();
        headless->device = device;
        headless->queue = queue;
        headless->rendererContext = rendererContext;
        return headless;
    }
}

EXPORT void* headlessContextFactory(void* headlessCtx)
{
    if (headlessCtx == nullptr)
    {
        return nullptr;
    }
    auto* ctx = static_cast<HeadlessContext*>(headlessCtx);
    return ctx->rendererContext->actual.get();
}

EXPORT void* createHeadlessRenderer(void* headlessCtx,
                                    uint32_t width,
                                    uint32_t height)
{
    if (headlessCtx == nullptr || width == 0 || height == 0)
    {
        return nullptr;
    }
    auto* ctx = static_cast<HeadlessContext*>(headlessCtx);
    return new HeadlessMetalRenderer(ctx, width, height);
}

EXPORT bool headlessClear(void* renderer, bool doClear, uint32_t color)
{
    if (renderer == nullptr)
    {
        return false;
    }
    static_cast<HeadlessMetalRenderer*>(renderer)->begin(doClear, color);
    return true;
}

EXPORT bool headlessFlush(void* renderer, float /*devicePixelRatio*/)
{
    if (renderer == nullptr)
    {
        return false;
    }
    static_cast<HeadlessMetalRenderer*>(renderer)->end();
    return true;
}

EXPORT rive::Renderer* headlessMakeRenderer(void* renderer)
{
    if (renderer == nullptr)
    {
        return nullptr;
    }
    return static_cast<HeadlessMetalRenderer*>(renderer)->renderer();
}

EXPORT bool headlessReadPixels(void* renderer, uint8_t* buffer)
{
    if (renderer == nullptr)
    {
        return false;
    }
    return static_cast<HeadlessMetalRenderer*>(renderer)->readPixels(buffer);
}

EXPORT void destroyHeadlessRenderer(void* renderer)
{
    if (renderer != nullptr)
    {
        delete static_cast<HeadlessMetalRenderer*>(renderer);
    }
}

EXPORT void destroyHeadlessContext(void* headlessCtx)
{
    if (headlessCtx == nullptr)
    {
        return;
    }
    auto* ctx = static_cast<HeadlessContext*>(headlessCtx);
    ctx->rendererContext->unref();
    delete ctx;
}
