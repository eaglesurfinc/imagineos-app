import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/story/illustration_contract.dart';
import 'package:imagineos/features/story/story_composer.dart';
import 'package:imagineos/features/story/story_draft_screen.dart';
import 'package:imagineos/features/story/story_preview.dart';
import 'package:imagineos/features/library/character_store.dart';

import 'support/memory_drawing_drafts.dart';

const exactWords = '  I  said: “GO!” 🌈\n\nمرحبا بالعالم\nDoN’t change me.  ';
final fixture = jsonDecode(
    File('backend/tests/fixtures/illustration_request.json')
        .readAsStringSync()) as Map<String, dynamic>;
final source = StoryReference.fromJson(fixture['character']);
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=');

class TestGateway implements IllustrationGateway {
  final calls = <IllustrationRequest>[];
  Future<IllustrationResult> Function()? respond;
  @override
  Future<IllustrationResult> check(IllustrationRequest request) {
    calls.add(request);
    return respond?.call() ??
        Future.value(const IllustrationResult(
            IllustrationState.disabled, 'GENERATION_DISABLED'));
  }
}

class FailingDrafts extends MemoryDrawingDrafts {
  bool failing = false;
  @override
  Future<void> write(String key, String value, int session) async {
    if (failing) throw StateError('Device quota');
    await super.write(key, value, session);
  }
}

StoryComposer composer(MemoryDrawingDrafts drafts, TestGateway gateway) =>
    StoryComposer(
        reference: source,
        drafts: drafts,
        draftKey:
            drafts.key('adult@example.invalid', 'story.${source.versionId}'),
        gateway: gateway);

void main() {
  test('Dart and server share the canonical hash without page text', () {
    final request = IllustrationRequest.fromJson(fixture);
    expect(
        request.fingerprint,
        File('backend/tests/fixtures/illustration_fingerprint.txt')
            .readAsStringSync()
            .trim());
    expect(request.toJson(), fixture);
    expect(request.toJson().containsKey('dialogue'), false);
    expect(request.toJson().containsKey('narration'), false);
  });

  test(
      'strict disabled contract rejects generated text/images, changed identity or live status',
      () {
    final request = IllustrationRequest.fromJson(fixture);
    final valid = <String, dynamic>{
      'contract_version': 1,
      'request_id': request.requestId,
      'trace_id': request.traceId,
      'fingerprint': request.fingerprint,
      'status': 'disabled',
      'code': 'GENERATION_DISABLED',
      'retryable': false,
      'output': null,
      'cost_micros': 0,
      'provider_attempts': 0
    };
    expect(IllustrationResult.parse(valid, request).state,
        IllustrationState.disabled);
    for (final overrides in [
      {
        'output': {'url': 'https://image.invalid', 'dialogue': 'Rewritten'}
      },
      {'status': 'succeeded'},
      {'cost_micros': 1},
      {'provider_attempts': 1},
      {'request_id': 'different'},
      {'trace_id': 'different'},
      {'fingerprint': 'different'},
      {'contract_version': 2},
      {'retryable': true},
      {'extra': true},
    ]) {
      expect(() => IllustrationResult.parse({...valid, ...overrides}, request),
          throwsFormatException);
    }
  });

  test(
      'exact whitespace, line breaks and Unicode survive disabled check and draft reload',
      () async {
    final drafts = MemoryDrawingDrafts(), gateway = TestGateway();
    final first = composer(drafts, gateway);
    await first.load();
    first.update(
        scene: fixture['scene_direction'],
        dialogue: exactWords,
        narration: '  Narrator\n  ');
    await first.check();
    expect(first.result!.state, IllustrationState.disabled);
    expect(first.canCheck, false);
    final restored = composer(drafts, gateway);
    await restored.load();
    expect(restored.dialogue, exactWords);
    expect(restored.narration, '  Narrator\n  ');
    expect(restored.scene, fixture['scene_direction']);
    expect(restored.reference.sameAs(source), true);
    expect(restored.request!.toJson(), gateway.calls.single.toJson());
    expect(restored.canCheck, false);
    // A text edit does not create a different illustration job.
    restored.update(dialogue: 'New exact words');
    expect(restored.request!.requestId, first.request!.requestId);
    restored.update(scene: 'Another setting');
    expect(restored.request, null);
    expect(restored.canCheck, true);
    first.dispose();
    restored.dispose();
  });

  test(
      'checkpoint happens before a call; failed device writes retain fields and send nothing',
      () async {
    final drafts = FailingDrafts()..failing = true;
    final gateway = TestGateway();
    final model = composer(drafts, gateway);
    await model.load();
    model.update(scene: 'Flying', dialogue: exactWords);
    await model.check();
    expect(model.recoveryFailed, true);
    expect(model.dialogue, exactWords);
    expect(gateway.calls, isEmpty);
    expect(model.attempts, 0);
    drafts.failing = false;
    model.update(dialogue: exactWords);
    await model.checkpoint();
    final reopened = composer(drafts, gateway);
    await reopened.load();
    expect(reopened.corruptDraft, false);
    expect(reopened.dialogue, exactWords);
    reopened.dispose();
    await model.check();
    expect(model.result!.state, IllustrationState.disabled);
    model.dispose();
  });

  test(
      'interrupted job reuses identity, with at most two manual attempts and no automatic retries',
      () async {
    final drafts = MemoryDrawingDrafts(), gateway = TestGateway();
    final pending = Completer<IllustrationResult>();
    gateway.respond = () => pending.future;
    final first = composer(drafts, gateway);
    await first.load();
    first.update(scene: 'Flying', dialogue: exactWords);
    final running = first.check();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.calls.length, 1);
    final restored = composer(drafts, gateway);
    await restored.load();
    first.dispose();
    expect(restored.result!.code, 'INTERRUPTED');
    expect(restored.request!.requestId, gateway.calls.single.requestId);
    gateway.respond = () async => throw StateError('network');
    await restored.check();
    expect(gateway.calls.length, 2);
    expect(gateway.calls[0].toJson(), gateway.calls[1].toJson());
    expect(restored.canCheck, false);
    expect(restored.dialogue, exactWords);
    await restored.check();
    expect(gateway.calls.length, 2);
    pending.complete(const IllustrationResult(
        IllustrationState.disabled, 'GENERATION_DISABLED'));
    await running;
    restored.dispose();
  });

  test(
      'account invalidation fences late responses and clears both drawing and story drafts',
      () async {
    final drafts = MemoryDrawingDrafts(), gateway = TestGateway();
    final pending = Completer<IllustrationResult>();
    gateway.respond = () => pending.future;
    final model = composer(drafts, gateway);
    await model.load();
    model.update(scene: 'Flying', dialogue: exactWords);
    final running = model.check();
    await Future<void>.delayed(Duration.zero);
    await drafts.invalidate();
    pending.complete(const IllustrationResult(
        IllustrationState.disabled, 'GENERATION_DISABLED'));
    await running;
    expect(drafts.values, isEmpty);
    expect(model.active, false);
    model.dispose();
  });

  test(
      'invalid or mismatched local records remain untouched until explicit discard',
      () async {
    final drafts = MemoryDrawingDrafts();
    final reading = composer(drafts, TestGateway());
    drafts.values[reading.draftKey] = '{unreadable';
    await reading.load();
    expect(reading.corruptDraft, true);
    reading.update(dialogue: 'overwrite');
    expect(await reading.checkpoint(), false);
    expect(drafts.values[reading.draftKey], '{unreadable');
    expect(await reading.discard(), true);
    expect(drafts.values, isEmpty);
    reading.dispose();
  });

  testWidgets(
      'fixed text geometry retains all long exact text, including trailing newlines',
      (tester) async {
    final longWords = List.filled(60, exactWords).join('\n');
    final short = StoryTextLayout(exactWords, '');
    final long = StoryTextLayout(longWords, '\n');
    expect(long.height, greaterThan(short.height));
    expect(long.dialogue, longWords);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 320,
                    child: StoryPreview(
                        image: png, dialogue: longWords, narration: '\n'))))));
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text(longWords));
    expect(text.maxLines, null);
    expect(text.overflow, null);
    expect(text.textScaler, TextScaler.noScaling);
    expect(tester.takeException(), null);
  });

  testWidgets(
      'phone at 2x text supports exact input, preview, disabled result and restoration',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final version = OriginalVersion.fromJson({
      'character_id': source.characterId,
      'version_id': source.versionId,
      'request_id': source.assetId,
      'sha256': source.sha,
      'child_profile_id': 'creator',
      'version_number': 2,
      'name': 'Moon friend',
      'object_path': 'private/original',
      'state': 'ready'
    });
    final drafts = MemoryDrawingDrafts(), gateway = TestGateway();
    Widget screen() => MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: StoryDraftScreen(
            version: version,
            image: png,
            draftScope: 'test',
            drafts: drafts,
            gateway: gateway));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Scene direction'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.widgetWithText(TextField, 'Scene direction'), '  Flying\n  ');
    await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Exact dialogue'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(
        find.widgetWithText(TextField, 'Exact dialogue'), exactWords);
    final check = find.text('Check illustration availability');
    await tester.scrollUntilVisible(check, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.textContaining('Illustration is turned off.'), findsOneWidget);
    expect(gateway.calls.single.scene, '  Flying\n  ');
    expect(gateway.calls.single.reference.versionId, version.versionId);
    expect(jsonEncode(gateway.calls.single.toJson()).contains('DoN’t'), false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(TextField, 'Exact dialogue'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Exact dialogue'))
            .controller!
            .text,
        exactWords);
    expect(tester.takeException(), null);
  });
}
