// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('SRS schema constants', () {
    test('table name constants match schema identifiers', () {
      expect(kTableSrsStudy, 'srs_study');
      expect(kTableSrsChapter, 'srs_chapter');
      expect(kTableSrsDecision, 'srs_decision');
      expect(kTableSrsReviewState, 'srs_review_state');
      expect(kTableSrsReviewEvent, 'srs_review_event');
      expect(kTablePositionKnowledgeState, 'position_knowledge_state');
      expect(kTableSrsStudyRemote, 'srs_study_remote');
      expect(kTableSrsUnlockedDecision, 'srs_unlocked_decision');
      expect(kTableSrsNode, 'srs_node');
    });
  });

  group('createSrsTables', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit(noResult: true);
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> tableNames() async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'android_%' AND name != 'sqlite_sequence'",
      );
      return rows.map((r) => r['name']! as String).toSet();
    }

    test('creates all SRS tables', () async {
      expect(
        await tableNames(),
        containsAll(<String>{
          kTableSrsStudy,
          kTableSrsStudyRemote,
          kTableSrsChapter,
          kTableSrsDecision,
          kTablePositionKnowledgeState,
          kTableSrsReviewState,
          kTableSrsReviewEvent,
          kTableSrsUnlockedDecision,
          kTableSrsNode,
        }),
      );
    });

    test('creates the srs_node fen index', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_srs_node_fenKey'",
      );
      expect(rows, hasLength(1));
    });

    test('is idempotent when applied again', () async {
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit(noResult: true);
      expect(await tableNames(), contains(kTableSrsNode));
    });
  });

  group('createNodeIndexTable', () {
    test('creates srs_node table and index independently', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      final batch = db.batch();
      createNodeIndexTable(batch);
      await batch.commit(noResult: true);

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [kTableSrsNode],
      );
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_srs_node_fenKey'",
      );
      expect(tables, hasLength(1));
      expect(indexes, hasLength(1));
    });
  });
}
