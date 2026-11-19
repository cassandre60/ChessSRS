// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Knowledge state and memory retention models for board positions.
library;

import 'dart:convert';

import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:crypto/crypto.dart';
import 'package:dartchess/dartchess.dart';
import 'package:meta/meta.dart';

/// Canonical SHA-1 identity for a position + single move (`sha1("$fenKey|$expectedMoveUci")`).
String canonicalKey(String fenKey, String expectedMoveUci) =>
    sha1.convert(utf8.encode('$fenKey|${RepertoireMove.normalizeUci(expectedMoveUci)}')).toString();

/// Canonical SHA-1 identity for a position and its complete accepted move set
/// (`sha1("<repertoireSide>|<fenKey>|<sorted uci>|...")`, SPEC INV-016, INV-017, INV-033).
String canonicalKeyForPosition(
  String fenKey,
  Iterable<String> acceptedMoveUcis, {
  required Side repertoireSide,
}) {
  final sortedMoves = acceptedMoveUcis.map(RepertoireMove.normalizeUci).toList()..sort();
  return sha1
      .convert(utf8.encode([repertoireSide.name, fenKey, ...sortedMoves].join('|')))
      .toString();
}

/// Shared long-term SRS memory for a position and accepted continuation set (`canonicalId`).
@immutable
class PositionKnowledgeState {
  const PositionKnowledgeState({
    required this.canonicalId,
    this.firstReviewedAt,
    this.lastReviewedAt,
    this.nextDueAt,
    this.repetitionCount = 0,
    this.lapseCount = 0,
    this.stability = 0.0,
    this.difficulty = 0.0,
    this.latencyEmaMs,
    this.latencySampleCount = 0,
    this.lastExposedAt,
  });

  /// Creates a cold (unreviewed) knowledge state.
  factory PositionKnowledgeState.cold(String canonicalId) =>
      PositionKnowledgeState(canonicalId: canonicalId);

  /// Builds the canonical knowledge state for [canonicalId] from an equivalent
  /// [ReviewState]: the single mapping from decision-keyed review memory to
  /// canonical-position knowledge, and the inverse of [toReviewState].
  ///
  /// Latency fields have no counterpart on [ReviewState]; a caller holding only
  /// a review outcome passes no samples ("never measured" by default).
  factory PositionKnowledgeState.fromReviewState(
    ReviewState state, {
    required String canonicalId,
  }) => PositionKnowledgeState(
    canonicalId: canonicalId,
    firstReviewedAt: state.firstReviewedAt,
    lastReviewedAt: state.lastReviewedAt,
    nextDueAt: state.nextDueAt,
    repetitionCount: state.repetitionCount,
    lapseCount: state.lapseCount,
    stability: state.stability,
    difficulty: state.difficulty,
  );

  /// Canonical SHA-1 fingerprint of `<fenKey>|<expectedMoveUci>`.
  final String canonicalId;

  final DateTime? firstReviewedAt;
  final DateTime? lastReviewedAt;
  final DateTime? nextDueAt;

  final int repetitionCount;
  final int lapseCount;

  /// Memory stability in milliseconds.
  final double stability;

  /// Intrinsic difficulty rating on the FSRS scale (1.0 to 10.0).
  final double difficulty;

  /// Exponential moving average of retrieval response latency in milliseconds.
  final double? latencyEmaMs;

  /// Number of active recall latency samples recorded.
  final int latencySampleCount;

  /// When this position last received auto-traversal exposure credit (§B.2). Persisted so the
  /// "once per calendar day" cap survives a restart; null means never exposed, which is correct for
  /// rows written before the column existed. See review-2 C1.
  final DateTime? lastExposedAt;

  bool get isNew => repetitionCount == 0 && nextDueAt == null;
  bool get isLearned => repetitionCount > 0;
  bool isDueAt(DateTime now) => nextDueAt == null || !nextDueAt!.isAfter(now);

  /// Converts this canonical state into a legacy [ReviewState] for backward compatibility.
  ReviewState toReviewState([String? decisionId]) => ReviewState(
    decisionId: decisionId ?? canonicalId,
    firstReviewedAt: firstReviewedAt,
    lastReviewedAt: lastReviewedAt,
    nextDueAt: nextDueAt,
    repetitionCount: repetitionCount,
    lapseCount: lapseCount,
    stability: stability,
    difficulty: difficulty,
  );

  PositionKnowledgeState copyWith({
    DateTime? firstReviewedAt,
    DateTime? lastReviewedAt,
    DateTime? nextDueAt,
    int? repetitionCount,
    int? lapseCount,
    double? stability,
    double? difficulty,
    double? latencyEmaMs,
    int? latencySampleCount,
    DateTime? lastExposedAt,
  }) {
    return PositionKnowledgeState(
      canonicalId: canonicalId,
      firstReviewedAt: firstReviewedAt ?? this.firstReviewedAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      repetitionCount: repetitionCount ?? this.repetitionCount,
      lapseCount: lapseCount ?? this.lapseCount,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      latencyEmaMs: latencyEmaMs ?? this.latencyEmaMs,
      latencySampleCount: latencySampleCount ?? this.latencySampleCount,
      lastExposedAt: lastExposedAt ?? this.lastExposedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PositionKnowledgeState &&
          other.canonicalId == canonicalId &&
          other.firstReviewedAt == firstReviewedAt &&
          other.lastReviewedAt == lastReviewedAt &&
          other.nextDueAt == nextDueAt &&
          other.repetitionCount == repetitionCount &&
          other.lapseCount == lapseCount &&
          other.stability == stability &&
          other.difficulty == difficulty &&
          other.latencyEmaMs == latencyEmaMs &&
          other.latencySampleCount == latencySampleCount &&
          other.lastExposedAt == lastExposedAt;

  @override
  int get hashCode => Object.hash(
    canonicalId,
    firstReviewedAt,
    lastReviewedAt,
    nextDueAt,
    repetitionCount,
    lapseCount,
    stability,
    difficulty,
    latencyEmaMs,
    latencySampleCount,
    lastExposedAt,
  );

  @override
  String toString() =>
      'PositionKnowledgeState(id: $canonicalId, reps: $repetitionCount, lapses: $lapseCount, due: $nextDueAt)';
}
