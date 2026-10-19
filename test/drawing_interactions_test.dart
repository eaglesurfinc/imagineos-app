import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';
import 'package:imagineos/features/drawing/drawing_studio.dart';

import 'support/memory_drawing_drafts.dart';

Future<void> settleImage(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'device save exports transparent artwork and preserves the workspace on cancel or failure',
      (tester) async {
    final drafts = MemoryDrawingDrafts();
    var attempts = 0;
    Uint8List? exported;
    String? filename;
    await tester.pumpWidget(MaterialApp(
        home: DrawingStudio(
            draftKey: 'download',
            drafts: drafts,
            saveDrawing: (bytes, name) async {
              attempts++;
              if (attempts == 1) return false;
              if (attempts == 2) throw StateError('Fictional device failure');
              exported = bytes;
              filename = name;
              return true;
            })));
    await settleImage(tester);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    await tester.dragFrom(
        tester.getCenter(canvas) - const Offset(30, 0), const Offset(60, 20));
    await settleImage(tester);
    final before = drafts.values['download'];
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Save to device'));
      await settleImage(tester);
      expect(find.byType(DrawingStudio), findsOneWidget);
      expect(drafts.values['download'], before);
    }
    final png = image.decodePng(exported!)!;
    expect(filename, startsWith('imagineos-drawing-'));
    expect(filename, endsWith('.png'));
    expect(png.getPixel(0, 0).a, 0);
    expect(png.any((p) => p.a > 0), isTrue);
  });
  for (final key in [
    null,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.backspace
  ]) {
    testWidgets(
        'selection deletion via ${key?.keyLabel ?? 'button'} stays bounded and undo restores it',
        (tester) async {
      final photo = image.Image(width: 32, height: 32, numChannels: 4);
      image.fill(photo, color: image.ColorRgba8(230, 35, 75, 255));
      final drafts = MemoryDrawingDrafts();
      await tester.pumpWidget(MaterialApp(
          home: DrawingStudio(
              source: image.encodePng(photo),
              draftKey: 'selection',
              drafts: drafts)));
      await settleImage(tester);
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await settleImage(tester);
      }

      await tap('Select area');
      final canvas = find.byKey(const ValueKey('drawing-canvas'));
      await tester.scrollUntilVisible(canvas, -200);
      await tester.pumpAndSettle();
      final rect = tester.getRect(canvas);
      await tester.dragFrom(
          rect.topLeft + Offset(rect.width * .05, rect.height * .05),
          Offset(rect.width * .4, rect.height * .9));
      await settleImage(tester);
      if (key == null) {
        await tap('Delete selection');
      } else {
        await tester.sendKeyEvent(key);
        await settleImage(tester);
      }
      var doc = DrawingDocument.decode(drafts.values['selection']!);
      var png = image.decodePng(doc.frame.base!)!;
      expect(png.getPixel(4, 16).a, 0);
      expect(png.getPixel(24, 16).r, 230);
      expect(png.getPixel(24, 16).a, 255);
      await tester.tap(find.byTooltip('Undo'));
      await settleImage(tester);
      doc = DrawingDocument.decode(drafts.values['selection']!);
      png = image.decodePng(doc.frame.base!)!;
      expect(png.getPixel(4, 16).a, 255);
      if (key != null) {
        // A focused text field must consume deletion without clearing the canvas.
        final before = drafts.values['selection'];
        await tap('Custom color');
        await tester.enterText(find.byType(TextField), 'ABCDEF');
        await tester.sendKeyEvent(key);
        await settleImage(tester);
        expect(drafts.values['selection'], before);
        await tester.tap(find.text('Cancel'));
        await settleImage(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'studio records normalized pen pressure, ignores a palm, and erases with an inverted pen',
      (tester) async {
    final photo = image.Image(width: 32, height: 32, numChannels: 4);
    image.fill(photo, color: image.ColorRgba8(35, 140, 225, 255));
    final drafts = MemoryDrawingDrafts();
    await tester.pumpWidget(MaterialApp(
        home: DrawingStudio(
            source: image.encodePng(photo), draftKey: 'pen', drafts: drafts)));
    await settleImage(tester);
    final center =
        tester.getCenter(find.byKey(const ValueKey('drawing-canvas')));
    void event(PointerEvent event) => tester.binding.handlePointerEvent(event);
    event(PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: center - const Offset(40, 0),
        pressureMin: 0,
        pressureMax: 1024,
        pressure: 256));
    event(
        PointerDownEvent(pointer: 2, position: center + const Offset(30, 30)));
    event(PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: center + const Offset(40, 0),
        pressureMin: 0,
        pressureMax: 1024,
        pressure: 768));
    event(PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: center + const Offset(40, 0)));
    event(PointerUpEvent(pointer: 2, position: center + const Offset(30, 30)));
    await settleImage(tester);
    var doc = DrawingDocument.decode(drafts.values['pen']!);
    expect(doc.frame.strokes.length, 1);
    expect(doc.frame.strokes.single.points.map((p) => p.pressure), [.25, .75]);
    event(PointerDownEvent(
        pointer: 3,
        kind: PointerDeviceKind.invertedStylus,
        position: center,
        pressureMin: 0,
        pressureMax: 1,
        pressure: 1));
    event(PointerUpEvent(
        pointer: 3, kind: PointerDeviceKind.invertedStylus, position: center));
    await settleImage(tester);
    doc = DrawingDocument.decode(drafts.values['pen']!);
    expect(doc.frame.strokes.last.tool, DrawingTool.eraser);
    Uint8List? output;
    await tester.runAsync(() async {
      final base = await decodeDrawingBase(doc.frame.base);
      output = await exportDrawing(doc, base);
      base?.dispose();
    });
    final png = image.decodePng(output!)!;
    expect(png.getPixel(16, 16).a, 0);
    expect(png.getPixel(2, 2).b, 225);
  });
}
