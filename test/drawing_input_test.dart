import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/drawing/drawing_input.dart';

void main() {
  test(
      'pen pressure normalizes device ranges and safely falls back without pressure',
      () {
    expect(
        drawingPressure(const PointerDownEvent(
            kind: PointerDeviceKind.stylus,
            pressureMin: 2,
            pressureMax: 6,
            pressure: 3)),
        .25);
    expect(
        drawingPressure(const PointerDownEvent(
            kind: PointerDeviceKind.invertedStylus,
            pressureMin: 0,
            pressureMax: 1024,
            pressure: 768)),
        .75);
    expect(
        drawingPressure(const PointerDownEvent(kind: PointerDeviceKind.stylus)),
        1);
    expect(
        drawingPressure(const PointerDownEvent(
            kind: PointerDeviceKind.mouse, pressure: .2)),
        1);
  });
  testWidgets(
      'second finger cancels unfinished paint and pinches without stray strokes',
      (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    var starts = 0, ends = 0, cancels = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    height: 400,
                    child: DrawingInputSurface(
                        controller: controller,
                        pan: false,
                        penOnly: false,
                        onStart: (_, __) => starts++,
                        onMove: (_, __) {},
                        onEnd: () => ends++,
                        onCancel: () => cancels++,
                        child: const ColoredBox(color: Colors.white)))))));
    final center = tester.getCenter(find.byType(DrawingInputSurface));
    void event(PointerEvent event) => tester.binding.handlePointerEvent(event);
    event(PointerDownEvent(pointer: 1, position: center - const Offset(50, 0)));
    event(PointerDownEvent(pointer: 2, position: center + const Offset(50, 0)));
    event(PointerMoveEvent(
        pointer: 2,
        position: center + const Offset(100, 0),
        delta: const Offset(50, 0)));
    await tester.pump();
    expect(starts, 1);
    expect(cancels, 1);
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.4));
    event(PointerUpEvent(pointer: 2, position: center + const Offset(100, 0)));
    event(PointerMoveEvent(
        pointer: 1, position: center, delta: const Offset(50, 0)));
    event(PointerUpEvent(pointer: 1, position: center));
    expect(ends, 0);
    event(PointerDownEvent(pointer: 3, position: center));
    event(PointerUpEvent(pointer: 3, position: center));
    expect(starts, 2);
    expect(ends, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'pen wins over finger contact; pressure and eraser kind reach the canvas',
      (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    final kinds = <PointerDeviceKind>[],
        pressures = <double>[],
        positions = <Offset>[];
    var cancels = 0, ends = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    height: 400,
                    child: DrawingInputSurface(
                        controller: controller,
                        pan: false,
                        penOnly: false,
                        onStart: (event, position) {
                          kinds.add(event.kind);
                          positions.add(position);
                          pressures.add(drawingPressure(event));
                        },
                        onMove: (event, _) =>
                            pressures.add(drawingPressure(event)),
                        onEnd: () => ends++,
                        onCancel: () => cancels++,
                        child: const ColoredBox(color: Colors.white)))))));
    final center = tester.getCenter(find.byType(DrawingInputSurface));
    void event(PointerEvent event) => tester.binding.handlePointerEvent(event);
    event(PointerDownEvent(pointer: 1, position: center));
    event(PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: center,
        pressureMin: 0,
        pressureMax: 1024,
        pressure: 256));
    event(
        PointerDownEvent(pointer: 3, position: center + const Offset(20, 20)));
    event(PointerMoveEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: center + const Offset(30, 0),
        pressureMin: 0,
        pressureMax: 1024,
        pressure: 768));
    event(PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: center + const Offset(30, 0)));
    event(PointerUpEvent(pointer: 3, position: center + const Offset(20, 20)));
    event(PointerUpEvent(pointer: 1, position: center));
    expect(kinds, [PointerDeviceKind.touch, PointerDeviceKind.stylus]);
    expect(pressures.skip(1), [.25, .75]);
    expect(cancels, 1);
    expect(ends, 1);
    controller.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
    event(PointerDownEvent(
        pointer: 4, kind: PointerDeviceKind.invertedStylus, position: center));
    event(PointerUpEvent(
        pointer: 4, kind: PointerDeviceKind.invertedStylus, position: center));
    expect(kinds.last, PointerDeviceKind.invertedStylus);
    expect(positions.last, const Offset(100, 100));
  });
  testWidgets('pen-only mode makes finger input navigate instead of paint',
      (tester) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    var starts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    height: 400,
                    child: DrawingInputSurface(
                        controller: controller,
                        pan: false,
                        penOnly: true,
                        onStart: (_, __) => starts++,
                        onMove: (_, __) {},
                        onEnd: () {},
                        onCancel: () {},
                        child: const ColoredBox(color: Colors.white)))))));
    final center = tester.getCenter(find.byType(DrawingInputSurface));
    tester.binding
        .handlePointerEvent(PointerDownEvent(pointer: 1, position: center));
    tester.binding.handlePointerEvent(PointerMoveEvent(
        pointer: 1,
        position: center + const Offset(30, 20),
        delta: const Offset(30, 20)));
    tester.binding.handlePointerEvent(
        PointerUpEvent(pointer: 1, position: center + const Offset(30, 20)));
    expect(starts, 0);
    expect(controller.value.getTranslation().x, 30);
    tester.binding.handlePointerEvent(PointerDownEvent(
        pointer: 2, kind: PointerDeviceKind.stylus, position: center));
    tester.binding.handlePointerEvent(PointerUpEvent(
        pointer: 2, kind: PointerDeviceKind.stylus, position: center));
    expect(starts, 1);
  });
}
