// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Enforces `QUALITY.md` §4.1: local move legality validation and repertoire lookup must
/// complete in under 16 milliseconds, one display frame.
///
/// The invariant had no test behind it at all. The suite's only `Stopwatch` assertions were on
/// engine search and opening-book load, neither of which is the critical path, so a regression
/// here would have shipped silently against a documented non-negotiable.
///
/// The bound is asserted against the median of the submissions rather than a single one. A
/// single sample on a shared CI runner measures the runner, not the code: it fails at random and
/// then gets "fixed" by loosening the threshold until it stops meaning anything. The median is
/// the quantity the invariant is about — the typical answer is within a frame — and the full
/// sample list is printed on failure so a real regression stays diagnosable.
///
/// The seeded repertoire is six decisions deep, so a session yields six samples. That is enough
/// for a median and keeps the assertion honest about what it measured; a longer line would not
/// change what is being checked, only the shape of the distribution, and the p90 is printed
/// alongside so an emerging tail is visible without loosening anything.
///
/// SRS mode is used deliberately, not practice. Practice skips the incremental write, and the
/// interesting claim is that the write stays *incremental* — a full rewrite of the study tree on
/// every move is precisely the regression §4.2 forbids, and practice mode cannot detect it.
/// Timing the in-memory validation and the incremental transaction together is the real
/// critical path; a test that avoided the database would prove nothing about it.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('QUALITY.md §4.1 move validation latency', () {
    late Directory tempDir;
    late String dbPath;
    late FixedClock clock;
    late DateTime now;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_latency_test_');
      dbPath = p.join(tempDir.path, 'latency.db');
      now = DateTime.utc(2026, 9, 29, 12, 0, 0);
      clock = FixedClock(now);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// A linear Italian repertoire six decisions deep, so the session has a run of correct
    /// answers to walk rather than the single decision the other service tests use.
    Future<SqliteStudyRepository> seedRepository(Database db) async {
      final repo = SqliteStudyRepository(db);

      final study = Study(
        id: 's1',
        title: 'Latency Repertoire',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      // (nodeId, fenKey, move) for the opening line walked below.
      const line = [
        ('n1', 'start', ('e2', 'e4')),
        ('n2', 'after_e4', ('g1', 'f3')),
        ('n3', 'after_nf3', ('f1', 'c4')),
        ('n4', 'after_bc4', ('c2', 'c3')),
        ('n5', 'after_c3', ('d2', 'd3')),
        ('n6', 'after_d3', ('e1', 'g1')), // castling, the fiddliest lookup of the six
      ];

      RepertoireNode nodeAt(int index) {
        if (index >= line.length) {
          return const RepertoireNode(id: 'nX', fen: 'startfen', fenKey: 'startkey', children: []);
        }
        final (id, key, (from, to)) = line[index];
        return RepertoireNode(
          id: id,
          fen: 'fen_$key',
          fenKey: key,
          incomingMove: RepertoireMove(from: from, to: to, san: 'm$index'),
          children: [nodeAt(index + 1)],
        );
      }

      final chapter = Chapter(
        id: 'c1',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Chapter 1',
        root: nodeAt(0),
        createdAt: now,
      );

      await repo.saveStudy(study);
      await repo.saveChapter(chapter);

      for (var i = 0; i < line.length; i++) {
        final (id, _, (from, to)) = line[i];
        await repo.saveDecision(
          RepertoireDecision(
            id: 'd${i + 1}',
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: id,
            expectedMoves: [RepertoireMove(from: from, to: to, san: 'm$i')],
          ),
        );
      }

      return repo;
    }

    test('a graded move validates and persists well inside one display frame', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
      });

      final repo = await seedRepository(db);
      final service = ReviewService(repository: repo, clock: clock);
      await service.startSession();

      const submissions = 30;
      final samples = <Duration>[];

      for (var i = 0; i < submissions; i++) {
        final prompt = service.activeSession?.currentPrompt;
        if (prompt == null) break;
        final expected = prompt.decision.expectedMoves.first;

        final stopwatch = Stopwatch()..start();
        final result = await service.submitMove(from: expected.from, to: expected.to);
        stopwatch.stop();

        if (!result.isCorrect) {
          fail('move ${expected.from}-${expected.to} was graded incorrect; the fixture is wrong');
        }
        samples.add(stopwatch.elapsed);
      }

      expect(
        samples.length,
        greaterThanOrEqualTo(6),
        reason: 'the session should have graded at least the six seeded decisions',
      );

      samples.sort();
      final median = samples[samples.length ~/ 2];
      final p90 = samples[(samples.length * 0.9).floor()];

      // ignore: avoid_print
      print(
        'move submit (validate + lookup + incremental write): '
        'median ${median.inMicroseconds}us, p90 ${p90.inMicroseconds}us, '
        'max ${samples.last.inMicroseconds}us over ${samples.length} submissions',
      );

      expect(
        median,
        lessThan(const Duration(milliseconds: 16)),
        reason:
            'QUALITY.md §4.1 bounds the review critical loop at 16ms. Median of '
            '${samples.length} submissions was ${median.inMicroseconds}us; '
            'sorted samples: $samples',
      );
    });
  });
}
