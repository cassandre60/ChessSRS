// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('ReviewService');

/// Provider for the application's [Clock].
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Provider for the application's [Scheduler].
final schedulerProvider = Provider<Scheduler>((ref) {
  final type = ref.watch(studyPreferencesProvider.select((p) => p.schedulerType));
  final retention = ref.watch(studyPreferencesProvider.select((p) => p.targetRetention));
  final ease = ref.watch(studyPreferencesProvider.select((p) => p.schedulerEase));
  final scaling = ref.watch(studyPreferencesProvider.select((p) => p.schedulerScaling));

  return switch (type) {
    SchedulerType.fsrs => ChessFsrsScheduler(targetRetention: retention),
    SchedulerType.simple => const SimpleScheduler(),
    SchedulerType.easeScaling => EaseScalingScheduler(ease: ease, scaling: scaling),
  };
});

/// Provider for [ReviewService].
final reviewServiceProvider = Provider<ReviewService>((ref) {
  final repoAsync = ref.watch(srsStudyRepositoryProvider);
  final repo = repoAsync.asData?.value;
  final scheduler = ref.watch(schedulerProvider);
  final clock = ref.watch(clockProvider);
  final reviewOrder = ref.watch(studyPreferencesProvider.select((p) => p.reviewOrder));
  final transposeScope = ref.watch(studyPreferencesProvider.select((p) => p.transposeScope));
  final dynamicRepertoireMode = ref.watch(
    studyPreferencesProvider.select((p) => p.dynamicRepertoireMode),
  );

  if (repo == null) {
    throw StateError('StudyRepository is not yet initialized');
  }

  return ReviewService(
    repository: repo,
    scheduler: scheduler,
    clock: clock,
    reviewOrder: reviewOrder,
    transposeScope: transposeScope,
    dynamicRepertoireMode: dynamicRepertoireMode,
  );
});

/// Application service orchestrating review sessions, local persistence,
/// and SRS updates.
class DueCountsSummary {
  const DueCountsSummary({
    required this.totalDueCount,
    required this.totalFreshCount,
    required this.studyDueCounts,
    required this.openingDueCounts,
    this.studyProgress = const {},
    this.chapterProgress = const {},
    this.openingProgress = const {},
    this.sideProgress = const {},
    this.studySideProgress = const {},
    this.studyIdsBySide = const {},
    this.openingsBySide = const {},
  });

  /// Positions in scope the user has been shown and whose date has arrived.
  ///
  /// Never clamped to the day's remaining allowance. It used to be
  /// `min(totalDue, remainingQuota)`, which put a number that was not a count
  /// of anything under the word "due" in the top bar (INV-068).
  final int totalDueCount;

  /// Positions in scope that have never been presented, and so owe nothing yet.
  final int totalFreshCount;

  final Map<String, int> studyDueCounts;
  final Map<String, int> openingDueCounts;
  final Map<String, RepertoireProgress> studyProgress;
  final Map<String, RepertoireProgress> chapterProgress;
  final Map<String, RepertoireProgress> openingProgress;

  /// Progress over the chapters trained from each side, for the drawer's two
  /// repertoire buttons. Always carries both sides, so a button can render its
  /// memory bar at zero instead of guessing whether it has any material.
  final Map<Side, RepertoireProgress> sideProgress;

  /// Progress per study partitioned by the side its chapters train, so each
  /// repertoire menu shows only its own side's figures (INV-030). A study
  /// training both sides appears under both menus; a study with no decisions
  /// has no entry. The per-side figures sum to the study-wide ones.
  final Map<String, Map<Side, RepertoireProgress>> studySideProgress;

  /// Sides trained by [studyId]. Empty when the study has no decisions.
  Set<Side> sidesForStudy(String studyId) => studySideProgress[studyId]?.keys.toSet() ?? const {};

  /// Progress for [studyId] restricted to [side], or zero when the study
  /// trains nothing from that side.
  RepertoireProgress studyProgressForSide(String studyId, Side side) =>
      studySideProgress[studyId]?[side] ?? RepertoireProgress.zero;

  /// Which studies and which opening families belong to each colour, so a drawer
  /// can list only its own. Grouped by chapter rather than by decision: a study
  /// with nothing due yet still has to appear in the drawer, and a paused study
  /// has to stay findable so it can be resumed.
  final Map<Side, List<String>> studyIdsBySide;
  final Map<Side, List<String>> openingsBySide;

  /// Due positions for [side], or 0 when the summary predates this field.
  int dueCountForSide(Side side) => sideProgress[side]?.dueDecisions ?? 0;

  /// Never-presented positions for [side] (INV-068).
  int freshCountForSide(Side side) => sideProgress[side]?.freshDecisions ?? 0;

  RepertoireProgress progressForSide(Side side) => sideProgress[side] ?? RepertoireProgress.zero;
}

/// Running tallies for [ReviewService.getDueSummary], extracted so the method stays a
/// short orchestration (queries → accumulate → build) instead of a 250-line god-method.
///
/// Owns every map the summary is built from. Construct with the study/chapter metadata,
/// feed each decision to [add], then take the result from [toSummary]. Nothing here
/// touches the database; all queries stay in [getDueSummary].
class _DueTally {
  _DueTally({
    required this.studies,
    required Map<String, String?> chapterOpenings,
    required Map<String, Side> chapterSides,
    required Map<String, String> chapterStudyIds,
  }) : studyDueCounts = {for (final s in studies) s.id: 0},
       studyTotals = {for (final s in studies) s.id: 0},
       studyLearned = {for (final s in studies) s.id: 0},
       studyFresh = {for (final s in studies) s.id: 0},
       _chapterSides = chapterSides,
       _trimmedOpenings = {
         for (final e in chapterOpenings.entries)
           if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!.trim(),
       } {
    for (final op in chapterOpenings.values) {
      if (op != null && op.trim().isNotEmpty) {
        openingFamilies.add(op.trim());
      }
    }
    openingDueCounts = {for (final op in openingFamilies) op: 0};
    openingTotals = {for (final op in openingFamilies) op: 0};
    openingLearned = {for (final op in openingFamilies) op: 0};
    openingFresh = {for (final op in openingFamilies) op: 0};

    // Which colour each drawer lists. Derived from chapters, not from decisions,
    // and deliberately including paused studies: a drawer that hid a paused study
    // would be a place the user could not go to resume one. Insertion order
    // follows the chapter order, which is the order the library already shows.
    for (final entry in chapterSides.entries) {
      final side = entry.value;
      final studyId = chapterStudyIds[entry.key];
      if (studyId != null && seenStudyPerSide[side]!.add(studyId)) {
        studyIdsBySide[side]!.add(studyId);
      }
      final opening = chapterOpenings[entry.key]?.trim();
      if (opening != null && opening.isNotEmpty && seenOpeningPerSide[side]!.add(opening)) {
        openingsBySide[side]!.add(opening);
      }
    }
    // A study with no chapters is in neither list. It still has to be reachable,
    // so it goes to both: it trains no colour, and hiding it from both drawers
    // would strand it.
    for (final s in studies) {
      final known =
          seenStudyPerSide[Side.white]!.contains(s.id) ||
          seenStudyPerSide[Side.black]!.contains(s.id);
      if (!known) {
        studyIdsBySide[Side.white]!.add(s.id);
        studyIdsBySide[Side.black]!.add(s.id);
      }
    }
  }

  final List<Study> studies;
  final Map<String, Side> _chapterSides;
  final Map<String, String> _trimmedOpenings;

  final Map<String, int> studyDueCounts;
  final Map<String, int> studyTotals;
  final Map<String, int> studyLearned;

  /// Never-presented positions per study (INV-068).
  final Map<String, int> studyFresh;

  // Per-study figures partitioned by side, so each repertoire menu shows
  // only its own side's numbers (INV-030). Keyed sparsely: a side with no
  // decisions in the study has no entry, which is also how the drawer
  // decides which menu a study belongs to.
  final Map<String, Map<Side, int>> studySideTotals = {};
  final Map<String, Map<Side, int>> studySideLearned = {};
  final Map<String, Map<Side, int>> studySideDue = {};
  final Map<String, Map<Side, int>> studySideFresh = {};

  final Map<String, int> chapterTotals = {};
  final Map<String, int> chapterLearned = {};
  final Map<String, int> chapterDue = {};
  final Map<String, int> chapterFresh = {};

  final Set<String> openingFamilies = {};
  late final Map<String, int> openingDueCounts;
  late final Map<String, int> openingTotals;
  late final Map<String, int> openingLearned;
  late final Map<String, int> openingFresh;

  // Per-side tallies for the drawer's two repertoire buttons. Counted over
  // active studies only, so a paused study leaves neither button showing work
  // the review session will not ask for (INV-030).
  final Map<Side, int> sideDueCounts = {Side.white: 0, Side.black: 0};
  final Map<Side, int> sideTotals = {Side.white: 0, Side.black: 0};
  final Map<Side, int> sideLearned = {Side.white: 0, Side.black: 0};
  final Map<Side, int> sideFresh = {Side.white: 0, Side.black: 0};
  // Canonical ids already counted into a side, so a position reached by
  // transposition through two chapters of the same side is due once there —
  // the same rule the all-studies scope applies across studies.
  final Map<Side, Set<String>> sideAccountedCanonicalIds = {
    Side.white: <String>{},
    Side.black: <String>{},
  };

  final Map<Side, List<String>> studyIdsBySide = {Side.white: <String>[], Side.black: <String>[]};
  final Map<Side, List<String>> openingsBySide = {Side.white: <String>[], Side.black: <String>[]};
  final Map<Side, Set<String>> seenStudyPerSide = {Side.white: <String>{}, Side.black: <String>{}};
  final Map<Side, Set<String>> seenOpeningPerSide = {
    Side.white: <String>{},
    Side.black: <String>{},
  };

  int totalDueCount = 0;

  /// Never-presented positions in scope (INV-068), counted the same way as
  /// [totalDueCount]: once per canonical position in a wide scope.
  int totalFreshCount = 0;
  final Set<String> accountedDueCanonicalIds = <String>{};

  void add(
    TallyDecision d, {
    required Map<String, ReviewState> reviewStates,
    required DateTime now,
    required Set<String> activeStudyIds,
    required Map<String, String?> chapterOpenings,
    required Map<String, Side> chapterSides,
    required ReviewScope scope,
    bool dynamicRepertoireMode = false,
    Set<String> unlockedDecisionIds = const {},
  }) {
    final state =
        reviewStates[d.canonicalId] ?? (d.canonicalId == d.id ? null : reviewStates[d.id]);
    final status = dueStatusOf(state, now);
    final isDue = status.isDue;
    final isLearned = state != null && state.repetitionCount > 0;
    final isUnlocked =
        isLearned ||
        unlockedDecisionIds.contains(d.id) ||
        unlockedDecisionIds.contains(d.canonicalId);
    final isFresh = dynamicRepertoireMode
        ? (status.isFresh && isUnlocked)
        : status.isFresh;

    if (studyTotals.containsKey(d.studyId)) {
      studyTotals[d.studyId] = (studyTotals[d.studyId] ?? 0) + 1;
      if (isLearned) {
        studyLearned[d.studyId] = (studyLearned[d.studyId] ?? 0) + 1;
      }
      if (isFresh) {
        studyFresh[d.studyId] = (studyFresh[d.studyId] ?? 0) + 1;
      }
    }

    chapterTotals[d.chapterId] = (chapterTotals[d.chapterId] ?? 0) + 1;
    if (isLearned) {
      chapterLearned[d.chapterId] = (chapterLearned[d.chapterId] ?? 0) + 1;
    }
    if (isFresh) {
      chapterFresh[d.chapterId] = (chapterFresh[d.chapterId] ?? 0) + 1;
    }
    if (isDue) {
      chapterDue[d.chapterId] = (chapterDue[d.chapterId] ?? 0) + 1;
    }

    final opening = _trimmedOpenings[d.chapterId];
    final isActiveStudy = activeStudyIds.contains(d.studyId);
    final side = _chapterSides[d.chapterId] ?? Side.white;

    // Per-study figures partitioned by side (INV-030). Totals and learned
    // cover every study like the study-wide maps do; due counts below cover
    // every due decision the same way studyDueCounts does.
    if (studyTotals.containsKey(d.studyId)) {
      final totalsForStudy = studySideTotals.putIfAbsent(
        d.studyId,
        () => {Side.white: 0, Side.black: 0},
      );
      totalsForStudy[side] = totalsForStudy[side]! + 1;
      if (isLearned) {
        final learnedForStudy = studySideLearned.putIfAbsent(
          d.studyId,
          () => {Side.white: 0, Side.black: 0},
        );
        learnedForStudy[side] = learnedForStudy[side]! + 1;
      }
      if (isFresh) {
        final freshForStudy = studySideFresh.putIfAbsent(
          d.studyId,
          () => {Side.white: 0, Side.black: 0},
        );
        freshForStudy[side] = freshForStudy[side]! + 1;
      }
    }

    if (isActiveStudy && opening != null && opening.isNotEmpty) {
      if (openingTotals.containsKey(opening)) {
        openingTotals[opening] = (openingTotals[opening] ?? 0) + 1;
        if (isLearned) {
          openingLearned[opening] = (openingLearned[opening] ?? 0) + 1;
        }
        if (isFresh) {
          openingFresh[opening] = (openingFresh[opening] ?? 0) + 1;
        }
      }
    }

    if (isActiveStudy) {
      sideTotals[side] = sideTotals[side]! + 1;
      if (isLearned) {
        sideLearned[side] = sideLearned[side]! + 1;
      }
      if (isFresh) {
        sideFresh[side] = sideFresh[side]! + 1;
      }
    }

    if (studyDueCounts.containsKey(d.studyId) && isDue) {
      studyDueCounts[d.studyId] = (studyDueCounts[d.studyId] ?? 0) + 1;
      final dueForStudy = studySideDue.putIfAbsent(d.studyId, () => {Side.white: 0, Side.black: 0});
      dueForStudy[side] = dueForStudy[side]! + 1;
    }

    if (isDue && isActiveStudy && opening != null && opening.isNotEmpty) {
      if (openingDueCounts.containsKey(opening)) {
        openingDueCounts[opening] = (openingDueCounts[opening] ?? 0) + 1;
      }
    }

    if (isDue && isActiveStudy && sideAccountedCanonicalIds[side]!.add(d.canonicalId)) {
      sideDueCounts[side] = sideDueCounts[side]! + 1;
    }

    if (!scope.matches(
      studyId: d.studyId,
      chapterId: d.chapterId,
      openingFamily: opening,
      side: side,
    )) {
      return;
    }

    // A study or chapter scope names one position set, so every row in it is
    // counted; any wider scope counts each canonical position once however many
    // studies and chapters reach it.
    final dedupeByCanonical = scope.studyId == null && scope.chapterId == null;
    final countable =
        !dedupeByCanonical || (isActiveStudy && accountedDueCanonicalIds.add(d.canonicalId));

    if (!countable) return;
    if (isDue) totalDueCount++;
    if (isFresh) totalFreshCount++;
  }

  DueCountsSummary toSummary() {
    final studyProgress = <String, RepertoireProgress>{
      for (final s in studies)
        s.id: RepertoireProgress(
          totalDecisions: studyTotals[s.id] ?? 0,
          learnedDecisions: studyLearned[s.id] ?? 0,
          dueDecisions: studyDueCounts[s.id] ?? 0,
          freshDecisions: studyFresh[s.id] ?? 0,
        ),
    };

    final chapterProgress = <String, RepertoireProgress>{
      for (final chId in chapterTotals.keys)
        chId: RepertoireProgress(
          totalDecisions: chapterTotals[chId] ?? 0,
          learnedDecisions: chapterLearned[chId] ?? 0,
          dueDecisions: chapterDue[chId] ?? 0,
          freshDecisions: chapterFresh[chId] ?? 0,
        ),
    };

    final openingProgress = <String, RepertoireProgress>{
      for (final op in openingFamilies)
        op: RepertoireProgress(
          totalDecisions: openingTotals[op] ?? 0,
          learnedDecisions: openingLearned[op] ?? 0,
          dueDecisions: openingDueCounts[op] ?? 0,
          freshDecisions: openingFresh[op] ?? 0,
        ),
    };

    final sideProgress = <Side, RepertoireProgress>{
      for (final side in Side.values)
        side: RepertoireProgress(
          totalDecisions: sideTotals[side] ?? 0,
          learnedDecisions: sideLearned[side] ?? 0,
          dueDecisions: sideDueCounts[side] ?? 0,
          freshDecisions: sideFresh[side] ?? 0,
        ),
    };

    // Sparse: only sides with at least one decision in the study get an entry.
    final studySideProgress = <String, Map<Side, RepertoireProgress>>{
      for (final entry in studySideTotals.entries)
        entry.key: {
          for (final side in Side.values)
            if ((entry.value[side] ?? 0) > 0)
              side: RepertoireProgress(
                totalDecisions: entry.value[side] ?? 0,
                learnedDecisions: studySideLearned[entry.key]?[side] ?? 0,
                dueDecisions: studySideDue[entry.key]?[side] ?? 0,
                freshDecisions: studySideFresh[entry.key]?[side] ?? 0,
              ),
        },
    };

    return DueCountsSummary(
      totalDueCount: totalDueCount,
      totalFreshCount: totalFreshCount,
      studyDueCounts: studyDueCounts,
      openingDueCounts: openingDueCounts,
      studyProgress: studyProgress,
      chapterProgress: chapterProgress,
      openingProgress: openingProgress,
      sideProgress: sideProgress,
      studySideProgress: studySideProgress,
      studyIdsBySide: studyIdsBySide,
      openingsBySide: openingsBySide,
    );
  }
}

class _LoadedReviewData {
  const _LoadedReviewData({required this.reviewStates, required this.exposureThrottle});

  final Map<String, ReviewState> reviewStates;
  final Map<String, DateTime> exposureThrottle;
}

class ReviewService {
  ReviewService({
    required this.repository,
    this.scheduler = const SimpleScheduler(),
    this.clock = const SystemClock(),
    this.reviewOrder = ReviewOrder.dueDate,
    this.transposeScope = TransposeScope.inScope,
    this.dynamicRepertoireMode = false,
  });

  final StudyRepository repository;
  final Scheduler scheduler;
  final Clock clock;

  /// Presentation order of the due queue. The domain default stays due-date;
  /// the product default (StudyPrefs) is by-line.
  final ReviewOrder reviewOrder;

  /// Whether off-line-but-book moves are accepted (INV-065).
  final TransposeScope transposeScope;

  /// Whether dynamic repertoire branch selection is active.
  final bool dynamicRepertoireMode;

  ReviewSession? _activeSession;
  ReviewSession? get activeSession => _activeSession;

  /// The highest [startSession] generation that has claimed [_activeSession].
  ///
  /// A session start reads the studies, chapters, decisions and review states its scope
  /// needs, which takes long enough for a second request to be made and answered first. The
  /// last one to *finish* is not the last one the user asked for, and this service has a single
  /// active session: whichever start lands here last takes it over, so a stale request silently
  /// replaces the session the screen is showing and every move gets graded against a board the
  /// user is no longer looking at.
  ///
  /// Recording the generation makes the newest request win on request order instead of on
  /// completion order. A superseded start still returns its own session — its caller may be
  /// showing it — it just does not get to be the one that answers moves.
  int _activeGeneration = 0;

  /// Loads every study once plus the chapters of the active ones, optionally filtered.
  ///
  /// The three multi-study scope branches of [startSession] each repeated this same
  /// prologue (getAllStudies → filter isActive → loop getChaptersByStudy), which is
  /// how the three copies drifted. One source of truth now. Returns [allStudies] as
  /// well so the `all()` branch keeps reporting inactive studies in the session
  /// header without issuing a second identical query.
  Future<({List<Study> allStudies, List<Study> activeStudies, List<Chapter> chapters})>
  _loadActiveStudiesAndChapters({
    List<Study>? preloadedStudies,
    bool Function(Chapter)? chapterWhere,
  }) async {
    final allStudies = preloadedStudies ?? await repository.getAllStudies();
    final activeStudies = allStudies.where((s) => s.isActive).toList();
    final chapters = <Chapter>[];
    for (final s in activeStudies) {
      final studyChapters = await repository.getChaptersByStudy(s.id);
      chapters.addAll(chapterWhere == null ? studyChapters : studyChapters.where(chapterWhere));
    }
    return (allStudies: allStudies, activeStudies: activeStudies, chapters: chapters);
  }

  Future<_LoadedReviewData> _loadReviewData({
    required Iterable<String> decisionIds,
    required Iterable<String> canonicalIds,
  }) async {
    final distinctCanonical = canonicalIds.toSet().toList();
    final allQueryIds = {...decisionIds, ...distinctCanonical}.toList();
    final reviewStatesList = await repository.getReviewStatesByIds(allQueryIds);
    final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
    final kStates = await repository.getKnowledgeStatesByCanonicalIds(distinctCanonical);
    for (final k in kStates) {
      reviewStates[k.canonicalId] = k.toReviewState();
    }

    final exposureThrottle = <String, DateTime>{};
    for (final k in kStates) {
      final exposedAt = k.lastExposedAt;
      if (exposedAt != null) {
        exposureThrottle[k.canonicalId] = exposedAt;
      }
    }

    return _LoadedReviewData(reviewStates: reviewStates, exposureThrottle: exposureThrottle);
  }

  /// Starts a new review session for the given [scope].
  ///
  /// Implements targeted scope prefetching (docs/INTEGRATION_MAP.md §From chessrs):
  /// queries and deserializes only the chapters, decisions, and review states
  /// relevant to [scope], optimizing session initialization time and memory footprint.
  ///
  /// [generation] orders competing starts. Callers that can issue a second request before the
  /// first has answered pass a counter that increases with every request; a start whose
  /// generation has already been superseded still returns its session but does not become
  /// [activeSession]. Omitting it claims the slot unconditionally, which is only safe for a
  /// caller that cannot be overtaken.
  Future<ReviewSession> startSession({
    ReviewScope scope = const ReviewScope.all(),
    ReviewMode mode = ReviewMode.srs,
    int? prefetchBatchSize = kDefaultPrefetchBatchSize,
    int prefetchRefillThreshold = kDefaultPrefetchRefillThreshold,
    int? remainingDailyQuota,
    int? remainingNewQuota,
    int? generation,
    List<Study>? preloadedStudies,
    Map<String, ReviewState>? preloadedReviewStates,
    Map<String, DateTime>? preloadedExposureThrottle,
    List<RepertoireDecision>? preloadedAllDecisions,
    Map<String, String?>? preloadedChapterOpenings,
  }) async {
    final List<Study> targetStudies;
    final List<Chapter> targetChapters;
    final List<RepertoireDecision> decisions;

    if (scope.chapterId != null) {
      final chapter = await repository.getChapter(scope.chapterId!);
      final study = chapter != null
          ? (preloadedStudies?.where((s) => s.id == chapter.studyId).firstOrNull ??
                await repository.getStudy(chapter.studyId))
          : null;
      targetStudies = study != null ? [study] : const [];
      final chapterPool = chapter != null ? [chapter] : const <Chapter>[];
      targetChapters = scope.side == null
          ? chapterPool
          : chapterPool.where((c) => c.orientation == scope.side).toList();
      if (targetChapters.isEmpty) {
        decisions = const [];
      } else if (preloadedAllDecisions != null) {
        decisions = preloadedAllDecisions.where((d) => d.chapterId == scope.chapterId!).toList();
      } else {
        decisions = await repository.getDecisionsByChapter(scope.chapterId!);
      }
    } else if (scope.studyId != null) {
      final study =
          preloadedStudies?.where((s) => s.id == scope.studyId!).firstOrNull ??
          await repository.getStudy(scope.studyId!);
      targetStudies = study != null ? [study] : const [];
      final studyChapters = await repository.getChaptersByStudy(scope.studyId!);
      // A drawer names its colour when it builds this scope (INV-030): keep
      // only that side's chapters so the queue, its trees and its states
      // narrow together. Sideless scopes keep the legacy unfiltered set.
      targetChapters = scope.side == null
          ? studyChapters
          : studyChapters.where((c) => c.orientation == scope.side).toList();
      final chapterIds = targetChapters.map((c) => c.id).toSet();
      decisions = (await repository.getDecisionsByStudy(
        scope.studyId!,
      )).where((d) => chapterIds.contains(d.chapterId)).toList();
    } else if (scope.openingFamily != null) {
      final chapterOpenings = preloadedChapterOpenings ?? await repository.getChapterOpenings();
      final matchingChapterIds = chapterOpenings.entries
          .where((e) => e.value?.trim() == scope.openingFamily!.trim())
          .map((e) => e.key)
          .toSet();

      final loaded = await _loadActiveStudiesAndChapters(
        preloadedStudies: preloadedStudies,
        chapterWhere: (c) =>
            matchingChapterIds.contains(c.id) &&
            (scope.side == null || c.orientation == scope.side),
      );
      final activeStudies = loaded.activeStudies;
      targetStudies = activeStudies;
      targetChapters = loaded.chapters;
      decisions = await _getOpeningDecisions(
        targetChapters,
        scope.openingFamily!,
        activeStudies,
        preloadedAllDecisions,
      );
    } else if (scope.side != null) {
      // A side scope spans every active study but keeps only the chapters
      // trained from that side. Resolved here rather than by filtering the
      // whole decision list so the queue, its trees and its states are all
      // narrowed together — a decision whose chapter is excluded would
      // otherwise arrive with no tree to grade against (INV-030).
      final loaded = await _loadActiveStudiesAndChapters(
        preloadedStudies: preloadedStudies,
        chapterWhere: (c) => c.orientation == scope.side,
      );
      targetStudies = loaded.activeStudies;
      targetChapters = loaded.chapters;
      decisions = await _getSideDecisions(targetChapters, preloadedAllDecisions);
    } else {
      final loaded = await _loadActiveStudiesAndChapters(preloadedStudies: preloadedStudies);
      // The session header/progress counts see ALL studies including inactive ones;
      // only the chapters (and hence the queue) are active-scoped.
      targetStudies = loaded.allStudies;
      targetChapters = loaded.chapters;
      decisions = await _getActiveDecisions(loaded.allStudies, preloadedAllDecisions);
    }

    final Map<String, ReviewState> reviewStates;
    final Map<String, DateTime> exposureThrottle;

    if (preloadedReviewStates != null) {
      reviewStates = preloadedReviewStates;
      exposureThrottle = preloadedExposureThrottle ?? const {};
    } else {
      final loaded = await _loadReviewData(
        decisionIds: decisions.map((d) => d.id),
        canonicalIds: decisions.map((d) => d.canonicalId),
      );
      reviewStates = loaded.reviewStates;
      exposureThrottle = loaded.exposureThrottle;
    }

    final engine = ReviewEngine(scheduler: scheduler, clock: clock);
    final unlockedIds = await repository.getUnlockedDecisionIds();

    final session = engine.createSession(
      studies: targetStudies,
      chapters: targetChapters,
      decisions: decisions,
      reviewStates: reviewStates,
      scope: scope,
      mode: mode,
      order: reviewOrder,
      transposeScope: transposeScope,
      dynamicRepertoireMode: dynamicRepertoireMode,
      unlockedDecisionIds: unlockedIds,
      initialExposureThrottle: exposureThrottle,
      prefetchBatchSize: prefetchBatchSize,
      prefetchRefillThreshold: prefetchRefillThreshold,
      remainingDailyQuota: remainingDailyQuota,
      remainingNewQuota: remainingNewQuota,
    );

    // A later request has already claimed the active slot, so this session is only being
    // returned for a caller that is about to discard it.
    if (generation == null || generation >= _activeGeneration) {
      if (generation != null) _activeGeneration = generation;
      _activeSession = session;
    }
    return session;
  }

  /// Submits a user move for the current prompt in the active session.
  ///
  /// Incrementally persists the resulting [ReviewState] and [ReviewEvent]
  /// to SQLite without modifying the study or chapter trees (QUALITY.md §1.5).
  ///
  /// The in-memory session mutation and its persistence are transactional from
  /// the caller's perspective: if the write fails, the session is rolled back to
  /// its pre-answer state before the error is rethrown, so memory never gets
  /// ahead of the persisted store.
  Future<ReviewStepResult> submitMove({
    required String from,
    required String to,
    String? promotion,
  }) async {
    final session = _activeSession;
    if (session == null) {
      throw StateError('No active review session');
    }

    final currentDecision = session.currentPrompt?.decision;
    final checkpoint = session.checkpoint();
    final result = session.submitMove(from: from, to: to, promotion: promotion);

    // Incremental persistence to canonical knowledge state and review event (SRS mode only)
    if (session.mode != ReviewMode.practice) {
      // The throttle is authoritative for every id we are about to write: it was seeded from the
      // store for all in-scope canonical ids, so a null here means "never exposed", not "unknown".
      final throttle = session.exposureThrottle;
      final canonicalId = currentDecision?.canonicalId ?? result.updatedState.decisionId;
      final kState = PositionKnowledgeState.fromReviewState(
        result.updatedState,
        canonicalId: canonicalId,
      ).copyWith(lastExposedAt: throttle[canonicalId]);

      final allKStates = <PositionKnowledgeState>[kState];

      // Persist any secondary states updated via graph effects (contagion, siblings, auto-traversal)
      for (final sideState in result.sideEffectStates) {
        allKStates.add(
          PositionKnowledgeState.fromReviewState(
            sideState,
            canonicalId: sideState.decisionId,
          ).copyWith(lastExposedAt: throttle[sideState.decisionId]),
        );
      }

      try {
        await repository.saveAnswerBatch(knowledgeStates: allKStates, event: result.event);
      } catch (e, st) {
        // Persistence is atomic (single DB transaction). If it fails, undo the
        // in-memory answer so the session and the store remain consistent, then
        // let the caller surface the failure.
        session.restoreCheckpoint(checkpoint);
        _logger.warning('Failed to persist review answer; session rolled back', e, st);
        rethrow;
      }
    }

    return result;
  }

  /// Retries a move attempt on the current prompt after an incorrect answer.
  ///
  /// The retry records no answer of its own — the lapse was already persisted by the attempt it
  /// follows — but walking the continuation updates the exposure state of the later decisions it
  /// passes through. Those updates are persisted here; left only in memory they would be lost on
  /// restart, and the next session would plan as though the continuation had never been walked.
  ///
  /// Transactional in the same way as [submitMove]: a failed write rolls the session back rather
  /// than leaving it ahead of the store.
  Future<ReviewStepResult> retryMove({
    required String from,
    required String to,
    String? promotion,
  }) async {
    final session = _activeSession;
    if (session == null) {
      throw StateError('No active review session');
    }

    final checkpoint = session.checkpoint();
    final result = session.retryMove(from: from, to: to, promotion: promotion);

    if (session.mode != ReviewMode.practice && result.sideEffectStates.isNotEmpty) {
      // Hoisted: the getter copies the throttle map, so calling it per element would copy it once
      // per side effect.
      final throttle = session.exposureThrottle;
      try {
        await repository.saveAnswerBatch(
          knowledgeStates: [
            for (final sideState in result.sideEffectStates)
              PositionKnowledgeState.fromReviewState(
                sideState,
                canonicalId: sideState.decisionId,
              ).copyWith(lastExposedAt: throttle[sideState.decisionId]),
          ],
        );
      } catch (e, st) {
        session.restoreCheckpoint(checkpoint);
        _logger.warning('Failed to persist retry side effects; session rolled back', e, st);
        rethrow;
      }
    }

    return result;
  }

  /// Advances after an incorrect answer has been acknowledged by the user.
  void continueAfterIncorrect() {
    _activeSession?.continueAfterIncorrect();
  }

  /// Skips the active prompt to the end of the session.
  ReviewPrompt? skipCurrentPrompt() {
    return _activeSession?.skip();
  }

  /// Returns the number of due decisions for the given [scope] at current clock time.
  Future<int> getDueCount({ReviewScope scope = const ReviewScope.all()}) async {
    final studies = await repository.getAllStudies();
    final summary = await getDueSummary(studies: studies, scope: scope);
    return summary.totalDueCount;
  }

  /// Loads due count summary and starts a review session in a single database pass,
  /// eliminating redundant decision, review state, and knowledge state queries.
  Future<({ReviewSession session, DueCountsSummary summary})> loadSessionAndSummary({
    required List<Study> studies,
    ReviewScope scope = const ReviewScope.all(),
    ReviewMode mode = ReviewMode.srs,
    int? prefetchBatchSize = kDefaultPrefetchBatchSize,
    int prefetchRefillThreshold = kDefaultPrefetchRefillThreshold,
    int? remainingDailyQuota,
    int? remainingNewQuota,
    int? generation,
    Map<String, Side>? preloadedChapterOrientations,
  }) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final chapterOpenings = await repository.getChapterOpenings();
    final chapterSides = preloadedChapterOrientations ?? await repository.getChapterOrientations();
    final chapterStudyIds = await repository.getChapterStudyIds();

    final tallyDecisions = await repository.getTallyDecisions();
    final loadedData = await _loadReviewData(
      decisionIds: tallyDecisions.map((d) => d.id),
      canonicalIds: tallyDecisions.map((d) => d.canonicalId),
    );

    final now = clock.now();
    final unlockedIds = await repository.getUnlockedDecisionIds();
    final tally = _DueTally(
      studies: studies,
      chapterOpenings: chapterOpenings,
      chapterSides: chapterSides,
      chapterStudyIds: chapterStudyIds,
    );
    for (final d in tallyDecisions) {
      tally.add(
        d,
        reviewStates: loadedData.reviewStates,
        now: now,
        activeStudyIds: activeStudyIds,
        chapterOpenings: chapterOpenings,
        chapterSides: chapterSides,
        scope: scope,
        dynamicRepertoireMode: dynamicRepertoireMode,
        unlockedDecisionIds: unlockedIds,
      );
    }
    final summary = tally.toSummary();

    final session = await startSession(
      scope: scope,
      mode: mode,
      prefetchBatchSize: prefetchBatchSize,
      prefetchRefillThreshold: prefetchRefillThreshold,
      remainingDailyQuota: remainingDailyQuota,
      remainingNewQuota: remainingNewQuota,
      generation: generation,
      preloadedStudies: studies,
      preloadedReviewStates: loadedData.reviewStates,
      preloadedExposureThrottle: loadedData.exposureThrottle,
      preloadedChapterOpenings: chapterOpenings,
    );

    return (session: session, summary: summary);
  }

  /// Returns a batched summary of due counts for all studies, opening hubs, and the given [scope].
  ///
  /// Computes all counts in a single in-memory pass over decisions without reloading
  /// recursive chapter trees or performing N+1 database queries.
  Future<DueCountsSummary> getDueSummary({
    required List<Study> studies,
    ReviewScope scope = const ReviewScope.all(),
  }) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final chapterOpenings = await repository.getChapterOpenings();
    final chapterSides = await repository.getChapterOrientations();
    final chapterStudyIds = await repository.getChapterStudyIds();
    final tallyDecisions = await repository.getTallyDecisions();
    final loadedData = await _loadReviewData(
      decisionIds: tallyDecisions.map((d) => d.id),
      canonicalIds: tallyDecisions.map((d) => d.canonicalId),
    );
    final now = clock.now();
    final unlockedIds = await repository.getUnlockedDecisionIds();

    final tally = _DueTally(
      studies: studies,
      chapterOpenings: chapterOpenings,
      chapterSides: chapterSides,
      chapterStudyIds: chapterStudyIds,
    );
    for (final d in tallyDecisions) {
      tally.add(
        d,
        reviewStates: loadedData.reviewStates,
        now: now,
        activeStudyIds: activeStudyIds,
        chapterOpenings: chapterOpenings,
        chapterSides: chapterSides,
        scope: scope,
        dynamicRepertoireMode: dynamicRepertoireMode,
        unlockedDecisionIds: unlockedIds,
      );
    }
    return tally.toSummary();
  }

  Future<List<RepertoireDecision>> _getActiveDecisions(
    List<Study> studies, [
    List<RepertoireDecision>? preloadedDecisions,
  ]) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final allDecisions = preloadedDecisions ?? await repository.getAllDecisions();
    return allDecisions.where((d) => activeStudyIds.contains(d.studyId)).toList();
  }

  /// Decisions belonging to [chapters], in one pass over the decision table.
  ///
  /// The chapter id set is the authority, not the study: a chapter id names one
  /// study, so an id match cannot pull in a decision from a paused study.
  Future<List<RepertoireDecision>> _getSideDecisions(
    List<Chapter> chapters, [
    List<RepertoireDecision>? preloadedDecisions,
  ]) async {
    if (chapters.isEmpty) return const [];
    final chapterIds = chapters.map((c) => c.id).toSet();
    final allDecisions = preloadedDecisions ?? await repository.getAllDecisions();
    return allDecisions.where((d) => chapterIds.contains(d.chapterId)).toList();
  }

  Future<List<RepertoireDecision>> _getOpeningDecisions(
    List<Chapter> allChapters,
    String openingFamily,
    List<Study> studies, [
    List<RepertoireDecision>? preloadedDecisions,
  ]) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final wanted = openingFamily.trim();
    final matchingChapterIds = allChapters
        .where((c) => (c.opening?.trim() ?? '') == wanted && activeStudyIds.contains(c.studyId))
        .map((c) => c.id)
        .toSet();
    final allDecisions = preloadedDecisions ?? await repository.getAllDecisions();
    return allDecisions.where((d) => matchingChapterIds.contains(d.chapterId)).toList();
  }
}
