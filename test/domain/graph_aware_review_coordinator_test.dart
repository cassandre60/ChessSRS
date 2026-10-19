// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-017, INV-027, INV-028, INV-029.

import 'dart:math' as math;
import 'package:chess_srs/src/domain/chess_fsrs_scheduler.dart';
import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_review_state_repository.dart';

void main() {
  group('GraphAwareReviewCoordinator', () {
    late InMemoryReviewStateRepository repo;
    late ChessFsrsScheduler scheduler;
    late GraphAwareReviewCoordinator coordinator;
    final now = DateTime.utc(2026, 9, 18, 12, 0);

    setUp(() {
      repo = InMemoryReviewStateRepository();
      scheduler = const ChessFsrsScheduler(targetRetention: 0.90);
      coordinator = GraphAwareReviewCoordinator(scheduler: scheduler, repo: repo);
    });

    test('lapse contagion survives a degenerate tau instead of crashing the session', () {
      // A tau of 0 makes `-(depth - 1) / tau` 0/0 at depth 1, so exp() is NaN and the
      // (NaN).round() in _pullDueForward throws UnsupportedError. That takes down the review
      // session mid-answer rather than degrading the contagion, and nothing about a wrong answer
      // should be able to end the session that way. The shipped default is 1.5, so this is the
      // guard rail for a parameter that is public and const-constructible, not a live path.
      final degenerate = GraphAwareReviewCoordinator(
        scheduler: scheduler,
        repo: repo,
        params: const GraphAwareParams(contagionTau: 0),
      );

      repo.setChildren('root_dec', ['child_1']);
      repo.put(
        'root_dec',
        ReviewState(
          decisionId: 'root_dec',
          stability: 2.0 * 86400000,
          difficulty: 5.0,
          repetitionCount: 1,
          lastReviewedAt: now.subtract(const Duration(days: 2)),
          nextDueAt: now,
        ),
      );
      repo.put(
        'child_1',
        ReviewState(
          decisionId: 'child_1',
          stability: 2.0 * 86400000,
          difficulty: 5.0,
          repetitionCount: 1,
          lastReviewedAt: now.subtract(const Duration(days: 2)),
          nextDueAt: now.add(const Duration(days: 10)),
        ),
      );

      final result = degenerate.recordActiveReview(
        node: const GraphNode(
          decisionId: 'root_dec',
          fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          expectedMoveUci: 'e2e4',
        ),
        result: ReviewResult.incorrect,
        now: now,
      );

      // What matters is that the answer was graded at all: no throw, and the child it reached
      // came back with a finite schedule rather than a NaN one.
      expect(result.primaryState.lapseCount, 1);
      expect(result.sideEffectStates, hasLength(1));
      final child = result.sideEffectStates.single;
      expect(child.decisionId, 'child_1');
      // A NaN-derived date would come back null or wildly out of range; a pulled-forward
      // schedule is still in the future and no later than it started.
      expect(child.nextDueAt, isNotNull);
      expect(child.nextDueAt!.isAfter(now), isTrue);
      expect(child.nextDueAt!.isAfter(now.add(const Duration(days: 10))), isFalse);
    });

    // SPEC INV-027, INV-029. Hardened: the graph now carries a learned descendant so
    // the propagation axis is actually exercised. A correct answer must leave it
    // untouched (phase 1, isEmpty), while an incorrect answer must propagate to it
    // (phase 2, non-empty) — the latter is what makes the isEmpty assertion above
    // discriminate a mutation that skips side-effect application.
    test(
      'recordActiveReview: correct move primary state without side effects; incorrect move propagates side effects',
      () {
        repo.setChildren('root_dec', ['child_1']);
        repo.put(
          'child_1',
          ReviewState(
            decisionId: 'child_1',
            stability: 10.0 * 86400000,
            difficulty: 4.0,
            repetitionCount: 3,
            lapseCount: 0,
            lastReviewedAt: now.subtract(const Duration(days: 5)),
            nextDueAt: now.add(const Duration(days: 10)),
          ),
        );

        const node = GraphNode(
          decisionId: 'root_dec',
          fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          expectedMoveUci: 'e2e4',
        );
        repo.put(
          'root_dec',
          ReviewState(
            decisionId: 'root_dec',
            stability: 2.0 * 86400000,
            difficulty: 5.0,
            repetitionCount: 1,
            lastReviewedAt: now.subtract(const Duration(days: 2)),
            nextDueAt: now,
          ),
        );

        // Phase 1: correct answer updates primary state and produces no side effects.
        final correctResult = coordinator.recordActiveReview(
          node: node,
          result: ReviewResult.correct,
          now: now,
        );

        expect(correctResult.primaryState.repetitionCount, 2);
        expect(correctResult.primaryState.stability, greaterThan(2.0 * 86400000));
        expect(correctResult.sideEffectStates, isEmpty);
        expect(repo.get('root_dec'), equals(correctResult.primaryState));
        // Propagation axis: the descendant is untouched by a correct answer.
        expect(repo.get('child_1')!.stability, 10.0 * 86400000);

        // Phase 2: incorrect answer on the same graph propagates a side effect.
        final incorrectResult = coordinator.recordActiveReview(
          node: node,
          result: ReviewResult.incorrect,
          now: now,
        );

        expect(incorrectResult.sideEffectStates, hasLength(1));
        final sideEffect = incorrectResult.sideEffectStates.single;
        expect(sideEffect.decisionId, 'child_1');
      },
    );

    test('recordActiveReview on incorrect move propagates lapse contagion to descendants', () {
      // Tree topology: root -> child1 -> child2 -> child3 -> child4
      repo.setChildren('root_dec', ['child_1']);
      repo.setChildren('child_1', ['child_2']);
      repo.setChildren('child_2', ['child_3']);
      repo.setChildren('child_3', ['child_4']);

      // Setup initial learned states for all descendants
      final initialChild1Due = now.add(const Duration(days: 10));
      final initialChild2Due = now.add(const Duration(days: 20));
      final initialChild3Due = now.add(const Duration(days: 30));
      final initialChild4Due = now.add(const Duration(days: 40));

      final stateChild1 = ReviewState(
        decisionId: 'child_1',
        stability: 10.0 * 86400000,
        difficulty: 4.0,
        repetitionCount: 3,
        lapseCount: 0,
        firstReviewedAt: now.subtract(const Duration(days: 30)),
        lastReviewedAt: now.subtract(const Duration(days: 5)),
        nextDueAt: initialChild1Due,
      );
      final stateChild2 = ReviewState(
        decisionId: 'child_2',
        stability: 20.0 * 86400000,
        difficulty: 4.0,
        repetitionCount: 4,
        lapseCount: 0,
        nextDueAt: initialChild2Due,
      );
      final stateChild3 = ReviewState(
        decisionId: 'child_3',
        stability: 30.0 * 86400000,
        difficulty: 4.0,
        repetitionCount: 5,
        lapseCount: 0,
        nextDueAt: initialChild3Due,
      );
      final stateChild4 = ReviewState(
        decisionId: 'child_4',
        stability: 40.0 * 86400000,
        difficulty: 4.0,
        repetitionCount: 6,
        lapseCount: 0,
        nextDueAt: initialChild4Due,
      );

      repo.put('child_1', stateChild1);
      repo.put('child_2', stateChild2);
      repo.put('child_3', stateChild3);
      repo.put('child_4', stateChild4);

      const node = GraphNode(
        decisionId: 'root_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      repo.put('root_dec', ReviewState.initial(decisionId: 'root_dec'));

      final result = coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.incorrect,
        now: now,
      );

      expect(result.primaryState.lapseCount, 1);
      // Depths 1, 2, 3 should have received contagion updates
      expect(result.sideEffectStates.length, 3);

      final updatedChild1 = repo.get('child_1')!;
      final updatedChild2 = repo.get('child_2')!;
      final updatedChild3 = repo.get('child_3')!;
      final updatedChild4 = repo.get('child_4')!;

      // Depth 1 takes the full λ0: decay = 0.18 * exp(-(1 - 1) / 1.5) = 0.18 (review-2 C2).
      final expectedDecay1 = 0.18 * math.exp(-(1 - 1) / 1.5);
      expect(updatedChild1.stability, closeTo(stateChild1.stability * (1 - expectedDecay1), 100));
      expect(
        updatedChild1.difficulty,
        closeTo(stateChild1.difficulty + 0.6 * expectedDecay1, 0.001),
      );
      expect(updatedChild1.nextDueAt!.isBefore(initialChild1Due), isTrue);
      // Invariant: child repetitionCount and lapseCount MUST NOT be modified
      expect(updatedChild1.repetitionCount, stateChild1.repetitionCount);
      expect(updatedChild1.lapseCount, stateChild1.lapseCount);
      expect(updatedChild1.lastReviewedAt, stateChild1.lastReviewedAt);

      // Depth 2: decay = 0.18 * exp(-(2 - 1) / 1.5)
      final expectedDecay2 = 0.18 * math.exp(-(2 - 1) / 1.5);
      expect(updatedChild2.stability, closeTo(stateChild2.stability * (1 - expectedDecay2), 100));
      expect(
        updatedChild2.difficulty,
        closeTo(stateChild2.difficulty + 0.6 * expectedDecay2, 0.001),
      );

      // Depth 3: decay = 0.18 * exp(-(3 - 1) / 1.5)
      final expectedDecay3 = 0.18 * math.exp(-(3 - 1) / 1.5);
      expect(updatedChild3.stability, closeTo(stateChild3.stability * (1 - expectedDecay3), 100));

      // Depth 4: exceeds maxContagionDepth (3), remains untouched
      expect(updatedChild4.stability, stateChild4.stability);
      expect(updatedChild4.difficulty, stateChild4.difficulty);
      expect(updatedChild4.nextDueAt, stateChild4.nextDueAt);
    });

    test('lapse contagion skips unlearned / cold descendants', () {
      repo.setChildren('root_dec', ['cold_child']);
      repo.put('cold_child', ReviewState.initial(decisionId: 'cold_child'));

      const node = GraphNode(
        decisionId: 'root_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      repo.put('root_dec', ReviewState.initial(decisionId: 'root_dec'));

      final result = coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.incorrect,
        now: now,
      );

      expect(result.sideEffectStates, isEmpty);
      expect(repo.get('cold_child')!.stability, 0.0);
      expect(repo.get('cold_child')!.difficulty, 0.0);
    });

    test('lapse contagion leaves an already-due child due at its own instant', () {
      // SPEC INV-027. Contagion softens stability along the line, but a child
      // that is already due stays due: pulling its schedule from `now`
      // re-anchors the overdue instant instead of leaving the overdue item
      // exactly where the queue finds it.
      repo.setChildren('root_dec', ['overdue_child']);
      final overdueDue = now.subtract(const Duration(hours: 3));
      repo.put(
        'overdue_child',
        ReviewState(
          decisionId: 'overdue_child',
          stability: 8.0 * 86400000,
          difficulty: 4.0,
          repetitionCount: 3,
          nextDueAt: overdueDue,
        ),
      );

      const node = GraphNode(
        decisionId: 'root_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      repo.put('root_dec', ReviewState.initial(decisionId: 'root_dec'));

      final result = coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.incorrect,
        now: now,
      );

      expect(result.sideEffectStates, isNotEmpty, reason: 'the child is learned and softened');
      final updated = repo.get('overdue_child')!;
      expect(updated.stability, lessThan(8.0 * 86400000), reason: 'stability still softened');
      expect(updated.difficulty, greaterThan(4.0), reason: 'difficulty still bumped');
      expect(updated.nextDueAt, overdueDue, reason: 'already-due stays where the queue finds it');
    });

    // SPEC INV-027. Regression for review-2 C2: the immediate child of a lapse takes the full
    // λ0 = 18% haircut. The exponent used to read -depth/τ while entering at depth 1, which
    // delivered only 9.24% — 51.3% of the documented strength — at every depth.
    test('INV-027 lapse contagion applies the full lambda0 haircut at depth 1', () {
      repo.setChildren('root_dec', ['child_1']);
      const stability = 10.0 * 86400000;
      repo.put(
        'child_1',
        ReviewState(
          decisionId: 'child_1',
          stability: stability,
          difficulty: 4.0,
          repetitionCount: 3,
          nextDueAt: now.add(const Duration(days: 10)),
        ),
      );

      const node = GraphNode(
        decisionId: 'root_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      repo.put('root_dec', ReviewState.initial(decisionId: 'root_dec'));

      coordinator.recordActiveReview(node: node, result: ReviewResult.incorrect, now: now);

      expect(repo.get('child_1')!.stability, closeTo(stability * 0.82, 100));
    });

    // SPEC INV-028. Regression for review-2 C3: a node with no stored state gets nothing, not a
    // materialised initial state. The old branch returned ReviewState.initial, which the session
    // then persisted through sideEffects — a row for a position the user never engaged with.
    test('recordAutoTraversalExposure returns null for nodes with no stored state', () {
      const node = GraphNode(
        decisionId: 'never_seen',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );

      expect(coordinator.recordAutoTraversalExposure(node: node, now: now), isNull);
      expect(repo.get('never_seen'), isNull);
    });

    test('recordActiveReview couples difficulty on confusable sibling moves', () {
      const node = GraphNode(
        decisionId: 'study1_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      const sibMatching = GraphNode(
        decisionId: 'study2_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'd2d4',
      );
      const sibOther = GraphNode(
        decisionId: 'study3_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'c2c4',
      );

      repo.put(
        'study1_dec',
        const ReviewState(decisionId: 'study1_dec', stability: 1000, difficulty: 5.0),
      );
      repo.put(
        'study2_dec',
        const ReviewState(decisionId: 'study2_dec', stability: 1000, difficulty: 4.0),
      );
      repo.put(
        'study3_dec',
        const ReviewState(decisionId: 'study3_dec', stability: 1000, difficulty: 4.0),
      );

      // User mistakenly plays d2d4 (the move for study2_dec)
      final result = coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.incorrect,
        now: now,
        playedMoveUci: 'd2d4',
        siblings: const [sibMatching, sibOther],
      );

      expect(result.primaryState.lapseCount, 1);
      final updatedSibMatching = repo.get('study2_dec')!;
      final updatedSibOther = repo.get('study3_dec')!;

      // study2_dec difficulty bumped by kappa (0.35)
      expect(updatedSibMatching.difficulty, closeTo(4.35, 0.001));
      // study3_dec difficulty unchanged
      expect(updatedSibOther.difficulty, 4.0);
      expect(result.sideEffectStates, contains(updatedSibMatching));
    });

    test('sibling coupling caps difficulty at the FSRS ceiling', () {
      // SPEC INV-029. Coupling is a bounded difficulty mover like every
      // other: a confusable sibling already near the top of the scale stops
      // at 10.0 instead of overshooting it, whatever kappa adds.
      const node = GraphNode(
        decisionId: 'study1_dec',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      const nearCap = GraphNode(
        decisionId: 'sib_near_cap',
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'd2d4',
      );
      repo.put(
        'study1_dec',
        const ReviewState(decisionId: 'study1_dec', stability: 1000, difficulty: 5.0),
      );
      repo.put(
        'sib_near_cap',
        const ReviewState(decisionId: 'sib_near_cap', stability: 1000, difficulty: 9.8),
      );

      coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.incorrect,
        now: now,
        playedMoveUci: 'd2d4',
        siblings: const [nearCap],
      );

      expect(
        repo.get('sib_near_cap')!.difficulty,
        10.0,
        reason: '9.8 + kappa(0.35) must stop at the 10.0 ceiling, not land beyond it',
      );
    });

    test('recordAutoTraversalExposure grants micro-stability bump and extends due date', () {
      const node = GraphNode(
        decisionId: 'learned_dec',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );

      final initialDue = now.add(const Duration(days: 5));
      const initialStability = 5.0 * 86400000;
      final initialReviewDate = now.subtract(const Duration(days: 2));

      repo.put(
        'learned_dec',
        ReviewState(
          decisionId: 'learned_dec',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 3,
          lapseCount: 0,
          firstReviewedAt: now.subtract(const Duration(days: 10)),
          lastReviewedAt: initialReviewDate,
          nextDueAt: initialDue,
        ),
      );

      final updated = coordinator.recordAutoTraversalExposure(node: node, now: now);

      expect(updated, isNotNull);
      // Stability boosted by epsilon (0.08)
      expect(updated!.stability, closeTo(initialStability * 1.08, 100));
      // Due date extended
      expect(updated.nextDueAt!.isAfter(initialDue), isTrue);
      // Invariant: lastReviewedAt, repetitionCount, lapseCount, difficulty NOT touched
      expect(updated.lastReviewedAt, equals(initialReviewDate));
      expect(updated.repetitionCount, 3);
      expect(updated.lapseCount, 0);
      expect(updated.difficulty, 4.5);
    });

    test('recordAutoTraversalExposure is throttled to once per calendar day', () {
      const node = GraphNode(
        decisionId: 'learned_dec',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );

      final initialDue = now.add(const Duration(days: 5));
      const initialStability = 5.0 * 86400000;

      repo.put(
        'learned_dec',
        ReviewState(
          decisionId: 'learned_dec',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 2,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          nextDueAt: initialDue,
        ),
      );

      final firstExposure = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(firstExposure.stability, greaterThan(initialStability));

      // Immediate second exposure on same day returns existing state without second bump
      final secondExposure = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(secondExposure.stability, equals(firstExposure.stability));
      expect(secondExposure.nextDueAt, equals(firstExposure.nextDueAt));
    });

    // SPEC INV-028. Regression for review-2 C1: the "at most once per calendar day" cap has to
    // survive an app restart. The throttle lived only in the coordinator's memory, so a fresh
    // session started empty and granted credit again the same day — passive stability compounded
    // once per session rather than once per day. Seeding the throttle from the store closes that.
    test('INV-028 a reseeded throttle still refuses a same-day grant after a restart', () {
      const node = GraphNode(
        decisionId: 'learned_dec',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );
      final initialDue = now.add(const Duration(days: 5));
      const initialStability = 5.0 * 86400000;
      final laterSameDay = now.add(const Duration(hours: 6));
      final followingDay = now.add(const Duration(days: 1));

      repo.put(
        'learned_dec',
        ReviewState(
          decisionId: 'learned_dec',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 2,
          lastReviewedAt: now.subtract(const Duration(days: 1)),
          nextDueAt: initialDue,
        ),
      );

      // First session earns the day's credit, and the throttle is what the store would hold.
      final first = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(first.stability, greaterThan(initialStability));
      final persistedThrottle = coordinator.snapshotExposureThrottle();
      expect(persistedThrottle['learned_dec'], equals(now));

      // Restart: a fresh coordinator and repo, reseeded from that persisted throttle.
      final restartedRepo = InMemoryReviewStateRepository();
      restartedRepo.put('learned_dec', first);
      final restarted = GraphAwareReviewCoordinator(
        scheduler: scheduler,
        repo: restartedRepo,
        initialExposureThrottle: persistedThrottle,
      );

      // Later the same calendar day: no second grant, so nothing compounds per session.
      final sameDay = restarted.recordAutoTraversalExposure(node: node, now: laterSameDay)!;
      expect(sameDay.stability, equals(first.stability));
      expect(sameDay.nextDueAt, equals(first.nextDueAt));

      // The next calendar day grants again: the cap is daily, not a permanent lock.
      final nextDay = restarted.recordAutoTraversalExposure(node: node, now: followingDay)!;
      expect(nextDay.stability, greaterThan(first.stability));
    });

    test('recordAutoTraversalExposure refuses exposure credit to already-due decisions', () {
      const node = GraphNode(
        decisionId: 'due_dec',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );

      final initialDue = now.subtract(const Duration(hours: 1)); // overdue
      const initialStability = 5.0 * 86400000;

      repo.put(
        'due_dec',
        ReviewState(
          decisionId: 'due_dec',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 2,
          lastReviewedAt: now.subtract(const Duration(days: 5)),
          nextDueAt: initialDue,
        ),
      );

      final result = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      // Stability and due date remain unchanged
      expect(result.stability, initialStability);
      expect(result.nextDueAt, initialDue);
    });

    // SPEC INV-028. The same-day refusal reads lastReviewedAt as well as the in-memory
    // throttle: a fresh session (empty throttle) must still refuse traversal credit on a
    // calendar day the item was actively reviewed, or the passive boost compounds once
    // per session instead of once per day.
    test('INV-028 same-day active review blocks traversal credit with an empty throttle', () {
      const node = GraphNode(
        decisionId: 'reviewed_today',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );
      final initialDue = now.add(const Duration(days: 5));
      const initialStability = 5.0 * 86400000;

      repo.put(
        'reviewed_today',
        ReviewState(
          decisionId: 'reviewed_today',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 2,
          lastReviewedAt: now.subtract(const Duration(hours: 2)),
          nextDueAt: initialDue,
        ),
      );

      final result = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(result.stability, initialStability);
      expect(result.nextDueAt, initialDue);
    });

    // SPEC INV-028. The <= 0 guard is independent of the due-date refusal: a zero-stability
    // row with a future due date is still unlearned, and crediting it would extend a schedule
    // for an item whose stability never grew.
    test('INV-028 zero-stability states are refused credit even when not yet due', () {
      const node = GraphNode(
        decisionId: 'zero_stability',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );
      final initialDue = now.add(const Duration(days: 5));

      repo.put(
        'zero_stability',
        ReviewState(
          decisionId: 'zero_stability',
          stability: 0.0,
          difficulty: 4.5,
          repetitionCount: 2,
          lastReviewedAt: now.subtract(const Duration(days: 2)),
          nextDueAt: initialDue,
        ),
      );

      final result = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(result.stability, 0.0);
      expect(result.nextDueAt, initialDue);
    });

    test('a learned row without lastReviewedAt still earns traversal credit', () {
      // SPEC INV-028. The same-day refusal reads lastReviewedAt; a stored row
      // that has never been actively reviewed (null) is not "reviewed
      // today", so a null must route through the ordinary not-due /
      // not-throttled path instead of refusing or crashing the grant.
      const node = GraphNode(
        decisionId: 'learned_null_review',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );
      final initialDue = now.add(const Duration(days: 5));
      const initialStability = 5.0 * 86400000;
      repo.put(
        'learned_null_review',
        ReviewState(
          decisionId: 'learned_null_review',
          stability: initialStability,
          difficulty: 4.5,
          repetitionCount: 2,
          nextDueAt: initialDue,
        ),
      );

      final granted = coordinator.recordAutoTraversalExposure(node: node, now: now)!;

      expect(
        granted.stability,
        closeTo(initialStability * 1.08, 100),
        reason: 'credit flows when nothing was reviewed today',
      );
      expect(granted.nextDueAt!.isAfter(initialDue), isTrue, reason: 'due extended as usual');
    });

    test('recordAutoTraversalExposure ignores unlearned / cold decisions', () {
      const node = GraphNode(
        decisionId: 'cold_dec',
        fen4: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'g1f3',
      );

      repo.put('cold_dec', ReviewState.initial(decisionId: 'cold_dec'));

      final result = coordinator.recordAutoTraversalExposure(node: node, now: now)!;
      expect(result.stability, 0.0);
      expect(result.nextDueAt, isNull);
    });

    test('modern canonical identity ignores a colliding single-move map entry', () {
      // Two different questions share a position and one accepted move but have
      // different complete-set identities. The single-move adjacency map can
      // only hold one of them (last writer wins); a modern node must resolve
      // to its own state rather than adopt the stranger's.
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      repo.setCanonicalId(fen, 'e2e4', 'question_b');
      repo.put(
        'question_a',
        ReviewState(
          decisionId: 'question_a',
          stability: 2.0 * 86400000,
          difficulty: 5.0,
          repetitionCount: 1,
          lastReviewedAt: now.subtract(const Duration(days: 2)),
          nextDueAt: now,
        ),
      );
      final untouchedB = ReviewState(
        decisionId: 'question_b',
        stability: 30.0 * 86400000,
        difficulty: 4.0,
        repetitionCount: 5,
        lastReviewedAt: now.subtract(const Duration(days: 5)),
        nextDueAt: now.add(const Duration(days: 30)),
      );
      repo.put('question_b', untouchedB);

      const nodeA = GraphNode(
        decisionId: 'question_a',
        fen4: fen,
        expectedMoveUci: 'e2e4',
        hasCanonicalIdentity: true,
      );
      final result = coordinator.recordActiveReview(
        node: nodeA,
        result: ReviewResult.correct,
        now: now,
      );

      expect(result.primaryState.decisionId, 'question_a');
      expect(result.primaryState.repetitionCount, 2);
      expect(repo.get('question_a'), equals(result.primaryState));
      // The colliding question is untouched.
      expect(repo.get('question_b'), equals(untouchedB));
    });

    test('legacy occurrence identity still follows the single-move map', () {
      // Pre-v10 decisions carry occurrence ids and share memory through the
      // map. That path must keep working after the modern-identity fix.
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      repo.setCanonicalId(fen, 'e2e4', 'occurrence_2');
      repo.put(
        'occurrence_2',
        ReviewState(
          decisionId: 'occurrence_2',
          stability: 2.0 * 86400000,
          difficulty: 5.0,
          repetitionCount: 3,
          lastReviewedAt: now.subtract(const Duration(days: 2)),
          nextDueAt: now,
        ),
      );

      const nodeLegacy = GraphNode(decisionId: 'occurrence_1', fen4: fen, expectedMoveUci: 'e2e4');
      final result = coordinator.recordActiveReview(
        node: nodeLegacy,
        result: ReviewResult.correct,
        now: now,
      );

      expect(result.primaryState.decisionId, 'occurrence_2');
      expect(result.primaryState.repetitionCount, 4);
    });
  });
}
