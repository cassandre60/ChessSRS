// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/search_history.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_container.dart';

const signedInUser = AuthUser(
  token: 'token-a',
  user: LightUser(id: UserId('user-a'), name: 'User A'),
);

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  test('saveTerm prepends new terms and persists them under the signed-in key', () async {
    final container = await makeContainer(authUser: signedInUser);
    final prefs = TestLichessBinding.instance.sharedPreferences;

    await container.read(searchHistoryProvider.notifier).saveTerm('e4');
    await container.read(searchHistoryProvider.notifier).saveTerm('d4');

    expect(container.read(searchHistoryProvider).history.toList(), ['d4', 'e4']);
    final stored = jsonDecode(prefs.getString('search.history.user-a')!) as Map<String, dynamic>;
    expect(stored['history'], ['d4', 'e4']);
  });

  test('saveTerm ignores an existing term without rewriting storage', () async {
    final container = await makeContainer(authUser: signedInUser);
    final prefs = TestLichessBinding.instance.sharedPreferences;
    final notifier = container.read(searchHistoryProvider.notifier);

    await notifier.saveTerm('e4');
    await notifier.saveTerm('d4');
    await prefs.setString(
      'search.history.user-a',
      jsonEncode({
        'history': ['SENTINEL'],
      }),
    );

    await notifier.saveTerm('e4');

    expect(container.read(searchHistoryProvider).history.toList(), ['d4', 'e4']);
    expect(prefs.getString('search.history.user-a'), '{"history":["SENTINEL"]}');
  });

  test('saveTerm keeps at most maxHistory terms and drops the oldest', () async {
    final container = await makeContainer(authUser: signedInUser);
    final notifier = container.read(searchHistoryProvider.notifier);

    for (var i = 0; i <= SearchHistory.maxHistory; i++) {
      await notifier.saveTerm('term-$i');
    }

    expect(container.read(searchHistoryProvider).history.toList(), [
      'term-10',
      'term-9',
      'term-8',
      'term-7',
      'term-6',
      'term-5',
      'term-4',
      'term-3',
      'term-2',
      'term-1',
    ]);
  });

  test('build restores the persisted history for the current user', () async {
    final prefs = TestLichessBinding.instance.sharedPreferences;
    await prefs.setString(
      'search.history.user-a',
      jsonEncode({
        'history': ['Nf6', 'e4'],
      }),
    );

    final container = await makeContainer(authUser: signedInUser);

    expect(container.read(searchHistoryProvider).history.toList(), ['Nf6', 'e4']);
  });

  test('clear empties the in-memory and persisted history', () async {
    final container = await makeContainer(authUser: signedInUser);
    final prefs = TestLichessBinding.instance.sharedPreferences;
    final notifier = container.read(searchHistoryProvider.notifier);
    await notifier.saveTerm('e4');
    await notifier.saveTerm('d4');

    await notifier.clear();

    expect(container.read(searchHistoryProvider).history, isEmpty);
    final stored = jsonDecode(prefs.getString('search.history.user-a')!) as Map<String, dynamic>;
    expect(stored['history'], isEmpty);
  });

  test('signed-in and anonymous searches use separate storage keys', () async {
    final signedIn = await makeContainer(authUser: signedInUser);
    final anonymous = await makeContainer();
    final prefs = TestLichessBinding.instance.sharedPreferences;

    await signedIn.read(searchHistoryProvider.notifier).saveTerm('signed');
    await anonymous.read(searchHistoryProvider.notifier).saveTerm('anon');

    expect(jsonDecode(prefs.getString('search.history.user-a')!) as Map<String, dynamic>, {
      'history': ['signed'],
    });
    expect(jsonDecode(prefs.getString('search.history.**anon**')!) as Map<String, dynamic>, {
      'history': ['anon'],
    });
    expect(signedIn.read(searchHistoryProvider).history.toList(), ['signed']);
    expect(anonymous.read(searchHistoryProvider).history.toList(), ['anon']);
  });
}
