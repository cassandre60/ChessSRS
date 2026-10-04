// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stored-preference migrations: old installs carry keys the current code
/// has replaced. Dropping their values silently would flip behavior they
/// chose, so each replacement maps the legacy value explicitly.
void main() {
  group('StudyPrefs migrations', () {
    test('legacy transposeAccept bool maps to the transpose scope', () {
      final off = StudyPrefs.defaults.toJson()
        ..remove('transposeScope')
        ..['transposeAccept'] = false;
      expect(StudyPrefs.fromJson(off).transposeScope, TransposeScope.off);

      final on = StudyPrefs.defaults.toJson()
        ..remove('transposeScope')
        ..['transposeAccept'] = true;
      expect(StudyPrefs.fromJson(on).transposeScope, TransposeScope.inScope);
    });

    test('current preferences round-trip unchanged', () {
      const prefs = StudyPrefs.defaults;
      expect(StudyPrefs.fromJson(prefs.toJson()), prefs);
    });

    test('review order defaults to by-line', () {
      expect(StudyPrefs.defaults.reviewOrder, ReviewOrder.byLine);
    });
  });
}
