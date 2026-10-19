// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Mutation-audit coverage for ReviewEngine.createSession: the engine is a pure
// factory, so its whole contract is "every argument reaches the returned
// ReviewSession". A dropped, defaulted or swapped argument here changes review
// behaviour in ways component tests only see through the parameters they set
// themselves.

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [Scheduler] the engine cannot construct on its own, so instance identity
/// proves the caller's scheduler was passed through: a `const SimpleScheduler()`
/// would be identical whether it came from the caller or the engine's default.
class _CallerScheduler implements Scheduler {
  const _CallerScheduler();

  @override
  bool isDue(ReviewState state, DateTime now) => const SimpleScheduler().isDue(state, now);

  @override
  ReviewState schedule({
    required ReviewState previous,
    required ReviewResult result,
    required DateTime now,
  }) => const SimpleScheduler().schedule(previous: previous, result: result, now: now);
}

/// Counts [nextInt] calls so tests can prove which [Random] instance a session
/// consumed, without depending on a particular shuffle outcome.
class _CountingRandom implements Random {
  _CountingRandom([int seed = 1]) : _inner = Random(seed);

  final Random _inner;
  int nextIntCalls = 0;

  @override
  int nextInt(int max) {
    nextIntCalls++;
    return _inner.nextInt(max);
  }

  @override
  bool nextBool() => _inner.nextBool();

  @override
  double nextDouble() => _inner.nextDouble();
}

/// Minimal [ReviewStateRepository] for coordinator construction; these tests
/// never play a review move, so every method is inert.
class _InertRepository implements ReviewStateRepository {
  final Map<String, ReviewState> states = {};

  @override
  ReviewState? get(String decisionId) => states[decisionId];

  @override
  void put(String decisionId, ReviewState state) => states[decisionId] = state;

  @override
  List<String> childrenOf(String decisionId) => const [];

  @override
  String? canonicalIdFor(String fen4, String expectedMoveUci) => null;
}

void main() {
  late DateTime baseTime;

  setUp(() {
    baseTime = DateTime.utc(2026, 9, 16, 10, 0, 0);
  });

  // Three decisions on the same Italian-game skeleton as
  // test/review/review_engine_test.dart, so order/shuffle probes have more than
  // one queue entry to work with.
  (Study, Chapter, List<RepertoireDecision>) buildTestRepertoire() {
    final study = Study(
      id: 'study-openings',
      title: 'Openings',
      createdAt: baseTime,
      updatedAt: baseTime,
    );

    // Root -> 1. e4 (dec-1) -> 1... e5 -> 2. Nf3 (dec-2) -> 2... Nc6 -> 3. Bc4 (dec-3)
    const rootNode = RepertoireNode(
      id: 'node-root',
      fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      children: [
        RepertoireNode(
          id: 'node-e4',
          fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
          incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          children: [
            RepertoireNode(
              id: 'node-e5',
              fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
              fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
              incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
              children: [
                RepertoireNode(
                  id: 'node-nf3',
                  fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                  fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                  incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                  children: [
                    RepertoireNode(
                      id: 'node-nc6',
                      fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
                      fenKey: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq -',
                      incomingMove: RepertoireMove(from: 'b8', to: 'c6', san: 'Nc6'),
                      children: [
                        RepertoireNode(
                          id: 'node-bc4',
                          fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
                          fenKey: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq -',
                          incomingMove: RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final chapter = Chapter(
      id: 'chapter-italian',
      studyId: study.id,
      sourceOrder: 0,
      title: 'Italian Game',
      startingFen: rootNode.fen,
      root: rootNode,
      createdAt: baseTime,
    );

    final decisions = [
      const RepertoireDecision(
        id: 'dec-1',
        studyId: 'study-openings',
        chapterId: 'chapter-italian',
        nodeId: 'node-root',
        expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      ),
      const RepertoireDecision(
        id: 'dec-2',
        studyId: 'study-openings',
        chapterId: 'chapter-italian',
        nodeId: 'node-e5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      ),
      const RepertoireDecision(
        id: 'dec-3',
        studyId: 'study-openings',
        chapterId: 'chapter-italian',
        nodeId: 'node-nc6',
        expectedMoves: [RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4')],
      ),
    ];

    return (study, chapter, decisions);
  }

  Map<String, ReviewState> dueStates(List<RepertoireDecision> decisions) => {
    for (final d in decisions)
      d.id: ReviewState(
        decisionId: d.id,
        repetitionCount: 2,
        nextDueAt: baseTime.subtract(const Duration(days: 1)),
      ),
  };

  group('ReviewEngine.createSession argument wiring', () {
    test('passes every non-default argument through to the session', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      const scheduler = _CallerScheduler();
      final clock = FixedClock(baseTime);
      const scope = ReviewScope.study('study-openings');

      final session = ReviewEngine(scheduler: scheduler, clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        scope: scope,
        mode: ReviewMode.practice,
        order: ReviewOrder.byLine,
        continuity: ReviewContinuity.fullLine,
        transposeScope: TransposeScope.off,
        prefetchBatchSize: 7,
        prefetchRefillThreshold: 4,
        remainingDailyQuota: 11,
        remainingNewQuota: 5,
        dynamicRepertoireMode: true,
        unlockedDecisionIds: {'dec-2'},
      );

      expect(session.scope, same(scope));
      expect(session.mode, ReviewMode.practice);
      expect(session.order, ReviewOrder.byLine);
      expect(session.continuity, ReviewContinuity.fullLine);
      expect(session.transposeScope, TransposeScope.off);
      expect(session.scheduler, same(scheduler));
      expect(session.clock, same(clock));
      expect(session.prefetchBatchSize, 7);
      expect(session.prefetchRefillThreshold, 4);
      expect(session.remainingDailyQuota, 11);
      expect(session.remainingNewQuota, 5);
      expect(session.dynamicRepertoireMode, isTrue);
      expect(session.unlockedDecisionIds, contains('dec-2'));

      // The studies/chapters lists are only observable through the prompt
      // metadata they contribute.
      expect(session.currentPrompt?.studyTitle, 'Openings');
      expect(session.currentPrompt?.chapterTitle, 'Italian Game');
    });

    test('leaves every optional argument at its documented default', () {
      final (study, chapter, decisions) = buildTestRepertoire();

      final session = const ReviewEngine().createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
      );

      expect(session.scope.studyId, isNull);
      expect(session.scope.chapterId, isNull);
      expect(session.scope.openingFamily, isNull);
      expect(session.scope.side, isNull);
      expect(session.mode, ReviewMode.srs);
      expect(session.order, ReviewOrder.dueDate);
      expect(session.continuity, ReviewContinuity.dueOnly);
      expect(session.transposeScope, TransposeScope.inScope);
      expect(session.scheduler, isA<SimpleScheduler>());
      expect(session.clock, isA<SystemClock>());
      expect(session.prefetchBatchSize, kDefaultPrefetchBatchSize);
      expect(session.prefetchRefillThreshold, kDefaultPrefetchRefillThreshold);
      expect(session.remainingDailyQuota, isNull);
      expect(session.remainingNewQuota, isNull);
      expect(session.dynamicRepertoireMode, isFalse);
      expect(session.unlockedDecisionIds, isEmpty);
    });
  });

  group('ReviewEngine.createSession random wiring', () {
    test('engine-level random drives the queue shuffle when no per-call random is given', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engineRandom = _CountingRandom(5);

      final session = ReviewEngine(clock: FixedClock(baseTime), random: engineRandom).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        order: ReviewOrder.random,
      );

      expect(session.currentPrompt, isNotNull);
      expect(engineRandom.nextIntCalls, greaterThan(0));
    });

    test('a per-call random wins over the engine-level random', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engineRandom = _CountingRandom(5);
      final callRandom = _CountingRandom(9);

      final session = ReviewEngine(clock: FixedClock(baseTime), random: engineRandom).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        order: ReviewOrder.random,
        random: callRandom,
      );

      expect(session.currentPrompt, isNotNull);
      expect(callRandom.nextIntCalls, greaterThan(0));
      expect(engineRandom.nextIntCalls, 0);
    });

    test('a per-call random is used when the engine has none', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final callRandom = _CountingRandom(9);

      final session = ReviewEngine(clock: FixedClock(baseTime)).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        order: ReviewOrder.random,
        random: callRandom,
      );

      expect(session.currentPrompt, isNotNull);
      expect(callRandom.nextIntCalls, greaterThan(0));
    });
  });

  group('ReviewEngine.createSession coordinator wiring', () {
    test('a supplied coordinator is the one the session exposes', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final coordinator = GraphAwareReviewCoordinator(
        scheduler: const SimpleScheduler(),
        repo: _InertRepository(),
        initialExposureThrottle: {'canon-dec-1': baseTime},
      );

      final session = ReviewEngine(clock: FixedClock(baseTime)).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        coordinator: coordinator,
      );

      expect(session.exposureThrottle, containsPair('canon-dec-1', baseTime));
    });

    test('initialExposureThrottle seeds the coordinator the session builds', () {
      final (study, chapter, decisions) = buildTestRepertoire();

      final session = ReviewEngine(clock: FixedClock(baseTime)).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: dueStates(decisions),
        initialExposureThrottle: {'canon-dec-2': baseTime},
      );

      expect(session.exposureThrottle, containsPair('canon-dec-2', baseTime));
    });
  });
}
