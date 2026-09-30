// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/domain/position_knowledge_state.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

final _logger = Logger('CanonicalRekeyMigration');

/// Rewrites persisted canonical review IDs from the first-child key format to the
/// complete-contract format.
///
/// The canonical ID used to be `sha1("<fenKey>|<first accepted move>")`, which could not tell two
/// different questions asked at the same position apart. It is now
/// `sha1("<fenKey>|<every accepted move, sorted>")`. That is a different string for most decisions,
/// so every persisted `canonicalStateId` and every `position_knowledge_state` row keyed by the old
/// format would be orphaned — the position would look never-reviewed and a user's accumulated
/// stability, due dates and history would silently reset.
///
/// This walks the stored chapter trees to recover each decision's position, recomputes the ID
/// under the new rule, and rewrites both tables. The answer set is read back from
/// `srs_decision.expectedMoves` rather than re-derived from the tree, so the rewrite cannot drift
/// from the decisions that were actually persisted.
///
/// Safe to run more than once: a decision already on the new format recomputes to itself and is
/// left alone.
Future<CanonicalRekeyResult> rekeyCanonicalReviewState(DatabaseExecutor db) async {
  final fenKeysByChapter = await _loadFenKeysByChapter(db);

  final decisions = await db.query(
    kTableSrsDecision,
    columns: ['id', 'chapterId', 'nodeId', 'expectedMoves', 'canonicalStateId'],
  );

  // old canonical id -> new canonical id, for the ids that actually move.
  final renames = <String, String>{};
  // decision row id -> its new canonical id.
  final decisionUpdates = <String, String>{};
  // Decisions whose position could not be recovered, so their ID cannot be recomputed.
  var skipped = 0;

  for (final row in decisions) {
    final oldId = row['canonicalStateId'] as String?;
    if (oldId == null) continue;

    // Both columns are NOT NULL in the schema.
    final chapterId = row['chapterId']! as String;
    final nodeId = row['nodeId']! as String;
    final fenKey = fenKeysByChapter[chapterId]?[nodeId];
    if (fenKey == null) {
      // No tree, or no such node in it. Leaving the old id in place keeps the existing state
      // reachable under its current key, which is strictly better than orphaning it.
      skipped++;
      continue;
    }

    final rawMoves = row['expectedMoves'] as String?;
    final decisionId = row['id'] as String?;
    if (rawMoves == null || decisionId == null) {
      skipped++;
      continue;
    }

    final moves = decodeExpectedMoves(rawMoves);
    final newId = canonicalKeyForPosition(fenKey, moves.map((move) => move.uci));
    if (newId == oldId) continue;

    renames[oldId] = newId;
    decisionUpdates[decisionId] = newId;
  }

  if (renames.isEmpty) {
    return CanonicalRekeyResult(
      decisionsRemapped: 0,
      statesRemapped: 0,
      statesMerged: 0,
      skipped: skipped,
    );
  }

  final states = await db.query(kTablePositionKnowledgeState);
  final statesByOldId = <String, Map<String, Object?>>{
    for (final row in states)
      if (row['canonicalId'] is String) row['canonicalId']! as String: row,
  };

  // New id -> the row that should survive under it.
  final merged = <String, Map<String, Object?>>{};
  var mergeCount = 0;
  for (final entry in renames.entries) {
    final existing = merged[entry.value];
    if (existing == null) {
      final row = statesByOldId[entry.key];
      // Copied, not aliased: the primary key is rewritten below.
      if (row != null) merged[entry.value] = Map<String, Object?>.of(row);
    } else {
      mergeCount++;
      final incoming = statesByOldId[entry.key];
      // A decision that was never reviewed has no knowledge row; there is
      // nothing to merge, so keep the surviving row instead of crashing.
      if (incoming == null) continue;
      if (_knowledgeProgress(row: incoming, incumbent: existing)) {
        merged[entry.value] = Map<String, Object?>.of(incoming);
      }
    }
  }

  // The primary key changes, so the moved rows are removed and rewritten rather than updated:
  // two old ids can land on the same new one, which an in-place UPDATE could not express.
  for (final oldId in renames.keys) {
    await db.delete(kTablePositionKnowledgeState, where: 'canonicalId = ?', whereArgs: [oldId]);
  }
  for (final entry in merged.entries) {
    await db.insert(
      kTablePositionKnowledgeState,
      entry.value..['canonicalId'] = entry.key,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  for (final entry in decisionUpdates.entries) {
    await db.update(
      kTableSrsDecision,
      {'canonicalStateId': entry.value},
      where: 'id = ?',
      whereArgs: [entry.key],
    );
  }

  return CanonicalRekeyResult(
    decisionsRemapped: decisionUpdates.length,
    statesRemapped: merged.length,
    statesMerged: mergeCount,
    skipped: skipped,
  );
}

/// What a rekey pass changed, for logging and tests.
class CanonicalRekeyResult {
  const CanonicalRekeyResult({
    required this.decisionsRemapped,
    required this.statesRemapped,
    required this.statesMerged,
    required this.skipped,
  });

  /// Decisions whose stored canonical id was rewritten.
  final int decisionsRemapped;

  /// Knowledge-state rows written under a new canonical id.
  final int statesRemapped;

  /// How many of those were collisions, where two old ids resolved to one new id and the
  /// less-practised state was folded into the more-practised one.
  final int statesMerged;

  /// Decisions left untouched because their position could not be recovered from a stored tree.
  final int skipped;
}

/// chapterId -> nodeId -> position identity.
Future<Map<String, Map<String, String>>> _loadFenKeysByChapter(DatabaseExecutor db) async {
  final chapters = await db.query(kTableSrsChapter, columns: ['id', 'treeJson']);
  final result = <String, Map<String, String>>{};

  for (final row in chapters) {
    final treeJson = row['treeJson'] as String?;
    if (treeJson == null || treeJson.isEmpty) continue;
    try {
      final chapterId = row['id']! as String;
      final root = repertoireNodeFromJson(jsonDecode(treeJson) as Map<String, dynamic>);
      result[chapterId] = _collectFenKeys(root);
    } catch (e, st) {
      // A chapter whose tree cannot be read is skipped whole. Its decisions keep their current
      // ids, so nothing is lost — the states simply stay under the key they already use.
      _logger.warning('Skipping chapter ${row['id']} during canonical rekey', e, st);
    }
  }
  return result;
}

Map<String, String> _collectFenKeys(RepertoireNode node) {
  final result = <String, String>{node.id: node.fenKey};
  for (final child in node.children) {
    result.addAll(_collectFenKeys(child));
  }
  return result;
}

/// Whether [row] should replace [incumbent] when two old ids collapse onto one new id.
///
/// Deterministic, and biased towards the state that represents more practice, so a merge never
/// silently discards the further-advanced of two histories:
///
///  1. more repetitions,
///  2. then the later last review,
///  3. then the higher stability,
///  4. then the lower lapse count,
///  5. then the lexicographically smaller id, so equal states resolve the same way every run.
bool _knowledgeProgress({
  required Map<String, Object?> row,
  required Map<String, Object?> incumbent,
}) {
  int intOf(Map<String, Object?> row, String key) => (row[key] as num?)?.toInt() ?? 0;
  double doubleOf(Map<String, Object?> row, String key) => (row[key] as num?)?.toDouble() ?? 0.0;
  String? timeOf(Map<String, Object?> row, String key) => row[key] as String?;

  final byRepetitions = intOf(
    row,
    'repetitionCount',
  ).compareTo(intOf(incumbent, 'repetitionCount'));
  if (byRepetitions != 0) return byRepetitions > 0;

  final lastA = timeOf(row, 'lastReviewedAt');
  final lastB = timeOf(incumbent, 'lastReviewedAt');
  final byLastReviewed = (lastA ?? '').compareTo(lastB ?? '');
  if (byLastReviewed != 0) return byLastReviewed > 0;

  final byStability = doubleOf(row, 'stability').compareTo(doubleOf(incumbent, 'stability'));
  if (byStability != 0) return byStability > 0;

  final byLapses = intOf(row, 'lapseCount').compareTo(intOf(incumbent, 'lapseCount'));
  if (byLapses != 0) return byLapses < 0;

  return (row['canonicalId']! as String).compareTo(incumbent['canonicalId']! as String) < 0;
}

/// The result of a backfill pass, for logging and tests.
class LegacyBackfillResult {
  const LegacyBackfillResult({required this.statesCreated, required this.collisionsMerged});

  /// Canonical positions that gained a knowledge state they had no row for.
  final int statesCreated;

  /// How many of those had more than one legacy row to choose between — a transposition, where
  /// two occurrences of the same position each carried their own state.
  final int collisionsMerged;
}

/// Gives every canonical position a `position_knowledge_state` row derived from legacy state.
///
/// The v10 migration created `position_knowledge_state` and `srs_decision.canonicalStateId`
/// without ever copying anything into them, so an install that predates v10 has all of its review
/// history in `srs_review_state` and none in the canonical table.
///
/// The damage is not that the history is unreadable — the repository still falls back to the
/// legacy table — but that it is read per *occurrence*. A position reached by transposition has one
/// canonical id and two decisions pointing at it, each with its own legacy row, so the same
/// position would be scheduled from two different sets of numbers depending on which occurrence
/// asked. Collapsing them here is what makes a shared position actually share one memory.
///
/// Runs after [rekeyCanonicalReviewState] so it matches legacy rows against the keys the importer
/// now generates. Safe to run more than once: a canonical position that already has a row is left
/// alone.
Future<LegacyBackfillResult> backfillCanonicalStatesFromLegacy(DatabaseExecutor db) async {
  final decisions = await db.query(
    kTableSrsDecision,
    columns: ['id', 'canonicalStateId'],
    where: 'canonicalStateId IS NOT NULL',
  );
  if (decisions.isEmpty) {
    return const LegacyBackfillResult(statesCreated: 0, collisionsMerged: 0);
  }

  // occurrence decision id -> canonical id
  final canonicalByDecisionId = <String, String>{};
  for (final row in decisions) {
    final canonical = row['canonicalStateId']! as String;
    if (canonical.isNotEmpty) {
      canonicalByDecisionId[row['id']! as String] = canonical;
    }
  }
  if (canonicalByDecisionId.isEmpty) {
    return const LegacyBackfillResult(statesCreated: 0, collisionsMerged: 0);
  }

  // Canonical positions that already have a row win: the canonical table is the newer record.
  final existing = <String>{};
  for (final row in await db.query(kTablePositionKnowledgeState, columns: ['canonicalId'])) {
    final id = row['canonicalId'];
    if (id is String) existing.add(id);
  }

  // Gather the legacy rows that belong to a canonical position still missing one.
  final candidates = <String, Map<String, Object?>>{};
  final seenPerCanonical = <String, int>{};
  for (final row in await db.query(kTableSrsReviewState)) {
    final decisionId = row['decisionId'];
    if (decisionId is! String) continue;
    final canonical = canonicalByDecisionId[decisionId];
    if (canonical == null || existing.contains(canonical)) continue;

    seenPerCanonical[canonical] = (seenPerCanonical[canonical] ?? 0) + 1;
    final current = candidates[canonical];
    if (current == null) {
      candidates[canonical] = Map<String, Object?>.of(row)..['canonicalId'] = canonical;
    } else if (_knowledgeProgress(row: row, incumbent: current)) {
      candidates[canonical] = Map<String, Object?>.of(row)..['canonicalId'] = canonical;
    }
  }

  var collisions = 0;
  for (final entry in candidates.entries) {
    if ((seenPerCanonical[entry.key] ?? 0) > 1) collisions++;
    await db.insert(
      kTablePositionKnowledgeState,
      // The legacy row is keyed by decisionId; the canonical table is keyed by canonicalId, so
      // the row is projected rather than copied wholesale.
      {
        'canonicalId': entry.key,
        'firstReviewedAt': entry.value['firstReviewedAt'],
        'lastReviewedAt': entry.value['lastReviewedAt'],
        'nextDueAt': entry.value['nextDueAt'],
        'repetitionCount': entry.value['repetitionCount'] ?? 0,
        'lapseCount': entry.value['lapseCount'] ?? 0,
        'stability': entry.value['stability'] ?? 0.0,
        'difficulty': entry.value['difficulty'] ?? 5.0,
        'latencyEmaMs': entry.value['latencyEmaMs'],
        'latencySampleCount': entry.value['latencySampleCount'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  return LegacyBackfillResult(statesCreated: candidates.length, collisionsMerged: collisions);
}
