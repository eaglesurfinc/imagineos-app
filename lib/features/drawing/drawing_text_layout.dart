import 'package:flutter/painting.dart';

import 'drawing_document.dart';

/// Shared metrics for placement validation, hit testing and PNG rendering.
TextPainter drawingTextPainter(DrawingStroke stroke) => TextPainter(
      text: TextSpan(
          text: stroke.text,
          style: TextStyle(
              fontFamily: stroke.fontFamily,
              fontSize: stroke.fontSize,
              height: 1.25,
              color: Color(stroke.color).withValues(alpha: stroke.opacity))),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: stroke.textWidth);

Rect drawingTextBounds(DrawingStroke stroke) {
  final painter = drawingTextPainter(stroke);
  final lines = painter.computeLineMetrics();
  final width = lines.fold<double>(
      1, (value, line) => value > line.width ? value : line.width);
  final rect =
      (stroke.points.first.offset & Size(width, painter.height)).inflate(4);
  painter.dispose();
  return rect;
}
