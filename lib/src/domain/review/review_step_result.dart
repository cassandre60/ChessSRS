// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.review.review_engine;
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/review/review_prompt.dart';
import 'package:chess_srs/src/domain/review_state.dart';

/// The result of processing a user's move attempt in a review session.
class ReviewStepResult {
  const ReviewStepResult({
    required this.isCorrect,
    required this.movePlayed,
    required this.expectedMoves,
    required this.updatedState,
    this.event,
    required this.autoPlayedMoves,
    this.nextPrompt,
    this.sessionComplete = false,
    this.sideEffectStates = const [],
  });

  final bool isCorrect;
  final RepertoireMove movePlayed;
  final List<RepertoireMove> expectedMoves;
  final ReviewState updatedState;
  final ReviewEvent? event;
  final List<AutoPlayedMove> autoPlayedMoves;
  final ReviewPrompt? nextPrompt;
  final bool sessionComplete;

  /// Secondary states updated as graph side-effects (lapse contagion, confusable
  /// sibling coupling, or auto-traversal credit).
  final List<ReviewState> sideEffectStates;

  @override
  String toString() =>
      'ReviewStepResult(correct: $isCorrect, played: ${movePlayed.san ?? "${movePlayed.from}${movePlayed.to}"}, '
      'auto: ${autoPlayedMoves.length}, complete: $sessionComplete)';
}
