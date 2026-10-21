import 'dart:convert';
import 'dart:math';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/game/game_board_params.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/widgets/board.dart';
import 'package:chess_srs/src/widgets/game_layout.dart';
import 'package:chess_srs/src/widgets/move_list.dart';
import 'package:chess_srs/src/widgets/pockets.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test_helpers.dart';
import '../test_provider_scope.dart';

void main() {
  // `makeTestProviderScopeApp` supplies [SrsTheme] because it builds its own `MaterialApp`; a test
  // that passes its own `child` gets no theme. The design tokens are documented as provided once
  // near the root and the real app always has them, so a test that builds its own tree has to
  // supply them too — otherwise `context.srs` asserts as soon as a reskinned widget is built.
  Widget srsThemed(Widget child) =>
      SrsTheme(colors: SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent), child: child);

  testWidgets('board background size should match board size on all surfaces', (
    WidgetTester tester,
  ) async {
    for (final surface in kTestSurfaces) {
      final app = await makeTestProviderScope(
        key: ValueKey(surface),
        tester,
        child: const MaterialApp(
          home: GameLayout(
            orientation: Side.white,
            boardParams: GameBoardParams.readonly(
              variant: Variant.standard,
              position: Chess.initial,
            ),
            topTable: Row(
              mainAxisSize: MainAxisSize.max,
              key: ValueKey('top_table'),
              children: [Text('Top table')],
            ),
            bottomTable: Row(
              mainAxisSize: MainAxisSize.max,
              key: ValueKey('bottom_table'),
              children: [Text('Bottom table')],
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      final backgroundSize = tester.getSize(find.byType(SolidColorChessboardBackground));

      expect(
        backgroundSize.width,
        backgroundSize.height,
        reason: 'Board background size is square on $surface',
      );

      final boardSize = tester.getSize(find.byType(Chessboard));

      expect(boardSize.width, boardSize.height, reason: 'Board size is square on $surface');

      expect(
        boardSize,
        backgroundSize,
        reason: 'Board size should match background size on $surface',
      );
    }
  }, variant: kPlatformVariant);

  testWidgets('Landscape board position', (WidgetTester tester) async {
    for (final boardPosition in LandscapeBoardPosition.values) {
      const tabletSurface = Size(1280, 800);
      final app = await makeTestProviderScope(
        key: ValueKey(boardPosition),
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              moves: ['e4', 'e5'],
              topTable: Row(
                mainAxisSize: MainAxisSize.max,
                key: ValueKey('top_table'),
                children: [Text('Top table')],
              ),
              bottomTable: Row(
                mainAxisSize: MainAxisSize.max,
                key: ValueKey('bottom_table'),
                children: [Text('Bottom table')],
              ),
            ),
          ),
        ),
        defaultPreferences: {
          PrefCategory.board.storageKey: jsonEncode(
            BoardPrefs.defaults.copyWith(landscapeBoardPosition: boardPosition).toJson(),
          ),
        },
        surfaceSize: tabletSurface,
      );
      await tester.pumpWidget(app);

      final boardTopLeft = tester.getTopLeft(find.byType(Chessboard));
      final moveListTopLeft = tester.getTopLeft(find.byType(MoveList));

      expect(
        moveListTopLeft.dx,
        boardPosition == LandscapeBoardPosition.left
            ? greaterThan(boardTopLeft.dx)
            : lessThan(boardTopLeft.dx),
      );
    }
  }, variant: kPlatformVariant);

  testWidgets('board size and table side size should be harmonious on all surfaces', (
    WidgetTester tester,
  ) async {
    for (final surface in kTestSurfaces) {
      final app = await makeTestProviderScope(
        key: ValueKey(surface),
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              topTable: Row(
                mainAxisSize: MainAxisSize.max,
                key: ValueKey('top_table'),
                children: [Text('Top table')],
              ),
              bottomTable: Row(
                mainAxisSize: MainAxisSize.max,
                key: ValueKey('bottom_table'),
                children: [Text('Bottom table')],
              ),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      final isPortrait = surface.aspectRatio < 1.0;
      final isTablet = surface.shortestSide > 600;
      final boardSize = tester.getSize(find.byType(Chessboard));

      if (isPortrait) {
        // isShortVerticalScreen uses viewPadding=0 in tests, kToolbarHeight=56, kBottomBarHeight=56
        final isShortScreen =
            surface.height - surface.width - kToolbarHeight - kBottomBarHeight <
            kSmallHeightMinusBoard;

        double expectedBoardSize = isTablet ? surface.width - 32.0 : surface.width;

        final maxAllowedBoardSize = surface.height - 180.0;
        if (expectedBoardSize > maxAllowedBoardSize) {
          expectedBoardSize = maxAllowedBoardSize;
        }

        if (isShortScreen) {
          expectedBoardSize -= 16.0;
        }

        expect(
          boardSize,
          Size(expectedBoardSize, expectedBoardSize),
          reason: 'Board size should be $expectedBoardSize on $surface',
        );
      } else {
        final topTableSize = tester.getSize(find.byKey(const ValueKey('top_table')));
        final bottomTableSize = tester.getSize(find.byKey(const ValueKey('bottom_table')));
        final goldenBoardSize = (surface.longestSide / kGoldenRatio) - 32.0;
        final defaultBoardSize = surface.shortestSide - 32.0;
        final minBoardSize = min(goldenBoardSize, defaultBoardSize);
        final maxBoardSize = max(goldenBoardSize, defaultBoardSize);
        final minSideWidth = min(surface.longestSide - goldenBoardSize - 16.0 * 3, 250.0);
        expect(
          boardSize.width,
          greaterThanOrEqualTo(minBoardSize),
          reason: 'Board size should be at least $minBoardSize on $surface',
        );
        expect(
          boardSize.width,
          lessThanOrEqualTo(maxBoardSize),
          reason: 'Board size should be at most $maxBoardSize on $surface',
        );
        expect(
          bottomTableSize.width,
          greaterThanOrEqualTo(minSideWidth),
          reason: 'Bottom table width should be at least $minSideWidth on $surface',
        );
        expect(
          topTableSize.width,
          greaterThanOrEqualTo(minSideWidth),
          reason: 'Top table width should be at least $minSideWidth on $surface',
        );
      }
    }
  }, variant: kPlatformVariant);

  test('variantBoardOrientation', () {
    for (final variant in Variant.values.where((v) => v != Variant.racingKings)) {
      expect(
        variantBoardOrientation(variant: variant, youAre: Side.white, isBoardTurned: false),
        Side.white,
      );
      expect(
        variantBoardOrientation(variant: variant, youAre: Side.black, isBoardTurned: false),
        Side.black,
      );
      expect(
        variantBoardOrientation(variant: variant, youAre: Side.white, isBoardTurned: true),
        Side.black,
      );
      expect(
        variantBoardOrientation(variant: variant, youAre: Side.black, isBoardTurned: true),
        Side.white,
      );
    }

    expect(
      variantBoardOrientation(
        variant: Variant.racingKings,
        youAre: Side.white,
        isBoardTurned: false,
      ),
      Side.white,
    );
    expect(
      variantBoardOrientation(
        variant: Variant.racingKings,
        youAre: Side.black,
        isBoardTurned: false,
      ),
      Side.white,
    );
    expect(
      variantBoardOrientation(
        variant: Variant.racingKings,
        youAre: Side.white,
        isBoardTurned: true,
      ),
      Side.black,
    );
    expect(
      variantBoardOrientation(
        variant: Variant.racingKings,
        youAre: Side.black,
        isBoardTurned: true,
      ),
      Side.black,
    );
  });

  testWidgets('owned board becomes interactive when boardParams transitions from readonly', (
    WidgetTester tester,
  ) async {
    final paramsNotifier = ValueNotifier<GameBoardParams>(GameBoardParams.emptyBoard);
    addTearDown(paramsNotifier.dispose);
    final playedMoves = <Move>[];

    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: ValueListenableBuilder<GameBoardParams>(
          valueListenable: paramsNotifier,
          builder: (context, params, _) => GameLayout(orientation: Side.white, boardParams: params),
        ),
      ),
    );
    await tester.pumpWidget(app);

    // Readonly boards are controller-backed but non-interactive (PlayerSide.none).
    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isFalse);

    // Transition the same GameLayout to interactive params (triggers didUpdateWidget).
    paramsNotifier.value = GameBoardParams.interactive(
      variant: Variant.standard,
      position: Chess.initial,
      playerSide: PlayerSide.white,
      onMove: (move, {viaDragAndDrop}) {
        playedMoves.add(move);
      },
    );
    await tester.pump();

    // The same board is now interactive.
    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isTrue);

    // And user interaction reaches the onMove callback.
    await playMove(tester, 'e2', 'e4');
    expect(playedMoves, [const NormalMove(from: Square.e2, to: Square.e4)]);
  }, variant: kPlatformVariant);

  testWidgets('Crazyhouse displays pockets and supports drop moves', (WidgetTester tester) async {
    final playedMoves = <Move>[];
    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: GameLayout(
          orientation: Side.white,
          boardParams: GameBoardParams.interactive(
            variant: Variant.crazyhouse,
            position: Crazyhouse.fromSetup(
              Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
            ),
            playerSide: PlayerSide.white,
            onMove: (move, {viaDragAndDrop}) {
              playedMoves.add(move);
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(app);

    expect(find.byType(PocketsMenu), findsNWidgets(2));

    // Only the pockets of the player side should be interactive.
    await playDropMove(tester, Side.white, Role.pawn, 'a4');
    await playDropMove(tester, Side.black, Role.pawn, 'a3');

    expect(playedMoves, [const DropMove(to: Square.a4, role: Role.pawn)]);
  });

  testWidgets('readonly board animates to a new position and highlights the last move', (
    tester,
  ) async {
    final after1e4 = Chess.initial.play(const NormalMove(from: Square.e2, to: Square.e4));
    final boardNotifier = ValueNotifier<({Position position, Move? lastMove})>((
      position: Chess.initial,
      lastMove: null,
    ));
    addTearDown(boardNotifier.dispose);

    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: ValueListenableBuilder<({Position position, Move? lastMove})>(
          valueListenable: boardNotifier,
          builder: (context, value, _) => GameLayout(
            orientation: Side.white,
            boardParams: GameBoardParams.readonly(
              variant: Variant.standard,
              position: value.position,
              lastMove: value.lastMove,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app);

    expect(boardHasPiece(tester, Square.e2, Piece.whitePawn), isTrue);
    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isFalse);

    // Advance the readonly board to the position after 1.e4.
    boardNotifier.value = (
      position: after1e4,
      lastMove: const NormalMove(from: Square.e2, to: Square.e4),
    );
    await tester.pumpAndSettle();

    expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isTrue);
    expect(getBoardPieces(tester).containsKey(Square.e2), isFalse);
    expect(getBoardLastMove(tester), const NormalMove(from: Square.e2, to: Square.e4));
    // It must remain non-interactive throughout.
    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isFalse);
  });

  testWidgets('interactive board can be disabled via a metadata-only update (PlayerSide.none)', (
    tester,
  ) async {
    void noopOnMove(Move move, {bool? viaDragAndDrop}) {}

    final sideNotifier = ValueNotifier<PlayerSide>(PlayerSide.white);
    addTearDown(sideNotifier.dispose);

    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: ValueListenableBuilder<PlayerSide>(
          valueListenable: sideNotifier,
          builder: (context, playerSide, _) => GameLayout(
            orientation: Side.white,
            boardParams: GameBoardParams.interactive(
              variant: Variant.standard,
              position: Chess.initial,
              playerSide: playerSide,
              onMove: noopOnMove,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app);

    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isTrue);

    // Same position, only the playerSide changes (e.g. game over) — the board
    // should become non-interactive without a position change.
    sideNotifier.value = PlayerSide.none;
    await tester.pump();

    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isFalse);
    expect(getBoardPieces(tester).length, 32);
  });

  testWidgets('controllerParams path renders the external controller and does not dispose it', (
    tester,
  ) async {
    final playedMoves = <Move>[];
    final controller = ChessboardController(
      game: buildGameData(
        fen: kInitialFEN,
        variant: Variant.standard,
        position: Chess.initial,
        playerSide: PlayerSide.white,
        castlingMethod: CastlingMethod.kingTwoSquares,
        boardHighlights: true,
      ),
    );
    addTearDown(controller.dispose);

    final showBoard = ValueNotifier<bool>(true);
    addTearDown(showBoard.dispose);

    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showBoard,
          builder: (context, show, _) => show
              ? GameLayout(
                  orientation: Side.white,
                  controllerParams: ControllerBoardParams(
                    controller: controller,
                    variant: Variant.standard,
                    onMove: (move, {viaDragAndDrop}) => playedMoves.add(move),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpWidget(app);

    expect(tester.widget<Chessboard>(find.byType(Chessboard)).interactive, isTrue);

    await playMove(tester, 'e2', 'e4');
    expect(playedMoves, [const NormalMove(from: Square.e2, to: Square.e4)]);

    // Removing the GameLayout must not dispose the externally-owned controller.
    showBoard.value = false;
    await tester.pumpAndSettle();
    expect(
      () => controller.updatePosition(
        buildGameData(
          fen: kInitialFEN,
          variant: Variant.standard,
          position: Chess.initial,
          playerSide: PlayerSide.white,
          castlingMethod: CastlingMethod.kingTwoSquares,
          boardHighlights: true,
        ),
      ),
      returnsNormally,
    );
  });

  // The tests below pin the behaviours a Stream-A mutation round on
  // lib/src/widgets/game_layout.dart found unprotected: each one fails when the
  // named mutation is applied to the widget and passes on the committed source.
  //
  // SPEC.md has no invariant for the game layout's own geometry and chrome --
  // it covers the board squares (INV-061), the tap targets (INV-062) and the
  // review UX (INV-060), none of which names a size or a chrome decision made
  // here. The tests that pin a viewport decision (the board fitting its
  // viewport, the pockets getting their room, the tables staying on screen)
  // cite INV-062, whose contract is "survive narrow viewports without
  // clipping"; the ones that pin a default or a state transition say so in
  // their own comment rather than borrow an invariant that does not name them.
  group('GameLayout chrome and geometry', () {
    testWidgets('the tables are upright unless the layout asks for them upside down', (
      tester,
    ) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- a layout that
      // does not ask for an upside-down table renders it upright.
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              topTable: _TableMarker(key: ValueKey('top_table')),
              bottomTable: _TableMarker(key: ValueKey('bottom_table')),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // Each table carries a marker pinned to its own top-left corner. A table
      // rendered upside down is drawn rotated by half a turn, which puts the
      // marker at the bottom-right of the table's box instead.
      for (final key in const ['top_table', 'bottom_table']) {
        final table = tester.getRect(find.byKey(ValueKey(key)));
        final marker = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byKey(const ValueKey('marker')),
          ),
        );
        expect(marker.left, moreOrLessEquals(table.left, epsilon: 0.5), reason: '$key is upright');
        expect(marker.top, moreOrLessEquals(table.top, epsilon: 0.5), reason: '$key is upright');
      }
    });

    testWidgets('the empty layout still shows the moves it was given', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- an empty
      // layout is not in zen mode, so the moves it is given are listed.
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(const MaterialApp(home: GameLayout.empty(moves: ['e4', 'e5']))),
      );
      await tester.pumpWidget(app);

      expect(find.byType(MoveList), findsOneWidget);
      expect(find.text('e4'), findsOneWidget);
    });

    testWidgets('a position change plays the pending premove', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- when the
      // opponent moves, the premove the user queued is played.
      final premoves = <Move>[];
      final after1d4 = Chess.initial.play(const NormalMove(from: Square.d2, to: Square.d4));
      final after1d4d5 = after1d4.play(const NormalMove(from: Square.d7, to: Square.d5));
      final paramsNotifier = ValueNotifier<GameBoardParams>(
        GameBoardParams.interactive(
          variant: Variant.standard,
          position: after1d4,
          playerSide: PlayerSide.white,
          onMove: (move, {viaDragAndDrop}) {},
        ),
      );
      addTearDown(paramsNotifier.dispose);

      final app = await makeTestProviderScope(
        tester,
        child: MaterialApp(
          home: ValueListenableBuilder<GameBoardParams>(
            valueListenable: paramsNotifier,
            builder: (context, params, _) => GameLayout(
              orientation: Side.white,
              boardParams: params,
              onPremove: (move) => premoves.add(move),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // The user queues a premove while the opponent is to move.
      final controller = tester.widget<Chessboard>(find.byType(Chessboard)).controller;
      controller.premove = const NormalMove(from: Square.e2, to: Square.e4);

      // The opponent moves: the position changes and the premove is legal.
      paramsNotifier.value = GameBoardParams.interactive(
        variant: Variant.standard,
        position: after1d4d5,
        playerSide: PlayerSide.white,
        onMove: (move, {viaDragAndDrop}) {},
      );
      await tester.pump();

      expect(premoves, [const NormalMove(from: Square.e2, to: Square.e4)]);
    });

    testWidgets('a takeback clears the pending premove instead of playing it', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- a revert
      // rolls the line back, so a premove queued for the old line must not be
      // played on the new one.
      final premoves = <Move>[];
      final after1d4 = Chess.initial.play(const NormalMove(from: Square.d2, to: Square.d4));
      final after1d4d5 = after1d4.play(const NormalMove(from: Square.d7, to: Square.d5));
      final paramsNotifier = ValueNotifier<GameBoardParams>(
        GameBoardParams.interactive(
          variant: Variant.standard,
          position: after1d4d5,
          playerSide: PlayerSide.white,
          onMove: (move, {viaDragAndDrop}) {},
        ),
      );
      addTearDown(paramsNotifier.dispose);

      final app = await makeTestProviderScope(
        tester,
        child: MaterialApp(
          home: ValueListenableBuilder<GameBoardParams>(
            valueListenable: paramsNotifier,
            builder: (context, params, _) => GameLayout(
              orientation: Side.white,
              boardParams: params,
              onPremove: (move) => premoves.add(move),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final controller = tester.widget<Chessboard>(find.byType(Chessboard)).controller;
      controller.premove = const NormalMove(from: Square.e2, to: Square.e4);

      // The line is taken back: the ply goes down.
      paramsNotifier.value = GameBoardParams.interactive(
        variant: Variant.standard,
        position: after1d4,
        playerSide: PlayerSide.white,
        onMove: (move, {viaDragAndDrop}) {},
      );
      await tester.pump();

      expect(premoves, isEmpty);
      expect(controller.premove, isNull);
    });

    testWidgets('replaying the history clears the pending premove', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- while the
      // history is replayed the board is not a game, so a premove queued for it
      // must not survive the jump.
      final after1d4 = Chess.initial.play(const NormalMove(from: Square.d2, to: Square.d4));
      final after1d4d5 = after1d4.play(const NormalMove(from: Square.d7, to: Square.d5));
      final paramsNotifier = ValueNotifier<GameBoardParams>(
        GameBoardParams.interactive(
          variant: Variant.standard,
          position: after1d4,
          playerSide: PlayerSide.white,
          onMove: (move, {viaDragAndDrop}) {},
        ),
      );
      addTearDown(paramsNotifier.dispose);

      final app = await makeTestProviderScope(
        tester,
        child: MaterialApp(
          home: ValueListenableBuilder<GameBoardParams>(
            valueListenable: paramsNotifier,
            builder: (context, params, _) =>
                GameLayout(orientation: Side.white, boardParams: params, isReplaying: true),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final controller = tester.widget<Chessboard>(find.byType(Chessboard)).controller;
      controller.premove = const NormalMove(from: Square.e2, to: Square.e4);

      paramsNotifier.value = GameBoardParams.interactive(
        variant: Variant.standard,
        position: after1d4d5,
        playerSide: PlayerSide.white,
        onMove: (move, {viaDragAndDrop}) {},
      );
      await tester.pump();

      expect(controller.premove, isNull);
    });

    testWidgets('the layout follows the controller it renders', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- when the
      // owner swaps the controller, the layout listens to the new one.
      final crazyhouse = Crazyhouse.fromSetup(
        Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
      );
      ChessboardController makeController() => ChessboardController(
        game: buildGameData(
          fen: crazyhouse.fen,
          variant: Variant.crazyhouse,
          position: crazyhouse,
          playerSide: PlayerSide.white,
          castlingMethod: CastlingMethod.kingTwoSquares,
          boardHighlights: true,
        ),
      );
      final first = makeController();
      final second = makeController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final controllerNotifier = ValueNotifier<ChessboardController>(first);
      addTearDown(controllerNotifier.dispose);

      final app = await makeTestProviderScope(
        tester,
        child: MaterialApp(
          home: ValueListenableBuilder<ChessboardController>(
            valueListenable: controllerNotifier,
            builder: (context, controller, _) => GameLayout(
              orientation: Side.white,
              controllerParams: ControllerBoardParams(
                controller: controller,
                variant: Variant.crazyhouse,
                pockets: crazyhouse.pockets,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // The owner swaps in a new controller.
      controllerNotifier.value = second;
      await tester.pump();

      // A premove on the new controller must reach the layout, which shows the
      // role of the pending drop in the pockets.
      second.premove = const DropMove(to: Square.a4, role: Role.pawn);
      await tester.pump();

      final pockets = tester.widget<PocketsMenu>(find.byType(PocketsMenu).first);
      expect(pockets.premoveDropRole, Role.pawn);
    });

    testWidgets('the read-only board highlights the king only when it is in check', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- the check
      // highlight follows the position and the board-highlights preference.
      final inCheck = Chess.fromSetup(
        Setup.parseFen('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3'),
      );

      // A position that is not in check gets no check highlight.
      var app = await makeTestProviderScope(
        key: const ValueKey('not_in_check'),
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      expect(findBoardHighlightPainter(tester).interactionNotifier.checkSquare, isNull);

      // A position that is in check highlights the king.
      app = await makeTestProviderScope(
        key: const ValueKey('in_check'),
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(variant: Variant.standard, position: inCheck),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      expect(findBoardHighlightPainter(tester).interactionNotifier.checkSquare, Square.e1);

      // With the board highlights switched off, the king is not highlighted
      // even when it is in check. Each app gets its own provider scope, so the
      // preference is read again instead of being served from the previous
      // scope's state.
      app = await makeTestProviderScope(
        key: const ValueKey('in_check_without_highlights'),
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(variant: Variant.standard, position: inCheck),
            ),
          ),
        ),
        defaultPreferences: {
          PrefCategory.board.storageKey: jsonEncode(
            BoardPrefs.defaults.copyWith(boardHighlights: false).toJson(),
          ),
        },
      );
      await tester.pumpWidget(app);
      expect(findBoardHighlightPainter(tester).interactionNotifier.checkSquare, isNull);
    });

    testWidgets('the pockets have no side to move when the player has no side', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- a board with
      // no player has no side to move, so the pockets are not a drop source.
      final crazyhouse = Crazyhouse.fromSetup(
        Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
      );

      // The owned path: a board with no player.
      var app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.interactive(
                variant: Variant.crazyhouse,
                position: crazyhouse,
                playerSide: PlayerSide.none,
                onMove: (move, {viaDragAndDrop}) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      expect(tester.widget<PocketsMenu>(find.byType(PocketsMenu).first).sideToMove, isNull);

      // The controller path: a controller whose game has no player.
      final controller = ChessboardController(
        game: buildGameData(
          fen: crazyhouse.fen,
          variant: Variant.crazyhouse,
          position: crazyhouse,
          playerSide: PlayerSide.none,
          castlingMethod: CastlingMethod.kingTwoSquares,
          boardHighlights: true,
        ),
      );
      addTearDown(controller.dispose);

      app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              controllerParams: ControllerBoardParams(
                controller: controller,
                variant: Variant.crazyhouse,
                pockets: crazyhouse.pockets,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      expect(tester.widget<PocketsMenu>(find.byType(PocketsMenu).first).sideToMove, isNull);
    });

    testWidgets('a square viewport uses the portrait layout', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      const square = Size(800, 800);
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              topTable: SizedBox(key: ValueKey('top_table'), height: 40),
              bottomTable: SizedBox(key: ValueKey('bottom_table'), height: 40),
            ),
          ),
        ),
        surfaceSize: square,
      );
      await tester.pumpWidget(app);

      // Portrait stacks the tables above and below the board, so both tables
      // start to the left of the board's right edge. Landscape puts them in a
      // column beside the board, to the right of it.
      final board = tester.getRect(find.byType(Chessboard));
      expect(tester.getRect(find.byKey(const ValueKey('top_table'))).left, lessThan(board.right));
      expect(
        tester.getRect(find.byKey(const ValueKey('bottom_table'))).left,
        lessThan(board.right),
      );
    });

    testWidgets('the landscape board keeps the full height when the side panel is 250 wide', (
      tester,
    ) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      // 918 - 700 + 32 = 250, so the column left beside the board is exactly
      // 250 wide: the width at which the board stops being narrowed down.
      const surface = Size(918, 700);
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      // The board takes the whole height of the viewport, minus the padding.
      final board = tester.getSize(find.byType(Chessboard));
      expect(
        board.height,
        moreOrLessEquals(surface.height - kTabletBoardTableSidePadding * 2, epsilon: 0.5),
      );
      expect(board.width, moreOrLessEquals(board.height, epsilon: 0.5));
    });

    testWidgets('the landscape layout shows the user actions bar', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      const surface = Size(1280, 800);
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              userActionsBar: Text('ACTIONS'),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      expect(find.text('ACTIONS'), findsOneWidget);
    });

    testWidgets('a portrait tablet reserves room for the pockets', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      const surface = Size(800, 1280);
      const pocketPadding = 70.0;

      // Without pockets the board may use the whole width of the viewport.
      var app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);
      final plainBoard = tester.getSize(find.byType(Chessboard));

      // With pockets the board has to give them room.
      app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.crazyhouse,
                position: Crazyhouse.fromSetup(
                  Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
                ),
              ),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);
      final pocketsBoard = tester.getSize(find.byType(Chessboard));

      expect(pocketsBoard.width, lessThan(plainBoard.width));
      expect(plainBoard.width - pocketsBoard.width, moreOrLessEquals(pocketPadding, epsilon: 0.5));
    });

    testWidgets('the portrait layout shows the move list', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      // A phone with pockets: the pockets sit beside the board, and the move
      // list still has room above it.
      var app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.crazyhouse,
                position: Crazyhouse.fromSetup(
                  Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
                ),
              ),
              moves: const ['e4', 'e5'],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      expect(find.byType(MoveList), findsOneWidget);
      expect(find.text('e4'), findsOneWidget);

      // A tablet without pockets: the pockets are not what costs the move list
      // its room, so it is shown too.
      app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              moves: ['e4', 'e5'],
            ),
          ),
        ),
        surfaceSize: const Size(800, 1280),
      );
      await tester.pumpWidget(app);
      expect(find.byType(MoveList), findsOneWidget);
      expect(find.text('e4'), findsOneWidget);
    });

    testWidgets('the layout follows the viewport, not the looseness of its constraints', (
      tester,
    ) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      const surface = Size(1280, 800);
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: Center(
              child: GameLayout(
                orientation: Side.white,
                boardParams: GameBoardParams.readonly(
                  variant: Variant.standard,
                  position: Chess.initial,
                ),
                topTable: SizedBox(key: ValueKey('top_table'), height: 40),
                bottomTable: SizedBox(key: ValueKey('bottom_table'), height: 40),
              ),
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      // A centred layout is given loose constraints, but the viewport it is
      // shown in is still landscape, so the tables belong beside the board.
      final board = tester.getRect(find.byType(Chessboard));
      expect(
        tester.getRect(find.byKey(const ValueKey('top_table'))).left,
        greaterThan(board.right),
      );
    });

    testWidgets('the pockets are sized for the form factor', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      final crazyhouse = Crazyhouse.fromSetup(
        Setup.parseFen('rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3'),
      );

      // On a tablet the pockets are smaller than the board squares, so that
      // they do not overflow the space they are given.
      var app = await makeTestProviderScope(
        key: const ValueKey('tablet'),
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.crazyhouse,
                position: crazyhouse,
              ),
            ),
          ),
        ),
        surfaceSize: const Size(800, 1280),
      );
      await tester.pumpWidget(app);
      final tabletBoard = tester.getSize(find.byType(Chessboard));
      expect(
        tester.widgetList<PocketsMenu>(find.byType(PocketsMenu)).map((p) => p.squareSize),
        everyElement(lessThan(tabletBoard.width / 8)),
      );

      // On a phone the pockets are the size of a board square.
      app = await makeTestProviderScope(
        key: const ValueKey('phone'),
        tester,
        child: srsThemed(
          MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.crazyhouse,
                position: crazyhouse,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);
      final phoneBoard = tester.getSize(find.byType(Chessboard));
      expect(
        tester.widgetList<PocketsMenu>(find.byType(PocketsMenu)).map((p) => p.squareSize),
        everyElement(moreOrLessEquals(phoneBoard.width / 8, epsilon: 0.5)),
      );
    });

    testWidgets('an upside-down table is turned by half a turn', (tester) async {
      // No SPEC invariant names this behaviour: the game layout's chrome has no
      // invariant of its own. The contract is the widget's own -- a table drawn
      // upside down for an over-the-board game is turned, not swapped.
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              topTableUpsideDown: true,
              bottomTableUpsideDown: true,
              topTable: _TableMarker(key: ValueKey('top_table'), markerWidth: 20, markerHeight: 10),
              bottomTable: _TableMarker(
                key: ValueKey('bottom_table'),
                markerWidth: 20,
                markerHeight: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // Half a turn keeps the shape of the marker -- it is turned, not turned
      // sideways.
      for (final key in const ['top_table', 'bottom_table']) {
        final marker = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byKey(const ValueKey('marker')),
          ),
        );
        expect(marker.width, moreOrLessEquals(20, epsilon: 0.5), reason: '$key keeps its shape');
        expect(marker.height, moreOrLessEquals(10, epsilon: 0.5), reason: '$key keeps its shape');
      }
    });

    testWidgets('the top table gets the space it asked for', (tester) async {
      // SPEC INV-062: the layout survives the viewport it is given.
      final app = await makeTestProviderScope(
        tester,
        child: srsThemed(
          const MaterialApp(
            home: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.readonly(
                variant: Variant.standard,
                position: Chess.initial,
              ),
              topTableFlex: 3,
              bottomTableFlex: 1,
              topTable: SizedBox(key: ValueKey('top_table')),
              bottomTable: SizedBox(key: ValueKey('bottom_table')),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // The tables are given the share of the leftover height their flex asks
      // for, and the top table asked for three times the bottom one.
      double tableHeight(String key) => tester
          .getSize(
            find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(RotatedBox)).first,
          )
          .height;

      expect(tableHeight('top_table'), greaterThan(tableHeight('bottom_table')));
    });
  });
}

/// A stand-in for a game table.
///
/// The box has a fixed height and a small marker pinned to its top-left
/// corner, so a table that is drawn upside down -- rotated by half a turn --
/// can be told apart from one that is not.
class _TableMarker extends StatelessWidget {
  const _TableMarker({this.markerWidth = 10, this.markerHeight = 10, super.key});

  final double markerWidth;
  final double markerHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(key: const ValueKey('marker'), width: markerWidth, height: markerHeight),
      ),
    );
  }
}
