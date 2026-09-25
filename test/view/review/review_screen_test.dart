// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
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

    Future<void> pumpAsync(WidgetTester tester, [int ms = 80]) async {
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration(milliseconds: ms));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
    }

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

      expect(find.text('Bring your repertoire.'), findsOneWidget);
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

      // Board is rendered with Chessboard
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.text('All Studies'), findsOneWidget);

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
      // The design's answer help carries no parenthetical: the correct move is
      // already set large above it, and the demo's copy does not repeat it inline.
      expect(
        find.text('Play this move to continue. The position will come back soon.'),
        findsOneWidget,
      );
      expect(find.textContaining('Repertoire was'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);

      // Reguess on the board by playing the correct repertoire move d2 -> d4
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

    testWidgets('study options sheet opens AnalysisScreen via Analyze Study', (tester) async {
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
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Open study options sheet
      await tester.tap(find.byTooltip('Study options'));
      await pumpAsync(tester);

      // Tap Analyze Study
      await tester.tap(find.text('Analyze Study'));
      await pumpAsync(tester, 200);
      await tester.pumpAndSettle();

      // AnalysisScreen is now opened
      expect(find.byType(AnalysisScreen), findsOneWidget);
    });

    testWidgets('multi-chapter study opens StudyChaptersScreen and navigates to AnalysisScreen', (
      tester,
    ) async {
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
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Open study options sheet
      await tester.tap(find.byTooltip('Study options'));
      await pumpAsync(tester);

      // Tap Analyze Study
      await tester.tap(find.text('Analyze Study'));
      await pumpAsync(tester, 200);
      await tester.pumpAndSettle();

      // StudyChaptersScreen is now opened
      expect(find.byType(StudyChaptersScreen), findsOneWidget);
      expect(find.text('Chapter 1: Open Games'), findsOneWidget);
      expect(find.text('Chapter 2: French Defense'), findsOneWidget);

      // Tap Analyze icon on Chapter 1
      await tester.tap(find.byTooltip('Analyze chapter').first);
      await pumpAsync(tester, 200);
      await tester.pumpAndSettle();

      // AnalysisScreen is now opened
      expect(find.byType(AnalysisScreen), findsOneWidget);
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
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Find toggle icon in drawer
      final toggleButton = find.byTooltip('Active in review pool (tap to suspend)');
      expect(toggleButton, findsOneWidget);

      // Tap toggle to suspend study
      await tester.tap(toggleButton);
      await pumpAsync(tester);

      // Verify study toggle icon updated to suspended state
      expect(find.byTooltip('Suspended from review pool (tap to activate)'), findsOneWidget);
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

      // Exit practice mode via TopBar button
      await tester.tap(find.text('Exit Practice'));
      await pumpAsync(tester);

      // Returned to Nothing due view
      expect(find.text('Nothing due.'), findsOneWidget);
    });

    testWidgets('Opening Hubs section appears in drawer and filters review scope', (tester) async {
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

      // Open drawer
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Verify Opening Hubs section exists
      expect(find.text('Opening Hubs'), findsOneWidget);
      expect(find.text('Sicilian Defense'), findsOneWidget);
      expect(find.text('French Defense'), findsOneWidget);

      // Tap 'Sicilian Defense' hub
      await tester.tap(find.text('Sicilian Defense'));
      await pumpAsync(tester);

      // Verify AppBar now shows 'Sicilian Defense' as the active scope
      expect(find.text('Sicilian Defense'), findsOneWidget);
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
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Open study options sheet
      await tester.tap(find.byTooltip('Study options'));
      await pumpAsync(tester);

      // Tap Rename Study
      await tester.tap(find.text('Rename Study'));
      await pumpAsync(tester);

      // Enter new title in dialog
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Renamed Repertoire',
      );
      await tester.tap(find.text('Rename'));
      await pumpAsync(tester);

      // Verify study title updated in drawer
      expect(find.text('Renamed Repertoire'), findsOneWidget);

      // Open study options sheet again to delete
      await tester.tap(find.byTooltip('Study options'));
      await pumpAsync(tester);

      await tester.tap(find.text('Delete Study'));
      await pumpAsync(tester);

      // Tap Delete in confirmation dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpAsync(tester);

      // Study is deleted -> empty state
      expect(find.text('Bring your repertoire.'), findsOneWidget);
    });

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

      // Open drawer: before any reviews, 0/2 learned (0%)
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      expect(find.text('0/2 learned (0%)'), findsNWidgets(2)); // All Studies & Study tile

      // Close drawer by tapping the All Studies tile
      await tester.tap(find.widgetWithText(ListTile, 'All Studies'));
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

      // Open drawer again: shows 2/2 learned (100%)
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      expect(find.text('2/2 learned (100%)'), findsNWidgets(2));
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
      await tester.tap(find.byTooltip('Studies & Scope'));
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
        find.text('Repertoire "King Pawn Repertoire" is already imported and up to date'),
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
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      await tester.tap(find.text('Import PGN'));
      await pumpAsync(tester);

      expect(find.byType(RepertoireImportDialog), findsOneWidget);

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
        repertoireSide: Side.black,
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

      // Open drawer
      await tester.tap(find.byTooltip('Studies & Scope'));
      await pumpAsync(tester);

      // Both studies and All Studies tile are visible initially
      expect(find.text('French Defense Repertoire'), findsOneWidget);
      expect(find.text('Sicilian Dragon Repertoire'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'All Studies'), findsOneWidget);

      // Type "French" into the search field
      await tester.enterText(
        find.widgetWithText(TextField, 'Search repertoires & hubs...'),
        'French',
      );
      await tester.pumpAndSettle();

      // "French Defense Repertoire" is visible, "Sicilian" and "All Studies" are hidden
      expect(find.text('French Defense Repertoire'), findsOneWidget);
      expect(find.text('Sicilian Dragon Repertoire'), findsNothing);
      expect(find.widgetWithText(ListTile, 'All Studies'), findsNothing);

      // Type a query that matches nothing
      await tester.enterText(
        find.widgetWithText(TextField, 'Search repertoires & hubs...'),
        'Nonexistent',
      );
      await tester.pumpAndSettle();

      expect(find.text('No repertoires matching "Nonexistent"'), findsOneWidget);
      expect(find.text('French Defense Repertoire'), findsNothing);
      expect(find.text('Sicilian Dragon Repertoire'), findsNothing);

      // Tap clear search button
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      // Both studies and All Studies reappear
      expect(find.text('French Defense Repertoire'), findsOneWidget);
      expect(find.text('Sicilian Dragon Repertoire'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'All Studies'), findsOneWidget);
    });

    testWidgets(
      'displays daily limit reached view and navigates to SrsSettingsScreen on Adjust limit',
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
        expect(
          find.text('Daily review limit reached (1/1 positions reviewed today).'),
          findsOneWidget,
        );

        // Tap the Adjust limit link
        expect(find.text('Adjust limit'), findsOneWidget);
        await tester.tap(find.text('Adjust limit'));
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
        // By default, showMoveHistory is false
        expect(find.byType(SrsNotationLine), findsNothing);

        // Enabling showMoveHistory shows the notation line
        final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScreen)));
        await container.read(studyPreferencesProvider.notifier).setShowMoveHistory(true);
        await tester.pumpAndSettle();
        expect(find.byType(SrsNotationLine), findsOneWidget);

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
