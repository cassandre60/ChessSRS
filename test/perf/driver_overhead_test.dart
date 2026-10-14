// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Isolates SQL execution from driver overhead, and from row mapping.
//
// Three measurements of the same statements, because two earlier hypotheses died
// on them:
//
//   1. `getDueSummary` is slow because its SQL is slow  -> refuted, ~1.4 ms
//   2. it is slow because of ISO-8601 date parsing        -> refuted, 1.92 ms
//   3. it is slow because `toReviewState()` is heavy     -> refuted, 8 field copies
//
// All three were measured with python's sqlite3 or against a piece of the mapping
// in isolation. None of them measured the thing the app actually does: fetch a
// result set through sqflite_common_ffi, which hands Dart a Map per row with
// every column boxed. ~772 rows across two tables is ~7,300 value conversions
// across an FFI boundary, and python's driver was never going to show that.
//
// This measures the same SQL three ways through the same Dart driver the app uses,
// so the differences are attributable: raw driver fetch, then the repository's
// mapping on top, then the whole repository call.
//
// Deliberately cites no SPEC invariant — see session_constructor_cost_test.dart.
//
// Skips unless CHESS_SRS_PERF_DB is set. Does not fall back to a synthetic
// fixture: driver overhead scales with row count and column width, which is
// exactly what a fixture would get wrong.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Median of [runs] timed invocations after [warmups] untimed ones.
Future<Duration> medianOf(Future<void> Function() body, {int warmups = 3, int runs = 15}) async {
  for (var i = 0; i < warmups; i++) {
    await body();
  }
  final samples = <int>[];
  for (var i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return Duration(microseconds: samples[samples.length ~/ 2]);
}

void main() {
  final dbPath = Platform.environment['CHESS_SRS_PERF_DB'];

  test('separate SQL execution from FFI driver overhead', () async {
    if (dbPath == null || !File(dbPath).existsSync()) {
      markTestSkipped(
        "CHESS_SRS_PERF_DB is unset or missing. This measures the owner's real "
        'library; it does not fall back to a synthetic fixture.',
      );
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await openAppDatabase(databaseFactoryFfi, dbPath);
    final repo = SqliteStudyRepository(db);

    try {
      // 1. Driver fetch only. Same statements python measured at 0.43-0.45 ms.
      final rawReview = await medianOf(() => db.query(kTableSrsReviewState));
      final rawKnowledge = await medianOf(() => db.query(kTablePositionKnowledgeState));

      // 2. A statement that returns rows and columns but almost nothing else, so the
      // difference from (1) is marshalling rather than volume.
      final singleCol = await medianOf(
        () => db.rawQuery('SELECT decisionId FROM $kTableSrsReviewState'),
      );

      // 3. The repository method under investigation.
      final mapped = await medianOf(() => repo.getAllReviewStates());

      final rows = await db.rawQuery('SELECT COUNT(*) c FROM $kTableSrsReviewState');
      final n = (rows.first['c'] as num? ?? 0).toInt();

      stdout.writeln('\n=== driver overhead vs mapping ===');
      stdout.writeln('srs_review_state rows: $n');
      stdout.writeln(
        'raw fetch, SELECT *            ${(rawReview.inMicroseconds / 1000).toStringAsFixed(2)} ms  (python: 0.44 ms)',
      );
      stdout.writeln(
        'raw fetch, 1 column           ${(singleCol.inMicroseconds / 1000).toStringAsFixed(2)} ms',
      );
      stdout.writeln(
        'raw fetch, PKS               ${(rawKnowledge.inMicroseconds / 1000).toStringAsFixed(2)} ms  (python: 0.43 ms)',
      );
      stdout.writeln(
        '-- driver subtotal            ${((rawReview.inMicroseconds + rawKnowledge.inMicroseconds) / 1000).toStringAsFixed(2)} ms',
      );
      stdout.writeln(
        'getAllReviewStates() total    ${(mapped.inMicroseconds / 1000).toStringAsFixed(2)} ms',
      );
      stdout.writeln(
        '-- mapping remainder          ${((mapped.inMicroseconds - rawReview.inMicroseconds - rawKnowledge.inMicroseconds) / 1000).toStringAsFixed(2)} ms',
      );

      // Spread matters more than the median here. The same call has measured 16, 29 and
      // 36 ms across three harnesses on this database; a single median implies a precision
      // the measurement does not have.
      final spread = <int>[];
      for (var i = 0; i < 15; i++) {
        final sw = Stopwatch()..start();
        await repo.getAllReviewStates();
        sw.stop();
        spread.add(sw.elapsedMicroseconds);
      }
      spread.sort();
      stdout.writeln(
        '\ngetAllReviewStates spread: min ${(spread.first / 1000).toStringAsFixed(1)} '
        'median ${(spread[7] / 1000).toStringAsFixed(1)} max ${(spread.last / 1000).toStringAsFixed(1)} ms',
      );

      expect(mapped.inMilliseconds, lessThan(2000));
    } finally {
      await db.close();
    }
  });
}
