#ifndef RENDERER_CONTEXT_HPP
#define RENDERER_CONTEXT_HPP

#include "rive/refcnt.hpp"
#include "rive/renderer/render_context.hpp"
#include <CoreFoundation/CoreFoundation.h>
#include <memory>

/// Holds a Rive GPU RenderContext and the retained CF pointer to the
/// Metal device that created it. Ref-counted so multiple consumers
/// (production renderer, headless test renderer) can share ownership.
class RiveNativeRendererContext : public rive::RefCnt<RiveNativeRendererContext>
{
public:
    RiveNativeRendererContext(
        std::unique_ptr<rive::gpu::RenderContext>&& context,
        void* deviceRetainedCF) :
        actual(std::move(context)), m_deviceRetainedCF(deviceRetainedCF)
    {}

    ~RiveNativeRendererContext()
    {
        if (m_deviceRetainedCF)
        {
            CFRelease(m_deviceRetainedCF);
            m_deviceRetainedCF = nullptr;
        }
    }

    std::unique_ptr<rive::gpu::RenderContext> actual;

private:
    void* m_deviceRetainedCF = nullptr;
};

#endif // RENDERER_CONTEXT_HPP
