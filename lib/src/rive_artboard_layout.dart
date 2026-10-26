import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';
import 'package:rive_native/rive_native.dart';

/// A mixin that provides artboard layout options to a [RivePainter].
///
/// This mixin allows a painter to resize and position its artboard in response to size changes.
/// It provides control over how the artboard is scaled and positioned within its bounds through
/// [fit] and [alignment] properties. When using [Fit.layout], the artboard dimensions will
/// match the widget size, scaled by [layoutScaleFactor]. Other fit modes like [Fit.contain],
/// [Fit.cover], etc. will scale and position the artboard while maintaining its original
/// aspect ratio.
///
/// The mixin provides:
/// - [fit] - Controls how the artboard is scaled and positioned within its bounds
/// - [alignment] - Controls the alignment of the artboard within its bounds
/// - [layoutScaleFactor] - Scale factor applied when using [Fit.layout]
/// - [size] - The current size of the paint area (set automatically during layout).
/// This should be the same as the size of the widget. Initiall set to zero until the widget is laid out.
base mixin RiveArtboardLayoutMixin on RivePainter {
  Artboard? get artboard;

  /// The current size of the paint area.
  ///
  /// This property is set automatically by the Rive render object when the widget
  /// is laid out. When [fit] is [Fit.layout], setting this property will automatically
  /// resize the artboard dimensions to match.
  Size _size = Size.zero;
  Size get size => _size;
  @Deprecated('Use [size] instead')
  Size get lastSize => _size;

  /// Internal method.
  ///
  /// Updates the size of the paint area.
  ///
  /// This method is called automatically by the Rive render object when the widget
  /// is laid out. When [fit] is [Fit.layout], setting this property will automatically
  /// resize the artboard dimensions to match.
  @internal
  void updateSize(Size size) {
    if (_size == size) return;
    _size = size;
    _resizeArtboard();
  }

  /// Resizes the [artboard] to match the given [size] when using [Fit.layout].
  ///
  /// The artboard dimensions are scaled by [layoutScaleFactor].
  ///
  /// This is called automatically when setting the [size] property.
  void _resizeArtboard() {
    if (fit != Fit.layout) return;
    final artboardToResize = artboard;
    if (artboardToResize == null) return;

    artboardToResize.width = size.width / layoutScaleFactor;
    artboardToResize.height = size.height / layoutScaleFactor;
  }

  /// Controls how the artboard is scaled and positioned within its bounds.
  ///
  /// The fit mode determines how the artboard's dimensions are mapped to the
  /// widget's dimensions:
  /// - [Fit.layout] - Resize artboard to match widget size. Used with Rive's
  /// layout system.
  /// - [Fit.contain] - Scale to fit while maintaining aspect ratio
  /// - [Fit.cover] - Scale to cover while maintaining aspect ratio
  /// - [Fit.fill] - Stretch to fill the bounds
  /// - [Fit.fitWidth] - Scale to fit width while maintaining aspect ratio
  /// - [Fit.fitHeight] - Scale to fit height while maintaining aspect ratio
  /// - [Fit.none] - No scaling applied
  /// - [Fit.scaleDown] - Scale down to fit if needed
  ///
  /// When using [Fit.layout], the artboard dimensions are scaled by
  /// [layoutScaleFactor] to determine the final size.
  Fit get fit => _fit;
  Fit _fit = RiveDefaults.fit;
  set fit(Fit value) {
    if (_fit == value) return;

    if (value == Fit.layout) {
      _resizeArtboard();
    } else if (_fit == Fit.layout) {
      // Previous fit was Layout, we need to reset the artboard size to default
      artboard?.resetArtboardSize();
    }

    _fit = value;
    notifyListeners();
  }

  /// Controls how the artboard is aligned within its bounds.
  ///
  /// When the artboard's dimensions don't match the widget size exactly,
  /// this determines where the artboard is positioned. For example:
  /// - [Alignment.center] centers the artboard (default)
  /// - [Alignment.topLeft] positions it at the top left
  /// - [Alignment.bottomRight] positions it at the bottom right
  ///
  /// The alignment is used in conjunction with [fit] to determine the final
  /// position of the artboard content.
  Alignment get alignment => _alignment;
  Alignment _alignment = RiveDefaults.alignment;
  set alignment(Alignment value) {
    if (_alignment == value) return;

    _alignment = value;
    notifyListeners();
  }

  /// The scale factor to use for a fit of type `Fit.layout`.
  ///
  /// When using [Fit.layout], the artboard dimensions are scaled by this factor
  /// to determine the final size. A scale factor of 1.0 means the artboard
  /// dimensions will exactly match the widget size. Values less than 1.0 will
  /// make the artboard larger than the widget, while values greater than 1.0
  /// will make it smaller.
  ///
  /// For example, with a scale factor of 0.5:
  /// - Widget size: 200x100
  /// - Artboard size: 400x200
  ///
  /// This is useful for controlling the scale of the artboard content relative
  /// to the widget size.
  double get layoutScaleFactor => _layoutScaleFactor;
  double _layoutScaleFactor = RiveDefaults.layoutScaleFactor;
  set layoutScaleFactor(double value) {
    if (_layoutScaleFactor == value) return;
    _layoutScaleFactor = value;

    if (fit == Fit.layout) {
      _resizeArtboard();
    }

    notifyListeners();
  }
}
