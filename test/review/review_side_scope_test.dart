// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013, INV-030.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One game per side, so the two scopes have disjoint positions to count.
const String _whitePgn = '''
[Event "Test"]
[Orientation "white"]
1. e4 e5 2. Nf3 Nc6 *
''';

const String _blackPgn = '''
[Event "Test"]
[Orientation "black"]
1. d4 d5 2. c4 e6 *
''';

void main() {
  setUpAll(sqfliteFfiInit);

  group('side-scoped repertoires', () {
    late Directory tempDir;
    late String dbPath;
    late Database db;
    late SqliteStudyRepository repo;
    late ReviewService service;
    late FixedClock clock;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_side_scope_');
      dbPath = p.join(tempDir.path, 'side_scope.db');
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
      repo = SqliteStudyRepository(db);
      clock = FixedClock(DateTime.utc(2026, 10, 5, 12));
      service = ReviewService(repository: repo, clock: clock);

      await repo.saveImportResult(importPgn(_whitePgn, studyTitle: 'White book'));
      await repo.saveImportResult(importPgn(_blackPgn, studyTitle: 'Black book'));
    });

    tearDown(() async {
      await db.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<DueCountsSummary> summary([ReviewScope scope = const ReviewScope.all()]) {
      return repo.getAllStudies().then((studies) {
        return service.getDueSummary(studies: studies, scope: scope);
      });
    }

    test('each chapter reports the side it trains', () async {
      final orientations = await repo.getChapterOrientations();
      expect(orientations, hasLength(2));
      expect(orientations.values.toSet(), {Side.white, Side.black});
    });

    test('each repertoire button counts only its own side', () async {
      // Count the decisions per side directly, then require the button to report
      // exactly that. Deriving the expectation from the same chapter data the
      // button is built on is what makes a leak visible: a button that counted
      // every decision regardless of side would report the sum, not its own half.
      var whiteDecisions = 0;
      var blackDecisions = 0;
      for (final study in await repo.getAllStudies()) {
        for (final chapter in await repo.getChaptersByStudy(study.id)) {
          final count = (await repo.getDecisionsByChapter(chapter.id)).length;
          if (chapter.orientation == Side.white) {
            whiteDecisions += count;
          } else {
            blackDecisions += count;
          }
        }
      }
      expect(whiteDecisions, greaterThan(0));
      expect(blackDecisions, greaterThan(0));

      final s = await summary();

      expect(s.progressForSide(Side.white).totalDecisions, whiteDecisions);
      expect(s.progressForSide(Side.black).totalDecisions, blackDecisions);
      expect(s.dueCountForSide(Side.white), whiteDecisions);
      expect(s.dueCountForSide(Side.black), blackDecisions);
    });

    test('a side scope counts exactly that side', () async {
      final all = await summary();
      final white = await summary(const ReviewScope.white());
      final black = await summary(const ReviewScope.black());

      expect(white.totalDueCount, all.dueCountForSide(Side.white));
      expect(black.totalDueCount, all.dueCountForSide(Side.black));
      expect(white.totalDueCount + black.totalDueCount, all.totalDueCount);
    });

    test('a side session queues only that side’s positions', () async {
      final chapters = <String, Side>{};
      for (final study in await repo.getAllStudies()) {
        for (final chapter in await repo.getChaptersByStudy(study.id)) {
          chapters[chapter.id] = chapter.orientation;
        }
      }
      expect(chapters.values.toSet(), {Side.white, Side.black});

      // Walking the session is the only way to see what it actually queued, and
      // it is also the behaviour under test: each prompt must belong to a chapter
      // of the requested side, and no chapter of the other side may appear.
      Future<Set<String>> queuedChapterIds(ReviewScope scope) async {
        final session = await service.startSession(scope: scope);
        final seen = <String>{session.currentPrompt!.chapterId};
        var guard = 0;
        while (!session.isComplete && guard++ < 50) {
          final prompt = session.currentPrompt;
          if (prompt == null) break;
          expect(chapters[prompt.chapterId], scope.side);
          // Answering correctly walks the line; `skip` ends the session cleanly
          // without needing a legal move for every position.
          session.skip();
        }
        return seen;
      }

      final whiteChapters = await queuedChapterIds(const ReviewScope.white());
      final blackChapters = await queuedChapterIds(const ReviewScope.black());

      expect(whiteChapters, isNotEmpty);
      expect(blackChapters, isNotEmpty);
      expect(whiteChapters.intersection(blackChapters), isEmpty);
      expect(whiteChapters.every((id) => chapters[id] == Side.white), isTrue);
      expect(blackChapters.every((id) => chapters[id] == Side.black), isTrue);
    });

    test('a side session is smaller than the unscoped one', () async {
      final all = await service.startSession(scope: const ReviewScope.all());
      final white = await service.startSession(scope: const ReviewScope.white());

      expect(white.initialDueCount, greaterThan(0));
      expect(white.initialDueCount, lessThan(all.initialDueCount));
    });

    test('a paused study leaves both repertoire buttons', () async {
      final studies = await repo.getAllStudies();
      final blackStudy = studies.firstWhere((s) => s.title == 'Black book');
      await repo.updateStudyActive(blackStudy.id, false);

      final s = await summary();

      expect(s.dueCountForSide(Side.black), 0);
      expect(s.progressForSide(Side.black).totalDecisions, 0);
      expect(s.dueCountForSide(Side.white), greaterThan(0));
    });
  });
}
