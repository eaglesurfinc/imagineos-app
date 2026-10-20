import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imagineos/features/parent/parent_controls.dart';

void main() {
  test('lock fences late unlock responses and revokes their capability',
      () async {
    final response = Completer<Map<String, dynamic>>();
    final calls = <String>[];
    final controls = ParentControls((body, grant) async {
      calls.add(body['action'] as String);
      return body['action'] == 'unlock' ? response.future : {};
    });
    addTearDown(controls.dispose);
    final unlocking = controls.unlock('fictional');
    final expected =
        expectLater(unlocking, throwsA(isA<ParentControlsException>()));
    controls.lock();
    response.complete({
      'grant': 'a' * 64,
      'expires_at':
          DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
    });
    await expected;
    expect(controls.unlocked, isFalse);
    expect(calls, ['unlock', 'lock']);
  });
  test('locked and malformed grants cannot reach overview or deletion',
      () async {
    var calls = 0;
    final controls = ParentControls((body, grant) async {
      calls++;
      return {'grant': 'bad'};
    });
    addTearDown(controls.dispose);
    await expectLater(
        controls.overview(), throwsA(isA<ParentControlsException>()));
    await expectLater(
        controls.deleteAccount(), throwsA(isA<ParentControlsException>()));
    expect(calls, 0);
    await expectLater(
        controls.unlock('fictional'), throwsA(isA<ParentControlsException>()));
    expect(controls.unlocked, isFalse);
  });
  test('leaving parent settings discards in-flight private results', () async {
    final result = Completer<Map<String, dynamic>>();
    final controls = ParentControls((body, grant) async {
      if (body['action'] == 'unlock')
        return {
          'grant': 'a' * 64,
          'expires_at':
              DateTime.now().add(const Duration(minutes: 5)).toIso8601String()
        };
      if (body['action'] == 'lock') return {};
      return result.future;
    });
    addTearDown(controls.dispose);
    await controls.unlock('fictional');
    final deleting = controls.deleteAccount();
    final expected =
        expectLater(deleting, throwsA(isA<ParentControlsException>()));
    controls.lock();
    result.complete({'deleted': true, 'pending': false});
    await expected;
  });
}
