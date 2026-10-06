// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Repertoire tree node hierarchy.
library;

import 'package:chess_srs/src/domain/ids.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';

/// A node in the repertoire position tree.
///
/// Each node represents a distinct chess position (identified by its 4-field
/// FEN key). The edges to children are the legal moves from this position.
/// The incoming move ([incomingMove]) is the move that led to this position
/// from its parent.
///
/// **Variation preservation**: multiple children at any node are first-class
/// siblings — they represent PGN recursive annotation variations (RAVs).
/// They must never be flattened or silently dropped (QUALITY.md §2.2).
///
/// **Position identity**: [fen] is the full FEN; [fenKey] is the normalized
/// 4-field FEN (placement + turn + castling + en-passant) used as a stable
/// identity key (QUALITY.md §2.3).
class RepertoireNode {
  const RepertoireNode({
    required this.id,
    required this.fen,
    required this.fenKey,
    this.incomingMove,
    this.comment,
    this.children = const [],
  });

  /// Creates a root node (no incoming move, no parent).
  factory RepertoireNode.root({required String fen, required String fenKey, String? comment}) {
    return RepertoireNode(
      id: newId(),
      fen: fen,
      fenKey: fenKey,
      incomingMove: null,
      comment: comment,
      children: const [],
    );
  }

  /// Creates a child node reached via [incomingMove].
  factory RepertoireNode.child({
    required String fen,
    required String fenKey,
    required RepertoireMove incomingMove,
    String? comment,
  }) {
    return RepertoireNode(
      id: newId(),
      fen: fen,
      fenKey: fenKey,
      incomingMove: incomingMove,
      comment: comment,
      children: const [],
    );
  }

  /// Stable UUID for this node (used as a foreign key by [RepertoireDecision]).
  final String id;

  /// Full FEN string (6 fields including half-moves and full-move number).
  final String fen;

  /// 4-field position identity: `<placement> <turn> <castling> <ep>`.
  /// Used as the persistent key for SRS decisions (QUALITY.md §2.3).
  final String fenKey;

  /// The move that was played to reach this position from the parent.
  /// Null for the root node.
  final RepertoireMove? incomingMove;

  /// PGN comment text for this position, if any.
  final String? comment;

  /// Child positions reachable by legal moves from this position.
  /// Order matters: first child is the mainline; others are variations.
  final List<RepertoireNode> children;

  /// Whether this node is a leaf (no continuations recorded).
  bool get isLeaf => children.isEmpty;

  /// Adds a child, returning a new node (immutable update).
  RepertoireNode addChild(RepertoireNode child) {
    return RepertoireNode(
      id: id,
      fen: fen,
      fenKey: fenKey,
      incomingMove: incomingMove,
      comment: comment,
      children: [...children, child],
    );
  }

  /// Finds the child reached by [move], or null if not found.
  RepertoireNode? childForMove(RepertoireMove move) {
    for (final child in children) {
      if (child.incomingMove?.matches(move) == true) return child;
    }
    return null;
  }

  /// All moves available from this position.
  List<RepertoireMove> get childMoves =>
      children.map((c) => c.incomingMove!).toList(growable: false);

  RepertoireNode copyWith({
    List<RepertoireNode>? children,
    String? comment,
    RepertoireMove? incomingMove,
  }) {
    return RepertoireNode(
      id: id,
      fen: fen,
      fenKey: fenKey,
      incomingMove: incomingMove ?? this.incomingMove,
      comment: comment ?? this.comment,
      children: children ?? this.children,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RepertoireNode && other.id == id && other.fenKey == fenKey;

  @override
  int get hashCode => Object.hash(id, fenKey);

  @override
  String toString() => 'RepertoireNode(id: $id, fenKey: $fenKey)';
}
