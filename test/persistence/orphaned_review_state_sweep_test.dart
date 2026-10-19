// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-005.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/persistence/orphaned_review_state_sweep.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late String dbPath;
  late Database db;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_sweep_');
    dbPath = p.join(tempDir.path, 'sweep.db');
    db = await openAppDatabase(databaseFactoryFfi, dbPath);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The open database enforces the declared foreign keys, so the parents must exist.
  Future<void> seedDecision({required String decisionId, required String? canonicalStateId}) async {
    await db.insert(kTableSrsStudy, {
      'id': 'study-$decisionId',
      'title': 'Study',
      'createdAt': '2026-09-16T12:00:00.000Z',
      'updatedAt': '2026-09-16T12:00:00.000Z',
      'isActive': 1,
    });
    await db.insert(kTableSrsChapter, {
      'id': 'chapter-$decisionId',
      'studyId': 'study-$decisionId',
      'sourceOrder': 0,
      'createdAt': '2026-09-16T12:00:00.000Z',
    });
    await db.insert(kTableSrsDecision, {
      'id': decisionId,
      'studyId': 'study-$decisionId',
      'chapterId': 'chapter-$decisionId',
      'nodeId': 'node-$decisionId',
      'expectedMoves': '[]',
      'canonicalStateId': canonicalStateId,
    });
  }

  Future<void> seedKnowledge(String canonicalId) {
    return db.insert(kTablePositionKnowledgeState, {
      'canonicalId': canonicalId,
      'firstReviewedAt': '2026-09-01T10:00:00.000Z',
      'lastReviewedAt': '2026-09-15T10:00:00.000Z',
      'nextDueAt': '2026-09-20T10:00:00.000Z',
      'repetitionCount': 6,
      'lapseCount': 0,
      'stability': 3.0,
      'difficulty': 5.0,
      'latencyEmaMs': null,
      'latencySampleCount': 0,
    });
  }

  Future<void> seedMirror(String key, {int repetitions = 1}) {
    return db.insert(kTableSrsReviewState, {
      'decisionId': key,
      'firstReviewedAt': '2026-09-01T10:00:00.000Z',
      'lastReviewedAt': '2026-09-15T10:00:00.000Z',
      'nextDueAt': '2026-09-20T10:00:00.000Z',
      'repetitionCount': repetitions,
      'lapseCount': 0,
      'stability': 1.0,
      'difficulty': 5.0,
    });
  }

  /// Seeds the four reachability shapes at once: a stranded mirror, one named by a decision's
  /// `canonicalStateId`, one named by a decision's `id`, and one named by a knowledge row.
  Future<void> seedAllShapes() async {
    await seedDecision(decisionId: 'decision-1', canonicalStateId: 'canonical-kept');
    await seedDecision(decisionId: 'decision-2', canonicalStateId: null);
    await seedKnowledge('knowledge-only');
    await seedMirror('stranded-key', repetitions: 9);
    await seedMirror('canonical-kept', repetitions: 3);
    await seedMirror('decision-2', repetitions: 4);
    await seedMirror('knowledge-only', repetitions: 2);
  }

  group('orphaned review-state sweep on upgrade', () {
    test('a v19 database with stranded rows is swept on the upgrade', () async {
      // A v19 database exactly as the v14/v16 rekeys left it: knowledge rows moved to new
      // canonical ids, mirrors left behind under the old ones. Nothing reads a mirror that
      // neither a decision (by id or canonical id) nor a knowledge row names any more.
      await seedAllShapes();

      // Rewind the version so the next open takes the upgrade path.
      await db.execute('PRAGMA user_version = 19');
      await db.close();

      db = await openAppDatabase(databaseFactoryFfi, dbPath);

      expect(
        await db.query(kTableSrsReviewState, where: 'decisionId = ?', whereArgs: ['stranded-key']),
        isEmpty,
        reason: 'no decision and no knowledge row names this key: nothing can read it',
      );
      for (final key in ['canonical-kept', 'decision-2', 'knowledge-only']) {
        expect(
          await db.query(kTableSrsReviewState, where: 'decisionId = ?', whereArgs: [key]),
          hasLength(1),
          reason: '$key is still reachable and must survive the sweep',
        );
      }
    });
  });

  group('sweepOrphanedReviewStates', () {
    test('removes only the rows nothing names', () async {
      await seedAllShapes();

      final swept = await sweepOrphanedReviewStates(db);

      expect(swept, 1, reason: 'exactly the stranded mirror is unreachable');
      expect(await db.query(kTableSrsReviewState), hasLength(3));
      expect(
        await db.query(kTableSrsReviewState, where: 'decisionId = ?', whereArgs: ['stranded-key']),
        isEmpty,
      );
    });

    test('does nothing when the SRS tables are absent', () async {
      // Fixture databases created for other migrations may not carry the SRS
      // tables at all; the sweep must pass them through rather than throw.
      final bare = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(bare.close);

      expect(await sweepOrphanedReviewStates(bare), 0);
    });
  });
}
