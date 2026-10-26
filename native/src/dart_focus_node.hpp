/*
 * Copyright 2024 Rive
 */

#ifndef _RIVE_NATIVE_DART_FOCUS_NODE_HPP_
#define _RIVE_NATIVE_DART_FOCUS_NODE_HPP_

#include "rive/input/focus_node.hpp"
#include "dart_focusable_helper.hpp"
#include <memory>

namespace rive_native
{

/// FocusNode subclass for Dart FFI that optionally owns a DartFocusableHelper.
/// Since it inherits from FocusNode (which is RefCnt), the same ref-counting
/// applies:
/// 1. Dart holds one reference (released on dispose via unref)
/// 2. FocusManager holds references via rcp<FocusNode>
/// 3. The DartFocusableHelper (and its Dart callbacks) stays alive as long as
///    any reference exists
class DartFocusNode : public rive::FocusNode
{
public:
    // Create without callbacks (no Focusable)
    DartFocusNode() = default;

    // Create with Dart callbacks (creates internal DartFocusableHelper)
    // Pass `this` as nodePtr so Dart can look up the FocusNode in a hashmap
    DartFocusNode(DartKeyInputCallback keyInput,
                  DartTextInputCallback textInput,
                  DartFocusCallback focused,
                  DartFocusCallback blurred)
    {
        if (keyInput || textInput || focused || blurred)
        {
            m_helper = std::make_unique<DartFocusableHelper>(this,
                                                             keyInput,
                                                             textInput,
                                                             focused,
                                                             blurred);
            setFocusable(m_helper.get());
        }
    }

private:
    std::unique_ptr<DartFocusableHelper> m_helper;
};

} // namespace rive_native

#endif
