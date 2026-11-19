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

  group('StudyPrefs defaults (mutation pins)', () {
    test('defaults carry the documented boolean values', () {
      const d = StudyPrefs.defaults;
      expect(d.showVariationArrows, isFalse);
      expect(d.showEvaluationGauge, isTrue);
      expect(d.showEngineLines, isTrue);
      expect(d.showBestMoveArrow, isTrue);
      expect(d.showAnnotations, isTrue);
      expect(d.showPgnComments, isTrue);
      expect(d.animateOpponentPreMove, isTrue);
      expect(d.inlineNotation, isFalse);
      expect(d.smallBoard, isFalse);
      expect(d.srsDiagnostics, isFalse);
      expect(d.showMoveHistory, isTrue);
      expect(d.collapsibleScopeGroups, isTrue);
      expect(d.dynamicRepertoireMode, isFalse);
      expect(d.compactReviewHud, isFalse);
    });

    test('isDynamicRepertoireEnabled honours the global mode flag', () {
      final prefs = StudyPrefs.defaults.copyWith(dynamicRepertoireMode: true);
      expect(prefs.isDynamicRepertoireEnabled(), isTrue);
    });

    test('isDynamicRepertoireEnabled: per-study and per-opening IDs enable when global is off', () {
      final prefs = StudyPrefs.defaults.copyWith(
        dynamicRepertoireMode: false,
        dynamicRepertoireStudyIds: {'study-a'},
        dynamicRepertoireOpeningIds: {'sicilian'},
      );

      expect(prefs.isDynamicRepertoireEnabled(studyId: 'study-a'), isTrue);
      expect(prefs.isDynamicRepertoireEnabled(studyId: 'other'), isFalse);
      expect(prefs.isDynamicRepertoireEnabled(openingFamily: 'sicilian'), isTrue);
      expect(prefs.isDynamicRepertoireEnabled(openingFamily: 'other'), isFalse);
      expect(prefs.isDynamicRepertoireEnabled(), isFalse);
      expect(prefs.isDynamicRepertoireEnabled(studyId: 'other', openingFamily: 'other'), isFalse);
    });

    test('isDynamicRepertoireEnabled: null id arguments do not match entries', () {
      final prefs = StudyPrefs.defaults.copyWith(
        dynamicRepertoireMode: false,
        dynamicRepertoireStudyIds: {'study-a'},
        dynamicRepertoireOpeningIds: {'sicilian'},
      );

      expect(prefs.isDynamicRepertoireEnabled(studyId: null), isFalse);
      expect(prefs.isDynamicRepertoireEnabled(openingFamily: null), isFalse);
    });
  });

  group('StudyPrefs migration pins', () {
    test('does not synthesize transposeScope when legacy key is absent', () {
      final json = Map<String, dynamic>.from(StudyPrefs.defaults.toJson());
      json.remove('transposeScope');
      json.remove('transposeAccept');

      // Missing transposeScope with no legacy field must fall back to the
      // fromJson default, not be forced by unrelated migration logic.
      expect(StudyPrefs.fromJson(json).transposeScope, StudyPrefs.defaults.transposeScope);
    });
  });
}
