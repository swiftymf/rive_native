import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show MouseCursor;
import 'package:rive_native/rive_native.dart';

abstract class RiveDefaults {
  /// The default [Alignment] for Rive artboards.
  static const alignment = Alignment.center;

  /// The default [Fit] for Rive artboards.
  static const fit = Fit.contain;

  /// The default layout scale factor.
  static const layoutScaleFactor = 1.0;

  /// The default [RiveHitTestBehavior] for Rive listeners.
  static const hitTestBehaviour = RiveHitTestBehavior.opaque;

  /// The default [MouseCursor] for Rive listeners.
  static const mouseCursor = MouseCursor.defer;

  /// The default [RenderResolution] for Rive widgets.
  static const renderResolution = RenderResolution.defaultValue;
}
