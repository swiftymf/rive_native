// Linux Flutter plugin for rive_native
// Uses FlTextureGL with shared GDK GL context for zero-copy texture sharing.

#include "include/rive_native/rive_native_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Enable GL extension prototypes before including GL headers
#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/glx.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <sys/utsname.h>
#include <vector>

// Sibling textures created in Flutter's render_context (populate) can only be
// deleted with that context current, which happens during populate. Removed
// textures stash theirs here for the next populate to reap.
static std::mutex g_orphan_shared_tex_mutex;
static std::vector<uint32_t> g_orphan_shared_tex;

// The pixel-buffer readback FBO lives in the render (FFI) GL context, which is
// shared across textures and usually held current by the render thread — so it
// can't be made current (and the FBO deleted) from the platform thread at
// teardown. Removed textures stash it here for the next on_renderer_end (render
// thread, FFI context current) to reap. Mirrors g_orphan_shared_tex above.
static std::mutex g_orphan_readback_fbo_mutex;
static std::vector<uint32_t> g_orphan_readback_fbo;

// Since Flutter 3.38 the Linux shell renders in its own EGL context (not GDK's,
// flutter/flutter#172330), so textures from gdk_window_create_gl_context() are
// no longer in Flutter's share group and composite black (flutter#182998). We
// bridge our rendered textures into Flutter's render_context with an EGLImage:
// the renderer keeps drawing into its own context's textures, and populate()
// (called with render_context current) binds a sibling texture to the same
// image. Zero-copy, no shared GL group needed.
typedef void(APIENTRYP RiveGLEGLImageTargetTexture2DOESPROC)(
    GLenum target,
    GLeglImageOES image);
static PFNEGLCREATEIMAGEKHRPROC pEglCreateImageKHR = nullptr;
static PFNEGLDESTROYIMAGEKHRPROC pEglDestroyImageKHR = nullptr;
static RiveGLEGLImageTargetTexture2DOESPROC pGLEGLImageTargetTexture2DOES =
    nullptr;

static void rive_load_egl_image_procs()
{
    if (pEglCreateImageKHR != nullptr)
    {
        return;
    }
    pEglCreateImageKHR =
        (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    pEglDestroyImageKHR =
        (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    pGLEGLImageTargetTexture2DOES =
        (RiveGLEGLImageTargetTexture2DOESPROC)eglGetProcAddress(
            "glEGLImageTargetTexture2DOES");
}

// Forward declarations for rive_native library functions.
// These are implemented in rive_native_linux.cpp (linked from the static lib).
#include "rive_native/read_write_ring.hpp"

class FlutterRenderer;
namespace rive
{
class RenderPath;
class Factory;
class AudioSound;
} // namespace rive

#define EXPORT                                                                 \
    extern "C" __attribute__((visibility("default"))) __attribute__((used))

EXPORT void* loadRiveFile(const uint8_t* bytes, uint64_t length);
EXPORT void deleteFlutterRenderer(FlutterRenderer* renderer);
EXPORT void rewindRenderPath(rive::RenderPath* path);
EXPORT void* disposeYogaStyle(void* style);
EXPORT void riveFontDummyLinker();
#ifdef RIVE_WITH_SCRIPTING
EXPORT void riveLuaDummyLinker();
#endif
EXPORT void stopAudioSound(rive::AudioSound* sound, uint64_t timeInFrames);

extern "C"
{
    // From rive_native_linux.cpp
    void* createRiveRendererContext(void* gpu);
    void destroyRiveRendererContext(void* context);
    void* factoryFromRiveRendererContext(void* context);
    void setLinuxMakeCurrentCallback(void (*callback)(void*), void* userData);
    void* createRiveRenderer(void* textureRegistry,
                             void* riveRendererContext,
                             void* queue,
                             ReadWriteRing* ring,
                             void* texture0,
                             void* texture1,
                             void* texture2,
                             uint32_t width,
                             uint32_t height);
    void destroyRiveRenderer(void* renderer);
}

// ==================== RiveNativeGLTexture - FlTextureGL subclass ===========
// Triple-buffered GL texture for zero-copy sharing with Flutter's compositor.
// Returns the texture at ring->currentRead() in populate().

G_DECLARE_FINAL_TYPE(RiveNativeGLTexture,
                     rive_native_gl_texture,
                     RIVE_NATIVE,
                     GL_TEXTURE,
                     FlTextureGL)

struct _RiveNativeGLTexture
{
    FlTextureGL parent_instance;
    ReadWriteRing* ring;
    uint32_t gl_texture_ids[3];
    uint32_t width;
    uint32_t height;
    // EGLImage bridge to Flutter's render_context (see the note up top).
    EGLDisplay egl_display;
    EGLImageKHR egl_images[3]; // siblings of gl_texture_ids, created in our ctx
    uint32_t shared_tex[3];    // textures in render_context bound to egl_images
    bool shared_ready;         // shared_tex created lazily in populate
};

G_DEFINE_TYPE(RiveNativeGLTexture,
              rive_native_gl_texture,
              fl_texture_gl_get_type())

static gboolean rive_native_gl_texture_populate(FlTextureGL* texture,
                                                uint32_t* target,
                                                uint32_t* name,
                                                uint32_t* width,
                                                uint32_t* height,
                                                GError** error)
{
    RiveNativeGLTexture* self = RIVE_NATIVE_GL_TEXTURE(texture);

    // render_context is current here — the only place we can delete sibling
    // textures left behind by removed textures.
    {
        std::lock_guard<std::mutex> lock(g_orphan_shared_tex_mutex);
        if (!g_orphan_shared_tex.empty())
        {
            glDeleteTextures((GLsizei)g_orphan_shared_tex.size(),
                             g_orphan_shared_tex.data());
            g_orphan_shared_tex.clear();
        }
    }

    // Lazily create sibling textures bound to our EGLImages so the names we
    // return are valid where the engine binds them. Done once; the binding
    // tracks the underlying storage thereafter. createTexture guarantees the
    // images are all-or-nothing, but verify each to be safe.
    bool have_all_images = pGLEGLImageTargetTexture2DOES != nullptr;
    for (int i = 0; i < 3 && have_all_images; i++)
    {
        have_all_images = self->egl_images[i] != EGL_NO_IMAGE_KHR;
    }
    if (!self->shared_ready && have_all_images)
    {
        for (int i = 0; i < 3; i++)
        {
            glGenTextures(1, &self->shared_tex[i]);
            glBindTexture(GL_TEXTURE_2D, self->shared_tex[i]);
            pGLEGLImageTargetTexture2DOES(GL_TEXTURE_2D, self->egl_images[i]);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }
        glBindTexture(GL_TEXTURE_2D, 0);
        self->shared_ready = true;
    }

    *target = GL_TEXTURE_2D;
    *name = self->shared_ready
                ? self->shared_tex[self->ring->currentRead()]
                : self->gl_texture_ids[self->ring->currentRead()];
    *width = self->width;
    *height = self->height;

    return TRUE;
}

static void rive_native_gl_texture_class_init(RiveNativeGLTextureClass* klass)
{
    FL_TEXTURE_GL_CLASS(klass)->populate = rive_native_gl_texture_populate;
}

static void rive_native_gl_texture_init(RiveNativeGLTexture* self)
{
    self->ring = nullptr;
    self->gl_texture_ids[0] = 0;
    self->gl_texture_ids[1] = 0;
    self->gl_texture_ids[2] = 0;
    self->width = 0;
    self->height = 0;
    self->egl_display = EGL_NO_DISPLAY;
    for (int i = 0; i < 3; i++)
    {
        self->egl_images[i] = EGL_NO_IMAGE_KHR;
        self->shared_tex[i] = 0;
    }
    self->shared_ready = false;
}

static RiveNativeGLTexture* rive_native_gl_texture_new(void)
{
    return RIVE_NATIVE_GL_TEXTURE(
        g_object_new(rive_native_gl_texture_get_type(), nullptr));
}

// ============ RiveNativePixelBufferTexture - copy fallback =================
// Used when the EGLImage bridge is unavailable (e.g. GDK handed us a GLX
// context, common on X11). Returning a raw GL texture name there composites
// black on Flutter >= 3.38 (the name isn't valid in Flutter's render_context).
// Instead we read the rendered frame back to a CPU buffer on the render thread
// and let Flutter upload it into a texture it owns. One GPU->CPU->GPU copy per
// frame, but correct everywhere and fully supported by the embedder.

G_DECLARE_FINAL_TYPE(RiveNativePixelBufferTexture,
                     rive_native_pixel_buffer_texture,
                     RIVE_NATIVE,
                     PIXEL_BUFFER_TEXTURE,
                     FlPixelBufferTexture)

struct _RiveNativePixelBufferTexture
{
    FlPixelBufferTexture parent_instance;
    GMutex mutex;
    uint8_t* buffers[3]; // triple-buffered RGBA8 pixels, top-down
    int ready_index;     // last fully-written buffer; -1 until first frame
    uint32_t width;
    uint32_t height;
};

G_DEFINE_TYPE(RiveNativePixelBufferTexture,
              rive_native_pixel_buffer_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean rive_native_pixel_buffer_texture_copy_pixels(
    FlPixelBufferTexture* texture,
    const uint8_t** out_buffer,
    uint32_t* width,
    uint32_t* height,
    GError** error)
{
    RiveNativePixelBufferTexture* self =
        RIVE_NATIVE_PIXEL_BUFFER_TEXTURE(texture);

    g_mutex_lock(&self->mutex);
    // Before the first rendered frame, hand back the zero-filled buffer 0 so
    // the engine has something valid (transparent) to upload. The returned
    // pointer must stay valid until the engine finishes uploading; triple
    // buffering guarantees the render thread won't reuse this slot for two
    // more frames, well past the engine's synchronous upload.
    int idx = self->ready_index >= 0 ? self->ready_index : 0;
    *out_buffer = self->buffers[idx];
    g_mutex_unlock(&self->mutex);

    *width = self->width;
    *height = self->height;
    return TRUE;
}

static void rive_native_pixel_buffer_texture_init(
    RiveNativePixelBufferTexture* self)
{
    g_mutex_init(&self->mutex);
    self->buffers[0] = nullptr;
    self->buffers[1] = nullptr;
    self->buffers[2] = nullptr;
    self->ready_index = -1;
    self->width = 0;
    self->height = 0;
}

static void rive_native_pixel_buffer_texture_finalize(GObject* object)
{
    RiveNativePixelBufferTexture* self =
        RIVE_NATIVE_PIXEL_BUFFER_TEXTURE(object);
    for (int i = 0; i < 3; i++)
    {
        g_free(self->buffers[i]);
        self->buffers[i] = nullptr;
    }
    g_mutex_clear(&self->mutex);
    G_OBJECT_CLASS(rive_native_pixel_buffer_texture_parent_class)
        ->finalize(object);
}

static void rive_native_pixel_buffer_texture_class_init(
    RiveNativePixelBufferTextureClass* klass)
{
    FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
        rive_native_pixel_buffer_texture_copy_pixels;
    G_OBJECT_CLASS(klass)->finalize = rive_native_pixel_buffer_texture_finalize;
}

static RiveNativePixelBufferTexture* rive_native_pixel_buffer_texture_new(
    uint32_t width,
    uint32_t height)
{
    RiveNativePixelBufferTexture* self = RIVE_NATIVE_PIXEL_BUFFER_TEXTURE(
        g_object_new(rive_native_pixel_buffer_texture_get_type(), nullptr));
    self->width = width;
    self->height = height;
    size_t size = (size_t)width * (size_t)height * 4;
    for (int i = 0; i < 3; i++)
    {
        self->buffers[i] = (uint8_t*)g_malloc0(size);
    }
    return self;
}

// ==================== Texture info struct ==================================

/// Callback struct passed to the native renderer via the `queue` parameter.
/// The native renderer calls endCallback after glFlush() to notify Flutter,
/// and makeCurrentCallback before rendering to ensure GL context is active.
struct LinuxRendererCallbacks
{
    void (*endCallback)(void* userData);
    void (*makeCurrentCallback)(void* userData);
    void* userData;
};

struct RiveNativeTextureInfo
{
    int64_t texture_id; // Flutter texture ID
    FlTextureRegistrar* texture_registrar;
    RiveNativeGLTexture* gl_texture;
    // Set instead of gl_texture when the EGLImage bridge is unavailable; the
    // renderer still draws into gl_texture_ids but we read them back to CPU.
    RiveNativePixelBufferTexture* pixel_buffer_texture;
    // FBO in the render (FFI) context used to read gl_texture_ids back to CPU.
    uint32_t readback_fbo;
    GdkGLContext* shared_gl_context; // For making GL context current

    uint32_t gl_texture_ids[3]; // GL texture IDs
    uint32_t gl_fbos[3];        // GL framebuffer objects (for cleanup)
    ReadWriteRing ring;
    LinuxRendererCallbacks callbacks;

    void* rive_renderer; // LinuxGLRenderer*
    int width;
    int height;
};

// ==================== RiveNativePlugin =====================================

#define RIVE_NATIVE_PLUGIN(obj)                                                \
    (G_TYPE_CHECK_INSTANCE_CAST((obj),                                         \
                                rive_native_plugin_get_type(),                 \
                                RiveNativePlugin))

struct _RiveNativePlugin
{
    GObject parent_instance;
    FlPluginRegistrar* registrar;
    FlMethodChannel* channel;
    std::map<int64_t, std::unique_ptr<RiveNativeTextureInfo>>* textures;

    // Shared GL context created from FlView's GdkWindow.
    // This shares GL objects with Flutter's own GL context.
    GdkGLContext* shared_gl_context;
    // Second GL context for the Dart FFI/rendering thread.
    // Shares resources with the first context (same share group).
    GdkGLContext* ffi_gl_context;
    bool shared_context_initialized;

    // Rive renderer context (wraps RenderContextGLImpl).
    void* rive_renderer_context;
};

G_DEFINE_TYPE(RiveNativePlugin, rive_native_plugin, g_object_get_type())

// Global make-current callback for riveFactory()/riveLock().
static void on_global_make_current(void* userData)
{
    GdkGLContext* ctx = (GdkGLContext*)userData;
    if (ctx)
    {
        gdk_gl_context_make_current(ctx);
    }
}

// Callback from the native renderer before rendering begins.
// Makes the FFI GL context current on the rendering thread.
static void on_make_current(void* userData)
{
    auto* info = (RiveNativeTextureInfo*)userData;
    if (info && info->shared_gl_context)
    {
        gdk_gl_context_make_current(info->shared_gl_context);
    }
}

// Callback from the native renderer after glFlush() + ring advance.
// Marks the Flutter texture frame as available for compositing.
static void on_renderer_end(void* userData)
{
    auto* info = (RiveNativeTextureInfo*)userData;
    if (!info)
    {
        return;
    }

    // Reap readback FBOs orphaned by removed textures. We're on the render
    // thread with the FFI GL context current — the only place these FBOs (which
    // live in that context) can be deleted — just as populate() reaps orphaned
    // sibling textures with the render_context current.
    {
        std::lock_guard<std::mutex> lock(g_orphan_readback_fbo_mutex);
        if (!g_orphan_readback_fbo.empty())
        {
            glDeleteFramebuffers((GLsizei)g_orphan_readback_fbo.size(),
                                 g_orphan_readback_fbo.data());
            g_orphan_readback_fbo.clear();
        }
    }

    // Pixel-buffer fallback: read the just-rendered frame back to CPU here, on
    // the render thread with our GL context current (Flutter's render_context
    // can't see our textures). The ring already Y-flipped the texture to
    // top-down, so glReadPixels yields a top-down buffer as
    // FlPixelBufferTexture expects — no extra flip. FBOs aren't shared across
    // contexts, so we use a readback FBO created lazily here in the render
    // context.
    if (info->pixel_buffer_texture)
    {
        RiveNativePixelBufferTexture* pb = info->pixel_buffer_texture;
        int slot = (int)info->ring.currentRead();
        uint8_t* dst = pb->buffers[slot];
        if (dst)
        {
            if (info->readback_fbo == 0)
            {
                glGenFramebuffers(1, &info->readback_fbo);
            }
            glBindFramebuffer(GL_READ_FRAMEBUFFER, info->readback_fbo);
            glFramebufferTexture2D(GL_READ_FRAMEBUFFER,
                                   GL_COLOR_ATTACHMENT0,
                                   GL_TEXTURE_2D,
                                   info->gl_texture_ids[slot],
                                   0);
            glReadBuffer(GL_COLOR_ATTACHMENT0);
            glPixelStorei(GL_PACK_ALIGNMENT, 4);
            glReadPixels(0,
                         0,
                         (GLsizei)info->width,
                         (GLsizei)info->height,
                         GL_RGBA,
                         GL_UNSIGNED_BYTE,
                         dst);
            glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);

            g_mutex_lock(&pb->mutex);
            pb->ready_index = slot;
            g_mutex_unlock(&pb->mutex);
        }
        if (info->texture_registrar)
        {
            fl_texture_registrar_mark_texture_frame_available(
                info->texture_registrar,
                FL_TEXTURE(pb));
        }
        return;
    }

    if (info->texture_registrar && info->gl_texture)
    {
        fl_texture_registrar_mark_texture_frame_available(
            info->texture_registrar,
            FL_TEXTURE(info->gl_texture));
    }
}

// Initialize shared GL context from FlView's GdkWindow.
// This creates a context that shares textures with Flutter's GL renderer.
static bool rive_native_plugin_init_shared_context(RiveNativePlugin* self)
{
    if (self->shared_context_initialized)
    {
        return self->shared_gl_context != nullptr;
    }
    self->shared_context_initialized = true;

    FlView* view = fl_plugin_registrar_get_view(self->registrar);
    if (!view)
    {
        g_warning("rive_native: No FlView available (headless mode?)");
        return false;
    }

    GtkWidget* widget = GTK_WIDGET(view);
    if (!gtk_widget_get_realized(widget))
    {
        gtk_widget_realize(widget);
    }

    GdkWindow* gdk_window = gtk_widget_get_window(widget);
    if (!gdk_window)
    {
        g_warning("rive_native: No GdkWindow available");
        return false;
    }

    GError* error = nullptr;
    self->shared_gl_context = gdk_window_create_gl_context(gdk_window, &error);
    if (error)
    {
        g_warning("rive_native: Failed to create GdkGLContext: %s",
                  error->message);
        g_error_free(error);
        return false;
    }

    if (!gdk_gl_context_realize(self->shared_gl_context, &error))
    {
        g_warning("rive_native: Failed to realize GdkGLContext: %s",
                  error->message);
        g_error_free(error);
        g_object_unref(self->shared_gl_context);
        self->shared_gl_context = nullptr;
        return false;
    }

    // Create a second GL context for the Dart FFI thread.
    // Both contexts share GL resources (textures, buffers) because they're
    // created from the same GdkWindow (same GLX share group).
    error = nullptr;
    self->ffi_gl_context = gdk_window_create_gl_context(gdk_window, &error);
    if (error)
    {
        g_warning("rive_native: Failed to create FFI GdkGLContext: %s",
                  error->message);
        g_error_free(error);
    }
    else if (!gdk_gl_context_realize(self->ffi_gl_context, &error))
    {
        g_warning("rive_native: Failed to realize FFI GdkGLContext: %s",
                  error->message);
        g_error_free(error);
        g_object_unref(self->ffi_gl_context);
        self->ffi_gl_context = nullptr;
    }

    return true;
}

// Make the shared context current.
static bool rive_native_plugin_make_context_current(RiveNativePlugin* self)
{
    if (!self->shared_gl_context)
        return false;
    gdk_gl_context_make_current(self->shared_gl_context);
    return true;
}

// Create triple GL textures for a render target.
static bool create_gl_textures(uint32_t width,
                               uint32_t height,
                               uint32_t* out_texture_ids,
                               uint32_t* out_fbo_ids)
{
    for (int i = 0; i < 3; i++)
    {
        glGenTextures(1, &out_texture_ids[i]);
        glBindTexture(GL_TEXTURE_2D, out_texture_ids[i]);
        glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, width, height);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        // Clear the texture to transparent black.
        out_fbo_ids[i] = 0;
        glGenFramebuffers(1, &out_fbo_ids[i]);
        glBindFramebuffer(GL_FRAMEBUFFER, out_fbo_ids[i]);
        glFramebufferTexture2D(GL_FRAMEBUFFER,
                               GL_COLOR_ATTACHMENT0,
                               GL_TEXTURE_2D,
                               out_texture_ids[i],
                               0);
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glFlush();
    return true;
}

// Destroy GL textures and FBOs.
static void destroy_gl_textures(uint32_t* texture_ids, uint32_t* fbo_ids)
{
    for (int i = 0; i < 3; i++)
    {
        if (fbo_ids[i] != 0)
        {
            glDeleteFramebuffers(1, &fbo_ids[i]);
            fbo_ids[i] = 0;
        }
        if (texture_ids[i] != 0)
        {
            glDeleteTextures(1, &texture_ids[i]);
            texture_ids[i] = 0;
        }
    }
}

// Destroy the EGLImages wrapping a texture's ring. The sibling textures in
// Flutter's render_context (shared_tex) can't be deleted here (that context
// isn't current), so they're left for the engine to reap with render_context.
static void destroy_egl_images(RiveNativeGLTexture* tex)
{
    if (tex == nullptr)
    {
        return;
    }
    if (tex->egl_display != EGL_NO_DISPLAY && pEglDestroyImageKHR != nullptr)
    {
        for (int i = 0; i < 3; i++)
        {
            if (tex->egl_images[i] != EGL_NO_IMAGE_KHR)
            {
                pEglDestroyImageKHR(tex->egl_display, tex->egl_images[i]);
                tex->egl_images[i] = EGL_NO_IMAGE_KHR;
            }
        }
    }
    // The sibling textures live in render_context; hand them to the next
    // populate to delete (only it has that context current).
    std::lock_guard<std::mutex> lock(g_orphan_shared_tex_mutex);
    for (int i = 0; i < 3; i++)
    {
        if (tex->shared_tex[i] != 0)
        {
            g_orphan_shared_tex.push_back(tex->shared_tex[i]);
            tex->shared_tex[i] = 0;
        }
    }
}

// Handle method calls from Dart.
static void rive_native_plugin_handle_method_call(RiveNativePlugin* self,
                                                  FlMethodCall* method_call)
{
    g_autoptr(FlMethodResponse) response = nullptr;
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    if (strcmp(method, "createTexture") == 0)
    {
        // Ensure the shared GL context is initialized.
        if (!self->shared_gl_context)
        {
            if (!rive_native_plugin_init_shared_context(self))
            {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                    "GL_CONTEXT_ERROR",
                    "Failed to create shared GL context",
                    nullptr));
                fl_method_call_respond(method_call, response, nullptr);
                return;
            }
        }

        // Initialize the Rive renderer context if not done yet.
        if (!self->rive_renderer_context)
        {
            GdkGLContext* initCtx = self->ffi_gl_context
                                        ? self->ffi_gl_context
                                        : self->shared_gl_context;
            gdk_gl_context_make_current(initCtx);
            self->rive_renderer_context = createRiveRendererContext(nullptr);
            if (!self->rive_renderer_context)
            {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                    "RENDERER_ERROR",
                    "Failed to create Rive renderer context",
                    nullptr));
                fl_method_call_respond(method_call, response, nullptr);
                return;
            }
            setLinuxMakeCurrentCallback(on_global_make_current, (void*)initCtx);
        }

        // Parse width and height.
        FlValue* width_val = fl_value_lookup_string(args, "width");
        FlValue* height_val = fl_value_lookup_string(args, "height");
        if (!width_val || !height_val)
        {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                "INVALID_ARGS",
                "Missing width or height in createTexture",
                nullptr));
            fl_method_call_respond(method_call, response, nullptr);
            return;
        }
        int32_t width = (int32_t)fl_value_get_int(width_val);
        int32_t height = (int32_t)fl_value_get_int(height_val);

        // Reject non-positive or oversized dimensions before we allocate
        // anything. 16384 is a conservative GL_MAX_TEXTURE_SIZE floor.
        if (width <= 0 || height <= 0 || width > 16384 || height > 16384)
        {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new(
                "INVALID_ARGS",
                "createTexture width/height out of range",
                nullptr));
            fl_method_call_respond(method_call, response, nullptr);
            return;
        }

        // Make context current and create GL textures.
        rive_native_plugin_make_context_current(self);

        auto info = std::make_unique<RiveNativeTextureInfo>();
        info->width = width;
        info->height = height;
        info->texture_registrar =
            fl_plugin_registrar_get_texture_registrar(self->registrar);

        if (!create_gl_textures(width,
                                height,
                                info->gl_texture_ids,
                                info->gl_fbos))
        {
            response = FL_METHOD_RESPONSE(
                fl_method_error_response_new("GL_ERROR",
                                             "Failed to create GL textures",
                                             nullptr));
            fl_method_call_respond(method_call, response, nullptr);
            return;
        }

        // Decide how to present frames to Flutter. Preferred path: wrap each
        // ring texture in an EGLImage and hand Flutter sibling textures in its
        // own render_context (zero-copy). This needs an EGL context here; on a
        // GLX context (common on X11) eglGetCurrentContext() is EGL_NO_CONTEXT,
        // so we fall back to the pixel-buffer copy path instead of returning a
        // texture name that would composite black on Flutter >= 3.38.
        rive_load_egl_image_procs();
        EGLDisplay dpy = eglGetCurrentDisplay();
        EGLContext cur = eglGetCurrentContext();
        bool egl_ready = false;
        if (pEglCreateImageKHR != nullptr && pEglDestroyImageKHR != nullptr &&
            pGLEGLImageTargetTexture2DOES != nullptr && dpy != EGL_NO_DISPLAY &&
            cur != EGL_NO_CONTEXT)
        {
            info->gl_texture = rive_native_gl_texture_new();
            info->gl_texture->ring = &info->ring;
            info->gl_texture->width = (uint32_t)width;
            info->gl_texture->height = (uint32_t)height;
            for (int i = 0; i < 3; i++)
            {
                info->gl_texture->gl_texture_ids[i] = info->gl_texture_ids[i];
            }

            info->gl_texture->egl_display = dpy;
            bool all_ok = true;
            for (int i = 0; i < 3; i++)
            {
                EGLint attribs[] = {EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE};
                info->gl_texture->egl_images[i] = pEglCreateImageKHR(
                    dpy,
                    cur,
                    EGL_GL_TEXTURE_2D_KHR,
                    (EGLClientBuffer)(uintptr_t)info->gl_texture_ids[i],
                    attribs);
                if (info->gl_texture->egl_images[i] == EGL_NO_IMAGE_KHR)
                {
                    g_warning("rive_native: eglCreateImageKHR[%d] failed: 0x%x",
                              i,
                              eglGetError());
                    all_ok = false;
                }
            }
            if (all_ok)
            {
                egl_ready = true;
            }
            else
            {
                // Partial set — drop the GL-texture path entirely and use the
                // pixel-buffer fallback below.
                destroy_egl_images(info->gl_texture);
                g_object_unref(info->gl_texture);
                info->gl_texture = nullptr;
            }
        }

        FlTexture* fl_texture = nullptr;
        if (egl_ready)
        {
            fl_texture = FL_TEXTURE(info->gl_texture);
        }
        else
        {
            g_message("rive_native: EGLImage unavailable - using pixel-buffer");
            info->pixel_buffer_texture =
                rive_native_pixel_buffer_texture_new((uint32_t)width,
                                                     (uint32_t)height);
            fl_texture = FL_TEXTURE(info->pixel_buffer_texture);
        }

        fl_texture_registrar_register_texture(info->texture_registrar,
                                              fl_texture);
        info->texture_id = fl_texture_get_id(fl_texture);

        // Store the FFI GL context for the make-current callback.
        info->shared_gl_context = self->ffi_gl_context
                                      ? self->ffi_gl_context
                                      : self->shared_gl_context;

        // Set up callbacks so native code can make GL context current and
        // notify Flutter when a frame is done.
        info->callbacks.endCallback = on_renderer_end;
        info->callbacks.makeCurrentCallback = on_make_current;
        info->callbacks.userData = info.get();

        // Create the native Rive renderer for this texture.
        // FBOs inside the renderer are created lazily on the first begin()
        // call (FFI thread), not here.
        info->rive_renderer =
            createRiveRenderer(nullptr, // textureRegistry (unused on Linux)
                               self->rive_renderer_context,
                               &info->callbacks,
                               &info->ring,
                               (void*)(uintptr_t)info->gl_texture_ids[0],
                               (void*)(uintptr_t)info->gl_texture_ids[1],
                               (void*)(uintptr_t)info->gl_texture_ids[2],
                               width,
                               height);

        // Release the GL context from the main thread so the rendering
        // thread can acquire it via makeCurrentCallback.
        gdk_gl_context_clear_current();

        int64_t texture_id = info->texture_id;

        // Format the renderer pointer as a hex string for Dart FFI.
        char buff[255];
        snprintf(buff, sizeof(buff), "%p", info->rive_renderer);

        self->textures->emplace(texture_id, std::move(info));

        g_autoptr(FlValue) result = fl_value_new_map();
        fl_value_set_string_take(result,
                                 "textureId",
                                 fl_value_new_int(texture_id));
        fl_value_set_string_take(result, "renderer", fl_value_new_string(buff));
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    else if (strcmp(method, "getRenderContext") == 0)
    {
        // Ensure context is initialized.
        if (!self->shared_gl_context)
        {
            rive_native_plugin_init_shared_context(self);
        }
        if (!self->rive_renderer_context && self->shared_gl_context)
        {
            GdkGLContext* initCtx = self->ffi_gl_context
                                        ? self->ffi_gl_context
                                        : self->shared_gl_context;
            gdk_gl_context_make_current(initCtx);
            self->rive_renderer_context = createRiveRendererContext(nullptr);
            setLinuxMakeCurrentCallback(on_global_make_current, (void*)initCtx);
            gdk_gl_context_clear_current();
        }

        // Return 'android' as the rendererContext string. This triggers the
        // Dart FFI code to call riveFactory() via FFI (instead of parsing a
        // hex pointer). The riveFactory() call ensures the GL context is
        // current on the Dart UI thread.
        g_autoptr(FlValue) result = fl_value_new_map();
        fl_value_set_string_take(result,
                                 "rendererContext",
                                 fl_value_new_string(self->rive_renderer_context
                                                         ? "android"
                                                         : "0x0"));
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    else if (strcmp(method, "removeTexture") == 0)
    {
        FlValue* id_val = fl_value_lookup_string(args, "id");
        if (!id_val)
        {
            response = FL_METHOD_RESPONSE(
                fl_method_error_response_new("INVALID_ARGS",
                                             "Missing id in removeTexture",
                                             nullptr));
            fl_method_call_respond(method_call, response, nullptr);
            return;
        }
        int64_t id = fl_value_get_int(id_val);

        auto it = self->textures->find(id);
        if (it != self->textures->end())
        {
            RiveNativeTextureInfo* info = it->second.get();

            if (info->rive_renderer)
            {
                destroyRiveRenderer(info->rive_renderer);
                info->rive_renderer = nullptr;
            }

            FlTexture* fl_texture =
                info->gl_texture ? FL_TEXTURE(info->gl_texture)
                                 : (info->pixel_buffer_texture
                                        ? FL_TEXTURE(info->pixel_buffer_texture)
                                        : nullptr);
            if (fl_texture)
            {
                fl_texture_registrar_unregister_texture(info->texture_registrar,
                                                        fl_texture);
            }

            if (info->gl_texture)
            {
                destroy_egl_images(info->gl_texture);
                g_object_unref(info->gl_texture);
                info->gl_texture = nullptr;
            }

            // The readback FBO lives in the render (FFI) context, which the
            // render thread usually holds current, so we can't make it current
            // and delete it here. Stash it for the next on_renderer_end to
            // reap.
            if (info->readback_fbo != 0)
            {
                std::lock_guard<std::mutex> lock(g_orphan_readback_fbo_mutex);
                g_orphan_readback_fbo.push_back(info->readback_fbo);
                info->readback_fbo = 0;
            }
            if (info->pixel_buffer_texture)
            {
                g_object_unref(info->pixel_buffer_texture);
                info->pixel_buffer_texture = nullptr;
            }

            rive_native_plugin_make_context_current(self);
            destroy_gl_textures(info->gl_texture_ids, info->gl_fbos);

            self->textures->erase(it);
        }
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    else if (strcmp(method, "getPlatformVersion") == 0)
    {
        struct utsname uname_data = {};
        uname(&uname_data);
        g_autofree gchar* version =
            g_strdup_printf("Linux %s", uname_data.version);
        g_autoptr(FlValue) result = fl_value_new_string(version);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    else
    {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    fl_method_call_respond(method_call, response, nullptr);
}

// Method call callback.
static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data)
{
    RiveNativePlugin* plugin = RIVE_NATIVE_PLUGIN(user_data);
    rive_native_plugin_handle_method_call(plugin, method_call);
}

// Plugin dispose.
static void rive_native_plugin_dispose(GObject* object)
{
    RiveNativePlugin* self = RIVE_NATIVE_PLUGIN(object);

    if (self->textures)
    {
        if (self->shared_gl_context)
        {
            rive_native_plugin_make_context_current(self);
        }
        for (auto& pair : *self->textures)
        {
            RiveNativeTextureInfo* info = pair.second.get();
            if (info->rive_renderer)
            {
                destroyRiveRenderer(info->rive_renderer);
                info->rive_renderer = nullptr;
            }
            if (info->gl_texture)
            {
                fl_texture_registrar_unregister_texture(
                    info->texture_registrar,
                    FL_TEXTURE(info->gl_texture));
                destroy_egl_images(info->gl_texture);
                g_object_unref(info->gl_texture);
                info->gl_texture = nullptr;
            }
            if (info->pixel_buffer_texture)
            {
                fl_texture_registrar_unregister_texture(
                    info->texture_registrar,
                    FL_TEXTURE(info->pixel_buffer_texture));
                // Readback FBO lives in the render (FFI) context; stash it for
                // reaping. On full dispose no more frames run to reap it, so
                // the FFI context teardown at the end of dispose frees it with
                // the context and we just clear the stash.
                if (info->readback_fbo != 0)
                {
                    std::lock_guard<std::mutex> lock(
                        g_orphan_readback_fbo_mutex);
                    g_orphan_readback_fbo.push_back(info->readback_fbo);
                    info->readback_fbo = 0;
                }
                g_object_unref(info->pixel_buffer_texture);
                info->pixel_buffer_texture = nullptr;
                // Restore the shared context for destroy_gl_textures below.
                rive_native_plugin_make_context_current(self);
            }
            destroy_gl_textures(info->gl_texture_ids, info->gl_fbos);
        }
        delete self->textures;
        self->textures = nullptr;
    }

    if (self->rive_renderer_context)
    {
        destroyRiveRendererContext(self->rive_renderer_context);
        self->rive_renderer_context = nullptr;
    }

    // Any readback FBOs stashed above are freed when the FFI context they live
    // in is destroyed just below; drop the now-stale names so they can't be
    // deleted against a different context created by a future plugin instance.
    {
        std::lock_guard<std::mutex> lock(g_orphan_readback_fbo_mutex);
        g_orphan_readback_fbo.clear();
    }

    if (self->ffi_gl_context)
    {
        g_object_unref(self->ffi_gl_context);
        self->ffi_gl_context = nullptr;
    }
    if (self->shared_gl_context)
    {
        g_object_unref(self->shared_gl_context);
        self->shared_gl_context = nullptr;
    }

    g_clear_object(&self->channel);
    g_clear_object(&self->registrar);

    G_OBJECT_CLASS(rive_native_plugin_parent_class)->dispose(object);
}

static void rive_native_plugin_class_init(RiveNativePluginClass* klass)
{
    G_OBJECT_CLASS(klass)->dispose = rive_native_plugin_dispose;
}

static void rive_native_plugin_init(RiveNativePlugin* self)
{
    self->textures =
        new std::map<int64_t, std::unique_ptr<RiveNativeTextureInfo>>();
    self->shared_gl_context = nullptr;
    self->ffi_gl_context = nullptr;
    self->shared_context_initialized = false;
    self->rive_renderer_context = nullptr;
}

void rive_native_plugin_register_with_registrar(FlPluginRegistrar* registrar)
{
    RiveNativePlugin* plugin = RIVE_NATIVE_PLUGIN(
        g_object_new(rive_native_plugin_get_type(), nullptr));

    plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    plugin->channel =
        fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                              "rive_native",
                              FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(plugin->channel,
                                              method_call_cb,
                                              g_object_ref(plugin),
                                              g_object_unref);

    g_object_unref(plugin);

    // Force link these methods to pull the whole object file from the static
    // library. Without these calls, the linker may strip unused symbols.
    loadRiveFile(nullptr, 0);
    deleteFlutterRenderer(nullptr);
    rewindRenderPath(nullptr);
    disposeYogaStyle(nullptr);
    riveFontDummyLinker();
#ifdef RIVE_WITH_SCRIPTING
    riveLuaDummyLinker();
#endif
    stopAudioSound(nullptr, 0);
}
