// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
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
  final transposeAccept = ref.watch(studyPreferencesProvider.select((p) => p.transposeAccept));

  if (repo == null) {
    throw StateError('StudyRepository is not yet initialized');
  }

  return ReviewService(
    repository: repo,
    scheduler: scheduler,
    clock: clock,
    reviewOrder: reviewOrder,
    transposeAccept: transposeAccept,
  );
});

/// Application service orchestrating review sessions, local persistence,
/// and SRS updates.
class DueCountsSummary {
  const DueCountsSummary({
    required this.totalDueCount,
    required this.studyDueCounts,
    required this.openingDueCounts,
    this.studyProgress = const {},
    this.chapterProgress = const {},
    this.openingProgress = const {},
  });

  final int totalDueCount;
  final Map<String, int> studyDueCounts;
  final Map<String, int> openingDueCounts;
  final Map<String, RepertoireProgress> studyProgress;
  final Map<String, RepertoireProgress> chapterProgress;
  final Map<String, RepertoireProgress> openingProgress;
}

class ReviewService {
  ReviewService({
    required this.repository,
    this.scheduler = const SimpleScheduler(),
    this.clock = const SystemClock(),
    this.reviewOrder = ReviewOrder.dueDate,
    this.transposeAccept = true,
  });

  final StudyRepository repository;
  final Scheduler scheduler;
  final Clock clock;

  /// Presentation order of the due queue. The domain default stays due-date;
  /// the product default (StudyPrefs) is by-line.
  final ReviewOrder reviewOrder;

  /// Whether off-line-but-book moves are accepted (INV-065).
  final bool transposeAccept;

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
    int? prefetchBatchSize = 25,
    int prefetchRefillThreshold = 3,
    int? remainingDailyQuota,
    int? generation,
  }) async {
    final List<Study> targetStudies;
    final List<Chapter> targetChapters;
    final List<RepertoireDecision> decisions;

    if (scope.chapterId != null) {
      final chapter = await repository.getChapter(scope.chapterId!);
      targetChapters = chapter != null ? [chapter] : const [];
      final study = chapter != null ? await repository.getStudy(chapter.studyId) : null;
      targetStudies = study != null ? [study] : const [];
      decisions = await repository.getDecisionsByChapter(scope.chapterId!);
    } else if (scope.studyId != null) {
      final study = await repository.getStudy(scope.studyId!);
      targetStudies = study != null ? [study] : const [];
      targetChapters = await repository.getChaptersByStudy(scope.studyId!);
      decisions = await repository.getDecisionsByStudy(scope.studyId!);
    } else if (scope.openingFamily != null) {
      final allStudies = await repository.getAllStudies();
      final activeStudies = allStudies.where((s) => s.isActive).toList();
      final chapterOpenings = await repository.getChapterOpenings();
      final matchingChapterIds = chapterOpenings.entries
          .where((e) => e.value?.trim() == scope.openingFamily!.trim())
          .map((e) => e.key)
          .toSet();

      final chapters = <Chapter>[];
      for (final s in activeStudies) {
        final studyChapters = await repository.getChaptersByStudy(s.id);
        chapters.addAll(studyChapters.where((c) => matchingChapterIds.contains(c.id)));
      }
      targetStudies = activeStudies;
      targetChapters = chapters;
      decisions = await _getOpeningDecisions(targetChapters, scope.openingFamily!, activeStudies);
    } else {
      final allStudies = await repository.getAllStudies();
      final activeStudies = allStudies.where((s) => s.isActive).toList();
      final chapters = <Chapter>[];
      for (final s in activeStudies) {
        final studyChapters = await repository.getChaptersByStudy(s.id);
        chapters.addAll(studyChapters);
      }
      targetStudies = allStudies;
      targetChapters = chapters;
      decisions = await _getActiveDecisions(allStudies);
    }

    final decisionIds = decisions.map((d) => d.id).toList();
    final canonicalIds = decisions.map((d) => d.canonicalId).toSet().toList();
    final allQueryIds = {...decisionIds, ...canonicalIds}.toList();
    final reviewStatesList = await repository.getReviewStatesByDecisions(allQueryIds);
    final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
    final kStates = await repository.getKnowledgeStatesByCanonicalIds(canonicalIds);
    for (final k in kStates) {
      reviewStates[k.canonicalId] = k.toReviewState();
    }

    final engine = ReviewEngine(scheduler: scheduler, clock: clock);

    final session = engine.createSession(
      studies: targetStudies,
      chapters: targetChapters,
      decisions: decisions,
      reviewStates: reviewStates,
      scope: scope,
      mode: mode,
      order: reviewOrder,
      transposeAccept: transposeAccept,
      prefetchBatchSize: prefetchBatchSize,
      prefetchRefillThreshold: prefetchRefillThreshold,
      remainingDailyQuota: remainingDailyQuota,
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
      final canonicalId = currentDecision?.canonicalId ?? result.updatedState.decisionId;
      final kState = PositionKnowledgeState(
        canonicalId: canonicalId,
        firstReviewedAt: result.updatedState.firstReviewedAt,
        lastReviewedAt: result.updatedState.lastReviewedAt,
        nextDueAt: result.updatedState.nextDueAt,
        repetitionCount: result.updatedState.repetitionCount,
        lapseCount: result.updatedState.lapseCount,
        stability: result.updatedState.stability,
        difficulty: result.updatedState.difficulty,
      );

      final allKStates = <PositionKnowledgeState>[kState];

      // Persist any secondary states updated via graph effects (contagion, siblings, auto-traversal)
      for (final sideState in result.sideEffectStates) {
        allKStates.add(
          PositionKnowledgeState(
            canonicalId: sideState.decisionId,
            firstReviewedAt: sideState.firstReviewedAt,
            lastReviewedAt: sideState.lastReviewedAt,
            nextDueAt: sideState.nextDueAt,
            repetitionCount: sideState.repetitionCount,
            lapseCount: sideState.lapseCount,
            stability: sideState.stability,
            difficulty: sideState.difficulty,
          ),
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
      try {
        await repository.saveAnswerBatch(
          knowledgeStates: [
            for (final sideState in result.sideEffectStates)
              PositionKnowledgeState(
                canonicalId: sideState.decisionId,
                firstReviewedAt: sideState.firstReviewedAt,
                lastReviewedAt: sideState.lastReviewedAt,
                nextDueAt: sideState.nextDueAt,
                repetitionCount: sideState.repetitionCount,
                lapseCount: sideState.lapseCount,
                stability: sideState.stability,
                difficulty: sideState.difficulty,
              ),
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

  /// Returns a batched summary of due counts for all studies, opening hubs, and the given [scope].
  ///
  /// Computes all counts in a single in-memory pass over decisions without reloading
  /// recursive chapter trees or performing N+1 database queries.
  Future<DueCountsSummary> getDueSummary({
    required List<Study> studies,
    ReviewScope scope = const ReviewScope.all(),
    int? remainingDailyQuota,
  }) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final chapterOpenings = await repository.getChapterOpenings();
    final allDecisions = await repository.getAllDecisions();
    final reviewStatesList = await repository.getAllReviewStates();
    final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
    final now = clock.now();

    final studyDueCounts = <String, int>{for (final s in studies) s.id: 0};
    final studyTotals = <String, int>{for (final s in studies) s.id: 0};
    final studyLearned = <String, int>{for (final s in studies) s.id: 0};

    final chapterTotals = <String, int>{};
    final chapterLearned = <String, int>{};
    final chapterDue = <String, int>{};

    final openingFamilies = <String>{};
    for (final op in chapterOpenings.values) {
      if (op != null && op.trim().isNotEmpty) {
        openingFamilies.add(op.trim());
      }
    }
    final openingDueCounts = <String, int>{for (final op in openingFamilies) op: 0};
    final openingTotals = <String, int>{for (final op in openingFamilies) op: 0};
    final openingLearned = <String, int>{for (final op in openingFamilies) op: 0};

    var totalDueCount = 0;
    final accountedDueCanonicalIds = <String>{};

    for (final d in allDecisions) {
      final state = reviewStates[d.canonicalId] ?? reviewStates[d.id];
      final isDue = state == null || state.isDueAt(now);
      final isLearned = state != null && state.repetitionCount > 0;

      if (studyTotals.containsKey(d.studyId)) {
        studyTotals[d.studyId] = (studyTotals[d.studyId] ?? 0) + 1;
        if (isLearned) {
          studyLearned[d.studyId] = (studyLearned[d.studyId] ?? 0) + 1;
        }
      }

      chapterTotals[d.chapterId] = (chapterTotals[d.chapterId] ?? 0) + 1;
      if (isLearned) {
        chapterLearned[d.chapterId] = (chapterLearned[d.chapterId] ?? 0) + 1;
      }
      if (isDue) {
        chapterDue[d.chapterId] = (chapterDue[d.chapterId] ?? 0) + 1;
      }

      final opening = chapterOpenings[d.chapterId]?.trim();
      final isActiveStudy = activeStudyIds.contains(d.studyId);

      if (isActiveStudy && opening != null && opening.isNotEmpty) {
        if (openingTotals.containsKey(opening)) {
          openingTotals[opening] = (openingTotals[opening] ?? 0) + 1;
          if (isLearned) {
            openingLearned[opening] = (openingLearned[opening] ?? 0) + 1;
          }
        }
      }

      if (!isDue) continue;

      if (studyDueCounts.containsKey(d.studyId)) {
        studyDueCounts[d.studyId] = (studyDueCounts[d.studyId] ?? 0) + 1;
      }

      if (isActiveStudy && opening != null && opening.isNotEmpty) {
        if (openingDueCounts.containsKey(opening)) {
          openingDueCounts[opening] = (openingDueCounts[opening] ?? 0) + 1;
        }
      }

      if (scope.matches(studyId: d.studyId, chapterId: d.chapterId, openingFamily: opening)) {
        if (scope.studyId != null || scope.chapterId != null) {
          totalDueCount++;
        } else if (scope.openingFamily != null) {
          if (isActiveStudy && accountedDueCanonicalIds.add(d.canonicalId)) {
            totalDueCount++;
          }
        } else {
          if (isActiveStudy && accountedDueCanonicalIds.add(d.canonicalId)) {
            totalDueCount++;
          }
        }
      }
    }

    final studyProgress = <String, RepertoireProgress>{
      for (final s in studies)
        s.id: RepertoireProgress(
          totalDecisions: studyTotals[s.id] ?? 0,
          learnedDecisions: studyLearned[s.id] ?? 0,
          dueDecisions: studyDueCounts[s.id] ?? 0,
        ),
    };

    final chapterProgress = <String, RepertoireProgress>{
      for (final chId in chapterTotals.keys)
        chId: RepertoireProgress(
          totalDecisions: chapterTotals[chId] ?? 0,
          learnedDecisions: chapterLearned[chId] ?? 0,
          dueDecisions: chapterDue[chId] ?? 0,
        ),
    };

    final openingProgress = <String, RepertoireProgress>{
      for (final op in openingFamilies)
        op: RepertoireProgress(
          totalDecisions: openingTotals[op] ?? 0,
          learnedDecisions: openingLearned[op] ?? 0,
          dueDecisions: openingDueCounts[op] ?? 0,
        ),
    };

    final effectiveTotalDue = remainingDailyQuota != null && remainingDailyQuota >= 0
        ? math.min(totalDueCount, remainingDailyQuota)
        : totalDueCount;

    return DueCountsSummary(
      totalDueCount: effectiveTotalDue,
      studyDueCounts: studyDueCounts,
      openingDueCounts: openingDueCounts,
      studyProgress: studyProgress,
      chapterProgress: chapterProgress,
      openingProgress: openingProgress,
    );
  }

  Future<List<RepertoireDecision>> _getActiveDecisions(List<Study> studies) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final allDecisions = await repository.getAllDecisions();
    return allDecisions.where((d) => activeStudyIds.contains(d.studyId)).toList();
  }

  Future<List<RepertoireDecision>> _getOpeningDecisions(
    List<Chapter> allChapters,
    String openingFamily,
    List<Study> studies,
  ) async {
    final activeStudyIds = studies.where((s) => s.isActive).map((s) => s.id).toSet();
    final wanted = openingFamily.trim();
    final matchingChapterIds = allChapters
        .where((c) => (c.opening?.trim() ?? '') == wanted && activeStudyIds.contains(c.studyId))
        .map((c) => c.id)
        .toSet();
    final allDecisions = await repository.getAllDecisions();
    return allDecisions.where((d) => matchingChapterIds.contains(d.chapterId)).toList();
  }
}
