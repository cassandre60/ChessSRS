// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-060, INV-062, INV-063.

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/view/study/study_screen.dart';
import 'package:chess_srs/src/widgets/board.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReviewScreen widget tests', () {
    late Database db;
    late SqliteStudyRepository repo;
    late FixedClock clock;

    setUp(() async {
      await TestLichessBinding.instance.sharedPreferences.clear();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
      repo = SqliteStudyRepository(db);
      clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('shows first launch empty state when no studies exist', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester, 500);

      expect(find.text('Bring your study.'), findsOneWidget);
      expect(find.text('Choose file'), findsWidgets);
    });

    testWidgets('tapping import button opens RepertoireImportDialog', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      await tester.tap(find.text('Choose file').first);
      await tester.pump();
      await pumpAsync(tester);

      expect(find.byType(RepertoireImportDialog), findsOneWidget);
    });

    testWidgets('renders active board and handles moves when studies exist', (tester) async {
      // Setup a study with 1. e4 e5 2. Nf3
      final importResult = importPgn(
        '1. e4 e5 2. Nf3 *',
        studyTitle: 'King Pawn Repertoire',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Board is rendered with Chessboard and top bar shows colour squares
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.byType(ColourSquare).first, findsOneWidget);
      expect(find.byType(ColourSquare).last, findsOneWidget);

      // Play correct move: e2 -> e4
      await playMove(tester, 'e2', 'e4');

      // Wait for move pacing (user move -> pause -> opponent reply 1... e5 -> pause)
      await pumpAsync(tester, 700);

      // Next due move is 2. Nf3 (opponent move e5 was auto-played)
      await playMove(tester, 'g1', 'f3');
      await pumpAsync(tester, 700);

      // Session is now complete (0 due)
      expect(find.text('Nothing due.'), findsOneWidget);
    });

    testWidgets('displays lapse feedback and allows user to reguess on the board', (tester) async {
      final importResult = importPgn(
        '1. d4 d5 *',
        studyTitle: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Play incorrect move: e2 -> e4 instead of d2 -> d4
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 100);

      // Shows lapse feedback banner
      expect(
        find.text('Play this move to continue. The position will come back soon.'),
        findsOneWidget,
      );
      // Recall has failed, so the action says what it does: reveal the study move by
      // playing it on the learner's behalf. A bare "Skip" here mislabeled the action.
      expect(find.text('Reveal answer'), findsOneWidget);
      expect(find.text('Skip'), findsNothing);

      // Reguess on the board by playing the correct study move d2 -> d4
      await playMove(tester, 'd2', 'd4');
      await pumpAsync(tester, 700);

      // Re-prompted for the failed item (re-queued for practice)
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.text('White to play'), findsOneWidget);

      // Play 1. d4 successfully on the re-test
      await playMove(tester, 'd2', 'd4');
      await pumpAsync(tester, 700);

      // Session is now complete (0 due)
      expect(find.text('Nothing due.'), findsOneWidget);
    });

    testWidgets('a lapse offers Open in analysis at the drilled position', (tester) async {
      // A correction state is a dead end today: the answer is shown but there is no way to
      // explore *why* it is the move. The bridge must open the analysis board at the exact
      // position being drilled, not at the start position.
      final importResult = importPgn(
        '1. d4 d5 *',
        studyTitle: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Prompt state shows no escape hatch: the button must not leak a way out of recall.
      expect(find.text('Open in analysis'), findsNothing);

      // Play incorrect move: e2 -> e4 instead of d2 -> d4
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 100);

      // Lapse state shows the bridge under the answer.
      expect(find.text('Open in analysis'), findsOneWidget);

      await tester.tap(find.text('Open in analysis'));
      await pumpAsync(tester, 200);
      await tester.pump(const Duration(milliseconds: 500));

      // Analysis opens at the drilled decision point: the lapse happened on move 1, so
      // boardPosition is still the start position (the wrong e4 never became state).
      final screen = tester.widget<AnalysisScreen>(find.byType(AnalysisScreen));
      final options = screen.options;
      expect(options, isA<Pgn>());
      expect(
        (options as Pgn).pgn,
        contains('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
      );
    });

    testWidgets('Reveal answer plays the study move and continues the session', (tester) async {
      // The correction state offers no way out except replaying the move by hand or
      // requeueing: tapping Reveal answer must do what a correct reguess does — advance
      // through the retry path with the lapse standing — rather than swallowing the tap
      // or requeueing silently.
      final importResult = importPgn(
        '1. d4 d5 *',
        studyTitle: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Prompt state still says Skip: recall has not failed yet.
      expect(find.text('Skip'), findsOneWidget);

      // Play incorrect move: e2 -> e4 instead of d2 -> d4
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 100);

      await tester.tap(find.text('Reveal answer'));
      await pumpAsync(tester, 700);

      // The correction is gone and the session continued (re-queued card re-prompted,
      // exactly as after a manual correct reguess).
      expect(
        find.text('Play this move to continue. The position will come back soon.'),
        findsNothing,
      );
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.text('White to play'), findsOneWidget);
    });

    testWidgets('a screen reader is told whether the answer was right', (tester) async {
      // design/docs/04-screens-and-flows.md §6 requires the verdict announced through a live
      // region, and this is the assertion that was missing. A wrong answer already puts the
      // study move on screen, so a sighted player is told; a *correct* one shows nothing at
      // all, because the product is deliberately quiet on success. That left a screen-reader user
      // with no confirmation, and no way to tell a right answer from a wrong one.
      final sem = tester.ensureSemantics();

      // The move carries a note, which is what pauses auto-advancement and so holds the verdict on
      // screen long enough to read. Without a note a correct answer advances within a few
      // milliseconds, and the announcement is deliberately transient -- which is exactly what a
      // live region is for, and what makes it untestable in the un-commented case.
      final importResult = importPgn(
        '1. e4 {Attacks the centre} e5 2. Nf3 {Develops} Nc6 *',
        studyTitle: 'Live Region Study',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // While the question is open there is no verdict to announce.
      expect(find.bySemanticsLabel(RegExp('Correct')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Not this move')), findsNothing);

      // The correct move, announced as the move that was played. Not the expected one: a
      // transposition can make an alternative equally correct, in which case the study move is
      // not what the player actually played.
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 100);
      expect(find.bySemanticsLabel('Correct. e4.'), findsOneWidget);

      // Past it, the next question is open and the verdict is gone rather than lingering.
      await tester.tap(find.widgetWithText(SrsPillButton, 'Continue'));
      await pumpAsync(tester, 400);
      expect(find.bySemanticsLabel(RegExp('Correct')), findsNothing);

      // A wrong move, announced with the study move. The study's second move is Nf3, so
      // d4 is the mistake here and Nf3 is what should have been played.
      await playMove(tester, 'd2', 'd4');
      await pumpAsync(tester, 100);
      expect(find.bySemanticsLabel('Not this move. The study move is Nf3.'), findsOneWidget);

      // flutter_test checks at end of test that every handle was disposed, so this cannot be an
      // addTearDown.
      sem.dispose();
    });

    testWidgets('study actions sheet opens StudyScreen via Analyze', (tester) async {
      final importResult = importPgn(
        '1. e4 e5 2. Nf3 Nc6 *',
        studyTitle: 'King Pawn Repertoire',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      // Open study options sheet. design/docs/03-components.md §6.4 keeps row actions off the row
      // itself, so the sheet opens from a long-press rather than from a permanent `…`.
      await tester.longPress(find.text('King Pawn Repertoire'));
      await pumpAsync(tester);

      // Tap Analyze
      await tester.tap(find.text('Analyze'));
      await pumpAsync(tester, 200);
      await tester.pump(const Duration(milliseconds: 500));

      // StudyScreen is now opened
      expect(find.byType(StudyScreen), findsOneWidget);
    });

    testWidgets('multi-chapter study opens StudyScreen via Analyze', (tester) async {
      const multiChapterPgn = '''
[Event "Chapter 1: Open Games"]
1. e4 e5 *

[Event "Chapter 2: French Defense"]
1. e4 e6 *
''';
      final importResult = importPgn(
        multiChapterPgn,
        studyTitle: 'Multi Chapter Repertoire',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      // Open study options sheet. design/docs/03-components.md §6.4 keeps row actions off the row
      // itself, so the sheet opens from a long-press rather than from a permanent `…`.
      await tester.longPress(find.text('Multi Chapter Repertoire'));
      await pumpAsync(tester);

      // Tap Analyze
      await tester.tap(find.text('Analyze'));
      await pumpAsync(tester, 200);
      await tester.pump(const Duration(milliseconds: 500));

      // StudyScreen is now opened
      expect(find.byType(StudyScreen), findsOneWidget);
    });

    testWidgets(
      'comments are withheld during active recall to prevent move spoilers and revealed on lapse',
      (tester) async {
        final importResult = importPgn(
          '1. e4 {Best by test} 1... e5 2. Nf3 {Attacks the e5 pawn} *',
          studyTitle: 'King Pawn with Comments',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Verify comment is NOT shown before guessing (anti-spoiler)
        expect(find.text('Best by test'), findsNothing);

        // Play incorrect move: d2 -> d4 instead of e2 -> e4
        await playMove(tester, 'd2', 'd4');
        await pumpAsync(tester, 100);

        // Now the comment is revealed as explanation
        expect(find.text('Best by test'), findsOneWidget);
      },
    );

    testWidgets(
      'board shapes and arrows from PGN comments are withheld before move and revealed on lapse',
      (tester) async {
        final importResult = importPgn(
          '1. e4 {[%cal Gf3e5][%csl Re5] Attacks the center} e5 *',
          studyTitle: 'King Pawn with Shapes',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Before guessing: BoardWidget has NO shapes (anti-spoiler)
        var board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(board.shapes, isEmpty);
        expect(find.text('Attacks the center'), findsNothing);

        // Play incorrect move: d2 -> d4 instead of e2 -> e4
        await playMove(tester, 'd2', 'd4');
        await pumpAsync(tester, 100);

        // After lapse: displays SrsMoveArrow PLUS the comment shapes (arrow and circle) on BoardWidget
        expect(find.byType(SrsMoveArrow), findsOneWidget);
        board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(board.shapes.isNotEmpty, isTrue);
        expect(
          board.shapes.any((s) => s is Arrow && s.orig == Square.f3 && s.dest == Square.e5),
          isTrue,
        );
        expect(board.shapes.any((s) => s is Circle && s.orig == Square.e5), isTrue);

        // Clean comment text without raw [%cal ...] markup
        expect(find.text('Attacks the center'), findsOneWidget);
        expect(find.textContaining('[%cal'), findsNothing);
      },
    );

    testWidgets(
      'when showAnnotations is disabled, board shapes from comments are withheld even after lapse',
      (tester) async {
        final importResult = importPgn(
          '1. e4 {[%cal Gf3e5][%csl Re5] Attacks the center} e5 *',
          studyTitle: 'King Pawn with Shapes Disabled',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Disable annotations via studyPreferencesProvider
        final element = tester.element(find.byType(ReviewScreen));
        final container = ProviderScope.containerOf(element);
        await container.read(studyPreferencesProvider.notifier).toggleAnnotations();
        await pumpAsync(tester);

        // Play incorrect move: d2 -> d4 instead of e2 -> e4
        await playMove(tester, 'd2', 'd4');
        await pumpAsync(tester, 100);

        // After lapse: SrsMoveArrow is present, but commentary shapes (Gf3e5, Re5) are NOT added to BoardWidget
        expect(find.byType(SrsMoveArrow), findsOneWidget);
        final board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(
          board.shapes.any((s) => s is Arrow && s.orig == Square.f3 && s.dest == Square.e5),
          isFalse,
        );
        expect(board.shapes.any((s) => s is Circle && s.orig == Square.e5), isFalse);

        // Text is still present (unless comments are disabled separately)
        expect(find.text('Attacks the center'), findsOneWidget);
      },
    );

    testWidgets('study active toggle suspends and activates study from review pool in drawer', (
      tester,
    ) async {
      final importResult = importPgn(
        '1. e4 e5 *',
        studyTitle: 'Active Study',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      // Suspending is a row action, so it lives in the actions sheet (design/docs/03-components.md
      // §6.4) rather than on the row. The row itself reports the paused state as `Paused`.
      expect(find.text('Paused'), findsNothing);
      await tester.longPress(find.text('Active Study'));
      await pumpAsync(tester);
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await pumpAsync(tester);

      expect(find.text('Paused'), findsOneWidget);

      // And it can be put back into the pool.
      await tester.longPress(find.text('Active Study'));
      await pumpAsync(tester);
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await pumpAsync(tester);

      expect(find.text('Paused'), findsNothing);
    });

    testWidgets('tapping Rehearse Moves enters cram mode when 0 items are due', (tester) async {
      final importResult = importPgn(
        '1. e4 e5 2. Nf3 Nc6 *',
        studyTitle: 'Rehearse Study',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
        // Mark all decisions as already learned (due in future)
        for (final d in importResult.decisions) {
          await repo.saveReviewState(
            ReviewState(decisionId: d.id, nextDueAt: DateTime.utc(2026, 10, 1), repetitionCount: 3),
          );
        }
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Initially 0 items due -> shows Nothing due view
      expect(find.text('Nothing due.'), findsOneWidget);

      // Tap 'Practice'
      await tester.tap(find.widgetWithText(SrsPillButton, 'Practice'));
      await pumpAsync(tester);

      // Now board is active in practice mode with Practice badge in TopBar!
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);

      // Exit practice mode via the TopBar's Practice label, which is the target (00-agent-brief.md
      // open decision 3). It used to be a separate `Exit Practice` button beside inert text.
      await tester.tap(find.text('Practice'));
      await pumpAsync(tester);

      // Returned to Nothing due view
      expect(find.text('Nothing due.'), findsOneWidget);
    });

    testWidgets('Openings section appears in drawer and filters review scope', (tester) async {
      const pgn1 = '''
[Opening "Sicilian Defense: Najdorf"]
1. e4 c5 2. Nf3 d6 *
''';
      const pgn2 = '''
[Opening "French Defense: Advance"]
1. e4 e6 2. d4 d5 *
''';
      final import1 = importPgn(pgn1, studyTitle: 'Najdorf PGN', repertoireSide: Side.black);
      final import2 = importPgn(pgn2, studyTitle: 'French PGN', repertoireSide: Side.black);

      await tester.runAsync(() async {
        await repo.saveImportResult(import1);
        await repo.saveImportResult(import2);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open Black drawer
      await tester.tap(find.byType(ColourSquare).last);
      await pumpAsync(tester);

      // Verify the Openings section exists
      expect(find.text('Openings'), findsOneWidget);
      expect(find.text('Sicilian Defense'), findsOneWidget);
      expect(find.text('French Defense'), findsOneWidget);

      // Tap 'Sicilian Defense' hub
      await tester.tap(find.text('Sicilian Defense'));
      await pumpAsync(tester);

      // Verify scope changed to 'Sicilian Defense'
      final element = tester.element(find.byType(ReviewScreen));
      final container = ProviderScope.containerOf(element);
      expect(
        container.read(reviewControllerProvider).value?.scope.openingFamily,
        'Sicilian Defense',
      );
    });

    testWidgets('study options sheet renames and deletes study from drawer', (tester) async {
      final importResult = importPgn(
        '1. e4 e5 *',
        studyTitle: 'Old Title',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      // Open study options sheet (long-press: see the note at the first occurrence above)
      await tester.longPress(find.text('Old Title'));
      await pumpAsync(tester);

      // Tap Rename
      await tester.tap(find.text('Rename'));
      await pumpAsync(tester);

      // Enter new title in dialog
      await tester.enterText(
        find.descendant(of: find.byType(SrsDialog), matching: find.byType(TextField)),
        'Renamed Repertoire',
      );
      await tester.tap(find.widgetWithText(SrsPillButton, 'Rename'));
      await pumpAsync(tester);

      // Verify study title updated in drawer
      expect(find.text('Renamed Repertoire'), findsOneWidget);

      // Open study actions sheet again to delete
      await tester.longPress(find.text('Renamed Repertoire'));
      await pumpAsync(tester);

      await tester.tap(find.text('Delete'));
      await pumpAsync(tester);

      // §12 names the item and its position count, and forbids red. The count is fixture
      // data, so what is pinned here is the format rather than the number.
      final copy = find.textContaining('positions? This cannot be undone.');
      expect(copy, findsOneWidget);
      expect(
        tester.widget<Text>(copy).data,
        matches(
          RegExp(
            r'^Delete \u201cRenamed Repertoire\u201d and its \d+ positions\? This cannot be undone\.$',
          ),
        ),
      );

      // Tap Delete in confirmation dialog
      await tester.tap(find.widgetWithText(SrsPillButton, 'Delete'));
      await pumpAsync(tester);

      // Study is deleted -> empty state
      expect(find.text('Bring your study.'), findsOneWidget);
    });

    testWidgets(
      'study options Analyze navigates even when chapter load outlasts the dismiss animation',
      (tester) async {
        final importResult = importPgn(
          '1. e4 e5 *',
          studyTitle: 'King Pawn',
          repertoireSide: Side.white,
        );
        // Dismiss transitions run 180ms; a 400ms chapter load guarantees the
        // drawer is fully unmounted before the navigation decision is made.
        final slowRepo = _SlowChaptersRepository(db);
        await tester.runAsync(() => slowRepo.saveImportResult(importResult));

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => slowRepo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: slowRepo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        // Slow chapter load delays the initial state too; settle twice.
        await pumpAsync(tester, 600);
        await pumpAsync(tester, 600);

        // Open drawer and study options sheet
        await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
        await pumpAsync(tester, 600);
        await tester.longPress(find.text('King Pawn'));
        await pumpAsync(tester, 600);

        // Tap Analyze: pops both sheets, loads chapters, then must navigate.
        await tester.tap(find.text('Analyze'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 500));
        await pumpAsync(tester, 600);
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(StudyScreen), findsOneWidget);
      },
    );

    testWidgets(
      'correct move with commentary/shapes pauses auto-advancement with Move Explanation and Continue button',
      (tester) async {
        final importResult = importPgn(
          '1. e4 {[%cal Gf3e5][%csl Re5] Attacks the center} e5 *',
          studyTitle: 'King Pawn with Shapes',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Before move: no shapes or comment
        expect(find.text('Attacks the center'), findsNothing);
        expect(find.text('From your study'), findsNothing);

        // Play correct move: e2 -> e4
        await playMove(tester, 'e2', 'e4');
        await pumpAsync(tester, 100);

        // Auto-advancement paused: shows Note and Continue button
        expect(find.text('From your study'), findsOneWidget);
        expect(find.text('Attacks the center'), findsOneWidget);
        expect(find.widgetWithText(SrsPillButton, 'Continue'), findsOneWidget);

        // Shapes are displayed on the board
        final board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(
          board.shapes.any((s) => s is Arrow && s.orig == Square.f3 && s.dest == Square.e5),
          isTrue,
        );
        expect(board.shapes.any((s) => s is Circle && s.orig == Square.e5), isTrue);

        // Tap Continue button
        await tester.tap(find.widgetWithText(SrsPillButton, 'Continue'));
        await pumpAsync(tester, 700);

        // Queue advances (session caught up)
        expect(find.text('Nothing due.'), findsOneWidget);
      },
    );

    testWidgets('tapping the board overlay while awaiting advance continues advancement', (
      tester,
    ) async {
      final importResult = importPgn(
        '1. e4 {Important center move} *',
        studyTitle: 'King Pawn Tap Test',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Play correct move: e2 -> e4
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 100);

      // Paused awaiting continue (comment note is visible)
      expect(find.text('Important center move'), findsOneWidget);

      // Tap on the chessboard
      await tester.tap(find.byType(Chessboard));
      await pumpAsync(tester, 700);

      // Successfully advanced to completion
      expect(find.text('Nothing due.'), findsOneWidget);
    });

    testWidgets(
      'quick toggle action in overflow sheet toggles annotations and updates shapes/comments in real time',
      (tester) async {
        final importResult = importPgn(
          '1. e4 {[%cal Gf3e5] Attacks the center} *',
          studyTitle: 'Quick Toggle Test',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(importResult);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Play correct move: e2 -> e4
        await playMove(tester, 'e2', 'e4');
        await pumpAsync(tester, 100);

        // Shapes and commentary are visible
        var board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(board.shapes, isNotEmpty);
        expect(find.text('Attacks the center'), findsOneWidget);

        // Toggle annotations and PGN comments via study preferences provider
        final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScreen)));
        await container.read(studyPreferencesProvider.notifier).setShowAnnotations(false);
        await container.read(studyPreferencesProvider.notifier).togglePgnComments();
        await tester.pumpAndSettle();

        // Shapes and comment text are hidden in real time!
        board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(board.shapes, isEmpty);
        expect(find.text('Attacks the center'), findsNothing);

        // Re-enable annotations and PGN comments
        await container.read(studyPreferencesProvider.notifier).setShowAnnotations(true);
        await container.read(studyPreferencesProvider.notifier).togglePgnComments();
        await tester.pumpAndSettle();

        // Shapes and comment text reappear
        board = tester.widget<BoardWidget>(find.byType(BoardWidget));
        expect(board.shapes, isNotEmpty);
        expect(find.text('Attacks the center'), findsOneWidget);
      },
    );

    testWidgets('ReviewScopeDrawer and All Caught Up view display progress metrics', (
      tester,
    ) async {
      final importResult = importPgn(
        '1. e4 e5 2. Nf3 *',
        studyTitle: 'Progress Test Study',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer: before any reviews, both positions are still in the learning bucket.
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      // The sub line is `{n} positions` (design/docs/01-identity.md); the learned state rides on
      // the memory mini-bar beside it, not in the text.
      expect(find.text('2 positions'), findsOneWidget);
      List<SrsMemoryBar> drawerBars() => tester
          .widgetList<SrsMemoryBar>(
            find.descendant(
              of: find.byType(ReviewScopeDrawer),
              matching: find.byType(SrsMemoryBar),
            ),
          )
          .toList();
      expect(drawerBars().first.retained, 0);
      expect(drawerBars().first.learning, 2);

      // Close drawer by tapping the study row
      await tester.tap(
        find.descendant(
          of: find.byType(ReviewScopeDrawer),
          matching: find.text('Progress Test Study'),
        ),
      );
      await pumpAsync(tester);

      // Play 1. e4 (first move)
      await playMove(tester, 'e2', 'e4');
      await pumpAsync(tester, 700);

      // Play 2. Nf3 (second move)
      await playMove(tester, 'g1', 'f3');
      await pumpAsync(tester, 700);

      // Nothing due view: shows memory bar and next review time
      expect(find.text('Nothing due.'), findsOneWidget);
      expect(find.textContaining('Next review in 1 day'), findsOneWidget);
      expect(find.byType(SrsMemoryBar), findsOneWidget);

      // Open drawer again: both positions have moved to retained
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      expect(find.text('2 positions'), findsOneWidget);
      expect(drawerBars().first.learning, 0);
      expect(drawerBars().first.retained, 2);
    });

    testWidgets('RepertoireImportDialog indicates when imported PGN is already up to date', (
      tester,
    ) async {
      const pgn = '1. e4 e5 2. Nf3 *';
      final importResult = importPgn(
        pgn,
        studyTitle: 'King Pawn Repertoire',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer and click Import PGN
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      await tester.tap(find.text('Import PGN'));
      await pumpAsync(tester);

      expect(find.byType(RepertoireImportDialog), findsOneWidget);

      // Switch to PGN Text / File tab
      await tester.tap(find.text('PGN Text / File'));
      await pumpAsync(tester);

      // Enter same PGN into PGN text field
      await tester.enterText(find.widgetWithText(TextField, 'PGN text'), pgn);
      await tester.tap(find.text('Import and Start Review'));
      await pumpAsync(tester, 600);

      // Dialog is dismissed and info snackbar is shown
      expect(find.byType(RepertoireImportDialog), findsNothing);
      expect(
        find.text('Study "King Pawn Repertoire" is already imported and up to date'),
        findsOneWidget,
      );
    });

    testWidgets('RepertoireImportDialog imports study from Lichess URL', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/study/m1AbCd2E.pgn') {
          return http.Response(
            '''
[Event "French Defense: Winawer Variation"]
[Site "https://lichess.org/study/m1AbCd2E"]
1. e4 e6 2. d4 d5 3. Nc3 Bb4 *
''',
            200,
            headers: {'content-type': 'application/x-chess-pgn'},
          );
        }
        return http.Response('Not Found', 404);
      });

      // First, create a study so the main review view is shown with the top bar
      final whiteStudy = importPgn(
        '1. e4 e5 *',
        studyTitle: 'White study',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(whiteStudy);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
          lichessClientProvider: lichessClientProvider.overrideWith(
            (ref) => LichessClient(mockClient, ref),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open drawer and click Import PGN
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      await tester.tap(find.text('Import PGN'));
      await pumpAsync(tester);

      // Switch to Lichess tab
      await tester.tap(find.text('Lichess Study'));
      await pumpAsync(tester);

      // Enter Lichess study URL
      await tester.enterText(
        find.widgetWithText(TextField, 'Lichess Study URL or ID'),
        'https://lichess.org/study/m1AbCd2E',
      );
      await tester.tap(find.text('Fetch & Import from Lichess'));
      await pumpAsync(tester, 600);

      // Dialog is dismissed and success snackbar is shown
      expect(find.byType(RepertoireImportDialog), findsNothing);
      expect(find.textContaining('Imported "French Defense"'), findsOneWidget);
    });

    testWidgets('SRS Diagnostics HUD is hidden by default and displayed when toggled', (
      tester,
    ) async {
      final importResult = importPgn(
        '1. e4 e5 *',
        studyTitle: 'King Pawn Repertoire',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(importResult);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Vanilla mode: calm diagnostics strip is NOT rendered
      expect(find.textContaining('expected'), findsNothing);

      // Toggle srsDiagnostics on
      final element = tester.element(find.byType(ReviewScreen));
      final container = ProviderScope.containerOf(element);
      await container.read(studyPreferencesProvider.notifier).toggleSrsDiagnostics();
      await pumpAsync(tester);

      // Diagnostics HUD is now rendered with live metrics (calm sentence case)
      expect(find.textContaining('expected'), findsOneWidget);
      expect(find.textContaining('R: 100% (New)'), findsOneWidget);
      expect(find.textContaining('D: 5.0/10'), findsOneWidget);
    });

    testWidgets('tapping SRS settings action opens SrsSettingsScreen', (tester) async {
      final app = await makeTestProviderScopeApp(tester, home: const ReviewScreen());

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      expect(find.byTooltip('Library and settings'), findsOneWidget);
      await tester.tap(find.byTooltip('Library and settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SrsSettingsScreen), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Daily limit'), findsOneWidget);
    });

    testWidgets('ReviewScopeDrawer search filters repertoires and opening hubs by query', (
      tester,
    ) async {
      final study1 = importPgn(
        '1. e4 e6 *',
        studyTitle: 'French Defense Repertoire',
        repertoireSide: Side.white,
      );
      final study2 = importPgn(
        '1. e4 c5 *',
        studyTitle: 'Sicilian Dragon Repertoire',
        repertoireSide: Side.black,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(study1);
        await repo.saveImportResult(study2);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      // Open White drawer
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      final drawer = find.byType(ReviewScopeDrawer);
      Finder inDrawer(String text) => find.descendant(of: drawer, matching: find.text(text));

      // White drawer only shows the White study:
      expect(inDrawer('French Defense Repertoire'), findsOneWidget);
      expect(inDrawer('Sicilian Dragon Repertoire'), findsNothing);

      // Type "French" into the search field
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'French');
      await tester.pumpAndSettle();

      expect(inDrawer('French Defense Repertoire'), findsOneWidget);

      // Type a query that matches nothing
      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'Nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches \u201cNonexistent\u201d.'), findsOneWidget);
      expect(find.text('French Defense Repertoire'), findsNothing);

      // Tap clear search button
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(inDrawer('French Defense Repertoire'), findsOneWidget);

      // Close drawer and open Black drawer
      Navigator.of(tester.element(find.byType(ReviewScopeDrawer))).pop();
      await pumpAsync(tester, 250);

      await tester.tap(find.byType(ColourSquare).last);
      await pumpAsync(tester);

      expect(inDrawer('Sicilian Dragon Repertoire'), findsOneWidget);
      expect(inDrawer('French Defense Repertoire'), findsNothing);
    });

    testWidgets('ReviewScopeDrawer groups collapse and expand on header tap', (tester) async {
      final study = importPgn(
        '[Opening "Sicilian Defense"]\n1. e4 c5 *',
        studyTitle: 'Sicilian Lines',
        repertoireSide: Side.black,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(study);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      await tester.tap(find.byType(ColourSquare).last);
      await pumpAsync(tester);

      final drawer = find.byType(ReviewScopeDrawer);
      Finder inDrawer(String text) => find.descendant(of: drawer, matching: find.text(text));

      expect(inDrawer('Sicilian Defense'), findsOneWidget);
      expect(inDrawer('Sicilian Lines'), findsOneWidget);

      await tester.tap(inDrawer('Studies'));
      await pumpAsync(tester);

      expect(inDrawer('Sicilian Lines'), findsNothing);
      expect(inDrawer('Sicilian Defense'), findsOneWidget);

      await tester.tap(inDrawer('Openings'));
      await pumpAsync(tester);

      expect(inDrawer('Sicilian Defense'), findsNothing);

      await tester.tap(inDrawer('Openings'));
      await pumpAsync(tester);

      expect(inDrawer('Sicilian Defense'), findsOneWidget);
    });

    testWidgets('ReviewScopeDrawer collapse survives closing and reopening', (tester) async {
      final study = importPgn(
        '1. e4 e5 *',
        studyTitle: 'King Pawn Lines',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(study);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      final drawer = find.byType(ReviewScopeDrawer);
      Finder inDrawer(String text) => find.descendant(of: drawer, matching: find.text(text));

      await tester.tap(inDrawer('Studies'));
      await pumpAsync(tester);
      expect(inDrawer('King Pawn Lines'), findsNothing);

      // Dismiss drawer and reopen; reopening must keep the collapse.
      Navigator.of(tester.element(find.byType(ReviewScopeDrawer))).pop();
      await pumpAsync(tester, 250);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      expect(find.byType(ReviewScopeDrawer), findsOneWidget);
      expect(inDrawer('King Pawn Lines'), findsNothing);
    });

    testWidgets('ReviewScopeDrawer search shows matches from collapsed groups', (tester) async {
      final study = importPgn(
        '1. e4 e5 *',
        studyTitle: 'King Pawn Lines',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(study);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      final drawer = find.byType(ReviewScopeDrawer);
      Finder inDrawer(String text) => find.descendant(of: drawer, matching: find.text(text));

      await tester.tap(inDrawer('Studies'));
      await pumpAsync(tester);
      expect(inDrawer('King Pawn Lines'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Search'), 'King Pawn');
      await tester.pumpAndSettle();

      expect(inDrawer('King Pawn Lines'), findsOneWidget);
    });

    testWidgets('collapse toggle off keeps groups expanded and headers plain', (tester) async {
      final study = importPgn(
        '1. e4 e5 *',
        studyTitle: 'King Pawn Lines',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() async {
        await repo.saveImportResult(study);
      });

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );

      await tester.pumpWidget(app);
      await pumpAsync(tester);

      final element = tester.element(find.byType(ReviewScreen));
      final container = ProviderScope.containerOf(element);
      await container.read(studyPreferencesProvider.notifier).toggleCollapsibleScopeGroups();
      await pumpAsync(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColourSquare && widget.side == Side.white,
        ),
      );
      await pumpAsync(tester);

      final drawer = find.byType(ReviewScopeDrawer);
      Finder inDrawer(String text) => find.descendant(of: drawer, matching: find.text(text));

      // With the master switch off, tapping a header does nothing.
      await tester.tap(inDrawer('Studies'));
      await pumpAsync(tester);
      expect(inDrawer('King Pawn Lines'), findsOneWidget);

      // Switching it back on restores collapsing without losing the state.
      await container.read(studyPreferencesProvider.notifier).toggleCollapsibleScopeGroups();
      await pumpAsync(tester);
      await tester.tap(inDrawer('Studies'));
      await pumpAsync(tester);
      expect(inDrawer('King Pawn Lines'), findsNothing);
    });

    testWidgets(
      'displays daily limit reached view and navigates to SrsSettingsScreen on Change daily limit',
      (tester) async {
        final study = importPgn(
          '1. e4 e5 *',
          studyTitle: 'King Pawn Repertoire',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(study);
          // Pre-record a review event for this decision today so daily count reaches 1
          final dec = study.decisions.first;
          await repo.saveReviewEvent(
            ReviewEvent(
              decisionId: dec.id,
              when: clock.now(),
              result: ReviewResult.correct,
              oldState: const ReviewState(decisionId: 'dec'),
              newState: const ReviewState(decisionId: 'dec', repetitionCount: 1),
            ),
          );
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        // Set maxDailyReviews to 1 in preferences
        final element = tester.element(find.byType(ReviewScreen));
        final container = ProviderScope.containerOf(element);
        await container.read(studyPreferencesProvider.notifier).setMaxDailyReviews(1);
        await pumpAsync(tester);

        // Daily limit reached view is now shown!
        expect(find.text('Daily limit reached.'), findsOneWidget);
        expect(find.textContaining('positions today.'), findsOneWidget);

        // Tap Change daily limit button
        expect(find.text('Change daily limit'), findsOneWidget);
        await tester.tap(find.text('Change daily limit'));
        await tester.pumpAndSettle();

        // Navigates to SrsSettingsScreen
        expect(find.byType(SrsSettingsScreen), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Daily limit'), findsOneWidget);
      },
    );

    testWidgets(
      'renders narrow layout without overflow and displays board with side column below',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final study = importPgn(
          '1. e4 e5 2. Nf3 Nc6 *',
          studyTitle: 'Narrow Test Repertoire',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(study);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) => ReviewService(repository: repo, clock: clock),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpAsync(tester);

        expect(find.byType(SrsReviewLayout), findsOneWidget);
        expect(find.byType(Chessboard), findsOneWidget);
        expect(find.text('White to play'), findsOneWidget);

        // The notation line is the headline of this screen
        // (design/docs/03-components.md: "the line is the headline"), so it is on by default.
        // It used to default off, which left the primary screen as a board above an empty
        // column; every sibling display preference already defaulted on.
        expect(find.byType(SrsNotationLine), findsOneWidget);

        // ...and it is still a setting.
        final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScreen)));
        await container.read(studyPreferencesProvider.notifier).setShowMoveHistory(false);
        await tester.pumpAndSettle();
        expect(find.byType(SrsNotationLine), findsNothing);

        expect(find.widgetWithText(SrsTextButton, 'Skip'), findsOneWidget);

        // Play 1. e4
        await playMove(tester, 'e2', 'e4');
        await pumpAsync(tester, 700);

        // Verify no exceptions or overflow occurred
        expect(tester.takeException(), isNull);
      },
    );
  });
}

/// Chapter loads slower than the 180ms sheet-dismiss transition, so any
/// navigation decision made after the load sees an unmounted drawer.
class _SlowChaptersRepository extends SqliteStudyRepository {
  _SlowChaptersRepository(super.db);

  @override
  Future<List<Chapter>> getChaptersByStudy(String studyId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return await super.getChaptersByStudy(studyId);
  }
}
