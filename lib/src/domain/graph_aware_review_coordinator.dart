// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';

/// Representation of a node in the repertoire decision graph for the graph layer.
class GraphNode {
  const GraphNode({
    required this.decisionId,
    required this.parentId,
    required this.fen4,
    required this.expectedMoveUci,
    this.hasCanonicalIdentity = false,
  });

  /// The decision ID.
  final String decisionId;

  /// The parent decision ID, if any.
  final String? parentId;

  /// Normalized 4-field FEN of the decision position.
  final String fen4;

  /// Expected repertoire move in UCI notation (e.g. `e2e4`).
  final String expectedMoveUci;

  /// True when [decisionId] is a complete-set canonical id
  /// ([RepertoireDecision.canonicalStateId]), i.e. it already identifies the
  /// exact question being asked. False for legacy occurrence ids, which predate
  /// complete-set keys and share memory through the single-move adjacency map.
  final bool hasCanonicalIdentity;
}

/// Abstract storage interface providing the graph topology and state lookups
/// needed by [GraphAwareReviewCoordinator].
abstract class ReviewStateRepository {
  /// Retrieves the current review state for [decisionId].
  ReviewState? get(String decisionId);

  /// Stores or updates the review state for [decisionId].
  void put(String decisionId, ReviewState state);

  /// Returns the decision IDs of immediate descendant decisions following [decisionId].
  List<String> childrenOf(String decisionId);

  /// Returns the canonical state ID for a given position and move, or null if unmapped.
  String? canonicalIdFor(String fen4, String expectedMoveUci);
}

/// In-memory implementation of [ReviewStateRepository] for testing and in-memory sessions.
class InMemoryReviewStateRepository implements ReviewStateRepository {
  InMemoryReviewStateRepository({
    Map<String, ReviewState>? initialStates,
    Map<String, List<String>>? childrenMap,
    Map<String, String>? canonicalKeyMap,
  }) : _states = Map.of(initialStates ?? {}),
       _children = Map.of(childrenMap ?? {}),
       _canonicalKeys = Map.of(canonicalKeyMap ?? {});

  final Map<String, ReviewState> _states;
  final Map<String, List<String>> _children;
  final Map<String, String> _canonicalKeys;

  @override
  ReviewState? get(String decisionId) => _states[decisionId];

  @override
  void put(String decisionId, ReviewState state) {
    _states[decisionId] = state;
  }

  @override
  List<String> childrenOf(String decisionId) => _children[decisionId] ?? const [];

  void setChildren(String decisionId, List<String> children) {
    _children[decisionId] = List.unmodifiable(children);
  }

  @override
  String? canonicalIdFor(String fen4, String expectedMoveUci) =>
      _canonicalKeys['$fen4|$expectedMoveUci'];

  void setCanonicalId(String fen4, String expectedMoveUci, String canonicalId) {
    _canonicalKeys['$fen4|$expectedMoveUci'] = canonicalId;
  }
}

/// Tunable parameters for graph propagation effects (ChessSRS Scheduling Architecture §B).
class GraphAwareParams {
  const GraphAwareParams({
    this.contagionBase = 0.18,
    this.contagionTau = 1.5,
    this.maxContagionDepth = 3,
    this.contagionDifficultyBump = 0.6,
    this.exposureStabilityGain = 0.08,
    this.confusionDifficultyCoupling = 0.35,
  });

  /// Maximum stability haircut applied at depth 1 (lambda0 = 0.18).
  final double contagionBase;

  /// Decay rate for contagion depth (tau = 1.5 plies).
  final double contagionTau;

  /// Maximum ply depth for lapse contagion propagation.
  final int maxContagionDepth;

  /// Difficulty increase factor for lapsed subtree (beta = 0.6).
  final double contagionDifficultyBump;

  /// Micro-stability boost factor for auto-traversed non-due moves (epsilon = 0.08).
  final double exposureStabilityGain;

  /// Difficulty increase factor for confusable sibling candidate moves (kappa = 0.35).
  final double confusionDifficultyCoupling;
}

/// The result of an active review processed through the graph coordinator.
class GraphAwareReviewResult {
  const GraphAwareReviewResult({required this.primaryState, this.sideEffectStates = const []});

  /// The updated state for the primary reviewed decision.
  final ReviewState primaryState;

  /// Any secondary states updated as graph side-effects (lapse contagion or confusion coupling).
  final List<ReviewState> sideEffectStates;
}

/// Chess-specific graph propagation layer wrapped around the underlying [Scheduler].
///
/// Implements:
/// 1. Upstream Lapse Contagion (§B.1): soft stability reduction on descendants instead of full subtree resets.
/// 2. Auto-Traversal Exposure Credit (§B.2): micro-stability bump for non-due moves passed over during traversal.
/// 3. Confusable Sibling Coupling (§B.4): coupled difficulty updates when user plays a sibling candidate move.
/// 4. Canonical Transposition Resolution (§B.3): resolves shared positions across studies/chapters.
class GraphAwareReviewCoordinator {
  GraphAwareReviewCoordinator({
    required this.scheduler,
    required this.repo,
    this.params = const GraphAwareParams(),
    Map<String, DateTime>? initialExposureThrottle,
  }) : _lastExposedAt = {...?initialExposureThrottle};

  final Scheduler scheduler;
  final ReviewStateRepository repo;
  final GraphAwareParams params;

  /// Last auto-traversal exposure grant per canonical id (§B.2's once-per-calendar-day cap). Seeded
  /// from the store and re-persisted by the caller, so the cap survives a restart — review-2 C1.
  final Map<String, DateTime> _lastExposedAt;

  /// Resolves the scheduling identity for [node].
  ///
  /// A node carrying a complete-set canonical id is already its own identity:
  /// routing it through the single-move adjacency map can only agree with it
  /// (redundant) or land on a *different* question that happens to share the
  /// position and one move (wrong — two such questions must not share SRS
  /// memory). Legacy occurrence ids keep the historical map-first resolution,
  /// which is their only transposition-sharing mechanism.
  String _resolveCanonicalId(GraphNode node) {
    if (node.hasCanonicalIdentity) return node.decisionId;
    return repo.canonicalIdFor(node.fen4, node.expectedMoveUci) ?? node.decisionId;
  }

  /// Snapshot of the transient exposure-throttle bookkeeping.
  ///
  /// Used to roll back side effects of a review answer whose persistence
  /// failed, so the in-memory session stays consistent with the store.
  Map<String, DateTime> snapshotExposureThrottle() => Map<String, DateTime>.of(_lastExposedAt);

  /// Restores a snapshot previously obtained from [snapshotExposureThrottle].
  void restoreExposureThrottle(Map<String, DateTime> snapshot) {
    _lastExposedAt
      ..clear()
      ..addAll(snapshot);
  }

  /// Records an active recall attempt at [node], propagating graph effects as appropriate.
  GraphAwareReviewResult recordActiveReview({
    required GraphNode node,
    required ReviewResult result,
    required DateTime now,
    String? playedMoveUci,
    List<GraphNode> siblings = const [],
  }) {
    final canonicalId = _resolveCanonicalId(node);
    final previous = repo.get(canonicalId) ?? ReviewState.initial(decisionId: canonicalId);

    final updatedPrimary = scheduler.schedule(previous: previous, result: result, now: now);
    repo.put(canonicalId, updatedPrimary);

    final sideEffects = <ReviewState>[];

    if (result == ReviewResult.incorrect) {
      // 1. Lapse contagion on direct descendants in the same branch
      _propagateLapseContagion(node.decisionId, now, depth: 1, collector: sideEffects);

      // 2. Confusable sibling coupling
      if (playedMoveUci != null && siblings.isNotEmpty) {
        _coupleConfusableSiblings(playedMoveUci, siblings, collector: sideEffects);
      }
    }

    return GraphAwareReviewResult(
      primaryState: updatedPrimary,
      sideEffectStates: List.unmodifiable(sideEffects),
    );
  }

  /// Records a non-tested pass-through move during auto-traversal (Invariant §2.4).
  ///
  /// Never touches repetitionCount, lapseCount, difficulty, or lastReviewedAt.
  /// Throttled to once per calendar day per decision.
  ReviewState? recordAutoTraversalExposure({required GraphNode node, required DateTime now}) {
    final canonicalId = _resolveCanonicalId(node);
    final previous = repo.get(canonicalId);
    if (previous == null || previous.stability <= 0) {
      return previous ?? ReviewState.initial(decisionId: canonicalId);
    }

    // Never grant exposure credit to an item that is already due
    if (scheduler.isDue(previous, now)) return previous;

    // Once per calendar day throttle
    if (previous.lastReviewedAt != null && _isSameCalendarDay(previous.lastReviewedAt!, now)) {
      return previous;
    }
    final lastExposed = _lastExposedAt[canonicalId];
    if (lastExposed != null && _isSameCalendarDay(lastExposed, now)) {
      return previous;
    }

    final boostedStability = previous.stability * (1 + params.exposureStabilityGain);
    final currentDue = previous.nextDueAt ?? now;
    final remainingMs = currentDue.difference(now).inMilliseconds;
    final extendedDue = remainingMs > 0
        ? currentDue.add(
            Duration(milliseconds: (remainingMs * params.exposureStabilityGain).round()),
          )
        : currentDue;

    final updated = previous.copyWith(nextDueAt: extendedDue, stability: boostedStability);
    repo.put(canonicalId, updated);
    _lastExposedAt[canonicalId] = now;
    return updated;
  }

  void _propagateLapseContagion(
    String parentId,
    DateTime now, {
    required int depth,
    required List<ReviewState> collector,
  }) {
    if (depth > params.maxContagionDepth) return;
    final decay = params.contagionBase * math.exp(-depth / params.contagionTau);

    for (final childId in repo.childrenOf(parentId)) {
      final childState = repo.get(childId);
      if (childState == null || childState.stability <= 0) continue;

      final shrunkStability = childState.stability * (1 - decay).clamp(0.0, 1.0);
      final shrunkDue = _pullDueForward(childState, decay, now);
      final bumpedDifficulty = (childState.difficulty + params.contagionDifficultyBump * decay)
          .clamp(1.0, 10.0);

      final updatedChild = childState.copyWith(
        nextDueAt: shrunkDue,
        stability: shrunkStability,
        difficulty: bumpedDifficulty,
      );
      repo.put(childId, updatedChild);
      collector.add(updatedChild);

      _propagateLapseContagion(childId, now, depth: depth + 1, collector: collector);
    }
  }

  DateTime? _pullDueForward(ReviewState s, double decay, DateTime now) {
    if (s.nextDueAt == null) return null;
    final remaining = s.nextDueAt!.difference(now);
    if (remaining.isNegative) return s.nextDueAt; // already due; leave as-is
    final newRemainingMs = (remaining.inMilliseconds * (1 - decay)).round();
    return now.add(Duration(milliseconds: newRemainingMs));
  }

  void _coupleConfusableSiblings(
    String playedMoveUci,
    List<GraphNode> siblings, {
    required List<ReviewState> collector,
  }) {
    for (final sib in siblings) {
      if (sib.expectedMoveUci != playedMoveUci) continue;
      final sibCanonicalId = _resolveCanonicalId(sib);
      final sibState = repo.get(sibCanonicalId);
      if (sibState == null) continue;

      final bumped = (sibState.difficulty + params.confusionDifficultyCoupling).clamp(1.0, 10.0);
      final updated = sibState.copyWith(difficulty: bumped);
      repo.put(sibCanonicalId, updated);
      collector.add(updated);
    }
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
