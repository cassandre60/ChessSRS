import 'dart:convert';
import 'dart:math';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/view/analysis/analysis_layout.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:chess_srs/src/widgets/pockets.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

void main() {
  testWidgets('board background size should match board size on all surfaces', (
    WidgetTester tester,
  ) async {
    for (final surface in kTestSurfaces) {
      final app = await makeTestProviderScope(
        key: ValueKey(surface),
        tester,
        child: MaterialApp(
          home: DefaultTabController(
            length: 1,
            child: AnalysisLayout(
              pov: Side.white,
              sideToMove: Side.white,
              boardBuilder: (context, boardSize, boardRadius) {
                return StaticChessboard(
                  size: boardSize,
                  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
                  orientation: Side.white,
                );
              },
              bottomBar: const SizedBox(height: kBottomBarHeight),
              children: const [Center(child: Text('Analysis tab'))],
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

      final boardSize = tester.getSize(find.byType(StaticChessboard));

      expect(boardSize.width, boardSize.height, reason: 'Board size is square on $surface');

      expect(
        boardSize,
        backgroundSize,
        reason: 'Board size should match background size on $surface',
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
        child: MaterialApp(
          home: DefaultTabController(
            length: 1,
            child: AnalysisLayout(
              pov: Side.white,
              sideToMove: Side.white,
              boardBuilder: (context, boardSize, boardRadius) {
                return StaticChessboard(
                  size: boardSize,
                  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
                  orientation: Side.white,
                );
              },
              bottomBar: const SizedBox(height: kBottomBarHeight),
              children: const [Center(child: Text('Analysis tab'))],
            ),
          ),
        ),
        surfaceSize: surface,
      );
      await tester.pumpWidget(app);

      final isPortrait = surface.aspectRatio < 1.0;
      final isTablet = surface.shortestSide > 600;
      final boardSize = tester.getSize(find.byType(StaticChessboard));

      if (isPortrait) {
        final expectedBoardSize = isTablet ? surface.width - 32.0 : surface.width;
        expect(
          boardSize,
          Size(expectedBoardSize, expectedBoardSize),
          reason: 'Board size should match surface width on $surface',
        );
      } else {
        final tabBarViewSize = tester.getSize(find.byType(TabBarView));
        final goldenBoardSize = (surface.longestSide / kGoldenRatio) - 32.0;
        final defaultBoardSize = surface.shortestSide - kBottomBarHeight - 32.0;
        final minBoardSize = min(goldenBoardSize, defaultBoardSize);
        final maxBoardSize = max(goldenBoardSize, defaultBoardSize);
        // TabBarView is inside a Card so we need to account for its padding
        const cardPadding = 8.0;
        final minSideWidth = min(
          surface.longestSide - goldenBoardSize - 16.0 * 3 - cardPadding,
          250.0,
        );
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
          tabBarViewSize.width,
          greaterThanOrEqualTo(minSideWidth),
          reason: 'Tab bar view width should be at least $minSideWidth on $surface',
        );
      }
    }
  }, variant: kPlatformVariant);

  testWidgets('Landscape board position', (WidgetTester tester) async {
    for (final boardPosition in LandscapeBoardPosition.values) {
      const tabletSurface = Size(1280, 800);
      final app = await makeTestProviderScope(
        key: ValueKey(boardPosition),
        tester,
        child: MaterialApp(
          home: DefaultTabController(
            length: 1,
            child: AnalysisLayout(
              pov: Side.white,
              sideToMove: Side.white,
              boardBuilder: (context, boardSize, boardRadius) {
                return StaticChessboard(
                  size: boardSize,
                  fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
                  orientation: Side.white,
                );
              },
              bottomBar: const SizedBox(height: kBottomBarHeight),
              children: const [Center(child: Text('Analysis tab'))],
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

      final boardTopLeft = tester.getTopLeft(find.byType(StaticChessboard));
      final tabBarTopLeft = tester.getTopLeft(find.byType(TabBarView));

      expect(
        tabBarTopLeft.dx,
        boardPosition == LandscapeBoardPosition.left
            ? greaterThan(boardTopLeft.dx)
            : lessThan(boardTopLeft.dx),
      );
    }
  }, variant: kPlatformVariant);

  testWidgets('tab strip is a segmented switch and taps change the page', (
    WidgetTester tester,
  ) async {
    // The Material tab bar (with its icon vocabulary) is gone: one segmented control
    // over the same swipeable pages. Fails on base, which built a TabBar.
    //
    // The App flavour of the harness, not the bare MaterialApp: the strip reads
    // localized tab labels, and only the App wrapper provides the delegates.
    final app = await makeTestProviderScopeApp(
      tester,
      home: DefaultTabController(
        length: 2,
        child: AnalysisLayout(
          pov: Side.white,
          sideToMove: Side.white,
          tabs: const [AnalysisTab.moves, AnalysisTab.explorer],
          boardBuilder: (context, boardSize, boardRadius) {
            return StaticChessboard(
              size: boardSize,
              fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
              orientation: Side.white,
            );
          },
          bottomBar: const SizedBox(height: kBottomBarHeight),
          children: const [
            Center(child: Text('Moves page')),
            Center(child: Text('Explorer page')),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsOneWidget);
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.byType(SrsSegmented<int>), findsOneWidget);
    expect(find.text('Moves page'), findsOneWidget);

    await tester.tap(find.text('Explorer'));
    await tester.pumpAndSettle();
    expect(find.text('Explorer page'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Geometry contracts pinned by the Stream A mutation round.
  //
  // SPEC: no invariant in SPEC.md names the analysis-layout geometry, and G05
  // rejects unknown INV ids, so these tests cite none on purpose. What they
  // pin is the layout's own documented contract -- "The layout is responsive
  // and adapts to the screen size and orientation" (analysis_layout.dart) --
  // read through the board builder, the layout's only seam for the geometry
  // it decides.
  // ---------------------------------------------------------------------------

  /// Pumps an [AnalysisLayout] on a surface of [surfaceSize] and returns the
  /// geometry the layout handed to its board builder.
  ///
  /// The board builder is the layout's seam: it receives the board's edge
  /// length and the corner radius, so capturing it reads the decision the
  /// layout made instead of re-deriving it from the painted tree.
  Future<({double size, BorderRadius? radius})> pumpAnalysisLayout(
    WidgetTester tester, {
    required Size surfaceSize,
    bool smallBoard = false,
    Widget? boardHeader,
    Widget? boardFooter,
    Pockets? pockets,
    bool withEngineGauge = false,
  }) async {
    ({double size, BorderRadius? radius})? geometry;
    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: DefaultTabController(
          length: 1,
          child: AnalysisLayout(
            pov: Side.white,
            sideToMove: Side.white,
            smallBoard: smallBoard,
            boardHeader: boardHeader,
            boardFooter: boardFooter,
            pockets: pockets,
            engineGaugeBuilder: withEngineGauge
                ? (context) => SizedBox(
                    key: const ValueKey('analysis-gauge'),
                    width: getEvalGaugeWidth(context),
                    height: 10,
                  )
                : null,
            boardBuilder: (context, boardSize, boardRadius) {
              geometry = (size: boardSize, radius: boardRadius);
              return StaticChessboard(
                size: boardSize,
                fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
                orientation: Side.white,
              );
            },
            bottomBar: const SizedBox(height: kBottomBarHeight),
            children: const [Center(child: Text('Analysis tab'))],
          ),
        ),
      ),
      surfaceSize: surfaceSize,
    );
    await tester.pumpWidget(app);

    expect(geometry, isNotNull, reason: 'the board builder must have been called');
    return geometry!;
  }

  testWidgets('the available area decides the orientation, not the screen', (
    WidgetTester tester,
  ) async {
    // A square available area (500 x 500 once the 56px bottom bar is taken
    // off) is portrait: the board is scaled to the width and the tab view sits
    // below it.
    final square = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(500, 556),
      smallBoard: true,
    );
    expect(square.size, 500 * kSmallBoardScale);
    expect(
      tester.getRect(find.byType(TabBarView)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(StaticChessboard)).bottom),
      reason: 'a square available area is portrait: the tab view is below the board',
    );

    // A wide available area is landscape: the tab view shares the board's row.
    final wide = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(700, 500),
      smallBoard: true,
    );
    expect(wide.size, 500 - kBottomBarHeight - kTabletBoardTableSidePadding * 2);
    expect(
      tester.getRect(find.byType(TabBarView)).top,
      lessThan(tester.getRect(find.byType(StaticChessboard)).bottom),
      reason: 'a wide available area is landscape: the tab view is beside the board',
    );
  });

  testWidgets('the landscape board switches to the golden ratio below 250 of side width', (
    WidgetTester tester,
  ) async {
    // 994 x 800 leaves a 994 x 744 area, so the side width is exactly 250.
    final atThreshold = await pumpAnalysisLayout(tester, surfaceSize: const Size(994, 800));
    expect(
      atThreshold.size,
      800 - kBottomBarHeight - kTabletBoardTableSidePadding * 2,
      reason: 'at 250 of side width the board takes the full height of the area',
    );

    // One pixel less of side width: the board falls back to the golden ratio
    // of the width.
    final belowThreshold = await pumpAnalysisLayout(tester, surfaceSize: const Size(993, 800));
    expect(
      belowThreshold.size,
      closeTo(993 / kGoldenRatio - kTabletBoardTableSidePadding * 2, 0.001),
      reason: 'below 250 of side width the board follows the golden ratio of the width',
    );
  });

  testWidgets('the portrait board leaves the engine gauge its width', (WidgetTester tester) async {
    const surface = Size(500, 1000);
    final geometry = await pumpAnalysisLayout(tester, surfaceSize: surface, withEngineGauge: true);
    final gaugeWidth = getEvalGaugeWidth(tester.element(find.byType(AnalysisLayout)));

    expect(
      geometry.size + gaugeWidth,
      closeTo(surface.width, 0.001),
      reason: 'the board and the gauge share the width of the screen',
    );
    // The board runs edge to edge: a handset gets no side padding.
    expect(
      tester.getRect(find.byType(StaticChessboard)).left,
      0,
      reason: 'the board starts at the left edge of the screen',
    );
  });

  testWidgets('the pocket padding grows only below 200 of remaining height', (
    WidgetTester tester,
  ) async {
    // 400 x 600 area: 600 - 400 = exactly 200 of remaining height, which is
    // not "short", so the pockets take the roomy 16px.
    final roomy = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(400, 656),
      pockets: Pockets.empty.increment(Side.white, Role.knight),
    );
    expect(
      roomy.size,
      400 - 16.0,
      reason: 'with exactly 200 of remaining height the pockets take 16px',
    );

    // One pixel less of height and the screen counts as short, so the pockets
    // take 70px and the board gives way.
    final cramped = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(400, 655),
      pockets: Pockets.empty.increment(Side.white, Role.knight),
    );
    expect(cramped.size, 400 - 70.0, reason: 'below 200 of remaining height the pockets take 70px');
  });

  testWidgets('the board header and footer are rendered, and the board leaves room for them', (
    WidgetTester tester,
  ) async {
    const header = Text('header');
    const footer = Text('footer');

    // Landscape: the board is the height of the column minus the header and
    // the footer.
    final landscape = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(1280, 800),
      boardHeader: header,
      boardFooter: footer,
    );
    expect(find.text('header'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
    expect(
      landscape.size,
      800 -
          kBottomBarHeight -
          kTabletBoardTableSidePadding * 2 -
          kAnalysisBoardHeaderOrFooterHeight * 2,
    );

    // Portrait: the header and the footer stack around the board, which keeps
    // the width of the screen.
    final portrait = await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(800, 1280),
      boardHeader: header,
      boardFooter: footer,
    );
    expect(find.text('header'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
    expect(portrait.size, 800 - kTabletBoardTableSidePadding * 2);
  });

  testWidgets('the board radius follows the header and the footer', (WidgetTester tester) async {
    for (final surface in const [Size(1280, 800), Size(800, 1280)]) {
      // A board at the top of the stack, with something below it, carries the
      // rounded corners.
      final withFooter = await pumpAnalysisLayout(
        tester,
        surfaceSize: surface,
        boardFooter: const Text('footer'),
      );
      expect(
        withFooter.radius,
        Styles.boardBorderRadius,
        reason: 'a board at the top of the stack is rounded on $surface',
      );

      // A header above the board takes the rounded corners instead.
      final withHeader = await pumpAnalysisLayout(
        tester,
        surfaceSize: surface,
        boardHeader: const Text('header'),
      );
      expect(
        withHeader.radius,
        isNull,
        reason: 'a header above the board takes the corners on $surface',
      );

      // Sandwiched between a header and a footer, the board has square
      // corners.
      final withBoth = await pumpAnalysisLayout(
        tester,
        surfaceSize: surface,
        boardHeader: const Text('header'),
        boardFooter: const Text('footer'),
      );
      expect(withBoth.radius, isNull, reason: 'a sandwiched board has square corners on $surface');
    }
  });

  testWidgets('the engine gauge is rendered beside the board', (WidgetTester tester) async {
    for (final surface in const [Size(1280, 800), Size(500, 1000)]) {
      await pumpAnalysisLayout(tester, surfaceSize: surface, withEngineGauge: true);
      expect(
        find.byKey(const ValueKey('analysis-gauge')),
        findsOneWidget,
        reason: 'the engine gauge is rendered on $surface',
      );
    }
  });

  testWidgets('in landscape the pockets are rendered above and below the board', (
    WidgetTester tester,
  ) async {
    await pumpAnalysisLayout(
      tester,
      surfaceSize: const Size(1280, 800),
      pockets: Pockets.empty.increment(Side.white, Role.knight),
    );

    expect(find.byType(PocketsMenu), findsNWidgets(2));
    // The opponent's pockets sit above the board, ours below it, so the white
    // knight is only counted in the lower menu.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pocket-whiteknight')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pocket-blackknight')),
        matching: find.text('1'),
      ),
      findsNothing,
    );
  });

  testWidgets('a single tab renders no segmented strip', (WidgetTester tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: DefaultTabController(
        length: 1,
        child: AnalysisLayout(
          pov: Side.white,
          sideToMove: Side.white,
          tabs: const [AnalysisTab.moves],
          boardBuilder: (context, boardSize, boardRadius) {
            return StaticChessboard(
              size: boardSize,
              fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
              orientation: Side.white,
            );
          },
          bottomBar: const SizedBox(height: kBottomBarHeight),
          children: const [Center(child: Text('Moves page'))],
        ),
      ),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.byType(SrsSegmented<int>), findsNothing);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('the landscape board fits the height of the column it is laid out in', (
    WidgetTester tester,
  ) async {
    // A 480 x 300 window with the 56px bottom bar leaves a 480 x 244 area, so
    // the side width is 236: under the 250 threshold, the board follows the
    // golden ratio of the width (480 / 1.618 - 32 = 264.67 px) while the
    // column it is laid out in only has 244 - 2 x 16 = 212 px of height.
    //
    // The overflow is invisible to the suite: the shared provider scope
    // swallows every "A RenderFlex overflowed by" error, so this test asserts
    // the geometry and not the absence of an exception.
    const surface = Size(480, 300);
    final app = await makeTestProviderScope(
      tester,
      child: MaterialApp(
        home: DefaultTabController(
          length: 1,
          child: AnalysisLayout(
            pov: Side.white,
            sideToMove: Side.white,
            boardBuilder: (context, boardSize, boardRadius) {
              return StaticChessboard(
                size: boardSize,
                fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR',
                orientation: Side.white,
              );
            },
            bottomBar: const SizedBox(height: kBottomBarHeight),
            children: const [Center(child: Text('Analysis tab'))],
          ),
        ),
      ),
      surfaceSize: surface,
    );
    await tester.pumpWidget(app);

    final board = find.byType(StaticChessboard);
    // The column that holds the board: the closest Column above it.
    final column = find.ancestor(of: board, matching: find.byType(Column)).first;

    expect(
      tester.getSize(board).height,
      lessThanOrEqualTo(tester.getSize(column).height),
      reason: 'the board must fit the height of the column it is laid out in',
    );
  });
}
