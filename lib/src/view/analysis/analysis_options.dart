// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:dartchess/dartchess.dart' show Position, Rule, Setup, Side, kInitialFEN;
import 'package:logging/logging.dart';

final Logger _logger = Logger('AnalysisOptions');

/// A minimal PGN carrying a single FEN, so the analysis screen opens on a known position.
///
/// `PgnGame.parsePgn` honours the FEN header, which is what lets an analysis board be
/// seeded from a bare position instead of a move list.
String reviewPositionPgn(String fen) => '[FEN "$fen"]\n\n*';

/// Formats a list of SAN moves into a standard PGN move text (e.g. "1. e4 d5 2. exd5").
String movesToPgn(List<String> moves, {String? startingFen}) {
  final rootFen = (startingFen != null && startingFen.trim().isNotEmpty)
      ? startingFen.trim()
      : kInitialFEN;
  final header = rootFen != kInitialFEN ? '[SetUp "1"]\n[FEN "$rootFen"]\n\n' : '';
  if (moves.isEmpty) return '$header*'.trim();

  Position? pos;
  try {
    pos = Position.setupPosition(Rule.chess, Setup.parseFen(rootFen));
  } catch (_) {
    pos = null;
  }

  final buffer = StringBuffer(header);
  if (pos != null) {
    var currentPos = pos;
    var ok = true;
    final movesBuf = StringBuffer();
    for (var i = 0; i < moves.length; i++) {
      final san = moves[i];
      final move = currentPos.parseSan(san);
      if (move == null) {
        ok = false;
        break;
      }
      if (currentPos.turn == Side.white) {
        movesBuf.write('${currentPos.fullmoves}. $san ');
      } else if (i == 0) {
        movesBuf.write('${currentPos.fullmoves}... $san ');
      } else {
        movesBuf.write('$san ');
      }
      currentPos = currentPos.playUnchecked(move);
    }
    if (ok) {
      buffer.write(movesBuf);
      buffer.write('*');
      return buffer.toString().trim();
    }
  }

  for (var i = 0; i < moves.length; i++) {
    if (i.isEven) {
      buffer.write('${(i ~/ 2) + 1}. ');
    }
    buffer.write('${moves[i]} ');
  }
  buffer.write('*');
  return buffer.toString().trim();
}

String _fenKeyOf(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length >= 4 ? parts.take(4).join(' ') : fen.trim();
}

/// Analysis options for the review board's live position, including the move history that led to it
/// and the repertoire continuation after it.
/// Falling back to a blank standalone board when there is no review position.
///
/// Used by the review screen's "Open in analysis" action so the analysis board opens
/// with full move navigation at the drilled position rather than a blank board.
AnalysisOptions analysisOptionsForReviewPosition({
  String? fen,
  String? startingFen,
  required Side orientation,
  List<String> moveHistory = const [],
  List<String> continuationMoves = const [],
}) {
  if (fen == null && moveHistory.isEmpty && continuationMoves.isEmpty) {
    return const AnalysisOptions.standalone(variant: Variant.standard);
  }

  final rootFenCandidate = (startingFen != null && startingFen.trim().isNotEmpty)
      ? startingFen.trim()
      : kInitialFEN;

  String effectiveRootFen = fen ?? rootFenCandidate;
  List<String> validHistory = const [];
  Position? posAfterHistory;

  if (moveHistory.isNotEmpty) {
    for (final candidate in [rootFenCandidate, if (rootFenCandidate != kInitialFEN) kInitialFEN]) {
      try {
        var pos = Position.setupPosition(Rule.chess, Setup.parseFen(candidate));
        var ok = true;
        for (final san in moveHistory) {
          final move = pos.parseSan(san);
          if (move == null) {
            ok = false;
            break;
          }
          pos = pos.playUnchecked(move);
        }
        if (ok) {
          effectiveRootFen = candidate;
          validHistory = moveHistory;
          posAfterHistory = pos;
          break;
        }
      } catch (e, st) {
        // An unparseable starting position must surface the failure; swallowing it
        // silently would discard the reviewed move history without a trace.
        _logger.warning(
          'Unable to apply review move history from starting position "$candidate"',
          e,
          st,
        );
      }
    }
  }

  if (posAfterHistory == null) {
    try {
      posAfterHistory = Position.setupPosition(Rule.chess, Setup.parseFen(effectiveRootFen));
    } catch (_) {
      posAfterHistory = null;
    }
  }

  final validContinuation = <String>[];
  int? matchedCursor;
  if (posAfterHistory != null && continuationMoves.isNotEmpty) {
    var pos = posAfterHistory;
    final targetKey = fen != null ? _fenKeyOf(fen) : null;
    for (var i = 0; i < continuationMoves.length; i++) {
      final san = continuationMoves[i];
      final move = pos.parseSan(san);
      if (move == null) break;
      validContinuation.add(san);
      pos = pos.playUnchecked(move);
      if (targetKey != null && _fenKeyOf(pos.fen) == targetKey) {
        matchedCursor = validHistory.length + i + 1;
      }
    }
  }

  final allMoves = [...validHistory, ...validContinuation];
  final String pgn;
  int? initialMoveCursor;

  if (allMoves.isEmpty) {
    pgn = reviewPositionPgn(effectiveRootFen);
  } else {
    final withMoves = movesToPgn(allMoves, startingFen: effectiveRootFen);
    // Keep the [FEN "..."] header present even when starting from kInitialFEN so callers
    // and tests inspecting the seeded FEN alongside the move list find both.
    pgn = effectiveRootFen == kInitialFEN ? '[FEN "$effectiveRootFen"]\n\n$withMoves' : withMoves;
    if (validContinuation.isNotEmpty) {
      initialMoveCursor = matchedCursor ?? validHistory.length;
    }
  }

  return AnalysisOptions.pgn(
    id: const StringId('review_position'),
    orientation: orientation,
    initialMoveCursor: initialMoveCursor,
    pgn: pgn,
    isComputerAnalysisAllowed: true,
    variant: Variant.standard,
  );
}
