import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/common/time_increment.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/engine/weights_service.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/offline_computer_game.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/offline_computer/computer_analysis.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_clock.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_controller.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_storage.dart';
import 'package:chess_srs/src/model/offline_computer/practice_analyser.dart';
import 'package:chess_srs/src/model/offline_computer/practice_comment.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/styles/lichess_colors.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:chess_srs/src/widgets/clock.dart';
import 'package:chess_srs/src/widgets/move_list.dart';
import 'package:chess_srs/src/widgets/pockets.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../binding.dart';
import '../../model/engine/fake_engine.dart';
import '../../model/engine/fake_weights_service.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

class MockOfflineComputerGameStorage extends Mock implements OfflineComputerGameStorage {}

/// When the saved games below were created.
///
/// A fixture stamped with the wall clock is a different value on every run, and the game
/// screen never asks how old a game is: the stamp is data, so it is a constant.
final kFixedGameCreatedAt = DateTime.utc(2026, 1, 1);

void main() {
  TestLichessBinding.ensureInitialized();

  setUpAll(() {
    final game = OfflineComputerGame(
      id: const StringId('test-game-id'),
      steps: [const GameStep(position: Chess.initial)].lock,
      meta: GameMeta(
        createdAt: kFixedGameCreatedAt,
        rated: false,
        variant: Variant.standard,
        speed: Speed.classical,
        perf: Perf.classical,
      ),
      initialFen: null,
      status: GameStatus.started,
      playerSide: Side.white,
      opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
      humanPlayer: const Player(onGame: true),
      enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    );
    registerFallbackValue(game);
    registerFallbackValue(SavedOfflineComputerGame(game: game));
  });

  tearDown(() {
    // The paste test mocks the clipboard; the mock is per-test, not per-file.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('Offline computer game', () {
    setUp(() {
      // Use LegalMoveEngine which returns valid moves for each position
      fakeEngine = LegalMoveEngine();
    });

    testWidgets('New game dialog is shown on startup with all options', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify new game bottom sheet is displayed

      // Verify the opponent tile is shown, with the default opponent on it
      expect(find.text('Opponent'), findsOneWidget);
      // Once on the tile, once on the engine player behind the sheet.
      expect(find.text('Stockfish level 4'), findsNWidgets(2));

      // Verify side selection (label is "Side" with value showing default "Random side")
      expect(find.text('Side'), findsOneWidget);
      expect(find.text('Random side'), findsOneWidget);

      // Verify play button
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('Can start a new game with default settings', (tester) async {
      await initOfflineComputerGame(tester);

      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.text('Play against computer'), findsOneWidget);

      expect(find.widgetWithText(SrsTextButton, 'Menu'), findsOneWidget);
      expect(find.widgetWithText(SrsTextButton, 'Takeback'), findsOneWidget);
      expect(find.widgetWithText(SrsTextButton, 'Resign'), findsOneWidget);
      expect(find.widgetWithText(SrsTextButton, 'Get a hint'), findsOneWidget);

      // Verify Stockfish player info with default level (level 4)
      expect(find.textContaining('Stockfish'), findsOneWidget);
      expect(find.textContaining('4'), findsWidgets);
    });

    testWidgets('Can play moves and move list updates', (tester) async {
      await initOfflineComputerGame(tester);

      // Initially no moves in the move list
      expect(find.byType(InlineMoveItem), findsNothing);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Move list should now show moves
      expect(find.byType(InlineMoveItem), findsWidgets);
      expect(find.text('e4'), findsOneWidget);

      // Wait for engine response
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Engine should have responded - at least 2 moves now
      expect(find.byType(InlineMoveItem), findsAtLeast(2));
    });

    testWidgets('Hints run on the analysis engine, beside the resident opponent', (tester) async {
      // The payoff of two resident engines. The opponent needs Fairy-Stockfish for its negative
      // skill levels, but the hints no longer have to be computed by it: they go to the engine the
      // user chose for analysis, and neither engine is quit to make room for the other.
      final engine = MultiPvEngine();
      fakeEngine = engine;

      await initOfflineComputerGame(tester);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // The opponent has answered, and the hints for the player's turn have been computed.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(engine.sessions.map((session) => session.spec.label).toSet(), {
        'variant',
        'light',
      }, reason: 'the opponent plays on Fairy while the hints are computed on the light Stockfish');
      expect(
        engine.quitCount,
        0,
        reason: 'neither engine is quit between the opponent move and the hints',
      );
    });

    testWidgets('The analysis keeps running after the hints unlock', (tester) async {
      // The point of the continuous analysis: a usable eval unlocks the hints promptly, and the
      // search then runs on to the target depth while the player thinks, instead of the engine
      // sitting idle exactly when the device is free.
      final engine = AnalysisTestEngine();
      fakeEngine = engine;

      await initOfflineComputerGame(tester, variant: Variant.crazyhouse);

      engine.emitDepthRange(toDepth: kPracticeUsableDepth);
      await tester.pump(kEngineEvalEmissionThrottleDelay * 2);

      final hintButton = find.widgetWithText(SrsTextButton, 'Get a hint');
      expect(
        tester.widget<SrsTextButton>(hintButton).onPressed,
        isNotNull,
        reason: 'the hints unlock at the usable depth',
      );
      expect(engine.stopCount, 0, reason: 'and the search is still running');

      engine.emitDepthRange(toDepth: kPracticeTargetDepth);
      await tester.pump(kEngineEvalEmissionThrottleDelay * 2);

      expect(engine.stopCount, 1, reason: 'the target depth is where the engine is let go idle');
    });

    testWidgets('The analysis does not survive the app going to the background', (tester) async {
      // A search that runs for as long as the player thinks must not go on running with the app
      // out of sight — which is a problem the old one-burst-per-move model never had.
      final engine = AnalysisTestEngine();
      fakeEngine = engine;

      await initOfflineComputerGame(tester, variant: Variant.crazyhouse);

      engine.emitDepthRange(toDepth: kPracticeUsableDepth - 2);
      await tester.pump(kEngineEvalEmissionThrottleDelay * 2);
      expect(engine.stopCount, 0);

      // The full sequence: the app installs [AppLifecycleListener]s, which assert on a transition
      // the platform cannot make.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(engine.stopCount, 1, reason: 'the analysis is given up when the screen goes away');

      engine.resetTracking();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(
        engine.requestedPositions,
        hasLength(1),
        reason: 'and the position the game is at is analysed again when it comes back',
      );
    });

    testWidgets('A variant game sizes its one engine once, and keeps it', (tester) async {
      // On a variant the opponent and the hints are the same Fairy-Stockfish, so they have to ask
      // it for the same options: `setoption name Hash` reallocates and clears the transposition
      // table, and two roles disagreeing about it would throw the search away several times a move.
      final engine = MultiPvEngine();
      fakeEngine = engine;

      await initOfflineComputerGame(tester, variant: Variant.crazyhouse);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // The opponent has answered, and the hints for the player's turn have been computed.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(engine.sessions.map((session) => session.spec.label).toSet(), {'variant'});
      expect(
        engine.commands.where((command) => command.startsWith('setoption name Hash')),
        hasLength(1),
      );
      expect(
        engine.commands.where((command) => command.startsWith('setoption name Threads')),
        hasLength(1),
      );
    });

    testWidgets('Can play drop moves in crazyhouse', (tester) async {
      await initOfflineComputerGame(
        tester,
        variant: Variant.crazyhouse,
        fen: 'rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3',
      );

      expect(find.byType(PocketsMenu), findsNWidgets(2));

      await playDropMove(tester, Side.white, Role.pawn, 'c4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(boardHasPiece(tester, Square.c4, Piece.whitePawn), isTrue);
    });

    testWidgets('Engine responds after player move', (tester) async {
      await initOfflineComputerGame(tester);

      // Play a move to trigger engine thinking
      await playMove(tester, 'e2', 'e4');

      // Wait for engine to respond
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // After engine finishes, thinking indicator should not be visible
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Engine should have responded - move list should have at least 2 moves
      expect(find.byType(InlineMoveItem), findsAtLeast(2));
    });

    testWidgets('Takeback button removes moves and updates UI', (tester) async {
      await initOfflineComputerGame(tester);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify e4 is in move list
      expect(find.text('e4'), findsOneWidget);

      // Count moves before takeback
      final movesBefore = tester.widgetList(find.byType(InlineMoveItem)).length;
      expect(movesBefore, greaterThanOrEqualTo(1));

      // Tap takeback button
      await tester.tap(find.text('Takeback'));
      await tester.pumpAndSettle();

      // Move count should decrease
      final movesAfter = tester.widgetList(find.byType(InlineMoveItem)).length;
      expect(movesAfter, lessThan(movesBefore));
    });

    testWidgets('Resign button shows confirmation dialog', (tester) async {
      await initOfflineComputerGame(tester);

      // Play moves to make the game resignable (need fullmoves > 1)
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Tap resign button
      await tester.tap(find.text('Resign'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog is shown
      expect(find.text('Resign'), findsWidgets);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('Resign ends game and shows result dialog', (tester) async {
      await initOfflineComputerGame(tester);

      // Play moves to make the game resignable
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Tap resign button
      await tester.tap(find.text('Resign'));
      await tester.pumpAndSettle();

      // Confirm resignation
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      // Wait for result dialog timer (500ms)
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Verify result dialog is shown
      expect(find.text('Game Over'), findsOneWidget);
      expect(find.text('White resigned'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('New game'), findsWidgets);
    });

    testWidgets('The result dialog is dismissed by tapping outside it', (tester) async {
      // The result of the game is a dialog the player can be done with, not a wall:
      // tapping outside it is the same as pressing Close.
      await initOfflineComputerGame(tester);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pump(Duration.zero);
      await tester.pump();

      // The result is not thrown at the player the instant the game ends: the board
      // they were reading is still theirs for half a second.
      expect(find.text('Game Over'), findsNothing);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Game Over'), findsOneWidget);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Game Over'), findsNothing);
    });

    testWidgets('The result dialog starts a new game', (tester) async {
      await initOfflineComputerGame(tester);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New game'));
      await tester.pumpAndSettle();

      expect(
        find.text('Play'),
        findsOneWidget,
        reason: 'the sheet to start the next game is there',
      );
    });

    testWidgets('New game option in menu opens bottom sheet', (tester) async {
      await initOfflineComputerGame(tester);

      // Tap menu button
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      // Tap new game in menu
      await tester.tap(find.text('New game'));
      await tester.pumpAndSettle();

      // Verify new game bottom sheet is shown with all options
      await tester.ensureVisible(find.text('Side'));
      expect(find.text('Side'), findsOneWidget);
      expect(find.text('Opponent'), findsOneWidget);
    });

    testWidgets('Menu button opens action sheet', (tester) async {
      await initOfflineComputerGame(tester);

      // Tap menu button
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      // Verify action sheet with options
      expect(find.text('New game'), findsWidgets);
    });

    testWidgets(
      'Settings icon in app bar is visible and opens unified settings sheet in standard mode',
      (tester) async {
        await initOfflineComputerGame(tester);

        // Verify settings icon is present in app bar
        final settingsIcon = find.byIcon(Icons.settings);
        expect(settingsIcon, findsOneWidget);

        await tester.tap(settingsIcon);
        await tester.pumpAndSettle();

        // In standard mode, only general settings (blindfold mode) are shown
        expect(find.text('Blindfold'), findsOneWidget);
        expect(find.text('PRACTICE SETTINGS'), findsNothing);
        expect(find.text('Hide best move'), findsNothing);
      },
    );

    testWidgets(
      'Settings icon opens unified settings sheet with practice settings in practice mode',
      (tester) async {
        await initPracticeModeGame(tester);
        await tester.pumpAndSettle();

        // Verify settings icon is visible
        final settingsIcon = find.byIcon(Icons.settings);
        expect(settingsIcon, findsOneWidget);

        await tester.tap(settingsIcon);
        await tester.pumpAndSettle();

        // In practice mode, practice settings appear before general settings (blindfold mode)
        expect(find.text('PRACTICE SETTINGS'), findsOneWidget);
        expect(find.text('Blindfold'), findsOneWidget);
      },
    );

    // SPEC INV-023, INV-063. Practice mode writes nothing; comment shapes never leak.
    testWidgets('The settings sheet switches write the preferences they show', (tester) async {
      // The sheet is the only place these preferences are set, so a switch that does
      // not write what it shows leaves the player with a setting that does nothing.
      await initPracticeModeGame(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OfflineComputerGameScreen)),
      );

      final hideBestMove = find.byWidgetPredicate(
        // The label is "Hide best move" in English and "Hide the best move" in
        // en-US, so the switch is matched on what it says rather than on how.
        (w) => w is SrsSwitch && w.semanticLabel.toLowerCase().contains('best move'),
      );
      expect(tester.widget<SrsSwitch>(hideBestMove).value, isFalse);
      await tester.tap(hideBestMove);
      await tester.pumpAndSettle();
      expect(tester.widget<SrsSwitch>(hideBestMove).value, isTrue);
      expect(container.read(offlineComputerGamePreferencesProvider).hideBestMove, isTrue);

      final hideEvaluation = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Hide evaluation',
      );
      expect(tester.widget<SrsSwitch>(hideEvaluation).value, isFalse);
      await tester.tap(hideEvaluation);
      await tester.pumpAndSettle();
      expect(tester.widget<SrsSwitch>(hideEvaluation).value, isTrue);
      expect(container.read(offlineComputerGamePreferencesProvider).hideEvaluation, isTrue);

      final blindfold = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel.toLowerCase().contains('blindfold'),
      );
      expect(tester.widget<SrsSwitch>(blindfold).value, isFalse);
      await tester.tap(blindfold);
      await tester.pumpAndSettle();
      expect(tester.widget<SrsSwitch>(blindfold).value, isTrue);
      expect(container.read(offlineComputerGamePreferencesProvider).blindfoldMode, isTrue);
    });

    testWidgets('Playing as black shows board from black perspective', (tester) async {
      await initOfflineComputerGame(tester, side: Side.black);

      // Wait for engine to make first move
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify board is displayed
      expect(find.byType(Chessboard), findsOneWidget);

      // The Chessboard widget should have orientation set to black
      final chessboard = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(chessboard.orientation, Side.black);

      // Engine should have made the first move - move list should show a move
      expect(find.byType(InlineMoveItem), findsWidgets);
    });

    testWidgets('Stockfish player info displays correctly', (tester) async {
      await initOfflineComputerGame(tester);

      // Verify Stockfish icon is displayed
      expect(find.byType(Image), findsWidgets);

      // Verify Stockfish name with level
      expect(find.textContaining('Stockfish'), findsOneWidget);
    });

    testWidgets('Takeback button is disabled at game start', (tester) async {
      await initOfflineComputerGame(tester);

      // Find the takeback button
      final takebackButton = find.widgetWithText(SrsTextButton, 'Takeback');
      expect(takebackButton, findsOneWidget);

      // At game start with no moves, takeback should be disabled
      final button = tester.widget<SrsTextButton>(takebackButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('Resign button is disabled at game start', (tester) async {
      await initOfflineComputerGame(tester);

      // Find the resign button
      final resignButton = find.widgetWithText(SrsTextButton, 'Resign');
      expect(resignButton, findsOneWidget);

      // At game start, resign should be disabled (need fullmoves > 1)
      final button = tester.widget<SrsTextButton>(resignButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('A new game at the same level tells the engine it is a new game', (tester) async {
      // Two games at the same level are the same opponent on the same engine, and the player has
      // the first move of this one — so nothing about the opponent's first search of it says that
      // the game it belongs to is not the one the engine has just been playing.
      final engine = LegalMoveEngine();
      fakeEngine = engine;

      await initOfflineComputerGame(tester);
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final opponentEngine = engine.sessions.firstWhere(
        (session) => session.spec.label == 'variant',
      );
      opponentEngine.commands.clear();

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New game'));
      await tester.pumpAndSettle();
      // The side picker already holds the side of the game just played.
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(
        engine.sessions,
        contains(opponentEngine),
        reason: 'the opponent plays both games on the one engine',
      );
      expect(opponentEngine.commands, contains('ucinewgame'));
    });

    testWidgets('Can dismiss new game bottom sheet', (tester) async {
      await initOfflineComputerGame(tester);

      // Open menu and tap new game
      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New game'));
      await tester.pumpAndSettle();

      // Verify bottom sheet is shown (has Play button and the opponent tile)
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Opponent'), findsOneWidget);

      // Dismiss the bottom sheet by tapping the barrier (scrim)
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // Bottom sheet should be closed, game should still be visible
      expect(find.text('Opponent'), findsNothing);
      expect(find.byType(Chessboard), findsOneWidget);
    });

    testWidgets('Can start game with a different Stockfish level', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The level lives in the opponent picker now
      await tester.tap(find.text('Opponent'));
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Drag slider to change level (drag to the right for higher level)
      await tester.drag(slider, const Offset(100, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Only the engine player behind the sheet still says level 4; the tile has moved on.
      expect(find.text('Stockfish level 4'), findsOneWidget);

      // Select white and start game
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Verify game started
      expect(find.byType(Chessboard), findsOneWidget);
    });

    testWidgets('A preferred Maia whose network was deleted falls back to the bundled one', (
      tester,
    ) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      final weights = FakeMaiaWeightsService();

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        defaultPreferences: {
          PrefCategory.offlineComputerGame.storageKey: jsonEncode(
            OfflineComputerGamePrefs.defaults
                .copyWith(opponentSpec: const MaiaOpponentSpec(MaiaRating.maia2200))
                .toJson(),
          ),
        },
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
          maiaWeightsServiceProvider: maiaWeightsServiceProvider.overrideWithValue(weights),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Maia 2200'), findsNothing);
      expect(find.text('Maia ${MaiaRating.defaultRating.rating}'), findsWidgets);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OfflineComputerGameScreen)),
      );
      expect(
        container.read(offlineComputerGamePreferencesProvider).opponentSpec,
        const MaiaOpponentSpec(MaiaRating.defaultRating),
      );
      expect(weights.downloads, isEmpty);
    });

    testWidgets('Casual switch is shown in new game dialog', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify casual switch is shown (there are now 2 switches: practice mode and casual)
      expect(find.text('Casual'), findsOneWidget);
      expect(find.text('Allow takebacks and hints'), findsOneWidget);
      expect(find.text('Practice mode'), findsOneWidget);
      expect(find.text('Get feedback on your moves'), findsOneWidget);
      expect(find.byType(SrsSwitch), findsNWidgets(2));
    });

    testWidgets('Takeback and hint buttons are disabled in non-casual mode', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Turn off casual mode (find the switch that's part of the Casual setting tile)
      final casualSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Casual',
      );
      await tester.tap(casualSwitch);
      await tester.pump();

      // Start game
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Play a move so takeback would normally be available
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Find the takeback button - should be disabled
      final takebackButton = find.widgetWithText(SrsTextButton, 'Takeback');
      expect(takebackButton, findsOneWidget);
      final takebackWidget = tester.widget<SrsTextButton>(takebackButton);
      expect(takebackWidget.onPressed, isNull);

      // Find the hint button - should be disabled
      final hintButton = find.widgetWithText(SrsTextButton, 'Get a hint');
      expect(hintButton, findsOneWidget);
      final hintWidget = tester.widget<SrsTextButton>(hintButton);
      expect(hintWidget.onPressed, isNull);
    });

    testWidgets('Loading saved game restores position', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();

      // Return a saved game with moves already played (e4, e5)
      when(() => gameStorage.fetchGame()).thenAnswer(
        (_) async => SavedOfflineComputerGame(
          game: OfflineComputerGame(
            id: const StringId('test-game-id'),
            steps: [
              const GameStep(position: Chess.initial),
              GameStep(
                position: Position.setupPosition(
                  Rule.chess,
                  Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
                ),
                sanMove: SanMove('e4', Move.parse('e2e4')!),
              ),
              GameStep(
                position: Position.setupPosition(
                  Rule.chess,
                  Setup.parseFen('rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
                ),
                sanMove: SanMove('e5', Move.parse('e7e5')!),
              ),
            ].lock,
            meta: GameMeta(
              createdAt: kFixedGameCreatedAt,
              rated: false,
              variant: Variant.standard,
              speed: Speed.classical,
              perf: Perf.classical,
            ),
            initialFen: kInitialFEN,
            status: GameStatus.started,
            playerSide: Side.white,
            opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
            humanPlayer: const Player(onGame: true),
            enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
          ),
        ),
      );
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Test Screen')),
            body: FilledButton(
              child: const Text('Go to game'),
              onPressed: () => Navigator.of(
                context,
              ).push(buildScreenRoute<void>(screen: const OfflineComputerGameScreen())),
            ),
          ),
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);

      await tester.tap(find.text('Go to game'));

      // Wait for saved game to be loaded
      await tester.pumpAndSettle();

      verify(() => gameStorage.fetchGame()).called(1);

      // Should not show new game dialog if we loaded a saved game
      expect(find.text('Game setup'), findsNothing);

      // Should load the game's current position, i.e. e4 and e5 were played
      expect(boardHasPiece(tester, Square.e2, Piece.whitePawn), isFalse);
      expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isTrue);

      expect(boardHasPiece(tester, Square.e7, Piece.blackPawn), isFalse);
      expect(boardHasPiece(tester, Square.e5, Piece.blackPawn), isTrue);

      // Move list should show the played moves
      expect(find.text('e4'), findsOneWidget);
      expect(find.text('e5'), findsOneWidget);
    });

    testWidgets('Last move is highlighted when loading a saved game', (tester) async {
      // Regression test: interactive boards read the last move from
      // InteractiveBoardParams.lastMove, not GameLayout.lastMove (readonly only).
      // The last move of a restored game must be highlighted on the board.
      final gameStorage = MockOfflineComputerGameStorage();

      // Saved game after 1.e4 e5 — it's white's turn (the player's), so the
      // engine does not move and the last move stays e7e5.
      when(() => gameStorage.fetchGame()).thenAnswer(
        (_) async => SavedOfflineComputerGame(
          game: OfflineComputerGame(
            id: const StringId('test-game-id'),
            steps: [
              const GameStep(position: Chess.initial),
              GameStep(
                position: Position.setupPosition(
                  Rule.chess,
                  Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
                ),
                sanMove: SanMove('e4', Move.parse('e2e4')!),
              ),
              GameStep(
                position: Position.setupPosition(
                  Rule.chess,
                  Setup.parseFen('rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
                ),
                sanMove: SanMove('e5', Move.parse('e7e5')!),
              ),
            ].lock,
            meta: GameMeta(
              createdAt: kFixedGameCreatedAt,
              rated: false,
              variant: Variant.standard,
              speed: Speed.classical,
              perf: Perf.classical,
            ),
            initialFen: kInitialFEN,
            status: GameStatus.started,
            playerSide: Side.white,
            opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
            humanPlayer: const Player(onGame: true),
            enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
          ),
        ),
      );
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The last move (e7e5) must be highlighted on the restored board.
      expect(getBoardLastMove(tester), Move.parse('e7e5'));
    });

    testWidgets('Game is saved when exiting', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();

      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Test Screen')),
            body: FilledButton(
              child: const Text('Go to game'),
              onPressed: () => Navigator.of(
                context,
              ).push(buildScreenRoute<void>(screen: const OfflineComputerGameScreen())),
            ),
          ),
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);

      await tester.tap(find.text('Go to game'));
      await tester.pumpAndSettle();

      // Start a new game
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Play a move so the game is not abortable
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Play another move to ensure game is resignable (fullmoves > 1)
      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Leaving an unfinished game asks nothing: it is saved on the way out, so it can be
      // resumed or analysed later. The head uses a custom chevron, not a platform
      // back button, so pageBack() cannot see it.
      await tester.tap(find.bySemanticsLabel('Back to Review'));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineComputerGameScreen), findsNothing);
      verify(() => gameStorage.save(any())).called(1);
    });
  });

  group('Hint feature', () {
    setUp(() {
      // Use MultiPvEngine which returns multiPv evaluation data
      fakeEngine = MultiPvEngine();
    });

    testWidgets('Hint button shows its label', (tester) async {
      await initOfflineComputerGame(tester);

      // The bar is text-only now: no icons, just the action words.
      expect(find.widgetWithText(SrsTextButton, 'Get a hint'), findsOneWidget);
    });

    testWidgets('Hint button is disabled while hints are loading', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start game as white
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));

      // Pump once to trigger hint computation but not complete it
      await tester.pump();

      // Check if hints are loading
      final gameState = ref.read(offlineComputerGameControllerProvider);

      // If loading hint, the button should be disabled
      if (gameState.isLoadingHint) {
        final hintButton = find.widgetWithText(SrsTextButton, 'Get a hint');
        final button = tester.widget<SrsTextButton>(hintButton);
        expect(button.onPressed, isNull);
      }

      // Let hints finish computing
      await tester.pumpAndSettle();
    });

    testWidgets('Hint button shows circle on board when pressed', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start game as white
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Wait for hints to be computed (timeout after 3 seconds)
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);

      // If hints are available, pressing hint button should show a circle
      if (gameState.hintMoves != null && gameState.hintMoves!.isNotEmpty) {
        // No hint shown initially
        expect(gameState.hintSquare, isNull);

        // Press hint button
        await tester.tap(find.text('Get a hint'));
        await tester.pump();

        // Hint square should now be set
        final updatedState = ref.read(offlineComputerGameControllerProvider);
        expect(updatedState.hintMove, equals(gameState.hintMoves!.first));
        expect(updatedState.hintSquare, isNotNull);
      }
    });

    testWidgets('Hint button cycles through hints on subsequent presses', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start game as white
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Wait for hints to be computed
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);

      if (gameState.hintMoves != null && gameState.hintMoves!.length > 1) {
        // Press hint button first time
        await tester.tap(find.text('Get a hint'));
        await tester.pump();

        final firstHintState = ref.read(offlineComputerGameControllerProvider);
        expect(firstHintState.hintMove, equals(gameState.hintMoves![0]));
        final firstHintSquare = firstHintState.hintSquare;

        // Press hint button second time
        await tester.tap(find.text('Get a hint'));
        await tester.pump();

        final secondHintState = ref.read(offlineComputerGameControllerProvider);
        expect(secondHintState.hintMove, equals(gameState.hintMoves![1]));
        final secondHintSquare = secondHintState.hintSquare;

        // Hint square should be different (different origin)
        expect(secondHintSquare, isNot(equals(firstHintSquare)));
      }
    });

    testWidgets('A deeper eval that drops a hint leaves the shown hint where it is', (
      tester,
    ) async {
      // The analysis keeps running while a hint is on screen, and every evaluation re-sorts and
      // re-filters the hint moves. What is shown is the move the player cycled to, so it neither
      // jumps to another square under them nor — as an index into the list would — points past the
      // end of a list the new eval has shortened.
      final engine = NarrowingHintEngine();
      fakeEngine = engine;

      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.hintMoves, hasLength(2));

      // Cycle to the second hint.
      await tester.tap(find.text('Get a hint'));
      await tester.pump();
      await tester.tap(find.text('Get a hint'));
      await tester.pump();

      final shownState = ref.read(offlineComputerGameControllerProvider);
      expect(shownState.hintMove, equals(gameState.hintMoves![1]));
      final shownSquare = shownState.hintSquare;
      expect(shownSquare, isNotNull);

      // A deeper eval leaves the second line far enough behind that it is no longer a hint.
      engine.emitNarrowedDepth();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final narrowedState = ref.read(offlineComputerGameControllerProvider);
      expect(narrowedState.hintMoves, hasLength(1));
      expect(narrowedState.hintMove, equals(shownState.hintMove));
      expect(narrowedState.hintSquare, equals(shownSquare));
    });

    testWidgets('Hints are cleared when a move is made', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start game as white
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Wait for hints to be computed
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);

      if (gameState.hintMoves != null && gameState.hintMoves!.isNotEmpty) {
        // Press hint button to show a hint
        await tester.tap(find.text('Get a hint'));
        await tester.pump();

        final hintState = ref.read(offlineComputerGameControllerProvider);
        expect(hintState.hintSquare, isNotNull);

        // Play a move
        await playMove(tester, 'e2', 'e4');
        await tester.pump(const Duration(milliseconds: 200));

        // Hints should be cleared
        final afterMoveState = ref.read(offlineComputerGameControllerProvider);
        expect(afterMoveState.hintMove, isNull);
      }
    });

    testWidgets('Hint button is highlighted when hint is showing', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start game as white
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Wait for hints to be computed
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);

      if (gameState.hintMoves != null && gameState.hintMoves!.isNotEmpty) {
        // The bar no longer highlights the button; the hint arrow on the board is the
        // indicator. Pressing it still shows the hint.
        await tester.tap(find.text('Get a hint'));
        await tester.pump();

        expect(
          ref.read(offlineComputerGameControllerProvider).hintSquare,
          isNotNull,
          reason: 'the hint arrow is drawn on the board',
        );
      }
    });

    testWidgets('Hint button is disabled when not player turn', (tester) async {
      // An opponent that takes its time, so that it is still thinking when the button is checked.
      // The analysis of the player's own position now unlocks the hints as soon as the search is
      // deep enough, which with an engine that answers instantly is immediately.
      fakeEngine = SlowEngine(const Duration(seconds: 2));
      await initOfflineComputerGame(tester, side: Side.black);

      // When playing as black, it's white's turn initially (engine's turn)
      await tester.pump(const Duration(milliseconds: 100));

      // Find the hint button
      final hintButton = find.widgetWithText(SrsTextButton, 'Get a hint');

      // During engine's turn, hint button should be disabled
      final button = tester.widget<SrsTextButton>(hintButton);
      expect(button.onPressed, isNull);

      // Let the opponent answer and the analysis of the player's turn give up, so that nothing is
      // left running behind the test.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(kPracticeMaxSearchTime + const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });

  group('Time control', () {
    setUp(() {
      fakeEngine = LegalMoveEngine();
    });

    testWidgets('a game is untimed unless a clock is asked for', (tester) async {
      await initOfflineComputerGame(tester);

      expect(find.byType(Clock), findsNothing);
    });

    testWidgets('both clocks are shown, and start on the first move', (tester) async {
      const time = Duration(minutes: 5);
      await initTimedOfflineComputerGame(tester, TimeIncrement(time.inSeconds, 3));

      expect(find.byType(Clock), findsNWidgets(2));
      expect(activeClock(tester), null);
      expect(findPlayerClock(tester).timeLeft, time);
      expect(findEngineClock(tester).timeLeft, time);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // The exchange hands the clock back to the player, each side having been given the increment
      // and charged for its own move.
      expect(activeClock(tester), Side.white);
      expect(findEngineClock(tester).timeLeft, greaterThan(time));
      expect(findPlayerClock(tester).timeLeft, lessThan(time));
    });

    testWidgets('a loaded timed game is resumed with its clock already running', (tester) async {
      // A saved game part-way through: the clock was running when the app was last in the
      // foreground, so coming back to it has to be running again. Otherwise the player thinks
      // against a frozen clock.
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.save(any())).thenAnswer((_) async {});
      // Nothing to resume on first build; the saved game is installed after a move is played.
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Start a timed game, play a move so a clock is running, then save it.
      await selectTimeControl(tester, 'Clock');
      await selectSide(tester, Side.white);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(Chessboard)));
      final saved = container.read(offlineComputerGameControllerProvider).game;
      when(() => gameStorage.fetchGame()).thenAnswer(
        (_) async => SavedOfflineComputerGame(
          game: saved,
          timeIncrement: const TimeIncrement(300, 3),
          whiteTimeLeft: const Duration(minutes: 4),
          blackTimeLeft: const Duration(minutes: 5),
        ),
      );

      // Load it into a fresh controller.
      final reloaded = container.read(offlineComputerGameControllerProvider.notifier);
      reloaded.loadGame(
        SavedOfflineComputerGame(
          game: saved,
          timeIncrement: const TimeIncrement(300, 3),
          whiteTimeLeft: const Duration(minutes: 4),
          blackTimeLeft: const Duration(minutes: 5),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(offlineComputerClockProvider).activeClock,
        isNotNull,
        reason: 'a game already under way comes back with its clock running',
      );
    });

    testWidgets('the game ends when the player runs out of time', (tester) async {
      const time = Duration(seconds: 1);
      await initTimedOfflineComputerGame(tester, TimeIncrement(time.inSeconds, 0));

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // The game clock runs on package:clock's stopwatch, which the widget-test
      // zone fakes: pumping past the remaining time charges the countdown to 0,
      // so no real-time wait is needed.
      await tester.pump(time + const Duration(milliseconds: 200));
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      expect(find.text('White time out'), findsOneWidget);
      expect(activeClock(tester), null);
    });

    testWidgets('practice mode is played without a clock', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectTimeControl(tester, 'Clock');
      expect(timeControlTile(tester).value, 'Clock');

      final practiceSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
      );
      await tester.ensureVisible(find.text('Practice mode'));
      await tester.tap(practiceSwitch);
      await tester.pumpAndSettle();

      // Turning practice mode on takes the clock away, and there is no way to ask for one back.
      expect(timeControlTile(tester).value, 'Unlimited');
      expect(timeControlTile(tester).enabled, false);

      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(Clock), findsNothing);
    });
  });

  group('Custom starting position', () {
    setUp(() {
      fakeEngine = LegalMoveEngine();
    });

    testWidgets('New game dialog shows mini board when initialFen is provided', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      // A position after 1.e4 e5
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(initialFen: customFen),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify new game bottom sheet is shown

      // Verify that a StaticChessboard is shown (the mini board preview)
      expect(find.byType(StaticChessboard), findsOneWidget);
    });

    testWidgets('New game dialog does not show mini board without initialFen', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify new game bottom sheet is shown (has Play button)
      expect(find.text('Play'), findsOneWidget);

      // No StaticChessboard should be shown
      expect(find.byType(StaticChessboard), findsNothing);
    });

    testWidgets('Can start game from custom position as white', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      // A position after 1.e4 e5 - it's white's turn
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(initialFen: customFen),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Select white and start game
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Verify game started with custom position
      expect(find.byType(Chessboard), findsOneWidget);

      // The position should show e4 and e5 pawns
      expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isTrue);
      expect(boardHasPiece(tester, Square.e5, Piece.blackPawn), isTrue);

      // e2 and e7 should be empty
      expect(boardHasPiece(tester, Square.e2, Piece.whitePawn), isFalse);
      expect(boardHasPiece(tester, Square.e7, Piece.blackPawn), isFalse);
    });

    testWidgets('Engine plays first when custom position turn differs from player side', (
      tester,
    ) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      // A position where it's white's turn, but player chooses black
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialFen: customFen);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Select black (but position has white to move)
      await selectSide(tester, Side.black);
      await tester.tap(find.text('Play'));

      // Pump once to start the game
      await tester.pump();

      // The engine should be thinking (since it's white's turn and player is black)
      var gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.playerSide, Side.black);

      // Wait for engine to make its move
      await tester.pumpAndSettle();

      // After engine move, there should be at least one move in the list
      gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.steps.length, greaterThan(1));
    });

    testWidgets('Player plays first when custom position turn matches player side', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      // A position where it's black's turn, and player chooses black
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialFen: customFen);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Select black (position has black to move)
      await selectSide(tester, Side.black);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // Player should be able to move (no engine move yet)
      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.playerSide, Side.black);
      expect(gameState.turn, Side.black);
      expect(gameState.isEngineThinking, isFalse);
      // Only the initial position step
      expect(gameState.game.steps.length, 1);
    });

    testWidgets('Game uses Variant.fromPosition when started with custom FEN', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialFen: customFen);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.meta.variant, Variant.fromPosition);
      expect(gameState.game.initialFen, customFen);
    });

    testWidgets('Game uses Variant.standard when started without custom FEN', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.meta.variant, Variant.standard);
      expect(gameState.game.initialFen, null);
    });

    testWidgets('A given initial variant is selected by default', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialVariant: Variant.atomic);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.meta.variant, Variant.atomic);
      expect(gameState.game.initialFen, null);
    });

    testWidgets('Side defaults to "Next to play" when initialFen is provided', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(initialFen: customFen),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify the side selection defaults to "Next to play"
      expect(find.text('Next to play'), findsOneWidget);
    });

    testWidgets('"Next to play" resolves to white when FEN has white to move', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      // White to move
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialFen: customFen);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Default is "Next to play", just tap Play
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.playerSide, Side.white);
      expect(gameState.turn, Side.white);
    });

    testWidgets('"Next to play" resolves to black when FEN has black to move', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      late WidgetRef ref;
      // Black to move
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen(initialFen: customFen);
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Default is "Next to play", just tap Play
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.playerSide, Side.black);
    });

    testWidgets('"Next to play" is not shown in side picker without initialFen', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Default should be "Random side", not "Next to play"
      expect(find.text('Random side'), findsOneWidget);
      expect(find.text('Next to play'), findsNothing);

      // Open side picker
      await tester.tap(find.text('Random side'));
      await tester.pumpAndSettle();

      // "Next to play" should not be in the picker
      expect(find.text('Next to play'), findsNothing);
    });
  });

  group('Practice comment card', () {
    setUp(() {
      fakeEngine = LegalMoveEngine();
    });

    Future<void> pumpWithComment(WidgetTester tester, PracticeComment comment) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
          offlineComputerGameControllerProvider: offlineComputerGameControllerProvider.overrideWith(
            () => _FakePracticeController(_stateWithPracticeComment(comment)),
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
    }

    PracticeComment makeComment(MoveVerdict verdict, {bool isBookMove = false}) =>
        PracticeComment(verdict: verdict, isBookMove: isBookMove);

    // --- icons ---

    testWidgets('goodMove shows check_circle icon', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('notBest shows info icon', (tester) async {
      await pumpWithComment(tester, makeComment(.notBest));
      expect(find.byIcon(Icons.info), findsOneWidget);
    });

    testWidgets('inaccuracy shows help icon', (tester) async {
      await pumpWithComment(tester, makeComment(.inaccuracy));
      expect(find.byIcon(Icons.help), findsOneWidget);
    });

    testWidgets('mistake shows error icon', (tester) async {
      await pumpWithComment(tester, makeComment(.mistake));
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('blunder shows cancel icon', (tester) async {
      await pumpWithComment(tester, makeComment(.blunder));
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('book move shows menu_book icon regardless of verdict', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove, isBookMove: true));
      expect(find.byIcon(Icons.menu_book), findsOneWidget);
    });

    // --- verdict labels ---

    testWidgets('goodMove shows "Good move" label', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove));
      expect(find.text('Good move'), findsOneWidget);
    });

    testWidgets('notBest shows "Good move, but there\'s better" label', (tester) async {
      await pumpWithComment(tester, makeComment(.notBest));
      expect(find.text("Good move, but there's better"), findsOneWidget);
    });

    testWidgets('inaccuracy shows "Inaccuracy" label', (tester) async {
      await pumpWithComment(tester, makeComment(.inaccuracy));
      expect(find.text('Inaccuracy'), findsOneWidget);
    });

    testWidgets('mistake shows "Mistake" label', (tester) async {
      await pumpWithComment(tester, makeComment(.mistake));
      expect(find.text('Mistake'), findsOneWidget);
    });

    testWidgets('blunder shows "Blunder" label', (tester) async {
      await pumpWithComment(tester, makeComment(.blunder));
      expect(find.text('Blunder'), findsOneWidget);
    });

    testWidgets('book move shows "Good move" label', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove, isBookMove: true));
      expect(find.text('Good move'), findsOneWidget);
    });

    // --- icon colors ---

    testWidgets('goodMove icon is lightGreen', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove));
      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(icon.color, Colors.lightGreen);
    });

    // --- card background colors ---

    testWidgets('goodMove card background is lightGreen with low alpha', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove));
      final card = _findCommentCardContainer(tester, Icons.check_circle);
      expect((card.decoration! as BoxDecoration).color, Colors.lightGreen.withValues(alpha: 0.1));
    });

    testWidgets('inaccuracy card background is inaccuracyColor with low alpha', (tester) async {
      await pumpWithComment(tester, makeComment(.inaccuracy));
      final card = _findCommentCardContainer(tester, Icons.help);
      expect(
        (card.decoration! as BoxDecoration).color,
        LichessColors.inaccuracy.withValues(alpha: 0.1),
      );
    });

    testWidgets('mistake card background is mistakeColor with low alpha', (tester) async {
      await pumpWithComment(tester, makeComment(.mistake));
      final card = _findCommentCardContainer(tester, Icons.error);
      expect(
        (card.decoration! as BoxDecoration).color,
        LichessColors.mistake.withValues(alpha: 0.1),
      );
    });

    testWidgets('blunder card background is blunderColor with low alpha', (tester) async {
      await pumpWithComment(tester, makeComment(.blunder));
      final card = _findCommentCardContainer(tester, Icons.cancel);
      expect(
        (card.decoration! as BoxDecoration).color,
        LichessColors.blunder.withValues(alpha: 0.1),
      );
    });

    // --- suggested moves ---

    testWidgets('bestMove is shown for non-best moves', (tester) async {
      await pumpWithComment(
        tester,
        PracticeComment(
          verdict: MoveVerdict.mistake,
          moveSuggestion: SanMove('e5', Move.parse('e7e5')!),
        ),
      );
      expect(find.textContaining('Best was'), findsOneWidget);
      expect(find.textContaining('e5'), findsOneWidget);
    });

    testWidgets('alternativeGoodMove is shown for good moves with an alternative', (tester) async {
      await pumpWithComment(
        tester,
        PracticeComment(
          verdict: MoveVerdict.goodMove,
          moveSuggestion: SanMove('d4', Move.parse('d2d4')!),
        ),
      );
      expect(find.textContaining('Another was'), findsOneWidget);
      expect(find.textContaining('d4'), findsOneWidget);
    });

    testWidgets('no suggested move shown for goodMove without alternative', (tester) async {
      await pumpWithComment(tester, makeComment(.goodMove));
      expect(find.textContaining('Best was'), findsNothing);
      expect(find.textContaining('Another was'), findsNothing);
    });

    testWidgets('hideBestMove preference hides the suggested move', (tester) async {
      await _pumpWithState(
        tester,
        _stateWithPracticeComment(
          PracticeComment(
            verdict: MoveVerdict.mistake,
            moveSuggestion: SanMove('e5', Move.parse('e7e5')!),
          ),
        ),
        prefs: OfflineComputerGamePrefs.defaults.copyWith(hideBestMove: true),
      );
      expect(find.textContaining('Best was'), findsNothing);
    });

    // --- evalAfter ---

    testWidgets('evalAfter is displayed in the card', (tester) async {
      await pumpWithComment(
        tester,
        const PracticeComment(verdict: MoveVerdict.mistake, evalAfter: '+0.3'),
      );
      expect(find.text('+0.3'), findsOneWidget);
    });

    testWidgets('hideEvaluation preference hides evalAfter', (tester) async {
      await _pumpWithState(
        tester,
        _stateWithPracticeComment(
          const PracticeComment(verdict: MoveVerdict.mistake, evalAfter: '+0.3'),
        ),
        prefs: OfflineComputerGamePrefs.defaults.copyWith(hideEvaluation: true),
      );
      expect(find.text('+0.3'), findsNothing);
    });

    // --- game state display ---

    testWidgets('finished game shows "Game Over" instead of a verdict icon', (tester) async {
      await _pumpWithState(tester, _stateGameFinished());
      expect(find.text('Game Over'), findsOneWidget);
      // No verdict icons when game is over
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
      expect(find.byIcon(Icons.help), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets("player's turn shows no verdict icon", (tester) async {
      await _pumpWithState(tester, _statePlayerTurn());
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.info), findsNothing);
      expect(find.byIcon(Icons.help), findsNothing);
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets("player's turn with cached eval shows the eval string", (tester) async {
      await _pumpWithState(
        tester,
        _statePlayerTurn(
          analysis: ComputerAnalysis(
            eval: CloudEval(
              position: Chess.initial,
              depth: 20,
              nodes: 1000000,
              pvs: [
                PvData(moves: ['e2e4'].lock, cp: 50),
              ].lock,
            ),
          ),
        ),
      );
      // +50cp = +0.5 pawns
      expect(find.text('+0.5'), findsOneWidget);
    });

    testWidgets('isEvaluatingMove with no comment renders the card at half opacity', (
      tester,
    ) async {
      await _pumpWithState(tester, _stateEvaluatingMove());
      final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(animatedOpacity.opacity, 0.5);
    });

    // SPEC INV-061. Feedback stays readable in both themes.
    testWidgets('a card with nothing to say is not dimmed', (tester) async {
      // The dimming marks a verdict that is being replaced. With no evaluation in
      // flight there is nothing to replace, and the card is simply the feedback.
      await _pumpWithState(tester, _statePlayerTurn());
      final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(animatedOpacity.opacity, 1.0);
    });

    // SPEC INV-060. Every verdict is announced to screen readers.
    testWidgets("the card says it is the player's turn", (tester) async {
      // The player is told when the board is theirs.
      await _pumpWithState(
        tester,
        _stateWithPracticeComment(const PracticeComment(verdict: MoveVerdict.mistake)),
      );
      expect(find.text('Your turn'), findsOneWidget);
    });

    // SPEC INV-060. Every verdict is announced to screen readers.
    testWidgets("the card does not claim it is the player's turn when it is not", (tester) async {
      // The opponent's turn is not announced as the player's.
      await _pumpWithState(tester, _stateOpponentToMove());
      expect(find.text('Your turn'), findsNothing);
    });

    // SPEC INV-060. Every verdict is announced to screen readers.
    testWidgets('the suggested move is highlighted once it is on the board', (tester) async {
      // The move the card offers and the arrow on the board are the same move, and
      // the card says so by colouring it.
      final move = Move.parse('e7e5')! as NormalMove;

      await _pumpWithState(
        tester,
        _stateWithPracticeComment(
          PracticeComment(verdict: MoveVerdict.mistake, moveSuggestion: SanMove('e5', move)),
        ).copyWith(showingSuggestedMove: move),
      );

      final text = tester.widget<Text>(find.textContaining('e5'));
      final card = text.textSpan! as TextSpan;
      final moveSpan = card.children!.whereType<TextSpan>().firstWhere((span) => span.text == 'e5');
      expect(
        moveSpan.style?.color,
        LichessColors.mistake,
        reason: 'the move that is on the board is the one the card highlights',
      );
    });

    // SPEC INV-060. Every verdict is announced to screen readers.
    testWidgets('the last verdict stays on the card while the next move is judged', (tester) async {
      final controller = _MutablePracticeController(
        _stateWithPracticeComment(
          const PracticeComment(verdict: MoveVerdict.mistake, evalAfter: '+0.3'),
        ),
      );

      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
          offlineComputerGameControllerProvider: offlineComputerGameControllerProvider.overrideWith(
            () => controller,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Mistake'), findsOneWidget);

      // The next move is being judged: the verdict of the last one is still on the
      // card, dimmed rather than gone.
      controller.newState = _stateEvaluatingMove();
      await tester.pumpAndSettle();

      expect(find.text('Mistake'), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0.5);
    });
  });

  group('Practice mode', () {
    testWidgets('switch is shown in new game dialog', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify practice mode switch is shown
      expect(find.text('Practice mode'), findsOneWidget);
      expect(find.text('Get feedback on your moves'), findsOneWidget);
    });

    testWidgets('title is shown when practice mode is enabled', (tester) async {
      fakeEngine = PracticeModeEngine();
      await initPracticeModeGame(tester);

      // Verify the title shows "Practice with computer"
      expect(find.text('Practice with computer'), findsOneWidget);
    });

    testWidgets('game is started with practiceMode flag set', (tester) async {
      fakeEngine = PracticeModeEngine();

      late WidgetRef ref;
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enable practice mode
      final practiceSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
      );
      await tester.tap(practiceSwitch);
      await tester.pump();

      // Start game
      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify the game state has practice mode enabled
      final gameState = ref.read(offlineComputerGameControllerProvider);
      expect(gameState.game.practiceMode, isTrue);
    });
    testWidgets('a move outside the analysed lines is judged on its own analysis', (tester) async {
      // The slow path. The analysis running while the player thinks holds two lines, and e4 is not
      // one of the two the fake engine offers — so the position the move led to has no eval yet and
      // has to be analysed on its own before there is anything to judge the move by.
      fakeEngine = PracticeModeEngine(initialEvalCp: 50, evalShiftCp: -60);

      late WidgetRef ref;
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final practiceSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
      );
      await tester.tap(practiceSwitch);
      await tester.pump();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final state = ref.read(offlineComputerGameControllerProvider);
      expect(state.isEvaluatingMove, isFalse, reason: 'the verdict is in, one way or another');

      final comment = state.game.steps
          .map((step) => step.computerAnalysis?.practiceComment)
          .nonNulls
          .singleOrNull;
      expect(comment, isNotNull, reason: 'the move was judged');

      // The engine only drops its eval by [evalShiftCp] on a search *after* the move, so a verdict
      // that sees the drop is proof the position the move led to was analysed on its own rather
      // than read off the lines the pre-move analysis already held.
      expect(comment!.verdict, isNot(MoveVerdict.goodMove));
    });
  });
  group('New game sheet', () {
    setUp(() {
      fakeEngine = LegalMoveEngine();
    });

    /// The sheet, on a screen that has nothing saved to restore.
    Future<Widget> openSheet(
      WidgetTester tester, {
      String? initialFen,
      OfflineComputerGamePrefs? prefs,
    }) {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      return makeTestProviderScopeApp(
        tester,
        home: OfflineComputerGameScreen(initialFen: initialFen),
        defaultPreferences: prefs == null
            ? null
            : {PrefCategory.offlineComputerGame.storageKey: jsonEncode(prefs.toJson())},
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
    }

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('a saved game with no moves does not replace the new game dialog', (tester) async {
      // A game that was started and abandoned before the first move is not a game to
      // resume: what the player gets is the sheet to start a real one.
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer(
        (_) async => SavedOfflineComputerGame(
          game: OfflineComputerGame(
            id: const StringId('test-game-id'),
            steps: [const GameStep(position: Chess.initial)].lock,
            meta: GameMeta(
              createdAt: kFixedGameCreatedAt,
              rated: false,
              variant: Variant.standard,
              speed: Speed.classical,
              perf: Perf.classical,
            ),
            initialFen: null,
            status: GameStatus.started,
            playerSide: Side.white,
            opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
            humanPlayer: const Player(onGame: true),
            enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
          ),
        ),
      );

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('a preferred from-position variant falls back to standard without a FEN', (
      tester,
    ) async {
      // The from-position variant plays the position the player pastes. With no
      // position to paste there is nothing to play, so the sheet starts on standard.
      final app = await openSheet(
        tester,
        prefs: OfflineComputerGamePrefs.defaults.copyWith(variant: Variant.fromPosition),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(settingsRowValue(tester, 'Variant'), 'Standard');
      expect(find.byType(SrsTextInput), findsNothing);
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('the FEN input appears only for the from-position variant', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Standard chess has no position to paste.
      expect(find.byType(SrsTextInput), findsNothing);
      expect(find.text('Paste from clipboard'), findsNothing);

      await selectVariant(tester, 'From Position');

      expect(find.byType(SrsTextInput), findsOneWidget);
      expect(find.text('Paste from clipboard'), findsOneWidget);
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('the game cannot start from the from-position variant without a position', (
      tester,
    ) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectVariant(tester, 'From Position');

      final play = tester.widget<SrsPillButton>(find.widgetWithText(SrsPillButton, 'Play'));
      expect(play.onPressed, isNull, reason: 'there is no position to play from yet');
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('the game starts once a position is pasted in the from-position variant', (
      tester,
    ) async {
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectVariant(tester, 'From Position');

      // Tapping the field pastes the clipboard into it, which is the only way a
      // position gets in.
      mockClipboard(customFen);
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(find.text(customFen), findsOneWidget, reason: 'the position is in the field');
      expect(
        tester.widget<SrsTextInput>(find.byType(SrsTextInput)).readOnly,
        isTrue,
        reason: 'the position is pasted, not typed',
      );

      final play = tester.widget<SrsPillButton>(find.widgetWithText(SrsPillButton, 'Play'));
      expect(play.onPressed, isNotNull, reason: 'a position is there to play from');

      await selectSide(tester, Side.white);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(Chessboard)));
      expect(container.read(offlineComputerGameControllerProvider).game.initialFen, customFen);
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('the side picker offers "Next to play" for a custom position', (tester) async {
      final app = await openSheet(
        tester,
        initialFen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Next to play'), findsOneWidget);

      await tester.ensureVisible(find.text('Side'));
      await tester.tap(find.text('Side'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SrsDialog), matching: find.text('Next to play')),
        findsOneWidget,
        reason: 'the side to move is one of the choices when a position is given',
      );
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('the mini board says which side plays in the custom position', (tester) async {
      // Black to move.
      final app = await openSheet(
        tester,
        initialFen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Black to play'), findsOneWidget);
      expect(find.text('White to play'), findsNothing);
      expect(
        tester.widget<StaticChessboard>(find.byType(StaticChessboard)).settings.enableCoordinates,
        isFalse,
        reason: 'the preview is a picture of the position, not a board to play on',
      );
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('a custom position keeps the from-position variant in the sheet', (tester) async {
      // A position means the game is played from it, and the sheet says so: the
      // variant row is not quietly standard while the game is not.
      final app = await openSheet(
        tester,
        initialFen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
        prefs: OfflineComputerGamePrefs.defaults.copyWith(variant: Variant.fromPosition),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(settingsRowValue(tester, 'Variant'), 'From Position');

      final play = tester.widget<SrsPillButton>(find.widgetWithText(SrsPillButton, 'Play'));
      expect(play.onPressed, isNotNull, reason: 'a position is there to play from');
    });

    // SPEC INV-012. Custom starting positions are honored and normalized.
    testWidgets('switching away from the from-position variant drops the pasted position', (
      tester,
    ) async {
      // The position belongs to the from-position variant. A game in another variant
      // is played from that variant's own start, not from a position the sheet no
      // longer shows.
      const customFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectVariant(tester, 'From Position');

      mockClipboard(customFen);
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text(customFen), findsOneWidget);

      await selectVariant(tester, 'Atomic');

      await selectSide(tester, Side.white);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(Chessboard)));
      final game = container.read(offlineComputerGameControllerProvider).game;
      expect(game.meta.variant, Variant.atomic);
      expect(game.initialFen, isNull);
    });

    // SPEC INV-023. Practice mode writes nothing.
    testWidgets('a practice-mode game is a casual game', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // A game that is not casual has no takebacks and no hints.
      final casualSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Casual',
      );
      await tester.tap(casualSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<SrsSwitch>(casualSwitch).value, isFalse);

      final practiceSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
      );
      await tester.ensureVisible(find.text('Practice mode'));
      await tester.tap(practiceSwitch);
      await tester.pumpAndSettle();

      expect(
        tester.widget<SrsSwitch>(casualSwitch).value,
        isTrue,
        reason: 'a practice game is played casually, so the casual switch reads on',
      );

      await selectSide(tester, Side.white);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(Chessboard)));
      expect(
        container.read(offlineComputerGameControllerProvider).game.casual,
        isTrue,
        reason: 'and the game it starts is a casual one',
      );
    });

    // SPEC INV-023. Practice mode writes nothing.
    testWidgets('crazyhouse turns practice mode off, other variants keep it', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final practiceSwitch = find.byWidgetPredicate(
        (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
      );
      await tester.ensureVisible(find.text('Practice mode'));
      await tester.tap(practiceSwitch);
      await tester.pumpAndSettle();
      expect(tester.widget<SrsSwitch>(practiceSwitch).value, isTrue);

      // A variant that is not crazyhouse leaves practice mode alone.
      await selectVariant(tester, 'Atomic');
      expect(tester.widget<SrsSwitch>(practiceSwitch).value, isTrue);

      // Crazyhouse cannot be practised.
      await selectVariant(tester, 'Crazyhouse');
      expect(tester.widget<SrsSwitch>(practiceSwitch).value, isFalse);
    });

    // SPEC INV-041. Scheduling and review paths take time only through Clock.
    testWidgets('the clock sliders are shown only for a clock time control', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // An unlimited game has no clock to set.
      expect(find.textContaining('Minutes per side'), findsNothing);
      expect(find.textContaining('Increment in seconds'), findsNothing);

      await selectTimeControl(tester, 'Clock');

      expect(find.textContaining('Minutes per side'), findsOneWidget);
      expect(find.textContaining('Increment in seconds'), findsOneWidget);
    });

    // SPEC INV-041. Scheduling and review paths take time only through Clock.
    testWidgets('the clock asked for in the sheet is the clock the game has', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectTimeControl(tester, 'Clock');
      await selectSide(tester, Side.white);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.byType(Clock), findsNWidgets(2));
    });

    // SPEC INV-041. Scheduling and review paths take time only through Clock.
    testWidgets('the clock warns before a minute game is up', (tester) async {
      // The clock turns red when the time left is a fraction of what it was: an
      // eighth of it, and never less than ten seconds.
      await initTimedOfflineComputerGame(tester, const TimeIncrement(60, 0));

      expect(findPlayerClock(tester).emergencyThreshold, const Duration(seconds: 10));
    });

    // SPEC INV-041. Scheduling and review paths take time only through Clock.
    testWidgets('the clock warns no later than a minute before a long game is up', (tester) async {
      await initTimedOfflineComputerGame(tester, const TimeIncrement(600, 3));

      expect(findPlayerClock(tester).emergencyThreshold, const Duration(seconds: 60));
    });

    // SPEC INV-062. Interactive targets stay tappable.
    testWidgets('the Play button fills the width of the sheet', (tester) async {
      final app = await openSheet(tester);
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final sheet = tester.getRect(find.byKey(SrsSheetSurface.surfaceKey));
      // The pill itself, not the pressable around it: the pressable fills the sheet
      // either way, and the pill is what the player sees.
      final pill = find
          .descendant(
            of: find.widgetWithText(SrsPillButton, 'Play'),
            matching: find.byType(Container),
          )
          .first;

      expect(
        tester.getRect(pill).width,
        greaterThan(sheet.width * 0.8),
        reason: 'the sheet has one action, and it fills the sheet',
      );
    });
  });
  group('Board feedback', () {
    setUp(() {
      fakeEngine = MultiPvEngine();
    });

    // SPEC INV-011. Malformed input is quarantined, never half-applied.
    testWidgets('the board is not interactive while the opponent is to move', (tester) async {
      // The engine's reply waits for the piece animation. Until it starts, the board
      // must not offer the player a second move: a move made out of turn would be
      // applied to a game that is not the player's to move in.
      //
      // The piece animation is what makes the window observable, so this one test asks
      // for it; the rest of the suite turns it off to keep the board simple.
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        defaultPreferences: {
          PrefCategory.board.storageKey: jsonEncode(
            BoardPrefs.defaults.copyWith(pieceAnimation: true).toJson(),
          ),
        },
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await playMove(tester, 'e2', 'e4');

      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.interactive, isFalse);

      // Let the engine's reply run out, so nothing is left pending behind the test.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    });

    // SPEC INV-011. Malformed input is quarantined, never half-applied.
    testWidgets('the board is not interactive once the game is over', (tester) async {
      // A game that has ended is not one the player keeps moving in.
      await initOfflineComputerGame(tester);

      await playMove(tester, 'e2', 'e4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await playMove(tester, 'd2', 'd4');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      expect(board.interactive, isFalse);

      // Let the result dialog's timer run out, so nothing is left pending.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    // SPEC INV-063. Comment shapes never leak during recall.
    testWidgets('the hint is drawn on the board as a circle', (tester) async {
      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
      when(() => gameStorage.save(any())).thenAnswer((_) async {});

      late WidgetRef ref;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const OfflineComputerGameScreen();
          },
        ),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await selectSide(tester, Side.white);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // The hints are computed while the player thinks.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      final state = ref.read(offlineComputerGameControllerProvider);
      expect(state.hintMoves, isNotNull);
      expect(state.hintMoves, isNotEmpty);

      await tester.tap(find.text('Get a hint'));
      await tester.pump();

      final shown = ref.read(offlineComputerGameControllerProvider);
      expect(shown.hintSquare, isNotNull);

      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      final circles = board.shapes.whereType<Circle>().toList();
      expect(circles, hasLength(1), reason: 'the hint is drawn on the square it starts from');
      expect(circles.single.orig, shown.hintSquare);
    });

    // SPEC INV-063. Comment shapes never leak during recall.
    testWidgets('the suggested move is drawn on the board as an arrow', (tester) async {
      final move = Move.parse('e7e5')! as NormalMove;

      await _pumpWithState(
        tester,
        _stateWithPracticeComment(
          PracticeComment(verdict: MoveVerdict.mistake, moveSuggestion: SanMove('e5', move)),
        ).copyWith(showingSuggestedMove: move),
      );

      final board = tester.widget<Chessboard>(find.byType(Chessboard));
      final arrows = board.shapes.whereType<Arrow>().toList();
      expect(arrows, hasLength(1));
      expect(arrows.single.orig, move.from);
      expect(arrows.single.dest, move.to);
    });

    // SPEC INV-020. Correctness means matching the repertoire.
    testWidgets('a threefold repetition is offered as a draw, and only once', (tester) async {
      // The player is asked whether to claim the draw. Having said no, they are not
      // asked again the next time the screen hears about the repetition.
      final controller = _MutablePracticeController(_stateWithRepetition(false, 'game-1'));

      final gameStorage = MockOfflineComputerGameStorage();
      when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OfflineComputerGameScreen(),
        overrides: {
          offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
            (_) => gameStorage,
          ),
          offlineComputerGameControllerProvider: offlineComputerGameControllerProvider.overrideWith(
            () => controller,
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      controller.newState = _stateWithRepetition(true, 'game-2');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Threefold repetition'), findsOneWidget);
      expect(find.text('Claim a draw'), findsOneWidget);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.text('Threefold repetition'), findsNothing);

      // The screen hears about the repetition again, and the player is left alone.
      controller.newState = _stateWithRepetition(true, 'game-3');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Threefold repetition'), findsNothing);
    });
  });
}

/// A fake controller that returns a preset state, used to inject specific practice comments.
class _FakePracticeController extends OfflineComputerGameController {
  _FakePracticeController(this._initialState);
  final OfflineComputerGameState _initialState;

  @override
  OfflineComputerGameState build() => _initialState;
}

/// A fake controller whose state can be replaced, so that a rebuild of the card is observable.
class _MutablePracticeController extends OfflineComputerGameController {
  _MutablePracticeController(this._initialState);
  final OfflineComputerGameState _initialState;

  /// The state the screen is given, and the way to give it a new one.
  OfflineComputerGameState get newState => state;
  set newState(OfflineComputerGameState value) => state = value;

  @override
  OfflineComputerGameState build() => _initialState;
}

/// A fake preferences notifier that returns a preset [OfflineComputerGamePrefs].
class _FakeGamePreferences extends OfflineComputerGamePreferences {
  _FakeGamePreferences(this._prefs);
  final OfflineComputerGamePrefs _prefs;

  @override
  OfflineComputerGamePrefs build() => _prefs;
}

/// Pumps [OfflineComputerGameScreen] with a specific [state] and optional [prefs] override.
Future<void> _pumpWithState(
  WidgetTester tester,
  OfflineComputerGameState state, {
  OfflineComputerGamePrefs? prefs,
}) async {
  final gameStorage = MockOfflineComputerGameStorage();
  when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

  final app = await makeTestProviderScopeApp(
    tester,
    home: const OfflineComputerGameScreen(),
    overrides: {
      offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
        (_) => gameStorage,
      ),
      offlineComputerGameControllerProvider: offlineComputerGameControllerProvider.overrideWith(
        () => _FakePracticeController(state),
      ),
      if (prefs != null)
        offlineComputerGamePreferencesProvider: offlineComputerGamePreferencesProvider.overrideWith(
          () => _FakeGamePreferences(prefs),
        ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Finds the decorated [Container] that forms the comment card body,
/// anchored by [icon] to disambiguate from other containers in the tree.
Container _findCommentCardContainer(WidgetTester tester, IconData icon) {
  final ancestors = tester
      .widgetList<Container>(find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)))
      .toList();
  return ancestors.firstWhere(
    (c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).borderRadius != null,
  );
}

/// Builds a game state with the given [comment] on the last step.
///
/// Player side is black so the engine (white) has just moved, meaning the
/// practice comment card is visible (it's not the player's turn).
OfflineComputerGameState _stateWithPracticeComment(PracticeComment comment) {
  final afterE4 = Position.setupPosition(
    Rule.chess,
    Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
  );
  final game = OfflineComputerGame(
    id: const StringId('test-game-with-comment'),
    steps: [
      const GameStep(position: Chess.initial),
      GameStep(
        position: afterE4,
        sanMove: SanMove('e4', Move.parse('e2e4')!),
        computerAnalysis: ComputerAnalysis(practiceComment: comment),
      ),
    ].lock,
    meta: GameMeta(
      createdAt: DateTime.now(),
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.started,
    playerSide: Side.black,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    practiceMode: true,
    casual: true,
  );
  return OfflineComputerGameState(game: game, stepCursor: 1);
}

/// Builds a finished game state (checkmate) with practice mode on.
///
/// Used to test that the comment card shows "Game Over" when the game is finished.
OfflineComputerGameState _stateGameFinished() {
  final afterE4 = Position.setupPosition(
    Rule.chess,
    Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
  );
  final game = OfflineComputerGame(
    id: const StringId('test-game-finished'),
    steps: [
      const GameStep(position: Chess.initial),
      GameStep(position: afterE4, sanMove: SanMove('e4', Move.parse('e2e4')!)),
    ].lock,
    meta: GameMeta(
      createdAt: DateTime.now(),
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.mate,
    winner: Side.white,
    playerSide: Side.black,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    practiceMode: true,
    casual: true,
  );
  return OfflineComputerGameState(game: game, stepCursor: 1);
}

/// Builds a game state where it is the player's (white's) turn.
///
/// Practice mode is on. Optionally populates the current step with [analysis]
/// (e.g., a cached evaluation) to test the eval display in the comment card.
OfflineComputerGameState _statePlayerTurn({ComputerAnalysis? analysis}) {
  final game = OfflineComputerGame(
    id: const StringId('test-player-turn'),
    steps: [GameStep(position: Chess.initial, computerAnalysis: analysis)].lock,
    meta: GameMeta(
      createdAt: DateTime.now(),
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.started,
    playerSide: Side.white,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    practiceMode: true,
    casual: true,
  );
  return OfflineComputerGameState(game: game, stepCursor: 0);
}

/// Builds a game state whose threefold repetition flag is [isThreefoldRepetition].
///
/// The game id carries [id], so that two states with the same flag are still two
/// different states and the screen hears about the change.
OfflineComputerGameState _stateWithRepetition(bool isThreefoldRepetition, String id) {
  final game = OfflineComputerGame(
    id: StringId(id),
    steps: [const GameStep(position: Chess.initial)].lock,
    meta: GameMeta(
      createdAt: kFixedGameCreatedAt,
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.started,
    playerSide: Side.white,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    isThreefoldRepetition: isThreefoldRepetition,
  );
  return OfflineComputerGameState(game: game, stepCursor: 0);
}

/// Builds a state where it is the opponent's turn, with the player on white.
///
/// Practice mode is on, so the card is on screen and the status line above it has
/// something to say — or not to say.
OfflineComputerGameState _stateOpponentToMove() {
  final afterE4 = Position.setupPosition(
    Rule.chess,
    Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
  );
  final game = OfflineComputerGame(
    id: const StringId('test-opponent-to-move'),
    steps: [
      const GameStep(position: Chess.initial),
      GameStep(position: afterE4, sanMove: SanMove('e4', Move.parse('e2e4')!)),
    ].lock,
    meta: GameMeta(
      createdAt: kFixedGameCreatedAt,
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.started,
    playerSide: Side.white,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    practiceMode: true,
    casual: true,
  );
  return OfflineComputerGameState(game: game, stepCursor: 1);
}

/// Builds a state where the player has just moved and evaluation is in progress.
///
/// [isEvaluatingMove] is true and no practice comment is set yet, causing
/// the comment card to render at half opacity.
OfflineComputerGameState _stateEvaluatingMove() {
  final afterE4 = Position.setupPosition(
    Rule.chess,
    Setup.parseFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1'),
  );
  final afterE4E5 = Position.setupPosition(
    Rule.chess,
    Setup.parseFen('rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2'),
  );
  final game = OfflineComputerGame(
    id: const StringId('test-evaluating-move'),
    steps: [
      const GameStep(position: Chess.initial),
      GameStep(position: afterE4, sanMove: SanMove('e4', Move.parse('e2e4')!)),
      // Player (black) moved e5 but no comment yet — evaluation is in flight.
      GameStep(position: afterE4E5, sanMove: SanMove('e5', Move.parse('e7e5')!)),
    ].lock,
    meta: GameMeta(
      createdAt: DateTime.now(),
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: kInitialFEN,
    status: GameStatus.started,
    playerSide: Side.black,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
    humanPlayer: const Player(onGame: true),
    enginePlayer: enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)),
    practiceMode: true,
    casual: true,
  );
  return OfflineComputerGameState(game: game, stepCursor: 2, isEvaluatingMove: true);
}

/// Helper to initialize a practice mode game.
Future<Rect> initPracticeModeGame(WidgetTester tester, {Side side = Side.white}) async {
  final gameStorage = MockOfflineComputerGameStorage();
  when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);

  final app = await makeTestProviderScopeApp(
    tester,
    home: const OfflineComputerGameScreen(),
    overrides: {
      offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
        (_) => gameStorage,
      ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  // Enable practice mode
  final practiceSwitch = find.byWidgetPredicate(
    (w) => w is SrsSwitch && w.semanticLabel == 'Practice mode',
  );
  await tester.tap(practiceSwitch);
  await tester.pump();

  // Select the side
  await selectSide(tester, side);

  // Tap Play to start game
  await tester.tap(find.text('Play'));
  // Use explicit pumps instead of pumpAndSettle to avoid timeout
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));

  return tester.getRect(find.byType(Chessboard));
}

/// The "Time control" row of the new game bottom sheet.
SrsSettingsRow timeControlTile(WidgetTester tester) => tester.widget<SrsSettingsRow>(
  find.ancestor(of: find.text('Time control'), matching: find.byType(SrsSettingsRow)),
);

/// Picks [choice] ('Clock' or 'Unlimited') in the new game bottom sheet's time control picker.
Future<void> selectTimeControl(WidgetTester tester, String choice) async {
  await tester.ensureVisible(find.text('Time control'));
  await tester.tap(find.text('Time control'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

/// Picks [label] (a variant name) in the new game bottom sheet's variant picker.
Future<void> selectVariant(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text('Variant'));
  await tester.tap(find.text('Variant'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The value shown on the settings row labelled [label] in the new game bottom sheet.
String? settingsRowValue(WidgetTester tester, String label) => tester
    .widget<SrsSettingsRow>(
      find.ancestor(of: find.text(label), matching: find.byType(SrsSettingsRow)).first,
    )
    .value;

/// Initializes an offline computer game played with [timeIncrement], with the player as white.
Future<Rect> initTimedOfflineComputerGame(WidgetTester tester, TimeIncrement timeIncrement) async {
  final gameStorage = MockOfflineComputerGameStorage();
  when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
  when(() => gameStorage.save(any())).thenAnswer((_) async {});

  final app = await makeTestProviderScopeApp(
    tester,
    home: const OfflineComputerGameScreen(),
    overrides: {
      offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
        (_) => gameStorage,
      ),
    },
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();

  await selectTimeControl(tester, 'Clock');
  await selectSide(tester, Side.white);

  await tester.ensureVisible(find.text('Play'));
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();

  // The sliders only offer preset times, so the exact one under test is set on the clock itself.
  final container = ProviderScope.containerOf(tester.element(find.byType(Chessboard)));
  container.read(offlineComputerClockProvider.notifier).setupClock(timeIncrement);
  await tester.pumpAndSettle();

  return tester.getRect(find.byType(Chessboard));
}

/// Which side's clock is currently running, if any.
Side? activeClock(WidgetTester tester) {
  final playerClock = findPlayerClock(tester);
  final engineClock = findEngineClock(tester);

  if (playerClock.active) {
    expect(engineClock.active, false);
    return Side.white;
  }

  if (engineClock.active) {
    expect(playerClock.active, false);
    return Side.black;
  }

  return null;
}

Clock findPlayerClock(WidgetTester tester) =>
    tester.widget<Clock>(find.byKey(const ValueKey('playerClock')));

Clock findEngineClock(WidgetTester tester) =>
    tester.widget<Clock>(find.byKey(const ValueKey('engineClock')));

/// Helper to select a side in the new game bottom sheet using the picker.
Future<void> selectSide(WidgetTester tester, Side side) async {
  // Open the side picker by tapping on the side settings tile
  await tester.ensureVisible(find.text('Side'));
  await tester.tap(find.text('Side'));
  await tester.pumpAndSettle();

  // Select the desired side from the picker
  switch (side) {
    case Side.white:
      await tester.tap(find.text('White'));
    case Side.black:
      await tester.tap(find.text('Black'));
  }
  await tester.pumpAndSettle();
}

/// Initialize an offline computer game and return the board rect.
Future<Rect> initOfflineComputerGame(
  WidgetTester tester, {
  Variant? variant,
  String? fen,
  Side side = Side.white,
}) async {
  final gameStorage = MockOfflineComputerGameStorage();
  when(() => gameStorage.fetchGame()).thenAnswer((_) async => null);
  // Sending the app to the background saves the game as well as stopping the analysis.
  when(() => gameStorage.save(any())).thenAnswer((_) async {});

  final app = await makeTestProviderScopeApp(
    tester,
    home: OfflineComputerGameScreen(initialVariant: variant, initialFen: fen),
    overrides: {
      offlineComputerGameStorageProvider: offlineComputerGameStorageProvider.overrideWith(
        (_) => gameStorage,
      ),
    },
  );
  await tester.pumpWidget(app);

  // Wait for new game dialog to show up
  await tester.pumpAndSettle();

  // Select the side using the picker
  await selectSide(tester, side);

  // Tap Play to start game
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();

  return tester.getRect(find.byType(Chessboard));
}
