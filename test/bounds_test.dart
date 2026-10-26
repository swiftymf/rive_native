import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/utils.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  void boundsTest(rive.Component? component, double left, double top,
      double right, double bottom, double width, double height) {
    expect(component, isNotNull);
    expect(component!.localBounds.left, closeTo(left, 0.00002));
    expect(component.localBounds.top, closeTo(top, 0.00002));
    expect(component.localBounds.right, closeTo(right, 0.00002));
    expect(component.localBounds.bottom, closeTo(bottom, 0.00002));
    expect(component.localBounds.width, closeTo(width, 0.00002));
    expect(component.localBounds.height, closeTo(height, 0.00002));
  }

  test('Component bounds - match c++ test', () async {
    final riveBytes = loadFile('assets/local_bounds.riv');
    final riveFile =
        await rive.File.decode(riveBytes, riveFactory: rive.Factory.flutter)
            as rive.File;
    final artboard = riveFile.defaultArtboard();
    expect(artboard, isNotNull);
    final stateMachine = artboard!.defaultStateMachine();
    expect(stateMachine, isNotNull);
    stateMachine!.advanceAndApply(0);
    final shape1 = artboard.component('Shape1');
    final shape2 = artboard.component('Shape2');
    final shape3 = artboard.component('Shape3');
    final text1 = artboard.component('Text1');
    final text2 = artboard.component('Text2');
    final group1 = artboard.component('Group1');
    final image1 = artboard.component('Image1');
    final nslice2 = artboard.component('NSlice2');
    final customShape1 = artboard.component('CustomShape1');
    final customPath1 = artboard.component('CustomPath1');
    final layoutContainer = artboard.component('LayoutContainer');
    final layoutCellLeft = artboard.component('LayoutCellLeft');

    // Origin 0.5,0.5
    boundsTest(shape1, -35, -35, 35, 35, 70, 70);
    // Origin 1.0,1.0
    boundsTest(shape2, -80, -80, 0, 0, 80, 80);
    // Origin 0.0,0.0
    boundsTest(shape3, 0, 0, 60, 60, 60, 60);
    // Origin 0.0,0.0
    boundsTest(text1, 0, 0, 159.55078, 24.19921, 159.55078, 24.19921);
    // Origin 0.5,0.5
    boundsTest(text2, -79.775390, -12.099609, 79.775390, 12.099609, 159.55078,
        24.19921);
    boundsTest(group1, 0, 0, 0, 0, 0, 0);
    // Origin 0.5,0.5
    boundsTest(image1, -64, -64, 64, 64, 128, 128);
    boundsTest(nslice2, 0, 0, 112.18910, 77.70859, 112.18910, 77.70859);
    boundsTest(customShape1, -27.82596, -32.02759, 105.36988, 52.382587,
        133.19584, 84.410182);
    boundsTest(customPath1, -11.52589, -25.32601, 100.66321, 52.38258, 112.1891,
        77.7086);
    boundsTest(layoutContainer, 0, 0, 200, 100, 200, 100);
    boundsTest(layoutCellLeft, 0, 0, 88, 84, 88, 84);
  });
}
