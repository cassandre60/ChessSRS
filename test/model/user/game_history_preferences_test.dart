// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/user/game_history_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameHistoryPrefs', () {
    test('defaults to detail display mode', () {
      expect(GameHistoryPrefs.defaults.displayMode, GameHistoryDisplayMode.detail);
    });

    test('round-trips through JSON', () {
      const compact = GameHistoryPrefs(displayMode: GameHistoryDisplayMode.compact);

      expect(GameHistoryPrefs.fromJson(compact.toJson()), compact);
      expect(
        GameHistoryPrefs.fromJson(GameHistoryPrefs.defaults.toJson()),
        GameHistoryPrefs.defaults,
      );
    });

    test('fromJson falls back to default display mode when missing', () {
      expect(
        GameHistoryPrefs.fromJson(const <String, dynamic>{}).displayMode,
        GameHistoryDisplayMode.detail,
      );
    });

    test('GameHistoryDisplayMode values are stable', () {
      expect(GameHistoryDisplayMode.values, const [
        GameHistoryDisplayMode.compact,
        GameHistoryDisplayMode.detail,
      ]);
      expect(GameHistoryDisplayMode.compact.name, 'compact');
      expect(GameHistoryDisplayMode.detail.name, 'detail');
    });
  });
}
