import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

enum DrawingPixelOperation {
  prepare,
  paper,
  fill,
  remove,
  cutout,
  pick;

  bool get extractsArtwork => this == paper || this == remove || this == cutout;
}

class RasterRequest {
  const RasterRequest(this.bytes,
      {this.operation = DrawingPixelOperation.prepare,
      this.tolerance = 28,
      this.x = 0,
      this.y = 0,
      this.color = 0xff000000,
      this.polygon = const []});
  final Uint8List bytes;
  final DrawingPixelOperation operation;
  final double tolerance;
  final int x, y, color;
  final List<List<double>> polygon;
}

class RasterResult {
  const RasterResult(this.bytes, this.width, this.height, {this.color});
  final Uint8List bytes;
  final int width, height;
  final int? color;
}

RasterResult processDrawingPixels(RasterRequest request) {
  final decoder = image.findDecoderForData(request.bytes);
  final info = decoder?.startDecode(request.bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width > 8192 ||
      info.height > 8192 ||
      info.width * info.height > 16000000)
    throw const FormatException('Choose an image up to 16 megapixels.');
  final decoded = image.decodeImage(request.bytes, frame: 0);
  if (decoded == null)
    throw const FormatException('This image could not be opened.');
  var source = image.bakeOrientation(decoded).convert(numChannels: 4);
  if (request.operation == DrawingPixelOperation.prepare) {
    if (source.width > 1536 || source.height > 1536) {
      final scale = 1536 / math.max(source.width, source.height);
      source = image.copyResize(source,
          width: (source.width * scale).round(),
          height: (source.height * scale).round());
    }
  } else if (request.operation == DrawingPixelOperation.paper) {
    // Remove near-neutral light paper, including holes inside closed outlines.
    // Preview is mandatory: light artwork may also be affected.
    final minimum = 255 - request.tolerance.clamp(0, 160);
    for (final pixel in source) {
      final light = math.min(pixel.r, math.min(pixel.g, pixel.b));
      final chroma = math.max(pixel.r, math.max(pixel.g, pixel.b)) - light;
      if (light >= minimum && chroma <= request.tolerance * .65) pixel.a = 0;
    }
  } else if (request.operation == DrawingPixelOperation.fill ||
      request.operation == DrawingPixelOperation.remove) {
    final x = request.x.clamp(0, source.width - 1),
        y = request.y.clamp(0, source.height - 1);
    final seed = source.getPixel(x, y);
    final sr = seed.r.toDouble(),
        sg = seed.g.toDouble(),
        sb = seed.b.toDouble(),
        sa = seed.a.toDouble();
    final queue = Int32List(source.width * source.height);
    final seen = Uint8List(queue.length);
    var head = 0, tail = 1;
    queue[0] = y * source.width + x;
    seen[queue[0]] = 1;
    void enqueue(int next) {
      if (seen[next] == 0) {
        seen[next] = 1;
        queue[tail++] = next;
      }
    }

    while (head < tail) {
      final index = queue[head++],
          px = index % source.width,
          py = index ~/ source.width;
      final p = source.getPixel(px, py);
      final matches = sa == 0
          ? p.a == 0
          : p.a > 0 &&
              math.max((p.r - sr).abs(),
                      math.max((p.g - sg).abs(), (p.b - sb).abs())) <=
                  request.tolerance;
      if (!matches) continue;
      if (request.operation == DrawingPixelOperation.remove)
        p.a = 0;
      else
        source.setPixelRgba(
            px,
            py,
            (request.color >> 16) & 255,
            (request.color >> 8) & 255,
            request.color & 255,
            (request.color >> 24) & 255);
      if (px > 0) enqueue(index - 1);
      if (px + 1 < source.width) enqueue(index + 1);
      if (py > 0) enqueue(index - source.width);
      if (py + 1 < source.height) enqueue(index + source.width);
    }
  } else if (request.operation == DrawingPixelOperation.cutout) {
    if (request.polygon.length < 3)
      throw const FormatException(
          'Outline the whole drawing, then release to close the selection.');
    // Scanline polygon mask preserves every selected source pixel and its alpha.
    for (var y = 0; y < source.height; y++) {
      final intersections = <double>[];
      final scan = y + .5;
      for (var i = 0, j = request.polygon.length - 1;
          i < request.polygon.length;
          j = i++) {
        final a = request.polygon[j], b = request.polygon[i];
        if ((a[1] > scan) != (b[1] > scan))
          intersections
              .add(a[0] + (scan - a[1]) * (b[0] - a[0]) / (b[1] - a[1]));
      }
      intersections.sort();
      var interval = 0;
      for (var x = 0; x < source.width; x++) {
        while (interval < intersections.length &&
            x + .5 >= intersections[interval]) interval++;
        if (interval.isEven) source.getPixel(x, y).a = 0;
      }
    }
  } else if (request.operation == DrawingPixelOperation.pick) {
    final p = source.getPixel(request.x.clamp(0, source.width - 1),
        request.y.clamp(0, source.height - 1));
    return RasterResult(request.bytes, source.width, source.height,
        color: (p.a.toInt() << 24) |
            (p.r.toInt() << 16) |
            (p.g.toInt() << 8) |
            p.b.toInt());
  }
  final bytes = image.encodePng(source, level: 6);
  if (bytes.length > 5 * 1024 * 1024)
    throw const FormatException(
        'This drawing exceeds 5 MB. Crop the original first.');
  return RasterResult(bytes, source.width, source.height);
}
