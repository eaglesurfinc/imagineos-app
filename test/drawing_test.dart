import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_pixels.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';

Uint8List paperDrawing() {
  final photo = image.Image(width: 32, height: 32, numChannels: 4);
  image.fill(photo, color: image.ColorRgba8(248, 247, 245, 255));
  image.fillRect(photo,
      x1: 6, y1: 6, x2: 25, y2: 25, color: image.ColorRgba8(0, 0, 0, 255));
  image.fillRect(photo,
      x1: 7, y1: 7, x2: 24, y2: 24, color: image.ColorRgba8(225, 35, 75, 255));
  image.fillRect(photo,
      x1: 13,
      y1: 13,
      x2: 18,
      y2: 18,
      color: image.ColorRgba8(248, 247, 245, 255));
  return image.encodePng(photo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'paper extraction preserves ink/color, removes interior paper, and never mutates source',
      () {
    final source = paperDrawing(), before = Uint8List.fromList(paperDrawing());
    final result = processDrawingPixels(RasterRequest(source,
        operation: DrawingPixelOperation.paper, tolerance: 30));
    final cut = image.decodePng(result.bytes)!;
    expect(cut.getPixel(0, 0).a, 0);
    expect(cut.getPixel(15, 15).a, 0);
    expect(cut.getPixel(6, 6).r, 0);
    expect(cut.getPixel(6, 6).a, 255);
    expect(cut.getPixel(8, 8).r, 225);
    expect(cut.getPixel(8, 8).a, 255);
    expect(source, before);
  });
  test(
      'busy-background outline preserves selected pixels and removes surroundings',
      () {
    final source = paperDrawing();
    final result = processDrawingPixels(RasterRequest(source,
        operation: DrawingPixelOperation.cutout,
        polygon: const [
          [6, 6],
          [26, 6],
          [26, 26],
          [6, 26]
        ]));
    final cut = image.decodePng(result.bytes)!;
    expect(cut.getPixel(0, 0).a, 0);
    expect(cut.getPixel(8, 8).r, 225);
    expect(cut.getPixel(15, 15).a,
        255); // Only the outline decides; no semantic guess.
  });
  test('tap removal is connected and fill respects a closed outline', () {
    final source = paperDrawing();
    final removed = processDrawingPixels(RasterRequest(source,
        operation: DrawingPixelOperation.remove, x: 0, y: 0, tolerance: 20));
    var decoded = image.decodePng(removed.bytes)!;
    expect(decoded.getPixel(0, 0).a, 0);
    expect(decoded.getPixel(15, 15).a, 255);
    final filled = processDrawingPixels(RasterRequest(removed.bytes,
        operation: DrawingPixelOperation.fill,
        x: 15,
        y: 15,
        color: 0xff245ce8,
        tolerance: 10));
    decoded = image.decodePng(filled.bytes)!;
    expect(decoded.getPixel(15, 15).b, 232);
    expect(decoded.getPixel(0, 0).a, 0);
    expect(decoded.getPixel(8, 8).r, 225);
  });
  test(
      'eraser cuts imported artwork to alpha; paper is an independent background',
      () async {
    final source = paperDrawing();
    final base = await decodeDrawingBase(source);
    final doc = DrawingDocument(
        width: 32,
        height: 32,
        frame: DrawingFrame(base: source, strokes: const [
          DrawingStroke(
              tool: DrawingTool.eraser,
              points: [DrawingPoint(16, 0), DrawingPoint(16, 32)],
              color: 0xff000000,
              width: 8,
              opacity: 1),
        ]));
    try {
      var png = image.decodePng(await exportDrawing(doc, base))!;
      expect(png.getPixel(16, 8).a, 0);
      expect(png.getPixel(8, 8).r, 225);
      doc.commit(doc.frame.copyWith(background: 0xffffffff));
      png = image.decodePng(await exportDrawing(doc, base))!;
      expect(png.getPixel(16, 8).a, 255);
      expect(png.getPixel(16, 8).r, 255);
      doc.undo();
      expect(doc.frame.background, 0);
      doc.redo();
      expect(doc.frame.background, 0xffffffff);
    } finally {
      base?.dispose();
    }
  });
  test(
      'drawing draft restores editable strokes and a new action replaces redo branch',
      () {
    final doc = DrawingDocument();
    const stroke = DrawingStroke(
        tool: DrawingTool.pen,
        points: [DrawingPoint(10, 10), DrawingPoint(40, 40)],
        color: 0xffe4475d,
        width: 12,
        opacity: .8);
    doc.commit(doc.frame.copyWith(strokes: [stroke]));
    final restored = DrawingDocument.decode(doc.encode());
    expect(restored.frame.strokes.single.color, stroke.color);
    expect(restored.frame.strokes.single.points.last.x, 40);
    doc.undo();
    expect(doc.canRedo, isTrue);
    doc.commit(const DrawingFrame(background: 0xffffffff));
    expect(doc.canRedo, isFalse);
  });
}
