import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'drawing_masks.dart';
import 'drawing_regions.dart';
import 'paper_extraction.dart';

enum DrawingPixelOperation {
  prepare,
  paper,
  fill,
  remove,
  cutout,
  pick,
  clearSelection;

  bool get extractsArtwork => this == paper || this == remove || this == cutout;
}

class RasterRequest {
  const RasterRequest(this.bytes,
      {this.operation = DrawingPixelOperation.prepare,
      this.tolerance = 28,
      this.x = 0,
      this.y = 0,
      this.color = 0xff000000,
      this.polygon = const [],
      this.selection = const [],
      this.protectEdges = true,
      this.closeGaps = true});
  final Uint8List bytes;
  final DrawingPixelOperation operation;
  final double tolerance;
  final int x, y, color;
  final List<List<double>> polygon, selection;
  final bool protectEdges, closeGaps;
  RasterRequest withTolerance(double value, {bool? edges, bool? gaps}) =>
      RasterRequest(bytes,
          operation: operation,
          tolerance: value,
          x: x,
          y: y,
          color: color,
          polygon: polygon,
          selection: selection,
          protectEdges: edges ?? protectEdges,
          closeGaps: gaps ?? closeGaps);
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
  final selection = request.selection.length >= 3
      ? polygonMask(source.width, source.height, request.selection)
      : null;
  if (request.operation == DrawingPixelOperation.prepare) {
    if (source.width > 1536 || source.height > 1536) {
      final scale = 1536 / math.max(source.width, source.height);
      source = image.copyResize(source,
          width: (source.width * scale).round(),
          height: (source.height * scale).round());
    }
  } else if (request.operation == DrawingPixelOperation.paper) {
    removeDrawingPaper(source, request.tolerance, selection);
  } else if (request.operation == DrawingPixelOperation.fill ||
      request.operation == DrawingPixelOperation.remove) {
    editDrawingRegion(source,
        x: request.x,
        y: request.y,
        tolerance: request.tolerance,
        remove: request.operation == DrawingPixelOperation.remove,
        color: request.color,
        protectEdges: request.protectEdges,
        closeGaps: request.closeGaps,
        selection: selection);
  } else if (request.operation == DrawingPixelOperation.cutout) {
    if (request.polygon.length < 3) {
      throw const FormatException('Outline the drawing to keep first.');
    }
    final keep = polygonMask(source.width, source.height, request.polygon);
    for (final p in source) {
      if (keep[p.y * source.width + p.x] == 0) p.a = 0;
    }
  } else if (request.operation == DrawingPixelOperation.clearSelection) {
    if (selection == null) throw const FormatException('Select an area first.');
    for (final p in source) {
      if (selection[p.y * source.width + p.x] != 0) p.a = 0;
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
