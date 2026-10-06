// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.chapter;
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/ids.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:dartchess/dartchess.dart' show Side;

/// A single chapter within a [Study], corresponding to one PGN game.
///
/// A chapter owns its [root] position tree. When the source PGN uses a
/// non-standard starting position (FEN header), [startingFen] captures it.
/// Source order ([sourceOrder]) preserves the chapter sequence from the file.
class Chapter {
  const Chapter({
    required this.id,
    required this.studyId,
    required this.sourceOrder,
    this.title,
    this.startingFen,
    this.root,
    this.createdAt,
    this.opening,
    this.orientation = Side.white,
  });

  /// Creates a new [Chapter] with a freshly-generated UUID.
  factory Chapter.create({
    required String studyId,
    required int sourceOrder,
    String? title,
    String? startingFen,
    RepertoireNode? root,
    DateTime? createdAt,
    String? opening,
    Side orientation = Side.white,
  }) {
    return Chapter(
      id: newId(),
      studyId: studyId,
      sourceOrder: sourceOrder,
      title: title,
      startingFen: startingFen,
      root: root,
      createdAt: createdAt ?? DateTime.now(),
      opening: opening,
      orientation: orientation,
    );
  }

  final String id;
  final String studyId;

  /// Position of this chapter among siblings (0-based).
  final int sourceOrder;

  /// Optional human-readable chapter name from the PGN.
  final String? title;

  /// Non-standard starting FEN (null ⇒ standard initial position).
  final String? startingFen;

  /// Root of the repertoire position tree for this chapter.
  final RepertoireNode? root;

  final DateTime? createdAt;

  /// Classified opening family name (e.g. "Sicilian Defense", "French Defense").
  final String? opening;

  /// The player perspective / board orientation for this chapter (White or Black).
  final Side orientation;

  Chapter copyWith({
    String? title,
    String? startingFen,
    RepertoireNode? root,
    String? opening,
    Side? orientation,
  }) {
    return Chapter(
      id: id,
      studyId: studyId,
      sourceOrder: sourceOrder,
      title: title ?? this.title,
      startingFen: startingFen ?? this.startingFen,
      root: root ?? this.root,
      createdAt: createdAt,
      opening: opening ?? this.opening,
      orientation: orientation ?? this.orientation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Chapter &&
          other.id == id &&
          other.studyId == studyId &&
          other.sourceOrder == sourceOrder &&
          other.title == title &&
          other.startingFen == startingFen &&
          other.root == root &&
          other.opening == opening &&
          other.orientation == orientation;

  @override
  int get hashCode =>
      Object.hash(id, studyId, sourceOrder, title, startingFen, root, opening, orientation);

  @override
  String toString() =>
      'Chapter(id: $id, studyId: $studyId, title: $title, opening: $opening, orientation: $orientation)';
}
