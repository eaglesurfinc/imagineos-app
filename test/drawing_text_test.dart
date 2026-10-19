import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'package:imagineos/features/drawing/drawing_fonts.dart';
import 'package:imagineos/features/drawing/drawing_renderer.dart';
import 'package:imagineos/features/drawing/drawing_studio.dart';

import 'support/memory_drawing_drafts.dart';
import 'drawing_interactions_test.dart' show settleImage;

void main() {
  testWidgets(
      'all eight bundled original fonts match provenance and paint colored PNG text',
      (tester) async {
    final manifest =
        jsonDecode(File('assets/fonts/manifest.json').readAsStringSync());
    expect(manifest['fonts'].length, drawingFonts.length);
    final rendered = <String>{};
    for (final font in manifest['fonts']) {
      final bytes = File(font['path']).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), font['sha256']);
      final loader = FontLoader(font['family'])
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await tester.runAsync(loader.load);
      final stroke = DrawingStroke(
          tool: DrawingTool.text,
          points: const [DrawingPoint(12, 12)],
          color: 0xffe4475d,
          width: 10,
          opacity: 1,
          text: 'Hello Moon!',
          fontFamily: font['family'],
          fontSize: 28,
          textWidth: 230);
      final doc = DrawingDocument(
          width: 256, height: 128, frame: DrawingFrame(strokes: [stroke]));
      final restored =
          DrawingDocument.decode(doc.encode()).frame.strokes.single;
      expect(restored.text, 'Hello Moon!');
      expect(restored.fontFamily, font['family']);
      final png = await tester.runAsync(() => exportDrawing(doc, null));
      final pixels = image.decodePng(png!)!;
      expect(pixels.getPixel(0, 0).a, 0);
      expect(
          pixels.any((p) => p.a > 128 && p.r == 228 && p.g == 71 && p.b == 93),
          true);
      rendered.add(sha256.convert(png).toString());
    }
    expect(rendered.length, 8,
        reason: 'font choices must render as eight distinct faces');
  });

  testWidgets(
      'text can be placed, edited, recolored, undone and recovered exactly',
      (tester) async {
    final drafts = MemoryDrawingDrafts();
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'text', drafts: drafts)));
    await settleImage(tester);
    await tester.ensureVisible(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    await tester.scrollUntilVisible(canvas, -200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    final rect = tester.getRect(canvas);
    final point = rect.topLeft + Offset(rect.width * .12, rect.height * .12);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    const words = '  MY Moon!\n  Stay exactly.  ';
    await tester.enterText(
        find.widgetWithText(TextField, 'Your exact text'), words);
    await tester.ensureVisible(find.byTooltip('Text color E4475D'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text color E4475D'));
    await tester.ensureVisible(find.text('Place text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place text'));
    await settleImage(tester);
    var doc = DrawingDocument.decode(drafts.values['text']!);
    expect(doc.frame.strokes.single.text, words);
    expect(doc.frame.strokes.single.color, 0xffe4475d);
    expect(doc.frame.strokes.single.fontFamily, 'Nunito');
    // Hit an existing text item with the Text tool; editing replaces that item.
    await tester.tapAt(point + const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Canvas text'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Text color 3E80D6'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text color 3E80D6'));
    await tester.ensureVisible(find.text('Place text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place text'));
    await settleImage(tester);
    doc = DrawingDocument.decode(drafts.values['text']!);
    expect(doc.frame.strokes.length, 1);
    expect(doc.frame.strokes.single.text, words);
    expect(doc.frame.strokes.single.color, 0xff3e80d6);
    await tester.tap(find.byTooltip('Undo'));
    await settleImage(tester);
    doc = DrawingDocument.decode(drafts.values['text']!);
    expect(doc.frame.strokes.single.color, 0xffe4475d);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: DrawingStudio(draftKey: 'text', drafts: drafts)));
    await settleImage(tester);
    expect(
        DrawingDocument.decode(drafts.values['text']!)
            .frame
            .strokes
            .single
            .text,
        words);
    expect(tester.takeException(), null);
  });
}
