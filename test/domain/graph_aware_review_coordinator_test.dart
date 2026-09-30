// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'package:chess_srs/src/domain/chess_fsrs_scheduler.dart';
import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('recordActiveReview on correct move updates primary state without side effects', () {
      const node = GraphNode(
        decisionId: 'root_dec',
        parentId: null,
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

      final result = coordinator.recordActiveReview(
        node: node,
        result: ReviewResult.correct,
        now: now,
      );

      expect(result.primaryState.repetitionCount, 2);
      expect(result.primaryState.stability, greaterThan(2.0 * 86400000));
      expect(result.sideEffectStates, isEmpty);
      expect(repo.get('root_dec'), equals(result.primaryState));
    });

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
        parentId: null,
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

      // Depth 1: decay = 0.18 * exp(-1 / 1.5)
      final expectedDecay1 = 0.18 * math.exp(-1 / 1.5);
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

      // Depth 2: decay = 0.18 * exp(-2 / 1.5)
      final expectedDecay2 = 0.18 * math.exp(-2 / 1.5);
      expect(updatedChild2.stability, closeTo(stateChild2.stability * (1 - expectedDecay2), 100));
      expect(
        updatedChild2.difficulty,
        closeTo(stateChild2.difficulty + 0.6 * expectedDecay2, 0.001),
      );

      // Depth 3: decay = 0.18 * exp(-3 / 1.5)
      final expectedDecay3 = 0.18 * math.exp(-3 / 1.5);
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
        parentId: null,
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
    });

    test('recordActiveReview couples difficulty on confusable sibling moves', () {
      const node = GraphNode(
        decisionId: 'study1_dec',
        parentId: null,
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'e2e4',
      );
      const sibMatching = GraphNode(
        decisionId: 'study2_dec',
        parentId: null,
        fen4: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        expectedMoveUci: 'd2d4',
      );
      const sibOther = GraphNode(
        decisionId: 'study3_dec',
        parentId: null,
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

    test('recordAutoTraversalExposure grants micro-stability bump and extends due date', () {
      const node = GraphNode(
        decisionId: 'learned_dec',
        parentId: null,
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
        parentId: null,
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

    test('recordAutoTraversalExposure refuses exposure credit to already-due decisions', () {
      const node = GraphNode(
        decisionId: 'due_dec',
        parentId: null,
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

    test('recordAutoTraversalExposure ignores unlearned / cold decisions', () {
      const node = GraphNode(
        decisionId: 'cold_dec',
        parentId: null,
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
        parentId: null,
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

      const nodeLegacy = GraphNode(
        decisionId: 'occurrence_1',
        parentId: null,
        fen4: fen,
        expectedMoveUci: 'e2e4',
      );
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
