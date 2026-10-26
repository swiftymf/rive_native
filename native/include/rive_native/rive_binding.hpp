#include "rive/factory.hpp"
#include "rive/refcnt.hpp"
#include "rive/nested_animation.hpp"
#include "rive/artboard.hpp"
#include "rive/file.hpp"
#include "rive/animation/linear_animation_instance.hpp"
#include "rive/animation/state_machine_instance.hpp"

class WrappedArtboard;
typedef void (*EventCallback)(WrappedArtboard* wrapper, uint32_t);

class WrappedDataBind : public rive::RefCnt<WrappedDataBind>
{
public:
    WrappedDataBind(rive::DataBind* dataBind);

    ~WrappedDataBind();

    void deleteDataBind();

    rive::DataBind* dataBind();

private:
    rive::DataBind* m_dataBind = nullptr;
};

// This is the same as an artboard instance but provides a render transform.
class WrappedArtboard : public rive::RefCnt<WrappedArtboard>,
                        public rive::NestedEventListener
{
public:
    rive::Mat2D renderTransform;

    WrappedArtboard(std::unique_ptr<rive::ArtboardInstance>&& artboardInstance,
                    rive::rcp<rive::File> file);

    ~WrappedArtboard();

    void notify(const std::vector<rive::EventReport>& events,
                rive::NestedArtboard* context) override;

    void monitorEvents(rive::LinearAnimationInstance* animation);

    void monitorEvents(rive::StateMachineInstance* stateMachine);
    void addDataBind(WrappedDataBind* dataBind);
    void deleteDataBinds();
    rive::ArtboardInstance* artboard();
    EventCallback m_eventCallback = nullptr;

    rive::rcp<rive::File> file() { return m_file; }

private:
    rive::rcp<rive::File> m_file;
    std::unique_ptr<rive::ArtboardInstance> m_artboard;
    std::vector<WrappedDataBind*> m_dataBinds;
};

// Helper function to convert std::string to caller-owned C string
inline const char* toCString(const std::string& str)
{
    char* result = (char*)std::malloc(str.size() + 1);
    if (result == nullptr)
    {
        return nullptr;
    }
    std::strcpy(result, str.c_str());
    return result;
}