// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart' show Side;

/// Lightweight projection of a decision for due-summary tallies,
/// omitting moves and node IDs to avoid decoding JSON move lists.
typedef TallyDecision = ({String id, String studyId, String chapterId, String canonicalId});

/// Abstract interface for local persistence of studies, chapters, trees,
/// decisions, and spaced repetition review states.
abstract class StudyRepository {
  // Bulk import
  Future<void> saveImportResult(ImportResult result);

  // Studies
  Future<void> saveStudy(Study study);
  Future<Study?> getStudy(String id);

  /// The study with this fingerprint, or null if there is none.
  ///
  /// When [forSide] is given, a study is only returned if every one of its chapters was
  /// imported for that side. The PGN hash covers the move tree, which is identical whichever
  /// side is being trained, so a White and a Black repertoire of the same lines share a
  /// fingerprint while being entirely different sets of questions.
  Future<Study?> getStudyByPgnHash(String pgnHash, {Side? forSide});
  Future<List<Study>> getAllStudies();
  Future<List<Study>> getActiveStudies();
  Future<void> updateStudyActive(String studyId, bool isActive);
  Future<void> updateStudyTitle(String studyId, String newTitle);

  /// The local study bulk-imported from the Lichess study [remoteStudyId], if any,
  /// with the remote timestamp at its last import.
  Future<({Study study, DateTime? remoteUpdatedAt})?> getStudyByRemoteId(String remoteStudyId);

  /// Records (or refreshes) which remote study [studyId] was imported from.
  Future<void> updateStudyRemoteRef({
    required String studyId,
    required String remoteStudyId,
    required DateTime remoteUpdatedAt,
  });
  Future<void> deleteStudy(String id);

  // Chapters
  Future<void> saveChapter(Chapter chapter);
  Future<void> saveChapters(List<Chapter> chapters);
  Future<Chapter?> getChapter(String id);
  Future<List<Chapter>> getChaptersByStudy(String studyId);
  Future<List<Chapter>> getChaptersByStudyIds(List<String> studyIds);
  Future<List<Chapter>> getAllChapters();
  Future<Map<String, String?>> getChapterOpenings();

  /// Chapter id to the study it belongs to, for every chapter.
  ///
  /// Needed to group material by repertoire colour without walking every
  /// study's chapters: the colour lives on the chapter, and the drawer's list
  /// is of studies.
  Future<Map<String, String>> getChapterStudyIds();

  /// The repertoire side of every chapter, keyed by chapter id.
  ///
  /// One indexed read of two columns, so a side-scoped due count costs the same
  /// single pass as the opening one rather than a query per study. `Chapter`
  /// defaults to White when the column is absent or unreadable, matching the
  /// column's own default.
  Future<Map<String, Side>> getChapterOrientations();
  Future<void> deleteChapter(String id);

  // Position Trees
  Future<RepertoireNode?> getPositionTree(String chapterId);

  /// Saves the move tree of a chapter directly.
  ///
  /// In normal application workflows, [saveImportResult] atomically writes studies,
  /// chapters, and decision trees within a single transaction. This method exists for
  /// independent tree updates or test fixtures.
  Future<void> savePositionTree(String chapterId, RepertoireNode root);

  // Decisions
  Future<void> saveDecision(RepertoireDecision decision);

  /// Persists a batch of decisions directly.
  ///
  /// In production, [saveImportResult] atomically persists decisions alongside their
  /// studies and chapters. This method is used primarily by test fixtures and
  /// isolated decision seeding.
  Future<void> saveDecisions(List<RepertoireDecision> decisions);
  Future<RepertoireDecision?> getDecision(String id);
  Future<List<RepertoireDecision>> getDecisionsByChapter(String chapterId);
  Future<List<RepertoireDecision>> getDecisionsByStudy(String studyId);
  Future<List<RepertoireDecision>> getAllDecisions();

  /// Returns a lightweight projection of all decisions for due-summary tallies,
  /// omitting moves and node IDs to avoid decoding JSON move lists.
  Future<List<TallyDecision>> getTallyDecisions();

  // Position Knowledge States (canonical SRS memory layer)
  Future<void> savePositionKnowledgeState(PositionKnowledgeState state);
  Future<void> savePositionKnowledgeStates(List<PositionKnowledgeState> states);
  Future<void> saveAnswerBatch({
    required List<PositionKnowledgeState> knowledgeStates,
    ReviewEvent? event,
  });
  Future<PositionKnowledgeState?> getPositionKnowledgeState(String canonicalId);
  Future<List<PositionKnowledgeState>> getKnowledgeStatesByCanonicalIds(List<String> canonicalIds);
  Future<List<PositionKnowledgeState>> getAllKnowledgeStates();

  // Review states (SRS legacy/compatibility)
  Future<void> saveReviewState(ReviewState state);
  Future<void> saveReviewStates(List<ReviewState> states);
  Future<ReviewState?> getReviewState(String decisionId);
  Future<List<ReviewState>> getAllReviewStates();

  /// Reads from `srs_review_state` for any of the given ids, which may be
  /// per-occurrence `decisionId`s **or** canonical ids — see
  /// `SqliteStudyRepository.saveAnswerBatch`'s mirroring.
  Future<List<ReviewState>> getReviewStatesByIds(List<String> ids);

  /// Positions first presented on the local calendar day containing [now].
  ///
  /// Counts introductions, not reviews: one canonical position answers once
  /// however many times it is re-tested that day, which is what the new-position
  /// allowance is spent on (INV-068). Reads `firstReviewedAt`, so a position
  /// introduced on an earlier day does not count again no matter how often it
  /// recurs.
  Future<int> getTodayIntroducedPositionsCount(DateTime now);

  // Dynamic repertoire unlocked decisions
  Future<Set<String>> getUnlockedDecisionIds({String? studyId});
  Future<void> unlockDecisions(Iterable<String> decisionIds);
  Future<void> lockDecisions(Iterable<String> decisionIds);

  // Review events (SRS log)
  Future<void> saveReviewEvent(ReviewEvent event);
  Future<List<ReviewEvent>> getReviewEvents(String decisionId);
  Future<int> getTodayReviewedPositionsCount(DateTime now);
}
