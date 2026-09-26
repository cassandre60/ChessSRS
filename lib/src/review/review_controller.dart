// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' show Platform;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/service/move_feedback.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' show studyRepositoryProvider;
import 'package:chess_srs/src/network/http.dart' show ServerException;
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:logging/logging.dart';

final Logger _logger = Logger('ReviewController');

enum ReviewFeedback { none, correct, incorrect }

class ReviewScreenState {
  const ReviewScreenState({
    required this.studies,
    required this.scope,
    required this.totalDueCount,
    required this.studyDueCounts,
    this.session,
    this.currentPrompt,
    this.boardPosition,
    this.boardOrientation = Side.white,
    this.lastMove,
    this.feedback = ReviewFeedback.none,
    this.expectedMove,
    this.isLapseAcknowledged = true,
    this.revealedComment,
    this.mode = ReviewMode.srs,
    this.openingDueCounts = const {},
    this.isAwaitingAdvance = false,
    this.studyProgress = const {},
    this.chapterProgress = const {},
    this.openingProgress = const {},
    this.lastStepResult,
    this.dailyReviewedCount = 0,
    this.maxDailyReviews = 100,
  });

  final List<Study> studies;
  final ReviewScope scope;
  final int totalDueCount;
  final Map<String, int> studyDueCounts;
  final Map<String, int> openingDueCounts;
  final Map<String, RepertoireProgress> studyProgress;
  final Map<String, RepertoireProgress> chapterProgress;
  final Map<String, RepertoireProgress> openingProgress;
  final ReviewSession? session;
  final ReviewPrompt? currentPrompt;
  final Position? boardPosition;
  final Side boardOrientation;
  final Move? lastMove;
  final ReviewFeedback feedback;
  final RepertoireMove? expectedMove;
  final bool isLapseAcknowledged;
  final String? revealedComment;
  final ReviewMode mode;
  final bool isAwaitingAdvance;
  final ReviewStepResult? lastStepResult;
  final int dailyReviewedCount;
  final int maxDailyReviews;

  bool get isDailyLimitReached =>
      maxDailyReviews > 0 && dailyReviewedCount >= maxDailyReviews && !isPracticeMode;

  bool get hasStudies => studies.isNotEmpty;
  bool get hasDuePositions => (totalDueCount > 0 || isPracticeMode) && currentPrompt != null;
  bool get isComplete =>
      hasStudies &&
      !isAwaitingAdvance &&
      ((totalDueCount == 0 && !isPracticeMode) || currentPrompt == null);
  bool get isPracticeMode => mode == ReviewMode.practice;

  /// Aggregated progress across all active studies in the review pool.
  RepertoireProgress get totalProgress {
    var combined = RepertoireProgress.zero;
    for (final study in studies) {
      if (study.isActive) {
        final prog = studyProgress[study.id];
        if (prog != null) {
          combined += prog;
        }
      }
    }
    return combined;
  }

  /// Progress for the current review scope (study, chapter, or all).
  RepertoireProgress? get activeScopeProgress {
    if (scope.chapterId != null) {
      return chapterProgress[scope.chapterId!];
    }
    if (scope.studyId != null) {
      return studyProgress[scope.studyId!];
    }
    if (scope.openingFamily != null) {
      return openingProgress[scope.openingFamily!];
    }
    return totalProgress;
  }

  /// The earliest upcoming review timestamp scheduled in the future for this session's scope.
  DateTime? get nextReviewDueAt {
    final sessionStates = session?.reviewStates.values;
    if (sessionStates == null || sessionStates.isEmpty) return null;
    final now = session?.clock.now() ?? DateTime.now();
    DateTime? earliest;
    for (final s in sessionStates) {
      if (s.nextDueAt != null && s.nextDueAt!.isAfter(now)) {
        if (earliest == null || s.nextDueAt!.isBefore(earliest)) {
          earliest = s.nextDueAt;
        }
      }
    }
    return earliest;
  }

  /// Human-readable relative time until the next review is due across this scope.
  String? get timeUntilNextReview {
    final due = nextReviewDueAt;
    if (due == null) return null;
    final now = session?.clock.now() ?? DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) return 'due now';

    final minutes = diff.inMinutes;
    final hours = diff.inHours;
    final days = diff.inDays;

    if (minutes < 60) {
      return minutes <= 1 ? 'in 1 minute' : 'in $minutes minutes';
    } else if (hours < 24) {
      return hours == 1 ? 'in 1 hour' : 'in $hours hours';
    } else if (days == 1) {
      final remHours = hours % 24;
      return remHours > 0 ? 'in 1 day, $remHours hr' : 'in 1 day';
    } else {
      return 'in $days days';
    }
  }

  ReviewScreenState copyWith({
    List<Study>? studies,
    ReviewScope? scope,
    int? totalDueCount,
    Map<String, int>? studyDueCounts,
    Map<String, int>? openingDueCounts,
    Map<String, RepertoireProgress>? studyProgress,
    Map<String, RepertoireProgress>? chapterProgress,
    Map<String, RepertoireProgress>? openingProgress,
    ReviewSession? session,
    ReviewPrompt? currentPrompt,
    bool clearPrompt = false,
    Position? boardPosition,
    Side? boardOrientation,
    Move? lastMove,
    bool clearLastMove = false,
    ReviewFeedback? feedback,
    RepertoireMove? expectedMove,
    bool clearExpectedMove = false,
    bool? isLapseAcknowledged,
    String? revealedComment,
    bool clearRevealedComment = false,
    ReviewMode? mode,
    bool? isAwaitingAdvance,
    ReviewStepResult? lastStepResult,
    bool clearLastStepResult = false,
    int? dailyReviewedCount,
    int? maxDailyReviews,
  }) {
    return ReviewScreenState(
      studies: studies ?? this.studies,
      scope: scope ?? this.scope,
      totalDueCount: totalDueCount ?? this.totalDueCount,
      studyDueCounts: studyDueCounts ?? this.studyDueCounts,
      openingDueCounts: openingDueCounts ?? this.openingDueCounts,
      studyProgress: studyProgress ?? this.studyProgress,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      openingProgress: openingProgress ?? this.openingProgress,
      session: session ?? this.session,
      currentPrompt: clearPrompt ? null : (currentPrompt ?? this.currentPrompt),
      boardPosition: boardPosition ?? this.boardPosition,
      boardOrientation: boardOrientation ?? this.boardOrientation,
      lastMove: clearLastMove ? null : (lastMove ?? this.lastMove),
      feedback: feedback ?? this.feedback,
      expectedMove: clearExpectedMove ? null : (expectedMove ?? this.expectedMove),
      isLapseAcknowledged: isLapseAcknowledged ?? this.isLapseAcknowledged,
      revealedComment: clearRevealedComment ? null : (revealedComment ?? this.revealedComment),
      mode: mode ?? this.mode,
      isAwaitingAdvance: isAwaitingAdvance ?? this.isAwaitingAdvance,
      lastStepResult: clearLastStepResult ? null : (lastStepResult ?? this.lastStepResult),
      dailyReviewedCount: dailyReviewedCount ?? this.dailyReviewedCount,
      maxDailyReviews: maxDailyReviews ?? this.maxDailyReviews,
    );
  }
}

/// Provider for [ReviewController].
final reviewControllerProvider = AsyncNotifierProvider<ReviewController, ReviewScreenState>(
  ReviewController.new,
);

class _PendingAdvancement {
  const _PendingAdvancement({
    required this.currentState,
    required this.result,
    required this.isFirstAttempt,
  });

  final ReviewScreenState currentState;
  final ReviewStepResult result;
  final bool isFirstAttempt;
}

class ReviewController extends AsyncNotifier<ReviewScreenState> {
  ReviewService get _service => ref.read(reviewServiceProvider);
  StudyRepository get _repository => ref.read(reviewServiceProvider).repository;

  _PendingAdvancement? _pendingAdvancement;
  bool _isProcessingMove = false;

  /// Bumped by every request that establishes a review session.
  ///
  /// Loading a scope reads the studies, chapters, decisions and review states it needs, so it
  /// yields often enough for a second request to overtake it. Two scope changes in quick
  /// succession, or a scope change racing a settings change, both come to rest here with the
  /// screen showing one session while [ReviewService.activeSession] — the session that grades
  /// the moves — is the other. Ordering the requests and ordering the results on the same
  /// counter is what keeps the two in agreement.
  int _generation = 0;

  bool _hasAnnotationsOrShapes(String? comment) {
    if (comment == null || comment.trim().isEmpty) return false;
    try {
      final prefs = ref.read(studyPreferencesProvider);
      final pgn = PgnComment.fromPgn(comment);
      final hasText = prefs.showPgnComments && pgn.text?.trim().isNotEmpty == true;
      final hasShapes = prefs.showAnnotations && pgn.shapes.isNotEmpty;
      return hasText || hasShapes;
    } catch (_) {
      return comment.trim().isNotEmpty;
    }
  }

  bool get _shouldAnimateOpponentPreMove {
    try {
      return ref.read(studyPreferencesProvider).animateOpponentPreMove;
    } catch (_) {
      return true;
    }
  }

  @override
  Future<ReviewScreenState> build() async {
    ref.listen(schedulerProvider, (previous, next) {
      if (previous != null && previous != next) {
        reload();
      }
    });

    ref.listen(studyPreferencesProvider.select((p) => p.maxDailyReviews), (previous, next) {
      if (previous != null && previous != next) {
        reload();
      }
    });

    // `design/docs/02-tokens.md` §6: play `done` when reaching "Nothing due".
    //
    // [ReviewScreenState.isComplete] is a derived getter, not a field, so there is no
    // assignment site to hang this on — a session can run out through the queue draining,
    // the daily quota, or a study being deactivated. Listening to our own state catches all
    // three from one place, and the rising edge matters: the state is re-emitted constantly
    // while a session is finished, and `done` should sound once when it arrives, not on
    // every subsequent rebuild.
    listenSelf((previous, next) {
      final wasComplete = previous?.value?.isComplete ?? false;
      final isComplete = next.value?.isComplete ?? false;
      if (isComplete && !wasComplete) {
        try {
          ref.read(moveFeedbackServiceProvider).doneFeedback();
        } catch (_) {}
      }
    });

    // Wait for repository provider to be ready if needed
    final repoAsync = ref.watch(srsStudyRepositoryProvider);
    final repo = repoAsync.asData?.value;
    if (repo == null) {
      return const ReviewScreenState(
        studies: [],
        scope: ReviewScope.all(),
        totalDueCount: 0,
        studyDueCounts: {},
      );
    }

    // A load superseded before it finishes has nothing to publish — the request that replaced
    // it will. Riverpod discards a build result once the notifier has moved on, so returning
    // the empty state is only ever a placeholder for a result nobody will read.
    return await _loadState(scope: const ReviewScope.all(), generation: ++_generation) ??
        const ReviewScreenState(
          studies: [],
          scope: ReviewScope.all(),
          totalDueCount: 0,
          studyDueCounts: {},
        );
  }

  /// Derives the remaining allowance from a count of positions already reviewed today.
  int? _remainingQuotaFor(ReviewMode mode, int reviewedCount) {
    final maxDailyReviews = ref.read(studyPreferencesProvider).maxDailyReviews;
    if (mode != ReviewMode.srs || maxDailyReviews <= 0) return null;
    return (maxDailyReviews - reviewedCount).clamp(0, maxDailyReviews);
  }

  /// Reads the day's usage and derives what is left of the allowance.
  ///
  /// Read from the repository rather than carried in state, so a session started part-way through
  /// the day — after toggling a study, or deleting one — is still capped by what has actually been
  /// reviewed. A refresh that skipped this would hand the player a fresh, uncapped session.
  Future<int?> _remainingDailyQuota(ReviewMode mode) async {
    if (mode != ReviewMode.srs) return null;
    final reviewed = await _repository.getTodayReviewedPositionsCount(
      ref.read(clockProvider).now(),
    );
    return _remainingQuotaFor(mode, reviewed);
  }

  /// Loads [scope] in [mode] and publishes the result, unless a newer request has overtaken it.
  ///
  /// Bumping [_generation] first is what supersedes any load already in flight, so the older one
  /// reaches neither the screen nor the service's active session once it finishes.
  Future<void> _loadAndPublish(ReviewScope scope, ReviewMode mode) async {
    _pendingAdvancement = null;
    final generation = ++_generation;
    try {
      final next = await _loadState(scope: scope, mode: mode, generation: generation);
      // Null means a newer request took over; it publishes its own result.
      if (next == null || !ref.mounted) return;
      state = AsyncData(next);
    } catch (e, st) {
      // A failure from a superseded load is not this screen's problem to report.
      if (!ref.mounted || generation != _generation) return;
      _logger.warning('Failed to load review state for $scope', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Returns null when [generation] has been superseded, in which case the caller must not
  /// publish what it was loading.
  Future<ReviewScreenState?> _loadState({
    required ReviewScope scope,
    ReviewMode mode = ReviewMode.srs,
    int? generation,
  }) async {
    final maxDailyReviews = ref.read(studyPreferencesProvider).maxDailyReviews;
    final now = ref.read(clockProvider).now();
    final dailyReviewedCount = await _repository.getTodayReviewedPositionsCount(now);

    final remainingQuota = _remainingQuotaFor(mode, dailyReviewedCount);

    final studies = await _repository.getAllStudies();
    final summary = await _service.getDueSummary(
      studies: studies,
      scope: scope,
      remainingDailyQuota: remainingQuota,
    );

    if (studies.isEmpty) {
      if (generation != null && generation != _generation) return null;
      return ReviewScreenState(
        studies: studies,
        scope: scope,
        mode: mode,
        totalDueCount: 0,
        studyDueCounts: summary.studyDueCounts,
        openingDueCounts: summary.openingDueCounts,
        studyProgress: summary.studyProgress,
        chapterProgress: summary.chapterProgress,
        openingProgress: summary.openingProgress,
        dailyReviewedCount: dailyReviewedCount,
        maxDailyReviews: maxDailyReviews,
      );
    }

    final session = await _service.startSession(
      scope: scope,
      mode: mode,
      remainingDailyQuota: remainingQuota,
      generation: generation,
    );

    // Everything below reads the session that was just built, and everything above waited on
    // the database. A request made in between owns the screen now, so this load is abandoned
    // here rather than published over it — and the session was not installed as the active one
    // either, so the screen and the grader cannot end up on different sessions.
    if (generation != null && generation != _generation) return null;

    final prompt = session.currentPrompt;

    Position? position;
    Side orientation = Side.white;
    Move? lastMove;

    final shouldAnimate =
        prompt != null &&
        prompt.incomingMove != null &&
        prompt.parentFen != null &&
        _shouldAnimateOpponentPreMove;

    if (prompt != null) {
      position = shouldAnimate ? _parseFen(prompt.parentFen!) : _parseFen(prompt.fen);
      orientation = prompt.sideToMove;
    } else if (scope.chapterId != null) {
      final chapter = await _repository.getChapter(scope.chapterId!);
      if (chapter != null && chapter.orientation == Side.black) {
        orientation = Side.black;
      }
    } else if (scope.studyId != null) {
      final chapters = await _repository.getChaptersByStudy(scope.studyId!);
      if (chapters.isNotEmpty && chapters.first.orientation == Side.black) {
        orientation = Side.black;
      }
    }

    if (shouldAnimate) {
      Future.microtask(() => _playIncomingPreMove(prompt));
    }

    _logger.info(
      'ReviewState loaded for scope $scope: ${studies.length} studies, totalDue=${summary.totalDueCount}, mode=$mode, quota=$dailyReviewedCount/$maxDailyReviews',
    );

    return ReviewScreenState(
      studies: studies,
      scope: scope,
      mode: mode,
      totalDueCount: summary.totalDueCount,
      studyDueCounts: summary.studyDueCounts,
      openingDueCounts: summary.openingDueCounts,
      studyProgress: summary.studyProgress,
      chapterProgress: summary.chapterProgress,
      openingProgress: summary.openingProgress,
      dailyReviewedCount: dailyReviewedCount,
      maxDailyReviews: maxDailyReviews,
      session: session,
      currentPrompt: prompt,
      boardPosition: position,
      boardOrientation: orientation,
      lastMove: lastMove,
      feedback: ReviewFeedback.none,
      isLapseAcknowledged: true,
    );
  }

  /// Changes the active review scope (all studies or a specific study).
  Future<void> changeScope(ReviewScope scope) => _loadAndPublish(scope, ReviewMode.srs);

  /// Reloads the session and due counts for the current scope.
  Future<void> reload() async {
    if (!ref.mounted) return;
    final currentState = state.value;
    await _loadAndPublish(
      currentState?.scope ?? const ReviewScope.all(),
      currentState?.mode ?? ReviewMode.srs,
    );
  }

  /// Starts non-destructive pre-match rehearsal / cram mode (PRODUCT.md Journey 4).
  Future<void> startPracticeMode({ReviewScope? scope}) async {
    await _loadAndPublish(
      scope ?? state.value?.scope ?? const ReviewScope.all(),
      ReviewMode.practice,
    );
  }

  /// Exits practice mode and returns to standard SRS review.
  Future<void> exitPracticeMode() async {
    await _loadAndPublish(state.value?.scope ?? const ReviewScope.all(), ReviewMode.srs);
  }

  /// Toggles whether a study is included in the daily review pool (PRODUCT.md Journey 5).
  Future<void> toggleStudyActive(String studyId, bool isActive) async {
    final currentState = state.value;
    if (currentState == null) return;
    _logger.info('Toggling study $studyId active state to $isActive');

    // Adding or removing a study reshapes the review pool, so this is as much a change of
    // session as a scope change is. Claiming a generation supersedes any load already running:
    // that load's counts were computed from a pool this toggle has just invalidated.
    final generation = ++_generation;

    // 1. Optimistic UI update: flip isActive immediately so user sees instant feedback
    final updatedStudies = currentState.studies
        .map((s) => s.id == studyId ? s.copyWith(isActive: isActive) : s)
        .toList();
    state = AsyncData(currentState.copyWith(studies: updatedStudies));

    // 2. Persist to DB
    await _repository.updateStudyActive(studyId, isActive);

    // 3. Recompute due counts using the fast summary (without setting AsyncLoading)
    final summary = await _service.getDueSummary(
      studies: updatedStudies,
      scope: currentState.scope,
    );

    // 4. Smoothly refresh session if affected (e.g. current prompt belonged to deactivated study)
    ReviewSession? newSession = currentState.session;
    ReviewPrompt? newPrompt = currentState.currentPrompt;
    Position? newPosition = currentState.boardPosition;
    Side newOrientation = currentState.boardOrientation;

    final currentPromptStudyId = currentState.currentPrompt?.studyId;
    final isCurrentScopeAll =
        currentState.scope.studyId == null && currentState.scope.openingFamily == null;
    final needsSessionRefresh =
        (isCurrentScopeAll && !isActive && currentPromptStudyId == studyId) ||
        (currentState.isComplete && isActive);

    if (needsSessionRefresh) {
      newSession = await _service.startSession(
        scope: currentState.scope,
        mode: currentState.mode,
        remainingDailyQuota: await _remainingDailyQuota(currentState.mode),
        generation: generation,
      );
      newPrompt = newSession.currentPrompt;
      if (newPrompt != null) {
        newPosition = _parseFen(newPrompt.fen);
        newOrientation = newPrompt.sideToMove;
      } else {
        newPosition = null;
      }
    }

    // A scope change or reload that started after this toggle owns the screen now; the counts
    // computed here are from a pool it has already replaced.
    if (generation != _generation || !ref.mounted) return;

    state = AsyncData(
      currentState.copyWith(
        studies: updatedStudies,
        totalDueCount: summary.totalDueCount,
        studyDueCounts: summary.studyDueCounts,
        openingDueCounts: summary.openingDueCounts,
        studyProgress: summary.studyProgress,
        chapterProgress: summary.chapterProgress,
        openingProgress: summary.openingProgress,
        session: newSession,
        currentPrompt: newPrompt,
        clearPrompt: newPrompt == null,
        boardPosition: newPosition,
        boardOrientation: newOrientation,
      ),
    );
  }

  /// Renames a study to [newTitle].
  Future<void> renameStudy(String studyId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    _logger.info('Renaming study $studyId to "$trimmed"');
    await _repository.updateStudyTitle(studyId, trimmed);
    final currentState = state.value;
    if (currentState != null) {
      final updatedStudies = currentState.studies
          .map((s) => s.id == studyId ? s.copyWith(title: trimmed) : s)
          .toList();
      state = AsyncData(currentState.copyWith(studies: updatedStudies));
    }
  }

  /// Deletes a study and all associated chapters, decisions, and recall history.
  Future<void> deleteStudy(String studyId) async {
    _logger.info('Deleting study $studyId');
    // Claimed before the delete, not after: any load already running is counting positions in a
    // pool this is about to empty, so it must not be allowed to publish over the result.
    final generation = ++_generation;
    await _repository.deleteStudy(studyId);
    if (state.value?.scope.studyId == studyId) {
      await changeScope(const ReviewScope.all());
    } else {
      final currentState = state.value;
      if (currentState != null) {
        final updatedStudies = currentState.studies.where((s) => s.id != studyId).toList();
        final remainingQuota = await _remainingDailyQuota(currentState.mode);
        final summary = await _service.getDueSummary(
          studies: updatedStudies,
          scope: currentState.scope,
          remainingDailyQuota: remainingQuota,
        );
        final newSession = await _service.startSession(
          scope: currentState.scope,
          mode: currentState.mode,
          remainingDailyQuota: remainingQuota,
          generation: generation,
        );

        // Superseded while the delete and the summary were being computed.
        if (generation != _generation || !ref.mounted) return;

        final prompt = newSession.currentPrompt;
        state = AsyncData(
          currentState.copyWith(
            studies: updatedStudies,
            totalDueCount: summary.totalDueCount,
            studyDueCounts: summary.studyDueCounts,
            openingDueCounts: summary.openingDueCounts,
            studyProgress: summary.studyProgress,
            chapterProgress: summary.chapterProgress,
            openingProgress: summary.openingProgress,
            session: newSession,
            currentPrompt: prompt,
            clearPrompt: prompt == null,
            boardPosition: prompt != null ? _parseFen(prompt.fen) : null,
            boardOrientation: prompt?.sideToMove ?? Side.white,
          ),
        );
      }
    }
  }

  /// Exports all chapters of [studyId] to standard PGN string for explore/analysis mode.
  Future<String?> exportStudyPgn(String studyId) async {
    final study = await _repository.getStudy(studyId);
    if (study == null) return null;
    final chapters = await _repository.getChaptersByStudy(studyId);
    return studyToPgn(study, chapters);
  }

  /// Exports a single chapter with [chapterId] to standard PGN string.
  Future<String?> exportChapterPgn(String chapterId) async {
    final chapter = await _repository.getChapter(chapterId);
    if (chapter == null) return null;
    Chapter fullChapter = chapter;
    if (fullChapter.root == null) {
      final root = await _repository.getPositionTree(chapter.id);
      fullChapter = chapter.copyWith(root: root);
    }
    final study = await _repository.getStudy(chapter.studyId);
    return chapterToPgn(fullChapter, studyTitle: study?.title);
  }

  /// Advances to the next prompt after pausing to display move commentary or shapes.
  Future<void> continueAdvancement() async {
    if (_isProcessingMove) return;
    final pending = _pendingAdvancement;
    if (pending == null) return;
    _pendingAdvancement = null;

    _isProcessingMove = true;
    try {
      // Dismiss awaiting advance immediately so user receives instant tactile feedback
      if (state.value != null && state.value!.isAwaitingAdvance) {
        state = AsyncData(state.value!.copyWith(isAwaitingAdvance: false));
      }

      await _executeAdvancement(
        currentState: pending.currentState,
        result: pending.result,
        isFirstAttempt: pending.isFirstAttempt,
      );
    } finally {
      _isProcessingMove = false;
    }
  }

  /// Handles move animation, opponent reply pacing, and transition to the next prompt.
  Future<void> _handleCorrectAdvancement({
    required ReviewScreenState currentState,
    required ReviewStepResult result,
    required Move userMove,
    required bool isFirstAttempt,
  }) async {
    final currentPos = currentState.boardPosition;
    final posAfterUser = currentPos != null && userMove is NormalMove
        ? currentPos.play(userMove)
        : null;

    final comment = _resolveComment(currentState.currentPrompt, result.expectedMoves.firstOrNull);

    // 1. Immediately show user's move on the board
    // `design/docs/02-tokens.md` §6: "Play `move` for both the user's and the opponent's
    // piece landing." The opponent's reply already sounds, in _executeAdvancement; the user's
    // own landing did not, because the board is silent and onUserMove used to go straight
    // from submitMove to this state assignment. Fired here, beside the board update it
    // belongs to, rather than after the auto-advance delay.
    try {
      ref.read(moveFeedbackServiceProvider).moveFeedback();
    } catch (_) {}
    state = AsyncData(
      currentState.copyWith(
        boardPosition: posAfterUser ?? currentState.boardPosition,
        lastMove: userMove,
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        revealedComment: comment,
        lastStepResult: result,
      ),
    );

    // If annotations/shapes are present, pause auto-advancement so the learner
    // can read commentary and inspect board shapes before advancing.
    final hasAnnotations =
        _hasAnnotationsOrShapes(comment) ||
        _hasAnnotationsOrShapes(currentState.currentPrompt?.comment);

    if (hasAnnotations) {
      _pendingAdvancement = _PendingAdvancement(
        currentState: currentState,
        result: result,
        isFirstAttempt: isFirstAttempt,
      );
      state = AsyncData(
        state.value!.copyWith(isAwaitingAdvance: true, feedback: ReviewFeedback.correct),
      );
      return;
    }

    await _executeAdvancement(
      currentState: currentState,
      result: result,
      isFirstAttempt: isFirstAttempt,
    );
  }

  Future<void> _executeAdvancement({
    required ReviewScreenState currentState,
    required ReviewStepResult result,
    required bool isFirstAttempt,
  }) async {
    // 2. If opponent has an auto-reply, pause briefly then show it with smooth piece animation.
    // If it's the final move of the line (no opponent reply), pause so the user
    // sees their move actualized on the board before the line transitions.
    final opponentMoves = result.autoPlayedMoves.where((m) => !m.isUserMove).toList();
    if (opponentMoves.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!ref.mounted) return;

      final oppMove = opponentMoves.first;
      final oppNormalMove = NormalMove(
        from: Square.fromName(oppMove.move.from),
        to: Square.fromName(oppMove.move.to),
        promotion: oppMove.move.promotion != null ? Role.fromChar(oppMove.move.promotion!) : null,
      );
      final oppPos = _parseFen(oppMove.fenAfter);

      state = AsyncData(
        state.value!.copyWith(
          boardPosition: oppPos,
          lastMove: oppNormalMove,
          isAwaitingAdvance: false,
        ),
      );
      try {
        ref.read(moveFeedbackServiceProvider).moveFeedback();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!ref.mounted) return;
    } else {
      // Final move of line: pause so user sees their move actualized on the board
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!ref.mounted) return;
    }

    // 3. Advance to next prompt
    final session = _service.activeSession!;
    final nextPrompt = session.currentPrompt;

    final shouldAnimateBranchPreMove =
        opponentMoves.isEmpty &&
        nextPrompt != null &&
        nextPrompt.incomingMove != null &&
        nextPrompt.parentFen != null &&
        _shouldAnimateOpponentPreMove;

    Position? nextPosition;
    Side nextOrientation = currentState.boardOrientation;
    if (nextPrompt != null) {
      nextPosition = shouldAnimateBranchPreMove
          ? _parseFen(nextPrompt.parentFen!)
          : _parseFen(nextPrompt.fen);
      nextOrientation = nextPrompt.sideToMove;
    }

    final newTotalDue = isFirstAttempt && currentState.totalDueCount > 0
        ? currentState.totalDueCount - 1
        : currentState.totalDueCount;

    final studyCounts = Map<String, int>.from(currentState.studyDueCounts);
    final currentStudyId = currentState.currentPrompt!.studyId;
    if (isFirstAttempt &&
        studyCounts.containsKey(currentStudyId) &&
        studyCounts[currentStudyId]! > 0) {
      studyCounts[currentStudyId] = studyCounts[currentStudyId]! - 1;
    }

    final openingCounts = Map<String, int>.from(currentState.openingDueCounts);
    final currentChapter = session.getChapter(currentState.currentPrompt!.chapterId);
    final currentOpening = currentChapter?.opening;
    if (isFirstAttempt &&
        currentOpening != null &&
        openingCounts.containsKey(currentOpening) &&
        openingCounts[currentOpening]! > 0) {
      openingCounts[currentOpening] = openingCounts[currentOpening]! - 1;
    }

    final studyProgressMap = Map<String, RepertoireProgress>.from(currentState.studyProgress);
    final chapterProgressMap = Map<String, RepertoireProgress>.from(currentState.chapterProgress);
    final openingProgressMap = Map<String, RepertoireProgress>.from(currentState.openingProgress);
    final currentChapterId = currentState.currentPrompt!.chapterId;
    if (isFirstAttempt) {
      final isNewlyLearned =
          result.event != null &&
          !result.event!.oldState.isLearned &&
          result.updatedState.isLearned;

      final stProg = studyProgressMap[currentStudyId];
      if (stProg != null) {
        studyProgressMap[currentStudyId] = RepertoireProgress(
          totalDecisions: stProg.totalDecisions,
          learnedDecisions: isNewlyLearned
              ? (stProg.learnedDecisions + 1).clamp(0, stProg.totalDecisions)
              : stProg.learnedDecisions,
          dueDecisions: (stProg.dueDecisions - 1).clamp(0, stProg.totalDecisions),
        );
      }
      final chProg = chapterProgressMap[currentChapterId];
      if (chProg != null) {
        chapterProgressMap[currentChapterId] = RepertoireProgress(
          totalDecisions: chProg.totalDecisions,
          learnedDecisions: isNewlyLearned
              ? (chProg.learnedDecisions + 1).clamp(0, chProg.totalDecisions)
              : chProg.learnedDecisions,
          dueDecisions: (chProg.dueDecisions - 1).clamp(0, chProg.totalDecisions),
        );
      }
      if (currentOpening != null) {
        final opProg = openingProgressMap[currentOpening];
        if (opProg != null) {
          openingProgressMap[currentOpening] = RepertoireProgress(
            totalDecisions: opProg.totalDecisions,
            learnedDecisions: isNewlyLearned
                ? (opProg.learnedDecisions + 1).clamp(0, opProg.totalDecisions)
                : opProg.learnedDecisions,
            dueDecisions: (opProg.dueDecisions - 1).clamp(0, opProg.totalDecisions),
          );
        }
      }
    }

    // Counted on completion, not on a first-try success. A position answered right only after a
    // lapse is still one position reviewed today, and the session's own quota count includes it —
    // counting it here too is what keeps the number on screen equal to the one being enforced.
    // This cannot double-count: a prompt answered correctly has already advanced, so it cannot
    // complete a second time.
    final updatedDailyCount = currentState.dailyReviewedCount + 1;

    state = AsyncData(
      state.value!.copyWith(
        dailyReviewedCount: updatedDailyCount,
        totalDueCount: newTotalDue,
        studyDueCounts: studyCounts,
        openingDueCounts: openingCounts,
        studyProgress: studyProgressMap,
        chapterProgress: chapterProgressMap,
        openingProgress: openingProgressMap,
        session: session,
        currentPrompt: nextPrompt,
        clearPrompt: nextPrompt == null,
        boardPosition: nextPosition,
        boardOrientation: nextOrientation,
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        isAwaitingAdvance: false,
        lastMove: shouldAnimateBranchPreMove
            ? null
            : (opponentMoves.isNotEmpty ? state.value?.lastMove : null),
        clearLastMove: shouldAnimateBranchPreMove,
        revealedComment: null,
        clearRevealedComment: true,
        clearLastStepResult: true,
      ),
    );

    if (shouldAnimateBranchPreMove) {
      await _playIncomingPreMove(nextPrompt);
    }
  }

  /// Submits a move played by the user.
  Future<ReviewStepResult?> onUserMove(Move move) async {
    final currentState = state.asData?.value;
    if (currentState == null || currentState.currentPrompt == null) return null;
    if (_isProcessingMove) return null;
    if (currentState.isAwaitingAdvance) {
      await continueAdvancement();
      return null;
    }
    if (move is! NormalMove) return null;

    final from = move.from.name;
    final to = move.to.name;
    final promotion = move.promotion?.letter;

    final isRetrying = currentState.feedback == ReviewFeedback.incorrect;
    _logger.fine('onUserMove: ${move.uci} (retrying=$isRetrying)');

    _isProcessingMove = true;
    try {
      if (isRetrying) {
        // Reguess attempt after previous lapse
        final result = await _service.retryMove(from: from, to: to, promotion: promotion);
        if (result.isCorrect) {
          await _handleCorrectAdvancement(
            currentState: currentState,
            result: result,
            userMove: move,
            isFirstAttempt: false,
          );
        } else {
          // A reguess that is still wrong is another rejected move, so it gets the same
          // sound as the first one. Left silent before, which made the second and later
          // wrong attempts feel unacknowledged.
          try {
            ref.read(moveFeedbackServiceProvider).wrongFeedback();
          } catch (_) {}
          state = AsyncData(
            currentState.copyWith(
              feedback: ReviewFeedback.incorrect,
              expectedMove: result.expectedMoves.firstOrNull,
              isLapseAcknowledged: false,
              revealedComment: _resolveComment(
                currentState.currentPrompt,
                result.expectedMoves.firstOrNull,
              ),
            ),
          );
        }
        return result;
      }

      // Initial move attempt on this prompt
      final result = await _service.submitMove(from: from, to: to, promotion: promotion);

      if (result.isCorrect) {
        await _handleCorrectAdvancement(
          currentState: currentState,
          result: result,
          userMove: move,
          isFirstAttempt: true,
        );
      } else {
        // Lapse: show expected move banner, allow user to reguess on board
        // `design/docs/02-tokens.md` §6: play `wrong` on a rejected move. Fired before the
        // state assignment so the sound lands with the correction rather than after it.
        try {
          ref.read(moveFeedbackServiceProvider).wrongFeedback();
        } catch (_) {}
        state = AsyncData(
          currentState.copyWith(
            feedback: ReviewFeedback.incorrect,
            expectedMove: result.expectedMoves.firstOrNull,
            isLapseAcknowledged: false,
            revealedComment: _resolveComment(
              currentState.currentPrompt,
              result.expectedMoves.firstOrNull,
            ),
            lastStepResult: result,
          ),
        );
      }

      return result;
    } finally {
      _isProcessingMove = false;
    }
  }

  /// Acknowledges a lapse, clearing the expected move arrow and advancing.
  void acknowledgeLapse() {
    if (_isProcessingMove) return;
    _pendingAdvancement = null;
    final currentState = state.asData?.value;
    if (currentState == null) return;

    _service.continueAfterIncorrect();
    final session = _service.activeSession;
    final nextPrompt = session?.currentPrompt;

    final shouldAnimate =
        nextPrompt != null &&
        nextPrompt.incomingMove != null &&
        nextPrompt.parentFen != null &&
        _shouldAnimateOpponentPreMove;

    Position? nextPosition;
    Side nextOrientation = currentState.boardOrientation;
    if (nextPrompt != null) {
      nextPosition = shouldAnimate ? _parseFen(nextPrompt.parentFen!) : _parseFen(nextPrompt.fen);
      nextOrientation = nextPrompt.sideToMove;
    }

    state = AsyncData(
      currentState.copyWith(
        currentPrompt: nextPrompt,
        clearPrompt: nextPrompt == null,
        boardPosition: nextPosition,
        boardOrientation: nextOrientation,
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        isAwaitingAdvance: false,
        clearLastMove: true,
        clearRevealedComment: true,
        clearLastStepResult: true,
      ),
    );

    if (shouldAnimate) {
      _playIncomingPreMove(nextPrompt);
    }
  }

  /// Skips the current prompt, moving it to the back of the queue.
  void skip() {
    if (_isProcessingMove) return;
    _pendingAdvancement = null;
    final currentState = state.asData?.value;
    if (currentState == null || currentState.currentPrompt == null) return;

    final nextPrompt = _service.skipCurrentPrompt();

    final shouldAnimate =
        nextPrompt != null &&
        nextPrompt.incomingMove != null &&
        nextPrompt.parentFen != null &&
        _shouldAnimateOpponentPreMove;

    Position? nextPosition;
    Side nextOrientation = currentState.boardOrientation;
    if (nextPrompt != null) {
      nextPosition = shouldAnimate ? _parseFen(nextPrompt.parentFen!) : _parseFen(nextPrompt.fen);
      nextOrientation = nextPrompt.sideToMove;
    }

    state = AsyncData(
      currentState.copyWith(
        currentPrompt: nextPrompt,
        clearPrompt: nextPrompt == null,
        boardPosition: nextPosition,
        boardOrientation: nextOrientation,
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        isAwaitingAdvance: false,
        clearLastMove: true,
        clearRevealedComment: true,
        clearLastStepResult: true,
      ),
    );

    if (shouldAnimate) {
      _playIncomingPreMove(nextPrompt);
    }
  }

  Future<void> _playIncomingPreMove(ReviewPrompt prompt) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!ref.mounted) return;
    final currentState = state.value;
    if (currentState == null || currentState.currentPrompt?.decision.id != prompt.decision.id) {
      return;
    }

    final incoming = prompt.incomingMove;
    if (incoming == null) return;

    final normalMove = NormalMove(
      from: Square.fromName(incoming.from),
      to: Square.fromName(incoming.to),
      promotion: incoming.promotion != null ? Role.fromChar(incoming.promotion!) : null,
    );
    final targetPos = _parseFen(prompt.fen);

    try {
      ref.read(moveFeedbackServiceProvider).moveFeedback();
    } catch (_) {}

    state = AsyncData(currentState.copyWith(boardPosition: targetPos, lastMove: normalMove));
  }

  /// Whether [chapters] were all imported to train [side].
  ///
  /// The PGN hash covers the move tree, which is identical whichever side is being trained, so a
  /// White and a Black repertoire of the same lines share a fingerprint. They are different
  /// questions with different SRS memory, and treating the second import as a duplicate silently
  /// discards it — the user is switched to the study they already had and told it is up to date.
  ///
  /// The side is deliberately not folded into the hash itself: every stored `pgnHash` was
  /// computed without it, and changing the fingerprint would strand all of them, turning every
  /// re-import into a fresh duplicate.
  ///
  /// A mixed set is not a match, so it is re-imported. A spare copy costs the user a delete;
  /// a wrongly-skipped import costs them the repertoire.
  bool _chaptersMatchSide(List<Chapter> chapters, Side? side) =>
      side == null || (chapters.isNotEmpty && chapters.every((c) => c.orientation == side));

  /// Imports a repertoire from PGN text and immediately loads it for review.
  ///
  /// Implements Listudy tree_hash change detection: if a study with identical
  /// PGN hash already exists, avoids data duplication and switches directly to
  /// reviewing that existing study.
  Future<ImportResult> importPgnText({
    required String pgnText,
    String? title,
    Side? repertoireSide,
  }) async {
    // Hashed before anything else, because duplicate detection decides whether an import happens
    // at all — and computing it parses the whole file. Left synchronous, a multi-megabyte PGN
    // blocked the UI isolate before the background-parse branch below was ever reached. The
    // helper keeps small files on this isolate and moves large ones to a worker.
    final hash = await computePgnHashAsync(pgnText);
    _logger.info(
      'importPgnText called (title="$title", side=$repertoireSide, hash=${hash.substring(0, 8)})',
    );
    var existingStudy = await _repository.getStudyByPgnHash(hash, forSide: repertoireSide);

    if (existingStudy == null && title != null && title.trim().isNotEmpty) {
      final allStudies = await _repository.getAllStudies();
      final matchByTitle = allStudies
          .where((Study s) => s.title.trim().toLowerCase() == title.trim().toLowerCase())
          .firstOrNull;
      if (matchByTitle != null) {
        final chapters = await _repository.getChaptersByStudy(matchByTitle.id);
        final existingHash = matchByTitle.pgnHash ?? computeRepertoireTreeHash(chapters);
        if (existingHash == hash && _chaptersMatchSide(chapters, repertoireSide)) {
          existingStudy = matchByTitle;
        }
      }
    }

    if (existingStudy != null) {
      _logger.info(
        'Duplicate study detected for hash ${hash.substring(0, 8)}, skipping re-import: ${existingStudy.id}',
      );
      await changeScope(ReviewScope.study(existingStudy.id));
      return ImportResult(
        study: existingStudy,
        chapters: const [],
        decisions: const [],
        errors: const [],
        isDuplicate: true,
      );
    }

    // Offload large PGN parsing (>=64KB) to background worker isolate to keep UI thread 60/120fps.
    final ImportResult result;
    if (!Platform.environment.containsKey('FLUTTER_TEST') && pgnText.length >= 65536) {
      result = await importPgnAsync(
        pgnText,
        studyTitle: title ?? 'Imported Study',
        repertoireSide: repertoireSide,
        pgnHash: hash,
      );
    } else {
      result = importPgn(
        pgnText,
        studyTitle: title ?? 'Imported Study',
        repertoireSide: repertoireSide,
        pgnHash: hash,
      );
    }

    // Nothing to train means there is nothing worth keeping: storing the study would leave an
    // empty repertoire in the library that opens onto a blank board, with the only record of the
    // failure being a success message. A partial import is a different case — it has positions,
    // so it is saved and its errors travel with it.
    //
    // A duplicate is also a zero-decision result, and legitimately so: it imported nothing
    // because the study is already there, which is the answer the caller came for.
    if (!result.isDuplicate && result.decisions.isEmpty) {
      final reason = result.errors.isEmpty
          ? 'the PGN contained no moves for the selected side'
          : result.errors.first.message;
      _logger.warning('Rejecting import of "${result.study.title}": $reason');
      throw FormatException('Nothing to import — $reason');
    }

    await _repository.saveImportResult(result);
    await changeScope(ReviewScope.study(result.study.id));
    return result;
  }

  /// Imports a study directly from Lichess given its URL or 8-character study ID.
  Future<ImportResult> importLichessStudy({
    required String studyIdOrUrl,
    String? title,
    Side? repertoireSide,
  }) async {
    final studyRef = parseLichessStudyReference(studyIdOrUrl);
    if (studyRef == null) {
      _logger.warning('Invalid Lichess study reference: $studyIdOrUrl');
      throw const FormatException('Invalid Lichess study URL or 8-character study ID');
    }

    _logger.info('Fetching study from Lichess: ${studyRef.id} on ${studyRef.host}');
    final studyRepo = ref.read(studyRepositoryProvider);
    final String pgnText;
    try {
      pgnText = await studyRepo.getStudyPgn(StudyId(studyRef.id), host: studyRef.host);
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        throw const FormatException(
          'Study not found on Lichess. Ensure the study is public or unlisted.',
        );
      }
      throw FormatException('Failed to load study from Lichess (${e.statusCode}): ${e.message}');
    } on ClientException catch (e) {
      if (e.message.contains('404')) {
        throw const FormatException(
          'Study not found on Lichess. Ensure the study is public or unlisted.',
        );
      }
      rethrow;
    } catch (e) {
      if (e.toString().contains('404')) {
        throw const FormatException(
          'Study not found on Lichess. Ensure the study is public or unlisted.',
        );
      }
      rethrow;
    }

    if (pgnText.trim().isEmpty) {
      throw const FormatException('The study contains no games or moves');
    }

    final effectiveTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : extractStudyTitleFromPgn(pgnText) ?? 'Lichess Study ${studyRef.id}';

    return await importPgnText(
      pgnText: pgnText,
      title: effectiveTitle,
      repertoireSide: repertoireSide,
    );
  }

  String? _resolveComment(ReviewPrompt? prompt, RepertoireMove? expectedMove) {
    if (prompt == null) return null;
    final child = expectedMove != null && prompt.currentNode != null
        ? prompt.currentNode!.childForMove(expectedMove)
        : null;
    final childComment = child?.comment?.trim();
    final promptComment = prompt.comment?.trim();

    if (childComment != null &&
        childComment.isNotEmpty &&
        promptComment != null &&
        promptComment.isNotEmpty &&
        childComment != promptComment) {
      return '$childComment\n\n$promptComment';
    }
    return childComment?.isNotEmpty == true ? childComment : promptComment;
  }

  Position _parseFen(String fen) {
    try {
      final setup = Setup.parseFen(fen);
      return Chess.fromSetup(setup);
    } catch (_) {
      return Chess.initial;
    }
  }
}
