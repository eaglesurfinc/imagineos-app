import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_raster_selection.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';
import 'package:imagineos/features/drawing/drawing_selection.dart';
import 'package:imagineos/features/drawing/drawing_shapes.dart';

DrawingStroke square(double x, double y,
        {int color = 0xffe4475d, double side = 40}) =>
    DrawingStroke(
        tool: DrawingTool.rectangle,
        points: [DrawingPoint(x, y), DrawingPoint(x + side, y + side)],
        color: color,
        width: 2,
        opacity: 1,
        filled: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tap finds the top item and area selects whole intersecting items', () {
    final items = [square(10, 10), square(30, 30), square(140, 140)];
    expect(hitDrawingItem(items, const Offset(40, 40)), 1);
    expect(hitDrawingItem(items, const Offset(15, 15)), 0);
    expect(hitDrawingItem(items, const Offset(110, 110)), isNull);
    expect(
        drawingItemsInArea(
            items,
            selectionRectangle(
                const DrawingPoint(5, 5), const DrawingPoint(35, 35))),
        {0, 1});
    final diagonal = DrawingStroke(
        tool: DrawingTool.pen,
        points: const [DrawingPoint(0, 0), DrawingPoint(100, 100)],
        color: 0xff000000,
        width: 2,
        opacity: 1);
    expect(
        drawingItemsInArea(
            [diagonal],
            selectionRectangle(
                const DrawingPoint(10, 70), const DrawingPoint(30, 90))),
        isEmpty);
    expect(hitDrawingItem([diagonal], const Offset(55, 55)), 0);
  });

  test('lasso and clipped-item hit tests honor the painted region', () {
    final clipped = DrawingStroke(
        tool: DrawingTool.rectangle,
        points: const [DrawingPoint(10, 10), DrawingPoint(100, 100)],
        color: 0xff000000,
        width: 2,
        opacity: 1,
        filled: true,
        selection: selectionRectangle(
            const DrawingPoint(10, 10), const DrawingPoint(30, 100)));
    expect(hitDrawingItem([clipped], const Offset(20, 30)), 0);
    expect(hitDrawingItem([clipped], const Offset(50, 30)), isNull);
    expect(
        drawingItemsInArea([
          square(60, 60)
        ], const [
          DrawingPoint(0, 0),
          DrawingPoint(100, 0),
          DrawingPoint(0, 100)
        ]),
        isEmpty);
  });

  test(
      'uniform group transforms preserve exact source data and recover placement',
      () {
    const text = DrawingStroke(
        tool: DrawingTool.text,
        points: [DrawingPoint(50, 10)],
        color: 0xff3e80d6,
        width: 10,
        opacity: 1,
        text: '  My moon!\n  Stay.  ',
        textWidth: 100,
        fontSize: 16);
    final frame =
        DrawingFrame(strokes: [square(10, 10), text, square(150, 150)]);
    final selected = {0, 1},
        bounds = drawingSelectionBounds(frame.strokes, selected)!;
    final moved = transformDrawingItems(
        frame, selected, bounds, const Size(256, 256),
        factor: 1.4, delta: const Offset(30, 30));
    final originalPoints = frame.strokes[0].points;
    expect(moved.strokes[0].points, same(originalPoints));
    expect(moved.strokes[1].text, text.text);
    expect(moved.strokes[1].fontSize, text.fontSize);
    expect(moved.strokes[1].placement.scale, 1.4);
    expect(moved.strokes[2], same(frame.strokes[2]));
    final doc = DrawingDocument(width: 256, height: 256, frame: frame)
      ..commit(moved);
    final restored = DrawingDocument.decode(doc.encode());
    expect(restored.frame.strokes[1].placement.toJson(),
        moved.strokes[1].placement.toJson());
    expect(restored.frame.strokes[1].text, text.text);
    doc.undo();
    expect(doc.frame, same(frame));
    doc.redo();
    expect(doc.frame, same(moved));
    final huge = transformDrawingItems(moved, selected,
        drawingSelectionBounds(moved.strokes, selected)!, const Size(256, 256),
        factor: 1000, delta: const Offset(-999, 999));
    final actual = drawingSelectionBounds(huge.strokes, selected)!;
    expect(actual.left, greaterThanOrEqualTo(-.001));
    expect(actual.top, greaterThanOrEqualTo(-.001));
    expect(actual.right, lessThanOrEqualTo(256.001));
    expect(actual.bottom, lessThanOrEqualTo(256.001));
  });

  test('layer moves preserve selected and unselected relative order', () {
    final items = [for (var i = 0; i < 6; i++) square(10.0 * i, 10)];
    final frame = DrawingFrame(strokes: items);
    List<int> order(DrawingLayerOrder action) =>
        reorderDrawingItems(frame, {1, 2, 4}, action)
            .frame
            .strokes
            .map(items.indexOf)
            .toList();
    expect(order(DrawingLayerOrder.forward), [0, 3, 1, 2, 5, 4]);
    expect(order(DrawingLayerOrder.backward), [1, 2, 0, 4, 3, 5]);
    expect(order(DrawingLayerOrder.front), [0, 3, 5, 1, 2, 4]);
    expect(order(DrawingLayerOrder.back), [1, 2, 4, 0, 3, 5]);
    final reordered =
        reorderDrawingItems(frame, {1, 2, 4}, DrawingLayerOrder.front);
    expect(reordered.selected, {3, 4, 5});
    expect(frame.strokes, items);
  });

  test('raster selection cuts only its region and retains every source pixel',
      () {
    final source = image.Image(width: 64, height: 64, numChannels: 4);
    image.fill(source, color: image.ColorRgba8(200, 40, 70, 255));
    final bytes = image.encodePng(source), before = Uint8List.fromList(bytes);
    final split = selectDrawingRaster(DrawingRasterSelectionRequest(
        bytes,
        selectionRectangle(
            const DrawingPoint(10, 10), const DrawingPoint(30, 50))))!;
    expect(bytes, before);
    final rest = image.decodePng(split.remaining)!,
        cut = image.decodePng(split.item.image!)!;
    expect(rest.getPixel(15, 15).a, 0);
    expect(rest.getPixel(40, 15).a, 255);
    expect([cut.width, cut.height], [20, 40]);
    expect(cut.every((p) => p.r == 200 && p.g == 40 && p.b == 70 && p.a == 255),
        true);
    expect(
        selectDrawingRaster(DrawingRasterSelectionRequest(
            split.remaining, const [],
            tap: const Offset(15, 15))),
        isNull);
    final doc = DrawingDocument(
        width: 64,
        height: 64,
        frame: DrawingFrame(base: split.remaining, strokes: [split.item]));
    final restored = DrawingDocument.decode(doc.encode());
    expect(restored.frame.strokes.single.image, split.item.image);
  });

  testWidgets(
      'export paints transformed cutouts, selected text and layer order',
      (tester) async {
    final source = image.Image(width: 64, height: 64, numChannels: 4);
    image.fillRect(source,
        x1: 10,
        y1: 10,
        x2: 19,
        y2: 19,
        color: image.ColorRgba8(200, 40, 70, 255));
    final split = selectDrawingRaster(
        DrawingRasterSelectionRequest(image.encodePng(source), const []))!;
    final frame = DrawingFrame(
        strokes: [split.item, square(10, 10, color: 0xff3e80d6, side: 10)]);
    Future<image.Image> render(DrawingFrame f) async {
      final bytes = await tester.runAsync(() => exportDrawing(
          DrawingDocument(width: 64, height: 64, frame: f), null));
      return image.decodePng(bytes!)!;
    }

    expect((await render(frame)).getPixel(15, 15).b, 214);
    final reordered = reorderDrawingItems(frame, {0}, DrawingLayerOrder.front);
    expect((await render(reordered.frame)).getPixel(15, 15).r, 200);
    final moved = transformDrawingItems(DrawingFrame(strokes: [split.item]),
        {0}, drawingItemBounds(split.item), const Size(64, 64),
        factor: 2, delta: const Offset(25, 25));
    final output = await render(moved);
    expect(output.getPixel(15, 15).a, 0);
    expect(output.getPixel(40, 40).r, 200);
    expect(output.getPixel(48, 48).a, 255);
  });
}
