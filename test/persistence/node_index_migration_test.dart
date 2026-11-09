// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-050 (flat FEN->node index), INV-005 (upgrade without loss).

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('the v22 upgrade backfills srs_node from every stored chapter tree', () async {
    final dir = Directory.systemTemp.createTempSync('chess_srs_node_index_');
    final dbPath = p.join(dir.path, 'node_index.db');

    const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    const childFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
    const tree = RepertoireNode(
      id: 'n-root',
      fen: startFen,
      fenKey: startFen,
      children: [
        RepertoireNode(
          id: 'n-e4',
          fen: childFen,
          fenKey: childFen,
          incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
        ),
      ],
    );

    try {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      await db.insert(kTableSrsStudy, {
        'id': 'st-1',
        'title': 'Study',
        'createdAt': '2026-11-05T00:00:00.000Z',
        'updatedAt': '2026-11-05T00:00:00.000Z',
        'isActive': 1,
      });
      await db.insert(kTableSrsChapter, {
        'id': 'ch-1',
        'studyId': 'st-1',
        'sourceOrder': 0,
        'startingFen': startFen,
        'createdAt': '2026-11-05T00:00:00.000Z',
        'treeJson': jsonEncode(repertoireNodeToJson(tree)),
      });
      // Nothing indexed yet, and rewind so opening runs the v22 backfill.
      await db.delete(kTableSrsNode);
      await db.execute('PRAGMA user_version = 21');
      await db.close();

      final upgraded = await openAppDatabase(databaseFactoryFfi, dbPath);
      try {
        expect((await upgraded.rawQuery('PRAGMA user_version')).single['user_version'], 23);
        final rows = await upgraded.query(
          kTableSrsNode,
          where: 'chapterId = ?',
          whereArgs: ['ch-1'],
          orderBy: 'nodeRank ASC',
        );
        expect(rows.map((r) => r['nodeId']).toList(), ['n-root', 'n-e4']);
        expect(rows.map((r) => r['fenKey']).toList(), [startFen, childFen]);
        expect(rows.map((r) => r['nodeRank']).toList(), [0, 1]);
      } finally {
        await upgraded.close();
      }
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('importing a study writes the flat node index', () async {
    final dir = Directory.systemTemp.createTempSync('chess_srs_node_import_');
    final dbPath = p.join(dir.path, 'node_import.db');
    try {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);
      final result = importPgn('1. e4 e5 *', studyTitle: 'Import');
      await repo.saveImportResult(result);

      final chapter = result.chapters.first;
      final index = await repo.getNodeIndex([chapter.id]);
      final refs = index.values.expand((r) => r).toList();
      expect(refs, isNotEmpty);
      expect(refs.map((r) => r.nodeId).toSet(), contains(chapter.root!.id));
      // The 1.e4 child is indexed under its own fen key.
      final e4 = chapter.root!.children.first;
      expect(index[e4.fenKey]?.map((r) => r.nodeId), contains(e4.id));

      await db.close();
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
