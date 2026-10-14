// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/position_knowledge_state.dart';
import 'package:chess_srs/src/persistence/sqlite_study_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  group('schema v17 remote study linkage', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_upgrade_test_');
      dbPath = p.join(tempDir.path, 'upgrade.db');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
    });

    test('a v16 database gains the linkage table with rows intact', () async {
      // A real pre-v17 library: srs_study with no linkage table beside it.
      final oldDb = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 16,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE srs_study (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
              'createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL, '
              'isActive INTEGER NOT NULL DEFAULT 1, pgnHash TEXT)',
            );
            await db.insert('srs_study', {
              'id': 's1',
              'title': 'Old repertoire',
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-02T00:00:00.000',
              'isActive': 1,
              'pgnHash': 'abc123',
            });
          },
        ),
      );
      await oldDb.close();

      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
      });

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='srs_study_remote'",
      );
      expect(tables, hasLength(1));

      final rows = await db.query('srs_study');
      expect(rows.length, 1);
      expect(rows.first['title'], 'Old repertoire');

      // Linkage round-trips through the new table.
      final repo = SqliteStudyRepository(db);
      expect(await repo.getStudyByRemoteId('aaaaaaaa'), isNull);
      await repo.updateStudyRemoteRef(
        studyId: 's1',
        remoteStudyId: 'aaaaaaaa',
        remoteUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      final linked = await repo.getStudyByRemoteId('aaaaaaaa');
      expect(linked?.study.title, 'Old repertoire');
      expect(
        linked?.remoteUpdatedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
    });

    test('a v17 database with ghost FKs upgrades cleanly and answers persist', () async {
      // SPEC INV-001, INV-005. The long-lived user shape: V3 created
      // srs_review_state/event with FOREIGN KEY (decisionId) REFERENCES
      // srs_decision(id); later schemas dropped the clauses without ever
      // removing them from old tables. Once per-connection enforcement
      // switched on, every canonical-mirror write (a position key, never a
      // decision row) failed — freezing review after every graded answer
      // while skip kept working. Reproduced owner log, 2026-10-14.
      const ghostDecisionId = 'd1';
      const ghostCanonicalId = '019def0b09cdb13175295ed2cf3fe218125a2644';
      final legacyDb = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 17,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE srs_study (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
              'createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL, '
              'isActive INTEGER NOT NULL DEFAULT 1, pgnHash TEXT)',
            );
            await db.execute(
              'CREATE TABLE srs_decision (id TEXT PRIMARY KEY, studyId TEXT NOT NULL, '
              'chapterId TEXT NOT NULL, nodeId TEXT NOT NULL, expectedMoves TEXT NOT NULL, '
              'canonicalStateId TEXT)',
            );
            await db.execute(
              'CREATE TABLE srs_review_state (decisionId TEXT PRIMARY KEY, '
              'firstReviewedAt TEXT, lastReviewedAt TEXT, nextDueAt TEXT, '
              'repetitionCount INTEGER NOT NULL DEFAULT 0, lapseCount INTEGER NOT NULL DEFAULT 0, '
              'stability REAL NOT NULL DEFAULT 0.0, difficulty REAL NOT NULL DEFAULT 5.0, '
              'FOREIGN KEY (decisionId) REFERENCES srs_decision(id) ON DELETE CASCADE)',
            );
            await db.execute(
              'CREATE TABLE srs_review_event (id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'decisionId TEXT NOT NULL, whenTimestamp TEXT NOT NULL, result TEXT NOT NULL, '
              'oldStateJson TEXT NOT NULL, newStateJson TEXT NOT NULL, '
              'FOREIGN KEY (decisionId) REFERENCES srs_decision(id) ON DELETE CASCADE)',
            );
            await db.execute(
              'CREATE TABLE position_knowledge_state (canonicalId TEXT PRIMARY KEY, '
              'firstReviewedAt TEXT, lastReviewedAt TEXT, nextDueAt TEXT, '
              'repetitionCount INTEGER NOT NULL DEFAULT 0, lapseCount INTEGER NOT NULL DEFAULT 0, '
              'stability REAL NOT NULL DEFAULT 0.0, difficulty REAL NOT NULL DEFAULT 0.0, '
              'latencyEmaMs REAL, latencySampleCount INTEGER NOT NULL DEFAULT 0, '
              'lastExposedAt TEXT)',
            );
            await db.insert('srs_study', {
              'id': 's1',
              'title': 'Ghost study',
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-02T00:00:00.000',
              'isActive': 1,
              'pgnHash': 'abc123',
            });
            await db.insert('srs_decision', {
              'id': ghostDecisionId,
              'studyId': 's1',
              'chapterId': 'c1',
              'nodeId': 'n1',
              'expectedMoves': '[]',
              'canonicalStateId': ghostCanonicalId,
            });
            await db.insert('srs_review_state', {
              'decisionId': ghostDecisionId,
              'repetitionCount': 3,
              'lapseCount': 0,
              'stability': 2.0,
              'difficulty': 5.0,
            });
          },
        ),
      );
      await legacyDb.close();

      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
      });

      // The undeclared constraints are gone from both tables.
      for (final table in ['srs_review_state', 'srs_review_event']) {
        final fks = await db.rawQuery('PRAGMA foreign_key_list($table)');
        expect(fks, isEmpty, reason: '$table must not constrain decisionId anymore');
      }

      // Every legacy row survived with its numbers.
      final kept = await db.query(
        'srs_review_state',
        where: 'decisionId = ?',
        whereArgs: [ghostDecisionId],
      );
      expect(kept.length, 1);
      expect(kept.first['repetitionCount'], 3);
      expect(kept.first['difficulty'], 5.0);

      // The exact production failure now succeeds: a canonical mirror whose
      // id names no decision row.
      final repo = SqliteStudyRepository(db);
      await repo.saveAnswerBatch(
        knowledgeStates: [
          const PositionKnowledgeState(
            canonicalId: ghostCanonicalId,
            repetitionCount: 1,
            stability: 0.35,
            difficulty: 6.81,
          ),
        ],
        event: null,
      );
      final mirrors = await db.query(
        'srs_review_state',
        where: 'decisionId = ?',
        whereArgs: [ghostCanonicalId],
      );
      expect(mirrors.length, 1);
      expect(mirrors.first['difficulty'], 6.81);
    });
  });
}
