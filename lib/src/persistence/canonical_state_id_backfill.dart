// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseExecutor;

/// Result of [backfillDecisionCanonicalStateIds].
class CanonicalStateIdBackfillResult {
  const CanonicalStateIdBackfillResult({required this.filled, required this.skipped});

  final int filled;
  final int skipped;
}

/// Fills `srs_decision.canonicalStateId` for rows an older import left NULL.
///
/// A NULL canonical id makes `RepertoireDecision.canonicalId` fall back to the
/// decision id, so every duplicate occurrence of one question becomes its own
/// memory item and is queued separately — the same position asked many times in
/// one session. The identity is the same one the importer writes:
/// `canonicalKeyForPosition(fenKey, accepted move UCI set, repertoireSide:
/// chapter orientation)`.
///
/// Only rows with a non-empty `fenKey` are filled. A row the v21 fen-key
/// backfill could not resolve is skipped: without the position there is no
/// identity to compute, and guessing one would fork memory.
///
/// Safe to run more than once: rows that already have an id are left alone.
Future<CanonicalStateIdBackfillResult> backfillDecisionCanonicalStateIds(
  DatabaseExecutor db,
) async {
  final present = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
    [kTableSrsDecision, kTableSrsChapter],
  );
  if (present.length < 2) {
    return const CanonicalStateIdBackfillResult(filled: 0, skipped: 0);
  }

  final rows = await db.rawQuery('''
    SELECT d.id, d.fenKey, d.expectedMoves, c.orientation
    FROM $kTableSrsDecision d
    INNER JOIN $kTableSrsChapter c ON d.chapterId = c.id
    WHERE d.canonicalStateId IS NULL
  ''');

  var filled = 0;
  var skipped = 0;
  final updates = <MapEntry<String, String>>[];
  for (final row in rows) {
    final fenKey = row['fenKey'] as String?;
    final movesRaw = row['expectedMoves'] as String?;
    if (fenKey == null || fenKey.isEmpty || movesRaw == null || movesRaw.isEmpty) {
      skipped++;
      continue;
    }
    final List<RepertoireMove> moves;
    try {
      moves = decodeExpectedMoves(movesRaw);
    } catch (_) {
      skipped++;
      continue;
    }
    if (moves.isEmpty) {
      skipped++;
      continue;
    }
    final side = (row['orientation'] as String?) == 'black' ? Side.black : Side.white;
    final canonical = canonicalKeyForPosition(
      fenKey,
      moves.map((m) => m.uci),
      repertoireSide: side,
    );
    updates.add(MapEntry(row['id']! as String, canonical));
  }

  final batch = db.batch();
  for (final update in updates) {
    batch.update(
      kTableSrsDecision,
      {'canonicalStateId': update.value},
      where: 'id = ?',
      whereArgs: [update.key],
    );
    filled++;
  }
  await batch.commit(noResult: true);
  return CanonicalStateIdBackfillResult(filled: filled, skipped: skipped);
}
