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

/// Analysis options for the review board's live position, falling back to a blank standalone
/// board when there is no review position.
///
/// Used by the review screen's "Open in analysis" action (owner report 2026-09-29: the analysis
/// board should open where the user already is rather than on the start position).
AnalysisOptions analysisOptionsForReviewPosition({String? fen, required Side orientation}) {
  if (fen == null) return const AnalysisOptions.standalone(variant: Variant.standard);
  return AnalysisOptions.pgn(
    id: const StringId('review_position'),
    orientation: orientation,
    pgn: reviewPositionPgn(fen),
    isComputerAnalysisAllowed: true,
    variant: Variant.standard,
  );
}
