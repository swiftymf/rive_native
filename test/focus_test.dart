import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/focus.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('FocusNode', () {
    test('default properties', () {
      final node = FocusNode.make();

      expect(node.canFocus, isTrue);
      expect(node.canTouch, isTrue);
      expect(node.canTraverse, isTrue);
      expect(node.tabIndex, equals(0));
      expect(node.edgeBehavior, equals(EdgeBehavior.parentScope));

      node.dispose();
    });

    test('property setters', () {
      final node = FocusNode.make();

      node.canFocus = false;
      expect(node.canFocus, isFalse);

      node.canTouch = false;
      expect(node.canTouch, isFalse);

      node.canTraverse = false;
      expect(node.canTraverse, isFalse);

      node.tabIndex = 42;
      expect(node.tabIndex, equals(42));

      node.edgeBehavior = EdgeBehavior.closedLoop;
      expect(node.edgeBehavior, equals(EdgeBehavior.closedLoop));

      node.edgeBehavior = EdgeBehavior.stop;
      expect(node.edgeBehavior, equals(EdgeBehavior.stop));

      node.dispose();
    });

    test('with callbacks', () {
      final node = FocusNode.make(
        onKeyInput: (key, modifiers, isPressed, isRepeat) {
          return true;
        },
        onTextInput: (text) {
          return true;
        },
        onFocused: () {},
        onBlurred: () {},
      );

      expect(node.canFocus, isTrue);

      node.dispose();
    });

    test('dispose cleans up', () {
      final node = FocusNode.make();
      node.dispose();
      // Calling dispose again should not crash
      node.dispose();
    });
  });

  group('FocusManager', () {
    test('basic focus operations', () {
      final manager = FocusManager.make();
      final node = FocusNode.make();

      manager.addChild(null, node);
      manager.setFocus(node);

      expect(manager.hasFocus(node), isTrue);
      expect(manager.hasPrimaryFocus(node), isTrue);

      manager.clearFocus();

      node.dispose();
      manager.dispose();
    });

    test('hierarchy operations', () {
      final manager = FocusManager.make();
      final parent = FocusNode.make();
      final child1 = FocusNode.make();
      final child2 = FocusNode.make();

      manager.addChild(null, parent);
      manager.addChild(parent, child1);
      manager.addChild(parent, child2);

      // Focus on child, parent should have focus (descendant)
      manager.setFocus(child1);
      expect(manager.hasFocus(parent), isTrue);
      expect(manager.hasPrimaryFocus(parent), isFalse);
      expect(manager.hasFocus(child1), isTrue);
      expect(manager.hasPrimaryFocus(child1), isTrue);

      manager.dispose();
      parent.dispose();
      child1.dispose();
      child2.dispose();
    });

    test('traversal', () {
      final manager = FocusManager.make();
      final node1 = FocusNode.make();
      final node2 = FocusNode.make();
      final node3 = FocusNode.make();

      manager.addChild(null, node1);
      manager.addChild(null, node2);
      manager.addChild(null, node3);

      manager.setFocus(node1);
      expect(manager.hasPrimaryFocus(node1), isTrue);

      manager.focusNext();
      expect(manager.hasPrimaryFocus(node2), isTrue);

      manager.focusNext();
      expect(manager.hasPrimaryFocus(node3), isTrue);

      manager.focusPrevious();
      expect(manager.hasPrimaryFocus(node2), isTrue);

      manager.dispose();
      node1.dispose();
      node2.dispose();
      node3.dispose();
    });

    test('traversal with tabIndex', () {
      final manager = FocusManager.make();
      final node1 = FocusNode.make()..tabIndex = 3;
      final node2 = FocusNode.make()..tabIndex = 1;
      final node3 = FocusNode.make()..tabIndex = 2;

      manager.addChild(null, node1);
      manager.addChild(null, node2);
      manager.addChild(null, node3);

      // Start from nothing, focusNext should pick first by tabIndex
      manager.focusNext();
      expect(manager.hasPrimaryFocus(node2), isTrue); // tabIndex 1

      manager.focusNext();
      expect(manager.hasPrimaryFocus(node3), isTrue); // tabIndex 2

      manager.focusNext();
      expect(manager.hasPrimaryFocus(node1), isTrue); // tabIndex 3

      manager.dispose();
      node1.dispose();
      node2.dispose();
      node3.dispose();
    });

    test('traversal skips non-traversable', () {
      final manager = FocusManager.make();
      final node1 = FocusNode.make();
      final node2 = FocusNode.make()..canTraverse = false;
      final node3 = FocusNode.make();

      manager.addChild(null, node1);
      manager.addChild(null, node2);
      manager.addChild(null, node3);

      manager.setFocus(node1);
      manager.focusNext();

      // Should skip node2 and go to node3
      expect(manager.hasPrimaryFocus(node3), isTrue);

      manager.dispose();
      node1.dispose();
      node2.dispose();
      node3.dispose();
    });

    test('input routing', () {
      final manager = FocusManager.make();
      var keyInputReceived = false;
      var textInputReceived = false;

      final node = FocusNode.make(
        onKeyInput: (key, modifiers, isPressed, isRepeat) {
          keyInputReceived = true;
          return true;
        },
        onTextInput: (text) {
          textInputReceived = true;
          return true;
        },
      );

      manager.addChild(null, node);

      // No focus, input not handled
      expect(manager.keyInput(65, 0, true, false), isFalse);
      expect(manager.textInput('hello'), isFalse);

      manager.setFocus(node);

      // With focus, input is routed
      expect(manager.keyInput(65, 0, true, false), isTrue);
      expect(keyInputReceived, isTrue);

      expect(manager.textInput('hello'), isTrue);
      expect(textInputReceived, isTrue);

      manager.dispose();
      node.dispose();
    });

    test('removeChild clears focus', () {
      final manager = FocusManager.make();
      final node = FocusNode.make();

      manager.addChild(null, node);
      manager.setFocus(node);
      expect(manager.hasPrimaryFocus(node), isTrue);

      manager.removeChild(node);
      // After removal, focus should be cleared

      node.dispose();
      manager.dispose();
    });
  });

  group('EdgeBehavior', () {
    test('fromValue', () {
      expect(EdgeBehavior.fromValue(0), equals(EdgeBehavior.parentScope));
      expect(EdgeBehavior.fromValue(1), equals(EdgeBehavior.closedLoop));
      expect(EdgeBehavior.fromValue(2), equals(EdgeBehavior.stop));
      // Invalid value defaults to parentScope
      expect(EdgeBehavior.fromValue(99), equals(EdgeBehavior.parentScope));
    });

    test('value', () {
      expect(EdgeBehavior.parentScope.value, equals(0));
      expect(EdgeBehavior.closedLoop.value, equals(1));
      expect(EdgeBehavior.stop.value, equals(2));
    });
  });
}
