import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:imagineos/features/drawing/drawing_document.dart';
import 'support/memory_drawing_drafts.dart';
import 'package:imagineos/features/drawing/drawing_studio.dart';
import 'package:imagineos/features/library/character_store.dart';
import 'package:imagineos/theme.dart';

Future<void> imageWork(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 100; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'draw, undo/redo, export transparent PNG and restore device strokes',
      (tester) async {
    final drafts = MemoryDrawingDrafts();
    OriginalFile? output;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      output = await Navigator.push<OriginalFile>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DrawingStudio(
                                  draftKey: 'drawing-test', drafts: drafts)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await imageWork(tester);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    await tester.dragFrom(
        tester.getCenter(canvas) - const Offset(60, 0), const Offset(120, 30));
    await tester.pump(const Duration(milliseconds: 400));
    await imageWork(tester);
    expect(
        DrawingDocument.decode(drafts.values['drawing-test']!)
            .frame
            .strokes
            .length,
        1);
    await tester.tap(find.byTooltip('Undo'));
    await imageWork(tester);
    await tester.tap(find.byTooltip('Redo'));
    await imageWork(tester);
    await tester.tap(find.text('Use drawing'));
    await imageWork(tester);
    expect(output, isNotNull);
    final png = image.decodePng(output!.bytes)!;
    expect([png.width, png.height], [1024, 1024]);
    expect(png.getPixel(0, 0).a, 0);
    expect(png.any((pixel) => pixel.a > 0), isTrue);
    await tester.tap(find.text('Open'));
    await imageWork(tester);
    expect(find.textContaining('Device draft restored'), findsOneWidget);
  });
  testWidgets('phone controls reflow at 2x text and keyboard draws on canvas',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final drafts = MemoryDrawingDrafts();
    await tester.pumpWidget(MaterialApp(
        theme: imagineOsTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: DrawingStudio(draftKey: 'keyboard-test', drafts: drafts)));
    await imageWork(tester);
    final canvas = find.byKey(const ValueKey('drawing-canvas'));
    await tester.tap(canvas);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 400));
    await imageWork(tester);
    expect(
        DrawingDocument.decode(drafts.values['keyboard-test']!)
            .frame
            .strokes
            .length,
        2);
    await tester.scrollUntilVisible(find.text('Custom color'), 300);
    expect(find.text('Custom color'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
