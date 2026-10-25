// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/persistence/canonical_rekey_migration.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:sqflite/sqflite.dart';

/// The result of the v21 fen-key backfill, for logging and tests.
class FenKeyBackfillResult {
  const FenKeyBackfillResult({required this.decisionsFilled, required this.skipped});

  /// Decisions whose row gained the position identity of their node.
  final int decisionsFilled;

  /// Decisions left null: their chapter tree could not be read or their node
  /// no longer exists in it. They fall back to the decoded node at session
  /// time, exactly as every row did before the column existed.
  final int skipped;
}

/// Copies each decision's position identity (its node's fen key) onto its row.
///
/// Session construction needs the position a decision sits on to build the
/// transposition and canonical indexes; before v21 that identity lived only
/// inside the chapter's tree JSON, so building those indexes force-decoded
/// nearly the whole library on whole-library review (performance-handoff §10).
///
/// Nothing in the app mutates a stored chapter tree after import, so the copy
/// cannot go stale: the importer writes it for new decisions, this migration
/// backfills existing ones, and a row whose tree cannot be read stays null
/// rather than guessing.
///
/// Safe to run more than once: a row already carrying a fen key is left alone.
Future<FenKeyBackfillResult> backfillDecisionFenKeys(DatabaseExecutor db) async {
  // Fixture databases can carry a version without either SRS table; skip
  // whole rather than throwing, as the v20 sweep does.
  final present = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
    [kTableSrsDecision, kTableSrsChapter],
  );
  if (present.length < 2) {
    return const FenKeyBackfillResult(decisionsFilled: 0, skipped: 0);
  }

  final fenKeysByChapter = await loadFenKeysByChapter(db);

  final decisions = await db.query(
    kTableSrsDecision,
    columns: ['id', 'chapterId', 'nodeId', 'fenKey'],
  );
  var filled = 0;
  var skipped = 0;
  final updates = <MapEntry<String, String>>[];
  for (final row in decisions) {
    final existing = row['fenKey'] as String?;
    if (existing != null && existing.isNotEmpty) continue;
    final chapterId = row['chapterId']! as String;
    final nodeId = row['nodeId']! as String;
    final fenKey = fenKeysByChapter[chapterId]?[nodeId];
    if (fenKey == null || fenKey.isEmpty) {
      skipped++;
      continue;
    }
    updates.add(MapEntry(row['id']! as String, fenKey));
    filled++;
  }
  if (updates.isNotEmpty) {
    final batch = db.batch();
    for (final update in updates) {
      batch.update(
        kTableSrsDecision,
        {'fenKey': update.value},
        where: 'id = ?',
        whereArgs: [update.key],
      );
    }
    await batch.commit(noResult: true);
  }
  return FenKeyBackfillResult(decisionsFilled: filled, skipped: skipped);
}
