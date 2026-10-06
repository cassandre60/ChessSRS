// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/import/opening_name.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseExecutor;

/// What [repairSpuriousOpeningNames] changed.
class OpeningNameRepairResult {
  const OpeningNameRepairResult({required this.cleared, required this.kept});

  /// Rows whose opening was erased: a title that merely mentioned an opening.
  final int cleared;

  /// Rows left alone, whether they name a real family or a name this build
  /// simply does not recognise.
  final int kept;
}

/// Erases opening names that were never opening families.
///
/// P-OPENNAME stopped the importer from *creating* such names, but a study
/// imported before that fix still carries one: `White vs French` was stored in
/// `srs_chapter.opening` and still produces a drawer hub, backed by positions
/// that can never be reviewed (P-OPENNAME follow-up, owner report 2026-10-05).
/// The drawer's opening list is built from this column, so repairing it is the
/// only place the phantom can be removed — re-importing would not help, and the
/// user has no way to reach the chapter to fix it by hand.
///
/// Deliberately narrow. Only a name that [mentionsOpeningButIsNotFamily] is
/// cleared: one that plainly is a family, and one this build does not
/// recognise ("QGD Exchange Variation"), are both kept. A migration that
/// silently deleted names it merely failed to match would destroy correct data
/// on the way past.
///
/// The chapter keeps its title, its tree and its decisions; only the derived
/// family label goes, which is what makes this safe to run on a live library.
/// Safe to run more than once.
Future<OpeningNameRepairResult> repairSpuriousOpeningNames(DatabaseExecutor db) async {
  final rows = await db.query(
    kTableSrsChapter,
    columns: ['id', 'opening'],
    where: 'opening IS NOT NULL AND opening != ?',
    whereArgs: [''],
  );
  if (rows.isEmpty) {
    return const OpeningNameRepairResult(cleared: 0, kept: 0);
  }

  final spurious = <String>[];
  var kept = 0;
  for (final row in rows) {
    final name = (row['opening'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      continue;
    }
    if (mentionsOpeningButIsNotFamily(name)) {
      spurious.add(row['id']! as String);
    } else {
      kept++;
    }
  }

  if (spurious.isNotEmpty) {
    // Chunked like every other bulk write here: a library with thousands of
    // chapters would otherwise build a statement past SQLite's variable limit.
    for (final chunk in _chunks(spurious, 400)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.update(
        kTableSrsChapter,
        {'opening': null},
        where: 'id IN ($placeholders)',
        whereArgs: chunk,
      );
    }
  }

  return OpeningNameRepairResult(cleared: spurious.length, kept: kept);
}

Iterable<List<T>> _chunks<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}
