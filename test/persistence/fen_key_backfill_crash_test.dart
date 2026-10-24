// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-005.
//
// Crash consistency of the v21 fen-key backfill, driven with
// crash_consistency_test.dart's fault vocabulary: the migration's whole update
// set travels in ONE batch, so a fault at its boundary must leave every row
// unfilled — never a subset — and a retry on the same connection must heal
// without duplicating.
//
// The fault is armed on a direct `backfillDecisionFenKeys` call over a wrapped
// open database because the upgrade path itself is out of the harness's reach
// on two counts: sqflite hands the upgrade callbacks its own database handle,
// so no wrapper can sit in the upgrade's loop, and the v21 DDL leg goes through
// `batch.execute`, which FaultyDatabase's batch does not carry. (A hand-built
// "column added, version still 20" state cannot stand in for the torn upgrade
// either: sqflite runs the DDL and the version bump in one transaction, so the
// app never persists that state, and reopening it fails on the re-run ALTER.)

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/persistence/fen_key_backfill_migration.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'faulty_database.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
const _childFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';

/// Only the harness's own fault should satisfy `throwsA`; a `DatabaseException`
/// from anywhere else must fail the test instead of passing vacuously.
final Matcher _injectedFault = isA<InjectedFault>();

void main() {
  setUpAll(sqfliteFfiInit);

  group('fen key backfill under fault injection', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_fen_key_crash_');
      dbPath = p.join(tempDir.path, 'fenkey_crash.db');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; the database file may already be gone.
      }
    });

    /// One study, one chapter whose tree is the root plus the single child
    /// `node-1` at [_childFen], and one decision pointing at that child. The
    /// decision insert omits `fenKey`, so the row starts exactly as the v21
    /// data migration receives it.
    Future<Database> seedOpen() async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      await db.insert(kTableSrsStudy, {
        'id': 'st-1',
        'title': 'Study',
        'createdAt': '2026-10-24T00:00:00.000Z',
        'updatedAt': '2026-10-24T00:00:00.000Z',
        'isActive': 1,
      });
      await db.insert(kTableSrsChapter, {
        'id': 'ch-1',
        'studyId': 'st-1',
        'sourceOrder': 0,
        'startingFen': _startFen,
        'createdAt': '2026-10-24T00:00:00.000Z',
        'treeJson': jsonEncode(
          repertoireNodeToJson(
            const RepertoireNode(
              id: 'root',
              fen: _startFen,
              fenKey: _startFen,
              children: [
                RepertoireNode(
                  id: 'node-1',
                  fen: _childFen,
                  fenKey: _childFen,
                  incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
                ),
              ],
            ),
          ),
        ),
      });
      await db.insert(kTableSrsDecision, {
        'id': 'dec-1',
        'studyId': 'st-1',
        'chapterId': 'ch-1',
        'nodeId': 'node-1',
        'expectedMoves': encodeExpectedMoves([
          const RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
        ]),
      });
      return db;
    }

    test(
      'a fault at the backfill batch commit leaves the row unfilled; a retry heals it',
      () async {
        // Pins: a backfill update must not survive its own failed batch
        // commit, and the healing retry must fill the row exactly once.
        final db = FaultyDatabase(await seedOpen());
        db.arm(const FaultPlan(throwAtBatchCommit: 1));
        await expectLater(backfillDecisionFenKeys(db), throwsA(_injectedFault));

        final torn = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
        expect(
          torn.single['fenKey'],
          isNull,
          reason: 'a backfill update survived a failed batch commit',
        );

        // The single-shot fault has fired; the retry on the same instance heals.
        final healed = await backfillDecisionFenKeys(db);
        expect(healed.decisionsFilled, 1);
        expect(healed.skipped, 0);

        // The healed write is durable across close and reopen (INV-001), and
        // the upgrade never duplicated the row.
        await db.close();
        final reopened = await openAppDatabase(databaseFactoryFfi, dbPath);
        expect((await reopened.rawQuery('PRAGMA user_version')).single['user_version'], 21);
        final rows = await reopened.query(kTableSrsDecision);
        expect(rows, hasLength(1), reason: 'the retried backfill duplicated the decision row');
        expect(rows.single['fenKey'], _childFen);
        await reopened.close();
      },
    );

    test('a fault while the backfill batch is still being built leaves nothing behind', () async {
      // Pins: the batch's only statement is the row's update, so a fault as
      // it is added must not reach SQLite at all, and the retry still heals.
      final db = FaultyDatabase(await seedOpen());
      db.arm(const FaultPlan(throwAtStatement: 1));
      await expectLater(backfillDecisionFenKeys(db), throwsA(_injectedFault));

      final torn = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(torn.single['fenKey'], isNull, reason: 'an unfilled row gained a fen key anyway');

      final healed = await backfillDecisionFenKeys(db);
      expect(healed.decisionsFilled, 1);
      expect(healed.skipped, 0);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], _childFen);
      await db.close();
    });
  });

  group('v20 → v21 upgrade idempotence', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_fen_key_reopen_');
      dbPath = p.join(tempDir.path, 'fenkey_reopen.db');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; the database file may already be gone.
      }
    });

    test('repeated reopens of an upgraded database leave the backfilled row untouched', () async {
      // Pins: a re-run of the backfill must not rewrite an already-filled row,
      // a reopen must not lose or corrupt the stored fen key, and a reopen
      // that re-ran the ladder would fail the open itself on the
      // duplicate-column ALTER before any assertion below runs.
      await _seedV20Fixture(dbPath);

      final upgraded = await openAppDatabase(databaseFactoryFfi, dbPath);
      expect((await upgraded.rawQuery('PRAGMA user_version')).single['user_version'], 21);
      expect((await upgraded.query(kTableSrsDecision)).single['fenKey'], _childFen);
      await upgraded.close();

      for (var i = 0; i < 2; i++) {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final result = await backfillDecisionFenKeys(db);
        expect(result.decisionsFilled, 0, reason: 'a re-run rewrote an already-filled row');
        expect(result.skipped, 0);
        expect((await db.query(kTableSrsDecision)).single['fenKey'], _childFen);
        await db.close();
      }
    });
  });
}

/// A database at v20: the current SRS tables minus the v21 column, seeded with
/// the same one-child tree and one decision whose fen key is not stored, so
/// the upgrade ladder's v21 leg is what runs on the first open.
Future<void> _seedV20Fixture(String dbPath) async {
  final seeded = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 20,
      onCreate: (db, version) async {
        final batch = db.batch();
        createSrsTables(batch);
        await batch.commit();
        await db.execute('ALTER TABLE $kTableSrsDecision DROP COLUMN fenKey');
        await db.insert(kTableSrsStudy, {
          'id': 'st-1',
          'title': 'Study',
          'createdAt': '2026-10-24T00:00:00.000Z',
          'updatedAt': '2026-10-24T00:00:00.000Z',
          'isActive': 1,
        });
        await db.insert(kTableSrsChapter, {
          'id': 'ch-1',
          'studyId': 'st-1',
          'sourceOrder': 0,
          'startingFen': _startFen,
          'createdAt': '2026-10-24T00:00:00.000Z',
          'treeJson': jsonEncode(
            repertoireNodeToJson(
              const RepertoireNode(
                id: 'root',
                fen: _startFen,
                fenKey: _startFen,
                children: [
                  RepertoireNode(
                    id: 'node-1',
                    fen: _childFen,
                    fenKey: _childFen,
                    incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
                  ),
                ],
              ),
            ),
          ),
        });
        await db.insert(kTableSrsDecision, {
          'id': 'dec-1',
          'studyId': 'st-1',
          'chapterId': 'ch-1',
          'nodeId': 'node-1',
          'expectedMoves': encodeExpectedMoves([
            const RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
          ]),
        });
      },
    ),
  );
  await seeded.close();
}
