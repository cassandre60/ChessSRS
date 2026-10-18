// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Mutation-audit kill tests for [ReviewSession].
///
/// Each test pins behaviour that a surviving mutant of the review-session
/// mutation campaign (Stream 1 of `docs/AUTONOMOUS_IMPROVEMENT_CATALOG.md`)
/// proved unpinned: without the assertion the mutant is green again. The
/// `// mutant L<n>` comments name the mutated source line.
library;

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

final _now = DateTime.utc(2026, 10, 16, 12);

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const _mE4 = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
const _mE5 = RepertoireMove(from: 'e7', to: 'e5', san: 'e5');
const _mNf3 = RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3');
const _mNc6 = RepertoireMove(from: 'b8', to: 'c6', san: 'Nc6');
const _mBc4 = RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4');
const _mD4 = RepertoireMove(from: 'd2', to: 'd4', san: 'd4');
const _mD5 = RepertoireMove(from: 'd7', to: 'd5', san: 'd5');
const _mC5 = RepertoireMove(from: 'c7', to: 'c5', san: 'c5');
const _mPromoQ = RepertoireMove(from: 'a7', to: 'a8', promotion: 'q', san: 'a8=Q');
const _mPromoR = RepertoireMove(from: 'a7', to: 'a8', promotion: 'r', san: 'a8=R');

const _fenStart = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _fenKeyStart = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
const _fenE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
const _fenKeyE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
const _fenE5 = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
const _fenKeyE5 = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
const _fenNf3 = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
const _fenKeyNf3 = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -';
const _fenNc6 = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
const _fenKeyNc6 = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq -';
const _fenBc4 = 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3';
const _fenKeyBc4 = 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq -';
const _fenC5 = 'rnbqkbnr/pppp1ppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2';
const _fenKeyC5 = 'rnbqkbnr/pppp1ppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
const _fenD4AfterE4 = 'rnbqkbnr/pppp1ppp/8/4p3/3PP3/8/PPP2PPP/RNBQKBNR b KQkq d3 0 2';
const _fenKeyD4AfterE4 = 'rnbqkbnr/pppp1ppp/8/4p3/3PP3/8/PPP2PPP/RNBQKBNR b KQkq -';
const _fenD5AfterD4 = 'rnbqkbnr/pppp1ppp/8/3pp3/3PP3/8/PPP2PPP/RNBQKBNR w KQkq d6 0 3';
const _fenKeyD5AfterD4 = 'rnbqkbnr/pppp1ppp/8/3pp3/3PP3/8/PPP2PPP/RNBQKBNR w KQkq -';
const _fenPromo = '4k3/P7/8/8/8/8/8/4K3 w - - 0 1';
const _fenKeyPromo = '4k3/P7/8/8/8/8/8/4K3 w - -';
const _fenPromoQ = 'Q3k3/8/8/8/8/8/8/4K3 b - - 0 1';
const _fenKeyPromoQ = 'Q3k3/8/8/8/8/8/8/4K3 b - -';

/// The standard line: 1.e4 e5 2.Nf3 Nc6 3.Bc4, one node per move.
const _lBc4 = RepertoireNode(id: 'node-bc4', fen: _fenBc4, fenKey: _fenKeyBc4, incomingMove: _mBc4);
const _lNc6 = RepertoireNode(
  id: 'node-nc6',
  fen: _fenNc6,
  fenKey: _fenKeyNc6,
  incomingMove: _mNc6,
  children: [_lBc4],
);
const _lNf3 = RepertoireNode(
  id: 'node-nf3',
  fen: _fenNf3,
  fenKey: _fenKeyNf3,
  incomingMove: _mNf3,
  children: [_lNc6],
);
const _lE5 = RepertoireNode(
  id: 'node-e5',
  fen: _fenE5,
  fenKey: _fenKeyE5,
  incomingMove: _mE5,
  children: [_lNf3],
);
const _lE4 = RepertoireNode(
  id: 'node-e4',
  fen: _fenE4,
  fenKey: _fenKeyE4,
  incomingMove: _mE4,
  children: [_lE5],
);
const _lRoot = RepertoireNode(
  id: 'node-root',
  fen: _fenStart,
  fenKey: _fenKeyStart,
  children: [_lE4],
);

const _studyId = 'study-1';
const _chapterId = 'ch-1';

Study _studyOf([String studyId = _studyId]) => Study(id: studyId, title: studyId);

Chapter _chapterOf(
  RepertoireNode root, {
  String chapterId = _chapterId,
  String studyId = _studyId,
  int sourceOrder = 0,
}) => Chapter(
  id: chapterId,
  studyId: studyId,
  sourceOrder: sourceOrder,
  title: chapterId,
  startingFen: root.fen,
  root: root,
);

RepertoireDecision _decision({
  required String id,
  required String nodeId,
  required List<RepertoireMove> expectedMoves,
  String? canonicalStateId,
  String chapterId = _chapterId,
  String studyId = _studyId,
}) => RepertoireDecision(
  id: id,
  studyId: studyId,
  chapterId: chapterId,
  nodeId: nodeId,
  expectedMoves: expectedMoves,
  canonicalStateId: canonicalStateId,
);

RepertoireDecision _dec1({String? canonicalStateId, List<RepertoireMove> moves = const [_mE4]}) =>
    _decision(
      id: 'dec-1',
      nodeId: 'node-root',
      expectedMoves: moves,
      canonicalStateId: canonicalStateId,
    );

RepertoireDecision _dec2({String? canonicalStateId, List<RepertoireMove> moves = const [_mNf3]}) =>
    _decision(
      id: 'dec-2',
      nodeId: 'node-e5',
      expectedMoves: moves,
      canonicalStateId: canonicalStateId,
    );

RepertoireDecision _dec3({String? canonicalStateId, List<RepertoireMove> moves = const [_mBc4]}) =>
    _decision(
      id: 'dec-3',
      nodeId: 'node-nc6',
      expectedMoves: moves,
      canonicalStateId: canonicalStateId,
    );

ReviewState _dueState(
  String decisionId, {
  int reps = 3,
  double difficulty = 4.0,
  double stability = 1.0,
  Duration overdue = const Duration(hours: 2),
}) => ReviewState(
  decisionId: decisionId,
  firstReviewedAt: _now.subtract(const Duration(days: 10)),
  lastReviewedAt: _now.subtract(const Duration(days: 3)),
  nextDueAt: _now.subtract(overdue),
  repetitionCount: reps,
  stability: stability,
  difficulty: difficulty,
);

ReviewState _scheduledState(
  String decisionId, {
  int reps = 2,
  double difficulty = 4.0,
  double stability = 200,
  Duration ahead = const Duration(days: 3),
}) => ReviewState(
  decisionId: decisionId,
  firstReviewedAt: _now.subtract(const Duration(days: 10)),
  lastReviewedAt: _now.subtract(const Duration(days: 2)),
  nextDueAt: _now.add(ahead),
  repetitionCount: reps,
  stability: stability,
  difficulty: difficulty,
);

/// A state row with no due date: due immediately, but never fresh.
ReviewState _undatedDueState(String decisionId) => ReviewState(
  decisionId: decisionId,
  firstReviewedAt: _now.subtract(const Duration(days: 10)),
  lastReviewedAt: _now.subtract(const Duration(days: 3)),
  repetitionCount: 1,
);

ReviewSession _session({
  required List<Study> studies,
  required List<Chapter> chapters,
  required List<RepertoireDecision> decisions,
  Map<String, ReviewState> reviewStates = const {},
  ReviewScope scope = const ReviewScope.all(),
  ReviewMode mode = ReviewMode.srs,
  ReviewContinuity continuity = ReviewContinuity.dueOnly,
  ReviewOrder order = ReviewOrder.dueDate,
  bool dynamic = false,
  Set<String> unlocked = const {},
  int? remainingNewQuota,
  int? remainingDailyQuota,
  int? prefetchBatchSize = kDefaultPrefetchBatchSize,
  int prefetchRefillThreshold = kDefaultPrefetchRefillThreshold,
  Random? random,
}) => ReviewSession(
  studies: studies,
  chapters: chapters,
  decisions: decisions,
  reviewStates: reviewStates,
  scope: scope,
  mode: mode,
  continuity: continuity,
  order: order,
  clock: FixedClock(_now),
  dynamicRepertoireMode: dynamic,
  unlockedDecisionIds: unlocked,
  remainingNewQuota: remainingNewQuota,
  remainingDailyQuota: remainingDailyQuota,
  prefetchBatchSize: prefetchBatchSize,
  prefetchRefillThreshold: prefetchRefillThreshold,
  random: random,
);

void main() {
  group('ReviewSession queue construction', () {
    test('a directly constructed session defaults to static, not dynamic, mode', () {
      // mutant L67: this.dynamicRepertoireMode = false -> true
      final session = ReviewSession(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1()],
        reviewStates: {'dec-1': _dueState('dec-1')},
        clock: FixedClock(_now),
      );

      expect(session.dynamicRepertoireMode, isFalse);
      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('dynamic mode keeps a learned position that was never explicitly unlocked', () {
      // mutant L116: isLearned || -> isLearned &&
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(canonicalStateId: 'can-1')],
        reviewStates: {'can-1': _dueState('can-1', reps: 2)},
        dynamic: true,
      );

      expect(session.initialQueueCount, 1);
      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('dynamic mode accepts an unlock declared by canonical id alone', () {
      // mutant L117: unlockedDecisionIds.contains(d.id) || -> &&
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(canonicalStateId: 'can-1')],
        unlocked: {'can-1'},
        dynamic: true,
      );

      expect(session.initialQueueCount, 1);
      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('all-scope reviews one occurrence per canonical position, study scope keeps both', () {
      // mutant L122 (x3): the all-scope dedupe condition
      const rootB = RepertoireNode(id: 'node-b-root', fen: _fenStart, fenKey: _fenKeyStart);
      final decisions = [
        _decision(
          id: 'dec-aa',
          nodeId: 'node-root',
          expectedMoves: const [_mE4],
          canonicalStateId: 'can-shared',
        ),
        _decision(
          id: 'dec-bb',
          nodeId: 'node-b-root',
          expectedMoves: const [_mE4],
          canonicalStateId: 'can-shared',
          chapterId: 'ch-2',
        ),
      ];
      final studies = [_studyOf()];
      final chapters = [_chapterOf(_lRoot), _chapterOf(rootB, chapterId: 'ch-2')];
      final states = {'can-shared': _dueState('can-shared')};

      final allScope = _session(
        studies: studies,
        chapters: chapters,
        decisions: decisions,
        reviewStates: states,
      );
      final studyScope = _session(
        studies: studies,
        chapters: chapters,
        decisions: decisions,
        reviewStates: states,
        scope: const ReviewScope.study('study-1'),
      );

      expect(allScope.initialQueueCount, 1);
      expect(studyScope.initialQueueCount, 2);
    });
  });

  group('ReviewSession new-position allowance and ordering', () {
    test('a zero new-position allowance withholds every fresh introduction', () {
      // mutant L180: newAllowance >= 0 -> > 0
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        remainingNewQuota: 0,
      );

      expect(session.initialQueueCount, 0);
      expect(session.currentPrompt, isNull);
      expect(session.isComplete, isTrue);
    });

    test('an undated due position is prompted before dated ones (three-way queue)', () {
      // mutant L170: dueA == null && dueB == null -> dueA != null && dueB == null
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        // List order puts a dated decision first: only the comparator can fix it.
        decisions: [
          _decision(id: 'dec-dated-1', nodeId: 'node-root', expectedMoves: const [_mE4]),
          _decision(id: 'dec-undated', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
          _decision(id: 'dec-dated-2', nodeId: 'node-nc6', expectedMoves: const [_mBc4]),
        ],
        reviewStates: {
          'dec-dated-1': _dueState('dec-dated-1', overdue: const Duration(hours: 1)),
          'dec-undated': _undatedDueState('dec-undated'),
          'dec-dated-2': _dueState('dec-dated-2', overdue: const Duration(hours: 1)),
        },
      );

      expect(session.currentPrompt?.decision.id, 'dec-undated');
    });

    test('an undated due position is prompted before a dated one (two-way queue)', () {
      // mutant L170: dueA == null && dueB == null -> dueA == null && dueB != null / ||
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          _decision(id: 'dec-dated', nodeId: 'node-root', expectedMoves: const [_mE4]),
          _decision(id: 'dec-undated', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
        ],
        reviewStates: {
          'dec-dated': _dueState('dec-dated'),
          'dec-undated': _undatedDueState('dec-undated'),
        },
      );

      expect(session.currentPrompt?.decision.id, 'dec-undated');
    });

    test('by-line order walks tree order even when the due dates disagree', () {
      // mutant L248: if (c != 0) return c -> if (c == 0) return c
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        // Reversed decision list, reversed due dates: only tree order can win.
        decisions: [_dec2(), _dec1()],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 1)),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 2)),
        },
        order: ReviewOrder.byLine,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('by-line order in srs mode cannot let fresh work overtake due work', () {
      // mutant L252: if (mode == ReviewMode.srs) -> !=
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        // The fresh decision sits first in tree order; the due one is deeper.
        decisions: [
          _decision(id: 'dec-fresh', nodeId: 'node-root', expectedMoves: const [_mE4]),
          _decision(id: 'dec-due', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
        ],
        reviewStates: {'dec-due': _dueState('dec-due')},
        order: ReviewOrder.byLine,
      );

      expect(session.currentPrompt?.decision.id, 'dec-due');
    });

    test('random order in srs mode cannot let fresh work overtake due work', () {
      // mutant L263: if (mode == ReviewMode.srs) -> !=
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          _decision(id: 'dec-due', nodeId: 'node-root', expectedMoves: const [_mE4]),
          _decision(id: 'dec-fresh', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
        ],
        reviewStates: {'dec-due': _dueState('dec-due')},
        order: ReviewOrder.random,
        // Seed 1 makes a whole-queue shuffle reorder [due, fresh] -> [fresh, due],
        // so the mutant's flattened shuffle is observable.
        random: Random(1),
      );

      expect(session.currentPrompt?.decision.id, 'dec-due');
    });

    test('a null prefetch batch buffers the whole queue instead of throwing', () {
      // mutant L415: prefetchBatchSize == null -> != null (null-check crash)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1()],
        reviewStates: {'dec-1': _dueState('dec-1')},
        prefetchBatchSize: null,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
      expect(session.remainingDueCount, 1);
    });
  });

  group('ReviewSession lapse and advance flow', () {
    test('a lapse moves the card to the back of the queue, not past the others', () {
      // mutant L675: _unbufferedQueue removeWhere == -> != (drops the queue)
      // mutant L676: if (_unbufferedQueue.isNotEmpty) -> isEmpty (jumps the queue)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2(), _dec3()],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 3)),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 2)),
          'dec-3': _dueState('dec-3', overdue: const Duration(hours: 1)),
        },
        prefetchBatchSize: 1,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'd2', to: 'd4');
      expect(result.isCorrect, isFalse);
      session.continueAfterIncorrect();

      expect(session.currentPrompt?.decision.id, 'dec-2');
    });

    test('an incorrect answer never reports the session as complete', () {
      // mutant L690: sessionComplete: false -> true (lapse)
      // mutant L741: sessionComplete: false -> true (retry)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 1)),
        },
      );

      final lapse = session.submitMove(from: 'd2', to: 'd4');
      expect(lapse.isCorrect, isFalse);
      expect(lapse.sessionComplete, isFalse);
      expect(lapse.nextPrompt?.decision.id, 'dec-1');

      final retryMiss = session.retryMove(from: 'd2', to: 'd4');
      expect(retryMiss.isCorrect, isFalse);
      expect(retryMiss.sessionComplete, isFalse);
    });

    test('a correct move that opens the next card never reports the session complete', () {
      // mutant L824: sessionComplete: false -> true (walk prompt)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 1)),
        },
      );

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.decision.id, 'dec-2');
      expect(result.sessionComplete, isFalse);
    });

    test('a lapse on a question with no expected moves still requeues and advances', () {
      // mutant L925: the _advanceWithinLine guard returns true instead of false
      // Solo root: the played move has no transposed node, so the answer lapses.
      const soloRoot = RepertoireNode(id: 'node-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(soloRoot)],
        decisions: [_dec1(moves: const [])],
        reviewStates: {'dec-1': _dueState('dec-1')},
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isFalse);
      session.continueAfterIncorrect();

      expect(session.remainingDueCount, 1);
    });

    test('a full-line lapse with no node below the expected move falls back to the queue', () {
      // mutant L927: the userChild guard returns true instead of false
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        // dec-2's expected move (Bc4) has no node below this position, so the
        // walk stops at the userChild guard, not at a missing decision.
        decisions: [
          _dec2(moves: const [_mBc4]),
        ],
        reviewStates: {'dec-2': _dueState('dec-2')},
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-2');

      final result = session.submitMove(from: 'd2', to: 'd4');
      expect(result.isCorrect, isFalse);
      session.continueAfterIncorrect();

      expect(session.remainingDueCount, 1);
    });

    test('a full-line lapse falls back when the first continuation holds no question', () {
      // mutant L930: nextDecision == null returns true instead of false
      const branchyE4 = RepertoireNode(
        id: 'node-r1-e4',
        fen: _fenE4,
        fenKey: _fenKeyE4,
        incomingMove: _mE4,
        children: [
          RepertoireNode(id: 'node-r1-e5', fen: _fenE5, fenKey: _fenKeyE5, incomingMove: _mE5),
          RepertoireNode(id: 'node-r1-c5', fen: _fenC5, fenKey: _fenKeyC5, incomingMove: _mC5),
        ],
      );
      const branchyRoot = RepertoireNode(
        id: 'node-r1',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [branchyE4],
      );
      // A second line whose sole decision is its own line start: after the
      // fallback the queue must serve it, not revert to the lapsed card.
      const soloRoot = RepertoireNode(id: 'node-r2', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(branchyRoot),
          _chapterOf(soloRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _decision(id: 'dec-r1', nodeId: 'node-r1', expectedMoves: const [_mE4]),
          _decision(
            id: 'dec-r2',
            nodeId: 'node-r2',
            expectedMoves: const [_mD4],
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'dec-r1': _dueState('dec-r1'),
          'dec-r2': _dueState('dec-r2', overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-r1');

      final result = session.submitMove(from: 'g1', to: 'f3');
      expect(result.isCorrect, isFalse);
      session.continueAfterIncorrect();

      // The fallback pops dec-r2 and opens it plainly: its chain holds no
      // ancestor, so the walk cannot start anywhere else.
      expect(session.currentPrompt?.decision.id, 'dec-r2');
      expect(session.remainingDueCount, 2);
    });

    test('a full-line lapse continues along the first continuation of the junction', () {
      // mutant L928: userChild.children.first -> .last
      const e4Replies = RepertoireNode(
        id: 'node-e4',
        fen: _fenE4,
        fenKey: _fenKeyE4,
        incomingMove: _mE4,
        children: [
          RepertoireNode(id: 'node-e5', fen: _fenE5, fenKey: _fenKeyE5, incomingMove: _mE5),
          RepertoireNode(id: 'node-c5', fen: _fenC5, fenKey: _fenKeyC5, incomingMove: _mC5),
        ],
      );
      const root = RepertoireNode(
        id: 'node-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [e4Replies],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _dec1(),
          _decision(id: 'dec-e5', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
          _decision(id: 'dec-c5', nodeId: 'node-c5', expectedMoves: const [_mD4]),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-e5': _dueState('dec-e5', overdue: const Duration(hours: 2)),
          'dec-c5': _dueState('dec-c5', overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'g1', to: 'f3');
      expect(result.isCorrect, isFalse);
      session.continueAfterIncorrect();

      expect(session.currentPrompt?.decision.id, 'dec-e5');
    });

    test('a prompted position pulls its canonical twin out of the whole queue', () {
      // mutant L941: the dueQueue dequeue uses && instead of ||
      const twinE5 = RepertoireNode(
        id: 'node-b-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
      );
      const twinRoot = RepertoireNode(
        id: 'node-b-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-b-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [twinE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(twinRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(),
          _dec2(canonicalStateId: 'can-2'),
          _decision(
            id: 'dec-twin',
            nodeId: 'node-b-e5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-2',
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 3)),
          'can-2': _dueState('can-2', overdue: const Duration(hours: 2)),
        },
        scope: const ReviewScope.study('study-1'),
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.decision.id, 'dec-2');
      // The twin travelled with its canonical sibling and was dequeued too.
      expect(session.remainingDueCount, 1);
    });

    test('a prompted position pulls its canonical twin out of the buffered queue', () {
      // mutant L943 (x3): the unbufferedQueue dequeue predicate
      const twinE5 = RepertoireNode(
        id: 'node-b-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
      );
      const twinRoot = RepertoireNode(
        id: 'node-b-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-b-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [twinE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(twinRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(),
          _dec2(canonicalStateId: 'can-2'),
          _decision(
            id: 'dec-twin',
            nodeId: 'node-b-e5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-2',
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 3)),
          'can-2': _dueState('can-2', overdue: const Duration(hours: 2)),
        },
        scope: const ReviewScope.study('study-1'),
        continuity: ReviewContinuity.fullLine,
        // Only dec-1 in the due queue; its twin waits in the buffer.
        prefetchBatchSize: 1,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      // The lapse requeues dec-1 behind the buffer, then the walk opens the due
      // dec-2 and must clear its canonical twin from the buffer along with it.
      final lapse = session.submitMove(from: 'd2', to: 'd4');
      expect(lapse.isCorrect, isFalse);
      session.continueAfterIncorrect();
      expect(session.currentPrompt?.decision.id, 'dec-2');

      // The re-test lands after the walk. dec-1 must still be there: a buffer
      // dequeue that kept or dropped the twin changes who is served next.
      final retest = session.submitMove(from: 'g1', to: 'f3');
      expect(retest.isCorrect, isTrue);
      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('the daily quota cut can never drop a promised re-test', () {
      // mutant L977: conclude when the dueQueue is empty and the buffer is not
      // dec-a is queued; answering it lifts completed to the quota. The build
      // cut held dec-c out of the queue entirely, so it can only be reached by
      // the line walk — where it lapses and is requeued as a promised re-test.
      const lineE4 = RepertoireNode(
        id: 'node-a-e4',
        fen: _fenE4,
        fenKey: _fenKeyE4,
        incomingMove: _mE4,
        children: [
          RepertoireNode(id: 'node-a-e5', fen: _fenE5, fenKey: _fenKeyE5, incomingMove: _mE5),
        ],
      );
      const lineRoot = RepertoireNode(
        id: 'node-a-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [lineE4],
      );
      const soloRoot = RepertoireNode(id: 'node-b-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(lineRoot),
          _chapterOf(soloRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _decision(id: 'dec-a', nodeId: 'node-a-root', expectedMoves: const [_mE4]),
          _decision(
            id: 'dec-b',
            nodeId: 'node-b-root',
            expectedMoves: const [_mBc4],
            chapterId: 'ch-2',
          ),
          _decision(id: 'dec-c', nodeId: 'node-a-e5', expectedMoves: const [_mBc4]),
        ],
        reviewStates: {
          'dec-a': _dueState('dec-a', overdue: const Duration(hours: 4)),
          'dec-b': _dueState('dec-b', overdue: const Duration(hours: 3)),
          'dec-c': _dueState('dec-c', overdue: const Duration(hours: 2)),
        },
        remainingDailyQuota: 2,
        prefetchBatchSize: 1,
      );
      // Only the two most urgent were queued; dec-c waits outside the queue.
      expect(session.currentPrompt?.decision.id, 'dec-a');

      final first = session.submitMove(from: 'e2', to: 'e4');
      expect(first.isCorrect, isTrue);
      expect(first.nextPrompt?.decision.id, 'dec-c');

      // Lapse the walk prompt: it is promised a re-test and requeued last.
      final lapse = session.submitMove(from: 'g1', to: 'f3');
      expect(lapse.isCorrect, isFalse);
      session.continueAfterIncorrect();
      expect(session.currentPrompt?.decision.id, 'dec-b');

      // Answering dec-b reaches the quota (2/2). The cut must set aside new
      // work and still serve the promised re-test rather than concluding.
      final second = session.submitMove(from: 'f1', to: 'c4');
      expect(second.isCorrect, isTrue);
      expect(session.currentPrompt?.decision.id, 'dec-c');
      expect(session.remainingDueCount, 1);
    });

    test('a zero refill threshold still refills before the queue runs dry', () {
      // mutant L989: _dueQueue.length <= prefetchRefillThreshold -> <
      const soloRoot = RepertoireNode(id: 'node-x-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(soloRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(),
          _decision(
            id: 'dec-x',
            nodeId: 'node-x-root',
            expectedMoves: const [_mE4],
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2)),
          'dec-x': _dueState('dec-x', overdue: const Duration(hours: 1)),
        },
        prefetchBatchSize: 1,
        prefetchRefillThreshold: 0,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // The line ends after e5 and nothing else is on the walk: the next card
      // comes from the buffer, which the advance must refill.
      expect(session.currentPrompt?.decision.id, 'dec-x');
    });
  });

  group('ReviewSession full-line starts', () {
    test('dynamic full-line skips a locked ancestor and opens at the target', () {
      // mutant L1037: mode == srs && dynamic -> mode != srs && dynamic
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          // Never presented and never unlocked: locked in dynamic mode.
          _dec1(),
          _dec2(canonicalStateId: 'can-2'),
        ],
        reviewStates: {'can-2': _dueState('can-2', reps: 2)},
        continuity: ReviewContinuity.fullLine,
        dynamic: true,
      );

      expect(session.currentPrompt?.decision.id, 'dec-2');
      expect(session.remainingDueCount, 1);
    });

    test('practice full-line still opens at the earliest ancestor in dynamic mode', () {
      // mutant L1037: mode == srs && dynamic -> mode == srs || dynamic
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec2(), _dec1()],
        continuity: ReviewContinuity.fullLine,
        mode: ReviewMode.practice,
        dynamic: true,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('a canonical-only unlock counts as an unlocked line start', () {
      // mutant L1040: unlockedDecisionIds.contains(candidate.id) || -> &&
      // mutant L1043: if (!unlocked && !learned) -> if (!unlocked || !learned)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          _dec1(canonicalStateId: 'can-1'),
          _dec2(canonicalStateId: 'can-2'),
        ],
        reviewStates: {'can-2': _dueState('can-2', reps: 2)},
        unlocked: {'can-1'},
        continuity: ReviewContinuity.fullLine,
        dynamic: true,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
    });

    test('a never-learned ancestor with a state row is not a line start', () {
      // mutant L1042: state.repetitionCount > 0 -> >= 0
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          _dec1(),
          _dec2(canonicalStateId: 'can-2'),
        ],
        reviewStates: {'dec-1': _dueState('dec-1', reps: 0), 'can-2': _dueState('can-2', reps: 2)},
        continuity: ReviewContinuity.fullLine,
        dynamic: true,
      );

      expect(session.currentPrompt?.decision.id, 'dec-2');
    });

    test('a canonical twin of the target is a valid line start', () {
      // mutant L1045: candidate.id == target.id && canonical == -> != / || forms
      // Both decisions share one due date, so the stable bucket order keeps the
      // list order: the queue opens on the target (dec-2) and must scan its
      // ancestry for the twin (dec-1) to start the walk from.
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [
          _dec2(canonicalStateId: 'can-shared'),
          _dec1(canonicalStateId: 'can-shared'),
        ],
        reviewStates: {'can-shared': _dueState('can-shared')},
        scope: const ReviewScope.study('study-1'),
        continuity: ReviewContinuity.fullLine,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
      expect(session.remainingDueCount, 1);
    });

    test('the prompt carries the played move history down the line', () {
      // mutant L1101: if (nodeId == null) return const [] -> != null
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 1)),
        },
      );

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.nextPrompt?.decision.id, 'dec-2');
      expect(result.nextPrompt?.moveHistory, ['e4', 'e5']);
    });
  });

  group('ReviewSession walk steering and canonical identity', () {
    test('the walk continues onto a learned position that is not explicitly unlocked', () {
      // mutant L792: !dynamicRepertoireMode || -> &&
      // mutant L793: isLearned || -> &&
      const queueRoot = RepertoireNode(id: 'node-x-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(queueRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(),
          _dec2(canonicalStateId: 'can-2'),
          _decision(
            id: 'dec-x',
            nodeId: 'node-x-root',
            expectedMoves: const [_mE4],
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 3)),
          'can-2': _dueState('can-2', reps: 2, overdue: const Duration(hours: 1)),
          'dec-x': _dueState('dec-x', overdue: const Duration(hours: 2)),
        },
        dynamic: true,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // The walk reaches dec-2 before the queue front (dec-x) does.
      expect(result.nextPrompt?.decision.id, 'dec-2');
    });

    test('the walk continues onto a position unlocked by canonical id alone', () {
      // mutant L794: contains(nextDecision.id) || -> &&
      // mutant L1319: the _isDecisionDue unlock check becomes &&
      const queueRoot = RepertoireNode(id: 'node-x-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(queueRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(canonicalStateId: 'can-1'),
          _dec2(canonicalStateId: 'can-2'),
          _decision(
            id: 'dec-x',
            nodeId: 'node-x-root',
            expectedMoves: const [_mE4],
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'can-1': _dueState('can-1', reps: 2, overdue: const Duration(hours: 3)),
          'dec-x': _dueState('dec-x', reps: 2, overdue: const Duration(hours: 2)),
        },
        unlocked: {'can-2'},
        dynamic: true,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.decision.id, 'dec-2');
    });

    test('a never-learned state row is not due material when steering the walk', () {
      // mutant L1315: state.repetitionCount > 0 -> >= 0
      const junctionE5 = RepertoireNode(
        id: 'node-j-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
        children: [
          RepertoireNode(
            id: 'node-j-nf3',
            fen: _fenNf3,
            fenKey: _fenKeyNf3,
            incomingMove: _mNf3,
            children: [
              RepertoireNode(
                id: 'node-j-nc6',
                fen: _fenNc6,
                fenKey: _fenKeyNc6,
                incomingMove: _mNc6,
              ),
            ],
          ),
          RepertoireNode(
            id: 'node-j-d4',
            fen: _fenD4AfterE4,
            fenKey: _fenKeyD4AfterE4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-j-d5',
                fen: _fenD5AfterD4,
                fenKey: _fenKeyD5AfterD4,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const root = RepertoireNode(
        id: 'node-j-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-j-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [junctionE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _decision(
            id: 'dec-j1',
            nodeId: 'node-j-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-j1',
          ),
          _decision(
            id: 'dec-jc1',
            nodeId: 'node-j-nc6',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-jc1',
          ),
          _decision(
            id: 'dec-jc2',
            nodeId: 'node-j-d5',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-jc2',
          ),
        ],
        reviewStates: {
          'can-j1': _dueState('can-j1', reps: 2, overdue: const Duration(hours: 2)),
          // Never reviewed, not unlocked: not due material.
          'can-jc1': _dueState('can-jc1', reps: 0, overdue: const Duration(hours: 1)),
          'can-jc2': _dueState('can-jc2', reps: 2, overdue: const Duration(hours: 1)),
        },
        dynamic: true,
      );
      expect(session.currentPrompt?.decision.id, 'dec-j1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      final userMoves = result.autoPlayedMoves.where((m) => m.isUserMove).toList();
      expect(userMoves, hasLength(1));
      expect(userMoves.single.move.san, 'd4');
    });

    test('a due-count tie at a junction keeps the first continuation', () {
      // mutant L1272: if (due > bestDue) -> >=
      const junctionE5 = RepertoireNode(
        id: 'node-j-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
        children: [
          RepertoireNode(
            id: 'node-j-nf3',
            fen: _fenNf3,
            fenKey: _fenKeyNf3,
            incomingMove: _mNf3,
            children: [
              RepertoireNode(
                id: 'node-j-nc6',
                fen: _fenNc6,
                fenKey: _fenKeyNc6,
                incomingMove: _mNc6,
              ),
            ],
          ),
          RepertoireNode(
            id: 'node-j-d4',
            fen: _fenD4AfterE4,
            fenKey: _fenKeyD4AfterE4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-j-d5',
                fen: _fenD5AfterD4,
                fenKey: _fenKeyD5AfterD4,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const root = RepertoireNode(
        id: 'node-j-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-j-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [junctionE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _decision(
            id: 'dec-j1',
            nodeId: 'node-j-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-j1',
          ),
          _decision(
            id: 'dec-jc1',
            nodeId: 'node-j-nc6',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-jc1',
          ),
          _decision(
            id: 'dec-jc2',
            nodeId: 'node-j-d5',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-jc2',
          ),
        ],
        reviewStates: {
          'can-j1': _dueState('can-j1', overdue: const Duration(hours: 3)),
          'can-jc1': _dueState('can-jc1', overdue: const Duration(hours: 2)),
          'can-jc2': _dueState('can-jc2', overdue: const Duration(hours: 1)),
        },
      );
      expect(session.currentPrompt?.decision.id, 'dec-j1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      final userMoves = result.autoPlayedMoves.where((m) => m.isUserMove).toList();
      expect(userMoves, hasLength(1));
      expect(userMoves.single.move.san, 'Nf3');
    });

    test('full-line auto-play at an unguided junction takes the first continuation', () {
      // mutant L1266: children.first -> .last in _selectUserContinuation
      const junctionE5 = RepertoireNode(
        id: 'node-j-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
        children: [
          RepertoireNode(
            id: 'node-j-nf3',
            fen: _fenNf3,
            fenKey: _fenKeyNf3,
            incomingMove: _mNf3,
            children: [
              RepertoireNode(
                id: 'node-j-nc6',
                fen: _fenNc6,
                fenKey: _fenKeyNc6,
                incomingMove: _mNc6,
              ),
            ],
          ),
          RepertoireNode(
            id: 'node-j-d4',
            fen: _fenD4AfterE4,
            fenKey: _fenKeyD4AfterE4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-j-d5',
                fen: _fenD5AfterD4,
                fenKey: _fenKeyD5AfterD4,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const root = RepertoireNode(
        id: 'node-j-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-j-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [junctionE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _decision(id: 'dec-j1', nodeId: 'node-j-root', expectedMoves: const [_mE4]),
          _decision(id: 'dec-jc1', nodeId: 'node-j-nc6', expectedMoves: const [_mBc4]),
          _decision(id: 'dec-jc2', nodeId: 'node-j-d5', expectedMoves: const [_mBc4]),
        ],
        reviewStates: {'dec-j1': _dueState('dec-j1')},
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-j1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      final userMoves = result.autoPlayedMoves.where((m) => m.isUserMove).toList();
      expect(userMoves, hasLength(1));
      expect(userMoves.single.move.san, 'Nf3');
    });

    test('full-line walk takes the first opponent reply at a junction', () {
      // mutant L1224: return node.children.first -> .last in _selectOpponentChild
      const e4Replies = RepertoireNode(
        id: 'node-e4',
        fen: _fenE4,
        fenKey: _fenKeyE4,
        incomingMove: _mE4,
        children: [
          RepertoireNode(id: 'node-e5', fen: _fenE5, fenKey: _fenKeyE5, incomingMove: _mE5),
          RepertoireNode(id: 'node-c5', fen: _fenC5, fenKey: _fenKeyC5, incomingMove: _mC5),
        ],
      );
      const root = RepertoireNode(
        id: 'node-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [e4Replies],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _dec1(),
          _decision(id: 'dec-e5', nodeId: 'node-e5', expectedMoves: const [_mNf3]),
          _decision(id: 'dec-c5', nodeId: 'node-c5', expectedMoves: const [_mNf3]),
        ],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 3)),
          'dec-e5': _dueState('dec-e5', overdue: const Duration(hours: 2)),
          'dec-c5': _dueState('dec-c5', overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.decision.id, 'dec-e5');
    });

    test('auto-traversal credits each traversed question on its own canonical id', () {
      // mutant L854: nextDecision.canonicalStateId != null -> == null
      // mutant L877: siblingDecision.canonicalStateId != null -> == null
      const xE5 = RepertoireNode(
        id: 'node-x-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
        children: [
          RepertoireNode(id: 'node-x-nf3', fen: _fenNf3, fenKey: _fenKeyNf3, incomingMove: _mNf3),
          RepertoireNode(
            id: 'node-x-d4',
            fen: _fenD4AfterE4,
            fenKey: _fenKeyD4AfterE4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-x-d5',
                fen: _fenD5AfterD4,
                fenKey: _fenKeyD5AfterD4,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const xRoot = RepertoireNode(
        id: 'node-x-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-x-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [xE5],
          ),
        ],
      );
      // The twins are indexed after the originals, and can-t1 is due so the
      // twin chapter is loaded at build: a fen-move lookup would resolve to
      // the twins instead of the questions the walk actually passed.
      const yE5 = RepertoireNode(
        id: 'node-y-e5',
        fen: _fenE5,
        fenKey: _fenKeyE5,
        incomingMove: _mE5,
        children: [
          RepertoireNode(
            id: 'node-y-d4',
            fen: _fenD4AfterE4,
            fenKey: _fenKeyD4AfterE4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-y-d5',
                fen: _fenD5AfterD4,
                fenKey: _fenKeyD5AfterD4,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const yRoot = RepertoireNode(
        id: 'node-y-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-y-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [yE5],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(xRoot),
          _chapterOf(yRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _decision(
            id: 'dec-x1',
            nodeId: 'node-x-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-x1',
          ),
          _decision(
            id: 'dec-x2',
            nodeId: 'node-x-e5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-x2',
          ),
          _decision(
            id: 'dec-sib',
            nodeId: 'node-x-d5',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-sib',
          ),
          _decision(
            id: 'dec-twin1',
            nodeId: 'node-y-e5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-t1',
            chapterId: 'ch-2',
          ),
          _decision(
            id: 'dec-twin2',
            nodeId: 'node-y-d5',
            expectedMoves: const [_mBc4],
            canonicalStateId: 'can-t2',
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'can-x1': _dueState('can-x1', overdue: const Duration(hours: 3)),
          'can-x2': _scheduledState('can-x2', stability: 200),
          'can-sib': _scheduledState('can-sib', stability: 300),
          // Due, so its chapter is indexed when the session is built: the
          // fen-move collision must be live before the walk runs.
          'can-t1': _dueState('can-t1', stability: 100, overdue: const Duration(hours: 1)),
          'can-t2': _scheduledState('can-t2', stability: 100),
        },
      );
      expect(session.currentPrompt?.decision.id, 'dec-x1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);

      // The traversed question and the passed-over sibling were both exposed
      // on their own canonicals; the transposed twins stay untouched.
      expect(session.reviewStates['can-x2']!.stability, closeTo(216, 1e-6));
      expect(session.reviewStates['can-sib']!.stability, closeTo(324, 1e-6));
      expect(session.reviewStates['can-t1']!.stability, closeTo(100, 1e-6));
      expect(session.reviewStates['can-t2']!.stability, closeTo(100, 1e-6));
    });

    test('a lapse couples every sibling question on its own canonical id', () {
      // mutant L1389: other.canonicalStateId != null -> == null
      // mutant L663: if (sideEffects.isNotEmpty) -> isEmpty (fine log)
      const bRoot = RepertoireNode(id: 'node-b-root', fen: _fenStart, fenKey: _fenKeyStart);
      const cRoot = RepertoireNode(id: 'node-c-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(bRoot, chapterId: 'ch-2'),
          _chapterOf(cRoot, chapterId: 'ch-3'),
        ],
        decisions: [
          _decision(
            id: 'dec-ka',
            nodeId: 'node-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-ka',
          ),
          _decision(
            id: 'dec-kb',
            nodeId: 'node-b-root',
            expectedMoves: const [_mD4],
            canonicalStateId: 'can-kb',
            chapterId: 'ch-2',
          ),
          _decision(
            id: 'dec-kc',
            nodeId: 'node-c-root',
            expectedMoves: const [_mD4],
            canonicalStateId: 'can-kc',
            chapterId: 'ch-3',
          ),
        ],
        reviewStates: {
          'can-ka': _dueState('can-ka', overdue: const Duration(hours: 3)),
          'can-kb': _dueState('can-kb', difficulty: 4.0, overdue: const Duration(hours: 2)),
          'can-kc': _dueState('can-kc', difficulty: 4.0, overdue: const Duration(hours: 1)),
        },
      );
      expect(session.currentPrompt?.decision.id, 'dec-ka');

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);

      final result = session.submitMove(from: 'd2', to: 'd4');
      expect(result.isCorrect, isFalse);

      // Each sibling question was coupled once, against its own canonical.
      expect(session.reviewStates['can-kb']!.difficulty, closeTo(4.35, 1e-9));
      expect(session.reviewStates['can-kc']!.difficulty, closeTo(4.35, 1e-9));
      expect(records.any((r) => r.message.contains('Lapse contagion/coupling updated')), isTrue);
    });

    test('a lapse is graded against the question own canonical state', () {
      // mutant L633: decision.canonicalStateId != null -> == null
      const twinRoot = RepertoireNode(id: 'node-b-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(twinRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(canonicalStateId: 'can-first'),
          _decision(
            id: 'dec-second',
            nodeId: 'node-b-root',
            // The same position and the same expected move as dec-1, so the
            // fen-move map keeps whichever question is indexed later.
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-second',
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {
          'can-first': _dueState('can-first', reps: 5),
          // Scheduled, so it is never prompted: only its history can leak.
          'can-second': _scheduledState('can-second', reps: 7, difficulty: 6.0, stability: 300),
        },
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'd2', to: 'd4');
      expect(result.isCorrect, isFalse);

      // The lapse is scheduled against dec-1's own canonical state. Under the
      // mutant the fen-move map resolves the grade to can-second instead: that
      // row is lapsed (reps 7 -> 0) and its history leaks onto dec-1's row.
      expect(session.reviewStates['can-first']!.repetitionCount, 0);
      expect(session.reviewStates['can-first']!.lapseCount, 1);
      expect(session.reviewStates['can-first']!.difficulty, closeTo(4.0, 1e-9));
      expect(session.reviewStates['can-second']!.repetitionCount, 7);
      expect(session.reviewStates['can-second']!.lapseCount, 0);
      expect(session.reviewStates['can-second']!.stability, closeTo(300, 1e-9));
    });

    test('a valid promotion move is matched through the transposed line', () {
      // mutant L1163: movePlayed.promotion != null && promotion == null -> != null
      const promoRoot = RepertoireNode(
        id: 'node-pm',
        fen: _fenPromo,
        fenKey: _fenKeyPromo,
        children: [
          RepertoireNode(
            id: 'node-pm-q',
            fen: _fenPromoQ,
            fenKey: _fenKeyPromoQ,
            incomingMove: _mPromoQ,
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(promoRoot)],
        decisions: [
          _decision(id: 'dec-pm', nodeId: 'node-pm', expectedMoves: const [_mPromoR]),
        ],
        reviewStates: {'dec-pm': _dueState('dec-pm', reps: 1)},
      );
      expect(session.currentPrompt?.decision.id, 'dec-pm');

      final result = session.submitMove(from: 'a7', to: 'a8', promotion: 'q');
      expect(result.isCorrect, isTrue);
      expect(session.reviewStates['dec-pm']!.repetitionCount, greaterThan(1));
    });
  });

  group('ReviewSession move logging', () {
    test('a transposed acceptance is marked, a direct one is not', () {
      // mutant L587: transposedStart != null -> == null
      const qRoot = RepertoireNode(
        id: 'node-q',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(id: 'node-q-e4', fen: _fenE4, fenKey: _fenKeyE4, incomingMove: _mE4),
        ],
      );
      ReviewSession sessionWith() => _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(qRoot)],
        decisions: [
          _decision(id: 'dec-q', nodeId: 'node-q', expectedMoves: const [_mD4]),
        ],
        reviewStates: {'dec-q': _dueState('dec-q')},
      );

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      // e4 is not expected at the root, but the tree records it: transposed.
      final transposed = sessionWith();
      final first = transposed.submitMove(from: 'e2', to: 'e4');
      expect(first.isCorrect, isTrue);
      final transposedMoves = records
          .where((r) => r.message.startsWith('Move correct:'))
          .map((r) => r.message)
          .toList();
      expect(transposedMoves, hasLength(1));
      expect(transposedMoves.single, contains('(transposed line)'));

      records.clear();

      // d4 is the expected move: a direct acceptance carries no marker.
      final direct = sessionWith();
      final second = direct.submitMove(from: 'd2', to: 'd4');
      expect(second.isCorrect, isTrue);
      final directMoves = records
          .where((r) => r.message.startsWith('Move correct:'))
          .map((r) => r.message)
          .toList();
      expect(directMoves, hasLength(1));
      expect(directMoves.single, isNot(contains('(transposed line)')));
    });
  });
}
