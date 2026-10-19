import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

double _distance(image.Pixel a, image.Pixel b) => math
    .max((a.r - b.r).abs(), math.max((a.g - b.g).abs(), (a.b - b.b).abs()))
    .toDouble();

/// Four-connected, edge-limited growth. Read only from the original while
/// collecting the region, then change pixels, so growth never sees its own edits.
void editDrawingRegion(image.Image source,
    {required int x,
    required int y,
    required double tolerance,
    required bool remove,
    required int color,
    required bool protectEdges,
    required bool closeGaps,
    Uint8List? selection}) {
  x = x.clamp(0, source.width - 1);
  y = y.clamp(0, source.height - 1);
  final seed = source.getPixel(x, y);
  final start = y * source.width + x;
  if (selection != null && selection[start] == 0) {
    throw const FormatException('Tap inside the selected area.');
  }
  final queue = Int32List(source.width * source.height);
  final seen = Uint8List(queue.length), region = Uint8List(queue.length);
  var head = 0, tail = 1;
  queue[0] = start;
  seen[start] = 1;
  final edgeLimit = 5 + tolerance.clamp(0, 100) * .07;
  bool gap(int px, int py) {
    final p = source.getPixel(px, py);
    bool opposite(int ax, int ay, int bx, int by) {
      final a = source.getPixel(ax, ay), b = source.getPixel(bx, by);
      return a.a > 0 &&
          b.a > 0 &&
          _distance(p, a) > edgeLimit &&
          _distance(p, b) > edgeLimit &&
          _distance(a, b) < edgeLimit;
    }

    return (px > 0 &&
            px + 1 < source.width &&
            opposite(px - 1, py, px + 1, py)) ||
        (py > 0 && py + 1 < source.height && opposite(px, py - 1, px, py + 1));
  }

  void enqueue(int next, image.Pixel previous) {
    if (seen[next] != 0) return;
    // A region may reach the same pixel by another gradual-lighting path, so
    // mark seen only after the edge test has accepted it.
    if (selection != null && selection[next] == 0) return;
    final nx = next % source.width, ny = next ~/ source.width;
    final p = source.getPixel(nx, ny);
    if (protectEdges &&
        seed.a > 0 &&
        (_distance(previous, p) > edgeLimit || (closeGaps && gap(nx, ny))))
      return;
    seen[next] = 1;
    queue[tail++] = next;
  }

  while (head < tail) {
    final index = queue[head++],
        px = index % source.width,
        py = index ~/ source.width;
    final p = source.getPixel(px, py);
    if (seed.a == 0 ? p.a != 0 : p.a == 0 || _distance(p, seed) > tolerance)
      continue;
    region[index] = 1;
    if (px > 0) enqueue(index - 1, p);
    if (px + 1 < source.width) enqueue(index + 1, p);
    if (py > 0) enqueue(index - source.width, p);
    if (py + 1 < source.height) enqueue(index + source.width, p);
  }
  for (var i = 0; i < region.length; i++) {
    if (region[i] == 0) continue;
    final px = i % source.width, py = i ~/ source.width;
    if (remove) {
      source.getPixel(px, py).a = 0;
    } else {
      source.setPixelRgba(px, py, (color >> 16) & 255, (color >> 8) & 255,
          color & 255, (color >> 24) & 255);
    }
  }
}
