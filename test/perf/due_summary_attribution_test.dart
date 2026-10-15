// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// PERF-FIX-24, second pass: attribute the ~28 ms that `getDueSummary` spends
// outside its SQL.
//
// The first pass established that a whole-library `startSession()` costs 37-39 ms
// and that `getDueSummary()` alone accounts for 26-30 ms of it. That number was
// attributed to "the queries" on the reasonable assumption that the queries were
// the cost. They are not. Timing the six SQL statements `getDueSummary` issues
// directly against the same database puts all of them together at ~1.4 ms, so
// roughly 95% of the cost is Dart-side row mapping, not SQLite.
//
// That inverts the obvious optimisation: an index would buy nothing, because the
// database is not the bottleneck. What would help is not mapping 528 rows into
// domain objects in order to count them.
//
// Deliberately cites no SPEC invariant — see session_constructor_cost_test.dart for
// why naming one here would count as a second reference and disarm red-team case rt-06.
//
// Skips unless CHESS_SRS_PERF_DB is set, and never falls back to a synthetic
// fixture: row-mapping cost scales with row count, and a fixture's row count is
// exactly the thing that would make a synthetic answer wrong.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
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

  test('attribute the due-summary cost to SQL versus row mapping', () async {
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
    final service = ReviewService(repository: repo, clock: FixedClock(DateTime.now().toUtc()));

    try {
      final studies = await repo.getAllStudies();

      // Canonical ids come from the decisions themselves; resolved once, outside every
      // timed body, so each measurement is the call and not its setup.
      final decisions = await repo.getAllDecisions();
      final canonicalIds = decisions
          .map((d) => d.canonicalStateId)
          .whereType<String>()
          .toSet()
          .toList();

      // The six calls getDueSummary makes, timed individually through the repository so
      // each figure includes whatever Dart-side mapping that method performs.
      final calls = <String, Future<void> Function()>{
        'getChapterOpenings': () => repo.getChapterOpenings(),
        'getChapterOrientations': () => repo.getChapterOrientations(),
        'getChapterStudyIds': () => repo.getChapterStudyIds(),
        'getAllDecisions': () => repo.getAllDecisions(),
        'getTallyDecisions': () => repo.getTallyDecisions(),
        'getAllReviewStates': () => repo.getAllReviewStates(),
        'getKnowledgeStates': () => repo.getKnowledgeStatesByCanonicalIds(canonicalIds),
      };

      final measured = <String, int>{};
      var sum = 0;
      for (final entry in calls.entries) {
        final us = await medianOf(entry.value).then((d) => d.inMicroseconds);
        measured[entry.key] = us;
        sum += us;
      }

      final total = await medianOf(() => service.getDueSummary(studies: studies));

      stdout.writeln('\n=== getDueSummary attribution (median of 15, after 3 warmups) ===');
      stdout.writeln(
        'rows in play: decisions=${decisions.length} '
        'canonical=${canonicalIds.length}',
      );
      for (final e in measured.entries) {
        final pct = sum == 0 ? 0.0 : 100 * e.value / sum;
        stdout.writeln(
          '${e.key.padRight(26)} ${(e.value / 1000).toStringAsFixed(2)} ms  '
          '(${pct.toStringAsFixed(0)}%)',
        );
      }
      stdout.writeln('${'-- sum of parts'.padRight(26)} ${(sum / 1000).toStringAsFixed(2)} ms');
      stdout.writeln(
        '${'getDueSummary() total'.padRight(26)} '
        '${(total.inMicroseconds / 1000).toStringAsFixed(2)} ms',
      );

      // Direct measurement of the suspected cost, with no database in the loop.
      final sample = DateTime.utc(2026, 9, 16, 10, 0, 0).toIso8601String();
      const fieldsPerRow = 3;
      final rows = (await repo.getAllReviewStates()).length;
      final parseCost = await medianOf(() async {
        var sink = 0;
        for (var i = 0; i < rows * fieldsPerRow; i++) {
          sink += DateTime.parse(sample).toUtc().millisecondsSinceEpoch;
        }
        expect(sink, isNonZero);
      });
      stdout.writeln("\n=== direct cost of the mapper's date parsing ===");
      stdout.writeln('rows returned       $rows');
      stdout.writeln(
        'DateTime.parse x${rows * fieldsPerRow}   '
        '${(parseCost.inMicroseconds / 1000).toStringAsFixed(2)} ms',
      );

      expect(total.inMilliseconds, lessThan(2000));
    } finally {
      await db.close();
    }
  });
}

/// Measures the raw cost of parsing the ISO-8601 strings the review-state mapper
/// parses, with no database involved at all.
///
/// Exists because the first hypothesis — "it is the queries" — was wrong (the SQL
/// is ~1.4 ms total), and the second — "it is `DateTime.parse`" — was nearly
/// discarded on a comparison that turned out to be invalid: the control call was
/// given 66 canonical ids and so fetched 66 rows, not the 347 the naive reading
/// assumed. This measures the parse directly instead of inferring it from two
/// repository calls that do not do the same work.
