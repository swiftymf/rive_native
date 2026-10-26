import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'src/ffi/layout_engine_ffi.dart'
    if (dart.library.js_interop) 'src/web/layout_engine_web.dart';

enum LayoutOverflow { visible, hidden, scroll }

enum LayoutAlign {
  auto,
  flexStart,
  center,
  flexEnd,
  stretch,
  baseline,
  spaceBetween,
  spaceAround,
  // Grid backport values; appended to match the rive yoga fork.
  start,
  end,
  spaceEvenly,
}

enum LayoutDirection {
  inherit,
  ltr,
  rtl,
}

enum LayoutFlexDirection {
  column,
  columnReverse,
  row,
  rowReverse;

  bool get isRow => [
        LayoutFlexDirection.row,
        LayoutFlexDirection.rowReverse,
      ].contains(this);

  bool get isColumn => [
        LayoutFlexDirection.column,
        LayoutFlexDirection.columnReverse,
      ].contains(this);
}

enum LayoutGutter {
  column,
  row,
  all,
}

enum LayoutGridTrackType {
  auto,
  points,
  percent,
  fr,
  minmax,
}

enum LayoutGridCollection {
  templateColumns,
  templateRows,
  autoColumns,
  autoRows,
}

enum LayoutGridLineType {
  auto,
  lineIndex,
  span,
}

enum LayoutGridLinePosition {
  columnStart,
  columnEnd,
  rowStart,
  rowEnd,
}

/// A single entry of a grid track list (grid-template-rows/columns,
/// grid-auto-rows/columns). For [LayoutGridTrackType.minmax] tracks, [minType]
/// and [value] describe the min sizing function and [maxType]/[maxValue] the
/// max sizing function.
class LayoutGridTrack {
  final LayoutGridTrackType type;
  final double value;
  final LayoutGridTrackType minType;
  final LayoutGridTrackType maxType;
  final double maxValue;

  const LayoutGridTrack.points(this.value)
      : type = LayoutGridTrackType.points,
        minType = LayoutGridTrackType.auto,
        maxType = LayoutGridTrackType.auto,
        maxValue = 0;

  const LayoutGridTrack.percent(this.value)
      : type = LayoutGridTrackType.percent,
        minType = LayoutGridTrackType.auto,
        maxType = LayoutGridTrackType.auto,
        maxValue = 0;

  const LayoutGridTrack.fr(this.value)
      : type = LayoutGridTrackType.fr,
        minType = LayoutGridTrackType.auto,
        maxType = LayoutGridTrackType.auto,
        maxValue = 0;

  const LayoutGridTrack.auto()
      : type = LayoutGridTrackType.auto,
        value = 0,
        minType = LayoutGridTrackType.auto,
        maxType = LayoutGridTrackType.auto,
        maxValue = 0;

  const LayoutGridTrack.minmax(
      this.minType, this.value, this.maxType, this.maxValue)
      : type = LayoutGridTrackType.minmax;
}

/// A grid line placement (grid-row/column-start/end).
class LayoutGridLine {
  final LayoutGridLineType type;
  final int value;

  const LayoutGridLine.auto()
      : type = LayoutGridLineType.auto,
        value = 0;
  const LayoutGridLine.at(this.value)
      : type = LayoutGridLineType.lineIndex;
  const LayoutGridLine.span(this.value) : type = LayoutGridLineType.span;
}

enum LayoutDisplay {
  flex,
  none,
  grid,
}

enum LayoutJustify {
  flexStart,
  center,
  flexEnd,
  spaceBetween,
  spaceAround,
  spaceEvenly,
  // Grid backport values; appended to match the rive yoga fork.
  auto,
  stretch,
  start,
  end,
}

enum LayoutMeasureMode {
  undefined,
  exactly,
  atMost,
}

enum LayoutNodeType {
  normal,
  text,
}

enum LayoutWrap {
  noWrap,
  wrap,
  wrapReverse,
}

enum LayoutPosition {
  static,
  relative,
  absolute,
}

enum LayoutDimension {
  width,
  height,
}

enum LayoutUnit {
  undefined,
  point,
  percent,
  auto;

  bool get isPercent => this == LayoutUnit.percent;

  bool get isDefinitive =>
      [LayoutUnit.point, LayoutUnit.percent].contains(this);

  bool get isNotDefinitive =>
      [LayoutUnit.auto, LayoutUnit.undefined].contains(this);

  bool get isInteractable =>
      [LayoutUnit.point, LayoutUnit.percent, LayoutUnit.auto].contains(this);

  bool get isNotInteractable => [LayoutUnit.undefined].contains(this);
}

enum LayoutEdge {
  left,
  top,
  right,
  bottom,
  start,
  end,
  horizontal,
  vertical,
  all,
}

enum LayoutError {
  none,
  stretchFlexBasis, // 1
  all, // 2147483647
  classic, // 2147483646
}

class LayoutValue {
  final double value;
  final LayoutUnit unit;

  const LayoutValue({
    required this.value,
    required this.unit,
  });

  const LayoutValue.points(this.value) : unit = LayoutUnit.point;
  const LayoutValue.undefined()
      : unit = LayoutUnit.undefined,
        value = double.nan;

  const LayoutValue.auto()
      : unit = LayoutUnit.auto,
        value = double.nan;

  const LayoutValue.percent(this.value) : unit = LayoutUnit.percent;
}

abstract class LayoutStyle {
  static LayoutStyle make() {
    return makeLayoutStyle();
  }

  void dispose();

  LayoutAlign get alignContent;
  set alignContent(LayoutAlign value);

  LayoutDirection get direction;
  set direction(LayoutDirection value);

  LayoutFlexDirection get flexDirection;
  set flexDirection(LayoutFlexDirection value);

  LayoutJustify get justifyContent;
  set justifyContent(LayoutJustify value);

  LayoutAlign get alignItems;
  set alignItems(LayoutAlign value);

  LayoutAlign get alignSelf;
  set alignSelf(LayoutAlign value);

  LayoutPosition get positionType;
  set positionType(LayoutPosition value);

  LayoutWrap get flexWrap;
  set flexWrap(LayoutWrap value);

  LayoutOverflow get overflow;
  set overflow(LayoutOverflow value);

  LayoutDisplay get display;
  set display(LayoutDisplay value);

  double? get flex;
  set flex(double? value);

  double? get flexGrow;
  set flexGrow(double? value);

  double? get flexShrink;
  set flexShrink(double? value);

  LayoutValue get flexBasis;
  set flexBasis(LayoutValue value);

  double? get aspectRatio;
  set aspectRatio(double? value);

  LayoutValue getMargin(LayoutEdge edge);
  void setMargin(LayoutEdge edge, LayoutValue value);

  LayoutValue getPosition(LayoutEdge edge);
  void setPosition(LayoutEdge edge, LayoutValue value);

  LayoutValue getPadding(LayoutEdge edge);
  void setPadding(LayoutEdge edge, LayoutValue value);

  LayoutValue getBorder(LayoutEdge edge);
  void setBorder(LayoutEdge edge, LayoutValue value);

  LayoutValue getGap(LayoutGutter gutter);
  void setGap(LayoutGutter gutter, LayoutValue value);

  LayoutValue getDimension(LayoutDimension dimension);
  void setDimension(LayoutDimension dimension, LayoutValue value);

  LayoutValue getMinDimension(LayoutDimension dimension);
  void setMinDimension(LayoutDimension dimension, LayoutValue value);

  LayoutValue getMaxDimension(LayoutDimension dimension);
  void setMaxDimension(LayoutDimension dimension, LayoutValue value);

  LayoutJustify get justifyItems;
  set justifyItems(LayoutJustify value);

  LayoutJustify get justifySelf;
  set justifySelf(LayoutJustify value);

  /// Replaces the track list of [collection] with [tracks].
  void setGridTracks(
      LayoutGridCollection collection, List<LayoutGridTrack> tracks);

  void setGridLine(LayoutGridLinePosition position, LayoutGridLine line);
}

class Layout {
  late double left;
  late double top;
  late double width;
  late double height;
  Layout(double left, double top, double width, double height) {
    this.left = left.isNaN ? 0 : left;
    this.top = top.isNaN ? 0 : top;
    this.width = width.isNaN ? 0 : width;
    this.height = height.isNaN ? 0 : height;
  }
  Layout.zero() : this(0, 0, 0, 0);
  Layout.clone(Layout source)
      : this(source.left, source.top, source.width, source.height);

  bool equals(Layout v) =>
      left == v.left && top == v.top && width == v.width && height == v.height;

  // ignore: prefer_constructors_over_static_methods
  static Layout lerp(Layout from, Layout to, double f) {
    double fi = 1.0 - f;
    return Layout(to.left * f + from.left * fi, to.top * f + from.top * fi,
        to.width * f + from.width * fi, to.height * f + from.height * fi);
  }

  ui.Offset get offset => ui.Offset(left, top);
  ui.Size get size => ui.Size(width, height);
}

class LayoutPadding {
  final double left;
  final double top;
  final double right;
  final double bottom;
  LayoutPadding(this.left, this.top, this.right, this.bottom);
  LayoutPadding.zero() : this(0, 0, 0, 0);
  LayoutPadding.clone(LayoutPadding source)
      : this(source.left, source.top, source.right, source.bottom);

  bool equals(LayoutPadding v) =>
      left == v.left && top == v.top && right == v.right && bottom == v.bottom;
}

typedef MeasureFunction = Size Function(
  LayoutNode node,
  double width,
  LayoutMeasureMode widthMode,
  double height,
  LayoutMeasureMode heightMode,
);

typedef BaselineFunction = double Function(
  LayoutNode node,
  double width,
  double height,
);

abstract class LayoutNode {
  static LayoutNode make() {
    return makeLayoutNode();
  }

  void dispose();

  static LayoutNode fromExternal(dynamic ref) {
    return makeLayoutNodeExternal(ref);
  }

  void setStyle(LayoutStyle style);

  LayoutNodeType get nodeType;
  set nodeType(LayoutNodeType value);

  /// Returns true if an update is necessary, and also lowers the flag.
  bool checkAndResetUpdated();

  bool hasError();

  void clearChildren();
  void insertChild(LayoutNode node, int index);
  void removeChild(LayoutNode node);

  void calculateLayout(
      double availableWidth, double availableHeight, LayoutDirection direction);

  /// Provide a function for measuring the desired dimensions of the LayoutNode.
  /// This lets the layout engine know the intrinsic size of the contents. This
  /// doesn't guarantee the final size of the node will match but lets the
  /// layout attempt to provide the desired size when possible. Only works on
  /// leaf nodes (nodes with no further child layout nodes).
  MeasureFunction? get measureFunction;
  set measureFunction(MeasureFunction? value);

  /// Provide a function for measuring the baseline (in Y) of the contents of
  /// the node. The layout engine uses this when the alignment is set to
  /// baseline. Only works on leaf nodes (nodes with no further child layout
  /// nodes).
  BaselineFunction? get baselineFunction;
  set baselineFunction(BaselineFunction? value);

  void markDirty();

  Layout get layout;
  LayoutPadding get layoutPadding;

  /// Resolved grid line positions along each axis, in this node's local content
  /// space (same space as child [layout] positions). Available after layout on
  /// a grid node; empty for non-grid nodes. Consecutive offsets bound a
  /// cell/track, so N lines describe N-1 cells.
  List<double> get gridColumnLineOffsets;
  List<double> get gridRowLineOffsets;
}
