import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_selection.dart';
import 'package:imagineos/features/drawing/drawing_studio.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';

import 'drawing_interactions_test.dart' show settleImage;
import 'drawing_selection_test.dart' show square;
import 'support/memory_drawing_drafts.dart';

void main() {
  testWidgets(
      'a shape can go behind uploaded artwork; partial photo selections resize and recover',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final photo = image.Image(width: 256, height: 256, numChannels: 4);
    image.fillRect(photo,
        x1: 30,
        y1: 30,
        x2: 89,
        y2: 89,
        color: image.ColorRgba8(228, 71, 93, 255));
    final original = image.encodePng(photo);
    final drafts = MemoryDrawingDrafts()
      ..values['photo'] = DrawingDocument(
          width: 256,
          height: 256,
          frame: DrawingFrame(
              base: original,
              strokes: [square(50, 50, color: 0xff3e80d6, side: 60)])).encode();
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'photo', drafts: drafts)));
    await settleImage(tester);
    Future<void> action(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await settleImage(tester);
    }

    Offset at(double x, double y) {
      final rect = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
      return rect.topLeft + Offset(x / 256 * rect.width, y / 256 * rect.height);
    }

    DrawingDocument current() =>
        DrawingDocument.decode(drafts.values['photo']!);
    Future<image.Image> pixels() async {
      final doc = current();
      final bytes = await tester.runAsync(() async {
        final base = await decodeDrawingBase(doc.frame.base);
        try {
          return await exportDrawing(doc, base);
        } finally {
          base?.dispose();
        }
      });
      return image.decodePng(bytes!)!;
    }

    await action('Select area');
    await tester.tapAt(at(70, 70));
    await settleImage(tester);
    await action('Send to back');
    expect((await pixels()).getPixel(70, 70).r, 228,
        reason: 'the photo must now cover the blue shape');
    expect(current().frame.strokes.last.tool, DrawingTool.image);
    await action('Bring to front');
    expect((await pixels()).getPixel(70, 70).b, 214);
    await tester.tap(find.byTooltip('Undo'));
    await settleImage(tester);
    await tester.tap(find.byTooltip('Undo'));
    await settleImage(tester);
    final before = drafts.values['photo'];
    await tester.dragFrom(at(25, 25), at(45, 85) - at(25, 25));
    await settleImage(tester);
    expect(find.text('1 item selected'), findsOneWidget);
    expect(drafts.values['photo'], before);
    await action('Larger');
    final cut = current().frame.strokes.first;
    expect(cut.tool, DrawingTool.image);
    expect(cut.placement.scale, 1.2);
    expect(image.decodePng(cut.image!)!.width, 15);
    expect(image.decodePng(current().frame.base!)!.getPixel(35, 40).a, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'photo', drafts: drafts)));
    await settleImage(tester);
    expect(current().frame.strokes.first.placement.scale, 1.2);
    expect((await pixels()).getPixel(35, 40).a, 255);
    expect(image.decodePng(original)!.getPixel(35, 40).a, 255);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'tap, move, resize, layers, keyboard deletion and undo retain editable items',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final initial = DrawingDocument(
        width: 256,
        height: 256,
        frame: DrawingFrame(strokes: [
          square(30, 30, side: 60),
          square(60, 60, color: 0xff3e80d6, side: 60)
        ]));
    final drafts = MemoryDrawingDrafts()..values['objects'] = initial.encode();
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'objects', drafts: drafts)));
    await settleImage(tester);
    Future<void> action(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await settleImage(tester);
    }

    Offset at(double x, double y) {
      final rect = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
      return rect.topLeft + Offset(x / 256 * rect.width, y / 256 * rect.height);
    }

    DrawingDocument current() =>
        DrawingDocument.decode(drafts.values['objects']!);
    await action('Select area');
    await tester.tapAt(at(80, 80));
    await settleImage(tester);
    expect(find.text('1 item selected'), findsOneWidget);
    expect(drafts.values['objects'], initial.encode(),
        reason: 'selection alone must not change artwork');
    await action('Send to back');
    expect(current().frame.strokes.first.color, 0xff3e80d6);
    await action('Bring forward');
    expect(current().frame.strokes.last.color, 0xff3e80d6);
    await action('Larger');
    expect(current().frame.strokes.last.placement.scale, 1.2);
    await action('Smaller');
    expect(current().frame.strokes.last.placement.scale, closeTo(1, .0001));
    var bounds = drawingItemBounds(current().frame.strokes.last);
    final start = at(bounds.center.dx, bounds.center.dy);
    await tester.dragFrom(
        start, at(bounds.center.dx + 35, bounds.center.dy + 25) - start,
        kind: PointerDeviceKind.mouse);
    await settleImage(tester);
    var moved = current().frame.strokes.last;
    expect(moved.placement.x, closeTo(35, .1));
    expect(moved.placement.y, closeTo(25, .1));
    bounds = drawingItemBounds(moved);
    final corner = at(bounds.right, bounds.bottom),
        pivot = at(bounds.left, bounds.top);
    await tester.dragFrom(corner, (corner - pivot) * .25,
        kind: PointerDeviceKind.mouse);
    await settleImage(tester);
    moved = current().frame.strokes.last;
    expect(moved.placement.scale, closeTo(1.25, .01));
    expect(moved.tool, DrawingTool.rectangle);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await settleImage(tester);
    expect(current().frame.strokes.length, 1);
    expect(current().frame.base, isNull,
        reason: 'object deletion must not flatten other shapes');
    await tester.tap(find.byTooltip('Undo'));
    await settleImage(tester);
    expect(current().frame.strokes.length, 2);
    expect(current().frame.strokes.last.placement.scale, closeTo(1.25, .01));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'objects', drafts: drafts)));
    await settleImage(tester);
    await action('Select area');
    final recoveredBounds = drawingItemBounds(current().frame.strokes.last);
    await tester
        .tapAt(at(recoveredBounds.center.dx, recoveredBounds.center.dy));
    await settleImage(tester);
    await action('Delete selection');
    expect(current().frame.strokes.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'marquee selects multiple objects and touchscreen cancel leaves artwork intact',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final doc = DrawingDocument(
        width: 256,
        height: 256,
        frame: DrawingFrame(
            strokes: [square(30, 30), square(90, 90), square(200, 200)]));
    final drafts = MemoryDrawingDrafts()..values['multi'] = doc.encode();
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'multi', drafts: drafts)));
    await settleImage(tester);
    await tester.tap(find.text('Select area'));
    await tester.pumpAndSettle();
    Offset at(double x, double y) {
      final rect = tester.getRect(find.byKey(const ValueKey('drawing-canvas')));
      return rect.topLeft + Offset(x / 256 * rect.width, y / 256 * rect.height);
    }

    await tester.dragFrom(at(10, 10), at(150, 150) - at(10, 10));
    await settleImage(tester);
    expect(find.text('2 items selected'), findsOneWidget);
    final gesture = await tester.startGesture(at(80, 80));
    await gesture.moveTo(at(100, 100));
    await tester.pump();
    await gesture.cancel();
    await settleImage(tester);
    expect(drafts.values['multi'], doc.encode());
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await settleImage(tester);
    final changed = DrawingDocument.decode(drafts.values['multi']!);
    expect(changed.frame.strokes.length, 1);
    expect(changed.frame.strokes.single.points.first.x, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection controls fit a phone with enlarged text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final doc = DrawingDocument(
        width: 256,
        height: 256,
        frame: DrawingFrame(strokes: [square(40, 40)]));
    final drafts = MemoryDrawingDrafts()..values['phone'] = doc.encode();
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: DrawingStudio(draftKey: 'phone', drafts: drafts)));
    await settleImage(tester);
    await tester.ensureVisible(find.text('Select area'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select area'));
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    await tester.scrollUntilVisible(canvas, -200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final rect = tester.getRect(canvas);
    await tester.tapAt(
        rect.topLeft + Offset(rect.width * 60 / 256, rect.height * 60 / 256));
    await settleImage(tester);
    expect(find.text('1 item selected'), findsOneWidget);
    expect(find.text('Delete selection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
