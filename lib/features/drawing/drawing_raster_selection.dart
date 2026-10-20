import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as image;

import 'drawing_document.dart';
import 'drawing_masks.dart';

class DrawingRasterSelection {
  const DrawingRasterSelection(this.remaining, this.item);
  final Uint8List remaining;
  final DrawingStroke item;
}

class DrawingRasterSelectionRequest {
  const DrawingRasterSelectionRequest(this.bytes, this.polygon, {this.tap});
  final Uint8List bytes;
  final List<DrawingPoint> polygon;
  final Offset? tap;
}

/// Lift only selected, nontransparent source pixels; the original bytes are
/// never changed. Selection itself does not commit this split to the document.
DrawingRasterSelection? selectDrawingRaster(
    DrawingRasterSelectionRequest request) {
  final source = image.decodePng(request.bytes)?.convert(numChannels: 4);
  if (source == null)
    throw const FormatException('Could not select this artwork.');
  final tap = request.tap;
  if (tap != null &&
      (tap.dx < 0 ||
          tap.dy < 0 ||
          tap.dx >= source.width ||
          tap.dy >= source.height ||
          source.getPixel(tap.dx.floor(), tap.dy.floor()).a == 0)) return null;
  final mask = request.polygon.length >= 3
      ? polygonMask(source.width, source.height,
          request.polygon.map((p) => [p.x, p.y]).toList())
      : null;
  var left = source.width, top = source.height, right = -1, bottom = -1;
  for (final p in source) {
    if (p.a == 0 || (mask != null && mask[p.y * source.width + p.x] == 0))
      continue;
    if (p.x < left) left = p.x;
    if (p.x > right) right = p.x;
    if (p.y < top) top = p.y;
    if (p.y > bottom) bottom = p.y;
  }
  if (right < left) return null;
  final cut = image.Image(
      width: right - left + 1, height: bottom - top + 1, numChannels: 4);
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      if (mask != null && mask[y * source.width + x] == 0) continue;
      final p = source.getPixel(x, y);
      cut.setPixelRgba(x - left, y - top, p.r, p.g, p.b, p.a);
      p.setRgba(0, 0, 0, 0);
    }
  }
  final remaining = image.encodePng(source), pixels = image.encodePng(cut);
  return DrawingRasterSelection(
      remaining,
      DrawingStroke(
          tool: DrawingTool.image,
          points: [
            DrawingPoint(left.toDouble(), top.toDouble()),
            DrawingPoint((right + 1).toDouble(), (bottom + 1).toDouble())
          ],
          color: 0,
          width: 1,
          opacity: 1,
          image: pixels));
}
