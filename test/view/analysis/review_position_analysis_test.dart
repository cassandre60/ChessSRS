// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/view/analysis/analysis_options.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysisOptionsForReviewPosition includes move history so analysis is not blank', () {
    const fen = 'rnb1kbnr/ppp1pppp/8/q7/8/2N5/PPPP1PPP/R1BQKBNR w KQkq - 0 3';
    final options = analysisOptionsForReviewPosition(
      fen: fen,
      orientation: Side.white,
      moveHistory: const ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5'],
    );

    expect(options, isA<Pgn>());
    final pgnOption = options as Pgn;
    expect(pgnOption.pgn, contains('1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5'));

    // Verify it parses into a game tree with moves
    final game = PgnGame.parsePgn(pgnOption.pgn);
    final root = Root.fromPgnGame(game);
    expect(root.children, isNotEmpty);
    expect(root.children.first.sanMove.san, 'e4');

    // Walk to end of mainline: the position must match the reviewed FEN
    Node current = root;
    for (final san in ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qa5']) {
      final next = current.children.where((b) => b.sanMove.san == san).firstOrNull;
      expect(next, isNotNull, reason: 'Move $san must be in the game tree');
      current = next!;
    }
    expect(
      current.position.fen,
      startsWith('rnb1kbnr/ppp1pppp/8/q7/8/2N5/PPPP1PPP/R1BQKBNR w KQkq -'),
    );
  });

  test('analysisOptionsForReviewPosition falls back gracefully when move history is empty', () {
    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final options = analysisOptionsForReviewPosition(
      fen: fen,
      orientation: Side.white,
      moveHistory: const [],
    );

    expect(options, isA<Pgn>());
    final pgnOption = options as Pgn;
    expect(pgnOption.pgn, contains(fen));
  });
}
