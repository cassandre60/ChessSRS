// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.repertoire_move;

// SPDX-License-Identifier: GPL-3.0-or-later

/// A chess move in UCI notation stored in the domain layer.
///
/// This is a *domain* value — a thin named container for UCI coordinates.
/// It is not a dartchess [Move]; the import pipeline converts dartchess moves
/// into these after legal-move validation. The Review engine similarly converts
/// user input to this type before matching against [RepertoireDecision.expectedMoves].
///
/// Position identity is by [from]/[to]/[promotion] only (no FEN context stored
/// here). FEN context is on the parent [RepertoireNode].
class RepertoireMove {
  const RepertoireMove({required this.from, required this.to, this.promotion, this.san});

  /// Origin square, e.g. `'e2'`.
  final String from;

  /// Target square, e.g. `'e4'`.
  final String to;

  /// Promotion piece character (`'q'`, `'r'`, `'b'`, `'n'`) or null.
  final String? promotion;

  /// Standard Algebraic Notation label for display, e.g. `'e4'`, `'Nf6'`.
  /// Optional — may be null if not yet resolved.
  final String? san;

  /// Returns the UCI string for this move, e.g. `'e2e4'` or `'e7e8q'`.
  String get uci => '$from$to${promotion ?? ''}';

  static const _kingTakesRookCastles = {
    'e1c1': 'e1a1',
    'e1g1': 'e1h1',
    'e8c8': 'e8a8',
    'e8g8': 'e8h8',
  };

  static String _normalizeUci(String moveUci) => _kingTakesRookCastles[moveUci] ?? moveUci;

  /// Returns true when [other] represents the same move (from/to/promotion),
  /// including equivalence between standard and king-takes-rook castling notations
  /// (e.g. e1g1 matches e1h1 for O-O, e1c1 matches e1a1 for O-O-O).
  bool matches(RepertoireMove other) {
    if (promotion != other.promotion) return false;
    final f1 = from.toLowerCase();
    final t1 = to.toLowerCase();
    final f2 = other.from.toLowerCase();
    final t2 = other.to.toLowerCase();
    if (f1 == f2 && t1 == t2) return true;
    return _normalizeUci('$f1$t1') == _normalizeUci('$f2$t2');
  }

  RepertoireMove copyWith({String? from, String? to, String? promotion, String? san}) {
    return RepertoireMove(
      from: from ?? this.from,
      to: to ?? this.to,
      promotion: promotion ?? this.promotion,
      san: san ?? this.san,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepertoireMove &&
          other.from == from &&
          other.to == to &&
          other.promotion == promotion;

  @override
  int get hashCode => Object.hash(from, to, promotion);

  @override
  String toString() => 'RepertoireMove($uci${san != null ? ' / $san' : ''})';
}
