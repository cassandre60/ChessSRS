// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013.

// The v23 orientation repair runs a cleanup that deletes knowledge rows with no
// matching `srs_decision.canonicalStateId`. That check is wrong for legacy
// decisions whose `canonicalStateId` is NULL: their knowledge row is keyed by
// the decision id (the `canonicalStateId ?? id` convention), so the cleanup
// deletes the user's review memory for every such position.
//
// On the owner's real library this removed 303 of 412 knowledge rows the
// moment the v23 migration ran.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'the v23 repair keeps review memory for legacy decisions with no canonicalStateId',
    () async {
      final dir = Directory.systemTemp.createTempSync('chess_srs_v23_memory_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final dbPath = p.join(dir.path, 'upgrade.db');

      final old = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 22,
          onCreate: (db, version) async {
            final batch = db.batch();
            createSrsTables(batch);
            await batch.commit();
          },
        ),
      );
      const now = '2026-11-01T00:00:00.000Z';
      await old.insert(kTableSrsStudy, {
        'id': 'st-1',
        'title': 'Openings',
        'createdAt': now,
        'updatedAt': now,
        'isActive': 1,
      });
      // A chapter the v23 repair will flip: its title names Black, it is stored
      // white. Repaired > 0 is what arms the destructive cleanup.
      await old.insert(kTableSrsChapter, {
        'id': 'ch-flip',
        'studyId': 'st-1',
        'sourceOrder': 0,
        'title': 'Black [Sicilian] main line',
        'startingFen': '',
        'createdAt': now,
        'treeJson': jsonEncode(
          repertoireNodeToJson(
            const RepertoireNode(
              id: 'n-root',
              fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
            ),
          ),
        ),
        'orientation': 'white',
      });
      // A chapter the repair does not touch.
      await old.insert(kTableSrsChapter, {
        'id': 'ch-stable',
        'studyId': 'st-1',
        'sourceOrder': 1,
        'title': 'Sicilian main line',
        'startingFen': '',
        'createdAt': now,
        'treeJson': jsonEncode(
          repertoireNodeToJson(
            const RepertoireNode(
              id: 'n-stable',
              fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
            ),
          ),
        ),
        'orientation': 'white',
      });
      // A legacy decision: no canonicalStateId, and its review memory is keyed
      // by its own id (the `canonicalStateId ?? id` convention).
      await old.insert(kTableSrsDecision, {
        'id': 'dec-legacy',
        'studyId': 'st-1',
        'chapterId': 'ch-stable',
        'nodeId': 'n-root',
        'expectedMoves': encodeExpectedMoves([
          const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
        ]),
        'canonicalStateId': null,
      });
      await old.insert(kTablePositionKnowledgeState, {
        'canonicalId': 'dec-legacy',
        'firstReviewedAt': now,
        'lastReviewedAt': now,
        'nextDueAt': '2026-12-01T00:00:00.000Z',
        'repetitionCount': 4,
        'lapseCount': 1,
        'stability': 12.0,
        'difficulty': 6.0,
        'latencySampleCount': 0,
      });
      await old.close();

      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(db.close);

      final rows = await db.query(
        kTablePositionKnowledgeState,
        where: 'canonicalId = ?',
        whereArgs: ['dec-legacy'],
      );
      expect(
        rows,
        hasLength(1),
        reason:
            'the repair must not delete review memory that is keyed by a decision id '
            '(legacy NULL canonicalStateId); only rows orphaned by re-derivation may go',
      );
      expect(rows.single['repetitionCount'], 4);
    },
  );
}
