// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-067.

import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/import/opening_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opening name predicates', () {
    test('a title that merely mentions an opening is not a family (INV-067)', () {
      expect(isLikelyOpeningFamily('White vs French'), isFalse);
      expect(mentionsOpeningButIsNotFamily('White vs French'), isTrue);
      expect(mentionsOpeningButIsNotFamily('My French Repertoire'), isTrue);
    });

    test('empty or blank name is not a family (INV-067)', () {
      expect(isLikelyOpeningFamily(''), isFalse);
      expect(isLikelyOpeningFamily('   '), isFalse);
    });

    test('a real family is kept, including one the ECO table produces', () {
      for (final name in const [
        'French Defense',
        'Sicilian Defense',
        'Caro-Kann Defense',
        "Queen's Gambit",
        'Petrov Defense',
      ]) {
        expect(isLikelyOpeningFamily(name), isTrue, reason: name);
        expect(mentionsOpeningButIsNotFamily(name), isFalse, reason: name);
      }
    });

    test('every family the ECO fallback can produce is one the repair keeps', () {
      for (final code in const [
        'B20',
        'B12',
        'B05',
        'C00',
        'C30',
        'C60',
        'D10',
        'D30',
        'D80',
        'E40',
        'E60',
        'E00',
        'A20',
        'A40',
        'A80',
      ]) {
        final family = ecoToOpeningFamily(code);
        expect(family, isNotNull, reason: code);
        expect(mentionsOpeningButIsNotFamily(family!), isFalse, reason: '$code → $family');
      }

      // Exact upper and lower boundary tests across all ECO categories (INV-067)
      const boundaries = {
        'B00': 'Scandinavian / Alekhine',
        'B09': 'Scandinavian / Alekhine',
        'B10': 'Caro-Kann Defense',
        'B19': 'Caro-Kann Defense',
        'B20': 'Sicilian Defense',
        'B99': 'Sicilian Defense',
        'C00': 'French Defense',
        'C19': 'French Defense',
        'C20': 'Open Game',
        'C59': 'Open Game',
        'C60': 'Ruy Lopez',
        'C99': 'Ruy Lopez',
        'D00': "Queen's Gambit",
        'D69': "Queen's Gambit",
        'D10': 'Slav Defense',
        'D19': 'Slav Defense',
        'D70': 'Grünfeld Defense',
        'D99': 'Grünfeld Defense',
        'E00': 'Catalan Opening',
        'E09': 'Catalan Opening',
        'E20': 'Nimzo-Indian Defense',
        'E59': 'Nimzo-Indian Defense',
        'E60': "King's Indian Defense",
        'E99': "King's Indian Defense",
        'A10': 'English Opening',
        'A39': 'English Opening',
        'A40': "Queen's Pawn Game",
        'A44': "Queen's Pawn Game",
        'A80': 'Dutch Defense',
        'A99': 'Dutch Defense',
      };
      for (final entry in boundaries.entries) {
        expect(ecoToOpeningFamily(entry.key), equals(entry.value), reason: entry.key);
      }

      // Out of bounds / invalid ECO codes
      expect(ecoToOpeningFamily('A45'), isNull);
      expect(ecoToOpeningFamily('A05'), isNull);
      expect(ecoToOpeningFamily('B'), isNull);
      expect(ecoToOpeningFamily('B1'), isNull);
      expect(ecoToOpeningFamily('XYZ'), isNull);
    });

    test('an unrecognised name is left alone rather than erased', () {
      expect(mentionsOpeningButIsNotFamily('QGD Exchange Variation'), isFalse);
      expect(mentionsOpeningButIsNotFamily('My Repertoire'), isFalse);
    });

    test('normalizeOpeningFamily normalizes spelling variants', () {
      expect(normalizeOpeningFamily('French Defence'), 'French Defense');
      expect(normalizeOpeningFamily('Sicilian Defence'), 'Sicilian Defense');
      expect(normalizeOpeningFamily('Caro-Kann Defence'), 'Caro-Kann Defense');
      expect(normalizeOpeningFamily('Grunfeld Defense'), 'Grünfeld Defense');
      expect(normalizeOpeningFamily('French Defense'), 'French Defense');
      expect(normalizeOpeningFamily('grunfeld Defense'), 'Grünfeld Defense');
      expect(normalizeOpeningFamily('French defence'), 'French Defense');
    });

    test('simplifyOpeningName isolates family across delimiters (INV-067)', () {
      expect(simplifyOpeningName('French Defense: Winawer Variation'), 'French Defense');
      expect(simplifyOpeningName('Sicilian Defense, Dragon Variation'), 'Sicilian Defense');
      expect(simplifyOpeningName('Ruy Lopez - Marshall Attack'), 'Ruy Lopez');
      expect(simplifyOpeningName('Caro-Kann Defense'), 'Caro-Kann Defense');
      expect(simplifyOpeningName(''), '');
      expect(simplifyOpeningName('   '), '');
    });

    test('detectOpeningFamilyFromMoves classifies canonical openings from move sequence', () {
      RepertoireNode nodeFromMoves(List<String> moves) {
        RepertoireNode? current;
        for (var i = moves.length - 1; i >= 0; i--) {
          final san = moves[i];
          current = RepertoireNode(
            id: 'node-$i',
            fen: '',
            fenKey: '',
            incomingMove: RepertoireMove(from: '', to: '', san: san),
            children: current != null ? [current] : const [],
          );
        }
        return RepertoireNode(
          id: 'root',
          fen: '',
          fenKey: '',
          children: current != null ? [current] : const [],
        );
      }

      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e6', 'd4', 'd5'])),
        'French Defense',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'c5', 'Nf3', 'd6'])),
        'Sicilian Defense',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'c6', 'd4', 'd5'])),
        'Caro-Kann Defense',
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'd5'])), 'Scandinavian Defense');
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'])),
        'Ruy Lopez',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4'])),
        'Italian Game',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'd5', 'c4', 'e6'])),
        "Queen's Gambit",
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'd5', 'c4', 'c6'])), 'Slav Defense');
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'd5'])),
        'Grünfeld Defense',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'g6', 'Nc3', 'Bg7'])),
        "King's Indian Defense",
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'd5', 'Bf4'])), 'London System');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['c4', 'e5'])), 'English Opening');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['Nf3', 'd5'])), 'Réti Opening');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4'])), isNull);
      expect(detectOpeningFamilyFromMoves(null), isNull);

      // Mainline priority: first child is mainline (e4 e6 French), last is sideline (c5 Sicilian)
      const branchingRoot = RepertoireNode(
        id: 'root',
        fen: '',
        fenKey: '',
        children: [
          RepertoireNode(
            id: 'n1',
            fen: '',
            fenKey: '',
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'n2a',
                fen: '',
                fenKey: '',
                incomingMove: RepertoireMove(from: 'e7', to: 'e6', san: 'e6'),
              ),
              RepertoireNode(
                id: 'n2b',
                fen: '',
                fenKey: '',
                incomingMove: RepertoireMove(from: 'c7', to: 'c5', san: 'c5'),
              ),
            ],
          ),
        ],
      );
      expect(detectOpeningFamilyFromMoves(branchingRoot), 'French Defense');

      // Additional e4 branches
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'Nc6', 'd3'])),
        'Open Game',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'Nc6', 'd4'])),
        'Scotch Game',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'Nf6'])),
        'Petrov Defense',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nf3', 'd6'])),
        'Philidor Defense',
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'f4'])), "King's Gambit");
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'e5', 'Nc3'])), 'Vienna Game');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'Nf6'])), 'Alekhine Defense');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'd6'])), 'Pirc Defense');
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['e4', 'g6'])), 'Modern Defense');

      // Additional d4 branches
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'd5', 'Nf3', 'Nf6', 'Bf4'])),
        'London System',
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'Bf4'])), 'London System');
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'Nf3', 'e6', 'Bf4'])),
        'London System',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'e6', 'Nc3', 'Bb4'])),
        'Nimzo-Indian Defense',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'e6', 'Nf3', 'b6'])),
        "Queen's Indian Defense",
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'e6', 'g3'])),
        'Catalan Opening',
      );
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'Nf6', 'c4', 'c5'])),
        'Benoni Defense',
      );
      expect(detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'f5'])), 'Dutch Defense');
      expect(
        detectOpeningFamilyFromMoves(nodeFromMoves(['d4', 'd5', 'Nf3', 'Nf6'])),
        "Queen's Pawn Game",
      );
    });

    test('detectOpeningFamilyFromFen classifies openings from custom starting position', () {
      // After 1. e4 e6 2. d4 (French Defense)
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/pppp1ppp/4p3/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 1'),
        'French Defense',
      );
      // After 1. e4 e6 2. d4 d5 3. Nc3 (French Winawer/Classical setup)
      expect(
        detectOpeningFamilyFromFen(
          'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/2N5/PPP2PPP/R1BQKBNR b KQkq - 0 1',
        ),
        'French Defense',
      );
      // After 1. e4 c5 (Sicilian)
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
        'Sicilian Defense',
      );
      // After 1. e4 c6 (Caro-Kann)
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
        'Caro-Kann Defense',
      );
      // Scandinavian: Black has d5, White has e4, no d4
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
        'Scandinavian Defense',
      );
      // Queen's Gambit: White has d4 and c4, Black has d5
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2'),
        "Queen's Gambit",
      );
      // Slav: White has d4 and c4, Black has d5 and c6
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3'),
        'Slav Defense',
      );
      // King's Indian: White has d4 and c4, Black has g6
      expect(
        detectOpeningFamilyFromFen('rnbqk2r/ppppppbp/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 1 3'),
        "King's Indian Defense",
      );
      // Grünfeld: White has d4 and c4, Black has g6 and d5
      expect(
        detectOpeningFamilyFromFen(
          'rnbqkb1r/ppp1pp1p/5np1/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3',
        ),
        'Grünfeld Defense',
      );
      // Non-matching starting position returns null
      expect(
        detectOpeningFamilyFromFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
        isNull,
      );
    });

    test(
      'extractOpeningFamily uses move inspection when Opening header is missing or question mark',
      () {
        const root = RepertoireNode(
          id: 'root',
          fen: '',
          fenKey: '',
          children: [
            RepertoireNode(
              id: 'n1',
              fen: '',
              fenKey: '',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'n2',
                  fen: '',
                  fenKey: '',
                  incomingMove: RepertoireMove(from: 'e7', to: 'e6', san: 'e6'),
                ),
              ],
            ),
          ],
        );

        // Missing Opening header entirely
        expect(extractOpeningFamily({}, root: root), 'French Defense');
        // Opening header with ?
        expect(extractOpeningFamily({'Opening': '?'}, root: root), 'French Defense');
        // Event header that merely mentions an opening is ignored in favor of moves
        expect(extractOpeningFamily({'Event': 'White vs French'}, root: root), 'French Defense');

        // Direct Opening header wins outright without needing root
        expect(extractOpeningFamily({'Opening': 'Ruy Lopez: Morphy Defense'}), 'Ruy Lopez');
        expect(extractOpeningFamily({'Opening': 'Sicilian Defense'}), 'Sicilian Defense');

        // Event header fallback without Opening header or root
        expect(extractOpeningFamily({'Event': 'Sicilian Defense'}), 'Sicilian Defense');
        expect(extractOpeningFamily({'Event': 'French Defence - Winawer'}), 'French Defense');
        // Event header starting with "Game " is ignored
        expect(extractOpeningFamily({'Event': 'Game 1'}), isNull);

        // ECO header fallback when Opening and Event are missing
        expect(extractOpeningFamily({'ECO': 'B20'}), 'Sicilian Defense');
        expect(extractOpeningFamily({'ECO': 'C60'}), 'Ruy Lopez');

        // startingFen fallback when headers and root are absent
        expect(
          extractOpeningFamily(
            {},
            startingFen: 'rnbqkbnr/pppp1ppp/4p3/8/3PP3/8/PPP2PPP/RNBQKBNR b KQkq - 0 1',
          ),
          'French Defense',
        );
      },
    );
  });
}
