// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-026, INV-068.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 12);

  // Runtime-built operands on purpose: a `const` ReviewState is canonicalised
  // by the compiler into a single object, so `identical(this, other)` would
  // short-circuit every field comparison in `operator ==` and the equality
  // assertions below could never fail.
  ReviewState makeState({
    required int reps,
    String? id,
    DateTime? first,
    DateTime? last,
    DateTime? due,
    int lapses = 0,
    double stability = 0.0,
    double difficulty = 0.0,
  }) => ReviewState(
    decisionId: id ?? 'dec-$reps',
    firstReviewedAt: first,
    lastReviewedAt: last,
    nextDueAt: due,
    repetitionCount: reps,
    lapseCount: lapses,
    stability: stability,
    difficulty: difficulty,
  );

  group('ReviewState.isNew', () {
    test('a never-reviewed, never-scheduled state is new', () {
      final s = makeState(reps: 0);
      expect(s.isNew, isTrue);
      expect(s.isLearned, isFalse);
    });

    test('a state with a scheduled date is not new even at zero repetitions', () {
      // A traversal-only write leaves a row with a date but no successful
      // recall; it must not look like a never-presented position.
      final s = makeState(reps: 0, due: t0);
      expect(s.isNew, isFalse);
    });

    test('a state with repetitions is not new', () {
      final s = makeState(reps: 1, due: t0);
      expect(s.isNew, isFalse);
      expect(s.isLearned, isTrue);
    });
  });

  group('ReviewState.isDueAt', () {
    test('a state with no scheduled date is due', () {
      expect(makeState(reps: 0).isDueAt(t0), isTrue);
      expect(makeState(reps: 3).isDueAt(t0), isTrue);
    });

    test('the boundary instant counts as due', () {
      expect(makeState(reps: 1, due: t0).isDueAt(t0), isTrue);
    });

    test('a past date is due and a future date is not', () {
      expect(makeState(reps: 1, due: t0.subtract(const Duration(seconds: 1))).isDueAt(t0), isTrue);
      expect(makeState(reps: 1, due: t0.add(const Duration(seconds: 1))).isDueAt(t0), isFalse);
    });
  });

  group('ReviewState.copyWith', () {
    test('copyWith preserves every field that is not named', () {
      final first = t0.subtract(const Duration(days: 10));
      final last = t0.subtract(const Duration(days: 2));
      final due = t0.add(const Duration(days: 3));
      final original = makeState(
        reps: 4,
        id: 'dec-keep',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );

      final updated = original.copyWith(repetitionCount: 5);

      expect(updated.decisionId, 'dec-keep');
      expect(updated.firstReviewedAt, first);
      expect(updated.lastReviewedAt, last);
      expect(updated.nextDueAt, due);
      expect(updated.repetitionCount, 5);
      expect(updated.lapseCount, 2);
      expect(updated.stability, 1234.5);
      expect(updated.difficulty, 7.25);
    });

    test('copyWith with no arguments returns an equal state', () {
      final original = makeState(reps: 2, due: t0, lapses: 1, stability: 3.5, difficulty: 4.5);
      expect(original.copyWith(), equals(original));
    });
  });

  group('ReviewState equality', () {
    test('two runtime-built states with the same fields are equal', () {
      final first = t0.subtract(const Duration(days: 10));
      final last = t0.subtract(const Duration(days: 2));
      final due = t0.add(const Duration(days: 3));

      final a = makeState(
        reps: 4,
        id: 'dec-same',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final b = makeState(
        reps: 4,
        id: 'dec-same',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );

      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('states differing in any one field are not equal', () {
      final first = t0.subtract(const Duration(days: 10));
      final last = t0.subtract(const Duration(days: 2));
      final due = t0.add(const Duration(days: 3));

      final base = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );

      final diffDecisionId = makeState(
        reps: 4,
        id: 'dec-other',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffFirst = makeState(
        reps: 4,
        id: 'dec-base',
        first: first.add(const Duration(seconds: 1)),
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffLast = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last.add(const Duration(seconds: 1)),
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffDue = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last,
        due: due.add(const Duration(seconds: 1)),
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffReps = makeState(
        reps: 5,
        id: 'dec-base',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffLapses = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last,
        due: due,
        lapses: 3,
        stability: 1234.5,
        difficulty: 7.25,
      );
      final diffStability = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1235.5,
        difficulty: 7.25,
      );
      final diffDifficulty = makeState(
        reps: 4,
        id: 'dec-base',
        first: first,
        last: last,
        due: due,
        lapses: 2,
        stability: 1234.5,
        difficulty: 8.25,
      );

      expect(base, isNot(equals(diffDecisionId)));
      expect(base, isNot(equals(diffFirst)));
      expect(base, isNot(equals(diffLast)));
      expect(base, isNot(equals(diffDue)));
      expect(base, isNot(equals(diffReps)));
      expect(base, isNot(equals(diffLapses)));
      expect(base, isNot(equals(diffStability)));
      expect(base, isNot(equals(diffDifficulty)));
      expect(base, isNot(equals(Object())));
    });
  });

  group('ReviewEvent equality', () {
    ReviewEvent makeEvent({
      required String id,
      required DateTime when,
      required ReviewResult result,
      required ReviewState oldState,
      required ReviewState newState,
    }) => ReviewEvent(
      decisionId: id,
      when: when,
      result: result,
      oldState: oldState,
      newState: newState,
    );

    test('two runtime-built events with the same fields are equal', () {
      final oldState = makeState(reps: 1, id: 'dec-ev');
      final newState = makeState(reps: 2, id: 'dec-ev');

      final a = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );
      final b = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );

      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('events differing in any one field are not equal', () {
      final oldState = makeState(reps: 1, id: 'dec-ev');
      final newState = makeState(reps: 2, id: 'dec-ev');

      final base = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );

      final diffDecisionId = makeEvent(
        id: 'dec-other',
        when: t0,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );
      final diffWhen = makeEvent(
        id: 'dec-ev',
        when: t0.add(const Duration(seconds: 1)),
        result: ReviewResult.correct,
        oldState: oldState,
        newState: newState,
      );
      final diffResult = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.incorrect,
        oldState: oldState,
        newState: newState,
      );
      final diffOldState = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.correct,
        oldState: makeState(reps: 3, id: 'dec-ev'),
        newState: newState,
      );
      final diffNewState = makeEvent(
        id: 'dec-ev',
        when: t0,
        result: ReviewResult.correct,
        oldState: oldState,
        newState: makeState(reps: 4, id: 'dec-ev'),
      );

      expect(base, isNot(equals(diffDecisionId)));
      expect(base, isNot(equals(diffWhen)));
      expect(base, isNot(equals(diffResult)));
      expect(base, isNot(equals(diffOldState)));
      expect(base, isNot(equals(diffNewState)));
      expect(base, isNot(equals(Object())));
    });
  });
}
