// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013.

// A decision with a NULL `canonicalStateId` falls back to its own decision id as
// its canonical identity (`RepertoireDecision.canonicalId => canonicalStateId ?? id`).
// Every duplicate occurrence of the same question then becomes a separate
// memory item and is queued separately, so one position is asked many times in
// a session. The open-time top-up fills those ids from the row's own position,
// accepted moves and chapter side — the same identity the importer writes.

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

  test('opening fills a legacy decision canonical id so duplicates share memory', () async {
    final dir = Directory.systemTemp.createTempSync('chess_srs_canon_backfill_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final dbPath = p.join(dir.path, 'canon.db');

    const fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1';
    const fenKey = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
    const movesJson = '[{"from":"e4","to":"d5","san":"exd5"}]';

    final old = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 23,
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
      'title': 'Scandi',
      'createdAt': now,
      'updatedAt': now,
      'isActive': 1,
    });
    for (final chapterId in ['ch-1', 'ch-2']) {
      await old.insert(kTableSrsChapter, {
        'id': chapterId,
        'studyId': 'st-1',
        'sourceOrder': chapterId == 'ch-1' ? 0 : 1,
        'title': chapterId,
        'startingFen': '',
        'createdAt': now,
        'treeJson': jsonEncode(
          repertoireNodeToJson(const RepertoireNode(id: 'n1', fen: fen, fenKey: fenKey)),
        ),
        'orientation': 'white',
      });
      // Two occurrences of the same question, both with no canonical id.
      await old.insert(kTableSrsDecision, {
        'id': 'd-$chapterId',
        'studyId': 'st-1',
        'chapterId': chapterId,
        'nodeId': 'n1',
        'expectedMoves': movesJson,
        'canonicalStateId': null,
        'fenKey': fenKey,
      });
    }
    await old.close();

    final db = await openAppDatabase(databaseFactoryFfi, dbPath);
    addTearDown(db.close);

    final rows = await db.query(kTableSrsDecision, orderBy: 'id');
    final ids = rows.map((r) => r['canonicalStateId']).toList();
    expect(
      ids.every((id) => id != null && (id as String).isNotEmpty),
      isTrue,
      reason: 'the top-up must fill every resolvable row',
    );
    expect(
      ids.toSet(),
      hasLength(1),
      reason: 'the two occurrences are the same question and must share one canonical id',
    );

    // Idempotent: reopening changes nothing.
    await db.close();
    final again = await openAppDatabase(databaseFactoryFfi, dbPath);
    addTearDown(again.close);
    final againIds = (await again.query(
      kTableSrsDecision,
    )).map((r) => r['canonicalStateId']).toSet();
    expect(againIds, equals(ids.toSet()));
  });
}
