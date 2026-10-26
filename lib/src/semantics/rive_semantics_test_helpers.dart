import 'package:flutter/semantics.dart';
import 'package:meta/meta.dart';

/// Helpers for inspecting the Flutter [SemanticsNode] tree produced by Rive's
/// semantics overlay.
///
/// These are designed for use in widget tests where the Rive semantic nodes are
/// created manually inside a [RenderObject] (via `assembleSemanticsNode`) and
/// therefore cannot be found with [find.bySemanticsLabel].
///
/// Usage:
/// ```dart
/// import 'package:rive_native/src/semantics/rive_semantics_test_helpers.dart';
///
/// final root = tester.getSemantics(find.byType(RiveSemanticsOverlay));
/// final button = root.findByLabel('Submit');
/// expect(button, isNotNull);
/// expect(button!.flagsCollection.isButton, isTrue);
/// ```

// ─── Traversal ────────────────────────────────────────────────────────────────

/// Extension on [SemanticsNode] for tree queries useful in tests.
@experimental
@internal
extension RiveSemanticsNodeQueries on SemanticsNode {
  /// Find the first descendant (or self) whose [SemanticsNode.label] equals
  /// [label]. Returns `null` if no match is found.
  SemanticsNode? findByLabel(String label) {
    if (this.label == label) return this;
    SemanticsNode? result;
    visitChildren((child) {
      result ??= child.findByLabel(label);
      return result == null;
    });
    return result;
  }

  /// Find the first descendant (or self) whose [SemanticsNode.label] matches
  /// the given [pattern] (supports [RegExp] or plain [String]).
  SemanticsNode? findByLabelPattern(Pattern pattern) {
    if (pattern.allMatches(label).isNotEmpty) return this;
    SemanticsNode? result;
    visitChildren((child) {
      result ??= child.findByLabelPattern(pattern);
      return result == null;
    });
    return result;
  }

  /// Collect all descendants (and optionally self) that satisfy [predicate],
  /// returned in depth-first order.
  List<SemanticsNode> findAll(
    bool Function(SemanticsNode node) predicate, {
    bool includeSelf = true,
  }) {
    final results = <SemanticsNode>[];
    if (includeSelf && predicate(this)) results.add(this);
    visitChildren((child) {
      results.addAll(child.findAll(predicate));
      return true;
    });
    return results;
  }

  /// Collect all descendants (and self) whose label equals [label].
  List<SemanticsNode> findAllByLabel(String label) =>
      findAll((n) => n.label == label);

  /// Return the number of direct children of this node.
  int get childCount {
    int count = 0;
    visitChildren((_) {
      count++;
      return true;
    });
    return count;
  }

  /// Return the direct children as a list.
  List<SemanticsNode> get children {
    final list = <SemanticsNode>[];
    visitChildren((child) {
      list.add(child);
      return true;
    });
    return list;
  }

  /// Total number of nodes in the subtree rooted at this node (including self).
  int get subtreeCount {
    int count = 1;
    visitChildren((child) {
      count += child.subtreeCount;
      return true;
    });
    return count;
  }
}

// ─── Matchers ─────────────────────────────────────────────────────────────────

/// Returns `true` if the [SemanticsNode] has the `isButton` flag set.
bool isSemanticsButton(SemanticsNode node) => node.flagsCollection.isButton;

/// Returns `true` if the [SemanticsNode] has the `isSlider` flag set.
bool isSemanticsSlider(SemanticsNode node) => node.flagsCollection.isSlider;

/// Returns `true` if the [SemanticsNode] has the `isTextField` flag set.
bool isSemanticsTextField(SemanticsNode node) =>
    node.flagsCollection.isTextField;

/// Returns `true` if the [SemanticsNode] has the `isImage` flag set.
bool isSemanticsImage(SemanticsNode node) => node.flagsCollection.isImage;

/// Returns `true` if the [SemanticsNode] has the `isLink` flag set.
bool isSemanticsLink(SemanticsNode node) => node.flagsCollection.isLink;
