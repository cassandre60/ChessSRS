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
const _fenC5Nf3 = 'rnbqkbnr/pppp1ppp/8/2p5/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
const _fenKeyC5Nf3 = 'rnbqkbnr/pppp1ppp/8/2p5/5N2/PPPP1PPP/RNBQKB1R b KQkq -';
const _fenC5Nf3Nc6 = 'r1bqkbnr/pppp1ppp/2n5/2p5/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
const _fenKeyC5Nf3Nc6 = 'r1bqkbnr/pppp1ppp/2n5/2p5/5N2/PPPP1PPP/RNBQKB1R w KQkq -';
const _fenC5D4 = 'rnbqkbnr/pppp1ppp/8/2p5/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 2';
const _fenKeyC5D4 = 'rnbqkbnr/pppp1ppp/8/2p5/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -';
const _fenC5D4D5 = 'rnbqkbnr/pppp1ppp/3p4/2p5/3P4/8/PPP1PPPP/RNBQKBNR w KQkq d6 0 3';
const _fenKeyC5D4D5 = 'rnbqkbnr/pppp1ppp/3p4/2p5/3P4/8/PPP1PPPP/RNBQKBNR w KQkq -';
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
  String? fenKey,
  String chapterId = _chapterId,
  String studyId = _studyId,
}) => RepertoireDecision(
  id: id,
  studyId: studyId,
  chapterId: chapterId,
  nodeId: nodeId,
  expectedMoves: expectedMoves,
  canonicalStateId: canonicalStateId,
  fenKey: fenKey,
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

    test(
      'answering a due ancestor does not introduce a fresh descendant when new allowance is zero (INV-068)',
      () {
        // Tree A has due ancestor dec-1 (1. e4) -> opponent 1... e5 -> fresh descendant dec-2 (2. Nf3).
        // Tree B has due question dec-other (1. d4).
        const rootOther = RepertoireNode(
          id: 'node-other-root',
          fen: _fenStart,
          fenKey: _fenKeyStart,
        );
        final decOther = _decision(
          id: 'dec-other',
          nodeId: 'node-other-root',
          expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
          chapterId: 'ch-other',
        );
        final session = _session(
          studies: [_studyOf()],
          chapters: [
            _chapterOf(_lRoot),
            _chapterOf(rootOther, chapterId: 'ch-other'),
          ],
          decisions: [_dec1(), _dec2(), decOther],
          reviewStates: {
            'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2)),
            'dec-other': _dueState('dec-other', overdue: const Duration(hours: 1)),
          },
          remainingNewQuota: 0,
        );

        // Dec-1 and dec-other are due; fresh descendant dec-2 is not introduced.
        expect(session.initialDueCount, 2);
        expect(session.initialQueueCount, 2);
        expect(session.currentPrompt?.decision.id, 'dec-1');

        // Answer dec-1 correctly.
        final result = session.submitMove(from: 'e2', to: 'e4');
        expect(result.isCorrect, isTrue);
        // Opponent replies with 1... e5.
        expect(result.autoPlayedMoves.map((m) => m.move.san), ['e5']);

        // SPEC INV-068: fresh descendant dec-2 must NOT be introduced when remainingNewQuota is 0,
        // and remaining due work (dec-other) must stay ahead!
        expect(result.nextPrompt?.decision.id, 'dec-other');
        expect(session.currentPrompt?.decision.id, 'dec-other');
      },
    );

    test(
      'answering ancestor with zero new allowance and no other due work completes session without introducing fresh descendant (INV-068)',
      () {
        final session = _session(
          studies: [_studyOf()],
          chapters: [_chapterOf(_lRoot)],
          decisions: [_dec1(), _dec2()],
          reviewStates: {'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2))},
          remainingNewQuota: 0,
        );

        expect(session.initialDueCount, 1);
        expect(session.initialQueueCount, 1);
        expect(session.currentPrompt?.decision.id, 'dec-1');

        final result = session.submitMove(from: 'e2', to: 'e4');
        expect(result.isCorrect, isTrue);
        expect(result.autoPlayedMoves.map((m) => m.move.san), ['e5']);

        expect(result.nextPrompt, isNull);
        expect(session.currentPrompt, isNull);
        expect(session.isComplete, isTrue);
      },
    );

    test(
      'due work stays ahead of admitted fresh introductions down an answered line (INV-068)',
      () {
        const rootOther = RepertoireNode(
          id: 'node-other-root',
          fen: _fenStart,
          fenKey: _fenKeyStart,
        );
        final decOther = _decision(
          id: 'dec-other',
          nodeId: 'node-other-root',
          expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
          chapterId: 'ch-other',
        );
        final session = _session(
          studies: [_studyOf()],
          chapters: [
            _chapterOf(_lRoot),
            _chapterOf(rootOther, chapterId: 'ch-other'),
          ],
          decisions: [_dec1(), _dec2(), decOther],
          reviewStates: {
            'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2)),
            'dec-other': _dueState('dec-other', overdue: const Duration(hours: 1)),
          },
          remainingNewQuota: 5,
        );

        // 2 due questions and 1 admitted fresh introduction.
        expect(session.initialDueCount, 2);
        expect(session.initialQueueCount, 3);
        expect(session.currentPrompt?.decision.id, 'dec-1');

        // Answering dec-1 must NOT prompt fresh dec-2 yet; due dec-other must stay ahead.
        final res1 = session.submitMove(from: 'e2', to: 'e4');
        expect(res1.isCorrect, isTrue);
        expect(res1.nextPrompt?.decision.id, 'dec-other');
        expect(session.currentPrompt?.decision.id, 'dec-other');

        // After all due work is complete, the admitted fresh introduction is served.
        final res2 = session.submitMove(from: 'd2', to: 'd4');
        expect(res2.isCorrect, isTrue);
        expect(res2.nextPrompt?.decision.id, 'dec-2');
        expect(session.currentPrompt?.decision.id, 'dec-2');
      },
    );

    test('full-line continuity is exempt from the due-before-fresh ordering (INV-068)', () {
      // "Full line" means every line is played whole: the walk asks the
      // fresh step below the answered one even though due work is queued
      // elsewhere. The introduction allowance still caps it.
      const rootOther = RepertoireNode(id: 'node-other-root', fen: _fenStart, fenKey: _fenKeyStart);
      final decOther = _decision(
        id: 'dec-other',
        nodeId: 'node-other-root',
        expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        chapterId: 'ch-other',
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(rootOther, chapterId: 'ch-other'),
        ],
        decisions: [_dec1(), _dec2(), decOther],
        reviewStates: {
          'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2)),
          'dec-other': _dueState('dec-other', overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
        remainingNewQuota: 5,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // The fresh step below the answered one is asked, not deferred behind
      // dec-other: that is what "every line whole" means.
      expect(result.nextPrompt?.decision.id, 'dec-2');
    });

    test(
      'practice mode is explicitly exempt from fresh introduction cap during traversal (INV-068)',
      () {
        const rootOther = RepertoireNode(
          id: 'node-other-root',
          fen: _fenStart,
          fenKey: _fenKeyStart,
        );
        final decOther = _decision(
          id: 'dec-other',
          nodeId: 'node-other-root',
          expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
          chapterId: 'ch-other',
        );
        final session = _session(
          studies: [_studyOf()],
          chapters: [
            _chapterOf(_lRoot),
            _chapterOf(rootOther, chapterId: 'ch-other'),
          ],
          decisions: [_dec1(), _dec2(), decOther],
          reviewStates: {
            'dec-1': _dueState('dec-1', overdue: const Duration(hours: 2)),
            'dec-other': _dueState('dec-other', overdue: const Duration(hours: 1)),
          },
          mode: ReviewMode.practice,
          remainingNewQuota: 0,
        );

        expect(session.currentPrompt?.decision.id, 'dec-1');

        // In practice mode, rehearsal walks fresh descendant dec-2 immediately.
        final result = session.submitMove(from: 'e2', to: 'e4');
        expect(result.isCorrect, isTrue);
        expect(result.autoPlayedMoves.map((m) => m.move.san), ['e5']);
        expect(result.nextPrompt?.decision.id, 'dec-2');
        expect(session.currentPrompt?.decision.id, 'dec-2');
      },
    );

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

    test('a full-line re-answer of a completed prefix is rehearsed, not re-graded', () {
      // mutant L539: continuity == ReviewContinuity.fullLine -> != / ||
      // mutant L540: mode == ReviewMode.srs -> != / ||
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final first = session.submitMove(from: 'e2', to: 'e4');
      expect(first.nextPrompt?.decision.id, 'dec-2');
      final gradedReps = session.reviewStates['dec-1']!.repetitionCount;
      expect(gradedReps, 4);

      // dec-2 lapses; its line-start re-pop walks the ancestry back to the
      // already-completed prefix (dec-1) and re-prompts it.
      final lapse = session.submitMove(from: 'c2', to: 'c4');
      expect(lapse.isCorrect, isFalse);
      session.continueAfterIncorrect();
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final replay = session.submitMove(from: 'e2', to: 'e4');
      expect(replay.isCorrect, isTrue);
      // Rehearsed: the prefix is re-walked with practice grading. No SRS event
      // fires and the state written by the first answer stands untouched.
      expect(replay.event, isNull);
      expect(session.reviewStates['dec-1']!.repetitionCount, gradedReps);
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

    test('couples siblings identically when the decision rows carry their fen key', () {
      // The v21 row carries its node's fen key, so the sibling-coupling index
      // is built from rows instead of decoded trees. Same fixture as the test
      // above, with every decision filled the way the v21 backfill leaves it —
      // coupling must not care which way the identity arrived.
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
            fenKey: _fenKeyStart,
          ),
          _decision(
            id: 'dec-kb',
            nodeId: 'node-b-root',
            expectedMoves: const [_mD4],
            canonicalStateId: 'can-kb',
            chapterId: 'ch-2',
            fenKey: _fenKeyStart,
          ),
          _decision(
            id: 'dec-kc',
            nodeId: 'node-c-root',
            expectedMoves: const [_mD4],
            canonicalStateId: 'can-kc',
            chapterId: 'ch-3',
            fenKey: _fenKeyStart,
          ),
        ],
        reviewStates: {
          'can-ka': _dueState('can-ka', overdue: const Duration(hours: 3)),
          'can-kb': _dueState('can-kb', difficulty: 4.0, overdue: const Duration(hours: 2)),
          'can-kc': _dueState('can-kc', difficulty: 4.0, overdue: const Duration(hours: 1)),
        },
      );
      expect(session.currentPrompt?.decision.id, 'dec-ka');

      final result = session.submitMove(from: 'd2', to: 'd4');
      expect(result.isCorrect, isFalse);

      expect(session.reviewStates['can-kb']!.difficulty, closeTo(4.35, 1e-9));
      expect(session.reviewStates['can-kc']!.difficulty, closeTo(4.35, 1e-9));
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

    test('practice full-line in dynamic mode still prompts the locked branch below', () {
      // mutant L804: mode == ReviewMode.srs -> != (the locked-branch break
      // would fire for practice instead of srs)
      const queueRoot = RepertoireNode(id: 'node-x-root', fen: _fenStart, fenKey: _fenKeyStart);
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(queueRoot, chapterId: 'ch-2'),
        ],
        decisions: [
          _dec1(),
          // Never presented and never unlocked: locked in dynamic mode.
          _dec2(),
          _decision(
            id: 'dec-u',
            nodeId: 'node-x-root',
            expectedMoves: const [_mD4],
            chapterId: 'ch-2',
          ),
        ],
        reviewStates: {'dec-1': _dueState('dec-1')},
        mode: ReviewMode.practice,
        continuity: ReviewContinuity.fullLine,
        dynamic: true,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // Practice mode has no dynamic lock on the walk: the branch below the
      // reply is prompted even though nothing was ever unlocked for it.
      expect(result.nextPrompt?.decision.id, 'dec-2');
    });

    test('reaching the daily quota in due-only mode still auto-plays the line below', () {
      // mutant L805: continuity == ReviewContinuity.fullLine -> != (a due-only
      // walk would break at the quota instead of walking past it)
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(_lRoot)],
        decisions: [_dec1(), _dec2()],
        reviewStates: {
          'dec-1': _dueState('dec-1'),
          'dec-2': _dueState('dec-2', overdue: const Duration(hours: 1)),
        },
        remainingDailyQuota: 1,
      );
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // The quota has no card left for dec-2, but the walk under the answer
      // still plays on: the reply, the user continuation past the passed-over
      // question, its opponent reply — and dec-2 earns its traversal exposure.
      expect(result.autoPlayedMoves.length, 4);
      expect(result.autoPlayedMoves.map((m) => m.move.san), ['e5', 'Nf3', 'Nc6', 'Bc4']);
      expect(result.sideEffectStates, isNotEmpty);
    });
  });

  group('ReviewSession dynamic lock and dedicated walk geometry', () {
    test('a never-learned branch ends the dynamic walk instead of being entered', () {
      // mutant L790: decState.repetitionCount > 0 -> >= 0
      // The branch below the reply holds a state row that was never learned:
      // in dynamic mode it is locked, so the walk stops on it and never
      // auto-plays the user's own move into it.
      const root = RepertoireNode(
        id: 'node-l-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-l-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [
              RepertoireNode(
                id: 'node-l-e5',
                fen: _fenE5,
                fenKey: _fenKeyE5,
                incomingMove: _mE5,
                children: [
                  RepertoireNode(
                    id: 'node-l-nf3',
                    fen: _fenNf3,
                    fenKey: _fenKeyNf3,
                    incomingMove: _mNf3,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _decision(
            id: 'dec-l1',
            nodeId: 'node-l-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-l1',
          ),
          _decision(
            id: 'dec-l2',
            nodeId: 'node-l-e5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-l2',
          ),
        ],
        reviewStates: {
          'can-l1': _dueState('can-l1', reps: 2, overdue: const Duration(hours: 2)),
          // Due by date, but never learned: locked in dynamic mode.
          'can-l2': _dueState('can-l2', reps: 0, overdue: const Duration(hours: 1)),
        },
        dynamic: true,
      );
      expect(session.currentPrompt?.decision.id, 'dec-l1');
      // The locked branch is not queued either: nothing ever unlocked it.
      expect(session.remainingDueCount, 1);

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // The reply below the answered card is played, and the walk stops there.
      expect(result.autoPlayedMoves.map((m) => m.move.san), ['e5']);
      // The locked branch earns no traversal exposure.
      expect(result.sideEffectStates, isEmpty);
      expect(result.nextPrompt, isNull);
    });

    test('the dedicated walk follows its guide into the side branch and re-prompts the target', () {
      // mutant L1057: _guidedNodeIds.isEmpty -> .isNotEmpty
      // mutant L1060: if (index < 0) -> if (index <= 0)
      // mutant L1061: _guidedNodeIds.sublist(index + 1) -> sublist(index + 2)
      // SPEC INV-022.
      const sideDecoy = RepertoireNode(
        id: 'node-g-alt',
        fen: _fenC5Nf3,
        fenKey: _fenKeyC5Nf3,
        incomingMove: _mNf3,
        children: [
          RepertoireNode(
            id: 'node-g-alt-nc6',
            fen: _fenC5Nf3Nc6,
            fenKey: _fenKeyC5Nf3Nc6,
            incomingMove: _mNc6,
          ),
        ],
      );
      const sideBranch = RepertoireNode(
        id: 'node-g-c5',
        fen: _fenC5,
        fenKey: _fenKeyC5,
        incomingMove: _mC5,
        children: [
          // The decoy comes first: only the guide can pick the branch below.
          sideDecoy,
          RepertoireNode(
            id: 'node-g-d4',
            fen: _fenC5D4,
            fenKey: _fenKeyC5D4,
            incomingMove: _mD4,
            children: [
              RepertoireNode(
                id: 'node-g-d5',
                fen: _fenC5D4D5,
                fenKey: _fenKeyC5D4D5,
                incomingMove: _mD5,
              ),
            ],
          ),
        ],
      );
      const root = RepertoireNode(
        id: 'node-g-root',
        fen: _fenStart,
        fenKey: _fenKeyStart,
        children: [
          RepertoireNode(
            id: 'node-g-e4',
            fen: _fenE4,
            fenKey: _fenKeyE4,
            incomingMove: _mE4,
            children: [
              // The mainline the tree-order walk takes.
              RepertoireNode(
                id: 'node-g-e5',
                fen: _fenE5,
                fenKey: _fenKeyE5,
                incomingMove: _mE5,
                children: [
                  RepertoireNode(
                    id: 'node-g-nf3',
                    fen: _fenNf3,
                    fenKey: _fenKeyNf3,
                    incomingMove: _mNf3,
                    children: [
                      RepertoireNode(
                        id: 'node-g-nc6',
                        fen: _fenNc6,
                        fenKey: _fenKeyNc6,
                        incomingMove: _mNc6,
                      ),
                    ],
                  ),
                ],
              ),
              // The side branch the dedicated walk's guide points at.
              sideBranch,
            ],
          ),
        ],
      );
      final session = _session(
        studies: [_studyOf()],
        chapters: [_chapterOf(root)],
        decisions: [
          _decision(
            id: 'dec-g1',
            nodeId: 'node-g-root',
            expectedMoves: const [_mE4],
            canonicalStateId: 'can-g1',
          ),
          _decision(
            id: 'dec-g2',
            nodeId: 'node-g-d5',
            expectedMoves: const [_mNf3],
            canonicalStateId: 'can-g2',
          ),
        ],
        reviewStates: {
          'can-g1': _dueState('can-g1', reps: 2, overdue: const Duration(hours: 2)),
          'can-g2': _dueState('can-g2', reps: 2, overdue: const Duration(hours: 1)),
        },
        continuity: ReviewContinuity.fullLine,
      );
      expect(session.currentPrompt?.decision.id, 'dec-g1');

      // First pass: tree order takes the mainline and misses the side branch.
      final first = session.submitMove(from: 'e2', to: 'e4');
      expect(first.isCorrect, isTrue);
      expect(first.autoPlayedMoves.map((m) => m.move.san), ['e5', 'Nf3', 'Nc6']);
      expect(first.nextPrompt?.decision.id, 'dec-g1');

      // Second pass: the session re-opens the line start to try the target again.
      final second = session.submitMove(from: 'e2', to: 'e4');
      expect(second.isCorrect, isTrue);
      expect(second.autoPlayedMoves.map((m) => m.move.san), ['e5', 'Nf3', 'Nc6']);
      expect(second.nextPrompt?.decision.id, 'dec-g1');

      // Third pass: the guide is armed, so the walk follows the side branch
      // and re-prompts the target that tree order would keep starving.
      final third = session.submitMove(from: 'e2', to: 'e4');
      expect(third.isCorrect, isTrue);
      expect(third.autoPlayedMoves.map((m) => m.move.san), ['c5', 'd4', 'd5']);
      expect(third.nextPrompt?.decision.id, 'dec-g2');
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

    test('a small chapter backlog indexes synchronously, with no scheduled work', () {
      // Budget path: at most kSynchronousIndexingChapterBudget chapters decode
      // inside the constructor, so the session is fully indexed the moment it
      // exists and no background timer was ever scheduled — a widget-test
      // FakeAsync zone must never see one pending.
      final session = _session(
        studies: [_studyOf()],
        chapters: [
          _chapterOf(_lRoot),
          _chapterOf(_lRoot, chapterId: 'ch-2'),
          _chapterOf(_lRoot, chapterId: 'ch-3'),
        ],
        decisions: [_dec1(canonicalStateId: 'can-1')],
        reviewStates: {'can-1': _dueState('can-1', overdue: const Duration(hours: 1))},
      );
      expect(
        session.isNodeIndexComplete,
        isTrue,
        reason: 'a 3-chapter backlog is inside the synchronous budget',
      );
    });

    test('a large chapter backlog defers to the background pass and completes', () async {
      // Above the budget the constructor must NOT decode every tree (that is
      // the whole point of v21); the background pass finishes the tail.
      final chapters = [
        for (var i = 0; i < 12; i++)
          _chapterOf(
            RepertoireNode(id: 'node-root-$i', fen: _fenStart, fenKey: _fenKeyStart),
            chapterId: 'ch-${i + 1}',
          ),
      ];
      final session = _session(
        studies: [_studyOf()],
        chapters: chapters,
        decisions: [_dec1(canonicalStateId: 'can-1')],
        reviewStates: {'can-1': _dueState('can-1', overdue: const Duration(hours: 1))},
      );
      expect(
        session.isNodeIndexComplete,
        isFalse,
        reason: 'a 12-chapter backlog exceeds the synchronous budget',
      );

      var turns = 0;
      while (!session.isNodeIndexComplete && turns < 100) {
        await Future<void>.delayed(Duration.zero);
        turns++;
      }
      expect(
        session.isNodeIndexComplete,
        isTrue,
        reason: 'the background pass must finish the deferred chapters',
      );
    });
  });
}
