// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/domain/review_state.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// Computes the canonical identity key for a position + expected move memory item.
///
/// Formatted as: sha1("$fenKey|$expectedMoveUci")
/// Allows transpositions across different chapters and studies to converge on a single
/// canonical [PositionKnowledgeState] memory item.
String canonicalKey(String fenKey, String expectedMoveUci) {
  final input = '$fenKey|$expectedMoveUci';
  return sha1.convert(utf8.encode(input)).toString();
}

/// Computes the canonical identity key for a position and its *complete* set of accepted
/// continuations.
///
/// Formatted as: `sha1("<fenKey>|<sorted uci>|<sorted uci>|...")`.
///
/// A repertoire position is not identified by one representative move: it is identified by the
/// whole question it asks the player ("from here, any of these is correct"). Two positions that
/// share a FEN and a first move but offer different continuation sets are different questions and
/// must not share SRS memory, so every accepted move participates in the key.
///
/// The moves are sorted, so two PGNs that spell the same repertoire with their branches in a
/// different order converge on the same memory item rather than forking it.
///
/// Occurrence identity is deliberately *not* part of this key. [RepertoireDecision.id] is the
/// per-occurrence identity; this is the shared position knowledge that transpositions converge on.
String canonicalKeyForPosition(String fenKey, Iterable<String> acceptedMoveUcis) {
  final sortedMoves = acceptedMoveUcis.toList()..sort();
  return sha1.convert(utf8.encode([fenKey, ...sortedMoves].join('|'))).toString();
}

/// The single source of truth for long-term memory of a specific chess position and move.
///
/// Keyed by [canonicalId] = `sha1(fenKey + expectedMoveUci)`. Multiple [RepertoireDecision]s
/// across different chapters and studies pointing to the same position and continuation
/// share this single state.
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
  });

  /// Creates a cold (unreviewed) knowledge state.
  factory PositionKnowledgeState.cold(String canonicalId) =>
      PositionKnowledgeState(canonicalId: canonicalId);

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
          other.latencySampleCount == latencySampleCount;

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
  );

  @override
  String toString() =>
      'PositionKnowledgeState(id: $canonicalId, reps: $repetitionCount, lapses: $lapseCount, due: $nextDueAt)';
}
