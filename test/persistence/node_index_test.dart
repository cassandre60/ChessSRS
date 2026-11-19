// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/node_index.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('nodeRowsForChapter', () {
    test('returns a single row for a leaf root with rank 0', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const root = RepertoireNode(id: 'n-root', fen: fen, fenKey: fen);

      final rows = nodeRowsForChapter('ch-1', root);

      expect(rows, hasLength(1));
      expect(rows.single, {'chapterId': 'ch-1', 'nodeId': 'n-root', 'fenKey': fen, 'nodeRank': 0});
    });

    test('walks the subtree depth-first pre-order and increments rank', () {
      const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const e4Fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
      const e5Fen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
      const d4Fen = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -';

      const root = RepertoireNode(
        id: 'n-root',
        fen: startFen,
        fenKey: startFen,
        children: [
          RepertoireNode(
            id: 'n-e4',
            fen: e4Fen,
            fenKey: e4Fen,
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'n-e5',
                fen: e5Fen,
                fenKey: e5Fen,
                incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
              ),
            ],
          ),
          RepertoireNode(
            id: 'n-d4',
            fen: d4Fen,
            fenKey: d4Fen,
            incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
          ),
        ],
      );

      final rows = nodeRowsForChapter('ch-42', root);

      expect(rows.map((r) => r['nodeId']).toList(), ['n-root', 'n-e4', 'n-e5', 'n-d4']);
      expect(rows.map((r) => r['nodeRank']).toList(), [0, 1, 2, 3]);
      expect(rows.every((r) => r['chapterId'] == 'ch-42'), isTrue);
      expect(rows.map((r) => r['fenKey']).toList(), [startFen, e4Fen, e5Fen, d4Fen]);
    });
  });

  group('backfillNodeIndex', () {
    test('creates the table and backfills rows from stored chapter trees', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute('''
          CREATE TABLE $kTableSrsChapter (
            id TEXT PRIMARY KEY,
            treeJson TEXT
          )
        ''');
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
        await db.insert(kTableSrsChapter, {
          'id': 'ch-1',
          'treeJson': jsonEncode(repertoireNodeToJson(tree)),
        });

        final inserted = await backfillNodeIndex(db);

        expect(inserted, 2);
        final rows = await db.query(kTableSrsNode, orderBy: 'nodeRank ASC');
        expect(rows.map((r) => r['nodeId']).toList(), ['n-root', 'n-e4']);
        expect(rows.map((r) => r['fenKey']).toList(), [startFen, childFen]);
      } finally {
        await db.close();
      }
    });

    test('is idempotent and skips chapters that already have rows', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute('''
          CREATE TABLE $kTableSrsChapter (
            id TEXT PRIMARY KEY,
            treeJson TEXT
          )
        ''');
        const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
        const tree = RepertoireNode(id: 'n-root', fen: fen, fenKey: fen);
        await db.insert(kTableSrsChapter, {
          'id': 'ch-1',
          'treeJson': jsonEncode(repertoireNodeToJson(tree)),
        });

        expect(await backfillNodeIndex(db), 1);
        expect(await backfillNodeIndex(db), 0);

        final rows = await db.query(kTableSrsNode, where: 'chapterId = ?', whereArgs: ['ch-1']);
        expect(rows, hasLength(1));
      } finally {
        await db.close();
      }
    });

    test('returns 0 when srs_chapter has no treeJson column', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute('CREATE TABLE $kTableSrsChapter (id TEXT PRIMARY KEY)');

        final inserted = await backfillNodeIndex(db);

        expect(inserted, 0);
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [kTableSrsNode],
        );
        expect(tables, isNotEmpty);
      } finally {
        await db.close();
      }
    });

    test('skips chapters with null or empty treeJson', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        await db.execute('''
          CREATE TABLE $kTableSrsChapter (
            id TEXT PRIMARY KEY,
            treeJson TEXT
          )
        ''');
        await db.insert(kTableSrsChapter, {'id': 'ch-null', 'treeJson': null});
        await db.insert(kTableSrsChapter, {'id': 'ch-empty', 'treeJson': ''});

        final inserted = await backfillNodeIndex(db);

        expect(inserted, 0);
        final rows = await db.query(kTableSrsNode);
        expect(rows, isEmpty);
      } finally {
        await db.close();
      }
    });
  });
}
