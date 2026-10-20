import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/app.dart';
import 'package:imagineos/features/child/child_access.dart';
import 'package:imagineos/features/library/character_store.dart';
import 'package:imagineos/features/parent/parent_account.dart';
import 'package:imagineos/features/parent/parent_controls.dart';
import 'package:imagineos/features/parent/parent_children_screen.dart';

const code = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> session(
        {Duration duration = const Duration(minutes: 5)}) =>
    {
      'child_id': '00000000-0000-4000-8000-000000000001',
      'session_id': '00000000-0000-4000-8000-000000000002',
      'nickname': 'Fictional creator',
      'allow_export': false,
      'ai_enabled': false,
      'expires_at': DateTime.now().add(duration).toIso8601String(),
      'server_time': DateTime.now().toIso8601String(),
    };

class _Account extends ParentAccount {
  String? value = 'adult@example.invalid';
  int handoffs = 0;
  @override
  String? get email => value;
  @override
  bool get recoveringPassword => false;
  @override
  Future<void> signIn(String email, String password) async {
    value = email;
    notifyListeners();
  }

  @override
  Future<void> signUp(String email, String password) async {}
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> updatePassword(String password) async {}
  @override
  Future<void> signOut() async {
    value = null;
    notifyListeners();
  }

  @override
  Future<void> leaveForChild() async {
    handoffs++;
    await signOut();
  }
}

class _Store implements CharacterStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> show(WidgetTester tester, ChildAccess child, _Account account,
    ParentControls controls) async {
  await tester.pumpWidget(ImagineOsApp(
      account: account,
      childAccess: child,
      parentControls: controls,
      characterStore: _Store()));
  await tester.pumpAndSettle();
}

Future<void> finish(
    WidgetTester tester, ChildAccess child, ParentControls controls) async {
  child.dispose();
  controls.dispose();
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('parent selects the exact duration on a phone with enlarged text',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? approved;
    final controls = ParentControls((body, _) async {
      if (body['action'] == 'unlock')
        return {
          'grant': 'a' * 64,
          'expires_at':
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
        };
      if (body['action'] == 'lock') return {};
      if (body['action'] == 'child_approve') {
        approved = body['minutes'] as int;
        return {'code': code, 'minutes': approved};
      }
      return {
        'profiles': [
          {
            'id': session()['child_id'],
            'nickname': 'Fictional creator',
            'minutes': 1,
            'blocked': false,
            'allow_export': false
          }
        ],
        'sessions': []
      };
    });
    try {
      await controls.unlock('fictional');
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!),
          home: ParentChildrenScreen(controls: controls)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.widgetWithText(TextField, 'Allowed minutes'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(
          tester
              .getSemantics(find.widgetWithText(TextField, 'Allowed minutes'))
              .rect
              .height,
          lessThan(120));
      await tester.enterText(
          find.widgetWithText(TextField, 'Allowed minutes'), '5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('Approve next sign-in for Fictional creator').hitTestable(),
          160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve next sign-in for Fictional creator'));
      await tester.pumpAndSettle();
      expect(approved, 5);
      expect(
          find.text('Approve Fictional creator for 5 minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      controls.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  test(
      'resume waits for an in-flight verification and never extends the deadline',
      () async {
    final result = Completer<Map<String, dynamic>>();
    var checks = 0;
    final child = ChildAccess((body, _) async {
      if (body['action'] == 'login') return session();
      if (body['action'] == 'logout') return true;
      checks++;
      return result.future;
    });
    try {
      await child.signIn(code);
      final before = child.remaining;
      final checking = child.verify();
      child.suspend();
      final resuming = child.resume();
      await Future<void>.delayed(Duration.zero);
      expect(child.suspended, isTrue);
      expect(checks, 1);
      result.complete(session());
      await checking;
      await resuming;
      expect(child.suspended, isFalse);
      expect(child.remaining <= before, isTrue);
    } finally {
      child.dispose();
    }
  });
  test(
      'uncertain sign-in retries reuse their identity/secret without a new approval',
      () async {
    final calls = <Map<String, dynamic>>[];
    var failed = false;
    final child = ChildAccess((body, _) async {
      if (body['action'] == 'logout') return true;
      calls.add(body);
      if (!failed) {
        failed = true;
        throw const ChildAccessException('Connection interrupted');
      }
      return session();
    });
    try {
      await expectLater(
          child.signIn(code), throwsA(isA<ChildAccessException>()));
      await child.signIn(code);
      expect(calls[0]['request_id'], calls[1]['request_id']);
      expect(calls[0]['secret'], calls[1]['secret']);
      expect(child.active, isTrue);
    } finally {
      child.dispose();
    }
  });
  test('late approvals cannot reopen a cancelled sign-in', () async {
    final result = Completer<Map<String, dynamic>>();
    final actions = <String>[];
    final child = ChildAccess((body, _) async {
      actions.add(body['action'] as String);
      return body['action'] == 'login' ? result.future : true;
    });
    try {
      final login = child.signIn(code);
      final expected = expectLater(login, throwsA(isA<ChildAccessException>()));
      child.end();
      result.complete(session());
      await expected;
      expect(child.active, isFalse);
      expect(actions, ['login', 'logout']);
    } finally {
      child.dispose();
    }
  });
  test('revocation or failed verification locks an existing child session',
      () async {
    final child = ChildAccess((body, _) async {
      if (body['action'] == 'login') return session();
      if (body['action'] == 'logout') return true;
      throw const ChildAccessException('Approval ended',
          approvalRequired: true);
    });
    try {
      await child.signIn(code);
      await child.verify();
      expect(child.active, isFalse);
      await expectLater(child.call({'action': 'library'}),
          throwsA(isA<ChildAccessException>()));
    } finally {
      child.dispose();
    }
  });
  testWidgets(
      'child entry requires approval and signs the parent out before the workspace opens',
      (tester) async {
    final account = _Account(), controls = ParentControls((_, __) async => {});
    var reads = 0;
    final child = ChildAccess((body, _) async {
      if (body['action'] == 'login') {
        expect(account.email, isNull);
        return session();
      }
      if (body['action'] == 'library') {
        reads++;
        return {
          'creators': [
            {'id': session()['child_id'], 'nickname': 'Fictional creator'}
          ],
          'versions': []
        };
      }
      return true;
    });
    try {
      await show(tester, child, account, controls);
      expect(find.text('Child sign-in'), findsOneWidget);
      expect(find.text('Parent sign-in'), findsOneWidget);
      expect(reads, 0);
      await tester.tap(find.text('Child sign-in'));
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(account.email, isNull);
      await tester.enterText(
          find.widgetWithText(TextField, 'Parent approval code'), code);
      await tester.tap(find.text('Enter my studio'));
      await tester.pumpAndSettle();
      expect(find.text('Fictional creator’s studio'), findsOneWidget);
      expect(reads, 1);
      expect(find.text('Add creator'), findsNothing);
      expect(find.text('Add another creator'), findsNothing);
      await tester.tap(find.text('Finish session'));
      await tester.pumpAndSettle();
      expect(find.text('Parent approval code'), findsOneWidget);
      expect(child.active, isFalse);
    } finally {
      await finish(tester, child, controls);
    }
  });
  testWidgets(
      'the parent deadline automatically closes the workspace and blocks further calls',
      (tester) async {
    final account = _Account(), controls = ParentControls((_, __) async => {});
    final child = ChildAccess((body, _) async {
      if (body['action'] == 'login')
        return session(duration: const Duration(seconds: 10));
      if (body['action'] == 'library')
        return {
          'creators': [
            {'id': session()['child_id'], 'nickname': 'Fictional creator'}
          ],
          'versions': []
        };
      return true;
    });
    try {
      await show(tester, child, account, controls);
      await tester.tap(find.text('Child sign-in'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Parent approval code'), code);
      await tester.tap(find.text('Enter my studio'));
      await tester.pumpAndSettle();
      expect(child.active, isTrue);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(child.active, isFalse);
      expect(find.textContaining('Your time is up.'), findsOneWidget);
      expect(find.text('Parent approval code'), findsOneWidget);
      await expectLater(child.call({'action': 'library'}),
          throwsA(isA<ChildAccessException>()));
    } finally {
      await finish(tester, child, controls);
    }
  });
}
