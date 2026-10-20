import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'drawing_document.dart';
import 'drawing_renderer.dart';
import 'drawing_shapes.dart';

class CheckerPainter extends CustomPainter {
  const CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()..color = const Color(0xffe7e4ed);
    for (var y = 0; y < size.height; y += 16) {
      for (var x = 0; x < size.width; x += 16) {
        if ((x ~/ 16 + y ~/ 16).isEven)
          canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(),
                  math.min(16, size.width - x), math.min(16, size.height - y)),
              paint);
      }
    }
  }

  @override
  bool shouldRepaint(CheckerPainter oldDelegate) => false;
}

class DrawingCanvasPainter extends CustomPainter {
  const DrawingCanvasPainter(
      this.document, this.base, this.active, this.outline, this.cursor,
      {this.selection = const [],
      this.itemBounds,
      this.images = const {},
      this.handleRadius = 6});
  final DrawingDocument document;
  final ui.Image? base;
  final DrawingStroke? active;
  final List<DrawingPoint> outline;
  final Offset? cursor;
  final List<DrawingPoint> selection;
  final Rect? itemBounds;
  final Map<Uint8List, ui.Image> images;
  final double handleRadius;
  @override
  void paint(Canvas canvas, Size size) {
    const CheckerPainter().paint(canvas, size);
    canvas.save();
    canvas.scale(size.width / document.width, size.height / document.height);
    paintDrawing(canvas, document, base, active: active, images: images);
    if (outline.isNotEmpty) {
      final path = drawingPolygon(outline);
      canvas.drawPath(path,
          Paint()..color = const Color(0xff5a3ce0).withValues(alpha: .15));
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff5a3ce0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    if (selection.length >= 3) {
      final path = drawingPolygon(selection);
      canvas.drawPath(path,
          Paint()..color = const Color(0xff007b94).withValues(alpha: .07));
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff007b94)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    final bounds = itemBounds;
    if (bounds != null) {
      canvas.drawRect(
          bounds,
          Paint()
            ..color = const Color(0xff007b94)
            ..style = PaintingStyle.stroke
            ..strokeWidth = handleRadius / 3);
      for (final point in [
        bounds.topLeft,
        bounds.topRight,
        bounds.bottomLeft,
        bounds.bottomRight
      ]) {
        canvas.drawCircle(point, handleRadius, Paint()..color = Colors.white);
        canvas.drawCircle(
            point,
            handleRadius,
            Paint()
              ..color = const Color(0xff007b94)
              ..style = PaintingStyle.stroke
              ..strokeWidth = handleRadius / 3);
      }
    }
    if (cursor != null) {
      final paint = Paint()
        ..color = const Color(0xffee4271)
        ..strokeWidth = 2;
      canvas.drawCircle(cursor!, 10, paint..style = PaintingStyle.stroke);
      canvas.drawLine(
          cursor! - const Offset(16, 0), cursor! + const Offset(16, 0), paint);
      canvas.drawLine(
          cursor! - const Offset(0, 16), cursor! + const Offset(0, 16), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) => true;
}
