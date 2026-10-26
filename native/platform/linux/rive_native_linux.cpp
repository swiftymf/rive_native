#include "rive_native/external.hpp"
#include "rive_native/rive_binding.hpp"
#include "rive/renderer/gl/render_context_gl_impl.hpp"
#include "rive/renderer/gl/render_target_gl.hpp"
#include "rive/renderer/rive_renderer.hpp"

#include <dlfcn.h>
#include <mutex>

/// Calls from the Flutter plugin come in on a different thread so we use a
/// mutex to ensure we're destroying/creating rive renderers without
/// concurrently changing our shared state.
std::mutex g_mutex;

// GL function loader for glad (RIVE_DESKTOP_GL).
// We avoid including <GL/glx.h> because it pulls in <GL/gl.h> which conflicts
// with glad's GL function macros. Instead, we dynamically load
// glXGetProcAddressARB via dlsym.
typedef void* (*GLXGetProcAddressARBFunc)(const unsigned char*);
static void* linuxGLGetProcAddress(const char* name)
{
    static GLXGetProcAddressARBFunc glXGetProcAddressARB = nullptr;
    static bool resolved = false;
    if (!resolved)
    {
        resolved = true;
        glXGetProcAddressARB =
            (GLXGetProcAddressARBFunc)dlsym(RTLD_DEFAULT,
                                            "glXGetProcAddressARB");
    }
    if (glXGetProcAddressARB)
    {
        void* p = glXGetProcAddressARB((const unsigned char*)name);
        if (p)
            return p;
    }
    return dlsym(RTLD_DEFAULT, name);
}

class RiveNativeRendererContext : public rive::RefCnt<RiveNativeRendererContext>
{
public:
    RiveNativeRendererContext(
        std::unique_ptr<rive::gpu::RenderContext>&& context) :
        actual(std::move(context))
    {}

    std::unique_ptr<rive::gpu::RenderContext> actual;
};

static RiveNativeRendererContext* g_rendererContext = nullptr;

// Global make-current callback so riveFactory() and riveLock() can ensure the
// GL context is current on whatever thread calls them (typically the Dart UI
// thread via FFI).
static void (*g_makeCurrentCallback)(void*) = nullptr;
static void* g_makeCurrentUserData = nullptr;

static void ensureGLContextCurrent()
{
    if (g_makeCurrentCallback)
    {
        g_makeCurrentCallback(g_makeCurrentUserData);
    }
}

/// Callback struct passed via the `queue` parameter of createRiveRenderer.
/// Allows the native renderer to interact with the Flutter plugin without
/// needing Flutter Linux embedder headers.
struct LinuxRendererCallbacks
{
    void (*endCallback)(void* userData);
    void (*makeCurrentCallback)(void* userData);
    void* userData;
};

class LinuxGLRenderer
{
public:
    LinuxGLRenderer(RiveNativeRendererContext* rendererContext,
                    LinuxRendererCallbacks* callbacks,
                    ReadWriteRing* ring,
                    uint32_t glTexture0,
                    uint32_t glTexture1,
                    uint32_t glTexture2,
                    uint32_t width,
                    uint32_t height) :
        m_renderContext(rive::ref_rcp(rendererContext)),
        m_ring(ring),
        m_width(width),
        m_height(height)
    {
        if (callbacks)
        {
            m_endCallback = callbacks->endCallback;
            m_makeCurrentCallback = callbacks->makeCurrentCallback;
            m_callbackData = callbacks->userData;
        }

        m_glTextures[0] = glTexture0;
        m_glTextures[1] = glTexture1;
        m_glTextures[2] = glTexture2;
    }

    ~LinuxGLRenderer()
    {
        if (m_scratchFbo)
            glDeleteFramebuffers(1, &m_scratchFbo);
        if (m_scratchTexture)
            glDeleteTextures(1, &m_scratchTexture);
        for (int i = 0; i < 3; i++)
        {
            if (m_textureFbos[i])
                glDeleteFramebuffers(1, &m_textureFbos[i]);
        }
    }

    void begin(bool clear, uint32_t color)
    {
        // Ensure the GL context is current on this thread. The rendering FFI
        // calls come in on the Dart UI thread, which may not have a GL context.
        if (m_makeCurrentCallback)
        {
            m_makeCurrentCallback(m_callbackData);
        }

        // Lazily create render targets, renderer, and flip resources on the
        // first begin() call. This runs on the FFI thread with ffi_gl_context
        // current, ensuring FBOs are created in the correct GL context.
        if (!m_initialized)
        {
            for (int i = 0; i < 3; i++)
            {
                m_renderTarget[i] =
                    rive::make_rcp<rive::gpu::TextureRenderTargetGL>(m_width,
                                                                     m_height);
                m_renderTarget[i]->setTargetTexture(m_glTextures[i]);

                // Create FBOs for each ring texture (used for Y-flip blit).
                glGenFramebuffers(1, &m_textureFbos[i]);
                glBindFramebuffer(GL_FRAMEBUFFER, m_textureFbos[i]);
                glFramebufferTexture2D(GL_FRAMEBUFFER,
                                       GL_COLOR_ATTACHMENT0,
                                       GL_TEXTURE_2D,
                                       m_glTextures[i],
                                       0);
            }

            // Create scratch texture + FBO for Y-flip blitting.
            // Rive renders in GL bottom-up orientation, but Flutter's
            // FlTextureGL compositor expects top-down (screen coords).
            glGenTextures(1, &m_scratchTexture);
            glBindTexture(GL_TEXTURE_2D, m_scratchTexture);
            glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, m_width, m_height);
            glGenFramebuffers(1, &m_scratchFbo);
            glBindFramebuffer(GL_FRAMEBUFFER, m_scratchFbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER,
                                   GL_COLOR_ATTACHMENT0,
                                   GL_TEXTURE_2D,
                                   m_scratchTexture,
                                   0);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glBindTexture(GL_TEXTURE_2D, 0);

            m_renderer = std::make_unique<rive::RiveRenderer>(
                m_renderContext->actual.get());
            m_initialized = true;
        }

        m_currentWriteIndex = m_ring->nextWrite();

        // Drain any pending GL errors left by Flutter.
        while (glGetError() != GL_NO_ERROR)
        {
        }

        // Invalidate Rive's cached GL state before beginFrame. Flutter's
        // raster thread may have modified GL state since the last frame.
        auto glImpl = m_renderContext->actual
                          ->static_impl_cast<rive::gpu::RenderContextGLImpl>();
        glImpl->invalidateGLState();

        m_renderContext->actual->beginFrame({
            .renderTargetWidth = m_width,
            .renderTargetHeight = m_height,
            .loadAction = clear ? rive::gpu::LoadAction::clear
                                : rive::gpu::LoadAction::preserveRenderTarget,
            .clearColor = color,
        });
    }

    void end(float devicePixelRatio)
    {
        // Hold g_mutex across the whole frame-finish, including the end
        // callback that reads this frame back into the plugin's CPU buffers, so
        // a concurrent destroyRiveRenderer() on the platform thread blocks
        // until we return and never tears down state this callback is still
        // using.
        std::lock_guard<std::mutex> lock(g_mutex);
        auto renderContext = m_renderContext->actual.get();
        if (renderContext == nullptr)
        {
            return;
        }

        renderContext->flush(
            {.renderTarget = m_renderTarget[m_currentWriteIndex].get()});

        // Unbind Rive's internal GL resources before we use the GL context
        // for the Y-flip blit.
        auto glImpl =
            renderContext->static_impl_cast<rive::gpu::RenderContextGLImpl>();
        glImpl->unbindGLInternalResources();

        // Y-flip: Rive renders in GL bottom-up orientation but Flutter's
        // FlTextureGL compositor expects top-down. Blit through a scratch
        // texture with flipped Y coordinates.
        {
            uint32_t w = m_width;
            uint32_t h = m_height;
            // Step 1: Copy render texture -> scratch (straight copy).
            glBindFramebuffer(GL_READ_FRAMEBUFFER,
                              m_textureFbos[m_currentWriteIndex]);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_scratchFbo);
            glBlitFramebuffer(0,
                              0,
                              w,
                              h,
                              0,
                              0,
                              w,
                              h,
                              GL_COLOR_BUFFER_BIT,
                              GL_NEAREST);
            // Step 2: Copy scratch -> render texture with Y-flip.
            glBindFramebuffer(GL_READ_FRAMEBUFFER, m_scratchFbo);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER,
                              m_textureFbos[m_currentWriteIndex]);
            glBlitFramebuffer(0,
                              0,
                              w,
                              h,
                              0,
                              h,
                              w,
                              0,
                              GL_COLOR_BUFFER_BIT,
                              GL_NEAREST);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        }

        // Ensure all GL commands are submitted before Flutter reads the
        // texture.
        glFlush();

        // Drain GL errors that Rive may have left.
        while (glGetError() != GL_NO_ERROR)
        {
        }

        // Advance the read ring so Flutter picks up the completed frame.
        m_ring->nextRead();

        // Notify the Flutter plugin to mark the texture frame available.
        if (m_endCallback)
        {
            m_endCallback(m_callbackData);
        }
    }

    rive::RiveRenderer* renderer() { return m_renderer.get(); }

    uint32_t currentTargetTexture() const
    {
        return m_glTextures[m_currentWriteIndex];
    }

    uint32_t width() const { return m_width; }
    uint32_t height() const { return m_height; }
    RiveNativeRendererContext* renderContext() const
    {
        return m_renderContext.get();
    }

private:
    rive::rcp<RiveNativeRendererContext> m_renderContext;
    ReadWriteRing* m_ring = nullptr;
    rive::rcp<rive::gpu::TextureRenderTargetGL> m_renderTarget[3];
    std::unique_ptr<rive::RiveRenderer> m_renderer;
    uint32_t m_width = 0;
    uint32_t m_height = 0;
    uint32_t m_glTextures[3] = {};
    uint32_t m_textureFbos[3] = {}; // FBOs for each ring texture (Y-flip)
    uint32_t m_scratchTexture = 0;  // Scratch texture for Y-flip blit
    uint32_t m_scratchFbo = 0;      // FBO for scratch texture
    bool m_initialized = false;
    uint32_t m_currentWriteIndex = 0;

    void (*m_endCallback)(void*) = nullptr;
    void (*m_makeCurrentCallback)(void*) = nullptr;
    void* m_callbackData = nullptr;
};

// --- Exported API ---

PLUGIN_API void* createRiveRendererContext(void* gpu)
{
    // gpu is unused on Linux; the GL context must already be current.
    // Load GL function pointers via glad before creating the render context.
    if (!gladLoadCustomLoader(
            reinterpret_cast<GLADloadfunc>(linuxGLGetProcAddress)))
    {
        fprintf(stderr,
                "[rive_linux] Failed to load OpenGL function pointers via "
                "glad.\n");
        return nullptr;
    }

    auto context = rive::gpu::RenderContextGLImpl::MakeContext();
    if (!context)
    {
        fprintf(stderr, "[rive_linux] Failed to create RenderContextGLImpl.\n");
        return nullptr;
    }

    auto* ctx = new RiveNativeRendererContext(std::move(context));
    g_rendererContext = ctx;
    return (void*)ctx;
}

/// Set the global GL context callback. Called by the plugin once during init.
PLUGIN_API void setLinuxMakeCurrentCallback(void (*callback)(void*),
                                            void* userData)
{
    g_makeCurrentCallback = callback;
    g_makeCurrentUserData = userData;
}

PLUGIN_API void destroyRiveRendererContext(void* contextPtr)
{
    RiveNativeRendererContext* context = (RiveNativeRendererContext*)contextPtr;
    if (context == nullptr)
    {
        return;
    }
    if (g_rendererContext == context)
    {
        g_rendererContext = nullptr;
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

PLUGIN_API void* createRiveRenderer(void* textureRegistry,
                                    void* riveRendererContext,
                                    void* queue,
                                    ReadWriteRing* ring,
                                    void* texture0,
                                    void* texture1,
                                    void* texture2,
                                    uint32_t width,
                                    uint32_t height)
{
    std::unique_lock<std::mutex> lock(g_mutex);

    auto* callbacks = (LinuxRendererCallbacks*)queue;

    LinuxGLRenderer* renderer =
        new LinuxGLRenderer((RiveNativeRendererContext*)riveRendererContext,
                            callbacks,
                            ring,
                            (uint32_t)(uintptr_t)texture0,
                            (uint32_t)(uintptr_t)texture1,
                            (uint32_t)(uintptr_t)texture2,
                            width,
                            height);

    return renderer;
}

PLUGIN_API void destroyRiveRenderer(void* renderer)
{
    if (renderer == nullptr)
    {
        return;
    }
    // Serialize with in-flight end() (which also locks g_mutex): block until
    // any running frame callback finishes so the plugin can safely free the
    // pixel-buffer readback state after this returns, matching
    // createRiveRenderer which also takes the lock.
    std::unique_lock<std::mutex> lock(g_mutex);
    LinuxGLRenderer* glRenderer = static_cast<LinuxGLRenderer*>(renderer);
    delete glRenderer;
}

EXPORT rive::Factory* riveFactory()
{
    std::unique_lock<std::mutex> lock(g_mutex);
    // Ensure GL context is current — the Factory creates GL resources
    // (RenderBuffers, textures) during file loading.
    ensureGLContextCurrent();
    auto* f = (g_rendererContext == nullptr) ? nullptr
                                             : g_rendererContext->actual.get();
    return (rive::Factory*)f;
}

EXPORT void* nativeTexture(LinuxGLRenderer* renderer)
{
    if (renderer == nullptr)
    {
        return nullptr;
    }
    return (void*)(uintptr_t)renderer->currentTargetTexture();
}

EXPORT rive::Renderer* makeRenderer(LinuxGLRenderer* renderer)
{
    if (renderer == nullptr)
    {
        return nullptr;
    }
    return renderer->renderer();
}

EXPORT bool clear(LinuxGLRenderer* renderer, bool doClear, uint32_t color)
{
    if (renderer == nullptr)
    {
        return false;
    }
    renderer->begin(doClear, color);
    return true;
}

EXPORT bool flush(LinuxGLRenderer* renderer, float devicePixelRatio)
{
    if (renderer == nullptr)
    {
        return false;
    }
    renderer->end(devicePixelRatio);
    return true;
}

void riveLock()
{
    g_mutex.lock();
    ensureGLContextCurrent();
}
void riveUnlock() { g_mutex.unlock(); }
