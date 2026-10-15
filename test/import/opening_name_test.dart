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
      },
    );
  });
}
