// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // fenKey helper
  // ---------------------------------------------------------------------------
  group('fenKey', () {
    test('returns first 4 fields of a 6-field FEN', () {
      const full = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      expect(fenKey(full), equals('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3'));
    });

    test('handles initial position FEN', () {
      const full = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      expect(fenKey(full), equals('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'));
    });
  });

  // ---------------------------------------------------------------------------
  // Empty / trivial input
  // ---------------------------------------------------------------------------
  group('importPgn — empty input', () {
    // This asserted the opposite once: an empty file produced no error, so the UI announced
    // "Imported 0 positions" as a success. An import with nothing in it is a failure, and the
    // error is what stops that being reported as a working import.
    test('empty string returns an error rather than a silent success', () {
      final result = importPgn('');
      expect(result.chapters, isEmpty);
      expect(result.decisions, isEmpty);
      expect(result.errors, isNotEmpty);
      expect(result.errors.first.message, contains('No games found'));
    });

    test('whitespace-only string returns empty result', () {
      final result = importPgn('   \n\n  ');
      expect(result.chapters, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Single-game PGN
  // ---------------------------------------------------------------------------
  group('importPgn — single game', () {
    const singleGame = '1. e4 e5 2. Nf3 Nc6 *';

    test('creates one chapter', () {
      final result = importPgn(singleGame);
      expect(result.chapters, hasLength(1));
      expect(result.errors, isEmpty);
    });

    test('extracts opening family from Opening header', () {
      const pgn = '''
[Opening "Sicilian Defense: Najdorf Variation"]
1. e4 c5 2. Nf3 d6 *
''';
      final result = importPgn(pgn);
      expect(result.chapters.first.opening, 'Sicilian Defense');
    });

    test('extracts opening family from Event header', () {
      const pgn = '''
[Event "French Defence - Winawer"]
1. e4 e6 2. d4 d5 *
''';
      final result = importPgn(pgn);
      expect(result.chapters.first.opening, 'French Defence');
    });

    test('classifies opening family from ECO header fallback', () {
      const pgn = '''
[ECO "B90"]
1. e4 c5 *
''';
      final result = importPgn(pgn);
      expect(result.chapters.first.opening, 'Sicilian Defense');
    });

    test('study title is set', () {
      final result = importPgn(singleGame, studyTitle: 'My Repertoire');
      expect(result.study.title, equals('My Repertoire'));
    });

    test('chapter root has no incoming move', () {
      final result = importPgn(singleGame);
      final root = result.chapters.first.root!;
      expect(root.incomingMove, isNull);
    });

    test('chapter root has the correct starting FEN key', () {
      final result = importPgn(singleGame);
      const expectedKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      expect(result.chapters.first.root!.fenKey, equals(expectedKey));
    });

    test('mainline moves are preserved in the tree', () {
      final result = importPgn(singleGame);
      final root = result.chapters.first.root!;
      // e4
      expect(root.children, hasLength(1));
      final e4node = root.children.first;
      expect(e4node.incomingMove!.san, equals('e4'));

      // e5
      expect(e4node.children, hasLength(1));
      final e5node = e4node.children.first;
      expect(e5node.incomingMove!.san, equals('e5'));

      // Nf3
      expect(e5node.children, hasLength(1));
      final nf3node = e5node.children.first;
      expect(nf3node.incomingMove!.san, equals('Nf3'));

      // Nc6
      expect(nf3node.children, hasLength(1));
      final nc6node = nf3node.children.first;
      expect(nc6node.incomingMove!.san, equals('Nc6'));

      // leaf
      expect(nc6node.children, isEmpty);
    });

    test('moves have correct UCI coordinates', () {
      final result = importPgn(singleGame);
      final root = result.chapters.first.root!;
      final e4move = root.children.first.incomingMove!;
      expect(e4move.from, equals('e2'));
      expect(e4move.to, equals('e4'));
      expect(e4move.promotion, isNull);
    });

    test('starting FEN is null for standard start', () {
      final result = importPgn(singleGame);
      expect(result.chapters.first.startingFen, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Multi-game PGN
  // ---------------------------------------------------------------------------
  group('importPgn — multi-game', () {
    const twoGames = '''
[Event "Game 1"]

1. e4 e5 *

[Event "Game 2"]

1. d4 d5 *
''';

    test('creates two chapters', () {
      final result = importPgn(twoGames);
      expect(result.chapters, hasLength(2));
    });

    test('sourceOrder is correct', () {
      final result = importPgn(twoGames);
      expect(result.chapters[0].sourceOrder, equals(0));
      expect(result.chapters[1].sourceOrder, equals(1));
    });

    test('chapter titles come from Event header', () {
      final result = importPgn(twoGames);
      expect(result.chapters[0].title, equals('Game 1'));
      expect(result.chapters[1].title, equals('Game 2'));
    });

    test('each chapter has independent move trees', () {
      final result = importPgn(twoGames);
      final root0 = result.chapters[0].root!;
      final root1 = result.chapters[1].root!;
      expect(root0.children.first.incomingMove!.san, equals('e4'));
      expect(root1.children.first.incomingMove!.san, equals('d4'));
    });
  });

  // ---------------------------------------------------------------------------
  // Variation preservation (RAVs)
  // ---------------------------------------------------------------------------
  group('importPgn — variation preservation', () {
    // Mainline e4, with a variation d4 at move 1.
    const withVariation = '1. e4 (1. d4 d5) e5 *';

    test('root has two children when a variation exists at move 1', () {
      final result = importPgn(withVariation);
      expect(result.errors, isEmpty);
      final root = result.chapters.first.root!;
      expect(root.children, hasLength(2));
    });

    test('mainline is first child', () {
      final result = importPgn(withVariation);
      final root = result.chapters.first.root!;
      expect(root.children.first.incomingMove!.san, equals('e4'));
    });

    test('variation is second child', () {
      final result = importPgn(withVariation);
      final root = result.chapters.first.root!;
      expect(root.children[1].incomingMove!.san, equals('d4'));
    });

    test('variation subtree is correct (d4 d5)', () {
      final result = importPgn(withVariation);
      final root = result.chapters.first.root!;
      final d4node = root.children[1];
      expect(d4node.children, hasLength(1));
      expect(d4node.children.first.incomingMove!.san, equals('d5'));
    });

    test('deeper variation is preserved', () {
      // e4 e5 with Nf3 and Nc6(mainline) or Nf6 (variation)
      const pgn = '1. e4 e5 2. Nf3 (2. Nc3 Nc6) Nc6 *';
      final result = importPgn(pgn);
      expect(result.errors, isEmpty);
      final root = result.chapters.first.root!;
      final e4n = root.children.first;
      final e5n = e4n.children.first;
      // Two children at the e5 node: Nf3 and Nc3
      expect(e5n.children, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Custom starting FEN
  // ---------------------------------------------------------------------------
  group('importPgn — custom starting FEN', () {
    // Sicilian after 1.e4 c5 — ep square c6 is present in the input FEN
    // but dartchess normalises it away (no white pawn can capture on c6),
    // so tests compare against the normalised FEN.
    const sicilianFenRaw = 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2';
    const sicilianFenNorm = 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const pgnWithFen = '[FEN "$sicilianFenRaw"]\n[SetUp "1"]\n\n1. Nf3 *';

    test('startingFen on the chapter is the normalised dartchess FEN', () {
      final result = importPgn(pgnWithFen);
      expect(result.errors, isEmpty);
      expect(result.chapters.first.startingFen, equals(sicilianFenNorm));
    });

    test('root fenKey matches the normalised starting FEN', () {
      final result = importPgn(pgnWithFen);
      final root = result.chapters.first.root!;
      expect(root.fenKey, equals(fenKey(sicilianFenNorm)));
    });

    test('moves are legal from the custom starting position', () {
      final result = importPgn(pgnWithFen);
      expect(result.errors, isEmpty);
      final root = result.chapters.first.root!;
      expect(root.children, hasLength(1));
      expect(root.children.first.incomingMove!.san, equals('Nf3'));
    });
  });

  // ---------------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------------
  group('importPgn — error handling', () {
    test('illegal move produces an error and truncates tree at that point', () {
      // Nf6 is not a legal first move for white.
      const pgn = '1. Nf6 *';
      final result = importPgn(pgn);
      expect(result.errors, hasLength(1));
      expect(result.errors.first.chapterTitle, isNotEmpty);
      // Chapter itself is still created (graceful degradation)
      expect(result.chapters, hasLength(1));
      // Tree is empty (no children from bad move)
      expect(result.chapters.first.root?.children, isEmpty);
    });

    test('bad FEN header quarantines the chapter and records an error', () {
      const pgn = '[FEN "not-a-valid-fen"]\n[SetUp "1"]\n\n1. e4 *';
      final result = importPgn(pgn);
      expect(result.errors, hasLength(1));
      expect(result.errors.first.moveIndex, equals(-1));
      // Chapter is skipped
      expect(result.chapters, isEmpty);
    });

    test('valid chapters after a bad chapter are still imported', () {
      const pgn = '''
[FEN "not-valid"]

1. e4 *

[Event "Good Game"]

1. d4 d5 *
''';
      final result = importPgn(pgn);
      // One chapter succeeds
      expect(result.chapters, hasLength(1));
      expect(result.chapters.first.title, equals('Good Game'));
      // One error for the bad FEN chapter
      expect(result.errors, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Canonical identity collisions
  // ---------------------------------------------------------------------------
  group('importPgn — canonical identity', () {
    // The root decision asks "from the start, what is White's move?". Two chapters can ask that
    // same question with different answers, and those are different things to drill.
    const oneAnswer = '1. e4 *';
    const twoAnswersSameFirstMove = '1. e4 (1. d4 d5) *';

    test('same position with a different accepted set gets a different canonical id', () {
      final one = importPgn(oneAnswer);
      final two = importPgn(twoAnswersSameFirstMove);

      expect(one.decisions, hasLength(1));
      expect(two.decisions, hasLength(1));

      // Both offer e4 from the same FEN, so the first move alone cannot tell them apart.
      expect(one.decisions.first.expectedMoves.map((m) => m.uci), contains('e2e4'));
      expect(two.decisions.first.expectedMoves.map((m) => m.uci), containsAll(['e2e4', 'd2d4']));
      expect(
        two.decisions.first.canonicalId,
        isNot(equals(one.decisions.first.canonicalId)),
        reason: 'a wider answer set is a different question and must not share SRS memory',
      );
    });

    test('a transposition of the same position converges on one id', () {
      // Both lines reach the position after 1.e4 e5 2.Nf3 Nc6, where Black must answer, by a
      // different move order. That is one question asked twice, so it gets one memory item.
      const viaE4 = '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *';
      const viaNf3 = '1. Nf3 Nc6 2. e4 e5 3. Bb5 a6 *';

      // The shared decision is the one offering the ...Nc6 answer.
      Iterable<String> idsOffering(String uci) sync* {
        final result = importPgn(uci);
        for (final d in result.decisions) {
          if (d.expectedMoves.any((m) => m.uci == 'b8c6')) yield d.canonicalId;
        }
      }

      expect(
        idsOffering(viaE4).toSet(),
        equals(idsOffering(viaNf3).toSet()),
        reason: 'the same position must not fork by move order',
      );
    });

    test('distinct positions never share a canonical id', () {
      final first = importPgn('1. e4 e5 *');
      final second = importPgn('1. d4 d5 *');

      expect(
        first.decisions.first.canonicalId,
        isNot(equals(second.decisions.first.canonicalId)),
        reason: 'different positions must not share SRS memory',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RepertoireDecision derivation
  // ---------------------------------------------------------------------------
  group('importPgn — decision derivation', () {
    const simplePgn = '1. e4 e5 *';

    test('derives decisions for chapter orientation when repertoireSide is null', () {
      final result = importPgn(simplePgn);
      // Default orientation is white: only root (white to move, e4 available)
      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.expectedMoves.first.san, equals('e4'));
    });

    test(
      'derives decisions for resolved black chapter orientation when repertoireSide is null',
      () {
        const blackPgn = '''
[Event "French Defense for Black"]
1. e4 e6 2. d4 d5 *
''';
        final result = importPgn(blackPgn);
        // Resolved orientation is black: only black responses (e6, d5)
        expect(result.decisions, hasLength(2));
        expect(
          result.decisions.map((d) => d.expectedMoves.first.san).toList(),
          equals(['e6', 'd5']),
        );
      },
    );

    test('derives only white decisions when repertoireSide is white', () {
      final result = importPgn(simplePgn, repertoireSide: Side.white);
      // Only root (white to move)
      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.expectedMoves.first.san, equals('e4'));
    });

    test('derives only black decisions when repertoireSide is black', () {
      final result = importPgn(simplePgn, repertoireSide: Side.black);
      // Only after e4 (black to move, e5)
      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.expectedMoves.first.san, equals('e5'));
    });

    test('decision nodeId matches a node in the tree', () {
      final result = importPgn(simplePgn, repertoireSide: Side.white);
      final decision = result.decisions.first;
      final root = result.chapters.first.root!;
      expect(decision.nodeId, equals(root.id));
    });

    test('decision expectedMoves match the tree children', () {
      final result = importPgn(simplePgn, repertoireSide: Side.white);
      final decision = result.decisions.first;
      expect(decision.expectedMoves, hasLength(1));
      expect(decision.expectedMoves.first.uci, equals('e2e4'));
    });

    test('variations produce additional decisions', () {
      const pgn = '1. e4 (1. d4) e5 *';
      final result = importPgn(pgn, repertoireSide: Side.white);
      // White has one decision at root but with 2 expected moves (e4 or d4).
      expect(result.decisions, hasLength(1));
      expect(result.decisions.first.expectedMoves, hasLength(2));
    });

    test('no decisions when tree is empty (position only chapter)', () {
      const pgn =
          '[FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"]\n[SetUp "1"]\n\n*';
      final result = importPgn(pgn);
      expect(result.decisions, isEmpty);
    });

    test('promotion move encodes promotion piece', () {
      // White pawn on e7, kings out of the way. e8=Q is a legal promotion.
      const promFen = '7k/4P3/8/8/8/8/8/4K3 w - - 0 1';
      const pgn = '[FEN "$promFen"]\n[SetUp "1"]\n\n1. e8=Q+ *';
      final result = importPgn(pgn);
      expect(result.errors, isEmpty);
      final root = result.chapters.first.root!;
      expect(root.children, hasLength(1));
      final move = root.children.first.incomingMove!;
      expect(move.promotion, equals('q'));
      expect(move.uci, equals('e7e8q'));
    });
  });

  // ---------------------------------------------------------------------------
  // Immutability: nodes are not shared across chapters
  // ---------------------------------------------------------------------------
  group('importPgn — tree isolation', () {
    test('chapters have independent root node instances', () {
      const pgn = '1. e4 *\n\n1. d4 *';
      final result = importPgn(pgn);
      if (result.chapters.length >= 2) {
        expect(result.chapters[0].root!.id, isNot(equals(result.chapters[1].root!.id)));
      }
    });
  });

  group('computePgnHash & fingerprinting', () {
    test(
      'computes identical SHA-256 hash for identical PGN text regardless of surrounding whitespace',
      () {
        const pgn1 = '1. e4 e5 2. Nf3 Nc6 *';
        const pgn2 = '   1. e4 e5 2. Nf3 Nc6 * \n\n';
        expect(computePgnHash(pgn1), equals(computePgnHash(pgn2)));
        expect(computePgnHash(pgn1).length, 64);
      },
    );

    test('computes different hash for modified PGN content', () {
      const pgn1 = '1. e4 e5 2. Nf3 Nc6 *';
      const pgn2 = '1. e4 c5 2. Nf3 d6 *';
      expect(computePgnHash(pgn1), isNot(equals(computePgnHash(pgn2))));
    });

    test('importPgn attaches pgnHash to created Study', () {
      const pgn = '1. d4 d5 2. c4 *';
      final result = importPgn(pgn);
      expect(result.study.pgnHash, isNotNull);
      expect(result.study.pgnHash, equals(computePgnHash(pgn)));
    });

    test('computes identical hash when PGN headers/titles are renamed but moves are identical', () {
      const pgn1 = '''
[Event "French Defense"]
[Date "2024.01.01"]
1. e4 e6 2. d4 d5 *
''';
      const pgn2 = '''
[Event "My Custom French Repertoire"]
[Date "2026.09.18"]
1. e4 e6 2. d4 d5 *
''';
      expect(computePgnHash(pgn1), equals(computePgnHash(pgn2)));
    });

    test('computeRepertoireTreeHash matches computePgnHash for same moves', () {
      const pgn = '1. e4 e5 2. Nf3 Nc6 3. Bc4 *';
      final importResult = importPgn(pgn);
      final treeHash = computeRepertoireTreeHash(importResult.chapters);
      expect(treeHash, equals(computePgnHash(pgn)));
    });

    test('computeRepertoireTreeHash distinguishes moves when SAN labels are missing', () {
      Chapter chapterWithUci(String chapterId, String from, String to) {
        return Chapter(
          id: chapterId,
          studyId: 'study-sanless',
          sourceOrder: 0,
          root: RepertoireNode(
            id: 'root-$chapterId',
            fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
            children: [
              RepertoireNode(
                id: 'child-$chapterId',
                fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
                fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
                // No SAN label: only coordinates are known.
                incomingMove: RepertoireMove(from: from, to: to),
              ),
            ],
          ),
        );
      }

      final hashE4 = computeRepertoireTreeHash([chapterWithUci('ch-e4', 'e2', 'e4')]);
      final hashD4 = computeRepertoireTreeHash([chapterWithUci('ch-d4', 'd2', 'd4')]);
      expect(
        hashE4,
        isNot(equals(hashD4)),
        reason: 'moves without SAN must fall back to UCI, never the literal "null"',
      );
    });

    test('computePgnHashAsync and importPgnAsync work across isolate boundaries', () async {
      const pgn = '''
[Event "Background Isolate Test"]
[Site "ChessSRS"]
[White "Player1"]
[Black "Player2"]

1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 *
''';
      final syncHash = computePgnHash(pgn);
      final asyncHash = await computePgnHashAsync(pgn);
      expect(asyncHash, equals(syncHash));

      final asyncResult = await importPgnAsync(
        pgn,
        studyTitle: 'Async Study',
        repertoireSide: Side.black,
      );
      expect(asyncResult.chapters.length, 1);
      expect(asyncResult.decisions.isNotEmpty, isTrue);
      expect(asyncResult.study.title, 'Async Study');
      expect(asyncResult.errors, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Orientation of a custom starting position (M12)
  // ---------------------------------------------------------------------------
  group('importPgn — orientation of a custom starting position', () {
    // After 1.e4 e5, and nothing else to go on: no Orientation tag, no title
    // keyword, no player tags. The side holding the move in the starting FEN
    // is the only signal left — and the one the resolver's own doc comment
    // lists as its fifth priority while never consulting.
    const afterE5Fen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2';
    const blackRepertoirePgn = '[FEN "$afterE5Fen"]\n[SetUp "1"]\n\n1. Nf6 2. Nc3 Nxe4 3. Qe2 *';

    test('a custom position with Black to move resolves to Black', () {
      final result = importPgn(blackRepertoirePgn);

      expect(result.errors, isEmpty);
      expect(
        result.chapters.first.orientation,
        equals(Side.black),
        reason: 'the only available signal is the side to move in the starting FEN',
      );
    });

    test('trains the moves the player has to play, not the opponent replies', () {
      final result = importPgn(blackRepertoirePgn);

      // Black's own moves are what a Black repertoire is drilled on. Resolving
      // to White instead shifts the whole tree a ply, so every question asked
      // is one the player never has to answer.
      expect(
        result.decisions.map((d) => d.expectedMoves.first.san).toList(),
        equals(['Nf6', 'Nxe4']),
      );
    });

    test('an explicit orientation still overrides the starting side', () {
      final result = importPgn(blackRepertoirePgn, repertoireSide: Side.white);

      expect(result.chapters.first.orientation, equals(Side.white));
      expect(
        result.decisions.map((d) => d.expectedMoves.first.san).toList(),
        equals(['Nc3', 'Qe2']),
        reason: 'an explicit side is the first priority and must not be displaced by the FEN',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // An import that produced no repertoire is a failure, not an empty success (M13)
  // ---------------------------------------------------------------------------
  group('importPgn — imports with nothing usable in them', () {
    test('reports an error when the text contains no games', () {
      final result = importPgn('');

      expect(result.decisions, isEmpty);
      expect(
        result.errors,
        isNotEmpty,
        reason: 'an empty file imported as a success is indistinguishable from working',
      );
    });

    test('reports an error for a header with no moves', () {
      final result = importPgn('[Event "Test"]\n[White "A"]\n[Black "B"]\n');

      expect(
        result.errors,
        isNotEmpty,
        reason: 'a chapter with no moves trains nothing and must not read as imported',
      );
    });

    test('reports an error for text that is not PGN at all', () {
      final result = importPgn('this is not a pgn at all');

      expect(
        result.errors,
        isNotEmpty,
        reason: 'arbitrary text was being persisted as a chapter and announced as a success',
      );
    });

    test('a real repertoire still imports without errors', () {
      final result = importPgn('1. e4 e5 2. Nf3 *');

      expect(result.errors, isEmpty);
      expect(result.decisions, isNotEmpty);
    });
  });
}
