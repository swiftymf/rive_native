#include "yoga/YGNode.h"
#include "rive_native/external.hpp"
#include "rive/layout/layout_data.hpp"

#include <stdio.h>
#include <cstdint>

using namespace rive;

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <emscripten/html5.h>
using namespace emscripten;
struct NodeContext
{
    LayoutData* layoutData = nullptr;
    emscripten::val measureFunc;
    emscripten::val baselineFunc;
};
#else
typedef YGSize (*RiveMeasureFunc)(LayoutData* layoutData,
                                  float width,
                                  YGMeasureMode widthMode,
                                  float height,
                                  YGMeasureMode heightMode);
typedef float (*RiveBaselineFunc)(LayoutData* layoutData,
                                  float width,
                                  float height);

struct NodeContext
{
    LayoutData* layoutData = nullptr;
    RiveMeasureFunc measureFunc;
    RiveBaselineFunc baselineFunc;
};
#endif

#ifdef DEBUG
EXPORT uint32_t debugYogaNodeCount()
{
#ifdef WITH_RIVE_TOOLS
    return LayoutData::count;
#else
    return 0;
#endif
}
#endif

EXPORT YGStyle* makeYogaStyle() { return new YGStyle(); }

EXPORT void disposeYogaStyle(YGStyle* style) { delete style; }

EXPORT int yogaStyleGetAlignContent(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGAlign align = style->alignContent();
    return (int)align;
}

EXPORT void yogaStyleSetAlignContent(YGStyle* style, int align)
{
    if (style == nullptr)
    {
        return;
    }
    style->alignContent() = (YGAlign)align;
}

EXPORT int yogaStyleGetDirection(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGDirection direction = style->direction();
    return (int)direction;
}

EXPORT void yogaStyleSetDirection(YGStyle* style, int direction)
{
    if (style == nullptr)
    {
        return;
    }
    style->direction() = (YGDirection)direction;
}

EXPORT int yogaStyleGetFlexDirection(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGFlexDirection flexDirection = style->flexDirection();
    return (int)flexDirection;
}

EXPORT void yogaStyleSetFlexDirection(YGStyle* style, int flexDirection)
{
    if (style == nullptr)
    {
        return;
    }
    style->flexDirection() = (YGFlexDirection)flexDirection;
}

EXPORT int yogaStyleGetJustifyContent(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGJustify justify = style->justifyContent();
    return (int)justify;
}

EXPORT void yogaStyleSetJustifyContent(YGStyle* style, int justify)
{
    if (style == nullptr)
    {
        return;
    }
    style->justifyContent() = (YGJustify)justify;
}

EXPORT int yogaStyleGetAlignItems(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGAlign align = style->alignItems();
    return (int)align;
}

EXPORT void yogaStyleSetAlignItems(YGStyle* style, int align)
{
    if (style == nullptr)
    {
        return;
    }
    style->alignItems() = (YGAlign)align;
}

EXPORT int yogaStyleGetAlignSelf(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGAlign align = style->alignSelf();
    return (int)align;
}

EXPORT void yogaStyleSetAlignSelf(YGStyle* style, int align)
{
    if (style == nullptr)
    {
        return;
    }
    style->alignSelf() = (YGAlign)align;
}

EXPORT int yogaStyleGetPositionType(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGPositionType position = style->positionType();
    return (int)position;
}

EXPORT void yogaStyleSetPositionType(YGStyle* style, int position)
{
    if (style == nullptr)
    {
        return;
    }
    style->positionType() = (YGPositionType)position;
}

EXPORT int yogaStyleGetFlexWrap(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGWrap wrap = style->flexWrap();
    return (int)wrap;
}

EXPORT void yogaStyleSetFlexWrap(YGStyle* style, int wrap)
{
    if (style == nullptr)
    {
        return;
    }
    style->flexWrap() = (YGWrap)wrap;
}

EXPORT int yogaStyleGetOverflow(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGOverflow overflow = style->overflow();
    return (int)overflow;
}

EXPORT void yogaStyleSetOverflow(YGStyle* style, int overflow)
{
    if (style == nullptr)
    {
        return;
    }
    style->overflow() = (YGOverflow)overflow;
}

EXPORT int yogaStyleGetDisplay(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGDisplay display = style->display();
    return (int)display;
}

EXPORT void yogaStyleSetDisplay(YGStyle* style, int display)
{
    if (style == nullptr)
    {
        return;
    }
    style->display() = (YGDisplay)display;
}

EXPORT float yogaStyleGetFlex(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGFloatOptional optional = style->flex();
    return optional.unwrap();
}

EXPORT void yogaStyleSetFlex(YGStyle* style, float flex)
{
    if (style == nullptr)
    {
        return;
    }
    style->flex() = YGFloatOptional(flex);
}

EXPORT float yogaStyleGetFlexGrow(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGFloatOptional optional = style->flexGrow();
    return optional.unwrap();
}

EXPORT void yogaStyleSetFlexGrow(YGStyle* style, float flex)
{
    if (style == nullptr)
    {
        return;
    }
    style->flexGrow() = YGFloatOptional(flex);
}

EXPORT float yogaStyleGetFlexShrink(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGFloatOptional optional = style->flexShrink();
    return optional.unwrap();
}

EXPORT void yogaStyleSetFlexShrink(YGStyle* style, float flex)
{
    if (style == nullptr)
    {
        return;
    }
    style->flexShrink() = YGFloatOptional(flex);
}

EXPORT void yogaStyleSetFlexBasis(YGStyle* style, float value, int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->flexBasis() = (YGValue){value, (YGUnit)unit};
}

EXPORT float yogaStyleGetAspectRatio(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    YGFloatOptional optional = style->aspectRatio();
    return optional.unwrap();
}

EXPORT void yogaStyleSetAspectRatio(YGStyle* style, float ratio)
{
    if (style == nullptr)
    {
        return;
    }
    style->aspectRatio() = YGFloatOptional(ratio);
}

// Grid (yoga grid backport) --------------------------------------------------
// collection: 0=templateColumns 1=templateRows 2=autoColumns 3=autoRows
// track type: 0=auto 1=points 2=percent 3=fr 4=minmax
// line: 0=columnStart 1=columnEnd 2=rowStart 3=rowEnd
// line type: 0=auto 1=index 2=span

static YGStyleSizeLength gridSizeLength(int type, float value)
{
    switch (type)
    {
        case 1:
            return YGStyleSizeLength::points(value);
        case 2:
            return YGStyleSizeLength::percent(value);
        case 3:
            return YGStyleSizeLength::stretch(value);
        default:
            return YGStyleSizeLength::ofAuto();
    }
}

static YGGridTrackSize gridTrackSize(int type, float value)
{
    switch (type)
    {
        case 1:
            return YGGridTrackSize::length(value);
        case 2:
            return YGGridTrackSize::percent(value);
        case 3:
            return YGGridTrackSize::fr(value);
        default:
            return YGGridTrackSize::auto_();
    }
}

static size_t gridTrackCount(YGStyle* style, int collection)
{
    switch (collection)
    {
        case 0:
            return style->gridTemplateColumns().size();
        case 1:
            return style->gridTemplateRows().size();
        case 2:
            return style->gridAutoColumns().size();
        case 3:
            return style->gridAutoRows().size();
    }
    return 0;
}

static void setGridTrackAt(YGStyle* style,
                           int collection,
                           uint32_t index,
                           YGGridTrackSize track)
{
    if (index >= gridTrackCount(style, collection))
    {
        return;
    }
    switch (collection)
    {
        case 0:
            style->setGridTemplateColumnAt(index, track);
            break;
        case 1:
            style->setGridTemplateRowAt(index, track);
            break;
        case 2:
            style->setGridAutoColumnAt(index, track);
            break;
        case 3:
            style->setGridAutoRowAt(index, track);
            break;
    }
}

EXPORT void yogaStyleSetGridTrackCount(YGStyle* style,
                                       int collection,
                                       uint32_t count)
{
    if (style == nullptr)
    {
        return;
    }
    switch (collection)
    {
        case 0:
            style->resizeGridTemplateColumns(count);
            break;
        case 1:
            style->resizeGridTemplateRows(count);
            break;
        case 2:
            style->resizeGridAutoColumns(count);
            break;
        case 3:
            style->resizeGridAutoRows(count);
            break;
    }
}

EXPORT void yogaStyleSetGridTrack(YGStyle* style,
                                  int collection,
                                  uint32_t index,
                                  int type,
                                  float value)
{
    if (style == nullptr)
    {
        return;
    }
    setGridTrackAt(style, collection, index, gridTrackSize(type, value));
}

EXPORT void yogaStyleSetGridTrackMinMax(YGStyle* style,
                                        int collection,
                                        uint32_t index,
                                        int minType,
                                        float minValue,
                                        int maxType,
                                        float maxValue)
{
    if (style == nullptr)
    {
        return;
    }
    setGridTrackAt(style,
                   collection,
                   index,
                   YGGridTrackSize::minmax(gridSizeLength(minType, minValue),
                                           gridSizeLength(maxType, maxValue)));
}

EXPORT void yogaStyleSetGridLine(YGStyle* style, int line, int type, int value)
{
    if (style == nullptr)
    {
        return;
    }
    YGGridLine gridLine;
    switch (type)
    {
        case 1:
            gridLine = YGGridLine::fromInteger(value);
            break;
        case 2:
            gridLine = YGGridLine::span(value);
            break;
        default:
            gridLine = YGGridLine::auto_();
            break;
    }
    switch (line)
    {
        case 0:
            style->setGridColumnStart(gridLine);
            break;
        case 1:
            style->setGridColumnEnd(gridLine);
            break;
        case 2:
            style->setGridRowStart(gridLine);
            break;
        case 3:
            style->setGridRowEnd(gridLine);
            break;
    }
}

EXPORT int yogaStyleGetJustifyItems(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    return (int)style->justifyItems();
}

EXPORT void yogaStyleSetJustifyItems(YGStyle* style, int justify)
{
    if (style == nullptr)
    {
        return;
    }
    style->setJustifyItems((YGJustify)justify);
}

EXPORT int yogaStyleGetJustifySelf(YGStyle* style)
{
    if (style == nullptr)
    {
        return 0;
    }
    return (int)style->justifySelf();
}

EXPORT void yogaStyleSetJustifySelf(YGStyle* style, int justify)
{
    if (style == nullptr)
    {
        return;
    }
    style->setJustifySelf((YGJustify)justify);
}

EXPORT void yogaStyleSetMargin(YGStyle* style, int edge, float value, int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->margin()[(YGEdge)edge] = (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetPosition(YGStyle* style,
                                 int edge,
                                 float value,
                                 int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->position()[(YGEdge)edge] = (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetPadding(YGStyle* style, int edge, float value, int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->padding()[(YGEdge)edge] = (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetBorder(YGStyle* style, int edge, float value, int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->border()[(YGEdge)edge] = (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetGap(YGStyle* style, int gutter, float value, int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->gap()[(YGGutter)gutter] = (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetDimension(YGStyle* style,
                                  int dimension,
                                  float value,
                                  int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->dimensions()[(YGDimension)dimension] =
        (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetMinDimension(YGStyle* style,
                                     int dimension,
                                     float value,
                                     int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->minDimensions()[(YGDimension)dimension] =
        (YGValue){value, (YGUnit)unit};
}

EXPORT void yogaStyleSetMaxDimension(YGStyle* style,
                                     int dimension,
                                     float value,
                                     int unit)
{
    if (style == nullptr)
    {
        return;
    }
    style->maxDimensions()[(YGDimension)dimension] =
        (YGValue){value, (YGUnit)unit};
}

EXPORT LayoutData* makeYogaNode()
{
    auto layoutData = new LayoutData();
    // Default to use fractional pixel values
    layoutData->node.getConfig()->setPointScaleFactor(0);
    return layoutData;
}

EXPORT bool yogaNodeCheckAndResetUpdated(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return false;
    }

    bool updated = layoutData->node.getHasNewLayout();
    layoutData->node.setHasNewLayout(false);
    layoutData->node.setHasError(false);
    return updated;
}

EXPORT bool yogaNodeHasError(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return false;
    }

    return layoutData->node.getHasError();
}

EXPORT void yogaNodeSetStyle(LayoutData* layoutData, YGStyle* style)
{
    if (layoutData == nullptr)
    {
        return;
    }
    layoutData->node.setStyle(*style);
}

EXPORT int yogaNodeGetType(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return 0;
    }
    return (int)layoutData->node.getNodeType();
}

EXPORT void yogaNodeSetType(LayoutData* layoutData, int type)
{
    if (layoutData == nullptr)
    {
        return;
    }
    layoutData->node.setNodeType((YGNodeType)type);
}

EXPORT void yogaNodeInsertChild(LayoutData* layoutData,
                                LayoutData* layoutDataChild,
                                int index)
{
    if (layoutData == nullptr || layoutDataChild == nullptr)
    {
        return;
    }
#ifdef WITH_RIVE_TOOLS
    layoutData->children.insert(safe_ref(layoutDataChild));
#endif
    layoutData->node.insertChild(&layoutDataChild->node, index);
    layoutDataChild->node.setOwner(&layoutData->node);
    layoutData->node.markDirtyAndPropagate();
}

EXPORT void yogaNodeRemoveChild(LayoutData* layoutData,
                                LayoutData* layoutDataChild)
{
    if (layoutData == nullptr || layoutDataChild == nullptr)
    {
        return;
    }
    YGNodeRemoveChild(&layoutData->node, &layoutDataChild->node);
#ifdef WITH_RIVE_TOOLS
    if (layoutData->children.erase(layoutDataChild) > 0)
    {
        layoutDataChild->unref();
    }
#endif
}

EXPORT void yogaNodeClearChildren(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return;
    }
    YGNodeRemoveAllChildren(&layoutData->node);
#ifdef WITH_RIVE_TOOLS
    layoutData->clearChildren();
#endif
}

EXPORT void yogaNodeCalculateLayout(LayoutData* layoutData,
                                    float availableWidth,
                                    float availableHeight,
                                    int direction)
{
    if (layoutData == nullptr)
    {
        return;
    }
    YGNodeCalculateLayout(&layoutData->node,
                          availableWidth,
                          availableHeight,
                          (YGDirection)direction);
}

EXPORT void yogaNodeMarkDirty(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return;
    }

    layoutData->node.markDirtyAndPropagate();
}

struct Layout
{
    float left;
    float top;
    float width;
    float height;
};

#ifdef __EMSCRIPTEN__
Layout yogaNodeGetLayout(WasmPtr layoutDataPtr)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return {};
    }
    auto node = &layoutData->node;
    return {YGNodeLayoutGetLeft(node),
            YGNodeLayoutGetTop(node),
            YGNodeLayoutGetWidth(node),
            YGNodeLayoutGetHeight(node)};
}
Layout yogaNodeGetPadding(WasmPtr layoutDataPtr)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return {};
    }
    auto node = &layoutData->node;
    return {YGNodeLayoutGetPadding(node, YGEdgeLeft),
            YGNodeLayoutGetPadding(node, YGEdgeTop),
            YGNodeLayoutGetPadding(node, YGEdgeRight),
            YGNodeLayoutGetPadding(node, YGEdgeBottom)};
}
YGValue yogaStyleGetFlexBasis(WasmPtr stylePtr)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }
    facebook::yoga::detail::CompactValue compact = style->flexBasis();

    YGValue value = compact;
    return value;
}
YGValue yogaStyleGetMargin(WasmPtr stylePtr, int edge)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->margin()[(YGEdge)edge];
}
YGValue yogaStyleGetPosition(WasmPtr stylePtr, int edge)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->position()[(YGEdge)edge];
}
YGValue yogaStyleGetPadding(WasmPtr stylePtr, int edge)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->padding()[(YGEdge)edge];
}
YGValue yogaStyleGetGap(WasmPtr stylePtr, int gutter)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->gap()[(YGGutter)gutter];
}
YGValue yogaStyleGetBorder(WasmPtr stylePtr, int edge)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->border()[(YGEdge)edge];
}
YGValue yogaStyleGetDimension(WasmPtr stylePtr, int dimension)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->dimensions()[(YGDimension)dimension];
}
YGValue yogaStyleGetMinDimension(WasmPtr stylePtr, int dimension)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->minDimensions()[(YGDimension)dimension];
}
YGValue yogaStyleGetMaxDimension(WasmPtr stylePtr, int dimension)
{
    YGStyle* style = (YGStyle*)stylePtr;
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->maxDimensions()[(YGDimension)dimension];
}
static YGSize _measureFunc(YGNode* node,
                           float width,
                           YGMeasureMode widthMode,
                           float height,
                           YGMeasureMode heightMode)
{
    if (node == nullptr)
    {
        return {0.0f, 0.0f};
    }
    auto nodeContext = static_cast<NodeContext*>(node->getContext());
    if (nodeContext == nullptr)
    {
        return {0.0f, 0.0f};
    }

    emscripten::val result =
        nodeContext->measureFunc((WasmPtr)nodeContext->layoutData,
                                 width,
                                 (int)widthMode,
                                 height,
                                 (int)heightMode);
    return {result[0].as<float>(), result[1].as<float>()};
}
static float _baselineFunc(YGNode* node, float width, float height)
{
    if (node == nullptr)
    {
        return 0.0f;
    }
    auto nodeContext = static_cast<NodeContext*>(node->getContext());
    if (nodeContext == nullptr)
    {
        return 0.0f;
    }

    emscripten::val result =
        nodeContext->baselineFunc((WasmPtr)nodeContext->layoutData,
                                  width,
                                  height);
    return result.as<float>();
}
EXPORT void yogaNodeSetMeasureFunc(WasmPtr layoutDataPtr,
                                   emscripten::val measureFunc)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return;
    }
    auto context = static_cast<NodeContext*>(layoutData->node.getContext());
    if (context == nullptr)
    {
        context = new NodeContext();
        layoutData->node.setContext(context);
    }
    context->layoutData = layoutData;
    context->measureFunc = measureFunc;

    layoutData->node.setMeasureFunc(_measureFunc);
}
EXPORT void yogaNodeClearMeasureFunc(WasmPtr layoutDataPtr)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return;
    }
    layoutData->node.setMeasureFunc(nullptr);
}
EXPORT void yogaNodeSetBaselineFunc(WasmPtr layoutDataPtr,
                                    emscripten::val baselineFunc)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return;
    }
    auto context = static_cast<NodeContext*>(layoutData->node.getContext());
    if (context == nullptr)
    {
        context = new NodeContext();
        layoutData->node.setContext(context);
    }
    context->layoutData = layoutData;
    context->baselineFunc = baselineFunc;

    layoutData->node.setBaselineFunc(_baselineFunc);
}
EXPORT void yogaNodeClearBaselineFunc(WasmPtr layoutDataPtr)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return;
    }
    layoutData->node.setBaselineFunc(nullptr);
}
EXPORT void disposeYogaNode(WasmPtr layoutDataPtr)
{
    LayoutData* layoutData = (LayoutData*)layoutDataPtr;
    if (layoutData == nullptr)
    {
        return;
    }
    delete (NodeContext*)layoutData->node.getContext();
    layoutData->node.setContext(nullptr);
#ifdef WITH_RIVE_TOOLS
    layoutData->unref();
#else
    delete layoutData;
#endif
}

EMSCRIPTEN_BINDINGS(LayoutEngine)
{
    value_object<Layout>("Layout")
        .field("left", &Layout::left)
        .field("top", &Layout::top)
        .field("width", &Layout::width)
        .field("height", &Layout::height);

    value_object<YGValue>("YGValue")
        .field("value", &YGValue::value)
        .field("unit",
               optional_override(
                   [](const YGValue& self) -> int { return (int)self.unit; }),
               optional_override([](YGValue& self, int value) {
                   self.unit = (YGUnit)value;
               }));

    function("yogaNodeGetLayout", &yogaNodeGetLayout);
    function("yogaNodeGetPadding", &yogaNodeGetPadding);
    function("yogaStyleGetFlexBasis", &yogaStyleGetFlexBasis);
    function("yogaStyleGetMargin", &yogaStyleGetMargin);
    function("yogaStyleGetPosition", &yogaStyleGetPosition);
    function("yogaStyleGetPadding", &yogaStyleGetPadding);
    function("yogaStyleGetBorder", &yogaStyleGetBorder);
    function("yogaStyleGetGap", &yogaStyleGetGap);
    function("yogaStyleGetDimension", &yogaStyleGetDimension);
    function("yogaStyleGetMinDimension", &yogaStyleGetMinDimension);
    function("yogaStyleGetMaxDimension", &yogaStyleGetMaxDimension);
    function("yogaNodeSetMeasureFunc", &yogaNodeSetMeasureFunc);
    function("yogaNodeClearMeasureFunc", &yogaNodeClearMeasureFunc);
    function("yogaNodeSetBaselineFunc", &yogaNodeSetBaselineFunc);
    function("yogaNodeClearBaselineFunc", &yogaNodeClearBaselineFunc);
    function("disposeYogaNode", &disposeYogaNode);
}
#else
EXPORT Layout yogaNodeGetLayout(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return {};
    }

    auto node = &layoutData->node;
    return {YGNodeLayoutGetLeft(node),
            YGNodeLayoutGetTop(node),
            YGNodeLayoutGetWidth(node),
            YGNodeLayoutGetHeight(node)};
}
EXPORT Layout yogaNodeGetPadding(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return {};
    }
    auto node = &layoutData->node;
    return {YGNodeLayoutGetPadding(node, YGEdgeLeft),
            YGNodeLayoutGetPadding(node, YGEdgeTop),
            YGNodeLayoutGetPadding(node, YGEdgeRight),
            YGNodeLayoutGetPadding(node, YGEdgeBottom)};
}
EXPORT uint32_t yogaNodeGetGridColumnLineCount(LayoutData* layoutData)
{
    return layoutData == nullptr
               ? 0
               : YGNodeLayoutGetGridColumnLineCount(&layoutData->node);
}
EXPORT float yogaNodeGetGridColumnLineOffset(LayoutData* layoutData,
                                             uint32_t index)
{
    return layoutData == nullptr
               ? 0.0f
               : YGNodeLayoutGetGridColumnLineOffset(&layoutData->node, index);
}
EXPORT uint32_t yogaNodeGetGridRowLineCount(LayoutData* layoutData)
{
    return layoutData == nullptr
               ? 0
               : YGNodeLayoutGetGridRowLineCount(&layoutData->node);
}
EXPORT float yogaNodeGetGridRowLineOffset(LayoutData* layoutData,
                                          uint32_t index)
{
    return layoutData == nullptr
               ? 0.0f
               : YGNodeLayoutGetGridRowLineOffset(&layoutData->node, index);
}
EXPORT YGValue yogaStyleGetFlexBasis(YGStyle* style)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }
    facebook::yoga::detail::CompactValue compact = style->flexBasis();

    YGValue value = compact;
    return value;
}
EXPORT YGValue yogaStyleGetMargin(YGStyle* style, int edge)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->margin()[(YGEdge)edge];
}
EXPORT YGValue yogaStyleGetPosition(YGStyle* style, int edge)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->position()[(YGEdge)edge];
}
EXPORT YGValue yogaStyleGetPadding(YGStyle* style, int edge)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->padding()[(YGEdge)edge];
}
EXPORT YGValue yogaStyleGetBorder(YGStyle* style, int edge)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->border()[(YGEdge)edge];
}
EXPORT YGValue yogaStyleGetGap(YGStyle* style, int gutter)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->gap()[(YGGutter)gutter];
}
EXPORT YGValue yogaStyleGetDimension(YGStyle* style, int dimension)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->dimensions()[(YGDimension)dimension];
}
EXPORT YGValue yogaStyleGetMinDimension(YGStyle* style, int dimension)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->minDimensions()[(YGDimension)dimension];
}
EXPORT YGValue yogaStyleGetMaxDimension(YGStyle* style, int dimension)
{
    if (style == nullptr)
    {
        return {0.0f, YGUnitAuto};
    }

    return style->maxDimensions()[(YGDimension)dimension];
}
static YGSize _measureFunc(YGNode* node,
                           float width,
                           YGMeasureMode widthMode,
                           float height,
                           YGMeasureMode heightMode)
{
    if (node == nullptr)
    {
        return {0.0f, 0.0f};
    }
    auto nodeContext = static_cast<NodeContext*>(node->getContext());
    if (nodeContext == nullptr)
    {
        return {0.0f, 0.0f};
    }

    return nodeContext->measureFunc(nodeContext->layoutData,
                                    width,
                                    widthMode,
                                    height,
                                    heightMode);
}
static float _baselineFunc(YGNode* node, float width, float height)
{
    if (node == nullptr)
    {
        return 0.0f;
    }
    auto nodeContext = static_cast<NodeContext*>(node->getContext());
    if (nodeContext == nullptr)
    {
        return 0.0f;
    }

    return nodeContext->baselineFunc(nodeContext->layoutData, width, height);
}
EXPORT void yogaNodeSetMeasureFunc(LayoutData* layoutData,
                                   RiveMeasureFunc measureFunc)
{
    if (layoutData == nullptr)
    {
        return;
    }

    auto context = static_cast<NodeContext*>(layoutData->node.getContext());
    if (context == nullptr)
    {
        context = new NodeContext();
        layoutData->node.setContext(context);
    }
    context->layoutData = layoutData;
    context->measureFunc = measureFunc;

    layoutData->node.setMeasureFunc(_measureFunc);
}

EXPORT void yogaNodeClearMeasureFunc(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return;
    }

    layoutData->node.setMeasureFunc(nullptr);
}

EXPORT void yogaNodeSetBaselineFunc(LayoutData* layoutData,
                                    RiveBaselineFunc baselineFunc)
{
    if (layoutData == nullptr)
    {
        return;
    }

    auto context = static_cast<NodeContext*>(layoutData->node.getContext());
    if (context == nullptr)
    {
        context = new NodeContext();
        layoutData->node.setContext(context);
    }
    context->layoutData = layoutData;
    context->baselineFunc = baselineFunc;

    layoutData->node.setBaselineFunc(_baselineFunc);
}

EXPORT void yogaNodeClearBaselineFunc(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return;
    }

    layoutData->node.setBaselineFunc(nullptr);
}

EXPORT void disposeYogaNode(LayoutData* layoutData)
{
    if (layoutData == nullptr)
    {
        return;
    }

    delete (NodeContext*)layoutData->node.getContext();
    layoutData->node.setContext(nullptr);
#ifdef WITH_RIVE_TOOLS
    layoutData->unref();
#else
    delete layoutData;
#endif
}
#endif