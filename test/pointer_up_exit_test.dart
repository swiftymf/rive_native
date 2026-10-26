import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart';

/// Records the order of pointer calls. Other [StateMachine] members route
/// through [noSuchMethod] and are never exercised by these tests.
class _RecordingStateMachine implements StateMachine {
  final List<String> calls = <String>[];

  @override
  HitResult pointerDown(Vec2D position, {int pointerId = 0}) {
    calls.add('down');
    return HitResult.hit;
  }

  @override
  HitResult pointerUp(Vec2D position, {int pointerId = 0}) {
    calls.add('up');
    return HitResult.hit;
  }

  @override
  HitResult pointerMove(Vec2D position, {double? timeStamp, int pointerId = 0}) {
    calls.add('move');
    return HitResult.hit;
  }

  @override
  HitResult pointerExit(Vec2D position, {int pointerId = 0}) {
    calls.add('exit');
    return HitResult.hit;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal painter so we can reach the protected [dispatchPointerEvent] helper
/// on [RivePointerEventMixin] from the tests.
final class _TestPainter extends RivePainter with RivePointerEventMixin {
  @override
  bool hitTest(Offset position) => false;

  @override
  void pointerEvent(PointerEvent event, HitTestEntry entry) {}

  HitResult dispatch(StateMachine stateMachine, PointerEvent event) =>
      dispatchPointerEvent(stateMachine, event, Vec2D());
}

void main() {
  late _RecordingStateMachine stateMachine;
  late _TestPainter painter;

  setUp(() {
    stateMachine = _RecordingStateMachine();
    painter = _TestPainter();
  });

  PointerUpEvent up(PointerDeviceKind kind) => PointerUpEvent(kind: kind);
  PointerCancelEvent cancel(PointerDeviceKind kind) =>
      PointerCancelEvent(kind: kind);

  group('pointer up is treated as exit for touch-like devices', () {
    test('touch up dispatches up then exit', () {
      painter.dispatch(stateMachine, up(PointerDeviceKind.touch));
      expect(stateMachine.calls, ['up', 'exit']);
    });

    test('stylus up dispatches up then exit', () {
      painter.dispatch(stateMachine, up(PointerDeviceKind.stylus));
      expect(stateMachine.calls, ['up', 'exit']);
    });

    test('inverted stylus up dispatches up then exit', () {
      painter.dispatch(stateMachine, up(PointerDeviceKind.invertedStylus));
      expect(stateMachine.calls, ['up', 'exit']);
    });

    test('touch cancel dispatches up then exit', () {
      painter.dispatch(stateMachine, cancel(PointerDeviceKind.touch));
      expect(stateMachine.calls, ['up', 'exit']);
    });
  });

  group('pointer up does not exit for hovering devices', () {
    test('mouse up dispatches up only', () {
      painter.dispatch(stateMachine, up(PointerDeviceKind.mouse));
      expect(stateMachine.calls, ['up']);
    });

    test('mouse cancel dispatches up only', () {
      painter.dispatch(stateMachine, cancel(PointerDeviceKind.mouse));
      expect(stateMachine.calls, ['up']);
    });
  });

  group('other pointer events map unchanged', () {
    test('down dispatches down', () {
      painter.dispatch(
        stateMachine,
        const PointerDownEvent(kind: PointerDeviceKind.touch),
      );
      expect(stateMachine.calls, ['down']);
    });

    test('move dispatches move', () {
      painter.dispatch(stateMachine, const PointerMoveEvent());
      expect(stateMachine.calls, ['move']);
    });

    test('hover dispatches move', () {
      painter.dispatch(stateMachine, const PointerHoverEvent());
      expect(stateMachine.calls, ['move']);
    });

    test('exit event dispatches exit', () {
      painter.dispatch(stateMachine, const PointerExitEvent());
      expect(stateMachine.calls, ['exit']);
    });
  });
}
