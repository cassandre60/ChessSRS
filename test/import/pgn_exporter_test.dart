// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

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

    test('opening classification survives export then re-import', () {
      const pgn = '[Opening "Sicilian Defense"]\n\n1. e4 c5 2. Nf3 d6 *';
      final importResult = importPgn(pgn, studyTitle: 'Sicilian');
      expect(importResult.chapters.first.opening, 'Sicilian Defense');

      final exported = chapterToPgn(importResult.chapters.first);
      expect(exported, contains('[Opening "Sicilian Defense"]'));

      final reimported = importPgn(exported);
      expect(reimported.chapters.first.opening, 'Sicilian Defense');
    });
  });
}
