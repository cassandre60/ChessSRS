// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Repertoire decision points and card structures.
library;

import 'package:chess_srs/src/domain/ids.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';

/// A lightweight projection of a decision for due-summary tallies,
/// omitting moves and node IDs to avoid parsing and allocation.
abstract interface class TallyDecision {
  String get id;
  String get studyId;
  String get chapterId;
  String get canonicalId;
}

/// Simple implementation of [TallyDecision] constructed from row projections.
class SimpleTallyDecision implements TallyDecision {
  const SimpleTallyDecision({
    required this.id,
    required this.studyId,
    required this.chapterId,
    required this.canonicalId,
  });

  @override
  final String id;
  @override
  final String studyId;
  @override
  final String chapterId;
  @override
  final String canonicalId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TallyDecision &&
          other.id == id &&
          other.studyId == studyId &&
          other.chapterId == chapterId &&
          other.canonicalId == canonicalId;

  @override
  int get hashCode => Object.hash(id, studyId, chapterId, canonicalId);

  @override
  String toString() => 'SimpleTallyDecision(id: $id, canonical: $canonicalId)';
}

/// The scheduled unit of active recall.
///
/// A [RepertoireDecision] represents a *position from the player's perspective*
/// in which the player must recall one of the expected repertoire continuations.
///
/// Only moves the **player must recall** become decisions. Opponent moves are
/// not independently scheduled — they are auto-played during traversal.
///
/// Inspired by chessrs `Move` entity (GPL-3.0, ZackMurry/chessrs); reimplemented
/// cleanly in Dart against our own contracts.
class RepertoireDecision implements TallyDecision {
  const RepertoireDecision({
    required this.id,
    required this.studyId,
    required this.chapterId,
    required this.nodeId,
    required this.expectedMoves,
    this.canonicalStateId,
  });

  /// Creates a new [RepertoireDecision] with a freshly-generated UUID.
  factory RepertoireDecision.create({
    required String studyId,
    required String chapterId,
    required String nodeId,
    required List<RepertoireMove> expectedMoves,
    String? canonicalStateId,
  }) {
    return RepertoireDecision(
      id: newId(),
      studyId: studyId,
      chapterId: chapterId,
      nodeId: nodeId,
      expectedMoves: List.unmodifiable(expectedMoves),
      canonicalStateId: canonicalStateId,
    );
  }

  @override
  final String id;
  @override
  final String studyId;
  @override
  final String chapterId;

  /// The [RepertoireNode.id] of the position from which the player must move.
  final String nodeId;

  /// Accepted repertoire continuations. Any matching move is considered correct.
  final List<RepertoireMove> expectedMoves;

  /// Pointer to the shared [PositionKnowledgeState.canonicalId].
  /// Nullable for backwards compatibility with pre-v10 databases.
  final String? canonicalStateId;

  /// Effective canonical knowledge identifier: [canonicalStateId] if set, else [id].
  @override
  String get canonicalId => canonicalStateId ?? id;

  /// Returns true if [move] is one of the accepted continuations.
  bool accepts(RepertoireMove move) => expectedMoves.any((m) => m.matches(move));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepertoireDecision &&
          other.id == id &&
          other.studyId == studyId &&
          other.chapterId == chapterId &&
          other.nodeId == nodeId &&
          other.canonicalStateId == canonicalStateId;

  @override
  int get hashCode => Object.hash(id, studyId, chapterId, nodeId, canonicalStateId);

  @override
  String toString() => 'RepertoireDecision(id: $id, nodeId: $nodeId, canonical: $canonicalId)';
}
