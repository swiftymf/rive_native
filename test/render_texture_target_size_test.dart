import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

/// Tests for how [rive.RiveNativeRenderBox] sizes its backing texture under
/// each [rive.RenderResolution] policy. The default display policy allocates
/// layout size × device pixel ratio × cumulative ancestor paint scale.
///
/// The ancestor scale is measured in [rive.RiveNativeRenderBox.paint] via
/// [rive.RiveNativeRenderBox.ancestorPaintScale] and only refreshes after the
/// render box's own [RenderObject.markNeedsLayout] ran (widget rebuilds
/// trigger this through the painter setter). [targetTextureSize] is what the
/// FFI render object allocates in performLayout.
base class _FakeRenderTexture extends rive.RenderTexture {
  int _width = 0;
  int _height = 0;

  @override
  int get textureId => -1;

  @override
  dynamic get nativeTexture => null;

  @override
  int get actualWidth => _width;

  @override
  int get actualHeight => _height;

  // Never ready: paintTexture bails before needing a renderer.
  @override
  bool get isReady => false;

  @override
  bool get isDisposed => false;

  @override
  rive.Renderer get renderer => throw UnimplementedError();

  @override
  bool clear(Color color, [bool write = true]) => true;

  @override
  bool flush(double devicePixelRatio) => true;

  @override
  bool needsResize(int width, int height) =>
      width != _width || height != _height;

  @override
  Future<void> makeRenderTexture(int width, int height) async {
    _width = width;
    _height = height;
  }

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();

  @override
  Widget widget({
    rive.RenderTexturePainter? painter,
    rive.RenderResolution resolution = rive.RenderResolution.defaultValue,
    Key? key,
  }) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _ProbeRenderBox extends rive.RiveNativeRenderBox {
  _ProbeRenderBox(super.renderTexture);
}

class _ProbeWidget extends LeafRenderObjectWidget {
  final rive.RenderTexture texture;
  final rive.RenderResolution resolution;
  const _ProbeWidget(
    this.texture, {
    this.resolution = rive.RenderResolution.defaultValue,
  });

  // Mirrors _RiveNativeView's create/updateRenderObject: the painter setter
  // calls markNeedsLayout unconditionally, which arms the ancestor-scale
  // (re)measure on the next paint.
  void _configure(BuildContext context, _ProbeRenderBox renderObject) {
    renderObject
      ..painter = null
      ..renderResolution = resolution
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    final renderObject = _ProbeRenderBox(texture);
    _configure(context, renderObject);
    return renderObject;
  }

  @override
  void updateRenderObject(
          BuildContext context, covariant _ProbeRenderBox renderObject) =>
      _configure(context, renderObject);
}

void main() {
  _ProbeRenderBox probeOf(WidgetTester tester) =>
      tester.renderObject<_ProbeRenderBox>(find.byType(_ProbeWidget));

  void setDpr(WidgetTester tester, double dpr) {
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The canonical probe tree: a fixed-size box, optionally under an
  /// ancestor transform (the shape the web twin test uses too).
  Widget host(
    Widget child, {
    Matrix4? transform,
    double width = 100,
    double height = 80,
  }) =>
      Center(
        child: Transform(
          transform: transform ?? Matrix4.identity(),
          alignment: Alignment.center,
          child: SizedBox(width: width, height: height, child: child),
        ),
      );

  testWidgets('no ancestor transform: texture = layout × DPR', (tester) async {
    setDpr(tester, 2.0);

    await tester.pumpWidget(host(_ProbeWidget(_FakeRenderTexture())));

    final probe = probeOf(tester);
    expect(probe.size, const Size(100, 80));
    expect(probe.desiredTransformWidthScale, 1.0);
    expect(probe.desiredTransformHeightScale, 1.0);
    expect(probe.scaleWidth, 2.0);
    expect(probe.scaleHeight, 2.0);
    expect(probe.targetTextureSize(), (200, 160));
  });

  testWidgets('scale ancestor is folded into the texture size', (tester) async {
    setDpr(tester, 1.0);

    await tester.pumpWidget(host(
      _ProbeWidget(_FakeRenderTexture()),
      transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
    ));
    // First paint measures the scale and schedules a post-frame relayout;
    // settle it.
    await tester.pump();

    final probe = probeOf(tester);
    expect(probe.size, const Size(100, 80));
    expect(probe.desiredTransformWidthScale, 2.0);
    expect(probe.desiredTransformHeightScale, 2.0);
    expect(probe.targetTextureSize(), (200, 160));
  });

  testWidgets('non-uniform ancestor scale is measured per axis',
      (tester) async {
    setDpr(tester, 1.0);

    await tester.pumpWidget(host(
      _ProbeWidget(_FakeRenderTexture()),
      transform: Matrix4.diagonal3Values(2.0, 3.0, 1.0),
    ));
    await tester.pump();

    final probe = probeOf(tester);
    expect(probe.desiredTransformWidthScale, 2.0);
    expect(probe.desiredTransformHeightScale, 3.0);
    expect(probe.targetTextureSize(), (200, 240));
  });

  testWidgets(
      'FittedBox downscale shrinks the texture below layout size '
      '(customer scenario inverted: R laid out, displayed smaller)',
      (tester) async {
    setDpr(tester, 2.0);

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 50,
          height: 40,
          child: FittedBox(
            child: SizedBox(
              width: 100,
              height: 80,
              child: _ProbeWidget(_FakeRenderTexture()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final probe = probeOf(tester);
    // Laid out at the inner 100×80, displayed at 50×40 → ancestor scale 0.5.
    expect(probe.size, const Size(100, 80));
    expect(probe.desiredTransformWidthScale, 0.5);
    expect(probe.desiredTransformHeightScale, 0.5);
    expect(probe.targetTextureSize(), (100, 80));
  });

  testWidgets(
      'FittedBox upscale grows the texture to display size '
      '(the customer scenario: laid out at R, displayed at L)', (tester) async {
    setDpr(tester, 2.0);

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 320,
          child: FittedBox(
            child: SizedBox(
              width: 100,
              height: 80,
              child: _ProbeWidget(_FakeRenderTexture()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final probe = probeOf(tester);
    // Display policy: allocation follows the on-screen footprint (L × DPR),
    // not the layout size (R × DPR). This is the deliberate
    // sharp-under-upscale behavior from #10645.
    expect(probe.size, const Size(100, 80));
    expect(probe.desiredTransformWidthScale, 4.0);
    expect(probe.desiredTransformHeightScale, 4.0);
    expect(probe.targetTextureSize(), (800, 640));
  });

  testWidgets('ancestor scale change on rebuild is remeasured', (tester) async {
    setDpr(tester, 1.0);

    final texture = _FakeRenderTexture();
    Widget tree(double scale) => host(
          _ProbeWidget(texture),
          transform: Matrix4.diagonal3Values(scale, scale, 1.0),
        );

    await tester.pumpWidget(tree(2.0));
    await tester.pump();
    expect(probeOf(tester).desiredTransformWidthScale, 2.0);

    await tester.pumpWidget(tree(3.0));
    await tester.pump();

    final probe = probeOf(tester);
    expect(probe.desiredTransformWidthScale, 3.0);
    expect(probe.desiredTransformHeightScale, 3.0);
    expect(probe.targetTextureSize(), (300, 240));
  });

  testWidgets('device pixel ratio change triggers a new target size',
      (tester) async {
    setDpr(tester, 1.0);

    await tester.pumpWidget(host(_ProbeWidget(_FakeRenderTexture())));
    expect(probeOf(tester).targetTextureSize(), (100, 80));

    tester.view.devicePixelRatio = 3.0;
    await tester.pump();
    await tester.pump();

    final probe = probeOf(tester);
    expect(probe.scaleWidth, 3.0);
    expect(probe.targetTextureSize(), (300, 240));
  });

  testWidgets('layout size change scales the target with it', (tester) async {
    setDpr(tester, 1.0);

    final texture = _FakeRenderTexture();

    await tester.pumpWidget(host(_ProbeWidget(texture), width: 100));
    expect(probeOf(tester).targetTextureSize(), (100, 80));

    await tester.pumpWidget(host(_ProbeWidget(texture), width: 250));
    expect(probeOf(tester).targetTextureSize(), (250, 80));
  });

  testWidgets('fractional results round to nearest physical pixel',
      (tester) async {
    setDpr(tester, 1.0);

    await tester.pumpWidget(host(
      _ProbeWidget(_FakeRenderTexture()),
      transform: Matrix4.diagonal3Values(1.5, 1.5, 1.0),
      width: 33,
      height: 21,
    ));
    await tester.pump();

    // 33 × 1.5 = 49.5 → 50 (round-half-up), 21 × 1.5 = 31.5 → 32.
    expect(probeOf(tester).targetTextureSize(), (50, 32));
  });

  group('RenderResolution policies', () {
    testWidgets(
        'layout: ancestor transform is never measured, target = layout × DPR',
        (tester) async {
      setDpr(tester, 2.0);

      await tester.pumpWidget(host(
        _ProbeWidget(
          _FakeRenderTexture(),
          resolution: const rive.RenderResolution.layout(),
        ),
        transform: Matrix4.diagonal3Values(3.0, 3.0, 1.0),
      ));
      await tester.pump();

      final probe = probeOf(tester);
      // The 3× ancestor scale never enters: no measurement, no allocation.
      expect(probe.desiredTransformWidthScale, 1.0);
      expect(probe.desiredTransformHeightScale, 1.0);
      expect(probe.scaleWidth, 2.0);
      expect(probe.targetTextureSize(), (200, 160));
    });

    testWidgets('layout scale multiplies on top of layout × DPR',
        (tester) async {
      setDpr(tester, 2.0);

      await tester.pumpWidget(host(
        _ProbeWidget(
          _FakeRenderTexture(),
          resolution: const rive.RenderResolution.layout(scale: 0.5),
        ),
      ));

      final probe = probeOf(tester);
      expect(probe.scaleWidth, 1.0);
      expect(probe.targetTextureSize(), (100, 80));
    });

    testWidgets(
        'fixed: exact physical size regardless of layout, DPR, and transforms',
        (tester) async {
      setDpr(tester, 3.0);

      await tester.pumpWidget(host(
        _ProbeWidget(
          _FakeRenderTexture(),
          resolution: const rive.RenderResolution.fixed(256, 128),
        ),
        transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
      ));
      await tester.pump();

      final probe = probeOf(tester);
      expect(probe.targetTextureSize(), (256, 128));
      // Fallback paint scale maps the layout box onto the fixed backing.
      expect(probe.scaleWidth, 256 / 100);
      expect(probe.scaleHeight, 128 / 80);
    });

    testWidgets(
        'display clamps the logical extent at maxTextureLogicalSize, '
        'preserving aspect', (tester) async {
      setDpr(tester, 1.0);

      await tester.pumpWidget(host(
        _ProbeWidget(_FakeRenderTexture()),
        transform: Matrix4.diagonal3Values(100.0, 100.0, 1.0),
      ));
      await tester.pump();

      final probe = probeOf(tester);
      expect(probe.desiredTransformWidthScale, 100.0);
      // Unclamped this would be (10000, 8000); the 4096 logical cap scales
      // both axes by 4096/10000.
      expect(rive.RiveNativeRenderBox.maxTextureLogicalSize, 4096);
      expect(probe.targetTextureSize(), (4096, 3277));
    });

    testWidgets('layout scale is clamped at maxTextureLogicalSize too',
        (tester) async {
      setDpr(tester, 1.0);

      await tester.pumpWidget(host(
        _ProbeWidget(
          _FakeRenderTexture(),
          resolution: const rive.RenderResolution.layout(scale: 100),
        ),
      ));

      expect(probeOf(tester).targetTextureSize(), (4096, 3277));
    });

    testWidgets(
        'clamp logs once per crossing (edge-triggered, debug builds only)',
        (tester) async {
      setDpr(tester, 1.0);

      final logs = <String?>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message);
      try {
        final texture = _FakeRenderTexture();
        Widget tree(double scale) => host(
              _ProbeWidget(
                texture,
                resolution: rive.RenderResolution.layout(scale: scale),
              ),
            );

        await tester.pumpWidget(tree(100));
        final probe = probeOf(tester);
        probe.targetTextureSize();
        probe.targetTextureSize();
        expect(logs.where((m) => m!.contains('clamped')), hasLength(1),
            reason: 'repeated clamped allocations must not re-log');

        // Dropping below the cap re-arms the log.
        await tester.pumpWidget(tree(1));
        probeOf(tester).targetTextureSize();
        await tester.pumpWidget(tree(100));
        probeOf(tester).targetTextureSize();
        expect(logs.where((m) => m!.contains('clamped')), hasLength(2));
      } finally {
        // Must be restored before the binding's end-of-test invariant check —
        // addTearDown is too late for foundation debug variables.
        debugPrint = original;
      }
    });

    testWidgets(
        'switching display → layout resets the cached ancestor scale, and '
        'switching back remeasures', (tester) async {
      setDpr(tester, 1.0);

      final texture = _FakeRenderTexture();
      Widget tree(rive.RenderResolution resolution) => host(
            _ProbeWidget(texture, resolution: resolution),
            transform: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
          );

      await tester.pumpWidget(tree(const rive.RenderResolution.display()));
      await tester.pump();
      expect(probeOf(tester).desiredTransformWidthScale, 2.0);
      expect(probeOf(tester).targetTextureSize(), (200, 160));

      await tester.pumpWidget(tree(const rive.RenderResolution.layout()));
      await tester.pump();
      expect(probeOf(tester).desiredTransformWidthScale, 1.0);
      expect(probeOf(tester).targetTextureSize(), (100, 80));

      await tester.pumpWidget(tree(const rive.RenderResolution.display()));
      await tester.pump();
      expect(probeOf(tester).desiredTransformWidthScale, 2.0);
      expect(probeOf(tester).targetTextureSize(), (200, 160));
    });
  });
}
