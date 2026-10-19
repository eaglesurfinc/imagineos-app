import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'drawing_document.dart';
import 'drawing_renderer.dart';

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
      this.document, this.base, this.active, this.outline, this.cursor);
  final DrawingDocument document;
  final ui.Image? base;
  final DrawingStroke? active;
  final List<DrawingPoint> outline;
  final Offset? cursor;
  @override
  void paint(Canvas canvas, Size size) {
    const CheckerPainter().paint(canvas, size);
    canvas.save();
    canvas.scale(size.width / document.width, size.height / document.height);
    paintDrawing(canvas, document, base, active: active);
    if (outline.isNotEmpty) {
      final path = Path()..moveTo(outline.first.x, outline.first.y);
      for (final p in outline.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      path.close();
      canvas.drawPath(path,
          Paint()..color = const Color(0xff5a3ce0).withValues(alpha: .15));
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff5a3ce0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
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
