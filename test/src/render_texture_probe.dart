import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

/// Painter that never draws; render-texture tests only assert backing size.
final class NoopTexturePainter extends rive.RenderTexturePainter {
  @override
  Color get background => const Color(0x00000000);

  @override
  bool paint(rive.RenderTexture texture, double devicePixelRatio, Size size,
          double elapsedSeconds) =>
      false;
}

/// Hosts [child] the way `texture.widget()` needs (its Stack of
/// HtmlElementView + view requires an ambient Directionality), under an
/// optional ancestor [transform].
Widget host(Widget child, {Matrix4? transform}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Transform(
          transform: transform ?? Matrix4.identity(),
          alignment: Alignment.center,
          child: SizedBox(width: 100, height: 80, child: child),
        ),
      ),
    );

/// Pumps [widget] and settles the measure → relayout → resize round trip.
Future<void> pumpSettled(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

/// Creates a real texture + no-op painter pair with disposal registered.
(rive.RenderTexture, rive.RenderTexturePainter) makeProbe() {
  final texture = rive.RiveNative.instance.makeRenderTexture();
  final painter = NoopTexturePainter();
  addTearDown(texture.dispose);
  addTearDown(painter.dispose);
  return (texture, painter);
}
