import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_pathops.dart';
import 'package:rive_native/rive_native.dart' show PathFillType;
import 'package:rive_native/rive_text.dart' show RawPathVerb;

// y-down screen space: left-top -> right-top -> right-bottom -> left-bottom
// is visually clockwise.
PathOpsPathBuffers rectCW(double l, double t, double r, double b) {
  final path = PathOpsPathBuffers()
    ..moveTo(l, t)
    ..lineTo(r, t)
    ..lineTo(r, b)
    ..lineTo(l, b)
    ..close();
  return path;
}

PathOpsPathBuffers rectCCW(double l, double t, double r, double b) {
  final path = PathOpsPathBuffers()
    ..moveTo(l, t)
    ..lineTo(l, b)
    ..lineTo(r, b)
    ..lineTo(r, t)
    ..close();
  return path;
}

/// Winding-based point containment for line-only result paths.
bool contains(PathOpsResult result, double px, double py) {
  var winding = 0;
  var first = (0.0, 0.0);
  var last = (0.0, 0.0);
  void edge((double, double) a, (double, double) b) {
    if (a.$2 == b.$2) {
      return;
    }
    final crossesDown = a.$2 <= py && b.$2 > py;
    final crossesUp = b.$2 <= py && a.$2 > py;
    if (crossesDown || crossesUp) {
      final t = (py - a.$2) / (b.$2 - a.$2);
      final x = a.$1 + t * (b.$1 - a.$1);
      if (x > px) {
        winding += b.$2 > a.$2 ? 1 : -1;
      }
    }
  }

  for (final command in result.path) {
    switch (command.verb) {
      case RawPathVerb.move:
        first = last = (command.point(0).x, command.point(0).y);
        break;
      case RawPathVerb.line:
        final p = (command.point(1).x, command.point(1).y);
        edge(last, p);
        last = p;
        break;
      case RawPathVerb.close:
        edge(last, first);
        last = first;
        break;
      default:
        fail('Unexpected curve verb in rect-only result');
    }
  }
  edge(last, first);
  return winding != 0;
}

bool isEmpty(PathOpsResult result) => result.path.isEmpty;

void main() {
  if (!pathOpsAvailable) {
    // flutter_runtime builds exclude the pathops symbols (editor-only);
    // this suite also runs in the runtime-publishing CI, which builds the
    // library with flutter-runtime. Nothing to test there.
    return;
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  test('pointsRequiredForVerbs matches verb consumption', () {
    final path = PathOpsPathBuffers()
      ..moveTo(0, 0)
      ..lineTo(10, 0)
      ..quadTo(15, 5, 10, 10)
      ..cubicTo(8, 12, 2, 12, 0, 10)
      ..close();
    expect(pointsRequiredForVerbs(path.verbs), path.points.length);
    expect(path.isConsistent, isTrue);
    // Unknown verb byte fails closed.
    expect(pointsRequiredForVerbs(Uint8List.fromList([0, 3])), -1);
  });

  test('union joins overlapping rects', () {
    final result = combineRawPaths(
      PathBooleanOp.join,
      rectCW(0, 0, 100, 100),
      PathFillType.nonZero,
      rectCW(50, 0, 150, 100),
      PathFillType.nonZero,
    );
    expect(result, isNotNull);
    expect(contains(result!, 25, 50), isTrue);
    expect(contains(result, 75, 50), isTrue);
    expect(contains(result, 125, 50), isTrue);
    expect(contains(result, 175, 50), isFalse);
    result.dispose();
  });

  test('difference subtracts the second path', () {
    final result = combineRawPaths(
      PathBooleanOp.difference,
      rectCW(0, 0, 100, 100),
      PathFillType.nonZero,
      rectCW(50, 0, 150, 100),
      PathFillType.nonZero,
    );
    expect(result, isNotNull);
    expect(contains(result!, 25, 50), isTrue);
    expect(contains(result, 75, 50), isFalse);
    expect(contains(result, 125, 50), isFalse);
    result.dispose();
  });

  test('intersect keeps only the overlap', () {
    final result = combineRawPaths(
      PathBooleanOp.intersect,
      rectCW(0, 0, 100, 100),
      PathFillType.nonZero,
      rectCW(50, 0, 150, 100),
      PathFillType.nonZero,
    );
    expect(result, isNotNull);
    expect(contains(result!, 25, 50), isFalse);
    expect(contains(result, 75, 50), isTrue);
    expect(contains(result, 125, 50), isFalse);
    result.dispose();
  });

  test('clockwise fill rule drops counterclockwise contours', () {
    final result = simplifyRawPath(
      rectCCW(0, 0, 100, 100),
      PathFillType.clockWise,
    );
    expect(result, isNotNull);
    expect(isEmpty(result!), isTrue);
    result.dispose();
  });

  test('clockwise fill rule keeps clockwise contours', () {
    final result = simplifyRawPath(
      rectCW(0, 0, 100, 100),
      PathFillType.clockWise,
    );
    expect(result, isNotNull);
    expect(isEmpty(result!), isFalse);
    expect(contains(result, 50, 50), isTrue);
    result.dispose();
  });

  test('nonZero keeps counterclockwise contours (contrast with clockwise)', () {
    final result = simplifyRawPath(
      rectCCW(0, 0, 100, 100),
      PathFillType.nonZero,
    );
    expect(result, isNotNull);
    expect(isEmpty(result!), isFalse);
    expect(contains(result, 50, 50), isTrue);
    result.dispose();
  });

  test('clockwise hole punch: CW outer + CCW inner leaves a ring', () {
    final path = rectCW(0, 0, 100, 100);
    // Second contour in the same path, wound counterclockwise: a hole.
    path
      ..moveTo(25, 25)
      ..lineTo(25, 75)
      ..lineTo(75, 75)
      ..lineTo(75, 25)
      ..close();
    final result = simplifyRawPath(path, PathFillType.clockWise);
    expect(result, isNotNull);
    expect(contains(result!, 10, 50), isTrue); // ring
    expect(contains(result, 50, 50), isFalse); // hole
    result.dispose();
  });

  test('clockwise combine: CCW operand contributes no area', () {
    final result = combineRawPaths(
      PathBooleanOp.join,
      rectCCW(0, 0, 100, 100),
      PathFillType.clockWise,
      rectCW(50, 0, 150, 100),
      PathFillType.clockWise,
    );
    expect(result, isNotNull);
    expect(contains(result!, 25, 50), isFalse); // only in the CCW operand
    expect(contains(result, 125, 50), isTrue); // in the CW operand
    result.dispose();
  });

  test('result iterates as valid RawPath commands', () {
    final result = combineRawPaths(
      PathBooleanOp.join,
      rectCW(0, 0, 100, 100),
      PathFillType.nonZero,
      rectCW(200, 0, 300, 100),
      PathFillType.nonZero,
    );
    expect(result, isNotNull);
    var moves = 0;
    for (final command in result!.path) {
      if (command.verb == RawPathVerb.move) {
        moves++;
      }
    }
    // Disjoint rects: two contours survive.
    expect(moves, 2);
    result.dispose();
  });
}
