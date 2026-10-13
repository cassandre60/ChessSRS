// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('SRS SQLite schema indexes', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
    });

    tearDown(() async {
      await db.close();
    });

    test('all declared indexes exist in sqlite_master', () async {
      final rows = await db.rawQuery(
        "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_autoindex_%'",
      );
      final indexes = {for (final r in rows) r['name']! as String: r['tbl_name']! as String};

      expect(indexes['idx_srs_study_pgnHash'], equals(kTableSrsStudy));
      expect(indexes['idx_srs_chapter_studyId'], equals(kTableSrsChapter));
      expect(indexes['idx_srs_decision_studyId'], equals(kTableSrsDecision));
      expect(indexes['idx_srs_decision_chapterId'], equals(kTableSrsDecision));
      expect(indexes['idx_srs_decision_canonicalStateId'], equals(kTableSrsDecision));
      expect(
        indexes['idx_position_knowledge_state_nextDueAt'],
        equals(kTablePositionKnowledgeState),
      );
      expect(indexes['idx_srs_review_state_nextDueAt'], equals(kTableSrsReviewState));
      expect(indexes['idx_srs_review_event_decisionId'], equals(kTableSrsReviewEvent));
      expect(indexes['idx_srs_review_event_whenTimestamp'], equals(kTableSrsReviewEvent));
    });

    test('query plans use indexes for high-frequency lookups', () async {
      // 1. Study lookup by pgnHash
      final studyPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsStudy WHERE pgnHash = ?',
        ['some-hash'],
      );
      expect(
        studyPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_study_pgnHash'),
      );

      // 2. Chapter lookup by studyId
      final chapterPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsChapter WHERE studyId = ?',
        ['study-1'],
      );
      expect(
        chapterPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_chapter_studyId'),
      );

      // 3. Decision lookups by studyId, chapterId, canonicalStateId
      final decStudyPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsDecision WHERE studyId = ?',
        ['study-1'],
      );
      expect(
        decStudyPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_decision_studyId'),
      );

      final decChapterPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsDecision WHERE chapterId = ?',
        ['chapter-1'],
      );
      expect(
        decChapterPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_decision_chapterId'),
      );

      final decCanonicalPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsDecision WHERE canonicalStateId = ?',
        ['state-1'],
      );
      expect(
        decCanonicalPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_decision_canonicalStateId'),
      );

      // 4. Review event lookup by decisionId
      final eventDecPlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsReviewEvent WHERE decisionId = ?',
        ['dec-1'],
      );
      expect(
        eventDecPlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_review_event_decisionId'),
      );

      // 5. Review event lookup by whenTimestamp
      final eventTimePlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsReviewEvent WHERE whenTimestamp >= ?',
        ['2026-10-13T00:00:00Z'],
      );
      expect(
        eventTimePlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_review_event_whenTimestamp'),
      );

      // 6. Dues queries by nextDueAt
      final knowledgeDuePlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTablePositionKnowledgeState WHERE nextDueAt <= ?',
        ['2026-10-13T12:00:00Z'],
      );
      expect(
        knowledgeDuePlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_position_knowledge_state_nextDueAt'),
      );

      final reviewStateDuePlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTableSrsReviewState WHERE nextDueAt <= ?',
        ['2026-10-13T12:00:00Z'],
      );
      expect(
        reviewStateDuePlan.map((r) => r['detail']! as String).join(' '),
        contains('idx_srs_review_state_nextDueAt'),
      );

      // 7. Primary key lookups use PRIMARY KEY index
      final pkKnowledgePlan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $kTablePositionKnowledgeState WHERE canonicalId = ?',
        ['canonical-1'],
      );
      expect(
        pkKnowledgePlan.map((r) => r['detail']! as String).join(' '),
        anyOf(contains('PRIMARY KEY'), contains('sqlite_autoindex_position_knowledge_state')),
      );
    });
  });
}
