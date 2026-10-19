// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:sqflite/sqflite.dart';

/// Removes `srs_review_state` rows that no reader can reach.
///
/// A mirror row is written next to the knowledge row it duplicates
/// (`saveAnswerBatch`, `savePositionKnowledgeStates`), and reads look it up by
/// decision id and by canonical id (`review_service.getReviewStatesByIds`, the
/// session's `reviewStates[canonicalId] ?? reviewStates[decisionId]`). So a row
/// whose key matches no decision — by `id` or `canonicalStateId` — and no
/// `position_knowledge_state.canonicalId` can never be read again.
///
/// The live v19 database held 67 such rows: the v14/v16 canonical rekeys moved
/// knowledge rows to new keys and rewrote `srs_decision.canonicalStateId`, but
/// left the mirrors behind under the superseded keys.
/// `rekeyCanonicalReviewState` now carries each mirror along with its knowledge
/// row, so no new ones are created; this sweep clears the ones already paid for.
///
/// Returns the number of rows removed. Only the review-state mirror is deleted:
/// review events are the history, are keyed by decision id, and are left
/// untouched.
Future<int> sweepOrphanedReviewStates(DatabaseExecutor db) async {
  const requiredTables = [kTableSrsReviewState, kTableSrsDecision, kTablePositionKnowledgeState];
  for (final table in requiredTables) {
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (rows.isEmpty) {
      // A fixture without the SRS tables is not a database to sweep.
      return 0;
    }
  }
  return await db.delete(
    kTableSrsReviewState,
    where:
        'NOT EXISTS (SELECT 1 FROM $kTableSrsDecision d WHERE d.id = $kTableSrsReviewState.decisionId) '
        'AND NOT EXISTS (SELECT 1 FROM $kTableSrsDecision c WHERE c.canonicalStateId = $kTableSrsReviewState.decisionId) '
        'AND NOT EXISTS (SELECT 1 FROM $kTablePositionKnowledgeState k WHERE k.canonicalId = $kTableSrsReviewState.decisionId)',
  );
}
