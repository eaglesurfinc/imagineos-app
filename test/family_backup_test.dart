import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:imagineos/features/library/character_store.dart';
import 'package:imagineos/features/parent/family_backup.dart';
import 'package:imagineos/features/parent/parent_controls.dart';
import 'package:imagineos/features/parent/parent_privacy_screen.dart';
import 'package:imagineos/features/story/illustration_contract.dart';
import 'package:imagineos/features/story/story_draft_store.dart';
import 'package:imagineos/features/story/story_project.dart';
import 'package:imagineos/features/story/story_project_store.dart';

String id() => const Uuid().v4();
const words = '  My exact words 🌈\n<script>fictional</script>  ';
final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=');

class MemoryCharacters implements CharacterStore {
  MemoryCharacters(this.family, this.creators, this.rows);
  final String family;
  final List<CreatorProfile> creators;
  final List<Map<String, dynamic>> rows;
  var writes = 0;
  bool loseResponse = false;
  @override
  Future<CharacterLibrary> load() async =>
      CharacterLibrary(creators, rows.map(OriginalVersion.fromJson).toList());
  @override
  Future<Uint8List> read(OriginalVersion version) async => png;
  @override
  Future<void> save(OriginalDraft draft) async {
    if (rows.any((r) => r['request_id'] == draft.requestId)) return;
    writes++;
    final character = draft.characterId ?? id();
    rows.add({
      'request_id': draft.requestId,
      'character_id': character,
      'child_profile_id': draft.childId,
      'version_id': id(),
      'version_number':
          rows.where((r) => r['character_id'] == character).length + 1,
      'name': draft.name,
      'object_path': '$family/${draft.requestId}',
      'sha256': draft.file.checksum,
      'state': 'ready',
      'deleting_character': false,
      'mime_type': draft.file.mimeType,
      'byte_size': draft.file.bytes.length
    });
    if (loseResponse) {
      loseResponse = false;
      throw StateError('lost save response');
    }
  }

  @override
  Future<void> finish(OriginalVersion v) async {}
  @override
  Future<void> discard(OriginalVersion v) async {}
  @override
  Future<void> deleteCharacter(String c, {String? versionId}) async {}
  @override
  Future<void> addCreator(String nickname) async {}
}

class MemoryStories implements StoryProjectStore {
  final saved = <String, StoryProject>{};
  @override
  Future<List<StoryProject>> load({int offset = 0}) async =>
      saved.values.skip(offset).take(20).toList();
  @override
  Future<int> save(StoryProject s) async {
    saved[s.id] = s.copy(revision: 1);
    return 1;
  }

  @override
  Future<void> delete(StoryProject s) async {}
}

class MemoryPages implements StoryDraftStore {
  final saved = <String, SavedStoryDraft>{};
  @override
  Future<List<SavedStoryDraft>> load(StoryReference r) async =>
      saved.values.where((p) => p.reference.sameAs(r)).toList();
  @override
  Future<int> save(SavedStoryDraft p) async {
    saved[p.pageId] = p;
    return 1;
  }
}

class Fixture {
  final family = id(), child = id(), other = id(), character = id();
  late final file = OriginalFile(png, 'image/png');
  late final originals = List.generate(2, (n) {
    final asset = id();
    return <String, dynamic>{
      'request_id': asset,
      'character_id': character,
      'child_profile_id': child,
      'version_id': id(),
      'version_number': n + 1,
      'name': 'Fictional drawing ${n + 1}',
      'object_path': '$family/$asset',
      'sha256': file.checksum,
      'state': 'ready',
      'deleting_character': false,
      'mime_type': 'image/png',
      'byte_size': png.length
    };
  });
  late final original = OriginalVersion.fromJson(originals.first);
  late final story = StoryProject(
      id: id(),
      childId: child,
      title: '  Child title  ',
      format: StoryFormat.comic,
      revision: 1,
      panels: [
        StoryPanel(
            id: id(),
            reference: StoryReference.fromVersion(original),
            characterName: original.name,
            versionNumber: 1,
            scene: 'walk',
            dialogue: words,
            narration: '\n End ')
      ]);
  late final snapshot = <String, dynamic>{
    'family_id': family,
    'children': [
      {'id': child, 'nickname': 'Fictional creator'},
      {'id': other, 'nickname': 'Recovery creator'}
    ],
    'originals': originals,
    'stories': [story.toJson()],
    'pages': [
      {
        'page_id': id(),
        'source_id': original.requestId,
        'character_id': original.characterId,
        'version_id': original.versionId,
        'sha256': file.checksum,
        'scene': 'walk',
        'dialogue': words,
        'narration': '\n End ',
        'revision': 1
      }
    ]
  };
  late final characters = MemoryCharacters(
      family,
      [
        CreatorProfile(child, 'Fictional creator'),
        CreatorProfile(other, 'Recovery creator')
      ],
      originals.map((r) => Map<String, dynamic>.of(r)).toList());
  final stories = MemoryStories(), pages = MemoryPages();
  late final controls = ParentControls((body, _) async {
    if (body['action'] == 'unlock')
      return {
        'grant': 'a' * 64,
        'expires_at':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
      };
    if (body['action'] == 'lock') return {};
    if (body['action'] == 'recovery_snapshot')
      return jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    if (body['action'] == 'privacy_pause') paused = body['paused'] as bool;
    return {
      'family_id': family,
      'pilot_enabled': false,
      'consent_status': 'not_configured',
      'retention_status': 'not_configured',
      'child_access_paused': paused
    };
  });
  bool paused = false;
  late final recovery = FamilyRecovery(
      controls: controls,
      characters: characters,
      stories: stories,
      pages: pages);
  Future<FamilyBackup> archive() => FamilyBackup.create(
      snapshot, {for (final r in originals) r['request_id']: file});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  setUp(() async {
    f = Fixture();
    await f.controls.unlock('fictional');
  });
  tearDown(() => f.controls.dispose());
  test(
      'portable backup round-trips original bytes, exact words, layouts and pinned versions',
      () async {
    final archive = await f.recovery.backup((_) {});
    final reopened = await FamilyBackup.decode(archive.encode());
    expect(reopened.stories.single.panels.single.dialogue, words);
    expect(reopened.stories.single.title, '  Child title  ');
    expect(reopened.stories.single.format, StoryFormat.comic);
    expect(reopened.stories.single.panels.single.reference.versionId,
        f.original.versionId);
    expect(reopened.images[f.original.requestId]!.bytes, png);
    expect(reopened.pages.single['dialogue'], words);
    final json = utf8.decode(reopened.encode());
    expect(json, isNot(contains('grant')));
    expect(json, isNot(contains('password')));
  });
  test(
      'corruption, missing images, unknown metadata and duplicate sources fail validation',
      () async {
    final archive = await f.archive();
    final bytes = archive.encode();
    bytes[bytes.length ~/ 2] ^= 1;
    await expectLater(FamilyBackup.decode(bytes), throwsFormatException);
    await expectLater(
        FamilyBackup.create(f.snapshot, {}), throwsFormatException);
    f.snapshot['provider_key'] = 'fictional-forbidden';
    await expectLater(f.archive(), throwsFormatException);
    f.snapshot.remove('provider_key');
    f.originals.add(Map.of(f.originals.first));
    await expectLater(f.archive(), throwsFormatException);
  });
  test('backup refuses family work changed during download', () async {
    await expectLater(f.recovery.backup((_) {
      f.snapshot['stories'] = [];
    }), throwsA(isA<ParentControlsException>()));
  });
  test(
      'interrupted recovery resumes with stable IDs and cannot duplicate or alter originals',
      () async {
    final archive = await f.archive();
    f.characters.loseResponse = true;
    await expectLater(f.recovery.restore(archive, f.child, f.other, (_) {}),
        throwsStateError);
    await f.recovery.restore(archive, f.child, f.other, (_) {});
    await f.recovery.restore(archive, f.child, f.other, (_) {});
    expect(f.characters.writes, 2);
    expect(f.characters.rows.length, 4);
    final restored = f.stories.saved.values.single;
    expect(restored.panels.single.dialogue, words);
    expect(restored.title, f.story.title);
    expect(restored.childId, f.other);
    expect(restored.panels.single.reference.versionId,
        isNot(f.original.versionId));
    expect(f.pages.saved.length, 1);
    expect(f.pages.saved.values.single.dialogue, words);
    expect(f.characters.rows.take(2).toList(), f.originals);
  });
  test(
      'changed recovery copies are preserved and missing historical artwork is never substituted',
      () async {
    final archive = await f.archive();
    await f.recovery.restore(archive, f.child, f.other, (_) {});
    final restored = f.stories.saved.values.single;
    f.stories.saved[restored.id] = restored.copy(title: 'Child edited this');
    await expectLater(f.recovery.restore(archive, f.child, f.other, (_) {}),
        throwsFormatException);
    expect(f.stories.saved[restored.id]!.title, 'Child edited this');
    (f.snapshot['stories'] as List).single['panels'][0]['source_available'] =
        false;
    final missing = await f.archive();
    final before = f.characters.writes;
    await expectLater(f.recovery.restore(missing, f.child, f.other, (_) {}),
        throwsFormatException);
    expect(f.characters.writes, before);
    expect(missing.stories.single.panels.single.dialogue, words);
  });
  test(
      'parent lock or a different owning family prevents backup/recovery writes',
      () async {
    final archive = await f.archive();
    f.controls.lock();
    await expectLater(f.recovery.restore(archive, f.child, f.other, (_) {}),
        throwsA(isA<ParentControlsException>()));
    expect(f.characters.writes, 0);
    await f.controls.unlock('fictional');
    f.snapshot['family_id'] = id();
    final foreign = Fixture();
    await foreign.controls.unlock('fictional');
    try {
      await expectLater(
          foreign.recovery.restore(archive, f.child, f.other, (_) {}),
          throwsA(isA<ParentControlsException>()));
      expect(foreign.characters.writes, 0);
    } finally {
      foreign.controls.dispose();
    }
  });
  testWidgets(
      'phone privacy flow requires explicit pause and recovery choices, and hides data when locked',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final archive = (await tester.runAsync(f.archive))!;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!),
        home: ParentPrivacyScreen(
            recovery: f.recovery, pickBackup: () async => archive)));
    await tester.pumpAndSettle();
    Future<void> tap(String text) async {
      await tester.scrollUntilVisible(find.text(text).hitTestable(), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(text).hitTestable());
      await tester.pumpAndSettle();
    }

    await tap('Pause all child access');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(f.paused, isFalse);
    await tap('Pause all child access');
    await tester.tap(find.text('Pause child access'));
    await tester.pumpAndSettle();
    expect(f.paused, isTrue);
    await tap('Review backup');
    await tester.scrollUntilVisible(
        find.text(
            'Backup integrity and image checks passed. Nothing has been imported.'),
        160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Backup integrity and image checks passed. Nothing has been imported.'),
        findsOneWidget);
    expect(f.characters.writes, 0);
    f.controls.lock();
    await tester.pumpAndSettle();
    expect(find.textContaining('Parent settings are locked.'), findsOneWidget);
    expect(find.text('Recover saved copies'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
