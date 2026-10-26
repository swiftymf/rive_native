import 'package:rive_native/rive_native.dart' show RenderTexture;

/// Controls how a Rive [RenderTexture] sizes its backing store relative to
/// the widget's layout.
///
/// Only applies when rendering with `Factory.rive` (the Rive Renderer draws
/// into a texture). With `Factory.flutter` content is painted directly into
/// Flutter's canvas at composite resolution and this setting is ignored.
///
/// The policy changes backing resolution only — layout, fit, alignment, and
/// hit-testing coordinates are unaffected.
sealed class RenderResolution {
  const RenderResolution();

  /// The default policy, referenced by every widget-layer and
  /// [RenderTexture.widget] parameter default so they cannot drift apart.
  static const RenderResolution defaultValue = RenderResolution.display();

  /// The default. The backing store is sized from the widget's layout size ×
  /// device pixel ratio × the cumulative scale ancestors apply at paint time
  /// (e.g. a `FittedBox` or `Transform.scale` above the widget). Content
  /// stays sharp at its final on-screen footprint, at the cost of allocating
  /// for that footprint.
  const factory RenderResolution.display() = DisplayRenderResolution;

  /// The backing store is sized from the widget's layout size × device pixel
  /// ratio × [LayoutRenderResolution.scale]. Ancestor transforms only apply
  /// at composite time: upscaling the widget stretches the texture (softer
  /// output) instead of reallocating it. Use this to decouple render
  /// resolution from on-screen footprint, e.g. for GPU budgeting.
  const factory RenderResolution.layout({double scale}) =
      LayoutRenderResolution;

  /// The backing store has an explicit size in physical pixels, independent
  /// of layout, device pixel ratio, and ancestor transforms. The texture is
  /// never reallocated on resize.
  const factory RenderResolution.fixed(int width, int height) =
      FixedRenderResolution;
}

/// See [RenderResolution.display].
final class DisplayRenderResolution extends RenderResolution {
  const DisplayRenderResolution();

  @override
  bool operator ==(Object other) => other is DisplayRenderResolution;

  @override
  int get hashCode => (DisplayRenderResolution).hashCode;

  @override
  String toString() => 'RenderResolution.display()';
}

/// See [RenderResolution.layout].
final class LayoutRenderResolution extends RenderResolution {
  const LayoutRenderResolution({this.scale = 1.0}) : assert(scale > 0);

  /// Multiplier applied on top of layout size × device pixel ratio.
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is LayoutRenderResolution && other.scale == scale;

  @override
  int get hashCode => Object.hash(LayoutRenderResolution, scale);

  @override
  String toString() => 'RenderResolution.layout(scale: $scale)';
}

/// See [RenderResolution.fixed].
final class FixedRenderResolution extends RenderResolution {
  const FixedRenderResolution(this.width, this.height)
      : assert(width > 0),
        assert(height > 0);

  /// Backing store width in physical pixels.
  final int width;

  /// Backing store height in physical pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is FixedRenderResolution &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(FixedRenderResolution, width, height);

  @override
  String toString() => 'RenderResolution.fixed($width, $height)';
}
