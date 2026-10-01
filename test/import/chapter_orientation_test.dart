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
    });

    test('detects White from Event or ChapterName keywords', () {
      expect(resolveChapterOrientation({'Event': 'Italian Game for White'}), Side.white);
      expect(resolveChapterOrientation({'ChapterName': 'Scotch [White]'}), Side.white);
      expect(resolveChapterOrientation({'Event': 'London System as White'}), Side.white);
    });

    test('detects orientation from player tags with placeholder opponent', () {
      expect(resolveChapterOrientation({'White': '?', 'Black': 'Sicilian Dragon'}), Side.black);
      expect(resolveChapterOrientation({'White': '*', 'Black': 'French Winawer'}), Side.black);
      expect(resolveChapterOrientation({'White': 'Ruy Lopez', 'Black': '?'}), Side.white);
    });

    test('detects orientation when player contains repertoire keyword', () {
      expect(resolveChapterOrientation({'ChapterName': "King's Indian [Black]"}), Side.black);
      expect(
        resolveChapterOrientation({'White': 'White Repertoire', 'Black': 'Karpov'}),
        Side.white,
      );
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
