// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' as io;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'binding.dart';
import 'test_helpers.dart';
import 'test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('V6: Vertical Slice End-to-End Gate', () {
    late String dbPath;
    late Database db;
    late FixedClock clock;

    setUp(() async {
      await TestLichessBinding.instance.sharedPreferences.clear();
      final tempDir = await io.Directory.systemTemp.createTemp('srs_gate_test_');
      dbPath = '${tempDir.path}/gate_test.db';
      db = await databaseFactory.openDatabase(dbPath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
      clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
    });

    tearDown(() async {
      try {
        await db.close();
      } catch (_) {}
      final file = io.File(dbPath);
      try {
        if (await file.exists()) {
          await file.parent.delete(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets(
      'Full vertical slice lifecycle: import -> review -> correct -> lapse -> restart persistence',
      (tester) async {
        // -----------------------------------------------------------------------
        // Step 1: First Launch — Empty state UI
        // -----------------------------------------------------------------------
        final repo = SqliteStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith((ref) => service),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester, 200);

        expect(find.text('Bring your repertoire.'), findsOneWidget);
        expect(find.text('Choose file'), findsWidgets);

        // -----------------------------------------------------------------------
        // Step 2: Import real PGN into database
        // -----------------------------------------------------------------------
        const samplePgn = '''
[Event "Italian Game Repertoire"]
[Site "ChessSRS"]
[Date "2026.09.16"]
[White "Repertoire"]
[Black "Opponent"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 *
''';

        final importResult = importPgn(
          samplePgn,
          studyTitle: 'Italian Game',
          repertoireSide: Side.white,
        );
        expect(importResult.study.title, 'Italian Game');
        expect(importResult.decisions.length, 3); // 1. e4, 2. Nf3, 3. Bc4

        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        // -----------------------------------------------------------------------
        // Step 3: Trigger Review reload
        // -----------------------------------------------------------------------
        final element = tester.element(find.byType(ReviewScreen));
        final container = ProviderScope.containerOf(element);
        await tester.runAsync(() async {
          await container.read(reviewControllerProvider.notifier).reload();
        });
        await pumpAsync(tester);

        // Board is interactive and oriented to White
        expect(find.byType(Chessboard), findsOneWidget);
        // design/docs/01-identity.md names the everywhere scope `All repertoires`; the top bar
        // shows it, and the scope list's first row shows the same string when the drawer opens.
        expect(find.text('All repertoires'), findsOneWidget);
        // The chapter's own title, taken from [Event]. This PGN carries
        // [White "Repertoire"]/[Black "Opponent"] — this app's own placeholders, which the
        // importer used to read first and show as the chapter name.
        expect(find.text('Italian Game Repertoire'), findsOneWidget);
        expect(find.text('Repertoire vs Opponent'), findsNothing);
        expect(find.text('White to play'), findsOneWidget);

        // -----------------------------------------------------------------------
        // Step 4: Play correct move 1. e4
        // -----------------------------------------------------------------------
        await playMove(tester, 'e2', 'e4');

        // Auto-traverses Black's response 1... e5; board is set up for 2. Nf3
        await pumpAsync(tester, 700);

        // -----------------------------------------------------------------------
        // Step 5: Intentional Lapse on move 2 (play 2. d4 instead of 2. Nf3)
        // -----------------------------------------------------------------------
        await playMove(tester, 'd2', 'd4');
        await pumpAsync(tester, 100);

        // Verify lapse feedback banner and arrow
        expect(
          find.text('Play this move to continue. The position will come back soon.'),
          findsOneWidget,
        );

        // Reguess on the board: play the correct move 2. Nf3
        await playMove(tester, 'g1', 'f3');
        await pumpAsync(tester, 700);

        // -----------------------------------------------------------------------
        // Step 6: Simulate App Restart / Restart Durability (Invariants §1.3 & §3.1)
        // Close database and recreate repositories from persistent disk storage
        // -----------------------------------------------------------------------
        await tester.runAsync(() async {
          await db.close();

          final reopenedDb = await databaseFactory.openDatabase(dbPath);
          final reopenedRepo = SqliteStudyRepository(reopenedDb);

          // Verify study metadata survived restart
          final allStudies = await reopenedRepo.getAllStudies();
          expect(allStudies.length, 1);
          expect(allStudies.first.title, 'Italian Game');

          // Verify review states survived restart
          final whiteDecisions = await reopenedRepo.getDecisionsByStudy(allStudies.first.id);
          expect(whiteDecisions.length, 3);

          // 1. e4 was answered correctly -> repetitionCount should have incremented
          final e4Decision = whiteDecisions.firstWhere(
            (d) => d.expectedMoves.any((m) => m.san == 'e4'),
          );
          final e4State = await reopenedRepo.getReviewState(e4Decision.id);
          expect(e4State, isNotNull);
          expect(e4State!.repetitionCount, 1);
          expect(e4State.stability, greaterThanOrEqualTo(1.0));

          // 2. Nf3 suffered a lapse -> lapseCount should be 1
          final nf3Decision = whiteDecisions.firstWhere(
            (d) => d.expectedMoves.any((m) => m.san == 'Nf3'),
          );
          final nf3State = await reopenedRepo.getReviewState(nf3Decision.id);
          expect(nf3State, isNotNull);
          expect(nf3State!.lapseCount, 1);

          // Verify review events survived restart
          final events = await reopenedRepo.getReviewEvents(nf3Decision.id);
          expect(events.length, greaterThanOrEqualTo(1));
          expect(events.any((e) => e.result == ReviewResult.incorrect), isTrue);

          await reopenedDb.close();
        });
      },
    );
  });
}
