import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;
import 'package:imagineos/app.dart';
import 'package:imagineos/features/library/character_library_screen.dart';
import 'package:imagineos/features/library/character_store.dart';
import 'package:imagineos/features/library/character_editor.dart';
import 'package:imagineos/features/parent/parent_account.dart';

final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGNw09iCFTEMLQkAOOxIgSesf3AAAAAASUVORK5CYII=');
OriginalVersion version(int number,
        {String state = 'ready',
        String name = 'Space friend',
        bool deletingCharacter = false}) =>
    OriginalVersion.fromJson({
      'request_id': 'request-$number',
      'character_id': 'character-1',
      'child_profile_id': 'creator-1',
      'version_id': 'version-$number',
      'version_number': number,
      'name': name,
      'object_path': 'family/file-$number',
      'sha256': OriginalFile(imageBytes, 'image/png').checksum,
      'state': state,
      'deleting_character': deletingCharacter,
    });

class FakeStore extends CharacterStore {
  final versions = <OriginalVersion>[];
  final retryKeys = <String>[];
  final reads = <String>[];
  final drafts = <OriginalDraft>[];
  bool failSaveOnce = false;
  bool failDeleteOnce = false;
  final deletionCalls = <String>[];
  @override
  Future<void> deleteCharacter(String characterId, {String? versionId}) async {
    deletionCalls.add(versionId ?? 'all');
    if (failDeleteOnce) {
      failDeleteOnce = false;
      for (var i = 0; i < versions.length; i++) {
        final row = versions[i];
        if (row.characterId == characterId &&
            (versionId == null || row.versionId == versionId)) {
          versions[i] = version(row.number,
              state: 'deleting',
              name: row.name,
              deletingCharacter: versionId == null);
        }
      }
      throw Exception('interrupted storage cleanup');
    }
    versions.removeWhere((row) =>
        row.characterId == characterId &&
        (versionId == null || row.versionId == versionId));
  }

  @override
  Future<CharacterLibrary> load() async => CharacterLibrary(
      const [CreatorProfile('creator-1', 'Fictional creator')],
      List.of(versions));
  @override
  Future<void> addCreator(String nickname) async {}
  @override
  Future<void> save(OriginalDraft draft) async {
    retryKeys.add(draft.requestId);
    drafts.add(draft);
    if (failSaveOnce) {
      failSaveOnce = false;
      throw Exception('network failure');
    }
    versions.removeWhere((row) => row.requestId == draft.requestId);
    final number = versions.isEmpty ? 1 : versions.first.number + 1;
    versions.insert(0, version(number, name: draft.name.trim()));
  }

  @override
  Future<void> finish(OriginalVersion pending) async {
    versions[versions.indexOf(pending)] = version(pending.number);
  }

  @override
  Future<void> discard(OriginalVersion pending) async {
    versions.remove(pending);
  }

  @override
  Future<Uint8List> read(OriginalVersion saved) async {
    reads.add(saved.versionId);
    return imageBytes;
  }
}

class TestAccount extends ParentAccount {
  String? currentEmail = 'adult@example.invalid';
  @override
  String? get email => currentEmail;
  @override
  bool get recoveringPassword => false;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> updatePassword(String password) async {}
  @override
  Future<void> signOut() async {
    currentEmail = null;
    notifyListeners();
  }

  @override
  Future<FamilySummary> loadFamily() async => const FamilySummary(1);
}

Future<void> showLibrary(WidgetTester tester, FakeStore store,
    {bool signedIn = true, double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Scaffold(
          body: CharacterLibraryScreen(
        store: store,
        signedIn: signedIn,
        chooseFile: () async => OriginalFile(imageBytes, 'image/png'),
      ))));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label,
    {bool imageWork = false}) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 250,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  if (imageWork) {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'whole character deletion requires confirmation and removes all versions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FakeStore()..versions.addAll([version(2), version(1)]);
    await showLibrary(tester, store, textScale: 2);
    await tap(tester, 'Space friend');
    await tap(tester, 'Delete character');
    await tap(tester, 'Cancel');
    expect(store.deletionCalls, isEmpty);
    expect(store.versions.length, 2);
    await tap(tester, 'Delete character');
    await tap(tester, 'Delete permanently');
    expect(store.deletionCalls, ['all']);
    expect(store.versions, isEmpty);
    await tap(tester, 'Refresh library');
    expect(find.text('No characters yet.'), findsOneWidget);
  });
  testWidgets('deleting a selected older version keeps the newer version',
      (tester) async {
    final store = FakeStore()
      ..versions.addAll([version(2, name: 'Updated friend'), version(1)]);
    await showLibrary(tester, store);
    await tap(tester, 'Updated friend');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version 1: Space friend').last);
    await tester.pumpAndSettle();
    await tap(tester, 'Delete selected version');
    expect(find.text('Delete version 1?'), findsOneWidget);
    await tap(tester, 'Delete permanently');
    expect(store.deletionCalls, ['version-1']);
    expect(store.versions.single.versionId, 'version-2');
    await tap(tester, 'Updated friend');
    expect(find.text('Delete selected version'), findsNothing);
    expect(find.textContaining('only saved version'), findsOneWidget);
  });
  testWidgets(
      'interrupted deletion is visible and can finish after returning to library',
      (tester) async {
    final store = FakeStore()
      ..versions.add(version(1))
      ..failDeleteOnce = true;
    await showLibrary(tester, store);
    await tap(tester, 'Space friend');
    await tap(tester, 'Delete character');
    await tap(tester, 'Delete permanently');
    expect(find.textContaining('Deletion did not finish'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, 'Finish deletion');
    expect(store.deletionCalls, ['all', 'all']);
    expect(store.versions, isEmpty);
  });
  test(
      'binary download missing-object wrapper is distinguished from denied access',
      () {
    expect(
        isMissingOriginal(const StorageException(
            '{"statusCode":"404","error":"not_found","message":"Object not found","code":"NoSuchKey"}',
            statusCode: '400')),
        isTrue);
    expect(
        isMissingOriginal(
            const StorageException('Permission denied', statusCode: '403')),
        isFalse);
    expect(
        isMissingOriginal(const StorageException('{"code":"AccessDenied"}',
            statusCode: '400')),
        isFalse);
    expect(
        isMissingOriginal(
            const StorageException('Invalid request', statusCode: '400')),
        isFalse);
  });
  test('oversized header dimensions are rejected before pixel decoding',
      () async {
    final bytes = Uint8List.fromList(imageBytes);
    final header = ByteData.sublistView(bytes);
    header.setUint32(16, 5000, Endian.big);
    header.setUint32(20, 5000, Endian.big);
    var crc = 0xffffffff;
    for (final byte in bytes.sublist(12, 29)) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
      }
    }
    header.setUint32(29, crc ^ 0xffffffff, Endian.big);
    await expectLater(
        validateOriginal(bytes),
        throwsA(isA<FormatException>().having((error) => error.message,
            'pixel limit', contains('16 megapixels'))));
  });
  testWidgets(
      'reselecting an interrupted file reuses its reserved upload identity',
      (tester) async {
    final store = FakeStore()..versions.add(version(1, state: 'pending'));
    await showLibrary(tester, store);
    await tap(tester, 'Choose file again');
    await tap(tester, 'Retry save');
    expect(store.retryKeys.single, 'request-1');
    expect(store.versions.length, 1);
    expect(store.versions.single.state, 'ready');
  });
  test('valid original bytes are preserved and hashed', () async {
    final original = await validateOriginal(imageBytes);
    expect(original.bytes, imageBytes);
    expect(original.mimeType, 'image/png');
    expect(original.checksum, OriginalFile(imageBytes, 'image/png').checksum);
  });
  test('oversized and non-image files are rejected', () async {
    await expectLater(validateOriginal(Uint8List(maxOriginalBytes + 1)),
        throwsFormatException);
    await expectLater(
        validateOriginal(
            Uint8List.fromList('<svg>not accepted</svg>'.codeUnits)),
        throwsFormatException);
    await expectLater(
        validateOriginal(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
        throwsFormatException);
  });
  testWidgets('signed-out library offers no private records', (tester) async {
    final store = FakeStore()..versions.add(version(1));
    await showLibrary(tester, store, signedIn: false);
    expect(find.textContaining('Sign in under For parents'), findsOneWidget);
    expect(find.text('Space friend'), findsNothing);
  });
  testWidgets('failed save keeps image and retries the identical draft',
      (tester) async {
    final store = FakeStore()..failSaveOnce = true;
    await showLibrary(tester, store);
    await tester.enterText(
        find.widgetWithText(TextField, 'Character name'), 'Space friend');
    await tap(tester, 'Choose drawing');
    await tap(tester, 'Save character');
    expect(
        find.textContaining('Your original selection is kept'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tap(tester, 'Retry save');
    expect(store.retryKeys.length, 2);
    expect(store.retryKeys[0], store.retryKeys[1]);
    expect(store.versions.length, 1);
    await tap(tester, 'Space friend');
    expect(store.reads.last, 'version-1');
  });
  testWidgets(
      'reopened library shows latest version and can reopen earlier original',
      (tester) async {
    final store = FakeStore()
      ..versions.addAll([version(2, name: 'Updated friend'), version(1)]);
    await showLibrary(tester, store);
    await tap(tester, 'Updated friend');
    expect(store.reads.last, 'version-2');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version 1: Space friend').last);
    await tester.pumpAndSettle();
    expect(store.reads.last, 'version-1');
    await tap(tester, 'Add new version');
    expect(find.text('Add a new version'), findsOneWidget);
    expect(store.versions.length, 2);
  });
  testWidgets('unfinished saves can be finished or discarded after reopening',
      (tester) async {
    final store = FakeStore()..versions.add(version(1, state: 'pending'));
    await showLibrary(tester, store);
    await tap(tester, 'Finish save');
    expect(store.versions.single.state, 'ready');
    store.versions.add(version(2, state: 'pending'));
    await tap(tester, 'Refresh library');
    await tap(tester, 'Discard unfinished');
    expect(store.versions.length, 1);
    expect(store.versions.single.state, 'ready');
  });
  testWidgets('signout closes an open original and removes private image state',
      (tester) async {
    final store = FakeStore()..versions.add(version(1));
    final account = TestAccount();
    await tester
        .pumpWidget(ImagineOsApp(account: account, characterStore: store));
    await tester.pumpAndSettle();
    await tap(tester, 'Space friend');
    expect(find.byType(Image), findsOneWidget);
    await tap(tester, 'Crop and edit', imageWork: true);
    await account.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CharacterEditor), findsNothing);
    expect(find.textContaining('Sign in under For parents'), findsOneWidget);
  });

  testWidgets('edited upload saves a new version and retries identical bytes',
      (tester) async {
    final store = FakeStore()..versions.add(version(1));
    await showLibrary(tester, store);
    await tap(tester, 'Space friend');
    await tap(tester, 'Crop and edit', imageWork: true);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(store.drafts, isEmpty);
    await tap(tester, 'Crop and edit', imageWork: true);
    await tap(tester, 'Flip horizontally', imageWork: true);
    await tap(tester, 'Use edited drawing');
    expect(find.byType(CharacterEditor), findsNothing);
    expect(store.drafts, isEmpty);
    store.failSaveOnce = true;
    await tap(tester, 'Save new version');
    await tap(tester, 'Retry save');
    expect(store.drafts.first.characterId, 'character-1');
    expect(store.drafts.first.childId, 'creator-1');
    expect(identical(store.drafts.first, store.drafts.last), isTrue);
    expect(store.drafts.first.file.mimeType, 'image/png');
    expect(store.versions.map((row) => row.number), [2, 1]);
    expect(store.versions.last.versionId, 'version-1');
  });

  testWidgets('phone editor crops, undoes and resets at enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: CharacterEditor(source: imageBytes),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    final horizontal = find.byKey(const ValueKey('Keep horizontal area'));
    await tester.scrollUntilVisible(horizontal, 200);
    final slider = tester.widget<RangeSlider>(horizontal);
    await tester.ensureVisible(horizontal);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(horizontal) + const Offset(26, 24));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.widget<RangeSlider>(horizontal).values.start, greaterThan(0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(tester.widget<RangeSlider>(horizontal).values.end, 99);
    slider.onChanged!(const RangeValues(25, 75));
    await tester.pump();
    await tap(tester, 'Apply crop', imageWork: true);
    Future<int> width() async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      return image
          .decodePng(
              (tester.widget<Image>(find.byType(Image)).image as MemoryImage)
                  .bytes)!
          .width;
    }

    expect(await width(), 4);
    await tap(tester, 'Undo', imageWork: true);
    expect(await width(), 8);
    await tap(tester, 'Rotate right', imageWork: true);
    await tap(tester, 'Reset edits', imageWork: true);
    expect(await width(), 8);
    expect(tester.takeException(), isNull);
  });
}
