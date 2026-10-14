// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deliberately cites no SPEC invariant. Every performance number in this repo before
// PERF-FIX-24 came from a synthetic fixture: `session_constructor_cost_test.dart` builds a
// chain of N nodes in memory and times the constructor directly. That is the right harness for
// the constructor, and it is not evidence about this app, because a fixture is balanced and a
// real repertoire is not.
//
// This measures the whole path a user actually pays for — SQLite queries plus `ReviewSession`
// construction — against a real database, read from a COPY. The owner's library is real data
// and real review history: opening it read-write can corrupt it, and migrating it changes the
// thing being measured. See docs/tasks/PERF-FIX-24-real-library-measurement.md.
//
// Skips unless CHESS_SRS_PERF_DB points at a database, so CI (which has no owner library)
// reports a skip rather than a failure.
//
//   cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
//   CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db fvm flutter test test/perf/real_library_session_cost_test.dart
//
// Thresholds are deliberately far above anything measured. The deliverable here is the printed
// number, not the pass/fail; asserting a real frame budget would flake on a loaded runner and
// then get loosened until it means nothing.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Median of [runs] timed invocations, after [warmups] untimed ones.
///
/// Median, not mean: the constructor's first run includes JIT compilation and a single slow
/// sample should not move the reported figure. That distinction is not an afterthought — an
/// unwarmed run reads roughly 2x the warmed one, which is compilation rather than the code
/// under test.
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

/// Index of the largest entry, or -1 for an empty list.
int _indexOfMax(List<int> xs) {
  var best = 0;
  for (var i = 1; i < xs.length; i++) {
    if (xs[i] > xs[best]) best = i;
  }
  return best;
}

void main() {
  final dbPath = Platform.environment['CHESS_SRS_PERF_DB'];

  test('session start against a real library', () async {
    if (dbPath == null || !File(dbPath).existsSync()) {
      markTestSkipped(
        "CHESS_SRS_PERF_DB is unset or missing. This measures the owner's real library; "
        'it does not fall back to a synthetic fixture, which is the gap it exists to close.',
      );
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await openAppDatabase(databaseFactoryFfi, dbPath);
    final repo = SqliteStudyRepository(db);
    final clock = FixedClock(DateTime.now().toUtc());
    final service = ReviewService(repository: repo, clock: clock);

    try {
      // ---- The data shape driving everything below. Printed because a timing without the
      // shape that produced it is not comparable to anything.
      final all = await repo.getAllStudies();
      final studies = all.where((s) => s.isActive).toList();
      var decisions = 0;
      var chapters = 0;
      for (final s in studies) {
        final chs = await repo.getChaptersByStudy(s.id);
        chapters += chs.length;
        for (final c in chs) {
          decisions += (await repo.getDecisionsByChapter(c.id)).length;
        }
      }
      final due = await service.getDueSummary(studies: all);
      stdout.writeln('\n=== real library shape ===');
      stdout.writeln('active studies      ${studies.length}');
      stdout.writeln('chapters            $chapters');
      stdout.writeln('decisions           $decisions');
      stdout.writeln('due (all)           ${due.totalDueCount}');
      stdout.writeln('database size       ${(await File(dbPath).length()) ~/ (1024 * 1024)} MiB');

      // ---- Attribution. The synthetic harness timed ONLY the constructor and concluded
      // ~4 us/decision, which at 519 decisions is ~2 ms. If the real path is far above that,
      // the cost is in the queries, not the tree walk — and that is a different fix entirely.
      final queriesOnly = await medianOf(() => service.getDueSummary(studies: all));
      stdout.writeln('due queries only    ${queriesOnly.inMilliseconds} ms');

      // ---- Whole library: the cold path a user pays when opening review.
      final wholeLibrary = await medianOf(() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.startSession();
      });
      final combined = await medianOf(() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.loadSessionAndSummary(studies: all);
      });
      stdout.writeln('\n=== whole-library session start (median of 15, after 3 warmups) ===');
      stdout.writeln('startSession()          ${wholeLibrary.inMilliseconds} ms');
      stdout.writeln('loadSessionAndSummary() ${combined.inMilliseconds} ms');

      // ---- Single study: what a user pays on every subsequent open.
      final chapterCounts = <int>[];
      for (final s in studies) {
        chapterCounts.add((await repo.getChaptersByStudy(s.id)).length);
      }
      final biggest = chapterCounts.isEmpty
          ? -1
          : chapterCounts.reduce((a, b) => a > b ? a : b) == 0
          ? -1
          : _indexOfMax(chapterCounts);
      if (biggest >= 0) {
        final perStudy = await medianOf(() async {
          final s = ReviewService(repository: repo, clock: clock);
          await s.startSession(scope: ReviewScope.study(studies[biggest].id));
        });
        stdout.writeln('\n=== largest single study (${studies[biggest].title}) ===');
        stdout.writeln('startSession()      ${perStudy.inMilliseconds} ms');
      }

      // A ceiling loose enough never to flake, and still tight enough to catch a regression
      // of an order of magnitude rather than a slow machine.
      expect(
        wholeLibrary.inMilliseconds,
        lessThan(2000),
        reason: 'a real-library session start taking seconds is a regression, not a slow runner',
      );
    } finally {
      await db.close();
    }
  });
}
