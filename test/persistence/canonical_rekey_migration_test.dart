// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-005.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/position_knowledge_state.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/persistence/canonical_rekey_migration.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('rekeyCanonicalReviewState', () {
    late Directory tempDir;
    late String dbPath;
    late Database db;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_rekey_');
      dbPath = p.join(tempDir.path, 'rekey.db');
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
    });

    tearDown(() async {
      await db.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Inserts the minimum a decision needs: a chapter whose tree carries the position identity,
    /// and the decision pointing at a node in it.
    Future<void> seed({
      required String studyId,
      required String chapterId,
      required String nodeId,
      required String fenKey,
      required String expectedMoves,
      required String? canonicalStateId,
    }) async {
      await db.insert(kTableSrsStudy, {
        'id': studyId,
        'title': 'Study',
        'createdAt': '2026-09-16T12:00:00.000Z',
        'updatedAt': '2026-09-16T12:00:00.000Z',
        'isActive': 1,
      });
      await db.insert(kTableSrsChapter, {
        'id': chapterId,
        'studyId': studyId,
        'sourceOrder': 0,
        'startingFen': fenKey,
        'createdAt': '2026-09-16T12:00:00.000Z',
        'treeJson': jsonEncode(
          repertoireNodeToJson(RepertoireNode(id: nodeId, fen: fenKey, fenKey: fenKey)),
        ),
      });
      await db.insert(kTableSrsDecision, {
        'id': 'decision-$nodeId',
        'studyId': studyId,
        'chapterId': chapterId,
        'nodeId': nodeId,
        'expectedMoves': expectedMoves,
        'canonicalStateId': canonicalStateId,
      });
    }

    Future<void> seedState(String canonicalId, {int repetitions = 1, double stability = 1.0}) {
      return db.insert(kTablePositionKnowledgeState, {
        'canonicalId': canonicalId,
        'firstReviewedAt': '2026-09-01T10:00:00.000Z',
        'lastReviewedAt': '2026-09-15T10:00:00.000Z',
        'nextDueAt': '2026-09-20T10:00:00.000Z',
        'repetitionCount': repetitions,
        'lapseCount': 0,
        'stability': stability,
        'difficulty': 5.0,
        'latencyEmaMs': null,
        'latencySampleCount': 0,
      });
    }

    Future<Map<String, Object?>> stateFor(String canonicalId) async {
      final rows = await db.query(
        kTablePositionKnowledgeState,
        where: 'canonicalId = ?',
        whereArgs: [canonicalId],
      );
      return rows.isEmpty ? const {} : rows.first;
    }

    test('moves knowledge state from the old key to the new one', () async {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      final oldId = canonicalKey(fenKey, 'e2e4');
      final newId = canonicalKeyForPosition(fenKey, ['e2e4', 'd2d4']);

      await seed(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        fenKey: fenKey,
        expectedMoves: encodeExpectedMoves([
          const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          const RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ]),
        canonicalStateId: oldId,
      );
      await seedState(oldId, repetitions: 7, stability: 12.5);

      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 1);
      expect(result.statesRemapped, 1);
      expect(result.statesMerged, 0);

      // The state is reachable under the key the importer will now generate.
      final moved = await stateFor(newId);
      expect(moved, isNotEmpty, reason: 'the state must not be orphaned by the key change');
      expect(moved['repetitionCount'], 7);
      expect(moved['stability'], 12.5);

      // And the decision points at it.
      final decisions = await db.query(kTableSrsDecision);
      expect(decisions.single['canonicalStateId'], newId);

      // Nothing left behind under the old key.
      expect(await stateFor(oldId), isEmpty);
    });

    test('merges two old keys that resolve to one, keeping the more practised state', () async {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      // Both decisions ask the same two-move question at the same position, so under the new rule
      // they are one item. Both old ids differ from the new one, so both genuinely move.
      final oldIdA = canonicalKey(fenKey, 'e2e4');
      const oldIdB = 'legacy-per-decision-state';
      final newId = canonicalKeyForPosition(fenKey, ['e2e4', 'd2d4']);
      expect(oldIdA, isNot(equals(newId)));

      for (final (index, oldId) in [oldIdA, oldIdB].indexed) {
        await seed(
          studyId: 'study-$index',
          chapterId: 'chapter-$index',
          nodeId: 'node-$index',
          fenKey: fenKey,
          expectedMoves: encodeExpectedMoves([
            const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            const RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
          ]),
          canonicalStateId: oldId,
        );
      }
      await seedState(oldIdA, repetitions: 3, stability: 4.0);
      await seedState(oldIdB, repetitions: 11, stability: 2.0);

      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 2);
      expect(result.statesRemapped, 1);
      expect(result.statesMerged, 1, reason: 'two old ids collapsed onto one new id');

      final merged = await stateFor(newId);
      expect(merged, isNotEmpty);
      expect(
        merged['repetitionCount'],
        11,
        reason: 'the more practised history is the one worth keeping',
      );
    });

    test('a single-move position keeps its existing key, so its state is never touched', () async {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      // With one accepted move the old and new formulations produce the same string, so positions
      // that only ever had one accepted move need no rewrite at all.
      final id = canonicalKey(fenKey, 'e2e4');
      expect(id, canonicalKeyForPosition(fenKey, ['e2e4']));

      await seed(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        fenKey: fenKey,
        expectedMoves: encodeExpectedMoves([const RepertoireMove(from: 'e2', to: 'e4', san: 'e4')]),
        canonicalStateId: id,
      );
      await seedState(id, repetitions: 9, stability: 20.0);

      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 0);
      expect((await stateFor(id))['repetitionCount'], 9);
      expect((await stateFor(id))['stability'], 20.0);
    });

    test('is a no-op when every id is already on the new format', () async {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      final newId = canonicalKeyForPosition(fenKey, ['e2e4']);

      await seed(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        fenKey: fenKey,
        expectedMoves: encodeExpectedMoves([const RepertoireMove(from: 'e2', to: 'e4', san: 'e4')]),
        canonicalStateId: newId,
      );
      await seedState(newId, repetitions: 4);

      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 0);
      expect(result.statesRemapped, 0);
      expect(result.skipped, 0);
      expect((await stateFor(newId))['repetitionCount'], 4);
    });

    test('leaves a decision alone when its position cannot be recovered', () async {
      const oldId = 'state-with-no-tree';
      await seed(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoves: encodeExpectedMoves([const RepertoireMove(from: 'e2', to: 'e4', san: 'e4')]),
        canonicalStateId: oldId,
      );
      // A tree that cannot be decoded must not take the upgrade down with it.
      await db.update(
        kTableSrsChapter,
        {'treeJson': '{not json'},
        where: 'id = ?',
        whereArgs: ['chapter-1'],
      );
      await seedState(oldId, repetitions: 5);

      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 0);
      expect(result.skipped, 1);
      expect(
        (await stateFor(oldId))['repetitionCount'],
        5,
        reason: 'an unreadable tree must not cost the user their state',
      );
    });

    test('merging onto one key skips a decision that was never reviewed', () async {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      final oldIdA = canonicalKey(fenKey, 'e2e4');
      const oldIdB = 'legacy-never-reviewed';
      final newId = canonicalKeyForPosition(fenKey, ['e2e4', 'd2d4']);

      await seed(
        studyId: 'study-0',
        chapterId: 'chapter-0',
        nodeId: 'node-0',
        fenKey: fenKey,
        expectedMoves: encodeExpectedMoves([
          const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          const RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ]),
        canonicalStateId: oldIdA,
      );
      await seed(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        fenKey: fenKey,
        expectedMoves: encodeExpectedMoves([
          const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          const RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ]),
        canonicalStateId: oldIdB,
      );
      // Only the first decision was ever reviewed; the second has no row.
      await seedState(oldIdA, repetitions: 3, stability: 4.0);

      // Must not throw on the missing row.
      final result = await rekeyCanonicalReviewState(db);

      expect(result.decisionsRemapped, 2);
      final merged = await stateFor(newId);
      expect(merged, isNotEmpty);
      expect(merged['repetitionCount'], 3);
    });
  });
  group('backfillCanonicalStatesFromLegacy', () {
    late Directory tempDir;
    late String dbPath;
    late Database db;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_backfill_');
      dbPath = p.join(tempDir.path, 'backfill.db');
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
    });

    tearDown(() async {
      await db.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Seeds a decision, optionally with a legacy per-occurrence review state.
    Future<void> seedDecision({
      required String decisionId,
      required String canonicalId,
      int repetitions = 0,
      double stability = 0,
    }) async {
      await db.insert(kTableSrsStudy, {
        'id': 'study-1',
        'title': 'S',
        'createdAt': '2026-09-16T12:00:00.000Z',
        'updatedAt': '2026-09-16T12:00:00.000Z',
        'isActive': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert(kTableSrsDecision, {
        'id': decisionId,
        'studyId': 'study-1',
        'chapterId': 'chapter-1',
        'nodeId': 'node-$decisionId',
        'expectedMoves': '[]',
        'canonicalStateId': canonicalId,
      });
      if (repetitions > 0) {
        await db.insert(kTableSrsReviewState, {
          'decisionId': decisionId,
          'firstReviewedAt': '2026-09-01T10:00:00.000Z',
          'lastReviewedAt': '2026-09-15T10:00:00.000Z',
          'nextDueAt': '2026-09-20T10:00:00.000Z',
          'repetitionCount': repetitions,
          'lapseCount': 0,
          'stability': stability,
          'difficulty': 5.0,
        });
      }
    }

    test('a legacy state becomes the canonical state for its position', () async {
      await seedDecision(
        decisionId: 'occ-1',
        canonicalId: 'canon-1',
        repetitions: 6,
        stability: 12,
      );
      expect(await db.query(kTablePositionKnowledgeState), isEmpty);

      final result = await backfillCanonicalStatesFromLegacy(db);

      expect(result.statesCreated, 1);
      final created = (await db.query(kTablePositionKnowledgeState)).single;
      expect(created['canonicalId'], 'canon-1');
      expect(created['repetitionCount'], 6);
      expect(created['stability'], 12.0);
    });

    test('a transposition collapses onto one state, keeping the more practised', () async {
      // Two occurrences of the same position, each carrying its own legacy state, and no
      // canonical row: without this the position would be scheduled from two different sets of
      // numbers depending on which occurrence asked.
      await seedDecision(
        decisionId: 'occ-a',
        canonicalId: 'canon-shared',
        repetitions: 2,
        stability: 30,
      );
      await seedDecision(
        decisionId: 'occ-b',
        canonicalId: 'canon-shared',
        repetitions: 9,
        stability: 4,
      );

      final result = await backfillCanonicalStatesFromLegacy(db);

      expect(result.statesCreated, 1);
      expect(result.collisionsMerged, 1, reason: 'two legacy rows resolved to one position');

      final rows = await db.query(kTablePositionKnowledgeState);
      expect(rows, hasLength(1), reason: 'one position, one memory item');
      expect(
        rows.single['repetitionCount'],
        9,
        reason: 'the further-advanced history is the one worth keeping',
      );
    });

    test('an existing canonical state is never overwritten by a legacy one', () async {
      await seedDecision(
        decisionId: 'occ-1',
        canonicalId: 'canon-1',
        repetitions: 2,
        stability: 30,
      );
      await db.insert(kTablePositionKnowledgeState, {
        'canonicalId': 'canon-1',
        'firstReviewedAt': null,
        'lastReviewedAt': '2026-09-18T10:00:00.000Z',
        'nextDueAt': '2026-10-18T10:00:00.000Z',
        'repetitionCount': 40,
        'lapseCount': 0,
        'stability': 99,
        'difficulty': 3,
        'latencyEmaMs': null,
        'latencySampleCount': 0,
      });

      final result = await backfillCanonicalStatesFromLegacy(db);

      expect(result.statesCreated, 0, reason: 'nothing was missing');
      final row = (await db.query(kTablePositionKnowledgeState)).single;
      expect(row['repetitionCount'], 40, reason: 'the newer canonical row stands');
    });

    test('legacy state for a decision with no canonical id is left alone', () async {
      await seedDecision(decisionId: 'occ-1', canonicalId: 'canon-1', repetitions: 5);
      await db.update(
        kTableSrsDecision,
        {'canonicalStateId': null},
        where: 'id = ?',
        whereArgs: ['occ-1'],
      );

      final result = await backfillCanonicalStatesFromLegacy(db);

      expect(result.statesCreated, 0, reason: 'nothing to key the state on');
      expect(await db.query(kTablePositionKnowledgeState), isEmpty);
    });
  });
}
