/*
 * Copyright 2024 Rive
 */

#ifndef _RIVE_NATIVE_DART_FOCUSABLE_HELPER_HPP_
#define _RIVE_NATIVE_DART_FOCUSABLE_HELPER_HPP_

#include "rive/input/focusable.hpp"

namespace rive_native
{

// All callbacks receive the DartFocusNode* as userData for Dart-side lookup
typedef bool (*DartKeyInputCallback)(void* nodePtr,
                                     uint16_t key,
                                     uint8_t modifiers,
                                     bool isPressed,
                                     bool isRepeat);
typedef bool (*DartTextInputCallback)(void* nodePtr, const char* text);
typedef void (*DartFocusCallback)(void* nodePtr);

/// Internal helper that implements Focusable and bridges to Dart callbacks.
/// The DartFocusNode pointer is passed as userData to all callbacks, allowing
/// Dart to look up the corresponding Dart object via a static hashmap.
class DartFocusableHelper : public rive::Focusable
{
public:
    DartFocusableHelper(void* nodePtr,
                        DartKeyInputCallback keyInput,
                        DartTextInputCallback textInput,
                        DartFocusCallback focused,
                        DartFocusCallback blurred) :
        m_nodePtr(nodePtr),
        m_keyInputCallback(keyInput),
        m_textInputCallback(textInput),
        m_focusedCallback(focused),
        m_blurredCallback(blurred)
    {}

    bool keyInput(rive::Key key,
                  rive::KeyModifiers modifiers,
                  bool isPressed,
                  bool isRepeat) override
    {
        if (m_keyInputCallback)
        {
            return m_keyInputCallback(m_nodePtr,
                                      static_cast<uint16_t>(key),
                                      static_cast<uint8_t>(modifiers),
                                      isPressed,
                                      isRepeat);
        }
        return false;
    }

    bool textInput(const std::string& text) override
    {
        if (m_textInputCallback)
        {
            return m_textInputCallback(m_nodePtr, text.c_str());
        }
        return false;
    }

    void focused() override
    {
        if (m_focusedCallback)
        {
            m_focusedCallback(m_nodePtr);
        }
    }

    void blurred() override
    {
        if (m_blurredCallback)
        {
            m_blurredCallback(m_nodePtr);
        }
    }

private:
    void* m_nodePtr; // DartFocusNode* for Dart-side lookup
    DartKeyInputCallback m_keyInputCallback;
    DartTextInputCallback m_textInputCallback;
    DartFocusCallback m_focusedCallback;
    DartFocusCallback m_blurredCallback;
};

} // namespace rive_native

#endif
