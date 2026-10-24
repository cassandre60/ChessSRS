// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Review session lifecycle and card queue state.
library;

import 'dart:async';
import 'dart:math';

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/domain/graph_aware_review_coordinator.dart';
import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/review/due_status.dart';
import 'package:chess_srs/src/domain/review/review_continuity.dart';
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
/// One copy of the number the engine, service, and session used to carry
/// independently (three `25`s that had to be changed together to mean anything).
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
    this.continuity = ReviewContinuity.dueOnly,
    this.transposeScope = TransposeScope.inScope,
    this.scheduler = const SimpleScheduler(),
    this.clock = const SystemClock(),
    this.prefetchBatchSize = kDefaultPrefetchBatchSize,
    this.prefetchRefillThreshold = kDefaultPrefetchRefillThreshold,
    this.remainingDailyQuota,
    this.remainingNewQuota,
    this.dynamicRepertoireMode = false,
    this.unlockedDecisionIds = const {},
    GraphAwareReviewCoordinator? coordinator,
    Map<String, DateTime>? initialExposureThrottle,
    Random? random,
  }) : _random = random ?? Random(),
       _studies = {for (final s in studies) s.id: s},
       _chapters = {for (final c in chapters) c.id: c},
       _reviewStates = Map<String, ReviewState>.from(reviewStates),
       _decisionsById = {for (final d in decisions) d.id: d},
       _decisionForNode = {for (final d in decisions) d.nodeId: d},
       _chaptersList = chapters {
    for (final d in decisions) {
      _decisionsByCanonicalId[d.canonicalId] = d;
      _decisionsByChapter.putIfAbsent(d.chapterId, () => []).add(d);
    }

    _coordinator =
        coordinator ??
        GraphAwareReviewCoordinator(
          scheduler: scheduler,
          repo: _SessionReviewStateRepository(this),
          // The session's clock decides which day an instant falls on, so the
          // store's UTC instants and the clock's local time are compared in
          // one frame (INV-028).
          localDayKey: clock.localDayKey,
          initialExposureThrottle: initialExposureThrottle,
        );

    // Build initial due queue
    final now = clock.now();
    final queuedCanonicalIds = <String>{};
    final dueBucket = <RepertoireDecision>[];
    final freshBucket = <RepertoireDecision>[];

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
      // INV-068: a position with no review state has never been presented, so it
      // is fresh rather than due. In dynamic repertoire mode, unreviewed positions
      // are only introduced if explicitly unlocked.
      final status = dueStatusOf(state, now);
      final isLearned = state != null && state.repetitionCount > 0;
      final isUnlocked =
          !dynamicRepertoireMode ||
          isLearned ||
          unlockedDecisionIds.contains(d.id) ||
          unlockedDecisionIds.contains(d.canonicalId);
      final isDue = dynamicRepertoireMode ? (status.isDue && isUnlocked) : status.isDue;
      if (mode == ReviewMode.practice || isDue || (status.isFresh && isUnlocked)) {
        // In multi-study scope, deduplicate shared canonical transpositions
        if (scope.studyId == null && scope.chapterId == null) {
          if (!queuedCanonicalIds.add(d.canonicalId)) {
            continue;
          }
        }
        // Snapshot the queue-time classification (INV-068): the answer-time
        // state cannot tell a lapsed fresh introduction from a lapsed due
        // debt — both hold rows by then — but the optimistic tally patch must
        // retire exactly what the load-time summary counted.
        if (status.isFresh) {
          _freshAtQueueTime.add(d.canonicalId);
          // Scope-wide figure before the daily new-position allowance holds
          // anything back (see [scopeFreshCount]). The allowance and the
          // practice/no-split modes change what is queued, never what the scope
          // contains.
          if (isUnlocked) _scopeFreshCount++;
          if (mode == ReviewMode.srs) {
            freshBucket.add(d);
          } else {
            _unbufferedQueue.add(d);
          }
        } else {
          // In SRS mode reaching this branch means the decision is due (the
          // entry condition above admits nothing else); practice mode queues
          // learned positions before their next due date too, and those are
          // neither due nor fresh.
          if (status.isDue) _scopeDueCount++;
          if (mode == ReviewMode.srs) {
            dueBucket.add(d);
          } else {
            _unbufferedQueue.add(d);
          }
        }
      }
    }

    bool isFresh(RepertoireDecision d) => _freshAtQueueTime.contains(d.canonicalId);

    if (mode == ReviewMode.srs) {
      // Due first, then fresh (INV-068). Two ordered buckets rather than one
      // pool sorted by date: fresh positions carry no date at all, so a date
      // sort floats them to the front and buries the recall work the user is
      // actually answerable for.
      dueBucket.sort((a, b) {
        final stateA = _reviewStates[a.canonicalId] ?? _reviewStates[a.id];
        final stateB = _reviewStates[b.canonicalId] ?? _reviewStates[b.id];
        final dueA = stateA?.nextDueAt;
        final dueB = stateB?.nextDueAt;
        if (dueA == null && dueB == null) return 0;
        if (dueA == null) return -1;
        if (dueB == null) return 1;
        return dueA.compareTo(dueB);
      });

      // Introduce at most `remainingNewQuota` never-presented positions; the
      // rest stay fresh for a later day instead of counting as work.
      var introduced = freshBucket;
      final newAllowance = remainingNewQuota;
      if (newAllowance != null && newAllowance >= 0 && freshBucket.length > newAllowance) {
        introduced = freshBucket.sublist(0, newAllowance);
        _logger.info(
          'Fresh backlog (${freshBucket.length}) exceeds the daily new-position '
          'allowance ($remainingNewQuota); holding back ${freshBucket.length - introduced.length}',
        );
      }
      // The positions this session may introduce. The ones the allowance held
      // back are not in the queue, and a walk that reaches one must not ask it
      // either (INV-068).
      _admittedFreshIds.addAll(introduced.map((d) => d.canonicalId));

      _unbufferedQueue
        ..addAll(dueBucket)
        ..addAll(introduced);

      if (remainingDailyQuota != null &&
          remainingDailyQuota! >= 0 &&
          _unbufferedQueue.length > remainingDailyQuota!) {
        // Not "quota reached". Nothing has been reached here: the due queue is simply longer
        // than what is left of today's allowance, so the session keeps the most urgent N. The
        // old wording printed the *remaining* allowance next to the word "reached", so a user
        // who had reviewed 6 of 100 read "Daily review quota (94) reached" and went looking for
        // 94 reviews. It also never said how long the queue was, so a truncated queue left no
        // trace of what was dropped.
        _logger.info(
          'Due queue (${_unbufferedQueue.length}) is longer than the remaining daily quota '
          '($remainingDailyQuota); keeping the $remainingDailyQuota most urgent',
        );
        _unbufferedQueue.removeRange(remainingDailyQuota!, _unbufferedQueue.length);
      }
    }

    // Index chapters holding decisions in queue (both SRS and practice mode).
    // The decision maps are tree-free since v21 — the row carries its node's
    // fen key — so nothing here decodes a chapter tree. The node maps the
    // prompts need are indexed for the prompted chapter on demand
    // (_ensureChapterNodesIndexed) and for everything else by the background
    // pass kicked below, with every reader still able to finish the job
    // synchronously.
    final neededChapterIds = _unbufferedQueue.map((d) => d.chapterId).toSet();
    for (final chapter in chapters) {
      if (neededChapterIds.contains(chapter.id)) {
        _indexChapterDecisions(chapter);
      }
    }

    // Presentation order (INV-066) applies within each bucket, so a chosen
    // order reshuffles the work without letting fresh material overtake due.
    void reorderWithinBuckets(int Function(RepertoireDecision, RepertoireDecision) compare) {
      final dueCount = _unbufferedQueue.where((d) => !isFresh(d)).length;
      if (dueCount >= _unbufferedQueue.length) {
        _unbufferedQueue.sort(compare);
        return;
      }
      final due = _unbufferedQueue.sublist(0, dueCount)..sort(compare);
      final fresh = _unbufferedQueue.sublist(dueCount)..sort(compare);
      _unbufferedQueue
        ..clear()
        ..addAll(due)
        ..addAll(fresh);
    }

    // By-line order (INV-066): same set, walking study, chapter, tree order.
    if (order == ReviewOrder.byLine) {
      _ensureAllChaptersIndexed();
      final studyIndex = <String, int>{for (var i = 0; i < studies.length; i++) studies[i].id: i};
      var n = 0;
      final nodeOrder = <String, int>{for (final id in _nodesById.keys) id: n++};
      int compareDecisions(RepertoireDecision a, RepertoireDecision b) {
        var c = (studyIndex[a.studyId] ?? 0).compareTo(studyIndex[b.studyId] ?? 0);
        if (c != 0) return c;
        c = (_chapters[a.chapterId]?.sourceOrder ?? 0).compareTo(
          _chapters[b.chapterId]?.sourceOrder ?? 0,
        );
        if (c != 0) return c;
        return (nodeOrder[a.nodeId] ?? 0).compareTo(nodeOrder[b.nodeId] ?? 0);
      }

      if (mode == ReviewMode.srs) {
        reorderWithinBuckets(compareDecisions);
      } else {
        _unbufferedQueue.sort(compareDecisions);
      }
    }

    // Random order: same set, shuffled with the session Random. Each bucket is
    // drawn independently and due is re-seated first, so shuffling reshuffles
    // the work without letting fresh material overtake recall work.
    if (order == ReviewOrder.random) {
      if (mode == ReviewMode.srs) {
        final due = _unbufferedQueue.where((d) => !isFresh(d)).toList()..shuffle(_random);
        final fresh = _unbufferedQueue.where(isFresh).toList()..shuffle(_random);
        _unbufferedQueue
          ..clear()
          ..addAll(due)
          ..addAll(fresh);
      } else {
        _unbufferedQueue.shuffle(_random);
      }
    }

    _initialQueueCount = _unbufferedQueue.length;
    // Practice mode rehearses rather than schedules, so it has no fresh/due
    // distinction to report: everything it queued counts as due.
    _initialDueCount = mode == ReviewMode.practice
        ? _initialQueueCount
        : _unbufferedQueue.where((d) => !isFresh(d)).length;
    _refillPrefetchBuffer();
    _advanceToNextDue();
    unawaited(_indexRemainingNodesInBackground());
    _logger.info(
      'ReviewSession created: mode=$mode, scope=$scope, order=$order, continuity=$continuity, '
      'initialDueCount=$_initialQueueCount, '
      'dueOfThose=$_initialDueCount, remainingQuota=$remainingDailyQuota',
    );
  }

  final ReviewScope scope;
  final ReviewMode mode;

  /// Queued prompts at build time, of which [initialDueCount] are due.
  ///
  /// The two differ because a session may hold fresh introductions as well
  /// (INV-068): `initialQueueCount` is how much work the session will ask for,
  /// `initialDueCount` is how much of it the user actually owes.
  late final int _initialDueCount;
  late final int _initialQueueCount;
  int _scopeDueCount = 0;
  int _scopeFreshCount = 0;

  /// Presentation order of the due queue; the due set never depends on this.
  final ReviewOrder order;

  /// In-line continuity (user setting): due-only quizzes just due
  /// positions; full-line plays every line whole, start to end. Mutable so a
  /// settings flip reaches the live session (the queued set never changes).
  ReviewContinuity continuity;

  /// Off-line-but-book moves accepted (INV-065); off keeps strict grading.
  final TransposeScope transposeScope;
  final bool dynamicRepertoireMode;
  final Set<String> unlockedDecisionIds;
  final Scheduler scheduler;
  final Clock clock;
  final Random _random;

  /// Optional daily quota limit for SRS reviews. When met, review completes for the day.
  final int? remainingDailyQuota;

  /// How many never-presented positions this session may introduce (INV-068).
  ///
  /// Null means no introduction cap, which only practice mode and the domain
  /// default use; SRS sessions pass the day's remaining allowance so a bulk
  /// import cannot dump its whole backlog on the user at once.
  final int? remainingNewQuota;

  /// Maximum batch size of due decisions to buffer in the active queue at once.
  /// Null disables batching and buffers the entire queue.
  final int? prefetchBatchSize;

  /// Threshold at which the active prefetch buffer refills from unbuffered decisions.
  final int prefetchRefillThreshold;

  late final GraphAwareReviewCoordinator _coordinator;
  final Map<String, Study> _studies;
  final Map<String, Chapter> _chapters;
  final List<Chapter> _chaptersList;
  final Map<String, List<RepertoireDecision>> _decisionsByChapter = {};

  /// Chapters whose decision maps (`_decisionsByFenKey`, `_canonicalByFenMove`)
  /// are built. Tree-free since v21 — the decision row carries its node's fen
  /// key — so this is done at construction for every queued chapter.
  final Set<String> _decisionIndexedChapterIds = {};

  /// Chapters whose node maps (`_nodesById`, `_parentOfNode`, `_nodesByFenKey`,
  /// `_chapterOfNode`) are built. Requires the chapter's decoded tree, so this
  /// happens on demand for the prompted chapter and in the background for the
  /// rest; every reader can also finish it synchronously.
  final Set<String> _nodeIndexedChapterIds = {};

  /// True once every chapter's node maps exist. Only set after the last
  /// chapter is indexed — a reader observing it false simply completes the
  /// work itself, so it must never promise more than is built.
  bool _allChaptersIndexed = false;
  final Map<String, ReviewState> _reviewStates;
  final Map<String, RepertoireDecision> _decisionsById;
  final Map<String, RepertoireDecision> _decisionForNode;
  final Map<String, RepertoireDecision> _decisionsByCanonicalId = {};
  final Map<String, List<RepertoireDecision>> _decisionsByFenKey = {};
  final Map<String, RepertoireNode> _nodesById = {};
  final Map<String, List<RepertoireNode>> _nodesByFenKey = {};
  final Map<String, String> _chapterOfNode = {};
  final Map<String, RepertoireNode> _parentOfNode = {};

  /// Each node-indexed chapter's position in [_chaptersList], and each indexed
  /// node's depth-first pre-order rank within its chapter. The transposition
  /// lookup sorts candidates by (chapter position, rank), which is exactly the
  /// order eager indexing always produced, whatever schedule built the maps.
  final Map<String, int> _chapterListIndex = {};
  final Map<String, int> _nodeDfsRank = {};
  int _nodeDfsRankCounter = 0;
  final Map<String, String> _canonicalByFenMove = {};
  final Map<String, int> _nodeCountCache = {};

  /// Builds the decision maps for [chapter] from its rows. The position a
  /// decision sits on comes from the row's own fen key; a row the v21 backfill
  /// could not fill falls back to the decoded node — so a chapter holding any
  /// unfilled row decodes its tree first, exactly as every row did before the
  /// column existed. A decision with neither (its node is gone from its tree)
  /// indexes nothing — also as before v21.
  void _indexChapterDecisions(Chapter chapter) {
    if (!_decisionIndexedChapterIds.add(chapter.id)) return;
    final decisions = _decisionsByChapter[chapter.id];
    if (decisions == null) return;
    if (decisions.any((d) => d.fenKey == null)) {
      _ensureChapterNodesIndexed(chapter.id);
    }
    for (final d in decisions) {
      final fenKey = d.fenKey ?? _nodesById[d.nodeId]?.fenKey;
      if (fenKey == null) continue;
      _decisionsByFenKey.putIfAbsent(fenKey, () => []).add(d);
      for (final m in d.expectedMoves) {
        _canonicalByFenMove['$fenKey|${m.uci}'] = d.canonicalId;
      }
    }
  }

  /// Builds the node maps for [chapter] by decoding its tree. This is the
  /// expensive half of the old `_indexChapter` — the part v21 exists to defer.
  void _indexChapterNodes(Chapter chapter) {
    if (!_nodeIndexedChapterIds.add(chapter.id)) return;
    final root = chapter.root;
    if (root != null) {
      _chapterListIndex[chapter.id] = _chaptersList.indexOf(chapter);
      _nodeDfsRankCounter = 0;
      _indexNodes(root, chapter.id);
    }
  }

  /// Indexes the node maps for one chapter if they are missing. Call before
  /// any read that needs a specific chapter's nodes.
  void _ensureChapterNodesIndexed(String chapterId) {
    if (_allChaptersIndexed || _nodeIndexedChapterIds.contains(chapterId)) return;
    final chapter = _chapters[chapterId];
    if (chapter != null) _indexChapterNodes(chapter);
  }

  void _ensureAllChaptersIndexed() {
    if (_allChaptersIndexed) return;
    for (final c in _chaptersList) {
      // Decision maps are tree-free, but cross-chapter readers (sibling
      // coupling, canonical resolution) need every chapter in them, exactly
      // as eager indexing provided.
      _indexChapterDecisions(c);
      if (!_nodeIndexedChapterIds.contains(c.id)) {
        _indexChapterNodes(c);
      }
    }
    _allChaptersIndexed = true;
  }

  /// Decodes the remaining chapter trees between event-loop turns so the cost
  /// overlaps the user's think-time instead of the first frame. Purely an
  /// optimization: every reader completes missing node maps synchronously, so
  /// correctness never depends on how far this has got. The loop keeps
  /// `_chaptersList` order, which preserves the candidate order the
  /// transposition lookup documents.
  Future<void> _indexRemainingNodesInBackground() async {
    // Let the first frame paint before any decoding runs.
    await Future<void>.delayed(Duration.zero);
    for (final c in _chaptersList) {
      if (_allChaptersIndexed) return;
      if (_nodeIndexedChapterIds.contains(c.id)) continue;
      _indexChapterNodes(c);
      await Future<void>.delayed(Duration.zero);
    }
    _allChaptersIndexed = true;
  }

  final List<RepertoireDecision> _dueQueue = [];
  final List<RepertoireDecision> _unbufferedQueue = [];
  final Set<String> _completedDecisionIds = {};

  /// Decisions already graded as a lapse this session. A failed decision is re-queued for a
  /// re-test; when that re-test succeeds it is a *corrected false-start*, which Decision D015
  /// grades as a single Again rather than a lapse plus an independent success seconds later.
  final Set<String> _lapsedThisSession = {};

  /// Canonical ids of lapsed decisions still waiting for their re-test. The daily quota caps
  /// *new* work: re-tests cost nothing (the set already holds them, INV-031) and the lapse
  /// handler promises them, so the quota cut keeps these and drops the rest (review-3 C2).
  final Set<String> _pendingRetest = {};
  ReviewPrompt? _currentPrompt;

  /// Targets whose line-start walk missed them; next pop walks their ancestry.
  final Set<String> _lineStartAttempted = {};

  /// Guided node-id path, start to target, for a dedicated sideline walk.
  /// Branch choices follow it; empty means PGN tree order.
  List<String> _guidedNodeIds = const [];

  /// Canonical ids queued as never-presented introductions (INV-068).
  ///
  /// Snapshot at queue-build time and never mutated afterwards, so it needs no
  /// checkpoint slot: answering, lapsing and re-testing all resolve against the
  /// classification the load-time summary reported.
  final Set<String> _freshAtQueueTime = {};

  /// Whether [canonicalId] entered this session as a fresh introduction.
  bool wasFreshAtQueueTime(String canonicalId) => _freshAtQueueTime.contains(canonicalId);

  /// Canonical ids the new-position allowance admitted into this session (INV-068).
  ///
  /// The allowance decides how many never-presented positions the session may
  /// introduce. The ones it held back are not queued, and a walk that reaches
  /// one must not ask it either — otherwise the cap is bypassed by answering
  /// the position above it.
  final Set<String> _admittedFreshIds = {};

  /// Whether the session still holds due work (INV-068).
  ///
  /// Fresh introductions come after the due work, so a walk that reaches a
  /// fresh position while due work is still queued stops there instead of
  /// asking it. Only positions the queue holds count: a position already
  /// answered, or one the daily quota set aside, is not work in front of the
  /// user.
  bool _hasQueuedDueWork(DateTime now) {
    for (final d in _dueQueue) {
      final state = _reviewStates[d.canonicalId] ?? _reviewStates[d.id];
      if (dueStatusOf(state, now).isDue) return true;
    }
    for (final d in _unbufferedQueue) {
      final state = _reviewStates[d.canonicalId] ?? _reviewStates[d.id];
      if (dueStatusOf(state, now).isDue) return true;
    }
    return false;
  }

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

  // Getters
  ReviewPrompt? get currentPrompt => _currentPrompt;
  int get remainingDueCount =>
      _dueQueue.length + _unbufferedQueue.length + (_currentPrompt != null ? 1 : 0);

  /// Positions completed this session. Derived from the quota set rather than counted by hand:
  /// a re-test of an already-completed lapse must not count twice, and a retry-driven session
  /// must not report zero (review-3 C1). One source of truth, by construction.
  int get completedCount => _completedDecisionIds.length;

  /// Work this session will ask for: due positions plus fresh introductions.
  ///
  /// Named "due count" for the callers that have always read it as queue size
  /// (prefetch, session-size tests); see [initialDueCount] for the subset the
  /// user actually owes. Practice mode reports the whole queue, having no
  /// fresh/due distinction to make.
  int get initialQueueCount => _initialQueueCount;

  /// Of [initialQueueCount], how many are genuinely due (INV-068). Practice
  /// mode reports the whole queue, having no fresh/due distinction to make.
  int get initialDueCount => _initialDueCount;

  /// Due positions the scope held when this session was built, before the
  /// daily quota trimmed the queue.
  ///
  /// [initialDueCount] answers "how much work did this session get"; this
  /// answers "how much debt does the scope have" — the figure the summary
  /// pass reports. The reuse fast path must reproduce that figure rather than
  /// re-deriving it from a capped queue (#164): the queue is capped by today's
  /// remaining allowance, so after any scope switch it undercounted.
  int get scopeDueCount => _scopeDueCount;

  /// Never-presented positions the scope held when this session was built,
  /// before the daily new-position allowance held any back. See
  /// [scopeDueCount] for why the reuse fast path needs the untrimmed figure.
  int get scopeFreshCount => _scopeFreshCount;

  bool get isComplete => _currentPrompt == null && _dueQueue.isEmpty && _unbufferedQueue.isEmpty;
  Map<String, ReviewState> get reviewStates => Map.unmodifiable(_reviewStates);

  /// Last auto-traversal exposure grant per canonical id (Architecture §B.2), exposed so the caller
  /// can persist the daily cap and reseed the next session. See review-2 C1.
  Map<String, DateTime> get exposureThrottle => _coordinator.snapshotExposureThrottle();

  /// Returns the chapter with [chapterId] if present in this session.
  Chapter? getChapter(String chapterId) => _chapters[chapterId];

  // Transactional rollback
  ReviewSessionCheckpoint checkpoint() {
    return ReviewSessionCheckpoint._(
      reviewStates: Map<String, ReviewState>.of(_reviewStates),
      dueQueue: List<RepertoireDecision>.of(_dueQueue),
      unbufferedQueue: List<RepertoireDecision>.of(_unbufferedQueue),
      completedDecisionIds: Set<String>.of(_completedDecisionIds),
      lapsedDecisionIds: Set<String>.of(_lapsedThisSession),
      pendingRetestIds: Set<String>.of(_pendingRetest),
      currentPrompt: _currentPrompt,
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
    _lapsedThisSession
      ..clear()
      ..addAll(checkpoint.lapsedDecisionIds);
    _pendingRetest
      ..clear()
      ..addAll(checkpoint.pendingRetestIds);
    _currentPrompt = checkpoint.currentPrompt;
    _coordinator.restoreExposureThrottle(checkpoint.exposureThrottle);
  }

  // Session Actions
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

    // Full-line prefix rehearsal: re-answering a position already answered
    // this session re-walks it with practice grading (no double SRS write).
    final isPrefixRehearsal =
        continuity == ReviewContinuity.fullLine &&
        mode == ReviewMode.srs &&
        _completedDecisionIds.contains(decision.canonicalId);

    if (expectedMatch != null) {
      _completedDecisionIds.add(decision.canonicalId);
      // -----------------------------------------------------------------------
      // CORRECT MOVE
      // -----------------------------------------------------------------------
      // Decision D015: a corrected false-start is graded once, as the lapse it already was. Grading
      // the re-test as a success too would tick repetitionCount up and push the due date out.
      // The re-test landing also clears the lapse's pending marker (review-3 C2).
      final isCorrectedFalseStart = _lapsedThisSession.contains(decision.canonicalId);
      if (isCorrectedFalseStart) _pendingRetest.remove(decision.canonicalId);

      ReviewState nextState;
      ReviewEvent? event;

      if (mode == ReviewMode.practice || isCorrectedFalseStart || isPrefixRehearsal) {
        nextState = prevState;
        event = null;
      } else {
        final graphNode = GraphNode(
          decisionId: decision.canonicalId,
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

      _logger.info(
        'Move correct: ${expectedMatch.san ?? expectedMatch.uci} for decision ${decision.canonicalId} '
        '${transposedStart != null ? '(transposed line) ' : ''}'
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
      // [movePlayed] is built once above and shared by both branches (review-3 D2).

      ReviewState nextState;
      ReviewEvent? event;
      List<ReviewState> sideEffects = const [];

      if (mode == ReviewMode.practice || isPrefixRehearsal) {
        nextState = prevState;
        event = null;
      } else {
        // No repertoire move recorded here (malformed or hand-edited data: the importer only
        // derives decisions from nodes with children). There is nothing to match, so grade
        // incorrect through the scheduler directly — the coordinator needs an expected move
        // for its graph effects — and never index into the empty list (review-3 C4, INV-020).
        final firstExpected = prompt.expectedMoves.firstOrNull;
        if (firstExpected == null) {
          _logger.warning(
            'No expected moves for decision ${decision.canonicalId}; grading incorrect',
          );
          nextState = scheduler.schedule(
            previous: prevState,
            result: ReviewResult.incorrect,
            now: now,
          );
          _reviewStates[decision.canonicalId] = nextState;
          _reviewStates[decision.id] = nextState;
        } else {
          final graphNode = GraphNode(
            decisionId: decision.canonicalId,
            fen4: prompt.fenKey,
            expectedMoveUci: firstExpected.uci,
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
        }

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

      // Decision D015: remember this was graded, so a later re-test is not graded twice.
      // It also stays pending until that re-test lands, so the quota cut cannot drop it.
      _lapsedThisSession.add(decision.canonicalId);
      _pendingRetest.add(decision.canonicalId);

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
        // Same scheduling identity as submitMove's fallback: the canonical id, so transposed
        // occurrences share one memory (INV-016). The occurrence id here disagreed (review-3 C5).
        ReviewState.initial(decisionId: prompt.decision.canonicalId);

    if (expectedMatch != null) {
      // The position counts toward the day's reviews whether it was answered right first time or
      // only after a lapse. Counting it here is what stops a run of retries from exceeding the
      // daily quota. A correct retry is also the re-test landing, so it clears the pending
      // marker set by the lapse (review-3 C2).
      _completedDecisionIds.add(prompt.decision.canonicalId);
      _pendingRetest.remove(prompt.decision.canonicalId);
      return _continueWithCorrectMove(
        prompt: prompt,
        expectedMatch: expectedMatch,
        updatedState: currentState,
        event: null,
        startNode: transposedStart,
      );
    } else {
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
    // Due counts are computed once per node for the whole traversal below.
    // This is sound because nothing in the loop flips due-ness at this `now`:
    // auto-traversal exposure returns already-due states unchanged and only
    // pushes not-due states further into the future, and `mode` is fixed for
    // the session. Without the memo every level re-walks its entire subtree,
    // making one move cost O(depth x subtree) instead of O(tree) (INV-050).
    final dueCountMemo = <String, int>{};
    final autoPlayed = <AutoPlayedMove>[];
    final sideEffects = <ReviewState>[];
    // Whether the session still holds due work (INV-068). Scanned once per
    // walk and reused: the queue does not change while the walk runs, and the
    // scan is O(queue), so re-reading it per step would cost O(steps x queue)
    // on the move path (INV-050).
    bool? hasQueuedDueWorkCached;
    // A transposed acceptance traverses from the reached line instead.
    var activeNode = startNode ?? _findChildForMove(prompt.currentNode, expectedMatch);

    while (activeNode != null) {
      if (activeNode.children.isEmpty) {
        activeNode = null;
        break;
      }

      // Opponent turn: select response using due-aware & weighted selection (Listudy semantics)
      final opponentChild = _selectOpponentChild(activeNode, now, dueCountMemo);
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
        final isDue = _isDecisionDue(nextDecision, decState, now);
        final isLearned = decState != null && decState.repetitionCount > 0;
        final isUnlocked =
            !dynamicRepertoireMode ||
            isLearned ||
            unlockedDecisionIds.contains(nextDecision.id) ||
            unlockedDecisionIds.contains(nextDecision.canonicalId);
        final isQuotaExhausted =
            mode == ReviewMode.srs &&
            remainingDailyQuota != null &&
            _completedDecisionIds.length >= remainingDailyQuota!;
        // Full line quizzes every step in order, even when not yet due. The
        // quota still caps prompted work — but it ends the walk instead of
        // auto-playing the user's own moves past it. In dynamic mode, locked
        // branches end the walk: unchosen moves must never be quizzed.
        if (mode == ReviewMode.srs && dynamicRepertoireMode && !isUnlocked) break;
        if (isQuotaExhausted && continuity == ReviewContinuity.fullLine) break;
        // INV-068: a position that was never presented is fresh, not due. The
        // session introduces fresh positions under the day's new-position
        // allowance, so a walk that reaches one asks it only if the allowance
        // admitted it.
        final isFreshPosition = mode == ReviewMode.srs && dueStatusOf(decState, now).isFresh;
        final freshHeldBack =
            isFreshPosition && !_admittedFreshIds.contains(nextDecision.canonicalId);
        // Fresh also waits for the due work: the session serves recall work
        // before introductions. Two modes are exempt from that ordering, each
        // because the user asked for the material explicitly: dynamic mode
        // (an unlocked line is the user's own request) and full-line
        // continuity (every line is played whole). The allowance cap still
        // applies to both.
        final freshOvertakesDueWork =
            isFreshPosition &&
            !dynamicRepertoireMode &&
            continuity != ReviewContinuity.fullLine &&
            (hasQueuedDueWorkCached ??= _hasQueuedDueWork(now));
        if (freshHeldBack || freshOvertakesDueWork) {
          // The line stops where the user still owes recall work, rather than
          // asking a position the session may not introduce.
          break;
        }
        final shouldPrompt =
            (isDue || continuity == ReviewContinuity.fullLine) && !isQuotaExhausted;
        if (shouldPrompt) {
          // Next decision along this branch.
          _dequeueDecision(nextDecision);
          _currentPrompt = _buildPrompt(decision: nextDecision, node: opponentChild);
          final trail = autoPlayed
              .map((m) => '${m.move.san ?? m.move.uci}${m.isUserMove ? '*' : ''}')
              .join(' ');
          _logger.info('Prompts ${nextDecision.canonicalId} (due=$isDue) after [$trail]');
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

      // User position was not due: auto-play a learned user continuation. With several
      // continuations (PGN variations are first-class siblings, QUALITY.md §2.2), follow the
      // branch holding due material rather than list position, and still credit the first
      // decision below each passed-over alternative — every junction option was traversed
      // past, not just the one followed (review-3 C3, INV-022).
      if (opponentChild.children.isNotEmpty) {
        final userChild = _selectUserContinuation(opponentChild, now, dueCountMemo);
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

        if (mode != ReviewMode.practice) {
          for (final sibling in opponentChild.children) {
            if (identical(sibling, userChild)) continue;
            final siblingDecision = _firstDecisionInSubtree(sibling);
            if (siblingDecision == null) continue;
            final siblingNode = _nodesById[siblingDecision.nodeId];
            final firstExpected = siblingDecision.expectedMoves.firstOrNull;
            if (siblingNode == null || firstExpected == null) continue;
            final sibExposed = _coordinator.recordAutoTraversalExposure(
              node: GraphNode(
                decisionId: siblingDecision.canonicalId,
                fen4: siblingNode.fenKey,
                expectedMoveUci: firstExpected.uci,
                hasCanonicalIdentity: siblingDecision.canonicalStateId != null,
              ),
              now: now,
            );
            if (sibExposed != null) {
              _reviewStates[siblingDecision.canonicalId] = sibExposed;
              _reviewStates[siblingDecision.id] = sibExposed;
              sideEffects.add(sibExposed);
            }
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

  /// Advance after acknowledging an incorrect answer. In full-line mode the
  /// line is not abandoned: review continues below (the failed card is
  /// already requeued), so a lapse never teleports into another line.
  void continueAfterIncorrect() {
    if (continuity == ReviewContinuity.fullLine && _advanceWithinLine()) return;
    _advanceToNextDue();
  }

  /// Prompts the next decision below the current line after a lapse. False
  /// when the line ends here (caller falls back to the queue).
  bool _advanceWithinLine() {
    final prompt = _currentPrompt;
    final repoNode = prompt?.currentNode;
    final correct = prompt?.expectedMoves.firstOrNull;
    if (prompt == null || repoNode == null || correct == null) return false;
    final userChild = repoNode.childForMove(correct);
    if (userChild == null || userChild.children.isEmpty) return false;
    final nextNode = _guidedChild(userChild.children) ?? userChild.children.first;
    final nextDecision = _decisionForNode[nextNode.id];
    if (nextDecision == null) return false;
    _dequeueDecision(nextDecision);
    _currentPrompt = _buildPrompt(decision: nextDecision, node: nextNode);
    _logger.info(
      'Lapse continue at ${nextDecision.canonicalId} (${prompt.decision.canonicalId} requeued)',
    );
    return true;
  }

  /// Pulls [decision] from both queue buffers once it is prompted elsewhere.
  void _dequeueDecision(RepertoireDecision decision) {
    _dueQueue.removeWhere((d) => d.id == decision.id || d.canonicalId == decision.canonicalId);
    _unbufferedQueue.removeWhere(
      (d) => d.id == decision.id || d.canonicalId == decision.canonicalId,
    );
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

  // Internal Helpers
  void _advanceToNextDue() {
    if (mode == ReviewMode.srs &&
        remainingDailyQuota != null &&
        _completedDecisionIds.length >= remainingDailyQuota!) {
      // The quota caps new work, not pending re-tests: they cost nothing (the set already holds
      // them, INV-031) and the lapse handler promised them before the session ends (INV-021).
      // Drop everything else so the day's allowance is honoured, then keep going only while a
      // re-test is still owed; otherwise the session concludes here.
      final droppedNew =
          _dueQueue.where((d) => !_pendingRetest.contains(d.canonicalId)).length +
          _unbufferedQueue.where((d) => !_pendingRetest.contains(d.canonicalId)).length;
      _dueQueue.removeWhere((d) => !_pendingRetest.contains(d.canonicalId));
      _unbufferedQueue.removeWhere((d) => !_pendingRetest.contains(d.canonicalId));
      if (_dueQueue.isEmpty && _unbufferedQueue.isEmpty) {
        _logger.info(
          'Daily review quota reached (${_completedDecisionIds.length} / $remainingDailyQuota), concluding review session',
        );
        _currentPrompt = null;
        return;
      }
      _logger.info(
        'Daily review quota reached (${_completedDecisionIds.length} / $remainingDailyQuota); '
        'set aside $droppedNew new item(s), concluding ${_dueQueue.length + _unbufferedQueue.length} pending re-test(s)',
      );
    }
    if (_dueQueue.length <= prefetchRefillThreshold) {
      _refillPrefetchBuffer();
    }
    if (_dueQueue.isEmpty) {
      _currentPrompt = null;
      _logger.info('ReviewSession queue empty. Completed decisions: $completedCount');
      return;
    }
    final nextDecision = _dueQueue.removeAt(0);
    // The prompt build reads the decision's node and its ancestry; make sure
    // this chapter's node maps exist (usually already done by the background
    // pass, which this call also finishes synchronously when not).
    _ensureChapterNodesIndexed(nextDecision.chapterId);
    if (continuity == ReviewContinuity.fullLine) {
      // Whole lines: open at the line start and walk it. A target whose walk
      // missed it gets a dedicated walk down its own ancestry — never a
      // mid-line drop into another variation.
      final guided = _lineStartAttempted.remove(nextDecision.canonicalId);
      final start = _lineStartFor(nextDecision);
      if (start != null) {
        if (!guided) _lineStartAttempted.add(nextDecision.canonicalId);
        if (!guided) _dueQueue.insert(0, nextDecision);
        _dequeueDecision(start.decision);
        _guidedNodeIds = guided ? start.path : const [];
        _currentPrompt = _buildPrompt(decision: start.decision, node: start.node);
        _logger.info(
          'Line start ${start.decision.canonicalId} for queued ${nextDecision.canonicalId}',
        );
        return;
      }
    }
    final node = _nodesById[nextDecision.nodeId];
    _currentPrompt = _buildPrompt(decision: nextDecision, node: node);
  }

  /// Earliest decision on [target]'s ancestry chain, plus the node-id path
  /// from it down to the target for dedicated walks. Null when the target
  /// itself is the line start. Re-answered prefixes rehearse with practice
  /// grading; in dynamic mode locked-unreviewed ancestors skip.
  ({RepertoireDecision decision, RepertoireNode node, List<String> path})? _lineStartFor(
    RepertoireDecision target,
  ) {
    var cursor = _nodesById[target.nodeId];
    if (cursor == null) return null;
    final chain = <RepertoireNode>[];
    while (cursor != null) {
      chain.add(cursor);
      cursor = _parentOfNode[chain.last.id];
    }
    for (var i = chain.length - 1; i >= 0; i--) {
      final candidate = _decisionForNode[chain[i].id];
      if (candidate == null) continue;
      if (mode == ReviewMode.srs && dynamicRepertoireMode) {
        final state = _reviewStates[candidate.canonicalId] ?? _reviewStates[candidate.id];
        final unlocked =
            unlockedDecisionIds.contains(candidate.id) ||
            unlockedDecisionIds.contains(candidate.canonicalId);
        final learned = state != null && state.repetitionCount > 0;
        if (!unlocked && !learned) continue;
      }
      if (candidate.id == target.id && candidate.canonicalId == target.canonicalId) {
        return null;
      }
      final path = chain.sublist(0, i + 1).reversed.map((n) => n.id).toList();
      return (decision: candidate, node: chain[i], path: path);
    }
    return null;
  }

  /// Next guided child among [children], consuming the guide through it.
  /// Null when none lies on the path (guide cleared, tree order resumes).
  RepertoireNode? _guidedChild(List<RepertoireNode> children) {
    if (_guidedNodeIds.isEmpty) return null;
    for (final child in children) {
      final index = _guidedNodeIds.indexOf(child.id);
      if (index < 0) continue;
      _guidedNodeIds = _guidedNodeIds.sublist(index + 1);
      return child;
    }
    _guidedNodeIds = const [];
    return null;
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
    // Depth-first pre-order rank within the chapter. Together with the
    // chapter's position in _chaptersList this reproduces the candidate order
    // the transposition lookup always had when indexing was eager (see
    // _findTransposedNode), no matter which schedule indexed the chapters.
    _nodeDfsRank[node.id] = _nodeDfsRankCounter++;
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
    if (target == null) return null;
    final incoming = target.incomingMove;
    if (incoming != null && incoming.matches(movePlayed)) {
      return (expected: incoming, start: target);
    }
    // The repertoire reached this position by another move. The move that
    // happened is the one the user played, and it is the one the verdict has
    // to name (INV-065).
    return (expected: movePlayed, start: target);
  }

  /// Transposition acceptance (P-TRANSPOSE, INV-065): returns the in-scope
  /// node at the position the played move reaches, or null. Illegal moves,
  /// out-of-scope targets, and targets without their own repertoire move
  /// fail closed, preserving ordinary incorrect handling exactly.
  /// Within-study scope additionally requires the target's study.
  RepertoireNode? _findTransposedNode(ReviewPrompt prompt, RepertoireMove movePlayed) {
    if (transposeScope == TransposeScope.off) return null;
    _ensureAllChaptersIndexed();
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
    // Candidates in the order eager indexing always produced: chapters in
    // _chaptersList order, depth-first within a chapter. Chapters may now be
    // indexed in any schedule (prompt-time, background), so the sort — not
    // insertion order — is what keeps the choice among equally valid targets
    // identical to the pre-v21 behavior.
    final candidates = [...(_nodesByFenKey[key] ?? const <RepertoireNode>[])]
      ..sort((a, b) {
        final chapterA = _chapterListIndex[_chapterOfNode[a.id]] ?? _chaptersList.length;
        final chapterB = _chapterListIndex[_chapterOfNode[b.id]] ?? _chaptersList.length;
        if (chapterA != chapterB) return chapterA.compareTo(chapterB);
        return (_nodeDfsRank[a.id] ?? 0).compareTo(_nodeDfsRank[b.id] ?? 0);
      });
    RepertoireNode? fallback;
    for (final node in candidates) {
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
      final incoming = node.incomingMove;
      if (incoming != null && incoming.matches(movePlayed)) {
        // The line the user is actually following: the repertoire used the
        // same move to get here.
        return node;
      }
      // The position is in scope, but the repertoire arrived here another way.
      // The position is what INV-065 is about — interchangeable pieces reach
      // the same square set by different moves — so this node is a valid
      // target. Kept as the fallback in case no node matches the arrival.
      fallback ??= node;
    }
    return fallback;
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
  RepertoireNode _selectOpponentChild(
    RepertoireNode node,
    DateTime now,
    Map<String, int> dueCountMemo,
  ) {
    if (node.children.length == 1) {
      return node.children.first;
    }

    // Full line walks tree order (mainline first), never steered; a
    // dedicated sideline walk follows its guide instead.
    if (continuity == ReviewContinuity.fullLine) {
      return _guidedChild(node.children) ?? node.children.first;
    }

    final dueCounts = <RepertoireNode, int>{};
    for (final child in node.children) {
      dueCounts[child] = _countDueDecisionsInSubtree(child, now, dueCountMemo);
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

  /// Selects the user continuation to auto-play when several are recorded.
  ///
  /// Deterministic: the branch whose subtree holds the most due decisions, ties broken by
  /// list order (mainline first), so behaviour is unchanged when nothing is due (review-3 C3).
  RepertoireNode _selectUserContinuation(
    RepertoireNode opponentChild,
    DateTime now,
    Map<String, int> dueCountMemo,
  ) {
    // Full line follows list order; a dedicated sideline walk follows
    // its guide instead. Neither is ever steered toward queued dues.
    if (continuity == ReviewContinuity.fullLine) {
      return _guidedChild(opponentChild.children) ?? opponentChild.children.first;
    }
    var best = opponentChild.children.first;
    var bestDue = -1;
    for (final child in opponentChild.children) {
      final due = _countDueDecisionsInSubtree(child, now, dueCountMemo);
      if (due > bestDue) {
        bestDue = due;
        best = child;
      }
    }
    return best;
  }

  /// First decision in pre-order DFS below [node], or null when the subtree holds none.
  ///
  /// Used to credit the passed-over alternative of a junction: the position the traversal
  /// would have met first had it followed that branch (review-3 C3).
  RepertoireDecision? _firstDecisionInSubtree(RepertoireNode node) {
    final direct = _decisionForNode[node.id];
    if (direct != null) return direct;
    for (final child in node.children) {
      final found = _firstDecisionInSubtree(child);
      if (found != null) return found;
    }
    return null;
  }

  int _countDueDecisionsInSubtree(RepertoireNode node, DateTime now, Map<String, int> memo) {
    final cached = memo[node.id];
    if (cached != null) return cached;
    var count = 0;
    final decision = _decisionForNode[node.id];
    if (decision != null) {
      final state = _reviewStates[decision.canonicalId] ?? _reviewStates[decision.id];
      final isDue = _isDecisionDue(decision, state, now);
      if (isDue) {
        count++;
      }
    }
    for (final child in node.children) {
      count += _countDueDecisionsInSubtree(child, now, memo);
    }
    memo[node.id] = count;
    return count;
  }

  bool _isDecisionDue(RepertoireDecision d, ReviewState? state, DateTime now) {
    if (mode == ReviewMode.practice) return true;
    final isLearned = state != null && state.repetitionCount > 0;
    if (!dynamicRepertoireMode) return state == null || state.isDueAt(now);
    return isLearned
        ? state.isDueAt(now)
        : (unlockedDecisionIds.contains(d.id) || unlockedDecisionIds.contains(d.canonicalId));
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
    // Lapse contagion walks the graded decision's chapter subtree; make sure
    // its node maps exist (the prompt path usually indexed them already).
    _ensureChapterNodesIndexed(decision.chapterId);
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
    _ensureAllChaptersIndexed();
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
    required this.lapsedDecisionIds,
    required this.pendingRetestIds,
    required this.currentPrompt,
    required this.exposureThrottle,
  });

  final Map<String, ReviewState> reviewStates;
  final List<RepertoireDecision> dueQueue;
  final List<RepertoireDecision> unbufferedQueue;
  final Set<String> completedDecisionIds;
  final Set<String> lapsedDecisionIds;
  final Set<String> pendingRetestIds;
  final ReviewPrompt? currentPrompt;
  final Map<String, DateTime> exposureThrottle;
}
