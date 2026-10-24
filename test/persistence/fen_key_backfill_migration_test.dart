// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-005.

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

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
const _childFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';

void main() {
  setUpAll(sqfliteFfiInit);

  group('backfillDecisionFenKeys', () {
    late Directory tempDir;
    late String dbPath;
    late Database db;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_fen_key_');
      dbPath = p.join(tempDir.path, 'fenkey.db');
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        expect(() => tempDir.deleteSync(recursive: true), returnsNormally);
      }
    });

    /// Seeds a study with one chapter whose tree decodes; its child node is
    /// always `node-1` at [_childFen], while the decision can point at any
    /// [nodeId] — which is how a row whose node has gone missing is simulated.
    Future<void> seed({
      String nodeId = 'node-1',
      String nodeFenKey = _childFen,
      String? treeJson,
    }) async {
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
        'treeJson':
            treeJson ??
            jsonEncode(
              repertoireNodeToJson(
                RepertoireNode(
                  id: 'root',
                  fen: _startFen,
                  fenKey: _startFen,
                  children: [
                    RepertoireNode(
                      id: 'node-1',
                      fen: nodeFenKey,
                      fenKey: nodeFenKey,
                      incomingMove: const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
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
        'nodeId': nodeId,
        'expectedMoves': encodeExpectedMoves([
          const RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
        ]),
      });
    }

    test('copies the node fen key onto the decision row', () async {
      await seed();
      final result = await backfillDecisionFenKeys(db);
      expect(result.decisionsFilled, 1);
      expect(result.skipped, 0);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], _childFen);
    });

    test('leaves a decision whose node is missing from the tree at null', () async {
      await seed(nodeId: 'ghost-node');
      final result = await backfillDecisionFenKeys(db);
      expect(result.decisionsFilled, 0);
      expect(result.skipped, 1);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], isNull);
    });

    test('skips a chapter whose tree cannot be read without throwing', () async {
      await seed(treeJson: '{not json');
      final result = await backfillDecisionFenKeys(db);
      expect(result.decisionsFilled, 0);
      expect(result.skipped, 1);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], isNull);
    });

    test('is idempotent: filled rows are left alone on a second run', () async {
      await seed();
      await backfillDecisionFenKeys(db);
      final second = await backfillDecisionFenKeys(db);
      expect(second.decisionsFilled, 0);
      expect(second.skipped, 0);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], _childFen);
    });

    test('fills an empty-string fen key as if it were null', () async {
      await seed();
      await db.update(kTableSrsDecision, {'fenKey': ''}, where: "id = 'dec-1'");
      final result = await backfillDecisionFenKeys(db);
      expect(result.decisionsFilled, 1);
      final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
      expect(row.single['fenKey'], _childFen);
    });
  });

  group('v20 → v21 upgrade', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_fenkey_upgrade_');
      dbPath = p.join(tempDir.path, 'upgrade.db');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        expect(() => tempDir.deleteSync(recursive: true), returnsNormally);
      }
    });

    test('adds the column and backfills it on open', () async {
      // Build a database at v20: the current tables minus everything after 20,
      // so the upgrade ladder's v21 leg is what runs on reopen.
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
                  const RepertoireNode(id: 'node-1', fen: _childFen, fenKey: _childFen),
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

      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      try {
        expect((await db.rawQuery('PRAGMA user_version')).single['user_version'], 21);
        final row = await db.query(kTableSrsDecision, where: "id = 'dec-1'");
        expect(row.single['fenKey'], _childFen);
      } finally {
        await db.close();
      }
    });
  });
}
