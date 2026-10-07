// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/review/review_mode.dart';
import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:chess_srs/src/domain/review/review_prompt.dart';
import 'package:chess_srs/src/domain/review/review_scope.dart';
import 'package:chess_srs/src/domain/review/review_step_result.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:chess_srs/src/domain/review_result.dart';
import 'package:chess_srs/src/domain/review_state.dart';
import 'package:chess_srs/src/domain/scheduler.dart';
import 'package:chess_srs/src/domain/study.dart';
import 'package:dartchess/dartchess.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('ReviewEngine');

/// Default number of due decisions buffered in the active queue at once.
///
/// Declared here, next to the [ReviewSession] field it feeds, because the
/// engine (which forwards it) and the application service (which starts
/// sessions) both used to carry their own copy of the number: three
/// independent `25`s that had to be changed together to mean anything.
const int kDefaultPrefetchBatchSize = 25;

/// Default threshold at which the active prefetch buffer refills.
///
/// The companion of [kDefaultPrefetchBatchSize]; see it for why the defaults
/// live on this side of the boundary.
const int kDefaultPrefetchRefillThreshold = 3;

/// Active review session state machine.
///
/// Encapsulates queue management, move validation against repertoire (Invariant §2.1),
/// auto-traversal through opponent replies and already-learned user moves (Invariant §2.4),
/// queue prefetching and buffering (chessrs PracticeMainPanel.tsx semantics),
/// and deterministic time testing via [Clock] (Invariant §3.2).
class ReviewSession {
  ReviewSession({
    required List<Study> studies,
    required List<Chapter> chapters,
    required List<RepertoireDecision> decisions,
    required Map<String, ReviewState> reviewStates,
    this.scope = const ReviewScope.all(),
    this.mode = ReviewMode.srs,
    this.order = ReviewOrder.dueDate,
    this.transposeScope = TransposeScope.inScope,
    this.scheduler = const SimpleScheduler(),
    this.clock = const SystemClock(),
    this.prefetchBatchSize = kDefaultPrefetchBatchSize,
    this.prefetchRefillThreshold = kDefaultPrefetchRefillThreshold,
    this.remainingDailyQuota,
    GraphAwareReviewCoordinator? coordinator,
    Random? random,
  }) : _random = random ?? Random(),
       _studies = {for (final s in studies) s.id: s},
       _chapters = {for (final c in chapters) c.id: c},
       _reviewStates = Map<String, ReviewState>.from(reviewStates),
       _decisionsById = {for (final d in decisions) d.id: d},
       _decisionForNode = {for (final d in decisions) d.nodeId: d} {
    // Index all nodes across chapter trees for O(1) lookup
    for (final chapter in chapters) {
      if (chapter.root != null) {
        _indexNodes(chapter.root!, chapter.id);
      }
    }

    // Canonical identity is shared position knowledge: two occurrences that ask the same
    // question (same FEN, same complete accepted set) deliberately collapse to one entry here,
    // which is what lets a transposition inherit the memory built for the position it transposed
    // into. Occurrence identity stays separate — [RepertoireDecision.id] and [RepertoireDecision
    // .nodeId] still address each appearance on its own, and `_decisionsById` keeps them all.
    //
    // `_canonicalByFenMove` stays keyed by (FEN, single move) on purpose: the graph layer uses it
    // for position adjacency, where propagating between two questions asked at the same board is
    // the intent. It is not the scheduling identity — that is the canonical ID above.
    for (final d in decisions) {
      _decisionsByCanonicalId[d.canonicalId] = d;
      final node = _nodesById[d.nodeId];
      if (node != null) {
        _decisionsByFenKey.putIfAbsent(node.fenKey, () => []).add(d);
        for (final m in d.expectedMoves) {
          _canonicalByFenMove['${node.fenKey}|${m.uci}'] = d.canonicalId;
        }
      }
    }

    _coordinator =
        coordinator ??
        GraphAwareReviewCoordinator(
          scheduler: scheduler,
          repo: _SessionReviewStateRepository(this),
        );

    // Build initial due queue
    final now = clock.now();
    final queuedCanonicalIds = <String>{};
    for (final d in decisions) {
      final chapter = _chapters[d.chapterId];
      if (!scope.matches(
        studyId: d.studyId,
        chapterId: d.chapterId,
        openingFamily: chapter?.opening,
        side: chapter?.orientation,
      )) {
        continue;
      }
      final state = _reviewStates[d.canonicalId] ?? _reviewStates[d.id];
      if (mode == ReviewMode.practice || state == null || state.isDueAt(now)) {
        // In multi-study scope, deduplicate shared canonical transpositions
        if (scope.studyId == null && scope.chapterId == null) {
          if (!queuedCanonicalIds.add(d.canonicalId)) {
            continue;
          }
        }
        _unbufferedQueue.add(d);
      }
    }

    if (mode == ReviewMode.srs) {
      _unbufferedQueue.sort((a, b) {
        final stateA = _reviewStates[a.canonicalId] ?? _reviewStates[a.id];
        final stateB = _reviewStates[b.canonicalId] ?? _reviewStates[b.id];
        final dueA = stateA?.nextDueAt;
        final dueB = stateB?.nextDueAt;
        if (dueA == null && dueB == null) return 0;
        if (dueA == null) return -1;
        if (dueB == null) return 1;
        return dueA.compareTo(dueB);
      });

      if (remainingDailyQuota != null &&
          remainingDailyQuota! >= 0 &&
          _unbufferedQueue.length > remainingDailyQuota!) {
        _logger.info(
          'Daily review quota ($remainingDailyQuota) reached, truncating queue to most urgent due items',
        );
        _unbufferedQueue.removeRange(remainingDailyQuota!, _unbufferedQueue.length);
      }

      // By-line order (INV-066): same set, walking study, chapter, tree order.
      if (order == ReviewOrder.byLine) {
        final studyIndex = <String, int>{for (var i = 0; i < studies.length; i++) studies[i].id: i};
        var n = 0;
        final nodeOrder = <String, int>{for (final id in _nodesById.keys) id: n++};
        _unbufferedQueue.sort((a, b) {
          var c = (studyIndex[a.studyId] ?? 0).compareTo(studyIndex[b.studyId] ?? 0);
          if (c != 0) return c;
          c = (_chapters[a.chapterId]?.sourceOrder ?? 0).compareTo(
            _chapters[b.chapterId]?.sourceOrder ?? 0,
          );
          if (c != 0) return c;
          return (nodeOrder[a.nodeId] ?? 0).compareTo(nodeOrder[b.nodeId] ?? 0);
        });
      }

      // Random order: same set, shuffled with the session Random.
      if (order == ReviewOrder.random) {
        _unbufferedQueue.shuffle(_random);
      }
    }

    _initialDueCount = _unbufferedQueue.length;
    _refillPrefetchBuffer();
    _advanceToNextDue();
    _logger.info(
      'ReviewSession created: mode=$mode, scope=$scope, initialDueCount=$_initialDueCount, remainingQuota=$remainingDailyQuota',
    );
  }

  final ReviewScope scope;
  final ReviewMode mode;

  /// Presentation order of the due queue; the due set never depends on this.
  final ReviewOrder order;

  /// Off-line-but-book moves accepted (INV-065); off keeps strict grading.
  final TransposeScope transposeScope;
  final Scheduler scheduler;
  final Clock clock;
  final Random _random;

  /// Optional daily quota limit for SRS reviews. When met, review completes for the day.
  final int? remainingDailyQuota;

  /// Maximum batch size of due decisions to buffer in the active queue at once.
  /// Null disables batching and buffers the entire queue.
  final int? prefetchBatchSize;

  /// Threshold at which the active prefetch buffer refills from unbuffered decisions.
  final int prefetchRefillThreshold;

  late final GraphAwareReviewCoordinator _coordinator;
  final Map<String, Study> _studies;
  final Map<String, Chapter> _chapters;
  final Map<String, ReviewState> _reviewStates;
  final Map<String, RepertoireDecision> _decisionsById;
  final Map<String, RepertoireDecision> _decisionForNode;
  final Map<String, RepertoireDecision> _decisionsByCanonicalId = {};
  final Map<String, List<RepertoireDecision>> _decisionsByFenKey = {};
  final Map<String, RepertoireNode> _nodesById = {};
  final Map<String, List<RepertoireNode>> _nodesByFenKey = {};
  final Map<String, String> _chapterOfNode = {};
  final Map<String, RepertoireNode> _parentOfNode = {};
  final Map<String, String> _canonicalByFenMove = {};
  final Map<String, int> _nodeCountCache = {};

  final List<RepertoireDecision> _dueQueue = [];
  final List<RepertoireDecision> _unbufferedQueue = [];
  final Set<String> _completedDecisionIds = {};
  ReviewPrompt? _currentPrompt;
  int _completedCount = 0;
  late final int _initialDueCount;

  void _refillPrefetchBuffer() {
    if (prefetchBatchSize == null) {
      _dueQueue.addAll(_unbufferedQueue);
      _unbufferedQueue.clear();
      return;
    }
    while (_dueQueue.length < prefetchBatchSize! && _unbufferedQueue.isNotEmpty) {
      _dueQueue.add(_unbufferedQueue.removeAt(0));
    }
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  ReviewPrompt? get currentPrompt => _currentPrompt;
  int get remainingDueCount =>
      _dueQueue.length + _unbufferedQueue.length + (_currentPrompt != null ? 1 : 0);
  int get completedCount => _completedCount;
  int get initialDueCount => _initialDueCount;
  bool get isComplete => _currentPrompt == null && _dueQueue.isEmpty && _unbufferedQueue.isEmpty;
  Map<String, ReviewState> get reviewStates => Map.unmodifiable(_reviewStates);

  /// Returns the chapter with [chapterId] if present in this session.
  Chapter? getChapter(String chapterId) => _chapters[chapterId];

  // ---------------------------------------------------------------------------
  // Transactional rollback
  // ---------------------------------------------------------------------------

  /// Captures the mutable session state so it can be restored if persisting an
  /// answer fails (QUALITY.md §2 incremental state writes).
  ///
  /// The snapshot is shallow because [ReviewState], [RepertoireDecision] and
  /// [ReviewPrompt] are immutable; only the containers holding them are copied.
  ReviewSessionCheckpoint checkpoint() {
    return ReviewSessionCheckpoint._(
      reviewStates: Map<String, ReviewState>.of(_reviewStates),
      dueQueue: List<RepertoireDecision>.of(_dueQueue),
      unbufferedQueue: List<RepertoireDecision>.of(_unbufferedQueue),
      completedDecisionIds: Set<String>.of(_completedDecisionIds),
      currentPrompt: _currentPrompt,
      completedCount: _completedCount,
      exposureThrottle: _coordinator.snapshotExposureThrottle(),
    );
  }

  /// Restores a [checkpoint] captured by [checkpoint], undoing any in-memory
  /// mutation performed since it was taken.
  ///
  /// Does not restore [_random] state: the scheduler's random selection only
  /// affects future queue ordering, never persisted knowledge state.
  void restoreCheckpoint(ReviewSessionCheckpoint checkpoint) {
    _reviewStates
      ..clear()
      ..addAll(checkpoint.reviewStates);
    _dueQueue
      ..clear()
      ..addAll(checkpoint.dueQueue);
    _unbufferedQueue
      ..clear()
      ..addAll(checkpoint.unbufferedQueue);
    _completedDecisionIds
      ..clear()
      ..addAll(checkpoint.completedDecisionIds);
    _currentPrompt = checkpoint.currentPrompt;
    _completedCount = checkpoint.completedCount;
    _coordinator.restoreExposureThrottle(checkpoint.exposureThrottle);
  }

  // ---------------------------------------------------------------------------
  // Session Actions
  // ---------------------------------------------------------------------------

  /// Submit a user move to validate against the expected repertoire continuation.
  ReviewStepResult submitMove({required String from, required String to, String? promotion}) {
    final prompt = _currentPrompt;
    if (prompt == null) {
      throw StateError('Cannot submit move: review session has no active prompt');
    }

    final decision = prompt.decision;
    final prevState =
        _reviewStates[decision.canonicalId] ??
        _reviewStates[decision.id] ??
        ReviewState.initial(decisionId: decision.canonicalId);

    // Validate move against expected repertoire moves (Invariant §2.1),
    // else the transposed line's incoming move (INV-065).
    final movePlayed = RepertoireMove(from: from, to: to, promotion: promotion);
    final resolved = _resolvePlayedMove(prompt, movePlayed);
    final expectedMatch = resolved?.expected;
    final transposedStart = resolved?.start;

    final now = clock.now();

    if (expectedMatch != null) {
      _completedDecisionIds.add(decision.canonicalId);
      // -----------------------------------------------------------------------
      // CORRECT MOVE
      // -----------------------------------------------------------------------
      ReviewState nextState;
      ReviewEvent? event;

      if (mode == ReviewMode.practice) {
        nextState = prevState;
        event = null;
      } else {
        final graphNode = GraphNode(
          decisionId: decision.canonicalId,
          parentId: null,
          fen4: prompt.fenKey,
          expectedMoveUci: expectedMatch.uci,
          hasCanonicalIdentity: decision.canonicalStateId != null,
        );
        final graphResult = _coordinator.recordActiveReview(
          node: graphNode,
          result: ReviewResult.correct,
          now: now,
        );
        nextState = graphResult.primaryState;
        _reviewStates[decision.canonicalId] = nextState;
        _reviewStates[decision.id] = nextState;

        event = ReviewEvent(
          decisionId: decision.canonicalId,
          when: now,
          result: ReviewResult.correct,
          oldState: prevState,
          newState: nextState,
        );
      }

      _completedCount++;

      _logger.info(
        'Move correct: ${expectedMatch.san ?? expectedMatch.uci} for decision ${decision.canonicalId} '
        '(reps: ${nextState.repetitionCount}, stability: ${nextState.stability.toStringAsFixed(2)})',
      );

      return _continueWithCorrectMove(
        prompt: prompt,
        expectedMatch: expectedMatch,
        updatedState: nextState,
        event: event,
        startNode: transposedStart,
      );
    } else {
      // -----------------------------------------------------------------------
      // INCORRECT MOVE
      // -----------------------------------------------------------------------
      final movePlayed = RepertoireMove(from: from, to: to, promotion: promotion);

      ReviewState nextState;
      ReviewEvent? event;
      List<ReviewState> sideEffects = const [];

      if (mode == ReviewMode.practice) {
        nextState = prevState;
        event = null;
      } else {
        final graphNode = GraphNode(
          decisionId: decision.canonicalId,
          parentId: null,
          fen4: prompt.fenKey,
          expectedMoveUci: prompt.expectedMoves.first.uci,
          hasCanonicalIdentity: decision.canonicalStateId != null,
        );
        final siblings = _findSiblingGraphNodes(decision);
        final graphResult = _coordinator.recordActiveReview(
          node: graphNode,
          result: ReviewResult.incorrect,
          now: now,
          playedMoveUci: movePlayed.uci,
          siblings: siblings,
        );
        nextState = graphResult.primaryState;
        _reviewStates[decision.canonicalId] = nextState;
        _reviewStates[decision.id] = nextState;
        sideEffects = graphResult.sideEffectStates;

        event = ReviewEvent(
          decisionId: decision.canonicalId,
          when: now,
          result: ReviewResult.incorrect,
          oldState: prevState,
          newState: nextState,
        );
      }

      _logger.warning(
        'Lapse on decision ${decision.canonicalId}: played ${movePlayed.uci}, '
        'expected: ${prompt.expectedMoves.map((m) => m.san ?? m.uci).join(', ')} '
        '(lapses: ${nextState.lapseCount}, stability: ${nextState.stability.toStringAsFixed(2)})',
      );
      if (sideEffects.isNotEmpty) {
        _logger.fine('Lapse contagion/coupling updated ${sideEffects.length} associated states');
      }

      // Re-queue the failed decision at the end of the session queue
      // so the user can re-test it before completing the session
      _dueQueue.removeWhere((d) => d.id == decision.id);
      _unbufferedQueue.removeWhere((d) => d.id == decision.id);
      if (_unbufferedQueue.isNotEmpty) {
        _unbufferedQueue.add(decision);
      } else {
        _dueQueue.add(decision);
      }

      return ReviewStepResult(
        isCorrect: false,
        movePlayed: movePlayed,
        expectedMoves: prompt.expectedMoves,
        updatedState: nextState,
        event: event,
        autoPlayedMoves: const [],
        nextPrompt: _currentPrompt, // keeps prompt until user continues or retries
        sessionComplete: false,
        sideEffectStates: sideEffects,
      );
    }
  }

  /// Retry a move on the current prompt after an incorrect answer.
  ///
  /// If the retry is correct, advances along the repertoire line without
  /// overwriting the initial lapse recorded in SRS.
  ReviewStepResult retryMove({required String from, required String to, String? promotion}) {
    final prompt = _currentPrompt;
    if (prompt == null) {
      throw StateError('Cannot retry move: review session has no active prompt');
    }

    final movePlayed = RepertoireMove(from: from, to: to, promotion: promotion);
    final resolved = _resolvePlayedMove(prompt, movePlayed);
    final expectedMatch = resolved?.expected;
    final transposedStart = resolved?.start;

    final currentState =
        _reviewStates[prompt.decision.canonicalId] ??
        _reviewStates[prompt.decision.id] ??
        ReviewState.initial(decisionId: prompt.decision.id);

    if (expectedMatch != null) {
      // The position counts toward the day's reviews whether it was answered right first time or
      // only after a lapse. Counting it here is what stops a run of retries from exceeding the
      // daily quota.
      _completedDecisionIds.add(prompt.decision.canonicalId);
      return _continueWithCorrectMove(
        prompt: prompt,
        expectedMatch: expectedMatch,
        updatedState: currentState,
        event: null,
        startNode: transposedStart,
      );
    } else {
      final movePlayed = RepertoireMove(from: from, to: to, promotion: promotion);
      return ReviewStepResult(
        isCorrect: false,
        movePlayed: movePlayed,
        expectedMoves: prompt.expectedMoves,
        updatedState: currentState,
        event: null,
        autoPlayedMoves: const [],
        nextPrompt: _currentPrompt,
        sessionComplete: false,
      );
    }
  }

  ReviewStepResult _continueWithCorrectMove({
    required ReviewPrompt prompt,
    required RepertoireMove expectedMatch,
    required ReviewState updatedState,
    required ReviewEvent? event,
    RepertoireNode? startNode,
  }) {
    final now = clock.now();
    final autoPlayed = <AutoPlayedMove>[];
    final sideEffects = <ReviewState>[];
    // A transposed acceptance traverses from the reached line instead.
    var activeNode = startNode ?? _findChildForMove(prompt.currentNode, expectedMatch);

    while (activeNode != null) {
      if (activeNode.children.isEmpty) {
        activeNode = null;
        break;
      }

      // Opponent turn: select response using due-aware & weighted selection (Listudy semantics)
      final opponentChild = _selectOpponentChild(activeNode, now);
      final opponentMove = opponentChild.incomingMove!;
      autoPlayed.add(
        AutoPlayedMove(
          move: opponentMove,
          fenBefore: activeNode.fen,
          fenAfter: opponentChild.fen,
          isUserMove: false,
          comment: opponentChild.comment,
        ),
      );

      // Now at opponentChild, which is user's turn
      final nextDecision = _decisionForNode[opponentChild.id];
      if (nextDecision != null) {
        final decState = _reviewStates[nextDecision.canonicalId] ?? _reviewStates[nextDecision.id];
        final isDue = mode == ReviewMode.practice || decState == null || decState.isDueAt(now);
        final isQuotaExhausted =
            mode == ReviewMode.srs &&
            remainingDailyQuota != null &&
            _completedDecisionIds.length >= remainingDailyQuota!;
        if (isDue && !isQuotaExhausted) {
          // Found next due decision along this branch!
          _dueQueue.removeWhere(
            (d) => d.id == nextDecision.id || d.canonicalId == nextDecision.canonicalId,
          );
          _unbufferedQueue.removeWhere(
            (d) => d.id == nextDecision.id || d.canonicalId == nextDecision.canonicalId,
          );
          _currentPrompt = _buildPrompt(decision: nextDecision, node: opponentChild);
          return ReviewStepResult(
            isCorrect: true,
            movePlayed: expectedMatch,
            expectedMoves: prompt.expectedMoves,
            updatedState: updatedState,
            event: event,
            autoPlayedMoves: autoPlayed,
            nextPrompt: _currentPrompt,
            sessionComplete: false,
            sideEffectStates: sideEffects,
          );
        }
      }

      // User position was not due: auto-play learned user continuation
      if (opponentChild.children.isNotEmpty) {
        final userChild = opponentChild.children.first;
        final userMove = userChild.incomingMove!;
        autoPlayed.add(
          AutoPlayedMove(
            move: userMove,
            fenBefore: opponentChild.fen,
            fenAfter: userChild.fen,
            isUserMove: true,
            comment: userChild.comment,
          ),
        );

        // Auto-traversal exposure credit for nextDecision (Invariant §2.4, Architecture §B.2)
        if (mode != ReviewMode.practice && nextDecision != null) {
          final expNode = GraphNode(
            decisionId: nextDecision.canonicalId,
            parentId: prompt.decision.canonicalId,
            fen4: opponentChild.fenKey,
            expectedMoveUci: userMove.uci,
            hasCanonicalIdentity: nextDecision.canonicalStateId != null,
          );
          final exposedState = _coordinator.recordAutoTraversalExposure(node: expNode, now: now);
          if (exposedState != null) {
            _reviewStates[nextDecision.canonicalId] = exposedState;
            _reviewStates[nextDecision.id] = exposedState;
            sideEffects.add(exposedState);
          }
        }

        activeNode = userChild;
      } else {
        activeNode = null;
      }
    }

    // Reached the end of the current line; advance to the next due decision in queue
    _advanceToNextDue();

    return ReviewStepResult(
      isCorrect: true,
      movePlayed: expectedMatch,
      expectedMoves: prompt.expectedMoves,
      updatedState: updatedState,
      event: event,
      autoPlayedMoves: autoPlayed,
      nextPrompt: _currentPrompt,
      sessionComplete: isComplete,
      sideEffectStates: sideEffects,
    );
  }

  /// Advance to the next due item after acknowledging an incorrect answer.
  void continueAfterIncorrect() {
    _advanceToNextDue();
  }

  /// Skip the current prompt, moving it to the back of the queue.
  ReviewPrompt? skip() {
    if (_currentPrompt == null) return null;
    final skippedDecision = _currentPrompt!.decision;
    _logger.info(
      'Skipped prompt for decision ${skippedDecision.canonicalId}; moved to back of queue',
    );
    if (_unbufferedQueue.isNotEmpty) {
      _unbufferedQueue.add(skippedDecision);
    } else {
      _dueQueue.add(skippedDecision);
    }
    _advanceToNextDue();
    return _currentPrompt;
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  void _advanceToNextDue() {
    if (mode == ReviewMode.srs &&
        remainingDailyQuota != null &&
        _completedDecisionIds.length >= remainingDailyQuota!) {
      _logger.info(
        'Daily review quota reached (${_completedDecisionIds.length} / $remainingDailyQuota), concluding review session',
      );
      _dueQueue.clear();
      _unbufferedQueue.clear();
      _currentPrompt = null;
      return;
    }
    if (_dueQueue.length <= prefetchRefillThreshold) {
      _refillPrefetchBuffer();
    }
    if (_dueQueue.isEmpty) {
      _currentPrompt = null;
      _logger.info('ReviewSession queue empty. Completed decisions: $_completedCount');
      return;
    }
    final nextDecision = _dueQueue.removeAt(0);
    final node = _nodesById[nextDecision.nodeId];
    _currentPrompt = _buildPrompt(decision: nextDecision, node: node);
  }

  ReviewPrompt _buildPrompt({required RepertoireDecision decision, RepertoireNode? node}) {
    final chapter = _chapters[decision.chapterId];
    final study = _studies[decision.studyId];

    final fen =
        node?.fen ??
        chapter?.startingFen ??
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final fenKey = node?.fenKey ?? fen;
    final side = sideFromFen(fen);
    final parentNode = node != null ? _parentOfNode[node.id] : null;
    final moveHistory = _moveHistoryForNode(node?.id);

    return ReviewPrompt(
      decision: decision,
      studyId: decision.studyId,
      chapterId: decision.chapterId,
      nodeId: decision.nodeId,
      fen: fen,
      fenKey: fenKey,
      sideToMove: side,
      expectedMoves: decision.expectedMoves,
      currentNode: node,
      comment: node?.comment,
      chapterTitle: chapter?.title,
      studyTitle: study?.title,
      parentFen: parentNode?.fen,
      incomingMove: node?.incomingMove,
      moveHistory: moveHistory,
    );
  }

  List<String> _moveHistoryForNode(String? nodeId) {
    if (nodeId == null) return const [];
    final moves = <String>[];
    var current = _nodesById[nodeId];
    while (current != null) {
      final incoming = current.incomingMove;
      if (incoming != null) {
        moves.add(incoming.san ?? incoming.uci);
      }
      current = _parentOfNode[current.id];
    }
    return moves.reversed.toList();
  }

  RepertoireNode? _findChildForMove(RepertoireNode? node, RepertoireMove move) {
    if (node == null) return null;
    return node.childForMove(move);
  }

  void _indexNodes(RepertoireNode node, String chapterId, [RepertoireNode? parent]) {
    _nodesById[node.id] = node;
    _chapterOfNode[node.id] = chapterId;
    _nodesByFenKey.putIfAbsent(node.fenKey, () => []).add(node);
    if (parent != null) {
      _parentOfNode[node.id] = parent;
    }
    for (final child in node.children) {
      _indexNodes(child, chapterId, node);
    }
  }

  /// Resolves the played move: the expected match, else the transposed
  /// line's incoming move when the scope covers it (else null).
  ({RepertoireMove expected, RepertoireNode? start})? _resolvePlayedMove(
    ReviewPrompt prompt,
    RepertoireMove movePlayed,
  ) {
    final direct = prompt.expectedMoves.where((exp) => exp.matches(movePlayed)).firstOrNull;
    if (direct != null) return (expected: direct, start: null);
    if (transposeScope == TransposeScope.off) return null;
    final target = _findTransposedNode(prompt, movePlayed);
    final incoming = target?.incomingMove;
    if (incoming == null || !incoming.matches(movePlayed)) return null;
    return (expected: incoming, start: target);
  }

  /// Transposition acceptance (P-TRANSPOSE, INV-065): returns the in-scope
  /// node at the position the played move reaches, or null. Illegal moves,
  /// out-of-scope targets, and targets without their own repertoire move
  /// fail closed, preserving ordinary incorrect handling exactly.
  /// Within-study scope additionally requires the target's study.
  RepertoireNode? _findTransposedNode(ReviewPrompt prompt, RepertoireMove movePlayed) {
    if (transposeScope == TransposeScope.off) return null;
    // 4-field FEN identity (QUALITY.md §2.3), recomputed: domain owns no FEN helpers.
    Position position;
    try {
      position = Chess.fromSetup(Setup.parseFen(prompt.fen));
    } catch (_) {
      return null;
    }
    const promotions = {'q': Role.queen, 'r': Role.rook, 'b': Role.bishop, 'n': Role.knight};
    final promotion = promotions[movePlayed.promotion ?? ''];
    if (movePlayed.promotion != null && promotion == null) return null;
    late final Position next;
    try {
      next = position.play(
        NormalMove(
          from: Square.fromName(movePlayed.from),
          to: Square.fromName(movePlayed.to),
          promotion: promotion,
        ),
      );
    } catch (_) {
      return null; // illegal here: ordinary incorrect, unchanged behavior
    }
    final parts = next.fen.split(' ');
    if (parts.length < 4) return null;
    final key = '${parts[0]} ${parts[1]} ${parts[2]} ${parts[3]}';
    for (final node in _nodesByFenKey[key] ?? const <RepertoireNode>[]) {
      final incoming = node.incomingMove;
      if (incoming == null || !incoming.matches(movePlayed)) continue;
      final chapter = _chapters[_chapterOfNode[node.id]];
      if (chapter == null ||
          !scope.matches(
            studyId: chapter.studyId,
            chapterId: chapter.id,
            openingFamily: chapter.opening,
            side: chapter.orientation,
          ) ||
          (transposeScope == TransposeScope.withinStudy && chapter.studyId != prompt.studyId)) {
        continue;
      }
      return node;
    }
    return null;
  }

  /// Parses the active side to move from [fen] using dartchess [Setup.parseFen].
  ///
  /// Falls back to [Side.white] if the FEN cannot be parsed.
  static Side sideFromFen(String fen) {
    try {
      final pos = Setup.parseFen(fen.trim());
      return pos.turn;
    } catch (_) {
      return Side.white;
    }
  }

  /// Selects the opponent response among multiple children.
  ///
  /// Uses Listudy-inspired due-aware selection (docs/review.md §Opponent Variation Selection):
  /// 1. Prioritizes opponent branches that lead to moves currently due for review.
  /// 2. If multiple branches have due moves, selects among them using weighted
  ///    randomness proportional to due move density.
  /// 3. In practice mode or if no branch has due moves, selects among all branches
  ///    using anti-repetition weighted randomness proportional to subtree size.
  RepertoireNode _selectOpponentChild(RepertoireNode node, DateTime now) {
    if (node.children.length == 1) {
      return node.children.first;
    }

    final dueCounts = <RepertoireNode, int>{};
    for (final child in node.children) {
      dueCounts[child] = _countDueDecisionsInSubtree(child, now);
    }

    final dueChildren = node.children.where((c) => (dueCounts[c] ?? 0) > 0).toList();
    if (dueChildren.isNotEmpty) {
      return _selectWeighted(dueChildren, dueCounts);
    }

    // Fallback: weight by total subtree size so larger variations get proportionate practice
    final subtreeSizes = <RepertoireNode, int>{};
    for (final child in node.children) {
      subtreeSizes[child] = _nodeCountCache.putIfAbsent(
        child.id,
        () => _countNodesInSubtree(child),
      );
    }
    return _selectWeighted(node.children, subtreeSizes);
  }

  int _countDueDecisionsInSubtree(RepertoireNode node, DateTime now) {
    var count = 0;
    final decision = _decisionForNode[node.id];
    if (decision != null) {
      final state = _reviewStates[decision.canonicalId] ?? _reviewStates[decision.id];
      final isDue = mode == ReviewMode.practice || state == null || state.isDueAt(now);
      if (isDue) {
        count++;
      }
    }
    for (final child in node.children) {
      count += _countDueDecisionsInSubtree(child, now);
    }
    return count;
  }

  int _countNodesInSubtree(RepertoireNode node) {
    var count = 1;
    for (final child in node.children) {
      count += _countNodesInSubtree(child);
    }
    return count;
  }

  RepertoireNode _selectWeighted(
    List<RepertoireNode> candidates,
    Map<RepertoireNode, int> weights,
  ) {
    if (candidates.length == 1) return candidates.first;

    final totalWeight = candidates.fold<int>(0, (sum, c) => sum + (weights[c] ?? 1));
    if (totalWeight <= 0) {
      return candidates[_random.nextInt(candidates.length)];
    }

    var roll = _random.nextInt(totalWeight);
    for (final candidate in candidates) {
      final weight = weights[candidate] ?? 1;
      if (roll < weight) {
        return candidate;
      }
      roll -= weight;
    }
    return candidates.first;
  }

  List<String> _childDecisionIdsOf(String decisionId) {
    final decision = _decisionsByCanonicalId[decisionId] ?? _decisionsById[decisionId];
    if (decision == null) return const [];
    final node = _nodesById[decision.nodeId];
    if (node == null) return const [];

    final childDecisionIds = <String>{};
    for (final exp in decision.expectedMoves) {
      final userChild = node.childForMove(exp);
      if (userChild == null) continue;
      for (final oppChild in userChild.children) {
        final childDec = _decisionForNode[oppChild.id];
        if (childDec != null) {
          childDecisionIds.add(childDec.canonicalId);
        }
      }
    }
    return childDecisionIds.toList(growable: false);
  }

  List<GraphNode> _findSiblingGraphNodes(RepertoireDecision decision) {
    final node = _nodesById[decision.nodeId];
    if (node == null) return const [];

    final candidates = _decisionsByFenKey[node.fenKey];
    if (candidates == null || candidates.isEmpty) return const [];

    final siblings = <GraphNode>[];
    for (final other in candidates) {
      if (other.id == decision.id || other.canonicalId == decision.canonicalId) continue;
      for (final m in other.expectedMoves) {
        siblings.add(
          GraphNode(
            decisionId: other.canonicalId,
            parentId: null,
            fen4: node.fenKey,
            expectedMoveUci: m.uci,
            hasCanonicalIdentity: other.canonicalStateId != null,
          ),
        );
      }
    }
    return siblings;
  }
}

class _SessionReviewStateRepository implements ReviewStateRepository {
  _SessionReviewStateRepository(this._session);
  final ReviewSession _session;

  @override
  ReviewState? get(String decisionId) {
    final decision =
        _session._decisionsById[decisionId] ?? _session._decisionsByCanonicalId[decisionId];
    if (decision != null) {
      return _session._reviewStates[decision.canonicalId] ?? _session._reviewStates[decision.id];
    }
    return _session._reviewStates[decisionId];
  }

  @override
  void put(String decisionId, ReviewState state) {
    _session._reviewStates[decisionId] = state;
    final decision =
        _session._decisionsById[decisionId] ?? _session._decisionsByCanonicalId[decisionId];
    if (decision != null) {
      _session._reviewStates[decision.canonicalId] = state;
      _session._reviewStates[decision.id] = state;
    }
  }

  @override
  List<String> childrenOf(String decisionId) => _session._childDecisionIdsOf(decisionId);

  @override
  String? canonicalIdFor(String fen4, String expectedMoveUci) =>
      _session._canonicalByFenMove['$fen4|$expectedMoveUci'];
}

/// An opaque snapshot of the mutable state of a [ReviewSession].
///
/// Produced by [ReviewSession.checkpoint] and consumed by
/// [ReviewSession.restoreCheckpoint] to undo an in-memory answer when its
/// persistence step fails.
class ReviewSessionCheckpoint {
  ReviewSessionCheckpoint._({
    required this.reviewStates,
    required this.dueQueue,
    required this.unbufferedQueue,
    required this.completedDecisionIds,
    required this.currentPrompt,
    required this.completedCount,
    required this.exposureThrottle,
  });

  final Map<String, ReviewState> reviewStates;
  final List<RepertoireDecision> dueQueue;
  final List<RepertoireDecision> unbufferedQueue;
  final Set<String> completedDecisionIds;
  final ReviewPrompt? currentPrompt;
  final int completedCount;
  final Map<String, DateTime> exposureThrottle;
}
