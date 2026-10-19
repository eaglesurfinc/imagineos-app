import 'dart:math' as math;
import 'dart:ui';

import 'drawing_document.dart';

Path drawingPolygon(List<DrawingPoint> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.x, points.first.y);
  for (final point in points.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path..close();
}

List<DrawingPoint> selectionRectangle(DrawingPoint a, DrawingPoint b) => [
      DrawingPoint(a.x, a.y),
      DrawingPoint(b.x, a.y),
      DrawingPoint(b.x, b.y),
      DrawingPoint(a.x, b.y)
    ];

Path drawingShape(DrawingTool tool, Offset start, Offset end) {
  var bounds = Rect.fromPoints(start, end);
  if (tool == DrawingTool.circle || tool == DrawingTool.square) {
    final side = math.min(bounds.width, bounds.height);
    bounds = Rect.fromCenter(center: bounds.center, width: side, height: side);
  }
  final path = Path();
  if (tool == DrawingTool.line)
    return path
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
  if (tool == DrawingTool.arrow) {
    final direction = end - start;
    final length = direction.distance;
    if (length == 0) return path;
    final unit = direction / length, normal = Offset(-unit.dy, unit.dx);
    final head = math.min(length * .35, 60.0);
    final neck = end - unit * head;
    final half = head * .18;
    return path
      ..moveTo((start + normal * half).dx, (start + normal * half).dy)
      ..lineTo((neck + normal * half).dx, (neck + normal * half).dy)
      ..lineTo((neck + normal * head * .55).dx, (neck + normal * head * .55).dy)
      ..lineTo(end.dx, end.dy)
      ..lineTo((neck - normal * head * .55).dx, (neck - normal * head * .55).dy)
      ..lineTo((neck - normal * half).dx, (neck - normal * half).dy)
      ..lineTo((start - normal * half).dx, (start - normal * half).dy)
      ..close();
  }
  if (tool == DrawingTool.rectangle || tool == DrawingTool.square)
    return path..addRect(bounds);
  if (tool == DrawingTool.ellipse || tool == DrawingTool.circle)
    return path..addOval(bounds);
  if (tool == DrawingTool.heart) {
    final left = bounds.left,
        top = bounds.top,
        w = bounds.width,
        h = bounds.height;
    return path
      ..moveTo(left + w / 2, top + h)
      ..cubicTo(left - w * .3, top + h * .45, left + w * .1, top - h * .3,
          left + w / 2, top + h * .25)
      ..cubicTo(left + w * .9, top - h * .3, left + w * 1.3, top + h * .45,
          left + w / 2, top + h)
      ..close();
  }
  final vertices = switch (tool) {
    DrawingTool.triangle => 3,
    DrawingTool.diamond => 4,
    DrawingTool.pentagon => 5,
    DrawingTool.hexagon => 6,
    DrawingTool.star => 10,
    _ => 0,
  };
  for (var i = 0; i < vertices; i++) {
    final angle = -math.pi / 2 + i * math.pi * 2 / vertices;
    final radius = tool == DrawingTool.star && i.isOdd ? .44 : 1.0;
    final x = bounds.center.dx + math.cos(angle) * bounds.width / 2 * radius;
    final y = bounds.center.dy + math.sin(angle) * bounds.height / 2 * radius;
    if (i == 0)
      path.moveTo(x, y);
    else
      path.lineTo(x, y);
  }
  return path..close();
}
