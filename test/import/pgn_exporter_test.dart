// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-010, INV-014.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PGN Exporter', () {
    test('single game chapter serializes to valid PGN string with correct moves', () {
      const pgn = '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 *';
      final importResult = importPgn(pgn, studyTitle: 'Italian Game');

      final exported = chapterToPgn(importResult.chapters.first, studyTitle: 'Italian Game');

      expect(exported, contains('[Event "Italian Game"]'));
      expect(exported, contains('1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5'));

      // Verify dartchess can parse the exported PGN without errors
      final parsed = PgnGame.parseMultiGamePgn(exported);
      expect(parsed.length, 1);
      final moves = parsed.first.moves.mainline().toList();
      expect(moves.map((m) => m.san).toList(), ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5']);
    });

    test('variations are serialized in parentheses and parseable', () {
      const pgn = '1. e4 c5 2. Nf3 (2. Nc3 Nc6 3. f4) 2... d6 *';
      final importResult = importPgn(pgn, studyTitle: 'Sicilian');

      final exported = chapterToPgn(importResult.chapters.first);

      expect(exported, contains('1. e4 c5 2. Nf3'));
      expect(exported, contains('(2. Nc3 Nc6 3. f4)'));

      final parsed = PgnGame.parseMultiGamePgn(exported);
      expect(parsed.length, 1);
    });

    test('custom starting FEN is preserved in SetUp and FEN headers', () {
      const fen = 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
      const pgn = '[FEN "$fen"]\n[SetUp "1"]\n\n2. Nf3 d6 *';
      final importResult = importPgn(pgn, studyTitle: 'From FEN');

      final exported = chapterToPgn(importResult.chapters.first);

      expect(exported, contains('[SetUp "1"]'));
      expect(exported, contains('[FEN "$fen"]'));

      final parsed = PgnGame.parseMultiGamePgn(exported);
      expect(parsed.length, 1);
      expect(parsed.first.headers['SetUp'], '1');
    });

    test('multi-chapter study serializes all chapters in source order', () {
      const multiPgn = '''
[Event "Chapter 1"]
1. e4 e5 *

[Event "Chapter 2"]
1. d4 d5 *
''';
      final importResult = importPgn(multiPgn, studyTitle: 'Openings');

      final exported = studyToPgn(importResult.study, importResult.chapters);

      final parsed = PgnGame.parseMultiGamePgn(exported);
      expect(parsed.length, 2);
      expect(parsed[0].headers['Event'], 'Chapter 1');
      expect(parsed[1].headers['Event'], 'Chapter 2');
    });

    test('exports orientation header and player tags matching chapter orientation', () {
      const pgn = '1. e4 c5 2. Nf3 d6 *';
      final importResult = importPgn(
        pgn,
        studyTitle: 'Sicilian for Black',
        repertoireSide: Side.black,
      );
      final chapter = importResult.chapters.first;
      expect(chapter.orientation, Side.black);

      final exported = chapterToPgn(chapter);

      expect(exported, contains('[Orientation "black"]'));
      expect(exported, contains('[White "Opponent"]'));
      expect(exported, contains('[Black "Repertoire"]'));

      // Re-importing the exported PGN without explicitSide should preserve Black orientation
      final reimported = importPgn(exported);
      expect(reimported.chapters.first.orientation, Side.black);
      // And decisions should be for Black moves (1... c5 and 2... d6)
      expect(reimported.decisions.length, 2);
      expect(reimported.decisions.first.expectedMoves.first.san, 'c5');
    });

    test('exports orientation white when chapter orientation is white', () {
      const pgn = '1. e4 e5 *';
      final importResult = importPgn(pgn, studyTitle: 'Italian for White');
      final chapter = importResult.chapters.first;

      final exported = chapterToPgn(chapter);

      expect(exported, contains('[Orientation "white"]'));
      expect(exported, contains('[White "Repertoire"]'));
      expect(exported, contains('[Black "Opponent"]'));
    });

    test('exports playable SAN when the stored move label is missing', () {
      const chapter = Chapter(
        id: 'ch-sanless',
        studyId: 'study-sanless',
        sourceOrder: 0,
        title: 'Sanless',
        root: RepertoireNode(
          id: 'root-sanless',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          children: [
            RepertoireNode(
              id: 'node-sanless-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              // Coordinates only: the label must be derived, never "null".
              incomingMove: RepertoireMove(from: 'e2', to: 'e4'),
            ),
          ],
        ),
      );

      final exported = chapterToPgn(chapter);

      expect(exported, isNot(contains('null')));
      expect(exported, contains('1. e4'));

      final parsed = PgnGame.parseMultiGamePgn(exported);
      expect(parsed.length, 1);
      expect(parsed.first.moves.mainline().map((m) => m.san).toList(), ['e4']);
    });

    test('corrupt starting FEN never crashes export and omits invalid headers', () {
      const chapter = Chapter(
        id: 'ch-badfen',
        studyId: 'study-badfen',
        sourceOrder: 0,
        title: 'Bad FEN',
        startingFen: 'not-a-fen',
        root: RepertoireNode(
          id: 'root-badfen',
          fen: 'not-a-fen',
          fenKey: 'not-a-fen',
          children: [
            RepertoireNode(
              id: 'node-badfen-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            ),
          ],
        ),
      );

      late String exported;
      expect(() => exported = chapterToPgn(chapter), returnsNormally);
      expect(exported, isNot(contains('not-a-fen')));
      expect(exported, contains('1. e4'));
    });

    test('opening classification survives export then re-import', () {
      const pgn = '[Opening "Sicilian Defense"]\n\n1. e4 c5 2. Nf3 d6 *';
      final importResult = importPgn(pgn, studyTitle: 'Sicilian');
      expect(importResult.chapters.first.opening, 'Sicilian Defense');

      final exported = chapterToPgn(importResult.chapters.first);
      expect(exported, contains('[Opening "Sicilian Defense"]'));

      final reimported = importPgn(exported);
      expect(reimported.chapters.first.opening, 'Sicilian Defense');
    });

    test('a chapter keeps its own title through an export and re-import', () {
      // The exporter writes the real title to [Event], and also to a [Chapter] tag, but always
      // writes the player tags as the placeholders "Repertoire"/"Opponent". An importer that
      // reads White/Black first therefore names every exported chapter "Repertoire vs
      // Opponent", which is what the review screen shows as the position's context and what
      // the scope list shows as the row name.
      const pgn = '[Event "Italian Game"]\n1. e4 e5 2. Nf3 Nc6 *';
      final original = importPgn(pgn, studyTitle: 'Repertoires');
      expect(original.chapters.first.title, 'Italian Game');

      final exported = studyToPgn(original.study, original.chapters);
      final reimported = importPgn(exported, studyTitle: 'Repertoires');

      expect(
        reimported.chapters.first.title,
        'Italian Game',
        reason: 'the chapter title is what the exporter wrote and the user named',
      );
    });

    test('multi-chapter export keeps the chapters distinguishable after re-import', () {
      const pgn = '[Event "Italian Game"]\n1. e4 e5 *\n\n[Event "Sicilian"]\n1. e4 c5 *';
      final original = importPgn(pgn, studyTitle: 'Openings');
      expect(original.chapters.length, 2);

      final exported = studyToPgn(original.study, original.chapters);
      final reimported = importPgn(exported, studyTitle: 'Openings');

      expect(reimported.chapters.map((c) => c.title).toList(), ['Italian Game', 'Sicilian']);
    });
    test('falls back to Untitled Study when no title is available', () {
      final chapter = Chapter.create(studyId: 'study-1', sourceOrder: 0);
      final exported = chapterToPgn(chapter);
      expect(exported, contains('[Event "Untitled Study"]'));
    });
  });
}
