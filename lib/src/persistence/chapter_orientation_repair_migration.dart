// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:dartchess/dartchess.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseExecutor;

/// Result of running [repairChapterOrientations].
class ChapterOrientationRepairResult {
  const ChapterOrientationRepairResult({required this.repaired, required this.unchanged});

  /// Chapters whose orientation was inverted/corrected and decisions re-derived.
  final int repaired;

  /// Chapters whose orientation was already correct.
  final int unchanged;
}

/// Repairs chapter orientations and re-derives decisions for chapters whose
/// study or chapter title explicitly indicates the intended perspective (INV-013),
/// correcting chapters where an overly strict keyword check or custom starting FEN
/// inverted the player perspective.
Future<ChapterOrientationRepairResult> repairChapterOrientations(DatabaseExecutor db) async {
  final rows = await db.rawQuery('''
    SELECT c.id, c.studyId, s.title AS studyTitle, c.title AS chapterTitle,
           c.startingFen, c.orientation, c.treeJson
    FROM $kTableSrsChapter c
    INNER JOIN $kTableSrsStudy s ON c.studyId = s.id
  ''');

  if (rows.isEmpty) {
    return const ChapterOrientationRepairResult(repaired: 0, unchanged: 0);
  }

  var repaired = 0;
  var unchanged = 0;

  for (final row in rows) {
    final chapterId = row['id']! as String;
    final studyId = row['studyId']! as String;
    final studyTitle = (row['studyTitle'] as String?)?.trim() ?? '';
    final chapterTitle = (row['chapterTitle'] as String?)?.trim() ?? '';
    final startingFen = row['startingFen'] as String?;
    final orientationStr = row['orientation'] as String?;
    final currentOrientation = orientationStr == 'black' ? Side.black : Side.white;
    final treeJson = row['treeJson'] as String?;

    Side startTurn = Side.white;
    if (startingFen != null && startingFen.trim().isNotEmpty) {
      try {
        startTurn = Setup.parseFen(startingFen.trim()).turn;
      } catch (_) {}
    }

    final headers = <String, String>{
      if (chapterTitle.isNotEmpty) 'ChapterName': chapterTitle,
      if (chapterTitle.isNotEmpty) 'Event': chapterTitle,
      if (studyTitle.isNotEmpty) 'StudyName': studyTitle,
      if (studyTitle.isNotEmpty) 'Study': studyTitle,
    };

    final resolved = resolveChapterOrientation(headers, startTurn: startTurn);

    if (resolved == currentOrientation) {
      unchanged++;
      continue;
    }

    // Update orientation on the chapter row
    await db.update(
      kTableSrsChapter,
      {'orientation': resolved.name},
      where: 'id = ?',
      whereArgs: [chapterId],
    );

    // Re-derive decisions from treeJson for the corrected orientation
    if (treeJson != null && treeJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(treeJson) as Map<String, dynamic>;
        final root = repertoireNodeFromJson(decoded);
        final newDecisions = deriveDecisionsForChapter(
          root: root,
          studyId: studyId,
          chapterId: chapterId,
          repertoireSide: resolved,
          startSide: startTurn,
        );

        await db.delete(kTableSrsDecision, where: 'chapterId = ?', whereArgs: [chapterId]);

        for (final d in newDecisions) {
          await db.insert(kTableSrsDecision, {
            'id': d.id,
            'studyId': d.studyId,
            'chapterId': d.chapterId,
            'nodeId': d.nodeId,
            'expectedMoves': encodeExpectedMoves(d.expectedMoves),
            'canonicalStateId': d.canonicalStateId,
            'fenKey': d.fenKey,
          });
        }
      } catch (_) {
        // If decoding treeJson fails, leave decisions as-is
      }
    }

    repaired++;
  }

  return ChapterOrientationRepairResult(repaired: repaired, unchanged: unchanged);
}
