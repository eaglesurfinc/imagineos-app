import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

double drawingPressure(PointerEvent event) {
  if (event.kind != PointerDeviceKind.stylus &&
      event.kind != PointerDeviceKind.invertedStylus) return 1;
  final range = event.pressureMax - event.pressureMin;
  if (!event.pressure.isFinite || !range.isFinite || range <= 0) return 1;
  return ((event.pressure - event.pressureMin) / range).clamp(0, 1);
}

/// Own pointer arbitration explicitly: a second finger cancels the pending
/// stroke and navigates; a pen takes priority over fingers. Pen-only mode lets
/// the user rest a hand without drawing while fingers remain navigation tools.
class DrawingInputSurface extends StatefulWidget {
  const DrawingInputSurface(
      {super.key,
      required this.controller,
      required this.child,
      required this.pan,
      required this.penOnly,
      required this.onStart,
      required this.onMove,
      required this.onEnd,
      required this.onCancel});
  final TransformationController controller;
  final Widget child;
  final bool pan, penOnly;
  final void Function(PointerEvent, Offset) onStart, onMove;
  final VoidCallback onEnd, onCancel;
  @override
  State<DrawingInputSurface> createState() => _DrawingInputSurfaceState();
}

class _DrawingInputSurfaceState extends State<DrawingInputSurface> {
  final _touches = <int, Offset>{};
  final _ignored = <int>{};
  int? _drawing, _pen, _panPointer;
  Offset? _lastPan, _gestureCenter;
  double _gestureSpan = 1;
  Matrix4? _gestureMatrix;
  bool _navigating = false;

  Offset _scene(Offset point) => MatrixUtils.transformPoint(
      Matrix4.inverted(widget.controller.value), point);
  void _cancel() {
    if (_drawing != null) widget.onCancel();
    _drawing = null;
  }

  (Offset, double) _touchGeometry() {
    final points = _touches.values.take(2).toList();
    return (
      (points[0] + points[1]) / 2,
      (points[0] - points[1]).distance.clamp(1, double.infinity)
    );
  }

  void _beginGesture() {
    _cancel();
    _navigating = true;
    _panPointer = null;
    _lastPan = null;
    final (center, span) = _touchGeometry();
    _gestureCenter = center;
    _gestureSpan = span;
    _gestureMatrix = Matrix4.copy(widget.controller.value);
  }

  void _down(PointerDownEvent event) {
    final pen = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (pen) {
      if (_pen != null) return;
      _cancel();
      _ignored.addAll(_touches.keys);
      _touches.clear();
      _gestureMatrix = null;
      _pen = event.pointer;
    } else if (_pen != null) {
      _ignored.add(event.pointer);
      return;
    }
    if (event.kind == PointerDeviceKind.touch) {
      _touches[event.pointer] = event.localPosition;
      if (_touches.length >= 2) {
        _beginGesture();
        return;
      }
    }
    if (_drawing != null) return;
    if (widget.pan ||
        (widget.penOnly && event.kind == PointerDeviceKind.touch)) {
      _panPointer = event.pointer;
      _lastPan = event.localPosition;
      _navigating = true;
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) return;
    _drawing = event.pointer;
    widget.onStart(event, _scene(event.localPosition));
  }

  void _move(PointerMoveEvent event) {
    if (_ignored.contains(event.pointer)) return;
    if (_touches.containsKey(event.pointer))
      _touches[event.pointer] = event.localPosition;
    if (_pen == null && _touches.length >= 2 && _gestureMatrix != null) {
      final (center, span) = _touchGeometry();
      final baseScale = _gestureMatrix!.getMaxScaleOnAxis();
      final scale = (baseScale * span / _gestureSpan).clamp(.5, 5) / baseScale;
      widget.controller.value = Matrix4.identity()
        ..translateByDouble(center.dx, center.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-_gestureCenter!.dx, -_gestureCenter!.dy, 0, 1)
        ..multiply(_gestureMatrix!);
    } else if (_panPointer == event.pointer &&
        _lastPan != null &&
        _touches.length < 2) {
      final delta = event.localPosition - _lastPan!;
      widget.controller.value = Matrix4.identity()
        ..translateByDouble(delta.dx, delta.dy, 0, 1)
        ..multiply(widget.controller.value);
      _lastPan = event.localPosition;
    } else if (_drawing == event.pointer &&
        (!_navigating || _pen == event.pointer)) {
      widget.onMove(event, _scene(event.localPosition));
    }
  }

  void _up(PointerEvent event, {bool cancelled = false}) {
    _ignored.remove(event.pointer);
    _touches.remove(event.pointer);
    if (_drawing == event.pointer) {
      _drawing = null;
      if (cancelled)
        widget.onCancel();
      else
        widget.onEnd();
    }
    if (_pen == event.pointer) _pen = null;
    if (_panPointer == event.pointer) {
      _panPointer = null;
      _lastPan = null;
    }
    if (_touches.isEmpty) {
      _navigating = false;
      _gestureMatrix = null;
    }
  }

  @override
  void didUpdateWidget(DrawingInputSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pan != widget.pan || oldWidget.penOnly != widget.penOnly) {
      // The parent clears its pending preview when changing tools/settings.
      _drawing = null;
      _panPointer = null;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Claim canvas gestures from the surrounding page scroller. Actual
      // drawing/navigation uses raw events, including pressure and pen erasers.
      onScaleStart: (_) {},
      onScaleUpdate: (_) {},
      child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: (event) => _up(event, cancelled: true),
          child: ClipRect(
              child: AnimatedBuilder(
                  animation: widget.controller,
                  child: widget.child,
                  builder: (context, child) => Transform(
                      transform: widget.controller.value,
                      transformHitTests: false,
                      child: child)))));
}
