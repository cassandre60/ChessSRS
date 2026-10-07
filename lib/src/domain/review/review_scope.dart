// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Scope filter for a review session.
class ReviewScope {
  const ReviewScope.all() : studyId = null, chapterId = null, openingFamily = null;

  const ReviewScope.study(String this.studyId) : chapterId = null, openingFamily = null;

  const ReviewScope.chapter({required String this.studyId, required String this.chapterId})
    : openingFamily = null;

  const ReviewScope.opening(String this.openingFamily) : studyId = null, chapterId = null;

  final String? studyId;
  final String? chapterId;
  final String? openingFamily;

  bool matches({required String studyId, required String chapterId, String? openingFamily}) {
    if (this.studyId != null && this.studyId != studyId) {
      return false;
    }
    if (this.chapterId != null && this.chapterId != chapterId) {
      return false;
    }
    if (this.openingFamily != null) {
      // Opening names accumulate surrounding whitespace across imports and
      // classifiers; compare trimmed so loading, counting, and session
      // filtering agree with each other.
      if (openingFamily == null || openingFamily.trim() != this.openingFamily!.trim()) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewScope &&
          other.studyId == studyId &&
          other.chapterId == chapterId &&
          other.openingFamily == openingFamily;

  @override
  int get hashCode => Object.hash(studyId, chapterId, openingFamily);

  @override
  String toString() => 'ReviewScope(study: $studyId, chapter: $chapterId, opening: $openingFamily)';
}
