#ifndef _RIVE_FENCE_WAIT_THREAD_HPP
#define _RIVE_FENCE_WAIT_THREAD_HPP

#include <cassert>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>

// Background thread that waits for the GPU to finish a frame and then presents
// it. Owns the handshake with the render thread so teardown can neither run
// the present callback after destruction begins nor deadlock the join.
class FenceWaitThread
{
public:
    // Runs on the wait thread; must block until the GPU completes frameIndex,
    // then present.
    using WaitAndPresent = std::function<void(uint64_t frameIndex)>;

    explicit FenceWaitThread(WaitAndPresent waitAndPresent) :
        m_waitAndPresent(std::move(waitAndPresent)),
        m_thread([this]() { threadLoop(); })
    {}

    ~FenceWaitThread()
    {
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            // Drain any in-flight frame first so the thread cannot present
            // after teardown begins.
            while (m_activeIndex != 0)
            {
                m_cond.wait(lock);
            }
            m_activeIndex = TERMINATE_INDEX;
        }
        m_cond.notify_one();
        m_thread.join();
    }

    // Blocks until the previously kicked frame has been presented.
    void waitForIdle()
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        while (m_activeIndex != 0)
        {
            m_cond.wait(lock);
        }
    }

    // Hands frameIndex to the wait thread. Requires idle; frameIndex must not
    // be 0 or ~0.
    void kick(uint64_t frameIndex)
    {
        assert(frameIndex != 0 && frameIndex != TERMINATE_INDEX);
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            assert(m_activeIndex == 0);
            m_activeIndex = frameIndex;
        }
        m_cond.notify_one();
    }

private:
    void threadLoop()
    {
        for (;;)
        {
            uint64_t index;
            {
                std::unique_lock<std::mutex> lock(m_mutex);
                while (m_activeIndex == 0)
                {
                    m_cond.wait(lock);
                }
                index = m_activeIndex;
            }

            if (index == TERMINATE_INDEX)
            {
                break;
            }

            m_waitAndPresent(index);

            {
                std::unique_lock<std::mutex> lock(m_mutex);
                // Never clobber a terminate request that raced in.
                if (m_activeIndex != TERMINATE_INDEX)
                {
                    m_activeIndex = 0;
                }
            }
            m_cond.notify_one();
        }
    }

    constexpr static uint64_t TERMINATE_INDEX = ~0ull;

    WaitAndPresent m_waitAndPresent;
    std::mutex m_mutex;
    std::condition_variable m_cond;
    uint64_t m_activeIndex = 0;
    // Last so the thread starts after all state is initialized.
    std::thread m_thread;
};

#endif
