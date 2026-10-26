import 'package:rive_native/rive_native.dart' as rive;

/// The cross-platform texture-allocation contract.
///
/// One table of {policy} × {ancestor transform} scenarios with a single
/// shared formula for the expected backing size, asserted against real
/// allocations on the VM (`allocation_contract_test.dart`, headless Metal)
/// and on chrome (`allocation_contract_web_test.dart`, real WebGL). Native
/// and web must agree on this formula — a change that reaches only one
/// platform fails the other twin.
///
/// The formula gives the backing as a multiple of the *base extent*:
/// - native: the widget's layout size;
/// - web (`flutter test --platform chrome`): the canvas client size — the
///   harness never adopts platform-view canvases into their slots, so the
///   canvas sizes to the document body and layout size is irrelevant there.
///   Web asserts ratios against a measured baseline, never absolutes.
class AllocationContractCase {
  final String name;
  final rive.RenderResolution resolution;

  /// Uniform-per-axis ancestor paint scale applied above the widget.
  /// Keep multipliers modest: on the web harness the base extent is the
  /// document body, and large factors would engage the 4096 logical clamp.
  final double ancestorScaleX;
  final double ancestorScaleY;

  const AllocationContractCase(
    this.name,
    this.resolution, [
    this.ancestorScaleX = 1,
    this.ancestorScaleY = 1,
  ]);
}

/// Expected backing size in physical pixels for [c] given the base extent.
///
/// `exact` is true for [rive.FixedRenderResolution] (absolute pixels,
/// independent of the base — assert equality, not a tolerance).
({double width, double height, bool exact}) expectedBacking(
  AllocationContractCase c, {
  required double baseWidth,
  required double baseHeight,
  required double dpr,
}) =>
    switch (c.resolution) {
      rive.DisplayRenderResolution() => (
          width: baseWidth * dpr * c.ancestorScaleX,
          height: baseHeight * dpr * c.ancestorScaleY,
          exact: false,
        ),
      rive.LayoutRenderResolution(:final scale) => (
          width: baseWidth * dpr * scale,
          height: baseHeight * dpr * scale,
          exact: false,
        ),
      rive.FixedRenderResolution(:final width, :final height) => (
          width: width.toDouble(),
          height: height.toDouble(),
          exact: true,
        ),
    };

const allocationContractCases = [
  AllocationContractCase(
    'display: identity tree allocates base * DPR',
    rive.RenderResolution.display(),
  ),
  AllocationContractCase(
    'display: non-uniform ancestor scale folds in per axis',
    rive.RenderResolution.display(),
    1.25,
    1.5,
  ),
  AllocationContractCase(
    'layout: ancestor scale is composite-only',
    rive.RenderResolution.layout(),
    3,
    3,
  ),
  AllocationContractCase(
    'layout(scale: 0.5): halves the backing',
    rive.RenderResolution.layout(scale: 0.5),
  ),
  AllocationContractCase(
    'fixed(64, 32): exact physical pixels, transforms ignored',
    rive.RenderResolution.fixed(64, 32),
    3,
    3,
  ),
];
