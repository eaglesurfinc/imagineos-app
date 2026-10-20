import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/app.dart';
import 'package:imagineos/features/parent/parent_account.dart';
import 'package:imagineos/features/parent/parent_controls.dart';
import 'package:imagineos/features/parent/parent_access_screen.dart';

class FakeAccount extends ParentAccount {
  int childCount = 2;
  String? signedInEmail;
  bool fail = false;
  bool recovery = false;
  int requests = 0;
  int deleteRequests = 0;
  @override
  String? get email => signedInEmail;
  @override
  bool get recoveringPassword => recovery;
  @override
  Future<void> signIn(String email, String password) async {
    requests++;
    if (fail) throw Exception('sensitive underlying failure');
    signedInEmail = email;
    notifyListeners();
  }

  @override
  Future<void> signUp(String email, String password) async {
    requests++;
  }

  @override
  Future<void> resetPassword(String email) async {
    requests++;
  }

  @override
  Future<void> updatePassword(String password) async {
    recovery = false;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    signedInEmail = null;
    notifyListeners();
  }
}

ParentControls fakeControls(FakeAccount account) =>
    ParentControls((body, grant) async {
      if (body['action'] == 'unlock')
        return {
          'grant': 'a' * 64,
          'expires_at':
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
        };
      if (body['action'] == 'lock') return {};
      if (body['action'] == 'start_delete' ||
          body['action'] == 'continue_delete') {
        account.deleteRequests++;
        return {'deleted': true, 'pending': false};
      }
      if (account.fail)
        throw const ParentControlsException('Overview unavailable');
      return {
        'child_profiles': account.childCount,
        'characters': 1,
        'versions': 1,
        'original_files': 1,
        'page_drafts': 0,
        'stories': 0,
        'provider_connections': 0,
        'deletion_pending': false,
        'generation_enabled': false
      };
    });
Future<void> show(WidgetTester tester, FakeAccount account) async {
  final controls = fakeControls(account);
  addTearDown(controls.dispose);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ParentAccessScreen(account: account, controls: controls))));
  await tester.pumpAndSettle();
}

Future<void> unlock(WidgetTester tester) async {
  await tester.enterText(
      find.widgetWithText(TextField, 'Parent password'), 'fictional');
  await tester.tap(find.text('Unlock parent settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'backgrounding locks parent settings and clears the password field',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await show(tester, account);
    await unlock(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('Unlock parent settings'), findsOneWidget);
    expect(find.text('Child profiles: 2'), findsNothing);
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Parent password'))
            .controller!
            .text,
        isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets('five-minute expiry relocks the parent interface',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await show(tester, account);
    await unlock(tester);
    await tester.pump(const Duration(minutes: 5, seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Unlock parent settings'), findsOneWidget);
    expect(find.text('Your family data'), findsNothing);
  });
  testWidgets(
      'whole-family deletion requires explicit scope; cancellation does nothing',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await show(tester, account);
    await unlock(tester);
    await tester.ensureVisible(find.text('Delete my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Permanently delete family'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Keep family account'));
    await tester.pumpAndSettle();
    expect(account.deleteRequests, 0);
    expect(account.email, isNotNull);
  });
  testWidgets(
      'restored parent session hides family details until password unlock',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await show(tester, account);
    expect(find.text('Child profiles: 2'), findsNothing);
    await unlock(tester);
    expect(find.text('Child profiles: 2'), findsOneWidget);
    await tester.tap(find.text('Lock parent settings'));
    await tester.pumpAndSettle();
    expect(find.text('Child profiles: 2'), findsNothing);
    account.childCount = 3;
    await unlock(tester);
    expect(find.text('Child profiles: 3'), findsOneWidget);
  });
  testWidgets('a password recovery event opens the parent panel',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await tester.pumpWidget(ImagineOsApp(account: account));
    await tester.pumpAndSettle();
    expect(find.text('No characters yet.'), findsOneWidget);
    account.recovery = true;
    account.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('New password'), findsOneWidget);
  });
  testWidgets('invalid fields do not make authentication requests',
      (tester) async {
    final account = FakeAccount();
    await show(tester, account);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid parent email.'), findsOneWidget);
    expect(account.requests, 0);
  });
  testWidgets('confirmation signup keeps the parent signed out',
      (tester) async {
    final account = FakeAccount();
    await show(tester, account);
    await tester.tap(find.text('Create a parent account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Parent email'),
        'adult@example.invalid');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'fictional-password');
    await tester
        .tap(find.widgetWithText(FilledButton, 'Create parent account'));
    await tester.pumpAndSettle();
    expect(find.text('Check your email to confirm your account, then sign in.'),
        findsOneWidget);
    expect(account.email, isNull);
  });
  testWidgets('restored session shows family and signout clears family context',
      (tester) async {
    final account = FakeAccount()..signedInEmail = 'adult@example.invalid';
    await show(tester, account);
    await unlock(tester);
    expect(find.text('Child profiles: 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your family is ready'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
  testWidgets('sign-in failure is safe and can be retried', (tester) async {
    final account = FakeAccount()..fail = true;
    await show(tester, account);
    await tester.enterText(find.widgetWithText(TextFormField, 'Parent email'),
        'adult@example.invalid');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'fictional-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Could not complete that request'), findsOneWidget);
    expect(find.textContaining('sensitive underlying failure'), findsNothing);
    account.fail = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock parent settings'), findsOneWidget);
  });
  testWidgets('overview errors keep parent settings locked from other actions',
      (tester) async {
    final account = FakeAccount()
      ..signedInEmail = 'adult@example.invalid'
      ..fail = true;
    await show(tester, account);
    await unlock(tester);
    expect(find.text('Retry family overview'), findsOneWidget);
    expect(find.text('Delete my account'), findsNothing);
    account.fail = false;
    await tester.tap(find.text('Retry family overview'));
    await tester.pumpAndSettle();
    expect(find.text('Child profiles: 2'), findsOneWidget);
  });
  testWidgets('recovery session requires a new password before family view',
      (tester) async {
    final account = FakeAccount()
      ..signedInEmail = 'adult@example.invalid'
      ..recovery = true;
    await show(tester, account);
    expect(find.text('New password'), findsOneWidget);
    expect(find.textContaining('Your family is ready'), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'),
        'new-fictional-password');
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock parent settings'), findsOneWidget);
  });
}
