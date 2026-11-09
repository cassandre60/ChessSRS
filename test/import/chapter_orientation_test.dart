// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013.

import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveChapterOrientation', () {
    test('respects explicit Orientation header', () {
      expect(resolveChapterOrientation({'Orientation': 'black'}), Side.black);
      expect(resolveChapterOrientation({'Orientation': 'Black'}), Side.black);
      expect(resolveChapterOrientation({'Orientation': 'white'}), Side.white);
      expect(resolveChapterOrientation({'Orientation': 'White'}), Side.white);
    });

    test('detects Black from Event or ChapterName keywords', () {
      expect(resolveChapterOrientation({'Event': 'Sicilian Defense for Black'}), Side.black);
      expect(resolveChapterOrientation({'ChapterName': "King's Indian [Black]"}), Side.black);
      expect(resolveChapterOrientation({'Event': 'French Defense (Black)'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Caro-Kann as Black'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Nimzo-Indian vs White'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Black Vs [Italian]'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Black vs 1.d4'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Black [Vienna]'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Black [Spanish]'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'Black opening cool ideas'}), Side.black);
      expect(
        resolveChapterOrientation({'Event': 'Black moves to play by heart in 0.1 s'}),
        Side.black,
      );
      expect(resolveChapterOrientation({'Event': 'Black Quizz'}), Side.black);
      expect(resolveChapterOrientation({'Event': 'lichess_study_black-vs-italian'}), Side.black);
    });

    test('reads the plain Study/Chapter tags our exporter writes', () {
      // Lichess writes StudyName/ChapterName; our exporter writes Study/Chapter.
      // Both spellings must feed the heuristic or self round-trips lose it.
      expect(resolveChapterOrientation({'Study': 'My Rep for Black'}), Side.black);
      expect(resolveChapterOrientation({'Chapter': 'French for Black'}), Side.black);
      expect(resolveChapterOrientation({'Study': 'My Rep for White'}), Side.white);
    });

    test('detects White from Event or ChapterName keywords', () {
      expect(resolveChapterOrientation({'Event': 'Italian Game for White'}), Side.white);
      expect(resolveChapterOrientation({'ChapterName': 'Scotch [White]'}), Side.white);
      expect(resolveChapterOrientation({'Event': 'London System as White'}), Side.white);
      expect(
        resolveChapterOrientation({
          'StudyName': 'White [French Defense][Final]',
        }, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White Vs [French]'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White vs French'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White vs. Sicilian'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White [Caro-Kann]'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White [Spanish]'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White opening ideas'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'StudyName': 'White e4 Quizz'}, startTurn: Side.black),
        Side.white,
      );
      expect(
        resolveChapterOrientation({
          'Event': 'lichess_study_white-vs-french',
        }, startTurn: Side.black),
        Side.white,
      );
    });

    test('detects orientation from player tags with placeholder opponent', () {
      expect(resolveChapterOrientation({'White': '?', 'Black': 'Sicilian Dragon'}), Side.black);
      expect(resolveChapterOrientation({'White': '*', 'Black': 'French Winawer'}), Side.black);
      expect(resolveChapterOrientation({'White': 'Ruy Lopez', 'Black': '?'}), Side.white);
    });

    // The title-keyword search is documented case-insensitive. White is also
    // the fallthrough default, so a mixed-case white keyword is only
    // observable where losing it flips the answer: a start position with
    // Black to move, where the keyword is what says White is at home.
    test('a mixed-case white title keyword wins over the starting side', () {
      expect(
        resolveChapterOrientation({
          'ChapterName': 'Marshall Attack (White)',
        }, startTurn: Side.black),
        Side.white,
      );
    });

    // An empty tag is a placeholder too: it means no name, so the context
    // decides. Plain-white context answering White proves the empty tag rides
    // the placeholder branch instead of counting as Black's named opponent.
    test('an empty player tag is a placeholder', () {
      expect(resolveChapterOrientation({'White': '?', 'Black': ''}), Side.white);
    });

    test('detects orientation when player contains repertoire keyword', () {
      expect(resolveChapterOrientation({'ChapterName': "King's Indian [Black]"}), Side.black);
      expect(
        resolveChapterOrientation({'White': 'White Repertoire', 'Black': 'Karpov'}),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'White': 'Kasparov', 'Black': 'Black Repertoire'}),
        Side.black,
      );
    });

    test('resolves White orientation for White study chapters starting after 1. e4', () {
      const pgn = '''
[Event "White Vs [French]: Opening [Nc3 Bb4]"]
[StudyName "White Vs [French]"]
[ChapterName "Opening [Nc3 Bb4]"]
[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]
[SetUp "1"]

1... e6 2. d4 d5 3. Nc3 Bb4 *
''';
      final result = importPgn(pgn);
      expect(result.chapters.first.orientation, Side.white);
      // Moves for White should be derived as decisions: 2. d4 and 3. Nc3
      expect(result.decisions.length, 2);
      expect(result.decisions.first.expectedMoves.first.san, 'd4');
      expect(result.decisions.last.expectedMoves.first.san, 'Nc3');
    });

    test('explicitSide parameter overrides headers', () {
      expect(
        resolveChapterOrientation({'Orientation': 'black'}, explicitSide: Side.white),
        Side.white,
      );
      expect(
        resolveChapterOrientation({'Orientation': 'white'}, explicitSide: Side.black),
        Side.black,
      );
    });

    test('defaults to White when no clues exist', () {
      expect(resolveChapterOrientation({'Event': 'Casual Game'}), Side.white);
      expect(resolveChapterOrientation({}), Side.white);
    });
  });

  group('importPgn with per-chapter auto-orientation', () {
    test('automatically resolves White and Black chapters in the same study', () {
      const pgn = '''
[Event "Queen's Gambit for White"]
[White "Repertoire"]
[Black "?"]
1. d4 d5 2. c4 e6 3. Nc3 *

[Event "Sicilian Najdorf for Black"]
[Orientation "black"]
[White "?"]
[Black "Repertoire"]
1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 *
''';

      // Import with repertoireSide = null (Auto)
      final result = importPgn(pgn, studyTitle: 'Comprehensive Repertoire');

      expect(result.chapters.length, 2);

      // Chapter 1: White
      final ch1 = result.chapters[0];
      expect(ch1.orientation, Side.white);
      final ch1Decisions = result.decisions.where((d) => d.chapterId == ch1.id).toList();
      // White decisions: after 1.d4 (d5), 2.c4 (e6), 3.Nc3
      expect(ch1Decisions.isNotEmpty, isTrue);

      // Chapter 2: Black
      final ch2 = result.chapters[1];
      expect(ch2.orientation, Side.black);
      final ch2Decisions = result.decisions.where((d) => d.chapterId == ch2.id).toList();
      // Black decisions: 1...c5, 2...d6, 3...cxd4, 4...Nf6
      expect(ch2Decisions.isNotEmpty, isTrue);
    });
  });
}
