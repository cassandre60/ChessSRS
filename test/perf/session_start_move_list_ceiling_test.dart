// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Session-start move-list ceiling, measured on the real library.
//
// Bounds every redesign that stops reading decision move lists during session
// construction — the "lazy expectedMoves" direction offered after §10 of
// performance-handoff. Two build-only variants over identical preloads: real
// move lists vs `const []` move lists. The delta is every constructor cost
// that depends on the CONTENT of expectedMoves (the per-expected-move
// canonical map writes in `_indexChapter` and the first prompt's copy); a raw
// row scan splits `decodeExpectedMoves`'s share out of `getAllDecisions`. The
// 2026-10-24 record at 31,182 decisions: delta ~30 ms of a ~550 ms preloaded
// build, decode share ~52 ms of the 145 ms mapping, 98.6% of rows carrying
// canonicalStateId — performance-handoff §11 holds the verdict and
// docs/open-questions.md Q15 the decision it leaves open.
//
// Deliberately cites no SPEC invariant — see session_constructor_cost_test.dart
// for why naming one here would count as a second reference and disarm
// red-team case rt-06.
//
// Skips unless CHESS_SRS_PERF_DB is set, and never falls back to a synthetic
// fixture: every cost here scales with the owner's real row counts.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'due_summary_attribution_test.dart' show interleavedRoundsOf, medianOf, percentileOf;

void main() {
  final dbPath = Platform.environment['CHESS_SRS_PERF_DB'];

  test('probe: constructor and row-mapping work that depends on move lists', () async {
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
    try {
      final repo = SqliteStudyRepository(db);
      final clock = FixedClock(DateTime.now().toUtc());
      final allStudies = await repo.getAllStudies();
      final allDecisions = await repo.getAllDecisions();
      final canonicalIds = allDecisions.map((d) => d.canonicalId).toSet().toList();
      final allQueryIds = {...allDecisions.map((d) => d.id), ...canonicalIds}.toList();
      final reviewStatesList = await repo.getReviewStatesByIds(allQueryIds);
      final kStates = await repo.getKnowledgeStatesByCanonicalIds(canonicalIds);
      final reviewStates = {for (final s in reviewStatesList) s.decisionId: s};
      for (final k in kStates) {
        reviewStates[k.canonicalId] = k.toReviewState();
      }
      final exposureThrottle = {
        for (final k in kStates)
          if (k.lastExposedAt != null) k.canonicalId: k.lastExposedAt!,
      };

      // Legacy rows are the only readers of the canonical map the constructor
      // builds from expectedMoves; print how much of the library is legacy.
      final withCanonicalId = allDecisions.where((d) => d.canonicalStateId != null).length;
      stdout.writeln(
        'decisions: ${allDecisions.length}, with canonicalStateId: $withCanonicalId '
        '(${(withCanonicalId * 100 / allDecisions.length).toStringAsFixed(1)}%)',
      );

      final emptyMoves = [
        for (final d in allDecisions)
          RepertoireDecision(
            id: d.id,
            studyId: d.studyId,
            chapterId: d.chapterId,
            nodeId: d.nodeId,
            expectedMoves: const [],
            canonicalStateId: d.canonicalStateId,
          ),
      ];

      Future<void> buildReal() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.startSession(
          preloadedStudies: allStudies,
          preloadedAllDecisions: allDecisions,
          preloadedReviewStates: reviewStates,
          preloadedExposureThrottle: exposureThrottle,
          preloadedUnlockedDecisionIds: const {},
        );
      }

      Future<void> buildEmptyMoves() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.startSession(
          preloadedStudies: allStudies,
          preloadedAllDecisions: emptyMoves,
          preloadedReviewStates: reviewStates,
          preloadedExposureThrottle: exposureThrottle,
          preloadedUnlockedDecisionIds: const {},
        );
      }

      Future<void> rawScan() async {
        final rows = await db.query(kTableSrsDecision);
        var n = 0;
        for (final row in rows) {
          n += row.length;
        }
        if (n == 0) throw StateError('unexpected empty decision table');
      }

      final parts = <String, Duration>{
        'getAllDecisions (full mapping)': await medianOf(() => repo.getAllDecisions()),
        'decision rows, no move decode': await medianOf(rawScan),
        'session build, real moves': await medianOf(buildReal),
        'session build, empty move lists': await medianOf(buildEmptyMoves),
      };
      stdout.writeln('\n=== move-list ceiling probe (median of 15, after 3 warmups) ===');
      parts.forEach((name, d) {
        stdout.writeln('${name.padRight(34)}${d.inMilliseconds.toString().padLeft(7)} ms');
      });
      final delta = parts['session build, real moves']! - parts['session build, empty move lists']!;
      final decodeShare =
          parts['getAllDecisions (full mapping)']! - parts['decision rows, no move decode']!;
      stdout.writeln(
        'constructor work that depends on move-list content (real - empty): '
        '${delta.inMilliseconds} ms',
      );
      stdout.writeln(
        'getAllDecisions share attributable to move decode: ${decodeShare.inMilliseconds} ms',
      );

      final interleaved = await interleavedRoundsOf({
        'session build, real moves': buildReal,
        'session build, empty move lists': buildEmptyMoves,
      });
      stdout.writeln('\n=== interleaved rotated rounds (min / p25 / median / p75 / max, ms) ===');
      for (final e in interleaved.entries) {
        final sorted = [...e.value]..sort();
        String f(double p) => (percentileOf(sorted, p) / 1000).toStringAsFixed(1);
        stdout.writeln(
          e.key.padRight(34) +
              '${f(0)} / ${f(0.25)} / ${f(0.5)} / ${f(0.75)} / ${f(1.0)}'.padLeft(34),
        );
      }
    } finally {
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
