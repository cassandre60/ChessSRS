// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:dartchess/dartchess.dart' show Side;

/// A minimal PGN carrying a single FEN, so the analysis screen opens on a known position.
///
/// `PgnGame.parsePgn` honours the FEN header, which is what lets an analysis board be
/// seeded from a bare position instead of a move list.
String reviewPositionPgn(String fen) => '[FEN "$fen"]\n\n*';

/// Formats a list of SAN moves into a standard PGN move text (e.g. "1. e4 d5 2. exd5").
String movesToPgn(List<String> moves) {
  if (moves.isEmpty) return '*';
  final buffer = StringBuffer();
  for (var i = 0; i < moves.length; i++) {
    if (i.isEven) {
      buffer.write('${(i ~/ 2) + 1}. ');
    }
    buffer.write('${moves[i]} ');
  }
  buffer.write('*');
  return buffer.toString().trim();
}

/// Analysis options for the review board's live position, including the move history that led to it.
/// Falling back to a blank standalone board when there is no review position.
///
/// Used by the review screen's "Open in analysis" action so the analysis board opens
/// with full move navigation up to the current position rather than a blank board.
AnalysisOptions analysisOptionsForReviewPosition({
  String? fen,
  required Side orientation,
  List<String> moveHistory = const [],
}) {
  if (fen == null && moveHistory.isEmpty) {
    return const AnalysisOptions.standalone(variant: Variant.standard);
  }

  final String pgn;
  if (moveHistory.isNotEmpty) {
    pgn = movesToPgn(moveHistory);
  } else {
    pgn = reviewPositionPgn(fen!);
  }

  return AnalysisOptions.pgn(
    id: const StringId('review_position'),
    orientation: orientation,
    pgn: pgn,
    isComputerAnalysisAllowed: true,
    variant: Variant.standard,
  );
}
