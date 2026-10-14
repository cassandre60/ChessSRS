// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:chess_srs/src/persistence/study_repository.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

final Logger _logger = Logger('StudyRepository');

/// Provider for the application's [StudyRepository].
final srsStudyRepositoryProvider = FutureProvider<StudyRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return SqliteStudyRepository(db);
}, name: 'SrsStudyRepositoryProvider');

/// Concrete SQLite implementation of [StudyRepository].
///
/// Ensures incremental persistence: review answers touch only the affected
/// decision's [ReviewState] and append one [ReviewEvent] without touching
/// study or chapter trees (QUALITY.md §1.5).
class SqliteStudyRepository implements StudyRepository {
  // Not const: the import FIFO below is per-instance mutable state. No call site used `const`,
  // so dropping it is invisible to callers.
  SqliteStudyRepository(this._db);

  final Database _db;

  /// The import currently running, or null when none is. A second import waits on it and takes
  /// its place; see [saveImportResult] for why the uncontended path deliberately does not await
  /// anything.
  Completer<void>? _importInFlight;

  @override
  Future<void> saveImportResult(ImportResult result) async {
    // Imports are serialised. The duplicate check that decides whether an import happens at
    // all lives in the controller, above this layer, so two imports that start together both ask
    // "already imported?" before either writes and both see no match. Serialising the writes lets
    // the second one re-check now that the first has committed.
    //
    // The uncontended path must not await at all. An unconditional `await previous` adds a
    // microtask hop before any I/O, and under a widget test's fake clock that hop needs a pump to
    // drain — which hangs export_pgn_dialog_test.dart outright. Waiting only when something is
    // genuinely in front keeps the single-import path byte-for-byte as asynchronous as it was.
    final ahead = _importInFlight;
    final mine = Completer<void>();
    _importInFlight = mine;
    if (ahead != null) {
      await ahead.future;
    }

    final sw = Stopwatch()..start();
    try {
      // Two imports of one file carry different study ids and fresh chapter/decision ids, so
      // nothing in the write itself matches: they accumulate into one study, and the duplicate is
      // invisible because there is only ever one study row.
      //
      // The orientation check is not optional. The same tree imported as White and as Black is two
      // studies that share a pgnHash on purpose — different questions, different SRS memory — so
      // matching on the hash alone would silently drop the second repertoire. This mirrors
      // getStudyByPgnHash's forSide filter.
      final hash = result.study.pgnHash;
      if (hash != null) {
        final orientation = result.chapters.isEmpty ? null : result.chapters.first.orientation;
        final existing = orientation == null
            ? await _db.query(
                kTableSrsStudy,
                columns: ['id'],
                where: 'pgnHash = ?',
                whereArgs: [hash],
                limit: 1,
              )
            : await _db.query(
                kTableSrsStudy,
                columns: ['id'],
                where:
                    'pgnHash = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsChapter c '
                    'WHERE c.studyId = $kTableSrsStudy.id AND c.orientation != ?)',
                whereArgs: [hash, orientation.name],
                limit: 1,
              );
        if (existing.isNotEmpty) {
          _logger.info(
            'Skipping import of "${result.study.title}": already stored as '
            '${existing.first['id']} while this one was in flight.',
          );
          return;
        }
      }

      await _db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();
        await txn.insert(
          kTableSrsStudy,
          _studyRow(result.study, nowIso: now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final chapterBatch = txn.batch();
        for (final chapter in result.chapters) {
          chapterBatch.insert(
            kTableSrsChapter,
            _chapterRow(chapter),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await chapterBatch.commit(noResult: true);

        final decisionBatch = txn.batch();
        for (final d in result.decisions) {
          decisionBatch.insert(
            kTableSrsDecision,
            _decisionRow(d),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await decisionBatch.commit(noResult: true);
      });
      sw.stop();
      _logger.info(
        'Saved import result for study ${result.study.id} ("${result.study.title}"): '
        '${result.chapters.length} chapters, ${result.decisions.length} decisions in ${sw.elapsedMilliseconds}ms',
      );
    } finally {
      // Released whether the import succeeded, was skipped as a duplicate, or threw — otherwise
      // one failed import would wedge every later one behind a future that never completes.
      mine.complete();
      if (identical(_importInFlight, mine)) {
        _importInFlight = null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Studies
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveStudy(Study study) async {
    final now = DateTime.now().toIso8601String();
    await _db.insert(
      kTableSrsStudy,
      _studyRow(study, nowIso: now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Study?> getStudy(String id) async {
    final rows = await _db.query(kTableSrsStudy, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _studyFromRow(rows.first);
  }

  @override
  Future<Study?> getStudyByPgnHash(String pgnHash, {Side? forSide}) async {
    // The side filter is part of the lookup rather than a second query afterwards: this runs on
    // the import path, and a study that does not match must fall through to a real import rather
    // than be fetched and then discarded. A mixed-orientation study is not a match either, so it
    // is re-imported — a spare copy costs the user a delete, a wrongly-skipped one costs them
    // the repertoire.
    final rows = await _db.query(
      kTableSrsStudy,
      where: forSide == null
          ? 'pgnHash = ?'
          : 'pgnHash = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsChapter c '
                'WHERE c.studyId = $kTableSrsStudy.id AND c.orientation != ?)',
      whereArgs: forSide == null ? [pgnHash] : [pgnHash, forSide.name],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return _studyFromRow(rows.first);
    }

    // Auto-backfill: if any existing studies have null pgnHash, inspect their chapters.
    // Batched (INV-051): one IN query fetches every unhashed study's chapters
    // and one batch writes the hashes back, instead of a SELECT plus an UPDATE
    // per study on the import path.
    final unhashedRows = await _db.query(kTableSrsStudy, where: 'pgnHash IS NULL');
    if (unhashedRows.isEmpty) return null;

    final unhashedIds = unhashedRows.map((r) => r['id']! as String).toList();
    final placeholders = List.filled(unhashedIds.length, '?').join(',');
    final chapterRows = await _db.query(
      kTableSrsChapter,
      where: 'studyId IN ($placeholders)',
      whereArgs: unhashedIds,
      orderBy: 'studyId ASC, sourceOrder ASC',
    );

    final chaptersByStudy = <String, List<Map<String, Object?>>>{};
    for (final chapterRow in chapterRows) {
      (chaptersByStudy[chapterRow['studyId']! as String] ??= []).add(chapterRow);
    }

    final batch = _db.batch();
    Study? match;
    for (final row in unhashedRows) {
      final study = _studyFromRow(row);
      final chapters =
          chaptersByStudy[study.id]?.map(_chapterFromRow).toList(growable: false) ??
          const <Chapter>[];
      if (chapters.isEmpty) continue;
      final computedHash = computeRepertoireTreeHash(chapters);
      batch.update(
        kTableSrsStudy,
        {'pgnHash': computedHash},
        where: 'id = ?',
        whereArgs: [study.id],
      );
      if (match == null &&
          computedHash == pgnHash &&
          (forSide == null || chapters.every((c) => c.orientation == forSide))) {
        match = study.copyWith(pgnHash: computedHash);
      }
    }
    await batch.commit(noResult: true);
    return match;
  }

  @override
  Future<List<Study>> getAllStudies() async {
    final rows = await _db.query(kTableSrsStudy, orderBy: 'createdAt ASC');
    return rows.map(_studyFromRow).toList(growable: false);
  }

  @override
  Future<List<Study>> getActiveStudies() async {
    final rows = await _db.query(kTableSrsStudy, where: 'isActive = 1', orderBy: 'createdAt ASC');
    return rows.map(_studyFromRow).toList(growable: false);
  }

  @override
  Future<void> updateStudyActive(String studyId, bool isActive) async {
    final now = DateTime.now().toIso8601String();
    await _db.update(
      kTableSrsStudy,
      {'isActive': isActive ? 1 : 0, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [studyId],
    );
  }

  @override
  Future<void> updateStudyTitle(String studyId, String newTitle) async {
    final now = DateTime.now().toIso8601String();
    await _db.update(
      kTableSrsStudy,
      {'title': newTitle, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [studyId],
    );
  }

  @override
  Future<void> deleteStudy(String id) async {
    await _db.transaction((txn) async {
      // Find all decisions belonging to this study
      final decisions = await txn.query(
        kTableSrsDecision,
        columns: ['id'],
        where: 'studyId = ?',
        whereArgs: [id],
      );
      final decisionIds = decisions.map((d) => d['id']! as String).toList();

      if (decisionIds.isNotEmpty) {
        const chunkSize = 400;
        final canonicalIds = <String>{};

        for (var i = 0; i < decisionIds.length; i += chunkSize) {
          final chunk = decisionIds.sublist(
            i,
            i + chunkSize > decisionIds.length ? decisionIds.length : i + chunkSize,
          );
          final placeholders = List.filled(chunk.length, '?').join(',');

          final canonicalRows = await txn.query(
            kTableSrsDecision,
            columns: ['canonicalStateId'],
            where: 'id IN ($placeholders)',
            whereArgs: chunk,
          );
          for (final r in canonicalRows) {
            final cId = r['canonicalStateId'] as String?;
            if (cId != null && cId.isNotEmpty) {
              canonicalIds.add(cId);
            }
          }

          // Events and legacy per-occurrence rows keyed by the occurrence id
          // belong to this study outright. Canonical-keyed rows are handled
          // below under the surviving-study guard: a transposition shared
          // with another study must keep its history and mirrors.
          final bothPlaceholders = List.filled(chunk.length, '?').join(',');
          await txn.delete(
            kTableSrsReviewEvent,
            where: 'decisionId IN ($bothPlaceholders)',
            whereArgs: chunk,
          );
          await txn.delete(
            kTableSrsReviewState,
            where: 'decisionId IN ($bothPlaceholders)',
            whereArgs: chunk,
          );
        }

        final canonicalList = canonicalIds.toList(growable: false);
        for (var i = 0; i < canonicalList.length; i += chunkSize) {
          final chunk = canonicalList.sublist(
            i,
            i + chunkSize > canonicalList.length ? canonicalList.length : i + chunkSize,
          );
          final cPlaceholders = List.filled(chunk.length, '?').join(',');
          // NOT EXISTS (not NOT IN): the correlated form uses the
          // idx_srs_decision_canonicalStateId index instead of forcing a scan, and it is
          // NULL-safe where NOT IN needs the IS NOT NULL guard to mean anything.
          final sharedGuard =
              'canonicalId IN ($cPlaceholders) AND NOT EXISTS ( '
              'SELECT 1 FROM $kTableSrsDecision d2 WHERE d2.canonicalStateId = '
              '$kTablePositionKnowledgeState.canonicalId AND d2.studyId != ?)';
          await txn.delete(
            kTablePositionKnowledgeState,
            where: sharedGuard,
            whereArgs: [...chunk, id],
          );
          await txn.delete(
            kTableSrsReviewState,
            where:
                'decisionId IN ($cPlaceholders) AND NOT EXISTS ( '
                'SELECT 1 FROM $kTableSrsDecision d2 WHERE d2.canonicalStateId = '
                '$kTableSrsReviewState.decisionId AND d2.studyId != ?)',
            whereArgs: [...chunk, id],
          );
          await txn.delete(
            kTableSrsReviewEvent,
            where:
                'decisionId IN ($cPlaceholders) AND NOT EXISTS ( '
                'SELECT 1 FROM $kTableSrsDecision d2 WHERE d2.canonicalStateId = '
                '$kTableSrsReviewEvent.decisionId AND d2.studyId != ?)',
            whereArgs: [...chunk, id],
          );
        }

        await txn.delete(kTableSrsDecision, where: 'studyId = ?', whereArgs: [id]);
      }

      await txn.delete(kTableSrsChapter, where: 'studyId = ?', whereArgs: [id]);
      await txn.delete(kTableSrsStudy, where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Chapters
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveChapter(Chapter chapter) async {
    await _db.insert(
      kTableSrsChapter,
      _chapterRow(chapter),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveChapters(List<Chapter> chapters) async {
    final batch = _db.batch();
    for (final chapter in chapters) {
      batch.insert(
        kTableSrsChapter,
        _chapterRow(chapter),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<Chapter?> getChapter(String id) async {
    final rows = await _db.query(kTableSrsChapter, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _chapterFromRow(rows.first);
  }

  @override
  Future<List<Chapter>> getChaptersByStudy(String studyId) async {
    final rows = await _db.query(
      kTableSrsChapter,
      where: 'studyId = ?',
      whereArgs: [studyId],
      orderBy: 'sourceOrder ASC',
    );
    return rows.map(_chapterFromRow).toList(growable: false);
  }

  @override
  Future<Map<String, String?>> getChapterOpenings() async {
    final rows = await _db.query(kTableSrsChapter, columns: ['id', 'opening']);
    return {for (final r in rows) r['id']! as String: r['opening'] as String?};
  }

  @override
  Future<Map<String, Side>> getChapterOrientations() async {
    final rows = await _db.query(kTableSrsChapter, columns: ['id', 'orientation']);
    return {
      for (final r in rows)
        r['id']! as String: (r['orientation'] as String?) == 'black' ? Side.black : Side.white,
    };
  }

  @override
  Future<Map<String, String>> getChapterStudyIds() async {
    final rows = await _db.query(kTableSrsChapter, columns: ['id', 'studyId']);
    return {for (final r in rows) r['id']! as String: r['studyId']! as String};
  }

  @override
  Future<void> deleteChapter(String id) async {
    await _db.transaction((txn) async {
      final decisions = await txn.query(
        kTableSrsDecision,
        columns: ['id', 'canonicalStateId'],
        where: 'chapterId = ?',
        whereArgs: [id],
      );
      final decisionIds = decisions.map((d) => d['id']! as String).toList();
      final canonicalIds = decisions
          .map((d) => d['canonicalStateId'] as String?)
          .whereType<String>()
          .where((c) => c.isNotEmpty)
          .toSet();

      if (decisionIds.isNotEmpty) {
        // Rows keyed by the per-occurrence id belong to this chapter outright.
        final occurrencePlaceholders = List.filled(decisionIds.length, '?').join(',');
        await txn.delete(
          kTableSrsReviewEvent,
          where: 'decisionId IN ($occurrencePlaceholders)',
          whereArgs: decisionIds,
        );
        await txn.delete(
          kTableSrsReviewState,
          where: 'decisionId IN ($occurrencePlaceholders)',
          whereArgs: decisionIds,
        );
        await txn.delete(kTableSrsDecision, where: 'chapterId = ?', whereArgs: [id]);

        // Rows keyed by the canonical id describe the *position*, not the occurrence. Another
        // chapter reaching the same position still needs them, so they only go when this was the
        // last decision referring to it.
        for (final canonicalId in canonicalIds) {
          // Still referenced by some other decision, so this position outlives the chapter.
          // NOT EXISTS (not NOT IN): index-using and NULL-safe without an IS NOT NULL
          // guard. Each guard correlates to its own target table.
          await txn.delete(
            kTablePositionKnowledgeState,
            where:
                'canonicalId = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsDecision '
                'WHERE canonicalStateId = $kTablePositionKnowledgeState.canonicalId)',
            whereArgs: [canonicalId],
          );
          await txn.delete(
            kTableSrsReviewState,
            where:
                'decisionId = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsDecision '
                'WHERE canonicalStateId = $kTableSrsReviewState.decisionId)',
            whereArgs: [canonicalId],
          );
          await txn.delete(
            kTableSrsReviewEvent,
            where:
                'decisionId = ? AND NOT EXISTS (SELECT 1 FROM $kTableSrsDecision '
                'WHERE canonicalStateId = $kTableSrsReviewEvent.decisionId)',
            whereArgs: [canonicalId],
          );
        }
      }

      await txn.delete(kTableSrsChapter, where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Position Trees
  // ---------------------------------------------------------------------------

  @override
  Future<RepertoireNode?> getPositionTree(String chapterId) async {
    final rows = await _db.query(
      kTableSrsChapter,
      columns: ['treeJson'],
      where: 'id = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final treeJson = rows.first['treeJson'] as String?;
    if (treeJson == null || treeJson.isEmpty) return null;
    return repertoireNodeFromJson(jsonDecode(treeJson) as Map<String, dynamic>);
  }

  @override
  Future<void> savePositionTree(String chapterId, RepertoireNode root) async {
    final treeJson = jsonEncode(repertoireNodeToJson(root));
    await _db.update(
      kTableSrsChapter,
      {'treeJson': treeJson},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
  }

  // ---------------------------------------------------------------------------
  // Decisions
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveDecision(RepertoireDecision decision) async {
    await _db.insert(
      kTableSrsDecision,
      _decisionRow(decision),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveDecisions(List<RepertoireDecision> decisions) async {
    final batch = _db.batch();
    for (final d in decisions) {
      batch.insert(
        kTableSrsDecision,
        _decisionRow(d),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<RepertoireDecision?> getDecision(String id) async {
    final rows = await _db.query(kTableSrsDecision, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _decisionFromRow(rows.first);
  }

  @override
  Future<List<RepertoireDecision>> getDecisionsByChapter(String chapterId) async {
    final rows = await _db.query(kTableSrsDecision, where: 'chapterId = ?', whereArgs: [chapterId]);
    return rows.map(_decisionFromRow).toList(growable: false);
  }

  @override
  Future<List<RepertoireDecision>> getDecisionsByStudy(String studyId) async {
    final rows = await _db.query(kTableSrsDecision, where: 'studyId = ?', whereArgs: [studyId]);
    return rows.map(_decisionFromRow).toList(growable: false);
  }

  @override
  Future<List<RepertoireDecision>> getAllDecisions() async {
    final rows = await _db.query(kTableSrsDecision);
    return rows.map(_decisionFromRow).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Position Knowledge States (canonical SRS layer)
  // ---------------------------------------------------------------------------

  @override
  Future<void> savePositionKnowledgeState(PositionKnowledgeState state) async {
    // One transaction for the canonical row and every mirror it implies. They are a single fact
    // about one position, and reading them apart is the failure mode: a canonical row that says
    // "reviewed" next to mirrors that disagree re-presents or skips the position on the next
    // session. Crashing between the two halves is not hypothetical either — an OOM kill or a
    // force-stop mid-answer is exactly where this runs.
    //
    // Every write goes through `txn` rather than `saveReviewState`, which would reach for `_db`
    // and land outside the transaction.
    await _db.transaction((txn) async {
      await txn.rawInsert(_knowledgeStateUpsertSql, _knowledgeStateUpsertArgs(state));

      await txn.insert(
        kTableSrsReviewState,
        _reviewStateRow(state.toReviewState(state.canonicalId)),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final matchingDecisions = await txn.query(
        kTableSrsDecision,
        columns: ['id'],
        where: 'canonicalStateId = ?',
        whereArgs: [state.canonicalId],
      );
      for (final dec in matchingDecisions) {
        final decId = dec['id']! as String;
        await txn.insert(
          kTableSrsReviewState,
          _reviewStateRow(state.toReviewState(decId)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> savePositionKnowledgeStates(List<PositionKnowledgeState> states) async {
    // Same reasoning as the single-state form: the canonical rows and the review-state rows are
    // one fact each, and they were two commits, so a failure between them left the two halves
    // disagreeing. One transaction, one commit, or neither.
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final s in states) {
        batch.rawInsert(_knowledgeStateUpsertSql, _knowledgeStateUpsertArgs(s));
      }
      for (final s in states) {
        batch.insert(
          kTableSrsReviewState,
          _reviewStateRow(s.toReviewState(s.canonicalId)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Persists an answer's canonical state **and** its per-occurrence mirrors.
  ///
  /// `srs_review_state` is written **twice per state** on purpose:
  ///
  /// 1. Once keyed by the canonical id (shared position knowledge — one row
  ///    per unique position).
  /// 2. Once per occurrence via `SELECT id FROM srs_decision WHERE canonicalStateId = ?`
  ///    (one row per `srs_decision.id` that reaches the same position via a
  ///    transposition). Reads query both key kinds
  ///    (`review_service.dart: getReviewStatesByIds({…decisionIds, …canonicalIds})`
  ///    plus `getKnowledgeStatesByCanonicalIds`) and the session looks up
  ///    `reviewStates[canonicalId] ?? reviewStates[decisionId]`. Doubling the
  ///    row volume is deliberate and what keeps transposition reads coherent.
  @override
  Future<void> saveAnswerBatch({
    required List<PositionKnowledgeState> knowledgeStates,
    ReviewEvent? event,
  }) async {
    if (knowledgeStates.isEmpty && event == null) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();

      for (final s in knowledgeStates) {
        batch.rawInsert(_knowledgeStateUpsertSql, _knowledgeStateUpsertArgs(s));

        // canonical mirror
        batch.insert(
          kTableSrsReviewState,
          _reviewStateRow(s.toReviewState(s.canonicalId)),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // per-occurrence mirrors (transpositions)
        batch.rawInsert(
          '''
          INSERT OR REPLACE INTO $kTableSrsReviewState(
            decisionId, firstReviewedAt, lastReviewedAt, nextDueAt,
            repetitionCount, lapseCount, stability, difficulty
          )
          SELECT id, ?, ?, ?, ?, ?, ?, ?
          FROM $kTableSrsDecision
          WHERE canonicalStateId = ?
        ''',
          [
            s.firstReviewedAt?.toUtc().toIso8601String(),
            s.lastReviewedAt?.toUtc().toIso8601String(),
            s.nextDueAt?.toUtc().toIso8601String(),
            s.repetitionCount,
            s.lapseCount,
            s.stability,
            s.difficulty,
            s.canonicalId,
          ],
        );
      }

      if (event != null) {
        batch.insert(kTableSrsReviewEvent, _reviewEventRow(event));
      }

      await batch.commit(noResult: true);
    });
  }

  @override
  Future<PositionKnowledgeState?> getPositionKnowledgeState(String canonicalId) async {
    final rows = await _db.query(
      kTablePositionKnowledgeState,
      where: 'canonicalId = ?',
      whereArgs: [canonicalId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return _knowledgeStateFromRow(rows.first);
    }
    // Fallback: check legacy srs_review_state directly (no mutual recursion)
    final legacyRows = await _db.query(
      kTableSrsReviewState,
      where: 'decisionId = ?',
      whereArgs: [canonicalId],
      limit: 1,
    );
    if (legacyRows.isNotEmpty) {
      final legacy = _reviewStateFromRow(legacyRows.first);
      return PositionKnowledgeState(
        canonicalId: legacy.decisionId,
        firstReviewedAt: legacy.firstReviewedAt,
        lastReviewedAt: legacy.lastReviewedAt,
        nextDueAt: legacy.nextDueAt,
        repetitionCount: legacy.repetitionCount,
        lapseCount: legacy.lapseCount,
        stability: legacy.stability,
        difficulty: legacy.difficulty,
      );
    }
    return null;
  }

  @override
  Future<List<PositionKnowledgeState>> getKnowledgeStatesByCanonicalIds(
    List<String> canonicalIds,
  ) async {
    if (canonicalIds.isEmpty) return const [];
    const chunkSize = 400;
    final results = <PositionKnowledgeState>[];
    for (var i = 0; i < canonicalIds.length; i += chunkSize) {
      final chunk = canonicalIds.sublist(
        i,
        i + chunkSize > canonicalIds.length ? canonicalIds.length : i + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.query(
        kTablePositionKnowledgeState,
        where: 'canonicalId IN ($placeholders)',
        whereArgs: chunk,
      );
      results.addAll(rows.map(_knowledgeStateFromRow));
    }
    return results;
  }

  @override
  Future<List<PositionKnowledgeState>> getAllKnowledgeStates() async {
    final rows = await _db.query(kTablePositionKnowledgeState);
    return rows.map(_knowledgeStateFromRow).toList(growable: false);
  }

  static PositionKnowledgeState _knowledgeStateFromRow(Map<String, Object?> row) {
    final first = row['firstReviewedAt'] as String?;
    final last = row['lastReviewedAt'] as String?;
    final next = row['nextDueAt'] as String?;
    final exposed = row['lastExposedAt'] as String?;

    return PositionKnowledgeState(
      canonicalId: row['canonicalId']! as String,
      firstReviewedAt: first != null ? DateTime.parse(first).toUtc() : null,
      lastReviewedAt: last != null ? DateTime.parse(last).toUtc() : null,
      nextDueAt: next != null ? DateTime.parse(next).toUtc() : null,
      repetitionCount: (row['repetitionCount']! as num).toInt(),
      lapseCount: (row['lapseCount']! as num).toInt(),
      stability: (row['stability']! as num).toDouble(),
      difficulty: (row['difficulty'] as num?)?.toDouble() ?? 5.0,
      latencyEmaMs: (row['latencyEmaMs'] as num?)?.toDouble(),
      latencySampleCount: (row['latencySampleCount'] as num?)?.toInt() ?? 0,
      lastExposedAt: exposed != null ? DateTime.parse(exposed).toUtc() : null,
    );
  }

  /// Upsert for `position_knowledge_state` that never erases latency telemetry.
  ///
  /// `latencyEmaMs` / `latencySampleCount` are deliberately absent from the
  /// conflict update: they are post-hoc telemetry the answer path does not
  /// measure, and a REPLACE-style rewrite erased them on every answer
  /// (review-4 C1). The insert branch (fresh row — nothing to preserve) still
  /// writes them when the caller provides values, so a seed or import that
  /// carries telemetry round-trips; on conflict only the nine SRS columns are
  /// touched and existing telemetry survives untouched.
  static const String _knowledgeStateUpsertSql =
      '''
    INSERT INTO $kTablePositionKnowledgeState(
      canonicalId, firstReviewedAt, lastReviewedAt, nextDueAt,
      repetitionCount, lapseCount, stability, difficulty,
      latencyEmaMs, latencySampleCount, lastExposedAt
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(canonicalId) DO UPDATE SET
      firstReviewedAt = excluded.firstReviewedAt,
      lastReviewedAt  = excluded.lastReviewedAt,
      nextDueAt       = excluded.nextDueAt,
      repetitionCount = excluded.repetitionCount,
      lapseCount      = excluded.lapseCount,
      stability       = excluded.stability,
      difficulty      = excluded.difficulty,
      lastExposedAt   = excluded.lastExposedAt
  ''';

  /// Bindings for [_knowledgeStateUpsertSql]: all eleven columns. On conflict
  /// the latency values are ignored — the update set does not mention them.
  /// Timestamps are normalised to UTC on write (review-4 C2) so a timezone
  /// change between write and read cannot shift due dates.
  static List<Object?> _knowledgeStateUpsertArgs(PositionKnowledgeState state) => [
    state.canonicalId,
    state.firstReviewedAt?.toUtc().toIso8601String(),
    state.lastReviewedAt?.toUtc().toIso8601String(),
    state.nextDueAt?.toUtc().toIso8601String(),
    state.repetitionCount,
    state.lapseCount,
    state.stability,
    state.difficulty,
    state.latencyEmaMs,
    state.latencySampleCount,
    state.lastExposedAt?.toUtc().toIso8601String(),
  ];

  // ---------------------------------------------------------------------------
  // Review States (SRS)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveReviewState(ReviewState state) async {
    await _db.insert(
      kTableSrsReviewState,
      _reviewStateRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> saveReviewStates(List<ReviewState> states) async {
    final batch = _db.batch();
    for (final s in states) {
      batch.insert(
        kTableSrsReviewState,
        _reviewStateRow(s),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<ReviewState?> getReviewState(String decisionId) async {
    final rows = await _db.query(
      kTableSrsReviewState,
      where: 'decisionId = ?',
      whereArgs: [decisionId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return _reviewStateFromRow(rows.first);
    }

    final decRows = await _db.query(
      kTableSrsDecision,
      columns: ['canonicalStateId'],
      where: 'id = ?',
      whereArgs: [decisionId],
      limit: 1,
    );
    if (decRows.isNotEmpty) {
      final cId = decRows.first['canonicalStateId'] as String?;
      if (cId != null && cId.isNotEmpty && cId != decisionId) {
        final kRows = await _db.query(
          kTablePositionKnowledgeState,
          where: 'canonicalId = ?',
          whereArgs: [cId],
          limit: 1,
        );
        if (kRows.isNotEmpty) {
          return _knowledgeStateFromRow(kRows.first).toReviewState(decisionId);
        }
      }
    }

    // Direct lookup in position_knowledge_state if decisionId is already a canonicalId
    final directKRows = await _db.query(
      kTablePositionKnowledgeState,
      where: 'canonicalId = ?',
      whereArgs: [decisionId],
      limit: 1,
    );
    if (directKRows.isNotEmpty) {
      return _knowledgeStateFromRow(directKRows.first).toReviewState(decisionId);
    }

    return null;
  }

  @override
  Future<List<ReviewState>> getAllReviewStates() async {
    final rows = await _db.query(kTableSrsReviewState);
    final kRows = await _db.query(kTablePositionKnowledgeState);
    final map = <String, ReviewState>{};
    for (final row in rows) {
      final s = _reviewStateFromRow(row);
      map[s.decisionId] = s;
    }
    for (final row in kRows) {
      final k = _knowledgeStateFromRow(row);
      map[k.canonicalId] = k.toReviewState();
    }
    return map.values.toList(growable: false);
  }

  @override
  Future<List<ReviewState>> getDueReviewStates(DateTime now) async {
    final rows = await _db.query(
      kTableSrsReviewState,
      where: 'nextDueAt IS NULL OR nextDueAt <= ?',
      whereArgs: [now.toUtc().toIso8601String()],
      orderBy: 'nextDueAt ASC',
    );
    return rows.map(_reviewStateFromRow).toList(growable: false);
  }

  @override
  Future<List<ReviewState>> getReviewStatesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    const chunkSize = 400;
    final results = <ReviewState>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await _db.query(
        kTableSrsReviewState,
        where: 'decisionId IN ($placeholders)',
        whereArgs: chunk,
      );
      results.addAll(rows.map(_reviewStateFromRow));
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Review Events (SRS history)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveReviewEvent(ReviewEvent event) async {
    _logger.fine(
      'Saving review event: decisionId=${event.decisionId}, result=${event.result.name}, at=${event.when}',
    );
    await _db.insert(kTableSrsReviewEvent, _reviewEventRow(event));
  }

  @override
  Future<List<ReviewEvent>> getReviewEvents(String decisionId) async {
    final decRows = await _db.query(
      kTableSrsDecision,
      columns: ['canonicalStateId'],
      where: 'id = ?',
      whereArgs: [decisionId],
      limit: 1,
    );
    final queryIds = <String>{decisionId};
    if (decRows.isNotEmpty) {
      final cId = decRows.first['canonicalStateId'] as String?;
      if (cId != null && cId.isNotEmpty) {
        queryIds.add(cId);
      }
    }
    final placeholders = List.filled(queryIds.length, '?').join(',');
    final rows = await _db.query(
      kTableSrsReviewEvent,
      where: 'decisionId IN ($placeholders)',
      whereArgs: queryIds.toList(),
      orderBy: 'whenTimestamp ASC',
    );
    return rows.map(_reviewEventFromRow).toList(growable: false);
  }

  @override
  Future<int> getTodayReviewedPositionsCount(DateTime now) async {
    // Local calendar day boundary, expressed as the UTC form of that instant:
    // event timestamps are stored as UTC `toIso8601String()` values (review-4
    // C2), so the comparison arg must be UTC too or the device offset would
    // leak into the string comparison.
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final result = await _db.rawQuery(
      '''
      SELECT COUNT(DISTINCT decisionId) as count
      FROM $kTableSrsReviewEvent
      WHERE whenTimestamp >= ?
      ''',
      [startOfDay],
    );
    final count = Sqflite.firstIntValue(result) ?? 0;
    _logger.fine('Today reviewed positions count: $count (startOfDay: $startOfDay)');
    return count;
  }

  // ---------------------------------------------------------------------------
  // Row mappers
  // ---------------------------------------------------------------------------

  static Study _studyFromRow(Map<String, Object?> row) {
    final rawActive = row['isActive'];
    final isActive = rawActive == null || rawActive != 0;
    return Study(
      id: row['id']! as String,
      title: row['title']! as String,
      createdAt: DateTime.parse(row['createdAt']! as String),
      updatedAt: DateTime.parse(row['updatedAt']! as String),
      isActive: isActive,
      pgnHash: row['pgnHash'] as String?,
    );
  }

  /// The `srs_study` row for [study], stamped with [nowIso] when the study
  /// carries no timestamp of its own.
  ///
  /// One builder per table: each of these tables is written from the import
  /// transaction, the single save and the batch save, and a column added to one
  /// copy and missed in another loses a field silently.
  static Map<String, Object?> _studyRow(Study study, {required String nowIso}) => {
    'id': study.id,
    'title': study.title,
    'createdAt': study.createdAt?.toIso8601String() ?? nowIso,
    'updatedAt': study.updatedAt?.toIso8601String() ?? nowIso,
    'isActive': study.isActive ? 1 : 0,
    'pgnHash': study.pgnHash,
  };

  static Chapter _chapterFromRow(Map<String, Object?> row) {
    final treeJson = row['treeJson'] as String?;
    final root = treeJson != null && treeJson.isNotEmpty
        ? repertoireNodeFromJson(jsonDecode(treeJson) as Map<String, dynamic>)
        : null;

    final orientationStr = row['orientation'] as String?;
    final orientation = orientationStr == 'black' ? Side.black : Side.white;

    return Chapter(
      id: row['id']! as String,
      studyId: row['studyId']! as String,
      sourceOrder: (row['sourceOrder']! as num).toInt(),
      title: row['title'] as String?,
      startingFen: row['startingFen'] as String?,
      root: root,
      createdAt: DateTime.parse(row['createdAt']! as String),
      opening: row['opening'] as String?,
      orientation: orientation,
    );
  }

  /// The `srs_chapter` row for [chapter], tree included.
  ///
  /// One builder per table: each of these tables is written from the import
  /// transaction, the single save and the batch save, and a column added to one
  /// copy and missed in another loses a field silently.
  static Map<String, Object?> _chapterRow(Chapter chapter) => {
    'id': chapter.id,
    'studyId': chapter.studyId,
    'sourceOrder': chapter.sourceOrder,
    'title': chapter.title,
    'startingFen': chapter.startingFen,
    'createdAt': (chapter.createdAt ?? DateTime.now()).toIso8601String(),
    'treeJson': chapter.root != null ? jsonEncode(repertoireNodeToJson(chapter.root!)) : null,
    'opening': chapter.opening,
    'orientation': chapter.orientation.name,
  };

  static RepertoireDecision _decisionFromRow(Map<String, Object?> row) {
    final rawMoves = row['expectedMoves']! as String;
    return RepertoireDecision(
      id: row['id']! as String,
      studyId: row['studyId']! as String,
      chapterId: row['chapterId']! as String,
      nodeId: row['nodeId']! as String,
      expectedMoves: decodeExpectedMoves(rawMoves),
      canonicalStateId: row['canonicalStateId'] as String?,
    );
  }

  /// The `srs_decision` row for [decision].
  ///
  /// One builder per table: each of these tables is written from the import
  /// transaction, the single save and the batch save, and a column added to one
  /// copy and missed in another loses a field silently.
  static Map<String, Object?> _decisionRow(RepertoireDecision decision) => {
    'id': decision.id,
    'studyId': decision.studyId,
    'chapterId': decision.chapterId,
    'nodeId': decision.nodeId,
    'expectedMoves': encodeExpectedMoves(decision.expectedMoves),
    'canonicalStateId': decision.canonicalStateId ?? decision.canonicalId,
  };

  static ReviewState _reviewStateFromRow(Map<String, Object?> row) {
    final first = row['firstReviewedAt'] as String?;
    final last = row['lastReviewedAt'] as String?;
    final next = row['nextDueAt'] as String?;

    return ReviewState(
      decisionId: (row['canonicalId'] ?? row['decisionId'])! as String,
      firstReviewedAt: first != null ? DateTime.parse(first).toUtc() : null,
      lastReviewedAt: last != null ? DateTime.parse(last).toUtc() : null,
      nextDueAt: next != null ? DateTime.parse(next).toUtc() : null,
      repetitionCount: (row['repetitionCount']! as num).toInt(),
      lapseCount: (row['lapseCount']! as num).toInt(),
      stability: (row['stability']! as num).toDouble(),
      difficulty: (row['difficulty'] as num?)?.toDouble() ?? 5.0,
    );
  }

  /// The `srs_review_state` row for [state].
  ///
  /// One builder per table: each of these tables is written from the import
  /// transaction, the single save and the batch save, and a column added to one
  /// copy and missed in another loses a field silently.
  static Map<String, Object?> _reviewStateRow(ReviewState state) => {
    'decisionId': state.decisionId,
    'firstReviewedAt': state.firstReviewedAt?.toUtc().toIso8601String(),
    'lastReviewedAt': state.lastReviewedAt?.toUtc().toIso8601String(),
    'nextDueAt': state.nextDueAt?.toUtc().toIso8601String(),
    'repetitionCount': state.repetitionCount,
    'lapseCount': state.lapseCount,
    'stability': state.stability,
    'difficulty': state.difficulty,
  };

  static ReviewEvent _reviewEventFromRow(Map<String, Object?> row) {
    return ReviewEvent(
      decisionId: row['decisionId']! as String,
      when: DateTime.parse(row['whenTimestamp']! as String).toUtc(),
      result: ReviewResult.values.byName(row['result']! as String),
      oldState: reviewStateFromJson(
        jsonDecode(row['oldStateJson']! as String) as Map<String, dynamic>,
      ),
      newState: reviewStateFromJson(
        jsonDecode(row['newStateJson']! as String) as Map<String, dynamic>,
      ),
    );
  }

  /// The `srs_review_event` row for [event].
  ///
  /// One builder per table: each of these tables is written from the import
  /// transaction, the single save and the batch save, and a column added to one
  /// copy and missed in another loses a field silently.
  static Map<String, Object?> _reviewEventRow(ReviewEvent event) => {
    'decisionId': event.decisionId,
    'whenTimestamp': event.when.toUtc().toIso8601String(),
    'result': event.result.name,
    'oldStateJson': jsonEncode(reviewStateToJson(event.oldState)),
    'newStateJson': jsonEncode(reviewStateToJson(event.newState)),
  };
}
