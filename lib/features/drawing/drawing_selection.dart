import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'drawing_document.dart';
import 'drawing_shapes.dart';
import 'drawing_text_layout.dart';

bool selectableDrawingItem(DrawingStroke item) =>
    item.points.isNotEmpty &&
    item.tool != DrawingTool.eraser &&
    item.opacity > 0;

Rect drawingItemBounds(DrawingStroke item) {
  Rect bounds;
  if (item.tool == DrawingTool.text) {
    bounds = drawingTextBounds(item);
  } else if (item.tool == DrawingTool.image) {
    bounds = Rect.fromPoints(item.points.first.offset, item.points.last.offset);
  } else if (item.tool.isShape) {
    bounds = drawingShape(
            item.tool, item.points.first.offset, item.points.last.offset)
        .getBounds()
        .inflate(item.width / 2);
  } else {
    final xs = item.points.map((p) => p.x), ys = item.points.map((p) => p.y);
    bounds = Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
            xs.reduce(math.max), ys.reduce(math.max))
        .inflate(item.width / 2);
  }
  if (item.selection.length >= 3) {
    bounds = bounds.intersect(drawingPolygon(item.selection).getBounds());
  }
  return item.placement.applyRect(bounds);
}

// Use the actual drawing path rather than a bounding-box-only intersection:
// a marquee beside a diagonal stroke must not select the stroke.
Path _itemRegion(DrawingStroke item, {double tolerance = 0}) {
  var path = Path();
  if (item.tool == DrawingTool.text || item.tool == DrawingTool.image) {
    final bounds = item.tool == DrawingTool.text
        ? drawingTextBounds(item)
        : Rect.fromPoints(item.points.first.offset, item.points.last.offset);
    path.addRect(bounds.inflate(tolerance));
  } else {
    final line = item.tool.isShape
        ? drawingShape(
            item.tool, item.points.first.offset, item.points.last.offset)
        : (Path()
          ..addPolygon(item.points.map((p) => p.offset).toList(), false));
    if (item.tool.isShape && item.tool != DrawingTool.line)
      path.addPath(line, Offset.zero);
    final radius = item.width / 2 + tolerance;
    void segment(Offset a, Offset b) {
      path.addOval(Rect.fromCircle(center: a, radius: radius));
      final direction = b - a;
      if (direction.distance > 0) {
        final normal =
            Offset(-direction.dy, direction.dx) / direction.distance * radius;
        path.addPolygon([a - normal, b - normal, b + normal, a + normal], true);
      }
    }

    if (item.tool.isShape) {
      for (final metric in line.computeMetrics()) {
        final first = metric.getTangentForOffset(0);
        if (first == null) continue;
        var last = first.position;
        for (var distance = 3.0; distance < metric.length + 3; distance += 3) {
          final next = metric
              .getTangentForOffset(math.min(distance, metric.length))
              ?.position;
          if (next != null) {
            segment(last, next);
            last = next;
          }
        }
        segment(last, last);
      }
    } else {
      for (var i = 0; i < item.points.length; i++) {
        segment(item.points[i].offset,
            item.points[math.min(i + 1, item.points.length - 1)].offset);
      }
    }
  }
  if (item.selection.length >= 3) {
    path = Path.combine(
        PathOperation.intersect, path, drawingPolygon(item.selection));
  }
  final p = item.placement;
  return path.transform(Float64List.fromList(
      [p.scale, 0, 0, 0, 0, p.scale, 0, 0, 0, 0, 1, 0, p.x, p.y, 0, 1]));
}

int? hitDrawingItem(List<DrawingStroke> items, Offset point,
    {double tolerance = 6}) {
  for (var i = items.length - 1; i >= 0; i--) {
    final item = items[i];
    if (selectableDrawingItem(item) &&
        drawingItemBounds(item).inflate(tolerance).contains(point) &&
        _itemRegion(item, tolerance: tolerance / item.placement.scale)
            .contains(point)) return i;
  }
  return null;
}

Set<int> drawingItemsInArea(
    List<DrawingStroke> items, List<DrawingPoint> polygon) {
  final path = drawingPolygon(polygon), bounds = path.getBounds();
  return {
    for (var i = 0; i < items.length; i++)
      if (selectableDrawingItem(items[i]) &&
          bounds.overlaps(drawingItemBounds(items[i])) &&
          !Path.combine(PathOperation.intersect, path, _itemRegion(items[i]))
              .getBounds()
              .isEmpty)
        i
  };
}

Rect? drawingSelectionBounds(List<DrawingStroke> items, Set<int> indices) {
  Rect? result;
  for (final index in indices) {
    final bounds = drawingItemBounds(items[index]);
    result = result?.expandToInclude(bounds) ?? bounds;
  }
  return result;
}

/// Keep selected content on the page and preserve its proportions, widths and
/// text layout. Every gesture uses its initial frame, avoiding cumulative drift.
DrawingFrame transformDrawingItems(
    DrawingFrame frame, Set<int> selected, Rect bounds, Size canvas,
    {Offset delta = Offset.zero, double factor = 1, Offset? pivot}) {
  pivot ??= bounds.center;
  final placements = selected.map((i) => frame.strokes[i].placement.scale);
  var minFactor = .01 / placements.reduce(math.min);
  var maxFactor = math.min(64 / placements.reduce(math.max),
      math.min(canvas.width / bounds.width, canvas.height / bounds.height));
  minFactor = math.min(minFactor, maxFactor);
  factor = factor.clamp(minFactor, maxFactor);
  final changed = Rect.fromPoints(
      (bounds.topLeft - pivot) * factor + pivot + delta,
      (bounds.bottomRight - pivot) * factor + pivot + delta);
  delta += Offset(
      changed.left < 0
          ? -changed.left
          : changed.right > canvas.width
              ? canvas.width - changed.right
              : 0,
      changed.top < 0
          ? -changed.top
          : changed.bottom > canvas.height
              ? canvas.height - changed.bottom
              : 0);
  return frame.copyWith(strokes: [
    for (var i = 0; i < frame.strokes.length; i++)
      selected.contains(i)
          ? frame.strokes[i]
              .placed(frame.strokes[i].placement.changed(factor, pivot, delta))
          : frame.strokes[i]
  ]);
}

enum DrawingLayerOrder { backward, forward, back, front }

({DrawingFrame frame, Set<int> selected}) reorderDrawingItems(
    DrawingFrame frame, Set<int> selected, DrawingLayerOrder order) {
  final indices = List.generate(frame.strokes.length, (i) => i);
  if (order == DrawingLayerOrder.front || order == DrawingLayerOrder.back) {
    indices.sort((a, b) {
      final group =
          (selected.contains(a) ? 1 : 0) - (selected.contains(b) ? 1 : 0);
      return group == 0
          ? a.compareTo(b)
          : order == DrawingLayerOrder.front
              ? group
              : -group;
    });
  } else if (order == DrawingLayerOrder.forward) {
    for (var i = indices.length - 2; i >= 0; i--) {
      if (selected.contains(indices[i]) && !selected.contains(indices[i + 1])) {
        final temp = indices[i];
        indices[i] = indices[i + 1];
        indices[i + 1] = temp;
      }
    }
  } else {
    for (var i = 1; i < indices.length; i++) {
      if (selected.contains(indices[i]) && !selected.contains(indices[i - 1])) {
        final temp = indices[i];
        indices[i] = indices[i - 1];
        indices[i - 1] = temp;
      }
    }
  }
  return (
    frame:
        frame.copyWith(strokes: indices.map((i) => frame.strokes[i]).toList()),
    selected: {
      for (var i = 0; i < indices.length; i++)
        if (selected.contains(indices[i])) i
    }
  );
}
