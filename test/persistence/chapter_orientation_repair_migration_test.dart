// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013.

import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/chapter_orientation_repair_migration.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('repairChapterOrientations', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
    });

    tearDown(() async {
      await db.close();
    });

    test('repairs misclassified White study chapters starting after 1. e4', () async {
      const studyId = 'study-white-french';
      const chapterId = 'ch-white-french-1';
      final now = DateTime.now().toUtc().toIso8601String();

      // Insert study titled "White [French Defense]"
      await db.insert(kTableSrsStudy, {
        'id': studyId,
        'title': 'White [French Defense]',
        'createdAt': now,
        'updatedAt': now,
        'isActive': 1,
      });

      // A chapter tree starting after 1. e4: 1... e6 2. d4 d5 3. Nc3
      const startingFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
      const rootNode = RepertoireNode(
        id: 'root-1',
        fen: startingFen,
        fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
        children: [
          RepertoireNode(
            id: 'node-e6',
            fen: 'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
            fenKey: 'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
            incomingMove: RepertoireMove(from: 'e7', to: 'e6', san: 'e6'),
            children: [
              RepertoireNode(
                id: 'node-d4',
                fen: 'rnbqkbnr/pppp1ppp/4p3/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 2',
                fenKey: 'rnbqkbnr/pppp1ppp/4p3/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq -',
                incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
              ),
            ],
          ),
        ],
      );

      final treeJson = jsonEncode(repertoireNodeToJson(rootNode));

      // Originally misclassified as black because startTurn was black
      await db.insert(kTableSrsChapter, {
        'id': chapterId,
        'studyId': studyId,
        'sourceOrder': 0,
        'title': 'Opening [Main line : Nc3]',
        'startingFen': startingFen,
        'createdAt': now,
        'treeJson': treeJson,
        'orientation': 'black',
      });

      // Old decisions were derived for Black: 1... e6
      await db.insert(kTableSrsDecision, {
        'id': 'dec-old-black-e6',
        'studyId': studyId,
        'chapterId': chapterId,
        'nodeId': 'root-1',
        'expectedMoves': encodeExpectedMoves([
          const RepertoireMove(from: 'e7', to: 'e6', san: 'e6'),
        ]),
        'canonicalStateId': 'canon-old-e6',
        'fenKey': 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
      });

      // Run repair
      final result = await repairChapterOrientations(db);
      expect(result.repaired, 1);
      expect(result.unchanged, 0);

      // Verify chapter orientation is now white
      final chRows = await db.query(kTableSrsChapter, where: 'id = ?', whereArgs: [chapterId]);
      expect(chRows.first['orientation'], 'white');

      // Verify decisions are now derived for White: 2. d4 (not 1... e6)
      final decRows = await db.query(
        kTableSrsDecision,
        where: 'chapterId = ?',
        whereArgs: [chapterId],
      );
      expect(decRows.length, 1);
      expect(decRows.first['fenKey'], 'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -');
      final expected = decodeExpectedMoves(decRows.first['expectedMoves']! as String);
      expect(expected.first.san, 'd4');

      // Running again is idempotent
      final rerun = await repairChapterOrientations(db);
      expect(rerun.repaired, 0);
      expect(rerun.unchanged, 1);
    });

    test(
      'repairs studies named after opponent openings (e.g. French Defense) without explicit color keywords',
      () async {
        const studyId = 'study-french-bible';
        const chapterId = 'ch-french-bible-1';
        final now = DateTime.now().toUtc().toIso8601String();

        // Study title has no "White" keyword, but is an opening name
        await db.insert(kTableSrsStudy, {
          'id': studyId,
          'title': 'French Defense Listudy Bible',
          'createdAt': now,
          'updatedAt': now,
          'isActive': 1,
        });

        // Tabia after 1. e4 e6 2. d4 d5 3. Nc3 (Black to move)
        const startingFen = 'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq - 0 1';
        const rootNode = RepertoireNode(
          id: 'root-tabia',
          fen: startingFen,
          fenKey: 'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq -',
          children: [
            RepertoireNode(
              id: 'node-nf6',
              fen: 'rnbqkb1r/ppp2ppp/4pn2/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR w KQkq - 1 2',
              fenKey: 'rnbqkb1r/ppp2ppp/4pn2/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR w KQkq -',
              incomingMove: RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6'),
              children: [
                RepertoireNode(
                  id: 'node-e5',
                  fen: 'rnbqkb1r/ppp2ppp/4pn2/3pP3/3P4/2N5/PPP2PPP/R1BQKBNR b KQkq - 0 2',
                  fenKey: 'rnbqkb1r/ppp2ppp/4pn2/3pP3/3P4/2N5/PPP2PPP/R1BQKBNR b KQkq -',
                  incomingMove: RepertoireMove(from: 'e4', to: 'e5', san: 'e5'),
                ),
              ],
            ),
          ],
        );

        final treeJson = jsonEncode(repertoireNodeToJson(rootNode));

        // Was wrongly imported as black because startTurn was black
        await db.insert(kTableSrsChapter, {
          'id': chapterId,
          'studyId': studyId,
          'sourceOrder': 0,
          'title': 'Opening [Nce2 f4] Main Lines',
          'startingFen': startingFen,
          'createdAt': now,
          'treeJson': treeJson,
          'orientation': 'black',
        });

        await db.insert(kTableSrsDecision, {
          'id': 'dec-old-black-nf6',
          'studyId': studyId,
          'chapterId': chapterId,
          'nodeId': 'root-tabia',
          'expectedMoves': encodeExpectedMoves([
            const RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6'),
          ]),
          'canonicalStateId': 'canon-old-nf6',
          'fenKey': 'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq -',
        });

        // Run repair
        final result = await repairChapterOrientations(db);
        expect(result.repaired, 1);

        // Orientation must default to white per INV-013, not black
        final chRows = await db.query(kTableSrsChapter, where: 'id = ?', whereArgs: [chapterId]);
        expect(chRows.first['orientation'], 'white');

        // Decisions must now train White: 4. e5
        final decRows = await db.query(kTableSrsDecision, where: 'chapterId = ?', whereArgs: [chapterId]);
        expect(decRows.length, 1);
        final expected = decodeExpectedMoves(decRows.first['expectedMoves']! as String);
        expect(expected.first.san, 'e5');
      },
    );

    test('repairs misclassified Black study chapters starting at move 1', () async {
      const studyId = 'study-black-italian';
      const chapterId = 'ch-black-italian-1';
      final now = DateTime.now().toUtc().toIso8601String();

      // Insert study titled "Black Vs [Italian]"
      await db.insert(kTableSrsStudy, {
        'id': studyId,
        'title': 'Black Vs [Italian]',
        'createdAt': now,
        'updatedAt': now,
        'isActive': 1,
      });

      // Tree starting from standard start: 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5
      final pgnResult = importPgn('''
[Event "Black Vs [Italian]: Main Line"]
[StudyName "Black Vs [Italian]"]
[ChapterName "Main Line"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 *
''', repertoireSide: Side.black);

      final rootNode = pgnResult.chapters.first.root!;
      final treeJson = jsonEncode(repertoireNodeToJson(rootNode));

      // Simulate prior buggy import where orientation was erroneously saved as 'white'
      await db.insert(kTableSrsChapter, {
        'id': chapterId,
        'studyId': studyId,
        'sourceOrder': 0,
        'title': 'Main Line',
        'startingFen': '',
        'createdAt': now,
        'treeJson': treeJson,
        'orientation': 'white',
      });

      // Decisions were wrongly derived for White: 1. e4, 2. Nf3, 3. Bc4
      await db.insert(kTableSrsDecision, {
        'id': 'dec-old-white-e4',
        'studyId': studyId,
        'chapterId': chapterId,
        'nodeId': rootNode.id,
        'expectedMoves': encodeExpectedMoves([
          const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
        ]),
        'canonicalStateId': 'canon-old-e4',
        'fenKey': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      });

      // Run repair
      final result = await repairChapterOrientations(db);
      expect(result.repaired, 1);

      // Verify chapter orientation is now black
      final chRows = await db.query(kTableSrsChapter, where: 'id = ?', whereArgs: [chapterId]);
      expect(chRows.first['orientation'], 'black');

      // Verify decisions are derived for Black: 1... e5, 2... Nc6, 3... Bc5
      final decRows = await db.query(
        kTableSrsDecision,
        where: 'chapterId = ?',
        whereArgs: [chapterId],
      );
      expect(decRows.length, 3);
      final sans = decRows.map((r) {
        final exp = decodeExpectedMoves(r['expectedMoves']! as String);
        return exp.first.san;
      }).toList();
      expect(sans, containsAll(['e5', 'Nc6', 'Bc5']));
    });
  });
}
