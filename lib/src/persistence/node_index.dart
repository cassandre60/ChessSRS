// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Flat FEN→node index (`srs_node`) and its v22 backfill.
///
/// The review session's transposition lookup needs the repertoire node at an
/// arbitrary position. Building that from the chapter trees meant decoding every
/// `treeJson` synchronously on the first wrong move (INV-050). This table holds
/// the same information as flat rows, so a lookup decodes only the chapter that
/// actually holds the target.
library;

import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:sqflite/sqflite.dart';

/// Flat `srs_node` rows for [root]'s subtree, ranked depth-first pre-order.
List<Map<String, Object?>> nodeRowsForChapter(String chapterId, RepertoireNode root) {
  final rows = <Map<String, Object?>>[];
  var rank = 0;
  void walk(RepertoireNode node) {
    rows.add({
      'chapterId': chapterId,
      'nodeId': node.id,
      'fenKey': node.fenKey,
      'nodeRank': rank++,
    });
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(root);
  return rows;
}

/// Creates `srs_node` if missing and backfills it from every chapter's stored
/// tree. Idempotent: a chapter that already has rows is skipped, so re-running
/// on an already-upgraded database changes nothing (v22).
Future<int> backfillNodeIndex(Database db) async {
  final schema = db.batch();
  createNodeIndexTable(schema);
  await schema.commit(noResult: true);

  // A minimal legacy fixture may predate srs_chapter (or its treeJson column);
  // there is then nothing to index, and querying a missing table would fail the
  // whole upgrade.
  final columns = await db.rawQuery('PRAGMA table_info($kTableSrsChapter)');
  if (!columns.any((c) => c['name'] == 'treeJson')) return 0;

  final chapters = await db.query(kTableSrsChapter, columns: ['id', 'treeJson']);
  final batch = db.batch();
  var inserted = 0;
  for (final row in chapters) {
    final chapterId = row['id']! as String;
    final treeJson = row['treeJson'] as String?;
    if (treeJson == null || treeJson.isEmpty) continue;
    final existing = await db.query(
      kTableSrsNode,
      columns: ['nodeId'],
      where: 'chapterId = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    if (existing.isNotEmpty) continue;
    final root = repertoireNodeFromJson(jsonDecode(treeJson) as Map<String, dynamic>);
    for (final nodeRow in nodeRowsForChapter(chapterId, root)) {
      batch.insert(kTableSrsNode, nodeRow, conflictAlgorithm: ConflictAlgorithm.replace);
      inserted++;
    }
  }
  await batch.commit(noResult: true);
  return inserted;
}
