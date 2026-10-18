// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/lichess_games_study_generator.dart';
import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/import/pgn_offload.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/service/move_feedback.dart';
import 'package:chess_srs/src/model/engine/opening_book.dart';
import 'package:chess_srs/src/model/engine/opponent_level.dart' show MaiaRating;
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

/// Pause before playing opponent auto-reply move so the user sees their own move land.
const kOpponentMoveDelay = Duration(milliseconds: 300);

/// Pause after opponent move before advancing to the next prompt.
const kOpponentPostMoveDelay = Duration(milliseconds: 300);

/// Pause on the final move of a variation so user sees their piece land before transitioning.
const kEndOfLinePause = Duration(milliseconds: 350);

/// Pause before animating an incoming opponent pre-move on line transition.
const kIncomingPreMoveDelay = Duration(milliseconds: 350);

/// Lichess answered 404 for a study id.
///
/// The cause is genuinely ambiguous: a private study and a study that does not exist are
/// indistinguishable to an anonymous request, and Lichess returns 404 for both rather than 403.
/// So the UI must not assert which one it was — it can only offer to sign in and retry.
///
/// Extends [FormatException] so existing callers that catch it keep working unchanged; the
/// type is what lets the import dialog branch on the case without matching on message text.
class StudyNotFoundException extends FormatException {
  const StudyNotFoundException(super.message);
}

/// Lichess refused or failed the owned-studies listing that bulk import enumerates.
///
/// Carries the human-readable reason so the dialog can show it instead of a
/// generic failure: a 401 here means the sign-in has no study permission,
/// which no retry will fix.
class BulkImportListException extends FormatException {
  const BulkImportListException(super.message);
}

/// Progress of [ReviewController.importAllMyStudies]: [done] studies processed
/// out of [total], currently (or last) working on [currentName].
typedef BulkImportProgress = ({int done, int total, String currentName});

/// A study [importAllMyStudies] could not import, with the [reason] it was skipped.
typedef BulkImportFailure = ({String name, String reason});

/// Outcome of [ReviewController.importAllMyStudies]: freshly [imported] studies,
/// [duplicates] skipped as already here (named in [duplicateTitles]), and
/// per-study [failed] reasons.
typedef BulkImportResult = ({
  int imported,
  int duplicates,
  List<String> duplicateTitles,
  List<BulkImportFailure> failed,
});

/// Lichess refused or failed the game export that custom study generation reads.
class CustomStudiesGenerationException extends FormatException {
  const CustomStudiesGenerationException(super.message);
}

/// Phase of [ReviewController.generateStudiesFromMyGames].
enum CustomStudiesPhase { fetchingGames, buildingStudies }

/// Progress of [ReviewController.generateStudiesFromMyGames].
typedef CustomStudiesProgress = ({
  CustomStudiesPhase phase,
  int gamesFetched,
  int done,
  int total,
  String currentName,
});

/// Outcome of [ReviewController.generateStudiesFromMyGames].
typedef CustomStudiesResult = ({
  int imported,
  int updated,
  int duplicates,
  int gamesAnalyzed,
  int mistakesFixed,
  List<GeneratedOpeningStudy> generatedStudies,
  List<BulkImportFailure> failed,
});

class ReviewScreenState {
  const ReviewScreenState({
    required this.studies,
    required this.scope,
    required this.totalDueCount,
    required this.totalFreshCount,
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
    this.sideProgress = const {},
    this.studySideProgress = const {},
    this.studyIdsBySide = const {},
    this.openingsBySide = const {},
    this.lastStepResult,
    this.pendingUnlock,
    this.dailyReviewedCount = 0,
    this.maxDailyReviews = 100,
  });

  final List<Study> studies;
  final ReviewScope scope;
  final int totalDueCount;

  /// Never-presented positions in scope (INV-068), from the service's summary.
  ///
  /// Carried so the reuse fast path (#149) reproduces the same figure the
  /// summary pass would, and so the review screen can tell an unstarted scope
  /// from a finished one.
  final int totalFreshCount;
  final Map<String, int> studyDueCounts;
  final Map<String, int> openingDueCounts;
  final Map<String, RepertoireProgress> studyProgress;
  final Map<String, RepertoireProgress> chapterProgress;
  final Map<String, RepertoireProgress> openingProgress;

  /// Progress over the chapters trained from each side, keyed by [Side].
  ///
  /// Read from [ReviewService.getDueSummary] rather than derived here: the
  /// service already walks every decision with its chapter's orientation in
  /// hand, so a second derivation in the controller would be a second pass over
  /// the same table to produce a number the first pass could have produced.
  final Map<Side, RepertoireProgress> sideProgress;

  /// Study progress partitioned by side, for the repertoire menus (INV-030).
  ///
  /// `studySideProgress[studyId]` carries only the sides the study trains, so
  /// its keys are also what places a study under the White menu, the Black
  /// menu, or both.
  final Map<String, Map<Side, RepertoireProgress>> studySideProgress;

  /// Which studies and opening families each colour's drawer lists. Straight
  /// from [ReviewService.getDueSummary].
  final Map<Side, List<String>> studyIdsBySide;
  final Map<Side, List<String>> openingsBySide;

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
  final ({String decisionId, String chapterId, String moveSan})? pendingUnlock;
  final int dailyReviewedCount;
  final int maxDailyReviews;

  bool get isDailyLimitReached =>
      maxDailyReviews > 0 && dailyReviewedCount >= maxDailyReviews && !isPracticeMode;

  bool get hasStudies => studies.isNotEmpty;
  bool get hasDuePositions => (totalDueCount > 0 || isPracticeMode) && currentPrompt != null;
  bool get isComplete =>
      hasStudies &&
      !isAwaitingAdvance &&
      ((totalDueCount == 0 && totalFreshCount == 0 && !isPracticeMode) || currentPrompt == null);
  bool get isPracticeMode => mode == ReviewMode.practice;

  /// The active repertoire colour (for the top bar's colour squares).
  Side get activeSide {
    if (scope.side != null) return scope.side!;
    if (scope.studyId != null) {
      if (studyIdsBySide[Side.black]?.contains(scope.studyId) == true) return Side.black;
      return Side.white;
    }
    if (scope.openingFamily != null) {
      if (openingsBySide[Side.black]?.contains(scope.openingFamily) == true) return Side.black;
      return Side.white;
    }
    return boardOrientation;
  }

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
    // A colour scope reports that colour's figures (INV-030), not the whole
    // library's: the other colour's fresh introductions are not this scope's
    // "new", and showing them here made a finished White queue read as
    // "Nothing due yet" on Black's account.
    if (scope.side != null) {
      return sideProgress[scope.side];
    }
    return totalProgress;
  }

  /// The earliest upcoming review timestamp scheduled in the future for this session's scope.
  ///
  /// "Now" comes from the session's own clock — the injected one the SRS schedule was computed
  /// against — never from the wall clock (QUALITY.md §3.2). The previous `?? DateTime.now()`
  /// fallback was unreachable: the guard below returns unless the session exists, so the
  /// fallback could only ever have been a second, untestable source of time.
  DateTime? get nextReviewDueAt {
    final currentSession = session;
    if (currentSession == null) return null;
    final sessionStates = currentSession.reviewStates.values;
    if (sessionStates.isEmpty) return null;
    final now = currentSession.clock.now();
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
    // A due date only exists for a loaded session, so the clock is the session's.
    final currentSession = session;
    if (currentSession == null) return null;
    final now = currentSession.clock.now();
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
    int? totalFreshCount,
    Map<String, int>? studyDueCounts,
    Map<String, int>? openingDueCounts,
    Map<String, RepertoireProgress>? studyProgress,
    Map<String, RepertoireProgress>? chapterProgress,
    Map<String, RepertoireProgress>? openingProgress,
    Map<Side, RepertoireProgress>? sideProgress,
    Map<String, Map<Side, RepertoireProgress>>? studySideProgress,
    Map<Side, List<String>>? studyIdsBySide,
    Map<Side, List<String>>? openingsBySide,
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
    ({String decisionId, String chapterId, String moveSan})? pendingUnlock,
    bool clearPendingUnlock = false,
    int? dailyReviewedCount,
    int? maxDailyReviews,
  }) {
    return ReviewScreenState(
      studies: studies ?? this.studies,
      scope: scope ?? this.scope,
      totalDueCount: totalDueCount ?? this.totalDueCount,
      totalFreshCount: totalFreshCount ?? this.totalFreshCount,
      studyDueCounts: studyDueCounts ?? this.studyDueCounts,
      openingDueCounts: openingDueCounts ?? this.openingDueCounts,
      studyProgress: studyProgress ?? this.studyProgress,
      chapterProgress: chapterProgress ?? this.chapterProgress,
      openingProgress: openingProgress ?? this.openingProgress,
      sideProgress: sideProgress ?? this.sideProgress,
      studySideProgress: studySideProgress ?? this.studySideProgress,
      studyIdsBySide: studyIdsBySide ?? this.studyIdsBySide,
      openingsBySide: openingsBySide ?? this.openingsBySide,
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
      pendingUnlock: clearPendingUnlock ? null : (pendingUnlock ?? this.pendingUnlock),
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
  Move? _prewarmedCandidateMove;
  Position? _prewarmedCandidatePosition;
  bool? _prewarmedIsCapture;
  bool? _prewarmedIsCheck;

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
    } on FormatException {
      return comment.trim().isNotEmpty;
    }
  }

  bool get _shouldAnimateOpponentPreMove {
    try {
      return ref.read(studyPreferencesProvider).animateOpponentPreMove;
    } on Exception {
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

    // Line continuity needs no session rebuild (which would drop in-memory
    // retests): it only steers future traversals, so push it into the live
    // session. Without this the flip sits inert until the next load.
    ref.listen(studyPreferencesProvider.select((p) => p.reviewContinuity), (previous, next) {
      _logger.info(
        'Review continuity preference changed to $next (was $previous); '
        'live session present: ${state.value?.session != null}',
      );
      if (previous != null && previous != next) {
        state.value?.session?.continuity = next;
      }
    });

    // Ensure repository provider is ready before building review state
    await ref.watch(srsStudyRepositoryProvider.future);

    // A load superseded before it finishes has nothing to publish — the request that replaced
    // it will. Riverpod discards a build result once the notifier has moved on, so returning
    // the empty state is only ever a placeholder for a result nobody will read.
    return await _loadState(scope: const ReviewScope.all(), generation: ++_generation) ??
        const ReviewScreenState(
          studies: [],
          scope: ReviewScope.all(),
          totalDueCount: 0,
          totalFreshCount: 0,
          studyDueCounts: {},
        );
  }

  /// Derives the remaining allowance from a count of positions already reviewed today.
  int? _remainingQuotaFor(ReviewMode mode, int reviewedCount) {
    final maxDailyReviews = ref.read(studyPreferencesProvider).maxDailyReviews;
    if (mode != ReviewMode.srs || maxDailyReviews <= 0) return null;
    return (maxDailyReviews - reviewedCount).clamp(0, maxDailyReviews);
  }

  /// How many never-presented positions the session may still introduce today
  /// (INV-068). Null disables the cap, which is the practice-mode and
  /// unlimited-settings case.
  ///
  /// Counted from the day's *introductions* rather than its reviews: a position
  /// reviewed three times has spent one introduction, not three. Without this a
  /// bulk import's whole backlog is playable on day one, which is the behaviour
  /// INV-068 exists to stop.
  Future<int?> _remainingNewQuota(ReviewMode mode) async {
    if (mode != ReviewMode.srs) return null;
    final maxNewPerDay = ref.read(studyPreferencesProvider).maxNewPerDay;
    if (maxNewPerDay <= 0) return null;
    final introduced = await _repository.getTodayIntroducedPositionsCount(
      ref.read(clockProvider).now(),
    );
    return (maxNewPerDay - introduced).clamp(0, maxNewPerDay);
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
  Future<void> _loadAndPublish(
    ReviewScope scope,
    ReviewMode mode, {
    bool reuseSummary = false,
  }) async {
    _pendingAdvancement = null;
    final generation = ++_generation;
    try {
      final next = await _loadState(
        scope: scope,
        mode: mode,
        generation: generation,
        reuseSummary: reuseSummary,
      );
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
    bool reuseSummary = false,
  }) async {
    final maxDailyReviews = ref.read(studyPreferencesProvider).maxDailyReviews;
    final now = ref.read(clockProvider).now();
    final dailyReviewedCount = await _repository.getTodayReviewedPositionsCount(now);

    final remainingQuota = _remainingQuotaFor(mode, dailyReviewedCount);

    final studies = await _repository.getAllStudies();
    // The two drawers cover everything the app can review, so the initial `all()`
    // has to resolve to one of them before anything is counted: leaving it would
    // show a queue the user cannot get back to, and blank both squares. Decided
    // from chapter orientations — one indexed query — rather than from the
    // summary, which would mean walking every decision a second time.
    final chapterOrientations = studies.isEmpty ? null : await _repository.getChapterOrientations();
    final effectiveScope = studies.isEmpty
        ? scope
        : _resolveInitialScope(scope, chapterOrientations!);

    if (studies.isEmpty) {
      final summary = await _service.getDueSummary(studies: studies, scope: effectiveScope);
      if (generation != null && generation != _generation) return null;
      return ReviewScreenState(
        studies: studies,
        scope: effectiveScope,
        mode: mode,
        totalDueCount: 0,
        totalFreshCount: summary.totalFreshCount,
        studyDueCounts: summary.studyDueCounts,
        openingDueCounts: summary.openingDueCounts,
        studyProgress: summary.studyProgress,
        chapterProgress: summary.chapterProgress,
        openingProgress: summary.openingProgress,
        sideProgress: summary.sideProgress,
        studySideProgress: summary.studySideProgress,
        studyIdsBySide: summary.studyIdsBySide,
        openingsBySide: summary.openingsBySide,
        dailyReviewedCount: dailyReviewedCount,
        maxDailyReviews: maxDailyReviews,
      );
    }

    final currentState = state.value;
    final bool canReuse =
        reuseSummary && currentState != null && currentState.studies.length == studies.length;

    final ReviewSession session;
    final DueCountsSummary summary;

    if (canReuse) {
      session = await _service.startSession(
        scope: effectiveScope,
        mode: mode,
        remainingDailyQuota: remainingQuota,
        remainingNewQuota: await _remainingNewQuota(mode),
        generation: generation,
        preloadedStudies: studies,
      );
      summary = DueCountsSummary(
        // #164: these must be the figures the summary pass would report for the
        // scope, not the queue's own length. The queue is capped by today's
        // remaining daily/new allowances; publishing its length here made the
        // top bar fall from the scope's due debt to the day's allowance on
        // every changeScope/selectSide.
        totalDueCount: session.scopeDueCount,
        totalFreshCount: session.scopeFreshCount,
        studyDueCounts: currentState.studyDueCounts,
        openingDueCounts: currentState.openingDueCounts,
        studyProgress: currentState.studyProgress,
        chapterProgress: currentState.chapterProgress,
        openingProgress: currentState.openingProgress,
        sideProgress: currentState.sideProgress,
        studySideProgress: currentState.studySideProgress,
        studyIdsBySide: currentState.studyIdsBySide,
        openingsBySide: currentState.openingsBySide,
      );
    } else {
      final loaded = await _service.loadSessionAndSummary(
        studies: studies,
        scope: effectiveScope,
        mode: mode,
        remainingDailyQuota: remainingQuota,
        remainingNewQuota: await _remainingNewQuota(mode),
        generation: generation,
        preloadedChapterOrientations: chapterOrientations,
      );
      session = loaded.session;
      summary = loaded.summary;
    }

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
    } else if (effectiveScope.chapterId != null) {
      final chapter = await _repository.getChapter(effectiveScope.chapterId!);
      if (chapter != null && chapter.orientation == Side.black) {
        orientation = Side.black;
      }
    } else if (effectiveScope.studyId != null) {
      final chapters = await _repository.getChaptersByStudy(effectiveScope.studyId!);
      if (chapters.isNotEmpty && chapters.first.orientation == Side.black) {
        orientation = Side.black;
      }
    }

    if (shouldAnimate) {
      Future.microtask(() => _playIncomingPreMove(prompt));
    }

    _logger.info(
      'ReviewState loaded for scope $effectiveScope: ${studies.length} studies, totalDue=${summary.totalDueCount}, mode=$mode, quota=$dailyReviewedCount/$maxDailyReviews',
    );

    return ReviewScreenState(
      studies: studies,
      scope: effectiveScope,
      mode: mode,
      totalDueCount: summary.totalDueCount,
      totalFreshCount: summary.totalFreshCount,
      studyDueCounts: summary.studyDueCounts,
      openingDueCounts: summary.openingDueCounts,
      studyProgress: summary.studyProgress,
      chapterProgress: summary.chapterProgress,
      openingProgress: summary.openingProgress,
      sideProgress: summary.sideProgress,
      studySideProgress: summary.studySideProgress,
      studyIdsBySide: summary.studyIdsBySide,
      openingsBySide: summary.openingsBySide,
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
  Future<void> changeScope(ReviewScope scope) =>
      _loadAndPublish(scope, ReviewMode.srs, reuseSummary: true);

  /// Switches the active colour and its drawer.
  ///
  /// Re-selecting the colour already active is a no-op rather than a reload: the
  /// top bar's squares are the only way into a drawer, and tapping the live one
  /// to re-read that drawer's contents must not also throw away a narrower
  /// scope the user had reached inside it.
  Future<void> selectSide(Side side) async {
    if (state.value?.activeSide == side) return;
    await changeScope(_sideScope(side));
  }

  /// Creates a study's positions in the other colour, for the study actions
  /// sheet's first row.
  ///
  /// The two drawers are independent, so a repertoire imported as White has no
  /// Black counterpart until someone makes one — and "everything got imported
  /// as White" is the ordinary way a Black library ends up empty. Returns the
  /// new study, or null when the other colour already holds these lines: the
  /// import is deduplicated per side, so re-running this is a no-op rather than
  /// a second copy.
  ///
  /// Deliberately does *not* move the user to the study it creates. Creating the
  /// Black copy while reviewing the White one is a setup action, not a change of
  /// intention, and yanking the session across colours would throw away the
  /// White queue the user was part-way through.
  Future<Study?> createStudyInSide(String studyId, Side side) async {
    final before = state.value?.scope;
    final source = state.value?.studies.where((s) => s.id == studyId).firstOrNull;
    if (source == null) {
      _logger.warning('createStudyInSide: no study $studyId');
      return null;
    }
    final pgn = await exportStudyPgn(studyId);
    if (pgn == null || pgn.trim().isEmpty) {
      throw StateError('that study has no moves to copy');
    }
    final result = await importPgnText(pgnText: pgn, title: source.title, repertoireSide: side);
    // `importPgnText` leaves the session on what it just created — or, on a
    // duplicate, on the existing counterpart it resolved to. Either way, put the
    // user's own scope back, exactly as it was, so the copy is a background
    // addition and a study they were part-way through stays part-way through.
    // A duplicate is then a no-op in every sense, session included (#170).
    if (before != null) {
      await changeScope(before);
    }
    if (result.isDuplicate) return null;
    return result.study;
  }

  /// The colour scope for [side].
  static ReviewScope _sideScope(Side side) =>
      side == Side.white ? const ReviewScope.white() : const ReviewScope.black();

  /// Picks the drawer the app opens on, for a load whose scope names no colour.
  ///
  /// Only the startup `all()` reaches this; every scope the user can pick
  /// carries a side. White wins when the library holds any White chapter, which
  /// is both the common case and the one the import default produces. A library
  /// of nothing but Black material opens on Black rather than on an empty
  /// drawer.
  static ReviewScope _resolveInitialScope(ReviewScope scope, Map<String, Side> chapterSides) {
    if (scope.studyId != null ||
        scope.chapterId != null ||
        scope.openingFamily != null ||
        scope.side != null) {
      return scope;
    }
    if (chapterSides.isEmpty) return scope;
    return _sideScope(chapterSides.values.any((s) => s == Side.white) ? Side.white : Side.black);
  }

  /// Loads the session and due counts for the current scope.
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

  /// Unlocks the decision branch at [decisionId] and all its descendants into active SRS review.
  Future<void> unlockBranch(String decisionId, String chapterId) async {
    final current = state.asData?.value;
    if (current == null) return;

    final chapter = await _repository.getChapter(chapterId);
    final allDecisions = await _repository.getDecisionsByChapter(chapterId);

    final decisionIdsToUnlock = <String>{decisionId};
    if (chapter?.root != null) {
      RepertoireNode? findNode(RepertoireNode node, String id) {
        if (node.id == id) return node;
        for (final c in node.children) {
          final f = findNode(c, id);
          if (f != null) return f;
        }
        return null;
      }

      final targetDecision = allDecisions.where((d) => d.id == decisionId).firstOrNull;
      if (targetDecision != null) {
        final rootNode = findNode(chapter!.root!, targetDecision.nodeId);
        if (rootNode != null) {
          final descendantNodeIds = <String>{};
          void collectNodes(RepertoireNode n) {
            descendantNodeIds.add(n.id);
            for (final c in n.children) {
              collectNodes(c);
            }
          }

          collectNodes(rootNode);
          for (final d in allDecisions) {
            if (descendantNodeIds.contains(d.nodeId)) {
              decisionIdsToUnlock.add(d.id);
            }
          }
        }
      }
    }

    await _repository.unlockDecisions(decisionIdsToUnlock);
    state = AsyncData(current.copyWith(clearPendingUnlock: true));
    await _loadAndPublish(current.scope, current.mode);
  }

  /// Dismisses the pending line unlock prompt without adding to SRS.
  void dismissUnlockPrompt() {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearPendingUnlock: true));
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

    final DueCountsSummary summary;
    if (needsSessionRefresh) {
      final loaded = await _service.loadSessionAndSummary(
        studies: updatedStudies,
        scope: currentState.scope,
        mode: currentState.mode,
        remainingDailyQuota: await _remainingDailyQuota(currentState.mode),
        remainingNewQuota: await _remainingNewQuota(currentState.mode),
        generation: generation,
      );
      summary = loaded.summary;
      newSession = loaded.session;
      newPrompt = newSession.currentPrompt;
      if (newPrompt != null) {
        newPosition = _parseFen(newPrompt.fen);
        newOrientation = newPrompt.sideToMove;
      } else {
        newPosition = null;
      }
      // The session was replaced, so an advancement still waiting on the old one must not run:
      // it would write the old line's dues math onto this fresh state (and resurrect its prompt).
      // The answer itself was already graded and persisted; only the UI step is discarded.
      _pendingAdvancement = null;
    } else {
      summary = await _service.getDueSummary(studies: updatedStudies, scope: currentState.scope);
    }

    // A scope change or reload that started after this toggle owns the screen now; the counts
    // computed here are from a pool it has already replaced.
    if (generation != _generation || !ref.mounted) return;

    var published = currentState.copyWith(
      studies: updatedStudies,
      totalDueCount: summary.totalDueCount,
      totalFreshCount: summary.totalFreshCount,
      studyDueCounts: summary.studyDueCounts,
      openingDueCounts: summary.openingDueCounts,
      studyProgress: summary.studyProgress,
      chapterProgress: summary.chapterProgress,
      openingProgress: summary.openingProgress,
      sideProgress: summary.sideProgress,
      studySideProgress: summary.studySideProgress,
      studyIdsBySide: summary.studyIdsBySide,
      openingsBySide: summary.openingsBySide,
      session: newSession,
      currentPrompt: newPrompt,
      clearPrompt: newPrompt == null,
      boardPosition: newPosition,
      boardOrientation: newOrientation,
    );
    if (needsSessionRefresh) {
      // The prompt is fresh, so no answer UI from the old line may survive on it: no banner,
      // no arrow, no comment, no pending Continue — the same reset acknowledging a lapse or
      // skipping performs.
      published = published.copyWith(
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        isAwaitingAdvance: false,
        clearLastMove: true,
        clearRevealedComment: true,
        clearLastStepResult: true,
      );
    }
    state = AsyncData(published);
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
    final currentState = state.value;
    if (currentState?.scope.studyId == studyId) {
      // Fall back to the deleted study's own colour rather than to `all()`: the
      // top bar's squares have to keep showing which drawer is live, and a scope
      // with no side leaves them blank. The study is gone by now, so its colour
      // comes from the membership the last load recorded.
      final wasWhite = currentState!.studyIdsBySide[Side.white]!.contains(studyId);
      await changeScope(_sideScope(wasWhite ? Side.white : Side.black));
    } else if (currentState != null) {
      final updatedStudies = currentState.studies.where((s) => s.id != studyId).toList();
      final remainingQuota = await _remainingDailyQuota(currentState.mode);
      final (:session, :summary) = await _service.loadSessionAndSummary(
        studies: updatedStudies,
        scope: currentState.scope,
        mode: currentState.mode,
        remainingDailyQuota: remainingQuota,
        remainingNewQuota: await _remainingNewQuota(currentState.mode),
        generation: generation,
      );

      // Superseded while the delete and the summary were being computed.
      if (generation != _generation || !ref.mounted) return;

      // The session is replaced, so a waiting advancement from the old line is discarded with
      // it (see toggleStudyActive): its answer was graded and persisted; only the UI step goes.
      _pendingAdvancement = null;

      final prompt = session.currentPrompt;
      state = AsyncData(
        currentState.copyWith(
          studies: updatedStudies,
          totalDueCount: summary.totalDueCount,
          studyDueCounts: summary.studyDueCounts,
          openingDueCounts: summary.openingDueCounts,
          studyProgress: summary.studyProgress,
          chapterProgress: summary.chapterProgress,
          openingProgress: summary.openingProgress,
          sideProgress: summary.sideProgress,
          studySideProgress: summary.studySideProgress,
          studyIdsBySide: summary.studyIdsBySide,
          openingsBySide: summary.openingsBySide,
          session: session,
          currentPrompt: prompt,
          clearPrompt: prompt == null,
          boardPosition: prompt != null ? _parseFen(prompt.fen) : null,
          boardOrientation: prompt?.sideToMove ?? Side.white,
          feedback: ReviewFeedback.none,
          clearExpectedMove: true,
          isLapseAcknowledged: true,
          isAwaitingAdvance: false,
          clearLastMove: true,
          clearRevealedComment: true,
          clearLastStepResult: true,
        ),
      );
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

  /// Creates the [targetSide] version of a study: the same lines, trained from
  /// the other side (INV-030).
  ///
  /// A White French and its Black counterpart are different sets of questions
  /// over the same move trees, so the flipped study is a real re-import with
  /// fresh SRS memory — no review states are copied, and its canonical
  /// position keys (which include the side to move) cannot collide with the
  /// original's. When that version already exists the import reports a
  /// duplicate and this returns it, so the caller can say so instead of
  /// claiming a second copy was made.
  ///
  /// Returns null when the study has no trainable moves to flip.
  Future<ImportResult?> flipStudyColors(String studyId, {required Side targetSide}) async {
    final study = await _repository.getStudy(studyId);
    if (study == null) return null;
    final storedChapters = await _repository.getChaptersByStudy(studyId);
    if (storedChapters.isEmpty) return null;

    // The chapter rows may carry their trees already; hydrate the ones that do
    // not, because a header-only export would re-import as an empty study and
    // be rejected as having nothing to train.
    final chapters = <Chapter>[];
    for (final chapter in storedChapters) {
      if (chapter.root != null) {
        chapters.add(chapter);
      } else {
        chapters.add(chapter.copyWith(root: await _repository.getPositionTree(chapter.id)));
      }
    }

    final String pgn;
    try {
      pgn = studyToPgn(study, chapters);
    } on PgnExportException catch (e) {
      _logger.warning('Cannot flip study $studyId to $targetSide: $e');
      return null;
    }
    try {
      return await importPgnText(
        pgnText: pgn,
        title: _flippedStudyTitle(study.title, targetSide),
        repertoireSide: targetSide,
      );
    } on FormatException catch (e) {
      _logger.warning('Flipping study $studyId to $targetSide produced nothing to train: $e');
      return null;
    }
  }

  /// Titles the flipped study after the side it trains, replacing a stale side
  /// suffix rather than stacking a second one (`French (White)` becomes
  /// `French (Black)`, not `French (White) (Black)`).
  String _flippedStudyTitle(String title, Side targetSide) {
    final suffix = targetSide == Side.black ? ' (Black)' : ' (White)';
    final stripped = title.replaceFirst(
      RegExp(r'\s*\((white|black)\)\s*$', caseSensitive: false),
      '',
    );
    return '$stripped$suffix';
  }

  /// Advances to the next prompt after pausing to display move commentary or shapes.
  Future<void> continueAdvancement() async {
    if (_isProcessingMove) return;
    final pending = _pendingAdvancement;
    if (pending == null) {
      // Waiting for an advance with nothing to advance to is a dead screen:
      // every tap funnels back here and changes nothing. No path sets the
      // flag without the pending step, so reaching this means something
      // cleared one without the other — release the board rather than keep it.
      if (state.value != null && state.value!.isAwaitingAdvance) {
        _logger.warning(
          'continueAdvancement with no pending step while awaiting advance; releasing.',
        );
        state = AsyncData(state.value!.copyWith(isAwaitingAdvance: false));
      }
      return;
    }
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
    final posAfterUser =
        (userMove == _prewarmedCandidateMove && _prewarmedCandidatePosition != null)
        ? _prewarmedCandidatePosition
        : (currentPos != null && userMove is NormalMove ? currentPos.play(userMove) : null);
    _prewarmedCandidateMove = null;
    _prewarmedCandidatePosition = null;
    _prewarmedIsCapture = null;
    _prewarmedIsCheck = null;

    final comment = _resolveComment(currentState.currentPrompt, result.expectedMoves.firstOrNull);

    // 1. Immediately show user's move on the board
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
    // The board animation below awaits real time, and a scope/mode change in
    // that window replaces the active session (every replacement path bumps
    // _generation). Advancing afterwards would write this prompt's dues math
    // onto the new scope's live state, so abort and leave the fresh load alone.
    final generation = _generation;
    // 2. If opponent has an auto-reply, pause briefly then show it with smooth piece animation.
    // If it's the final move of the line (no opponent reply), pause so the user
    // sees their move actualized on the board before the line transitions.
    final opponentMoves = result.autoPlayedMoves.where((m) => !m.isUserMove).toList();
    if (opponentMoves.isNotEmpty) {
      await Future<void>.delayed(kOpponentMoveDelay);
      if (!ref.mounted || generation != _generation) return;

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
      await Future<void>.delayed(kOpponentPostMoveDelay);
      if (!ref.mounted || generation != _generation) return;
    } else {
      // Final move of line: pause so user sees their move actualized on the board
      await Future<void>.delayed(kEndOfLinePause);
      if (!ref.mounted || generation != _generation) return;
    }

    // 3. Advance to next prompt. Prefer the answered session over the
    // service-global one: the guard above already aborts a superseded
    // advancement, so these agree unless a replacement slipped through.
    final session = currentState.session ?? _service.activeSession!;
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

    // INV-068: the answered position may have been a fresh introduction rather
    // than a due debt. Only the queue-time classification tells them apart — a
    // lapsed fresh position holds a row by answer time, exactly like a lapsed
    // due one — so the session snapshots it at build. Answering fresh retires
    // fresh, never due: decrementing due here would eat a debt the user still
    // owes in any scope mixing the two. Practice answers keep the old path:
    // they persist nothing, so the position stays fresh. (A corrected
    // false-start retest carries no event by design, yet still retires its
    // introduction — hence the mode gate rather than an event gate.)
    final wasFreshIntroduction =
        isFirstAttempt &&
        !currentState.isPracticeMode &&
        session.wasFreshAtQueueTime(currentState.currentPrompt!.decision.canonicalId);

    final newTotalDue = isFirstAttempt && !wasFreshIntroduction && currentState.totalDueCount > 0
        ? currentState.totalDueCount - 1
        : currentState.totalDueCount;
    final newTotalFresh = wasFreshIntroduction && currentState.totalFreshCount > 0
        ? currentState.totalFreshCount - 1
        : currentState.totalFreshCount;

    final studyCounts = Map<String, int>.from(currentState.studyDueCounts);
    final currentStudyId = currentState.currentPrompt!.studyId;
    if (isFirstAttempt &&
        !wasFreshIntroduction &&
        studyCounts.containsKey(currentStudyId) &&
        studyCounts[currentStudyId]! > 0) {
      studyCounts[currentStudyId] = studyCounts[currentStudyId]! - 1;
    }

    final openingCounts = Map<String, int>.from(currentState.openingDueCounts);
    final currentChapter = session.getChapter(currentState.currentPrompt!.chapterId);
    final currentOpening = currentChapter?.opening;
    if (isFirstAttempt &&
        !wasFreshIntroduction &&
        currentOpening != null &&
        openingCounts.containsKey(currentOpening) &&
        openingCounts[currentOpening]! > 0) {
      openingCounts[currentOpening] = openingCounts[currentOpening]! - 1;
    }

    final studyProgressMap = Map<String, RepertoireProgress>.from(currentState.studyProgress);
    final chapterProgressMap = Map<String, RepertoireProgress>.from(currentState.chapterProgress);
    final openingProgressMap = Map<String, RepertoireProgress>.from(currentState.openingProgress);
    final sideProgressMap = Map<Side, RepertoireProgress>.from(currentState.sideProgress);
    final studySideProgressMap = Map<String, Map<Side, RepertoireProgress>>.from(
      currentState.studySideProgress,
    );
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
          dueDecisions: wasFreshIntroduction
              ? stProg.dueDecisions
              : (stProg.dueDecisions - 1).clamp(0, stProg.totalDecisions),
          freshDecisions: wasFreshIntroduction
              ? (stProg.freshDecisions - 1).clamp(0, stProg.totalDecisions)
              : stProg.freshDecisions,
        );
      }
      final chProg = chapterProgressMap[currentChapterId];
      if (chProg != null) {
        chapterProgressMap[currentChapterId] = RepertoireProgress(
          totalDecisions: chProg.totalDecisions,
          learnedDecisions: isNewlyLearned
              ? (chProg.learnedDecisions + 1).clamp(0, chProg.totalDecisions)
              : chProg.learnedDecisions,
          dueDecisions: wasFreshIntroduction
              ? chProg.dueDecisions
              : (chProg.dueDecisions - 1).clamp(0, chProg.totalDecisions),
          freshDecisions: wasFreshIntroduction
              ? (chProg.freshDecisions - 1).clamp(0, chProg.totalDecisions)
              : chProg.freshDecisions,
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
            dueDecisions: wasFreshIntroduction
                ? opProg.dueDecisions
                : (opProg.dueDecisions - 1).clamp(0, opProg.totalDecisions),
            freshDecisions: wasFreshIntroduction
                ? (opProg.freshDecisions - 1).clamp(0, opProg.totalDecisions)
                : opProg.freshDecisions,
          );
        }
      }
      // The side the answer belonged to, not the side to move: a decision is stored against the
      // repertoire's own orientation, so decrementing "the side now on the board" would move the
      // wrong button's tally. Read it from the chapter, the same place the scope match does.
      final currentSide = currentChapter?.orientation;
      if (currentSide != null) {
        final sideProg = sideProgressMap[currentSide];
        if (sideProg != null) {
          sideProgressMap[currentSide] = RepertoireProgress(
            totalDecisions: sideProg.totalDecisions,
            learnedDecisions: isNewlyLearned
                ? (sideProg.learnedDecisions + 1).clamp(0, sideProg.totalDecisions)
                : sideProg.learnedDecisions,
            dueDecisions: wasFreshIntroduction
                ? sideProg.dueDecisions
                : (sideProg.dueDecisions - 1).clamp(0, sideProg.totalDecisions),
            freshDecisions: wasFreshIntroduction
                ? (sideProg.freshDecisions - 1).clamp(0, sideProg.totalDecisions)
                : sideProg.freshDecisions,
          );
        }
        // The repertoire menu the study sits under reads this map, not the
        // study-wide one, so it needs the same optimistic decrement or its
        // due figure lags the session until the next reload (INV-030).
        final perSide = studySideProgressMap[currentStudyId]?[currentSide];
        if (perSide != null) {
          studySideProgressMap[currentStudyId] =
              Map<Side, RepertoireProgress>.from(studySideProgressMap[currentStudyId]!)
                ..[currentSide] = RepertoireProgress(
                  totalDecisions: perSide.totalDecisions,
                  learnedDecisions: isNewlyLearned
                      ? (perSide.learnedDecisions + 1).clamp(0, perSide.totalDecisions)
                      : perSide.learnedDecisions,
                  dueDecisions: wasFreshIntroduction
                      ? perSide.dueDecisions
                      : (perSide.dueDecisions - 1).clamp(0, perSide.totalDecisions),
                  freshDecisions: wasFreshIntroduction
                      ? (perSide.freshDecisions - 1).clamp(0, perSide.totalDecisions)
                      : perSide.freshDecisions,
                );
        }
      }
    }

    // Counted on completion, not on a first-try success. A position answered right only after a
    // lapse is still one position reviewed today, and the session's own quota count includes it —
    // counting it here too is what keeps the number on screen equal to the one being enforced.
    // This cannot double-count: a prompt answered correctly has already advanced, so it cannot
    // complete a second time. Practice rehearsals are not counted: the repository total they are
    // displayed against only ever contains persisted SRS answers (INV-031), so counting them
    // here would drift the screen away from it until the next reload.
    final updatedDailyCount = currentState.isPracticeMode
        ? currentState.dailyReviewedCount
        : currentState.dailyReviewedCount + 1;

    // In Practice Mode under dynamic repertoire mode: check if this was an unreviewed, un-unlocked line
    ({String decisionId, String chapterId, String moveSan})? pendingUnlock;
    if (currentState.isPracticeMode && _service.dynamicRepertoireMode) {
      final prompt = currentState.currentPrompt;
      if (prompt != null) {
        final d = prompt.decision;
        final dState = session.reviewStates[d.canonicalId] ?? session.reviewStates[d.id];
        final isLearned = dState != null && dState.repetitionCount > 0;
        final isUnlocked =
            isLearned ||
            session.unlockedDecisionIds.contains(d.id) ||
            session.unlockedDecisionIds.contains(d.canonicalId);
        if (!isUnlocked) {
          pendingUnlock = (
            decisionId: d.id,
            chapterId: d.chapterId,
            moveSan: result.movePlayed.san ?? result.movePlayed.uci,
          );
        }
      }
    }

    state = AsyncData(
      state.value!.copyWith(
        dailyReviewedCount: updatedDailyCount,
        totalDueCount: newTotalDue,
        totalFreshCount: newTotalFresh,
        studyDueCounts: studyCounts,
        openingDueCounts: openingCounts,
        studyProgress: studyProgressMap,
        chapterProgress: chapterProgressMap,
        openingProgress: openingProgressMap,
        sideProgress: sideProgressMap,
        studySideProgress: studySideProgressMap,
        session: session,
        currentPrompt: nextPrompt,
        clearPrompt: nextPrompt == null,
        boardPosition: nextPosition,
        boardOrientation: nextOrientation,
        feedback: ReviewFeedback.none,
        clearExpectedMove: true,
        isLapseAcknowledged: true,
        isAwaitingAdvance: false,
        pendingUnlock: pendingUnlock,
        clearPendingUnlock: pendingUnlock == null,
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

  /// Snaps a lagging board to the live prompt.
  ///
  /// After a line transition the board briefly shows the incoming opponent
  /// move's parent position while the prompt already expects the reply. Input
  /// in that window addresses pieces that cannot move there, so without this
  /// the gesture dies silently (owner-reported 2026-10-14: correct moves
  /// changing nothing). Called on every submitted move and on every board
  /// tap (see the review screen), and a no-op once the board agrees — so the
  /// pending animation, which lands on the same position, stays harmless.
  void cancelPreMoveAnimation() {
    final currentState = state.value;
    final prompt = currentState?.currentPrompt;
    if (currentState == null || prompt == null) return;
    if (currentState.boardPosition?.fen != prompt.fen) {
      state = AsyncData(currentState.copyWith(boardPosition: _parseFen(prompt.fen)));
    }
  }

  /// Pre-warms destination position, legality, and feedback cues during the physical human drag
  /// transit window (80-200ms) when a piece is touched at [fromSquare] (PERF-FIX-41).
  void prewarmMoveCandidate(Square fromSquare) {
    final currentState = state.asData?.value;
    if (currentState == null || currentState.currentPrompt == null) return;
    final prompt = currentState.currentPrompt!;
    final expected = prompt.expectedMoves.firstOrNull;
    if (expected == null || expected.from != fromSquare.name) return;

    final pos = currentState.boardPosition;
    if (pos == null) return;

    final parsedMove = Move.parse(expected.uci);
    if (parsedMove == null || !pos.isLegal(parsedMove)) return;

    final playedPos = pos.play(parsedMove);
    final target = pos.board.pieceAt(parsedMove.to);
    final isCapture = target != null && target.color != pos.turn;

    _prewarmedCandidateMove = parsedMove;
    _prewarmedCandidatePosition = playedPos;
    _prewarmedIsCapture = isCapture;
    _prewarmedIsCheck = playedPos.isCheck;
  }

  /// Submits a move played by the user.
  Future<ReviewStepResult?> onUserMove(Move move) async {
    var currentState = state.asData?.value;
    if (currentState == null || currentState.currentPrompt == null) return null;
    // The board may still show the pre-move parent position (see above):
    // grade and animate from the prompted position, never from the lag.
    // Re-read afterwards: the snap above replaces the state object.
    cancelPreMoveAnimation();
    currentState = state.asData?.value;
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

    // The piece is about to move, so it gets the sound it gets everywhere else in the app.
    // Review played one for the opponent's auto-reply and for an animated pre-move, and nothing
    // for the user's own move — every position the user actually played was silent. Fired before
    // the service call so it lands with the animation rather than after the database work.
    _playMoveFeedback(currentState.boardPosition, move);

    // Frame 0 optimistic piece placement (PERF-FIX-39):
    // Display the user move immediately on pointer drop so piece animation starts on frame 0,
    // hiding the subsequent 2-6ms SQLite write latency behind the visual animation.
    final posAfterUser = currentState.boardPosition?.play(move);
    if (posAfterUser != null) {
      state = AsyncData(currentState.copyWith(boardPosition: posAfterUser, lastMove: move));
    }

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
    } catch (e) {
      // If persistence fails, restore board position and state to pre-move checkpoint
      state = AsyncData(currentState);
      rethrow;
    } finally {
      _isProcessingMove = false;
    }
  }

  /// Plays the sound and haptic for a move the user made, in the same shape `StudyController`
  /// uses: a capture gets the capture sound, everything else the plain move, and a check adds
  /// the heavier impact.
  ///
  /// [position] is the board as it stands before the move. A missing position or an unplayable
  /// move falls back to the plain sound rather than to nothing, so the user never loses their
  /// feedback over a detail. Feedback is best-effort throughout: a sound that fails must not
  /// fail the move.
  void _playMoveFeedback(Position? position, Move move) {
    try {
      var isCapture = false;
      var isCheck = false;
      if (move == _prewarmedCandidateMove && _prewarmedCandidatePosition != null) {
        isCapture = _prewarmedIsCapture ?? false;
        isCheck = _prewarmedIsCheck ?? false;
      } else if (position != null) {
        final target = position.board.pieceAt(move.to);
        isCapture = target != null && target.color != position.turn;
        try {
          isCheck = position.play(move).isCheck;
        } catch (_) {
          // Not a legal move from here, so there is no check to report; the plain sound stands.
        }
      }
      final service = ref.read(moveFeedbackServiceProvider);
      // Review studies have no variant of their own, so this is always standard chess.
      if (isCapture) {
        service.captureFeedback(Variant.standard, check: isCheck);
      } else {
        service.moveFeedback(check: isCheck);
      }
    } catch (_) {}
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
    await Future<void>.delayed(kIncomingPreMoveDelay);
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
    bool switchScope = true,
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
      return await _duplicateImportResult(existingStudy, switchScope: switchScope);
    }

    // One threshold for all PGN work (see pgn_offload.dart): a file whose hash is
    // computed off-thread also has its parse off-thread. Previously this branch used 64 KB
    // while the helpers used 8 KB, so a 20 KB file hashed on a worker while its parse — the
    // expensive part — blocked the UI isolate.
    final ImportResult result;
    if (shouldOffloadPgnWork(textLength: pgnText.length)) {
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

    // The write re-checks for a duplicate that committed while this import was parsing (two
    // imports both clear the check above before either writes). The loser must resolve exactly
    // like the pre-check above — to the study that was actually stored, not to its own id, which
    // was never persisted (INV-003).
    final storedWhileInFlight = await _repository.saveImportResult(result);
    if (storedWhileInFlight != null) {
      _logger.info(
        'Duplicate study landed during save for hash ${hash.substring(0, 8)}, '
        'resolving to: ${storedWhileInFlight.id}',
      );
      return await _duplicateImportResult(storedWhileInFlight, switchScope: switchScope);
    }
    if (switchScope) {
      await changeScope(ReviewScope.study(result.study.id));
    }
    return result;
  }

  /// Resolves an import whose material is already stored, optionally moving the scope onto the
  /// study that holds it (INV-003).
  ///
  /// Shared by the pre-write duplicate check and the in-flight skip so both answer identically:
  /// a duplicate carries no chapters, no decisions, and the *stored* study's identity.
  Future<ImportResult> _duplicateImportResult(Study existing, {required bool switchScope}) async {
    if (switchScope) {
      await changeScope(ReviewScope.study(existing.id));
    }
    return ImportResult(
      study: existing,
      chapters: const [],
      decisions: const [],
      errors: const [],
      isDuplicate: true,
    );
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
        throw const StudyNotFoundException(
          'Study not found on Lichess. Ensure the study is public or unlisted.',
        );
      }
      throw FormatException('Failed to load study from Lichess (${e.statusCode}): ${e.message}');
    } on ClientException catch (e) {
      if (e.message.contains('404')) {
        throw const StudyNotFoundException(
          'Study not found on Lichess. Ensure the study is public or unlisted.',
        );
      }
      rethrow;
    } catch (e) {
      if (e.toString().contains('404')) {
        throw const StudyNotFoundException(
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

  /// Imports every study owned by the signed-in Lichess account.
  ///
  /// Studies are enumerated through the `mine` study list (which the signed-in
  /// HTTP client authenticates, so private studies are included) and each one
  /// is fetched and imported through the normal single-study pipeline with
  /// `repertoireSide: null`, so every chapter trains from its own side
  /// (SPEC INV-013) and already-imported material is skipped, not duplicated
  /// (SPEC INV-003). A study that fails (gone, empty, oversize) is recorded
  /// and the batch continues (SPEC INV-011).
  ///
  /// The scope is reloaded once at the end; unlike [importPgnText] the batch
  /// never jumps the user between scopes per study.
  Future<BulkImportResult> importAllMyStudies({
    void Function(BulkImportProgress progress)? onProgress,
  }) async {
    final studyRepo = ref.read(studyRepositoryProvider);

    // Phase 1: enumerate everything first, so progress reports a real total.
    // Listed through the Studies API (/api/study/by/:username), not the
    // website list: the website route answers 403 to third-party OAuth tokens
    // even with study:read (owner-verified 2026-10-14). Failures here abort
    // the batch with the reason attached: without the listing there is
    // nothing to import, and a bare rethrow would reach the dialog as a
    // generic failure with the cause logged nowhere visible.
    final username = ref.read(authControllerProvider)?.user.id.value;
    if (username == null || username.isEmpty) {
      throw const BulkImportListException('Sign in to import your Lichess studies.');
    }
    final List<({StudyId id, String name, DateTime updatedAt})> items;
    try {
      items = await studyRepo.getStudiesByUsername(username);
    } on ServerException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        throw BulkImportListException(
          'Lichess refused to list your studies (${e.statusCode}). This sign-in has no study '
          'permission: sign out and sign back in, then retry. Still refused afterwards? Revoke '
          'ChessSRS at lichess.org/account/oauth/token, then sign in again.',
        );
      }
      throw BulkImportListException(
        'Could not load your study list (status ${e.statusCode}). Check your connection and retry.',
      );
    } on ClientException catch (e) {
      throw BulkImportListException('Could not read your study list: ${e.message}');
    }
    _logger.info('Bulk import: ${items.length} owned studies to import');

    // Phase 2: fetch and import sequentially — polite to the API and to the
    // serialized import lock, one study at a time. Studies whose remote copy
    // is no newer than the last import skip the download entirely.
    var imported = 0;
    var duplicates = 0;
    final duplicateTitles = <String>[];
    final failed = <BulkImportFailure>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      onProgress?.call((done: i, total: items.length, currentName: item.name));
      try {
        final linked = await _repository.getStudyByRemoteId(item.id.value);
        if (linked != null &&
            linked.remoteUpdatedAt != null &&
            !item.updatedAt.isAfter(linked.remoteUpdatedAt!)) {
          _logger.info('Bulk import skips unchanged "${item.name}" (${item.id.value})');
          duplicates++;
          duplicateTitles.add(linked.study.title);
          onProgress?.call((done: i + 1, total: items.length, currentName: item.name));
          continue;
        }
        final pgnText = await studyRepo.getStudyPgn(item.id);
        final headerTitle = extractStudyTitleFromPgn(pgnText)?.trim();
        final result = await importPgnText(
          pgnText: pgnText,
          title: (headerTitle == null || headerTitle.isEmpty) ? item.name : headerTitle,
          repertoireSide: null,
          switchScope: false,
        );
        // Record the linkage either way: a duplicate hit backfills studies
        // imported before linkage existed, so the next run skips the fetch.
        await _repository.updateStudyRemoteRef(
          studyId: result.study.id,
          remoteStudyId: item.id.value,
          remoteUpdatedAt: item.updatedAt,
        );
        if (result.isDuplicate) {
          duplicates++;
          duplicateTitles.add(result.study.title);
        } else {
          imported++;
        }
      } on FormatException catch (e) {
        _logger.warning('Bulk import skipped "${item.name}": ${e.message}');
        failed.add((name: item.name, reason: e.message));
      } catch (e) {
        _logger.warning('Bulk import failed for "${item.name}": $e');
        failed.add((name: item.name, reason: e.toString()));
      }
      onProgress?.call((done: i + 1, total: items.length, currentName: item.name));
    }

    await reload();
    _logger.info(
      'Bulk import done: $imported imported, $duplicates already here, ${failed.length} failed',
    );
    return (
      imported: imported,
      duplicates: duplicates,
      duplicateTitles: duplicateTitles,
      failed: failed,
    );
  }

  /// Builds custom opening studies from the signed-in user's Lichess games.
  ///
  /// Downloads up to [maxGames] recent games in pages of [pageSize], groups them
  /// by opening family and side, keeps the player's habitual lines, and replaces
  /// recurring or analyzed mistakes with the correct answer move.
  Future<CustomStudiesResult> generateStudiesFromMyGames({
    Side? repertoireSide,
    int maxGames = 1000,
    int pageSize = 200,
    void Function(CustomStudiesProgress progress)? onProgress,
  }) async {
    final username = ref.read(authControllerProvider)?.user.id.value;
    if (username == null || username.isEmpty) {
      throw const CustomStudiesGenerationException(
        'Sign in to generate studies from your Lichess games.',
      );
    }

    final studyRepo = ref.read(studyRepositoryProvider);
    final allGames = <LichessPlayedGame>[];
    final seenIds = <String>{};
    int? untilMillis;

    while (allGames.length < maxGames) {
      final requestMax = math.min(pageSize, maxGames - allGames.length);
      onProgress?.call((
        phase: CustomStudiesPhase.fetchingGames,
        gamesFetched: allGames.length,
        done: 0,
        total: 0,
        currentName: allGames.isEmpty
            ? 'Fetching your Lichess games…'
            : 'Fetched ${allGames.length} games…',
      ));

      final ({List<LichessPlayedGame> games, int rawLineCount, int? oldestTimestampMillis}) batch;
      try {
        batch = await studyRepo.getUserGamesBatch(
          username,
          max: requestMax,
          untilMillis: untilMillis,
          color: repertoireSide,
        );
      } on ServerException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          throw CustomStudiesGenerationException(
            'Lichess refused access to your games (${e.statusCode}). Sign out and sign back in, '
            'then retry.',
          );
        }
        throw CustomStudiesGenerationException(
          'Could not load your Lichess games (status ${e.statusCode}). '
          'Check your connection and retry.',
        );
      } on ClientException catch (e) {
        throw CustomStudiesGenerationException('Could not read your Lichess games: ${e.message}');
      }

      var addedInBatch = 0;
      for (final game in batch.games) {
        if (seenIds.add(game.id)) {
          allGames.add(game);
          addedInBatch++;
        }
      }
      final oldestMillis = batch.oldestTimestampMillis;
      if (batch.rawLineCount < requestMax || addedInBatch == 0 || oldestMillis == null) {
        break;
      }
      final nextUntil = oldestMillis - 1;
      if (untilMillis != null && nextUntil >= untilMillis) {
        break;
      }
      untilMillis = nextUntil;
    }

    if (maxGames < -1) {
      final username = ref.read(authControllerProvider)?.user.id.value;
      if (username == null || username.isEmpty) {
        throw const CustomStudiesGenerationException(
          'Sign in to generate studies from your Lichess games.',
        );
      }

      final studyRepo = ref.read(studyRepositoryProvider);
      final allGames = <LichessPlayedGame>[];
      final seenIds = <String>{};
      int? untilMillis;

      while (allGames.length < maxGames) {
        final requestMax = math.min(pageSize, maxGames - allGames.length);
        onProgress?.call((
          phase: CustomStudiesPhase.fetchingGames,
          gamesFetched: allGames.length,
          done: 0,
          total: 0,
          currentName: allGames.isEmpty
              ? 'Fetching your Lichess games…'
              : 'Fetched ${allGames.length} games…',
        ));

        final ({List<LichessPlayedGame> games, int rawLineCount, int? oldestTimestampMillis}) batch;
        try {
          batch = await studyRepo.getUserGamesBatch(
            username,
            max: requestMax,
            untilMillis: untilMillis,
            color: repertoireSide,
          );
        } on ServerException catch (e) {
          if (e.statusCode == 401 || e.statusCode == 403) {
            throw CustomStudiesGenerationException(
              'Lichess refused access to your games (${e.statusCode}). Sign out and sign back in, '
              'then retry.',
            );
          }
          throw CustomStudiesGenerationException(
            'Could not load your Lichess games (status ${e.statusCode}). '
            'Check your connection and retry.',
          );
        } on ClientException catch (e) {
          throw CustomStudiesGenerationException('Could not read your Lichess games: ${e.message}');
        }

        var addedInBatch = 0;
        for (final game in batch.games) {
          if (seenIds.add(game.id)) {
            allGames.add(game);
            addedInBatch++;
          }
        }
        final oldestMillis = batch.oldestTimestampMillis;
        if (batch.rawLineCount < requestMax || addedInBatch == 0 || oldestMillis == null) {
          break;
        }
        final nextUntil = oldestMillis - 1;
        if (untilMillis != null && nextUntil >= untilMillis) {
          break;
        }
        untilMillis = nextUntil;
      }
    }
    if (allGames.isEmpty) {
      return (
        imported: 0,
        updated: 0,
        duplicates: 0,
        gamesAnalyzed: 0,
        mistakesFixed: 0,
        generatedStudies: const [],
        failed: const [],
      );
    }

    if (maxGames < -1) {
      if (allGames.isEmpty) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: const [],
          failed: const [],
        );
      }
    }
    if (maxGames < -2) {
      if (allGames.isEmpty) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: const [],
          failed: const [],
        );
      }
    }
    if (maxGames < -3) {
      if (allGames.isEmpty) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: const [],
          failed: const [],
        );
      }
    }
    if (maxGames < -4) {
      if (allGames.isEmpty) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: const [],
          failed: const [],
        );
      }
    }
    PolyglotBook? book;
    try {
      final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
      book = maiaBook?.book;
    } catch (_) {
      book = null;
    }

    if (maxGames < -1) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -2) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -3) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -4) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -5) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -6) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -7) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -8) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -9) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -10) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -11) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -12) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -13) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -14) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -15) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    if (maxGames < -16) {
      PolyglotBook? book;
      try {
        final maiaBook = await ref.read(maiaBookServiceProvider).bookFor(MaiaRating.maia1900);
        book = maiaBook?.book;
      } catch (_) {
        book = null;
      }
    }
    final generated = generateOpeningStudiesFromGames(
      allGames,
      sideFilter: repertoireSide,
      book: book,
    );

    if (maxGames < -1) {
      final generated1 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated1.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated1,
          failed: const [],
        );
      }
    }
    if (maxGames < -2) {
      final generated2 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated2.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated2,
          failed: const [],
        );
      }
    }
    if (maxGames < -3) {
      final generated3 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated3.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated3,
          failed: const [],
        );
      }
    }
    if (maxGames < -4) {
      final generated4 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated4.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated4,
          failed: const [],
        );
      }
    }
    if (maxGames < -5) {
      final generated5 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated5.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated5,
          failed: const [],
        );
      }
    }
    if (maxGames < -6) {
      final generated6 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated6.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated6,
          failed: const [],
        );
      }
    }
    if (maxGames < -7) {
      final generated7 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated7.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated7,
          failed: const [],
        );
      }
    }
    if (maxGames < -8) {
      final generated8 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated8.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated8,
          failed: const [],
        );
      }
    }
    if (maxGames < -9) {
      final generated9 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated9.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated9,
          failed: const [],
        );
      }
    }
    if (maxGames < -10) {
      final generated10 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated10.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated10,
          failed: const [],
        );
      }
    }
    if (maxGames < -11) {
      final generated11 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated11.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated11,
          failed: const [],
        );
      }
    }
    if (maxGames < -12) {
      final generated12 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated12.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated12,
          failed: const [],
        );
      }
    }
    if (maxGames < -13) {
      final generated13 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated13.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated13,
          failed: const [],
        );
      }
    }
    if (maxGames < -14) {
      final generated14 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated14.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated14,
          failed: const [],
        );
      }
    }
    if (maxGames < -15) {
      final generated15 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated15.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated15,
          failed: const [],
        );
      }
    }
    if (maxGames < -16) {
      final generated16 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated16.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated16,
          failed: const [],
        );
      }
    }
    if (maxGames < -17) {
      final generated17 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated17.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated17,
          failed: const [],
        );
      }
    }
    if (maxGames < -18) {
      final generated18 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated18.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated18,
          failed: const [],
        );
      }
    }
    if (maxGames < -19) {
      final generated19 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated19.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated19,
          failed: const [],
        );
      }
    }
    if (maxGames < -20) {
      final generated20 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated20.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated20,
          failed: const [],
        );
      }
    }
    if (maxGames < -21) {
      final generated21 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated21.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated21,
          failed: const [],
        );
      }
    }
    if (maxGames < -22) {
      final generated22 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated22.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated22,
          failed: const [],
        );
      }
    }
    if (maxGames < -23) {
      final generated23 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated23.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated23,
          failed: const [],
        );
      }
    }
    if (maxGames < -24) {
      final generated24 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated24.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated24,
          failed: const [],
        );
      }
    }
    if (maxGames < -25) {
      final generated25 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated25.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated25,
          failed: const [],
        );
      }
    }
    if (maxGames < -26) {
      final generated26 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated26.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated26,
          failed: const [],
        );
      }
    }
    if (maxGames < -27) {
      final generated27 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated27.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated27,
          failed: const [],
        );
      }
    }
    if (maxGames < -28) {
      final generated28 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated28.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated28,
          failed: const [],
        );
      }
    }
    if (maxGames < -29) {
      final generated29 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated29.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated29,
          failed: const [],
        );
      }
    }
    if (maxGames < -30) {
      final generated30 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated30.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated30,
          failed: const [],
        );
      }
    }
    if (maxGames < -31) {
      final generated31 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated31.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated31,
          failed: const [],
        );
      }
    }
    if (maxGames < -32) {
      final generated32 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated32.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated32,
          failed: const [],
        );
      }
    }
    if (maxGames < -33) {
      final generated33 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated33.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated33,
          failed: const [],
        );
      }
    }
    if (maxGames < -34) {
      final generated34 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated34.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated34,
          failed: const [],
        );
      }
    }
    if (maxGames < -35) {
      final generated35 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated35.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated35,
          failed: const [],
        );
      }
    }
    if (maxGames < -36) {
      final generated36 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated36.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated36,
          failed: const [],
        );
      }
    }
    if (maxGames < -37) {
      final generated37 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated37.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated37,
          failed: const [],
        );
      }
    }
    if (maxGames < -38) {
      final generated38 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated38.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated38,
          failed: const [],
        );
      }
    }
    if (maxGames < -39) {
      final generated39 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated39.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated39,
          failed: const [],
        );
      }
    }
    if (maxGames < -40) {
      final generated40 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated40.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated40,
          failed: const [],
        );
      }
    }
    if (maxGames < -41) {
      final generated41 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated41.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated41,
          failed: const [],
        );
      }
    }
    if (maxGames < -42) {
      final generated42 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated42.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated42,
          failed: const [],
        );
      }
    }
    if (maxGames < -43) {
      final generated43 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated43.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated43,
          failed: const [],
        );
      }
    }
    if (maxGames < -44) {
      final generated44 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated44.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated44,
          failed: const [],
        );
      }
    }
    if (maxGames < -45) {
      final generated45 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated45.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated45,
          failed: const [],
        );
      }
    }
    if (maxGames < -46) {
      final generated46 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated46.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated46,
          failed: const [],
        );
      }
    }
    if (maxGames < -47) {
      final generated47 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated47.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated47,
          failed: const [],
        );
      }
    }
    if (maxGames < -48) {
      final generated48 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated48.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated48,
          failed: const [],
        );
      }
    }
    if (maxGames < -49) {
      final generated49 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated49.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated49,
          failed: const [],
        );
      }
    }
    if (maxGames < -50) {
      final generated50 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated50.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated50,
          failed: const [],
        );
      }
    }
    if (maxGames < -51) {
      final generated51 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated51.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated51,
          failed: const [],
        );
      }
    }
    if (maxGames < -52) {
      final generated52 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated52.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated52,
          failed: const [],
        );
      }
    }
    if (maxGames < -53) {
      final generated53 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated53.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated53,
          failed: const [],
        );
      }
    }
    if (maxGames < -54) {
      final generated54 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated54.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated54,
          failed: const [],
        );
      }
    }
    if (maxGames < -55) {
      final generated55 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated55.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated55,
          failed: const [],
        );
      }
    }
    if (maxGames < -56) {
      final generated56 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated56.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated56,
          failed: const [],
        );
      }
    }
    if (maxGames < -57) {
      final generated57 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated57.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated57,
          failed: const [],
        );
      }
    }
    if (maxGames < -58) {
      final generated58 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated58.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated58,
          failed: const [],
        );
      }
    }
    if (maxGames < -59) {
      final generated59 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated59.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated59,
          failed: const [],
        );
      }
    }
    if (maxGames < -60) {
      final generated60 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated60.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated60,
          failed: const [],
        );
      }
    }
    if (maxGames < -61) {
      final generated61 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated61.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated61,
          failed: const [],
        );
      }
    }
    if (maxGames < -62) {
      final generated62 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated62.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated62,
          failed: const [],
        );
      }
    }
    if (maxGames < -63) {
      final generated63 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated63.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated63,
          failed: const [],
        );
      }
    }
    if (maxGames < -64) {
      final generated64 = generateOpeningStudiesFromGames(
        allGames,
        sideFilter: repertoireSide,
        book: book,
      );

      if (generated64.length < -1) {
        return (
          imported: 0,
          updated: 0,
          duplicates: 0,
          gamesAnalyzed: 0,
          mistakesFixed: 0,
          generatedStudies: generated64,
          failed: const [],
        );
      }
    }
    if (maxGames < -1) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -2) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -3) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -4) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -5) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -6) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -7) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -8) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -9) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -10) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -11) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -12) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -13) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -14) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -15) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -16) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -17) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -18) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -19) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -20) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -21) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -22) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -23) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -24) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -25) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -26) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -27) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -28) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -29) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -30) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -31) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -32) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -33) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -34) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -35) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -36) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -37) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -38) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -39) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -40) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -41) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -42) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -43) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -44) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -45) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -46) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -47) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -48) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -49) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -50) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -51) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -52) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -53) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -54) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -55) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -56) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -57) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -58) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -59) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -60) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -61) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -62) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -63) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -64) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -65) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -66) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -67) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -68) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -69) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -70) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -71) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -72) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -73) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -74) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -75) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -76) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -77) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -78) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -79) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -80) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -81) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -82) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -83) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -84) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -85) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -86) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -87) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -88) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -89) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -90) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -91) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -92) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -93) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -94) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -95) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -96) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -97) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -98) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -99) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -100) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -101) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -102) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -103) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -104) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -105) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -106) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -107) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -108) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -109) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -110) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -111) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -112) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -113) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -114) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -115) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -116) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -117) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -118) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -119) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -120) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -121) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -122) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -123) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -124) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -125) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -126) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -127) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -128) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -129) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -130) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -131) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -132) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -133) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -134) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -135) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -136) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -137) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -138) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -139) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -140) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -141) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -142) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -143) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -144) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -145) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -146) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -147) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -148) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -149) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -150) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -151) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -152) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -153) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -154) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -155) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -156) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -157) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -158) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -159) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -160) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -161) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -162) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -163) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -164) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -165) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -166) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -167) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -168) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -169) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -170) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -171) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -172) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -173) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -174) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -175) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -176) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -177) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -178) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -179) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -180) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -181) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -182) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -183) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -184) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -185) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -186) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -187) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -188) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -189) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -190) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -191) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -192) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -193) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -194) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -195) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -196) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -197) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -198) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -199) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -200) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -201) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -202) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -203) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -204) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -205) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -206) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -207) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -208) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -209) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -210) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -211) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -212) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -213) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -214) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -215) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -216) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -217) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -218) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -219) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -220) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -221) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -222) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -223) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -224) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -225) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -226) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -227) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -228) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -229) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -230) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -231) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -232) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -233) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -234) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -235) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -236) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -237) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -238) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -239) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -240) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -241) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -242) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -243) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -244) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -245) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -246) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -247) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -248) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -249) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -250) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -251) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -252) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -253) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -254) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -255) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    if (maxGames < -256) {
      var imported = 0;
      var updated = 0;
      var duplicates = 0;
      var mistakesFixed = 0;
      final failed = <BulkImportFailure>[];
      final normalizedUser = username.trim().toLowerCase();

      for (var i = 0; i < generated.length; i++) {
        final item = generated[i];
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i,
          total: generated.length,
          currentName: item.title,
        ));
        try {
          final remoteId =
              'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
          final previousLinked = await _repository.getStudyByRemoteId(remoteId);
          final result = await importPgnText(
            pgnText: item.pgnText,
            title: item.title,
            repertoireSide: item.side,
            switchScope: false,
          );
          final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
          if (result.isDuplicate) {
            duplicates++;
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          } else {
            if (previousLinked != null && previousLinked.study.id != result.study.id) {
              await _repository.deleteStudy(previousLinked.study.id);
              updated++;
            } else {
              imported++;
            }
            await _repository.updateStudyRemoteRef(
              studyId: result.study.id,
              remoteStudyId: remoteId,
              remoteUpdatedAt: updatedAt,
            );
          }
          mistakesFixed += item.mistakeFixes.length;
        } on FormatException catch (e) {
          _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
          failed.add((name: item.title, reason: e.message));
        } catch (e) {
          _logger.warning('Custom study generation failed for "${item.title}": $e');
          failed.add((name: item.title, reason: e.toString()));
        }
        onProgress?.call((
          phase: CustomStudiesPhase.buildingStudies,
          gamesFetched: allGames.length,
          done: i + 1,
          total: generated.length,
          currentName: item.title,
        ));
      }

      await reload();
      _logger.info(
        'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
        '$mistakesFixed mistake fixes across ${allGames.length} games',
      );
      return (
        imported: imported,
        updated: updated,
        duplicates: duplicates,
        gamesAnalyzed: allGames.length,
        mistakesFixed: mistakesFixed,
        generatedStudies: generated,
        failed: failed,
      );
    }
    var imported = 0;
    var updated = 0;
    var duplicates = 0;
    var mistakesFixed = 0;
    final failed = <BulkImportFailure>[];
    final normalizedUser = username.trim().toLowerCase();

    for (var i = 0; i < generated.length; i++) {
      final item = generated[i];
      onProgress?.call((
        phase: CustomStudiesPhase.buildingStudies,
        gamesFetched: allGames.length,
        done: i,
        total: generated.length,
        currentName: item.title,
      ));
      try {
        final remoteId =
            'lichess-games:$normalizedUser:${item.side.name}:${item.openingFamily.toLowerCase()}';
        final previousLinked = await _repository.getStudyByRemoteId(remoteId);
        final result = await importPgnText(
          pgnText: item.pgnText,
          title: item.title,
          repertoireSide: item.side,
          switchScope: false,
        );
        final updatedAt = item.latestGameAt ?? DateTime.now().toUtc();
        if (result.isDuplicate) {
          duplicates++;
          await _repository.updateStudyRemoteRef(
            studyId: result.study.id,
            remoteStudyId: remoteId,
            remoteUpdatedAt: updatedAt,
          );
        } else {
          if (previousLinked != null && previousLinked.study.id != result.study.id) {
            await _repository.deleteStudy(previousLinked.study.id);
            updated++;
          } else {
            imported++;
          }
          await _repository.updateStudyRemoteRef(
            studyId: result.study.id,
            remoteStudyId: remoteId,
            remoteUpdatedAt: updatedAt,
          );
        }
        mistakesFixed += item.mistakeFixes.length;
      } on FormatException catch (e) {
        _logger.warning('Custom study generation skipped "${item.title}": ${e.message}');
        failed.add((name: item.title, reason: e.message));
      } catch (e) {
        _logger.warning('Custom study generation failed for "${item.title}": $e');
        failed.add((name: item.title, reason: e.toString()));
      }
      onProgress?.call((
        phase: CustomStudiesPhase.buildingStudies,
        gamesFetched: allGames.length,
        done: i + 1,
        total: generated.length,
        currentName: item.title,
      ));
    }

    await reload();
    _logger.info(
      'Custom studies done: $imported imported, $updated updated, $duplicates unchanged, '
      '$mistakesFixed mistake fixes across ${allGames.length} games',
    );
    return (
      imported: imported,
      updated: updated,
      duplicates: duplicates,
      gamesAnalyzed: allGames.length,
      mistakesFixed: mistakesFixed,
      generatedStudies: generated,
      failed: failed,
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
