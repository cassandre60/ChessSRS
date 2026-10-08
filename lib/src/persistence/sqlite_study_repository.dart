// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:chess_srs/src/persistence/study_repository.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

final Logger _logger = Logger('StudyRepository');

/// Concrete SQLite implementation of [StudyRepository].
///
/// Ensures incremental persistence: review answers touch only the affected
/// decision's [ReviewState] and append one [ReviewEvent] without touching
/// study or chapter trees (QUALITY.md §1.5).
class SqliteStudyRepository implements StudyRepository {
  const SqliteStudyRepository(this._db);

  final Database _db;

  @override
  Future<void> saveImportResult(ImportResult result) async {
    final sw = Stopwatch()..start();
    await _db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert(kTableSrsStudy, {
        'id': result.study.id,
        'title': result.study.title,
        'createdAt': result.study.createdAt?.toIso8601String() ?? now,
        'updatedAt': result.study.updatedAt?.toIso8601String() ?? now,
        'isActive': result.study.isActive ? 1 : 0,
        'pgnHash': result.study.pgnHash,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final chapterBatch = txn.batch();
      for (final chapter in result.chapters) {
        final treeJson = chapter.root != null
            ? jsonEncode(repertoireNodeToJson(chapter.root!))
            : null;
        chapterBatch.insert(kTableSrsChapter, {
          'id': chapter.id,
          'studyId': chapter.studyId,
          'sourceOrder': chapter.sourceOrder,
          'title': chapter.title,
          'startingFen': chapter.startingFen,
          'createdAt': (chapter.createdAt ?? DateTime.now()).toIso8601String(),
          'treeJson': treeJson,
          'opening': chapter.opening,
          'orientation': chapter.orientation.name,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await chapterBatch.commit(noResult: true);

      final decisionBatch = txn.batch();
      for (final d in result.decisions) {
        decisionBatch.insert(kTableSrsDecision, {
          'id': d.id,
          'studyId': d.studyId,
          'chapterId': d.chapterId,
          'nodeId': d.nodeId,
          'expectedMoves': encodeExpectedMoves(d.expectedMoves),
          'canonicalStateId': d.canonicalStateId ?? d.canonicalId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await decisionBatch.commit(noResult: true);
    });
    sw.stop();
    _logger.info(
      'Saved import result for study ${result.study.id} ("${result.study.title}"): '
      '${result.chapters.length} chapters, ${result.decisions.length} decisions in ${sw.elapsedMilliseconds}ms',
    );
  }

  // ---------------------------------------------------------------------------
  // Studies
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveStudy(Study study) async {
    final now = DateTime.now().toIso8601String();
    await _db.insert(kTableSrsStudy, {
      'id': study.id,
      'title': study.title,
      'createdAt': study.createdAt?.toIso8601String() ?? now,
      'updatedAt': study.updatedAt?.toIso8601String() ?? now,
      'isActive': study.isActive ? 1 : 0,
      'pgnHash': study.pgnHash,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

    // Auto-backfill: if any existing studies have null pgnHash, inspect their chapters
    final unhashedRows = await _db.query(kTableSrsStudy, where: 'pgnHash IS NULL');
    for (final row in unhashedRows) {
      final study = _studyFromRow(row);
      final chapters = await getChaptersByStudy(study.id);
      if (chapters.isNotEmpty) {
        final computedHash = computeRepertoireTreeHash(chapters);
        await _db.update(
          kTableSrsStudy,
          {'pgnHash': computedHash},
          where: 'id = ?',
          whereArgs: [study.id],
        );
        if (computedHash == pgnHash &&
            (forSide == null || chapters.every((c) => c.orientation == forSide))) {
          return study.copyWith(pgnHash: computedHash);
        }
      }
    }

    return null;
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
          final sharedGuard =
              'canonicalId IN ($cPlaceholders) AND canonicalId NOT IN ( '
              'SELECT canonicalStateId FROM $kTableSrsDecision WHERE studyId != ? AND canonicalStateId IS NOT NULL)';
          await txn.delete(
            kTablePositionKnowledgeState,
            where: sharedGuard,
            whereArgs: [...chunk, id],
          );
          await txn.delete(
            kTableSrsReviewState,
            where:
                'decisionId IN ($cPlaceholders) AND decisionId NOT IN ( '
                'SELECT canonicalStateId FROM $kTableSrsDecision WHERE studyId != ? AND canonicalStateId IS NOT NULL)',
            whereArgs: [...chunk, id],
          );
          await txn.delete(
            kTableSrsReviewEvent,
            where:
                'decisionId IN ($cPlaceholders) AND decisionId NOT IN ( '
                'SELECT canonicalStateId FROM $kTableSrsDecision WHERE studyId != ? AND canonicalStateId IS NOT NULL)',
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
    final treeJson = chapter.root != null ? jsonEncode(repertoireNodeToJson(chapter.root!)) : null;

    await _db.insert(kTableSrsChapter, {
      'id': chapter.id,
      'studyId': chapter.studyId,
      'sourceOrder': chapter.sourceOrder,
      'title': chapter.title,
      'startingFen': chapter.startingFen,
      'createdAt': (chapter.createdAt ?? DateTime.now()).toIso8601String(),
      'treeJson': treeJson,
      'opening': chapter.opening,
      'orientation': chapter.orientation.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveChapters(List<Chapter> chapters) async {
    final batch = _db.batch();
    for (final chapter in chapters) {
      final treeJson = chapter.root != null
          ? jsonEncode(repertoireNodeToJson(chapter.root!))
          : null;

      batch.insert(kTableSrsChapter, {
        'id': chapter.id,
        'studyId': chapter.studyId,
        'sourceOrder': chapter.sourceOrder,
        'title': chapter.title,
        'startingFen': chapter.startingFen,
        'createdAt': (chapter.createdAt ?? DateTime.now()).toIso8601String(),
        'treeJson': treeJson,
        'opening': chapter.opening,
        'orientation': chapter.orientation.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
          const ownedElsewhere =
              'SELECT canonicalStateId FROM $kTableSrsDecision '
              'WHERE canonicalStateId IS NOT NULL';
          await txn.delete(
            kTablePositionKnowledgeState,
            where: 'canonicalId = ? AND canonicalId NOT IN ($ownedElsewhere)',
            whereArgs: [canonicalId],
          );
          await txn.delete(
            kTableSrsReviewState,
            where: 'decisionId = ? AND decisionId NOT IN ($ownedElsewhere)',
            whereArgs: [canonicalId],
          );
          await txn.delete(
            kTableSrsReviewEvent,
            where: 'decisionId = ? AND decisionId NOT IN ($ownedElsewhere)',
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
    await _db.insert(kTableSrsDecision, {
      'id': decision.id,
      'studyId': decision.studyId,
      'chapterId': decision.chapterId,
      'nodeId': decision.nodeId,
      'expectedMoves': encodeExpectedMoves(decision.expectedMoves),
      'canonicalStateId': decision.canonicalStateId ?? decision.canonicalId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveDecisions(List<RepertoireDecision> decisions) async {
    final batch = _db.batch();
    for (final d in decisions) {
      batch.insert(kTableSrsDecision, {
        'id': d.id,
        'studyId': d.studyId,
        'chapterId': d.chapterId,
        'nodeId': d.nodeId,
        'expectedMoves': encodeExpectedMoves(d.expectedMoves),
        'canonicalStateId': d.canonicalStateId ?? d.canonicalId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  @override
  Future<void> deleteDecisionsByStudy(String studyId) async {
    await _db.delete(kTableSrsDecision, where: 'studyId = ?', whereArgs: [studyId]);
  }

  // ---------------------------------------------------------------------------
  // Position Knowledge States (canonical SRS layer)
  // ---------------------------------------------------------------------------

  @override
  Future<void> savePositionKnowledgeState(PositionKnowledgeState state) async {
    await _db.insert(kTablePositionKnowledgeState, {
      'canonicalId': state.canonicalId,
      'firstReviewedAt': state.firstReviewedAt?.toIso8601String(),
      'lastReviewedAt': state.lastReviewedAt?.toIso8601String(),
      'nextDueAt': state.nextDueAt?.toIso8601String(),
      'repetitionCount': state.repetitionCount,
      'lapseCount': state.lapseCount,
      'stability': state.stability,
      'difficulty': state.difficulty,
      'latencyEmaMs': state.latencyEmaMs,
      'latencySampleCount': state.latencySampleCount,
      'lastExposedAt': state.lastExposedAt?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await saveReviewState(state.toReviewState(state.canonicalId));

    final matchingDecisions = await _db.query(
      kTableSrsDecision,
      columns: ['id'],
      where: 'canonicalStateId = ?',
      whereArgs: [state.canonicalId],
    );
    for (final dec in matchingDecisions) {
      final decId = dec['id']! as String;
      await saveReviewState(state.toReviewState(decId));
    }
  }

  @override
  Future<void> savePositionKnowledgeStates(List<PositionKnowledgeState> states) async {
    final batch = _db.batch();
    for (final s in states) {
      batch.insert(kTablePositionKnowledgeState, {
        'canonicalId': s.canonicalId,
        'firstReviewedAt': s.firstReviewedAt?.toIso8601String(),
        'lastReviewedAt': s.lastReviewedAt?.toIso8601String(),
        'nextDueAt': s.nextDueAt?.toIso8601String(),
        'repetitionCount': s.repetitionCount,
        'lapseCount': s.lapseCount,
        'stability': s.stability,
        'difficulty': s.difficulty,
        'latencyEmaMs': s.latencyEmaMs,
        'latencySampleCount': s.latencySampleCount,
        'lastExposedAt': s.lastExposedAt?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    await saveReviewStates(states.map((s) => s.toReviewState()).toList());
  }

  @override
  Future<void> saveAnswerBatch({
    required List<PositionKnowledgeState> knowledgeStates,
    ReviewEvent? event,
  }) async {
    if (knowledgeStates.isEmpty && event == null) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();

      for (final s in knowledgeStates) {
        batch.insert(kTablePositionKnowledgeState, {
          'canonicalId': s.canonicalId,
          'firstReviewedAt': s.firstReviewedAt?.toIso8601String(),
          'lastReviewedAt': s.lastReviewedAt?.toIso8601String(),
          'nextDueAt': s.nextDueAt?.toIso8601String(),
          'repetitionCount': s.repetitionCount,
          'lapseCount': s.lapseCount,
          'stability': s.stability,
          'difficulty': s.difficulty,
          'latencyEmaMs': s.latencyEmaMs,
          'latencySampleCount': s.latencySampleCount,
          'lastExposedAt': s.lastExposedAt?.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        batch.insert(kTableSrsReviewState, {
          'decisionId': s.canonicalId,
          'firstReviewedAt': s.firstReviewedAt?.toIso8601String(),
          'lastReviewedAt': s.lastReviewedAt?.toIso8601String(),
          'nextDueAt': s.nextDueAt?.toIso8601String(),
          'repetitionCount': s.repetitionCount,
          'lapseCount': s.lapseCount,
          'stability': s.stability,
          'difficulty': s.difficulty,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

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
            s.firstReviewedAt?.toIso8601String(),
            s.lastReviewedAt?.toIso8601String(),
            s.nextDueAt?.toIso8601String(),
            s.repetitionCount,
            s.lapseCount,
            s.stability,
            s.difficulty,
            s.canonicalId,
          ],
        );
      }

      if (event != null) {
        batch.insert(kTableSrsReviewEvent, {
          'decisionId': event.decisionId,
          'whenTimestamp': event.when.toIso8601String(),
          'result': event.result.name,
          'oldStateJson': jsonEncode(reviewStateToJson(event.oldState)),
          'newStateJson': jsonEncode(reviewStateToJson(event.newState)),
        });
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
      firstReviewedAt: first != null ? DateTime.parse(first) : null,
      lastReviewedAt: last != null ? DateTime.parse(last) : null,
      nextDueAt: next != null ? DateTime.parse(next) : null,
      repetitionCount: (row['repetitionCount']! as num).toInt(),
      lapseCount: (row['lapseCount']! as num).toInt(),
      stability: (row['stability']! as num).toDouble(),
      difficulty: (row['difficulty'] as num?)?.toDouble() ?? 5.0,
      latencyEmaMs: (row['latencyEmaMs'] as num?)?.toDouble(),
      latencySampleCount: (row['latencySampleCount'] as num?)?.toInt() ?? 0,
      lastExposedAt: exposed != null ? DateTime.parse(exposed) : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Review States (SRS)
  // ---------------------------------------------------------------------------

  @override
  Future<void> saveReviewState(ReviewState state) async {
    await _db.insert(kTableSrsReviewState, {
      'decisionId': state.decisionId,
      'firstReviewedAt': state.firstReviewedAt?.toIso8601String(),
      'lastReviewedAt': state.lastReviewedAt?.toIso8601String(),
      'nextDueAt': state.nextDueAt?.toIso8601String(),
      'repetitionCount': state.repetitionCount,
      'lapseCount': state.lapseCount,
      'stability': state.stability,
      'difficulty': state.difficulty,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveReviewStates(List<ReviewState> states) async {
    final batch = _db.batch();
    for (final s in states) {
      batch.insert(kTableSrsReviewState, {
        'decisionId': s.decisionId,
        'firstReviewedAt': s.firstReviewedAt?.toIso8601String(),
        'lastReviewedAt': s.lastReviewedAt?.toIso8601String(),
        'nextDueAt': s.nextDueAt?.toIso8601String(),
        'repetitionCount': s.repetitionCount,
        'lapseCount': s.lapseCount,
        'stability': s.stability,
        'difficulty': s.difficulty,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      whereArgs: [now.toIso8601String()],
      orderBy: 'nextDueAt ASC',
    );
    return rows.map(_reviewStateFromRow).toList(growable: false);
  }

  @override
  Future<List<ReviewState>> getReviewStatesByDecisions(List<String> decisionIds) async {
    if (decisionIds.isEmpty) return const [];
    const chunkSize = 400;
    final results = <ReviewState>[];
    for (var i = 0; i < decisionIds.length; i += chunkSize) {
      final chunk = decisionIds.sublist(
        i,
        i + chunkSize > decisionIds.length ? decisionIds.length : i + chunkSize,
      );
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
    await _db.insert(kTableSrsReviewEvent, {
      'decisionId': event.decisionId,
      'whenTimestamp': event.when.toIso8601String(),
      'result': event.result.name,
      'oldStateJson': jsonEncode(reviewStateToJson(event.oldState)),
      'newStateJson': jsonEncode(reviewStateToJson(event.newState)),
    });
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
    // Local midnight: event timestamps are local `toIso8601String()` values
    // (no offset suffix), and `now` comes from `SystemClock` (local wall time).
    // Using UTC midnight here shifted the day boundary by the device offset.
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
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

  static ReviewState _reviewStateFromRow(Map<String, Object?> row) {
    final first = row['firstReviewedAt'] as String?;
    final last = row['lastReviewedAt'] as String?;
    final next = row['nextDueAt'] as String?;

    return ReviewState(
      decisionId: (row['canonicalId'] ?? row['decisionId'])! as String,
      firstReviewedAt: first != null ? DateTime.parse(first) : null,
      lastReviewedAt: last != null ? DateTime.parse(last) : null,
      nextDueAt: next != null ? DateTime.parse(next) : null,
      repetitionCount: (row['repetitionCount']! as num).toInt(),
      lapseCount: (row['lapseCount']! as num).toInt(),
      stability: (row['stability']! as num).toDouble(),
      difficulty: (row['difficulty'] as num?)?.toDouble() ?? 5.0,
    );
  }

  static ReviewEvent _reviewEventFromRow(Map<String, Object?> row) {
    return ReviewEvent(
      decisionId: row['decisionId']! as String,
      when: DateTime.parse(row['whenTimestamp']! as String),
      result: ReviewResult.values.byName(row['result']! as String),
      oldState: reviewStateFromJson(
        jsonDecode(row['oldStateJson']! as String) as Map<String, dynamic>,
      ),
      newState: reviewStateFromJson(
        jsonDecode(row['newStateJson']! as String) as Map<String, dynamic>,
      ),
    );
  }
}
