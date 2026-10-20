import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'drawing_document.dart';
import 'drawing_shapes.dart';
import 'drawing_text_layout.dart';

void paintDrawing(ui.Canvas canvas, DrawingDocument document, ui.Image? base,
    {DrawingStroke? active,
    bool background = true,
    Map<Uint8List, ui.Image> images = const {}}) {
  final bounds = ui.Rect.fromLTWH(
      0, 0, document.width.toDouble(), document.height.toDouble());
  canvas.save();
  canvas.clipRect(bounds);
  if (background)
    canvas.drawRect(
        bounds, ui.Paint()..color = ui.Color(document.frame.background));
  canvas.saveLayer(bounds, ui.Paint());
  if (base != null)
    canvas.drawImageRect(
        base,
        ui.Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        bounds,
        ui.Paint());
  for (final stroke in document.frame.strokes) {
    paintStroke(canvas, stroke, images: images);
  }
  if (active != null) paintStroke(canvas, active);
  canvas.restore();
  canvas.restore();
}

void paintStroke(ui.Canvas canvas, DrawingStroke stroke,
    {Map<Uint8List, ui.Image> images = const {}}) {
  canvas.save();
  canvas.translate(stroke.placement.x, stroke.placement.y);
  canvas.scale(stroke.placement.scale);
  if (stroke.selection.length >= 3)
    canvas.clipPath(drawingPolygon(stroke.selection));
  if (stroke.tool == DrawingTool.image) {
    final image = images[stroke.image];
    if (image != null) {
      canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
              0, 0, image.width.toDouble(), image.height.toDouble()),
          ui.Rect.fromPoints(
              stroke.points.first.offset, stroke.points.last.offset),
          ui.Paint()..filterQuality = ui.FilterQuality.medium);
    }
  } else {
    _paintStroke(canvas, stroke);
  }
  canvas.restore();
}

void _paintStroke(ui.Canvas canvas, DrawingStroke stroke) {
  if (stroke.points.isEmpty) return;
  if (stroke.tool == DrawingTool.text) {
    final painter = drawingTextPainter(stroke);
    painter.paint(canvas, stroke.points.first.offset);
    painter.dispose();
    return;
  }
  final paint = ui.Paint()
    ..color = ui.Color(stroke.color).withValues(alpha: stroke.opacity)
    ..strokeWidth = stroke.width
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..style = ui.PaintingStyle.stroke;
  if (stroke.tool == DrawingTool.eraser) paint.blendMode = ui.BlendMode.clear;
  if (stroke.tool == DrawingTool.softBrush)
    paint.maskFilter =
        ui.MaskFilter.blur(ui.BlurStyle.normal, stroke.width * .2);
  if (stroke.tool == DrawingTool.marker) paint.strokeCap = ui.StrokeCap.square;
  if (stroke.tool == DrawingTool.highlighter) {
    paint.strokeCap = ui.StrokeCap.square;
    paint.blendMode = ui.BlendMode.multiply;
  }
  final first = stroke.points.first.offset, last = stroke.points.last.offset;
  if (stroke.tool.isShape) {
    paint.style = stroke.filled && stroke.tool != DrawingTool.line
        ? ui.PaintingStyle.fill
        : ui.PaintingStyle.stroke;
    canvas.drawPath(drawingShape(stroke.tool, first, last), paint);
    return;
  }
  if (stroke.points.length == 1) {
    canvas.drawCircle(
        first,
        stroke.width * (.35 + .65 * stroke.points.first.pressure) / 2,
        paint..style = ui.PaintingStyle.fill);
    return;
  }
  if (stroke.points.every((p) => p.pressure == 1)) {
    if (stroke.tool == DrawingTool.pencil) {
      paint.color =
          ui.Color(stroke.color).withValues(alpha: stroke.opacity * .65);
      paint.strokeWidth = math.max(1, stroke.width * .55);
    }
    final path = ui.Path()..moveTo(first.dx, first.dy);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(path, paint);
    return;
  }
  for (var i = 1; i < stroke.points.length; i++) {
    final from = stroke.points[i - 1], to = stroke.points[i];
    paint.strokeWidth = stroke.width * (.35 + .65 * to.pressure.clamp(0, 1));
    if (stroke.tool == DrawingTool.pencil) {
      paint.color =
          ui.Color(stroke.color).withValues(alpha: stroke.opacity * .65);
      paint.strokeWidth = math.max(1, paint.strokeWidth * .55);
    }
    canvas.drawLine(from.offset, to.offset, paint);
  }
}

Future<ui.Image?> decodeDrawingBase(Uint8List? bytes) async {
  if (bytes == null) return null;
  if (bytes.length < 24 ||
      bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
    throw const FormatException('The drawing layer is not a valid PNG.');
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(16), height = header.getUint32(20);
  if (width < 1 || height < 1 || width > 1536 || height > 1536) {
    throw const FormatException(
        'The drawing layer exceeds the workspace limit.');
  }
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> exportDrawing(DrawingDocument document, ui.Image? base,
    {bool background = true}) async {
  final images = await decodeDrawingItems(document.frame);
  final recorder = ui.PictureRecorder();
  paintDrawing(ui.Canvas(recorder), document, base,
      background: background, images: images);
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(document.width, document.height);
    final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null)
      throw const FormatException('Could not prepare this drawing.');
    return bytes.buffer.asUint8List();
  } finally {
    output?.dispose();
    picture.dispose();
    for (final image in images.values) {
      image.dispose();
    }
  }
}

Future<Map<Uint8List, ui.Image>> decodeDrawingItems(DrawingFrame frame) async {
  final images = <Uint8List, ui.Image>{};
  var pixels = 0;
  try {
    for (final stroke in frame.strokes) {
      final bytes = stroke.image;
      if (bytes != null && !images.containsKey(bytes)) {
        if (bytes.length < 24)
          throw const FormatException('Invalid artwork item.');
        final header = ByteData.sublistView(bytes);
        pixels += header.getUint32(16) * header.getUint32(20);
        if (pixels > 16000000)
          throw const FormatException(
              'Merge paint to keep this workspace manageable.');
        images[bytes] = (await decodeDrawingBase(bytes))!;
      }
    }
    return images;
  } catch (_) {
    for (final image in images.values) {
      image.dispose();
    }
    rethrow;
  }
}
