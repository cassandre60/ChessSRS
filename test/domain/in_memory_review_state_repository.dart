// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/review_state.dart';

/// In-memory implementation of [ReviewStateRepository] for tests.
///
/// Lives here rather than in `lib/` so it cannot ship to users or drift from the production
/// adapter unnoticed (review-2 D4). Production sessions use the adapter owned by
/// `ReviewSession`; this double exists only so coordinator tests need no database.
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
