import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_pixels.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';
import 'package:imagineos/features/drawing/drawing_shapes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'large colored artwork is preserved at every pixel including tile-edge slivers',
      () {
    final photo = image.Image(width: 256, height: 256, numChannels: 4);
    for (final p in photo) {
      final shade = (20 * p.x / 255 + 12 * p.y / 255).round();
      final noise = ((p.x * 17 + p.y * 31) % 13) - 6;
      final d = math.pow((p.x - 128) / 73, 2) + math.pow((p.y - 128) / 87, 2);
      if (d < 1) {
        p.setRgba(225, 35, 75, 255);
      } else {
        p.setRgba(
            235 - shade + noise, 225 - shade + noise, 203 - shade + noise, 255);
      }
    }
    final source = image.encodePng(photo);
    for (final strength in [0.0, 30.0, 100.0]) {
      final cut = image.decodePng(processDrawingPixels(RasterRequest(source,
              operation: DrawingPixelOperation.paper, tolerance: strength))
          .bytes)!;
      for (final p in photo.where((p) => p.g == 35)) {
        final actual = cut.getPixel(p.x, p.y);
        expect([actual.r, actual.g, actual.b, actual.a], [225, 35, 75, 255],
            reason: 'artwork at ${p.x},${p.y}, strength $strength');
      }
    }
  });
  test(
      'photographed warm paper clears despite noise, JPEG compression and shadows',
      () {
    final photo = image.Image(width: 256, height: 192, numChannels: 4);
    final random = math.Random(51);
    for (final p in photo) {
      final shade = (24 * p.x / 255 + 9 * p.y / 191).round();
      final noise = random.nextInt(13) - 6;
      final ink = p.y >= 88 && p.y <= 90 && p.x >= 20 && p.x <= 235 ? 36 : 0;
      p.setRgba(235 - shade + noise - ink, 225 - shade + noise - ink,
          203 - shade + noise - ink, 255);
    }
    final bytes = image.encodeJpg(photo, quality: 78);
    final before = Uint8List.fromList(bytes);
    final cut = image.decodePng(processDrawingPixels(
            RasterRequest(bytes, operation: DrawingPixelOperation.paper))
        .bytes)!;
    var empty = 0, cleared = 0, lines = 0, kept = 0;
    for (final p in cut) {
      if (p.y < 70 || p.y > 110) {
        empty++;
        if (p.a < 16) cleared++;
      }
      if (p.y == 89 && p.x > 35 && p.x < 220) {
        lines++;
        if (p.a == 255) kept++;
      }
    }
    expect(cleared / empty, greaterThan(.95),
        reason: 'most empty photographed page must actually disappear');
    expect(kept / lines, greaterThan(.95),
        reason: 'pencil line must remain opaque');
    expect(bytes, before);
  });
  test('dim warm page is extracted instead of silently returning unchanged',
      () {
    final photo = image.Image(width: 64, height: 64, numChannels: 4);
    image.fill(photo, color: image.ColorRgba8(182, 174, 151, 255));
    image.drawLine(photo,
        x1: 8,
        y1: 32,
        x2: 55,
        y2: 32,
        color: image.ColorRgba8(108, 100, 77, 255));
    final cut = image.decodePng(processDrawingPixels(RasterRequest(
            image.encodePng(photo),
            operation: DrawingPixelOperation.paper))
        .bytes)!;
    expect(cut.getPixel(10, 10).a, 0);
    expect(cut.getPixel(30, 32).a, 255);
  });
  test(
      'paper cleanup follows gradual page lighting and preserves a crossing pencil line',
      () {
    final photo = image.Image(width: 96, height: 96, numChannels: 4);
    for (final p in photo) {
      final page = 248 - p.x ~/ 12;
      final value = p.y == 48 ? page - 12 : page;
      p.setRgba(value, value, value, 255);
    }
    final png = image.decodePng(processDrawingPixels(RasterRequest(
            image.encodePng(photo),
            operation: DrawingPixelOperation.paper))
        .bytes)!;
    for (final x in [12, 36, 60, 84]) {
      expect(png.getPixel(x, 12).a, 0, reason: 'empty page at $x');
      expect(png.getPixel(x, 48).a, 255, reason: 'pencil at $x');
    }
  });
  test(
      'paper cleanup keeps faint graphite, pale colors and thin edges across strengths',
      () {
    final photo = image.Image(width: 96, height: 96, numChannels: 4);
    image.fill(photo, color: image.ColorRgba8(248, 247, 245, 255));
    image.drawLine(photo,
        x1: 12,
        y1: 20,
        x2: 80,
        y2: 20,
        color: image.ColorRgba8(235, 234, 232, 255));
    image.drawLine(photo,
        x1: 12,
        y1: 21,
        x2: 80,
        y2: 21,
        color: image.ColorRgba8(241, 240, 238, 255));
    image.fillRect(photo,
        x1: 25,
        y1: 40,
        x2: 65,
        y2: 65,
        color: image.ColorRgba8(245, 230, 239, 255));
    final source = image.encodePng(photo), copy = Uint8List.fromList(source);
    for (final strength in [0.0, 30.0, 100.0]) {
      final png = image.decodePng(processDrawingPixels(RasterRequest(source,
              operation: DrawingPixelOperation.paper, tolerance: strength))
          .bytes)!;
      expect(png.getPixel(2, 2).a, 0);
      expect(png.getPixel(40, 20).a, 255,
          reason: 'faint graphite at strength $strength');
      expect(png.getPixel(40, 21).a, 255,
          reason: 'thin edge at strength $strength');
      expect(png.getPixel(40, 50).a, 255);
      expect(png.getPixel(40, 20).r, 235);
    }
    expect(source, copy);
  });
  test(
      'edge protection and tiny-gap bridging prevent removal from leaking through faint outlines',
      () {
    final photo = image.Image(width: 40, height: 40, numChannels: 4);
    image.fill(photo, color: image.ColorRgba8(248, 248, 248, 255));
    image.drawRect(photo,
        x1: 8,
        y1: 8,
        x2: 31,
        y2: 31,
        color: image.ColorRgba8(233, 233, 233, 255));
    photo.setPixelRgba(8, 19, 248, 248, 248, 255); // one-pixel break
    final source = image.encodePng(photo);
    final guarded = image.decodePng(processDrawingPixels(RasterRequest(source,
            operation: DrawingPixelOperation.remove, x: 2, y: 2, tolerance: 40))
        .bytes)!;
    expect(guarded.getPixel(2, 2).a, 0);
    expect(guarded.getPixel(8, 15).a, 255);
    expect(guarded.getPixel(20, 20).a, 255);
    final unguarded = image.decodePng(processDrawingPixels(RasterRequest(source,
            operation: DrawingPixelOperation.remove,
            x: 2,
            y: 2,
            tolerance: 40,
            protectEdges: false))
        .bytes)!;
    expect(unguarded.getPixel(20, 20).a, 0);
  });
  test(
      'selection constrains removal, paper and fill, and rejects a seed outside it',
      () {
    final photo = image.Image(width: 24, height: 24, numChannels: 4);
    image.fill(photo, color: image.ColorRgba8(248, 248, 248, 255));
    final source = image.encodePng(photo);
    const selection = [
      [4.0, 4.0],
      [12.0, 4.0],
      [12.0, 20.0],
      [4.0, 20.0]
    ];
    for (final operation in [
      DrawingPixelOperation.remove,
      DrawingPixelOperation.paper,
      DrawingPixelOperation.clearSelection,
      DrawingPixelOperation.fill
    ]) {
      final png = image.decodePng(processDrawingPixels(RasterRequest(source,
              operation: operation,
              selection: selection,
              x: 6,
              y: 8,
              color: 0xff00aa88))
          .bytes)!;
      expect(png.getPixel(2, 8).a, 255);
      expect(png.getPixel(16, 8).r, 248);
      if (operation == DrawingPixelOperation.fill) {
        expect(png.getPixel(6, 8).r, 0);
      } else {
        expect(png.getPixel(6, 8).a, 0);
      }
    }
    expect(
        () => processDrawingPixels(RasterRequest(source,
            operation: DrawingPixelOperation.remove,
            selection: selection,
            x: 0,
            y: 0)),
        throwsFormatException);
  });
  test(
      'selected strokes clip on export and preserve that boundary after draft reload',
      () async {
    const stroke = DrawingStroke(
        tool: DrawingTool.pen,
        points: [DrawingPoint(0, 16), DrawingPoint(32, 16)],
        color: 0xffee2244,
        width: 6,
        opacity: 1,
        selection: [
          DrawingPoint(8, 0),
          DrawingPoint(24, 0),
          DrawingPoint(24, 32),
          DrawingPoint(8, 32)
        ]);
    final doc = DrawingDocument(
        width: 32, height: 32, frame: const DrawingFrame(strokes: [stroke]));
    final restored = DrawingDocument.decode(doc.encode());
    final png = image.decodePng(await exportDrawing(restored, null))!;
    expect(png.getPixel(16, 16).a, 255);
    expect(png.getPixel(4, 16).a, 0);
    expect(png.getPixel(28, 16).a, 0);
  });
  test(
      'all added shapes render filled and outline pixels and remain editable in drafts',
      () async {
    for (final tool in [
      DrawingTool.square,
      DrawingTool.circle,
      DrawingTool.triangle,
      DrawingTool.diamond,
      DrawingTool.pentagon,
      DrawingTool.hexagon,
      DrawingTool.star,
      DrawingTool.heart,
      DrawingTool.arrow
    ]) {
      final doc = DrawingDocument(
          width: 64,
          height: 64,
          frame: DrawingFrame(strokes: [
            DrawingStroke(
                tool: tool,
                points: const [DrawingPoint(8, 8), DrawingPoint(56, 56)],
                color: 0xff009988,
                width: 2,
                opacity: 1,
                filled: true)
          ]));
      final restored = DrawingDocument.decode(doc.encode());
      var png = image.decodePng(await exportDrawing(restored, null))!;
      final filledPixels = png.where((p) => p.a > 0).length;
      expect(filledPixels, greaterThan(50), reason: tool.name);
      expect(png.getPixel(0, 0).a, 0);
      expect(restored.frame.strokes.single.tool, tool);
      final outline = DrawingDocument(
          width: 64,
          height: 64,
          frame: DrawingFrame(strokes: [
            DrawingStroke(
                tool: tool,
                points: const [DrawingPoint(8, 8), DrawingPoint(56, 56)],
                color: 0xff009988,
                width: 2,
                opacity: 1)
          ]));
      png = image.decodePng(await exportDrawing(outline, null))!;
      expect(png.where((p) => p.a > 0).length, greaterThan(20));
    }
    expect(
        drawingShape(DrawingTool.circle, const DrawingPoint(0, 0).offset,
                const DrawingPoint(80, 40).offset)
            .getBounds()
            .size
            .aspectRatio,
        1);
  });
}
