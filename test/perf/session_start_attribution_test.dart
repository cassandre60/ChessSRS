// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Session-start attribution, third measurement pass on the real library.
//
// The 2026-10-24 record (performance-handoff §9) measured a whole-library
// `startSession()` at 795 ms on the 31k-decision library and attributed
// `getDueSummary()` (~170 ms) but not the session path itself. This harness
// splits `startSession()`'s all-studies path into its parts: the studies and
// chapter loads, `getAllDecisions()` (the 61% suspect from the summary
// attribution — the session path loads the same full table), the review-state
// load, and the engine's `createSession`, measured directly by calling
// `startSession` with every preload provided so no database call runs. The
// remainder (whole minus parts) is the orchestration the parts do not cover.
//
// The 2026-10-14 pass taught that row mapping, not SQLite, dominated the
// summary at the then-current shape; the same may hold here at 60x the rows,
// which would invert an index-first fix. Measure before believing either way.
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

/// Keeps the compiler from folding the forced decode away.
void _touch(Object? _) {}

void main() {
  final dbPath = Platform.environment['CHESS_SRS_PERF_DB'];

  test('attribute the whole-library session start to its parts', () async {
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
      final activeIds = allStudies.where((s) => s.isActive).map((s) => s.id).toList();
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

      // Build-only: every preload provided, so startSession runs the engine's
      // createSession and nothing queries the database.
      Future<void> buildOnly() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.startSession(
          preloadedStudies: allStudies,
          preloadedAllDecisions: allDecisions,
          preloadedReviewStates: reviewStates,
          preloadedExposureThrottle: exposureThrottle,
          preloadedUnlockedDecisionIds: const {},
        );
      }

      Future<void> reviewDataLoad() async {
        final statesList = await repo.getReviewStatesByIds(allQueryIds);
        final states = {for (final s in statesList) s.decisionId: s};
        final ks = await repo.getKnowledgeStatesByCanonicalIds(canonicalIds);
        for (final k in ks) {
          states[k.canonicalId] = k.toReviewState();
        }
        // Same throttle map _loadReviewData builds.
        final throttle = <String, DateTime>{
          for (final k in ks)
            if (k.lastExposedAt != null) k.canonicalId: k.lastExposedAt!,
        };
        if (throttle.isEmpty && states.isEmpty) throw StateError('unexpected empty load');
      }

      Future<void> wholeSession() async {
        final s = ReviewService(repository: repo, clock: clock);
        await s.startSession();
      }

      final parts = <String, Duration>{
        'getAllStudies': await medianOf(() => repo.getAllStudies()),
        'getChaptersByStudyIds': await medianOf(() => repo.getChaptersByStudyIds(activeIds)),
        'getAllDecisions': await medianOf(() => repo.getAllDecisions()),
        'review data load (SQL + maps)': await medianOf(reviewDataLoad),
        'getUnlockedDecisionIds': await medianOf(() => repo.getUnlockedDecisionIds()),
        // Control for the lazy-tree hypothesis: `Chapter.root` jsonDecodes the
        // chapter's whole tree on first access (`_root ??= rootResolver?.call()`),
        // and the session constructor's chapter-index loop reads `chapter.root`.
        // This target times exactly that forced decode over the same chapters,
        // with no session in the loop.
        'force-decode all chapter trees': await medianOf(() async {
          final chapters = await repo.getChaptersByStudyIds(activeIds);
          for (final c in chapters) {
            _touch(c.root);
          }
        }),
        'session build (no DB)': await medianOf(buildOnly),
      };
      final whole = await medianOf(wholeSession);

      stdout.writeln('\n=== session-start attribution (median of 15, after 3 warmups) ===');
      var sum = Duration.zero;
      parts.forEach((name, d) {
        stdout.writeln('${name.padRight(34)}${d.inMilliseconds.toString().padLeft(7)} ms');
        sum += d;
      });
      stdout.writeln(
        '${'-- sum of parts'.padRight(34)}${sum.inMilliseconds.toString().padLeft(7)} ms',
      );
      stdout.writeln(
        '${'whole startSession()'.padRight(34)}${whole.inMilliseconds.toString().padLeft(7)} ms',
      );
      final remainder = whole - sum;
      stdout.writeln(
        '(remainder = whole - parts; covers service construction, preload plumbing,'
        ' and any part this harness did not split out)',
      );
      stdout.writeln(
        'remainder ${remainder.inMilliseconds} ms'
        ' (${(remainder.inMilliseconds * 100 / whole.inMilliseconds).toStringAsFixed(0)}%)',
      );

      final interleaved = await interleavedRoundsOf({
        'getAllDecisions': () => repo.getAllDecisions(),
        'review data load (SQL + maps)': reviewDataLoad,
        'session build (no DB)': buildOnly,
        'whole startSession()': wholeSession,
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

      expect(
        whole.inMilliseconds,
        lessThan(5000),
        reason:
            'a real-library session start taking many seconds is a regression, not a slow runner',
      );
    } finally {
      await db.close();
    }
    // 7 targets x (3 warmups + 15 runs), several near a second each: the 30 s
    // default per-test timeout cannot hold this run as the library grows.
  }, timeout: const Timeout(Duration(minutes: 10)));
}
