import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/app.dart';
import 'package:imagineos/features/parent/parent_account.dart';
import 'package:imagineos/features/parent/parent_access_screen.dart';

class FakeAccount extends ParentAccount {
  String? signedInEmail;
  bool fail = false;
  bool recovery = false;
  int requests = 0;
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

  @override
  Future<FamilySummary> loadFamily() async {
    if (fail) throw Exception('database error');
    return const FamilySummary(2);
  }
}

Future<void> show(WidgetTester tester, FakeAccount account) async {
  await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ParentAccessScreen(account: account))));
  await tester.pumpAndSettle();
}

void main() {
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
    expect(
        find.text('Your family is ready. Child profiles: 2.'), findsOneWidget);
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
    expect(
        find.text('Your family is ready. Child profiles: 2.'), findsOneWidget);
  });
  testWidgets('family-load errors offer retry and signout', (tester) async {
    final account = FakeAccount()
      ..signedInEmail = 'adult@example.invalid'
      ..fail = true;
    await show(tester, account);
    expect(find.text('Could not load your family. Please try again.'),
        findsOneWidget);
    account.fail = false;
    await tester.tap(find.text('Retry family'));
    await tester.pumpAndSettle();
    expect(
        find.text('Your family is ready. Child profiles: 2.'), findsOneWidget);
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
    expect(
        find.text('Your family is ready. Child profiles: 2.'), findsOneWidget);
  });
}
