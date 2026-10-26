import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/layout_engine.dart';

// Expected values ported from the browser-generated fixtures in
// facebook/yoga #1901 (tests/generated/YGGridTest.cpp).
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  void expectLayout(LayoutNode node, double left, double top, double width,
      double height) {
    final layout = node.layout;
    expect(layout.left, closeTo(left, 0.01));
    expect(layout.top, closeTo(top, 0.01));
    expect(layout.width, closeTo(width, 0.01));
    expect(layout.height, closeTo(height, 0.01));
  }

  LayoutNode makeChild(LayoutNode parent, int index,
      {double? width, double? height}) {
    final child = LayoutNode.make();
    final style = LayoutStyle.make();
    if (width != null) {
      style.setDimension(
          LayoutDimension.width, LayoutValue(value: width, unit: LayoutUnit.point));
    }
    if (height != null) {
      style.setDimension(LayoutDimension.height,
          LayoutValue(value: height, unit: LayoutUnit.point));
    }
    child.setStyle(style);
    parent.insertChild(child, index);
    return child;
  }

  test('grid with fixed template sizes container and places items', () {
    final root = LayoutNode.make();
    final style = LayoutStyle.make();
    style.display = LayoutDisplay.grid;
    style.positionType = LayoutPosition.absolute;
    style.setGridTracks(LayoutGridCollection.templateColumns, const [
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
    ]);
    style.setGridTracks(LayoutGridCollection.templateRows, const [
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
    ]);
    root.setStyle(style);

    final a = makeChild(root, 0);
    final b = makeChild(root, 1);
    final c = makeChild(root, 2);
    final d = makeChild(root, 3);

    root.calculateLayout(double.nan, double.nan, LayoutDirection.ltr);

    // Container hugs the explicit grid: 3x100 wide, 2x100 tall.
    expectLayout(root, 0, 0, 300, 200);
    // Row-major auto placement, items stretch to their cells.
    expectLayout(a, 0, 0, 100, 100);
    expectLayout(b, 100, 0, 100, 100);
    expectLayout(c, 200, 0, 100, 100);
    expectLayout(d, 0, 100, 100, 100);
  });

  test('fr tracks distribute free space after fixed tracks and gaps', () {
    final root = LayoutNode.make();
    final style = LayoutStyle.make();
    style.display = LayoutDisplay.grid;
    style.setDimension(LayoutDimension.width,
        const LayoutValue(value: 320, unit: LayoutUnit.point));
    style.setDimension(LayoutDimension.height,
        const LayoutValue(value: 100, unit: LayoutUnit.point));
    style.setGap(LayoutGutter.column,
        const LayoutValue(value: 10, unit: LayoutUnit.point));
    style.setGridTracks(LayoutGridCollection.templateColumns, const [
      LayoutGridTrack.points(100),
      LayoutGridTrack.fr(1),
      LayoutGridTrack.fr(2),
    ]);
    style.setGridTracks(LayoutGridCollection.templateRows, const [
      LayoutGridTrack.fr(1),
    ]);
    root.setStyle(style);

    final a = makeChild(root, 0);
    final b = makeChild(root, 1);
    final c = makeChild(root, 2);

    root.calculateLayout(double.nan, double.nan, LayoutDirection.ltr);

    // Free space: 320 - 100 - 2*10 = 200 -> 1fr = 66.67, 2fr = 133.33.
    expectLayout(a, 0, 0, 100, 100);
    expectLayout(b, 110, 0, 200 / 3, 100);
    expectLayout(c, 110 + 200 / 3 + 10, 0, 400 / 3, 100);
  });

  test('explicit placement with spans', () {
    final root = LayoutNode.make();
    final style = LayoutStyle.make();
    style.display = LayoutDisplay.grid;
    style.positionType = LayoutPosition.absolute;
    style.setGridTracks(LayoutGridCollection.templateColumns, const [
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
    ]);
    style.setGridTracks(LayoutGridCollection.templateRows, const [
      LayoutGridTrack.points(100),
      LayoutGridTrack.points(100),
    ]);
    root.setStyle(style);

    // Item spanning columns 1-3 in row 1.
    final spanner = LayoutNode.make();
    final spannerStyle = LayoutStyle.make();
    spannerStyle.setGridLine(
        LayoutGridLinePosition.columnStart, const LayoutGridLine.at(1));
    spannerStyle.setGridLine(
        LayoutGridLinePosition.columnEnd, const LayoutGridLine.at(4));
    spanner.setStyle(spannerStyle);
    root.insertChild(spanner, 0);

    // Item placed at column 2, row 2.
    final placed = LayoutNode.make();
    final placedStyle = LayoutStyle.make();
    placedStyle.setGridLine(
        LayoutGridLinePosition.columnStart, const LayoutGridLine.at(2));
    placedStyle.setGridLine(
        LayoutGridLinePosition.rowStart, const LayoutGridLine.at(2));
    placed.setStyle(placedStyle);
    root.insertChild(placed, 1);

    root.calculateLayout(double.nan, double.nan, LayoutDirection.ltr);

    expectLayout(root, 0, 0, 300, 200);
    expectLayout(spanner, 0, 0, 300, 100);
    expectLayout(placed, 100, 100, 100, 100);
  });

  test('justify and align items position fixed-size cells content', () {
    final root = LayoutNode.make();
    final style = LayoutStyle.make();
    style.display = LayoutDisplay.grid;
    style.justifyItems = LayoutJustify.center;
    style.alignItems = LayoutAlign.center;
    style.setGridTracks(LayoutGridCollection.templateColumns,
        const [LayoutGridTrack.points(100)]);
    style.setGridTracks(LayoutGridCollection.templateRows,
        const [LayoutGridTrack.points(100)]);
    style.setDimension(LayoutDimension.width,
        const LayoutValue(value: 100, unit: LayoutUnit.point));
    style.setDimension(LayoutDimension.height,
        const LayoutValue(value: 100, unit: LayoutUnit.point));
    root.setStyle(style);

    final item = makeChild(root, 0, width: 40, height: 20);

    root.calculateLayout(double.nan, double.nan, LayoutDirection.ltr);

    expectLayout(item, 30, 40, 40, 20);
  });
}
