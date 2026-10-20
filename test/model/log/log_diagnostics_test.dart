// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/persistence/sqlite_study_repository.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_container.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  setUp(() async {
    Logger.root.level = Level.ALL;
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  group('Domain & Diagnostics Logger Audit', () {
    test('ReviewEngine and ReviewSession emit rich diagnostic log events', () {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);

      final clock = FixedClock(DateTime(2026, 9, 19, 10, 0));
      const pgn = '''
[Event "French Defense Test"]
[Site "ChessSRS"]
[Date "2026.09.19"]
[White "Opponent"]
[Black "User"]
[Result "*"]

1. e4 e6 2. d4 d5 *
''';

      final importResult = importPgn(
        pgn,
        studyTitle: 'French Defense Test',
        repertoireSide: Side.black,
      );
      final engine = ReviewEngine(clock: clock);

      final session = engine.createSession(
        studies: [importResult.study],
        chapters: importResult.chapters,
        decisions: importResult.decisions,
        reviewStates: const {},
        scope: const ReviewScope.all(),
        mode: ReviewMode.srs,
      );

      // Verify ReviewEngine logged session initialization
      expect(
        records.any(
          (r) => r.loggerName == 'ReviewEngine' && r.message.contains('ReviewSession created'),
        ),
        isTrue,
      );

      // Submit incorrect move (lapse)
      final lapseResult = session.submitMove(from: 'a7', to: 'a6');
      expect(lapseResult.isCorrect, isFalse);

      expect(
        records.any(
          (r) =>
              r.loggerName == 'ReviewEngine' &&
              r.level == Level.WARNING &&
              r.message.contains('Lapse on decision'),
        ),
        isTrue,
      );

      // Submit correct move
      final correctResult = session.submitMove(from: 'e7', to: 'e6');
      expect(correctResult.isCorrect, isTrue);

      expect(
        records.any(
          (r) =>
              r.loggerName == 'ReviewEngine' &&
              r.level == Level.INFO &&
              r.message.contains('Move correct'),
        ),
        isTrue,
      );

      subscription.cancel();
    });

    test(
      'StudyImporter emits diagnostic logs for import operations and orientation heuristics',
      () {
        final records = <LogRecord>[];
        final subscription = Logger.root.onRecord.listen(records.add);

        const pgn = '''
[Event "Black Repertoire Guide"]
[Site "ChessSRS"]
[Orientation "black"]

1. d4 Nf6 2. c4 e6 *
''';

        final result = importPgn(pgn, studyTitle: 'Black Repertoire Guide');

        expect(result.chapters.length, equals(1));
        expect(result.chapters.first.orientation, equals(Side.black));

        // Verify StudyImporter logs
        expect(
          records.any(
            (r) => r.loggerName == 'StudyImporter' && r.message.contains('Starting PGN import'),
          ),
          isTrue,
        );
        expect(
          records.any(
            (r) => r.loggerName == 'StudyImporter' && r.message.contains('PGN import completed'),
          ),
          isTrue,
        );
        expect(
          records.any(
            (r) =>
                r.loggerName == 'StudyImporter' &&
                r.message.contains('Orientation resolved via explicit header'),
          ),
          isTrue,
        );

        subscription.cancel();
      },
    );

    test('ChessFsrsScheduler emits diagnostic logs for memory scheduling', () {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);

      const scheduler = ChessFsrsScheduler(targetRetention: 0.88);
      final now = DateTime(2026, 9, 19, 10, 0);
      final initial = ReviewState.initial(decisionId: 'test-fsrs-1');

      final scheduled = scheduler.schedule(
        previous: initial,
        result: ReviewResult.correct,
        now: now,
      );

      expect(scheduled.repetitionCount, equals(1));
      expect(
        records.any(
          (r) =>
              r.loggerName == 'FsrsScheduler' &&
              r.message.contains('FSRS scheduled decision test-fsrs-1') &&
              r.message.contains('targetRetention=0.88'),
        ),
        isTrue,
      );

      subscription.cancel();
    });

    test('SqliteStudyRepository emits performance timing and operation logs', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);

      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final repo = SqliteStudyRepository(db);

      // Create test tables
      await db.execute('''
        CREATE TABLE srs_study(
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          isActive INTEGER NOT NULL DEFAULT 1,
          pgnHash TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE srs_chapter(
          id TEXT PRIMARY KEY,
          studyId TEXT NOT NULL,
          sourceOrder INTEGER NOT NULL,
          title TEXT,
          startingFen TEXT,
          createdAt TEXT NOT NULL,
          treeJson TEXT,
          opening TEXT,
          orientation TEXT NOT NULL DEFAULT 'white'
        )
      ''');
      await db.execute('''
        CREATE TABLE srs_decision(
          id TEXT PRIMARY KEY,
          studyId TEXT NOT NULL,
          chapterId TEXT NOT NULL,
          nodeId TEXT NOT NULL,
          expectedMoves TEXT NOT NULL,
          canonicalStateId TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE srs_review_event(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          decisionId TEXT NOT NULL,
          whenTimestamp TEXT NOT NULL,
          result TEXT NOT NULL,
          oldStateJson TEXT NOT NULL,
          newStateJson TEXT NOT NULL
        )
      ''');

      const pgn = '1. e4 e5 *';
      final importResult = importPgn(pgn, studyTitle: 'Performance Timing Study');

      await repo.saveImportResult(importResult);

      expect(
        records.any(
          (r) =>
              r.loggerName == 'StudyRepository' &&
              r.message.contains('Saved import result for study') &&
              r.message.contains('in '),
        ),
        isTrue,
      );

      final now = DateTime(2026, 9, 19, 10, 0);
      final count = await repo.getTodayReviewedPositionsCount(now);
      expect(count, equals(0));

      expect(
        records.any(
          (r) =>
              r.loggerName == 'StudyRepository' &&
              r.message.contains('Today reviewed positions count'),
        ),
        isTrue,
      );

      await db.close();
      subscription.cancel();
    });

    test('AppLogStorage saves and queries entries in database', () async {
      final container = await makeContainer(
        overrides: {
          databaseProvider: databaseProvider.overrideWith((ref) async {
            final testDb = await openAppDatabase(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
            ref.onDispose(testDb.close);
            return testDb;
          }),
        },
      );

      final storage = await container.read(appLogStorageProvider.future);
      await storage.save(
        AppLogEntry(
          // A fixed stamp: the page query filters on text, never on the time, so the wall
          // clock has no place in this fixture.
          logTime: DateTime.utc(2026, 1, 1),
          loggerName: 'DiagnosticTestLogger',
          levelValue: Level.WARNING.value,
          levelName: 'WARNING',
          message: 'Sample edge case warning trace for diagnostics audit',
        ),
      );

      final page = await storage.page(searchQuery: 'Sample edge case');

      expect(page.items.isNotEmpty, isTrue);
      expect(page.items.first.loggerName, equals('DiagnosticTestLogger'));
      expect(page.items.first.levelName, equals('WARNING'));
      expect(
        page.items.first.message,
        equals('Sample edge case warning trace for diagnostics audit'),
      );
    });
  });
}
