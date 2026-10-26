import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart';

/// Regression test for https://github.com/rive-app/rive-flutter/issues/642
///
/// `RiveNativeRenderBox.paint` measures the cumulative scale its ancestors
/// apply (via `RiveNativeRenderBox.ancestorPaintScale`, which calls
/// `getTransformTo(null)`) so it can size its render texture for crisp output.
/// `getTransformTo(null)` walks the entire ancestor chain to the root and asks
/// each ancestor for `applyPaintTransform`. Some ancestors (e.g.
/// `RenderFractionalTranslation`, used by `SlideTransition` /
/// `FractionalTranslation`) read their own `size` there, which throws
/// "RenderBox was not laid out" if that ancestor has not been laid out yet.
///
/// These tests exercise the *real* `RiveNativeRenderBox.ancestorPaintScale`
/// guard against a render tree shaped like the one in the crash report.
class _ScaleProbeRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.biggest;
  }
}

/// Builds: root (rootNode) -> RenderFractionalTranslation -> probe.
///
/// `RenderFractionalTranslation` is the ancestor in the issue's stack trace
/// whose `applyPaintTransform` reads `size`.
({
  PipelineOwner owner,
  RenderProxyBox root,
  RenderFractionalTranslation frac,
  _ScaleProbeRenderBox probe,
}) _buildTree() {
  final probe = _ScaleProbeRenderBox();
  final frac = RenderFractionalTranslation(
    translation: const Offset(0.25, 0.25),
    child: probe,
  );
  final root = RenderProxyBox(frac);
  final owner = PipelineOwner();
  owner.rootNode = root;
  return (owner: owner, root: root, frac: frac, probe: probe);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Documents the underlying framework behaviour the guard protects against:
  // calling getTransformTo(null) while an ancestor is not laid out throws.
  test(
    'getTransformTo(null) throws when an ancestor is not laid out (issue #642)',
    () {
      final tree = _buildTree();

      // Lay out ONLY the probe, leaving its RenderFractionalTranslation ancestor
      // without a size. This is the state the render tree can transiently end up
      // in during route / opacity transitions.
      tree.probe.layout(BoxConstraints.tight(const Size(100, 100)));

      expect(tree.frac.hasSize, isFalse);
      expect(tree.probe.hasSize, isTrue);

      // In debug this surfaces as an AssertionError, in profile/release as a
      // FlutterError, both with the "was not laid out" message. This is exactly
      // what would happen if RiveNativeRenderBox.paint called getTransformTo
      // unguarded.
      expect(
        () => tree.probe.getTransformTo(null),
        throwsA(predicate((e) => e.toString().contains('was not laid out'))),
      );
    },
  );

  // Exercises the REAL production guard.
  test(
    'RiveNativeRenderBox.ancestorPaintScale returns null when an ancestor is '
    'not laid out (does not throw)',
    () {
      final tree = _buildTree();

      tree.probe.layout(BoxConstraints.tight(const Size(100, 100)));
      expect(tree.frac.hasSize, isFalse);

      // The production guard must bail out instead of crashing.
      expect(RiveNativeRenderBox.ancestorPaintScale(tree.probe), isNull);
    },
  );

  // Exercises the REAL production scale computation on a fully laid-out tree.
  test(
    'RiveNativeRenderBox.ancestorPaintScale measures the scale once the tree '
    'is laid out',
    () {
      final tree = _buildTree();

      tree.root.layout(BoxConstraints.tight(const Size(100, 100)));
      expect(tree.frac.hasSize, isTrue);

      final scale = RiveNativeRenderBox.ancestorPaintScale(tree.probe);
      expect(scale, isNotNull);
      expect(scale!.$1, 1.0);
      expect(scale.$2, 1.0);
    },
  );

  // A scaling ancestor should be reflected in the measured scale.
  test(
    'RiveNativeRenderBox.ancestorPaintScale reflects a scaling ancestor',
    () {
      final probe = _ScaleProbeRenderBox();
      final transform = RenderTransform(
        transform: Matrix4.diagonal3Values(2.0, 3.0, 1.0),
        child: probe,
      );
      final root = RenderProxyBox(transform);
      final owner = PipelineOwner();
      owner.rootNode = root;

      root.layout(BoxConstraints.tight(const Size(100, 100)));

      final scale = RiveNativeRenderBox.ancestorPaintScale(probe);
      expect(scale, isNotNull);
      expect(scale!.$1, closeTo(2.0, 1e-9));
      expect(scale.$2, closeTo(3.0, 1e-9));
    },
  );
}
