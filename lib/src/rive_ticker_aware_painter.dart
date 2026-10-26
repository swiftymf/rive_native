import 'package:meta/meta.dart';
import 'package:rive_native/rive_native.dart';

/// Mixin that provides access to ticker state for painters.
///
/// This mixin allows painters to query whether the animation ticker is active.
base mixin RiveTickerAwarePainterMixin on RivePainter {
  bool Function()? _tickerStateProvider;

  /// Whether the animation ticker is currently active.
  ///
  /// Returns false if the ticker state provider is not set or if the ticker
  /// is not active.
  @override
  bool get isTickerActive => _tickerStateProvider?.call() ?? false;

  /// Internal method to set the ticker state provider.
  /// This is called by the render box to provide ticker state.
  @internal
  void setTickerStateProvider(bool Function()? provider) {
    _tickerStateProvider = provider;
  }
}
