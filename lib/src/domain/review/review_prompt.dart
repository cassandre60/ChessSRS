// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review.review_engine;
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:dartchess/dartchess.dart';

/// The active position presented to the user during a review session.
class ReviewPrompt {
  const ReviewPrompt({
    required this.decision,
    required this.studyId,
    required this.chapterId,
    required this.nodeId,
    required this.fen,
    required this.fenKey,
    required this.sideToMove,
    required this.expectedMoves,
    this.currentNode,
    this.comment,
    this.studyTitle,
    this.chapterTitle,
    this.parentFen,
    this.incomingMove,
    this.moveHistory = const [],
  });

  final RepertoireDecision decision;
  final String studyId;
  final String chapterId;
  final String nodeId;
  final String fen;
  final String fenKey;
  final Side sideToMove;
  final List<RepertoireMove> expectedMoves;
  final RepertoireNode? currentNode;
  final String? comment;
  final String? studyTitle;
  final String? chapterTitle;
  final String? parentFen;
  final RepertoireMove? incomingMove;
  final List<String> moveHistory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewPrompt &&
          other.decision.id == decision.id &&
          other.nodeId == nodeId &&
          other.fenKey == fenKey;

  @override
  int get hashCode => Object.hash(decision.id, nodeId, fenKey);

  @override
  String toString() =>
      'ReviewPrompt(decision: ${decision.id}, fen: $fenKey, moves: ${expectedMoves.length})';
}

/// A move automatically played by the review engine during auto-traversal
/// (opponent replies or already-learned user moves).
class AutoPlayedMove {
  const AutoPlayedMove({
    required this.move,
    required this.fenBefore,
    required this.fenAfter,
    required this.isUserMove,
    this.comment,
  });

  final RepertoireMove move;
  final String fenBefore;
  final String fenAfter;
  final bool isUserMove;
  final String? comment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoPlayedMove &&
          other.move == move &&
          other.fenBefore == fenBefore &&
          other.fenAfter == fenAfter &&
          other.isUserMove == isUserMove;

  @override
  int get hashCode => Object.hash(move, fenBefore, fenAfter, isUserMove);

  @override
  String toString() => 'AutoPlayedMove(${move.san ?? "${move.from}${move.to}"}, user: $isUserMove)';
}
