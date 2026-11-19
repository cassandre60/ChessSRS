import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/review/review_prompt.dart';
import 'package:chess_srs/src/domain/review/review_step_result.dart';
import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewStepResult', () {
    test('stores required fields and defaults', () {
      const move = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
      const expected = RepertoireMove(from: 'e2', to: 'e4');
      final updated = ReviewState.initial(decisionId: 'd1');

      final result = ReviewStepResult(
        isCorrect: true,
        movePlayed: move,
        expectedMoves: const [expected],
        updatedState: updated,
        autoPlayedMoves: const [],
      );

      expect(result.isCorrect, isTrue);
      expect(result.movePlayed, same(move));
      expect(result.expectedMoves, hasLength(1));
      expect(result.expectedMoves.single, same(expected));
      expect(result.updatedState, same(updated));
      expect(result.event, isNull);
      expect(result.autoPlayedMoves, isEmpty);
      expect(result.nextPrompt, isNull);
      expect(result.sessionComplete, isFalse);
      expect(result.sideEffectStates, isEmpty);
      expect(result.adoptedDecisionIds, isEmpty);
    });

    test('stores optional fields', () {
      const move = RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3');
      final updated = ReviewState.initial(decisionId: 'd1');
      final sideEffect = ReviewState.initial(decisionId: 'd2');
      final event = ReviewEvent(
        decisionId: 'd1',
        when: DateTime.utc(2026, 11, 14),
        result: ReviewResult.correct,
        oldState: ReviewState.initial(decisionId: 'd1'),
        newState: updated,
      );
      const autoMove = AutoPlayedMove(
        move: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
        fenBefore: 'fen-before',
        fenAfter: 'fen-after',
        isUserMove: false,
      );

      final result = ReviewStepResult(
        isCorrect: false,
        movePlayed: move,
        expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4')],
        updatedState: updated,
        event: event,
        autoPlayedMoves: const [autoMove],
        sessionComplete: true,
        sideEffectStates: [sideEffect],
        adoptedDecisionIds: const ['adopted-1'],
      );

      expect(result.isCorrect, isFalse);
      expect(result.event, same(event));
      expect(result.autoPlayedMoves, hasLength(1));
      expect(result.autoPlayedMoves.single, same(autoMove));
      expect(result.sessionComplete, isTrue);
      expect(result.sideEffectStates, hasLength(1));
      expect(result.sideEffectStates.single, same(sideEffect));
      expect(result.adoptedDecisionIds, const ['adopted-1']);
    });

    test('toString prefers SAN and includes auto count and completion', () {
      final result = ReviewStepResult(
        isCorrect: true,
        movePlayed: const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
        updatedState: ReviewState.initial(decisionId: 'd1'),
        autoPlayedMoves: const [
          AutoPlayedMove(
            move: RepertoireMove(from: 'e7', to: 'e5'),
            fenBefore: 'a',
            fenAfter: 'b',
            isUserMove: false,
          ),
        ],
        sessionComplete: true,
      );

      expect(
        result.toString(),
        'ReviewStepResult(correct: true, played: e4, auto: 1, complete: true)',
      );
    });

    test('toString falls back to from-to when SAN is absent', () {
      final result = ReviewStepResult(
        isCorrect: false,
        movePlayed: const RepertoireMove(from: 'e2', to: 'e4'),
        expectedMoves: const [],
        updatedState: ReviewState.initial(decisionId: 'd1'),
        autoPlayedMoves: const [],
      );

      expect(
        result.toString(),
        'ReviewStepResult(correct: false, played: e2e4, auto: 0, complete: false)',
      );
    });
  });
}
