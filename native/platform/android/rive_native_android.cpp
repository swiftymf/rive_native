#include "rive_native/external.hpp"
#include "rive_native/rive_binding.hpp"
#include "rive/renderer/rive_renderer.hpp"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include "rive/renderer/gl/render_context_gl_impl.hpp"
#include "rive/renderer/gl/render_target_gl.hpp"

#include <android/log.h>
#include <android/native_window_jni.h>
#include <unordered_map>

#include <jni.h>

#define LOG_TAG "RiveNative"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

std::mutex flutterMutex;

#define EGL_ERR_CHECK() _check_egl_error(__FILE__, __LINE__)

void _check_egl_error(const char* file, int line)
{
    EGLenum err(eglGetError());

    while (true)
    {
        std::string error;

        switch (err)
        {
            case EGL_SUCCESS:
                return;
            case EGL_NOT_INITIALIZED:
                error = "EGL_NOT_INITIALIZED";
                break;
            case EGL_BAD_ACCESS:
                error = "EGL_BAD_ACCESS";
                break;
            case EGL_BAD_ALLOC:
                error = "EGL_BAD_ALLOC";
                break;
            case EGL_BAD_ATTRIBUTE:
                error = "EGL_BAD_ATTRIBUTE";
                break;
            case EGL_BAD_CONTEXT:
                error = "EGL_BAD_CONTEXT";
                break;
            case EGL_BAD_CONFIG:
                error = "EGL_BAD_CONFIG";
                break;
            case EGL_BAD_CURRENT_SURFACE:
                error = "EGL_BAD_CURRENT_SURFACE";
                break;
            case EGL_BAD_DISPLAY:
                error = "EGL_BAD_DISPLAY";
                break;
            case EGL_BAD_SURFACE:
                error = "EGL_BAD_SURFACE";
                break;
            case EGL_BAD_MATCH:
                error = "EGL_BAD_MATCH";
                break;
            case EGL_BAD_PARAMETER:
                error = "EGL_BAD_PARAMETER";
                break;
            case EGL_BAD_NATIVE_PIXMAP:
                error = "EGL_BAD_NATIVE_PIXMAP";
                break;
            case EGL_BAD_NATIVE_WINDOW:
                error = "EGL_BAD_NATIVE_WINDOW";
                break;
            case EGL_CONTEXT_LOST:
                error = "EGL_CONTEXT_LOST";
                break;
            default:
                LOGE("(%d) %s - %s:%d", err, "Unknown", file, line);
                return;
        }
        LOGE("(%d) %s - %s:%d", err, error.c_str(), file, line);
        err = eglGetError();
    }
}

static bool config_has_attribute(EGLDisplay display,
                                 EGLConfig config,
                                 EGLint attribute,
                                 EGLint value)
{
    EGLint outValue = 0;
    EGLBoolean result =
        eglGetConfigAttrib(display, config, attribute, &outValue);
    EGL_ERR_CHECK();
    return result && (outValue == value);
}

class EGLThreadState
{
public:
    EGLThreadState()
    {
        m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (m_display == EGL_NO_DISPLAY)
        {
            EGL_ERR_CHECK();
            LOGE("eglGetDisplay() failed.");
            return;
        }
        if (!eglInitialize(m_display, 0, 0))
        {
            EGL_ERR_CHECK();
            LOGE("eglInitialize() failed.");
            return;
        }

        const EGLint configAttributes[] = {EGL_RENDERABLE_TYPE,
                                           EGL_OPENGL_ES2_BIT,
                                           EGL_BLUE_SIZE,
                                           8,
                                           EGL_GREEN_SIZE,
                                           8,
                                           EGL_RED_SIZE,
                                           8,
                                           EGL_DEPTH_SIZE,
                                           0,
                                           EGL_STENCIL_SIZE,
                                           8,
                                           EGL_ALPHA_SIZE,
                                           8,
                                           EGL_NONE};
        EGLint num_configs = 0;
        if (!eglChooseConfig(m_display,
                             configAttributes,
                             nullptr,
                             0,
                             &num_configs))
        {
            EGL_ERR_CHECK();
            LOGE("eglChooseConfig() didn't find any (%d)", num_configs);
            return;
        }

        std::vector<EGLConfig> supportedConfigs(
            static_cast<size_t>(num_configs));
        eglChooseConfig(m_display,
                        configAttributes,
                        supportedConfigs.data(),
                        num_configs,
                        &num_configs);
        EGL_ERR_CHECK();

        // Choose a config, either a match if possible or the first config
        // otherwise
        const auto configMatches = [&](EGLConfig config) {
            if (!config_has_attribute(m_display, config, EGL_RED_SIZE, 8))
                return false;
            if (!config_has_attribute(m_display, config, EGL_GREEN_SIZE, 8))
                return false;
            if (!config_has_attribute(m_display, config, EGL_BLUE_SIZE, 8))
                return false;
            if (!config_has_attribute(m_display, config, EGL_STENCIL_SIZE, 8))
                return false;
            return config_has_attribute(m_display, config, EGL_DEPTH_SIZE, 0);
        };

        const auto configIter = std::find_if(supportedConfigs.cbegin(),
                                             supportedConfigs.cend(),
                                             configMatches);

        m_config = (configIter != supportedConfigs.cend())
                       ? *configIter
                       : supportedConfigs[0];

        const EGLint contextAttributes[] = {EGL_CONTEXT_CLIENT_VERSION,
                                            2,
                                            EGL_NONE};

        m_context =
            eglCreateContext(m_display, m_config, nullptr, contextAttributes);
        if (m_context == EGL_NO_CONTEXT)
        {
            LOGE("eglCreateContext() failed.");
            EGL_ERR_CHECK();
        }

        // PLS
        // Create a 1x1 Pbuffer surface that we can use to guarantee m_context
        // is
        // always current on this thread.
        const EGLint PbufferAttrs[] = {
            EGL_WIDTH,
            1,
            EGL_HEIGHT,
            1,
            EGL_NONE,
        };
        m_backgroundSurface =
            eglCreatePbufferSurface(m_display, m_config, PbufferAttrs);
        EGL_ERR_CHECK();
        if (m_backgroundSurface == EGL_NO_SURFACE)
        {
            LOGE("Failed to create a 1x1 background Pbuffer surface for PLS");
        }

        eglMakeCurrent(m_display,
                       m_backgroundSurface,
                       m_backgroundSurface,
                       m_context);
        m_currentSurface = m_backgroundSurface;

        m_renderContext = rive::gpu::RenderContextGLImpl::MakeContext();
    }

    ~EGLThreadState()
    {
        LOGD("EGLThreadState getting destroyed! 🧨");

        if (m_context != EGL_NO_CONTEXT)
        {
            eglDestroyContext(m_display, m_context);
            EGL_ERR_CHECK();
        }

        eglReleaseThread();
        EGL_ERR_CHECK();

        if (m_display != EGL_NO_DISPLAY)
        {
            eglTerminate(m_display);
            EGL_ERR_CHECK();
        }
    }

    EGLSurface createEGLSurface(ANativeWindow* window)
    {
        if (!window)
        {
            return EGL_NO_SURFACE;
        }

        auto res = eglCreateWindowSurface(m_display, m_config, window, nullptr);
        EGL_ERR_CHECK();
        return res;
    }

    void destroySurface(EGLSurface eglSurface)
    {
        if (eglSurface == EGL_NO_SURFACE)
        {
            return;
        }

        assert(eglSurface != m_backgroundSurface);
        if (m_currentSurface == eglSurface)
        {
            // Make sure m_context always stays current.
            makeCurrent(m_backgroundSurface);
        }

        eglDestroySurface(m_display, eglSurface);
        EGL_ERR_CHECK();
    }

    void makeCurrent(EGLSurface eglSurface)
    {
        if (eglSurface == m_currentSurface)
        {
            // return;
        }

        if (eglSurface == EGL_NO_SURFACE)
        {
            LOGE("Cannot make EGL_NO_SURFACE current");
            return;
        }

        if (!eglMakeCurrent(m_display, eglSurface, eglSurface, m_context))
        {
            LOGE("eglMakeCurrent failed");
            EGL_ERR_CHECK();
            return;
        }

        m_currentSurface = eglSurface;
    }

    void swapBuffers()
    {
        eglSwapBuffers(m_display, m_currentSurface);
        EGL_ERR_CHECK();
    }

    rive::gpu::RenderContext* renderContext() const
    {
        return m_renderContext.get();
    }

protected:
    EGLSurface m_currentSurface = EGL_NO_SURFACE;
    EGLDisplay m_display = EGL_NO_DISPLAY;
    EGLContext m_context = EGL_NO_CONTEXT;
    EGLConfig m_config = static_cast<EGLConfig>(0);

    std::unique_ptr<rive::gpu::RenderContext> m_renderContext;

    // 1x1 Pbuffer surface that allows us to make the GL context current without
    // a window surface.
    EGLSurface m_backgroundSurface;
};

class AndroidRenderTexture
{
public:
    AndroidRenderTexture(ANativeWindow* surfaceWindow,
                         uint32_t width,
                         uint32_t height) :
        m_surfaceWindow(surfaceWindow), m_width(width), m_height(height)
    {
        ANativeWindow_acquire(surfaceWindow);
    }

    ~AndroidRenderTexture()
    {
        // Clean up GPU resources first, in reverse order of creation
        if (threadState && m_eglSurface != EGL_NO_SURFACE)
        {
            // threadState->makeCurrent(m_eglSurface);
            threadState->destroySurface(m_eglSurface);
            m_eglSurface = EGL_NO_SURFACE;
        }

        if (m_surfaceWindow)
        {
            ANativeWindow_release(m_surfaceWindow);
            m_surfaceWindow = nullptr;
        }

        // TODO: Rive Android calls `releaseResources` when there are no Rive
        // views if (threadState && threadState->renderContext())
        // {
        //     threadState->renderContext()->releaseResources();
        // }
    }

    bool beginFrame(bool clear, uint32_t color)
    {
        if (m_scheduledDestruction)
        {
            LOGW("Rive AndroidRenderTexture beginFrame called on destroyed "
                 "texture");
            return false;
        }
        if (!threadState)
        {
            LOGD("Rive AndroidRenderTexture creating EGLThreadState");
            threadState = std::make_unique<EGLThreadState>();
        }

        if (!m_renderTarget)
        {
            m_eglSurface = threadState->createEGLSurface(m_surfaceWindow);
            if (m_eglSurface == EGL_NO_SURFACE)
            {
                LOGE("AndroidRenderTexture failed to create EGL surface");
                return false;
            }

            threadState->makeCurrent(m_eglSurface);
            auto renderContext = threadState->renderContext();
            if (renderContext == nullptr)
            {
                LOGW("Rive AndroidRenderTexture Rive Renderer (PLS) not "
                     "supported");
                return true; // PLS was not supported.
            }
            int width = ANativeWindow_getWidth(m_surfaceWindow);
            int height = ANativeWindow_getHeight(m_surfaceWindow);
            assert(width == m_width);
            assert(height == m_height);

            GLint sampleCount;
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glGetIntegerv(GL_SAMPLES, &sampleCount);
            m_renderTarget =
                rive::make_rcp<rive::gpu::FramebufferRenderTargetGL>(
                    width,
                    height,
                    0,
                    sampleCount);
            m_plsRenderer = std::make_unique<rive::RiveRenderer>(renderContext);
        }

        threadState->renderContext()->beginFrame({
            .renderTargetWidth = m_width,
            .renderTargetHeight = m_height,
            .loadAction = clear ? rive::gpu::LoadAction::clear
                                : rive::gpu::LoadAction::preserveRenderTarget,
            .clearColor = color,
        });
        return true;
    }

    bool endFrame(float devicePixelRatio)
    {
        if (m_scheduledDestruction)
        {
            LOGW("Rive AndroidRenderTexture endFrame called on destroyed "
                 "texture");
            return false;
        }

        if (!threadState || !m_renderTarget || m_eglSurface == EGL_NO_SURFACE)
        {
            LOGE("Rive AndroidRenderTexture endFrame called with invalid "
                 "state");
            return false;
        }

        auto renderContext = threadState->renderContext();
        if (!renderContext)
        {
            LOGE("Rive AndroidRenderTexture renderContext is null");
            return false;
        }

        auto plsGL =
            renderContext->static_impl_cast<rive::gpu::RenderContextGLImpl>();
        plsGL->invalidateGLState();

        threadState->makeCurrent(m_eglSurface);

        renderContext->flush({.renderTarget = m_renderTarget.get()});
        threadState->swapBuffers();

        plsGL->unbindGLInternalResources();
        return true;
    }

    void scheduleDestruction() { m_scheduledDestruction = true; }

private:
    ANativeWindow* m_surfaceWindow;
    uint32_t m_width;
    uint32_t m_height;

    EGLSurface m_eglSurface = nullptr;
    rive::rcp<rive::gpu::RenderTargetGL> m_renderTarget;
    std::unique_ptr<rive::RiveRenderer> m_plsRenderer;
    bool m_scheduledDestruction = false;

public:
    static std::unique_ptr<EGLThreadState> threadState;

    rive::Renderer* renderer() { return m_plsRenderer.get(); }
};

std::unique_ptr<EGLThreadState> AndroidRenderTexture::threadState;

EXPORT rive::Factory* riveFactory()
{
    std::unique_lock<std::mutex> lock(flutterMutex);
    if (!AndroidRenderTexture::threadState)
    {
        AndroidRenderTexture::threadState = std::make_unique<EGLThreadState>();
    }
    assert(AndroidRenderTexture::threadState != nullptr);
    assert(AndroidRenderTexture::threadState->renderContext() != nullptr);
    return AndroidRenderTexture::threadState->renderContext();
}

EXPORT jlong Java_app_rive_rive_1native_RiveNativePluginKt_createRiveRenderer(
    JNIEnv* env,
    jclass clazz,
    jobject surface,
    jint width,
    jint height)
{
    ANativeWindow* surfaceWindow = ANativeWindow_fromSurface(env, surface);

    AndroidRenderTexture* renderTexture =
        new AndroidRenderTexture(surfaceWindow,
                                 (uint32_t)width,
                                 (uint32_t)height);
    return reinterpret_cast<jlong>(renderTexture);
}

EXPORT void Java_app_rive_rive_1native_RiveNativePluginKt_destroyRiveRenderer(
    JNIEnv* env,
    jclass clazz,
    jlong renderer)
{
    std::unique_lock<std::mutex> lock(flutterMutex);
    if (renderer != 0)
    {
        AndroidRenderTexture* renderTexture =
            reinterpret_cast<AndroidRenderTexture*>(renderer);
        delete renderTexture;
    }
    else
    {
        LOGW("JNI: Rive destroyRiveRenderer called with null pointer");
    }
}

EXPORT void
Java_app_rive_rive_1native_RiveNativePluginKt_markDestroyedRiveRenderer(
    JNIEnv* env,
    jclass clazz,
    jlong renderer)
{
    std::unique_lock<std::mutex> lock(flutterMutex);
    if (renderer != 0)
    {
        AndroidRenderTexture* renderTexture =
            reinterpret_cast<AndroidRenderTexture*>(renderer);
        renderTexture->scheduleDestruction();
    }
    else
    {
        LOGW("JNI: Rive markDestroyedRiveRenderer called with null pointer");
    }
}

EXPORT bool clear(AndroidRenderTexture* renderTexture,
                  bool clear,
                  uint32_t color)
{
    if (renderTexture == nullptr)
    {
        return false;
    }
    std::unique_lock<std::mutex> lock(flutterMutex);
    return renderTexture->beginFrame(clear, color);
}

EXPORT bool flush(AndroidRenderTexture* renderTexture, float devicePixelRatio)
{
    if (renderTexture == nullptr)
    {
        return false;
    }

    std::unique_lock<std::mutex> lock(flutterMutex);
    return renderTexture->endFrame(devicePixelRatio);
}

EXPORT rive::Renderer* makeRenderer(AndroidRenderTexture* renderTexture)
{
    if (renderTexture == nullptr)
    {
        return nullptr;
    }
    std::unique_lock<std::mutex> lock(flutterMutex);
    return renderTexture->renderer();
}
