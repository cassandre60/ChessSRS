// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:dartchess/dartchess.dart' show Side;

/// Scope filter for a review session.
class ReviewScope {
  const ReviewScope.all() : this._(null);

  /// Every position trained as that side, across all active studies (INV-030).
  const ReviewScope.white() : this._(Side.white);
  const ReviewScope.black() : this._(Side.black);
  const ReviewScope._(this.side) : studyId = null, chapterId = null, openingFamily = null;

  const ReviewScope.study(String this.studyId)
    : chapterId = null,
      openingFamily = null,
      side = null;

  const ReviewScope.chapter({required String this.studyId, required String this.chapterId})
    : openingFamily = null,
      side = null;

  const ReviewScope.opening(String this.openingFamily)
    : studyId = null,
      chapterId = null,
      side = null;

  final String? studyId;
  final String? chapterId;
  final String? openingFamily;

  /// The repertoire side this scope is restricted to, or null for no restriction.
  ///
  /// Set on every scope a drawer can produce — a colour, a study, an opening —
  /// because the top bar's squares read it to show which drawer is live. A scope
  /// with no side is one the colour switch has nothing to say about: the initial
  /// `all()`, and nothing the user reached by tapping.
  final Side? side;

  bool matches({
    required String studyId,
    required String chapterId,
    String? openingFamily,
    Side? side,
  }) {
    if (this.studyId != null && this.studyId != studyId) return false;
    if (this.chapterId != null && this.chapterId != chapterId) return false;
    if (this.openingFamily != null &&
        // Opening names come from PGN headers and may carry stray whitespace;
        // compare trimmed so loading and queue filtering agree.
        (openingFamily?.trim() ?? '') != this.openingFamily!.trim()) {
      return false;
    }
    // A null `side` means the caller's chapter was unresolvable, which is not the
    // same as a resolved White chapter: admitting it would let an unresolvable
    // position back into a queue the user narrowed by colour.
    return this.side == null || side == this.side;
  }

  /// Whether this scope spans studies rather than naming one.
  bool get isAggregate => studyId == null && chapterId == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewScope &&
          other.studyId == studyId &&
          other.chapterId == chapterId &&
          other.openingFamily == openingFamily &&
          other.side == side;

  @override
  int get hashCode => Object.hash(studyId, chapterId, openingFamily, side);

  @override
  String toString() =>
      'ReviewScope(study: $studyId, chapter: $chapterId, opening: $openingFamily, side: $side)';
}
