import 'dart:convert';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_screen.dart';
import 'package:chess_srs/src/view/more/more_tab_screen.dart';
import 'package:chess_srs/src/widgets/move_list.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

void main() {
  // final explorerViewFinder = find.descendant(
  //   of: find.byType(LayoutBuilder),
  //   matching: find.byType(Scrollable),
  // );

  final mockClient = MockClient((request) {
    if (request.url.host == kLichessOpeningExplorerHost) {
      if (request.url.path == '/masters') {
        return mockResponse(mastersOpeningExplorerResponse, 200);
      }
      if (request.url.path == '/lichess') {
        return mockResponse(lichessOpeningExplorerResponse, 200);
      }
      if (request.url.path == '/player') {
        return mockResponse(playerOpeningExplorerResponse, 200);
      }
    }
    if (request.url.host == 'www.chessdb.cn') {
      return mockResponse(
        jsonEncode({
          'status': 'ok',
          'moves': [
            {'uci': 'e2e4', 'san': 'e4', 'winrate': 53.2, 'score': 12},
          ],
        }),
        200,
      );
    }
    return mockResponse('', 404);
  });

  const options = AnalysisOptions.pgn(
    id: StringId('standalone'),
    orientation: Side.white,
    pgn: '',
    isComputerAnalysisAllowed: false,
    variant: Variant.standard,
  );

  const name = 'John';

  final user = LightUser(id: UserId.fromUserName(name), name: name);

  final authUser = AuthUser(user: user, token: 'test-token');

  group('OpeningExplorerScreen', () {
    testWidgets('master opening explorer loads', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const OpeningExplorerScreen(options: options),
        authUser: authUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );
      await tester.pumpWidget(app);

      // wait for opening explorer data to load (taking debounce delay into account)
      await tester.pump(const Duration(milliseconds: 350));

      final moves = ['e4', 'd4'];
      for (final move in moves) {
        expect(find.widgetWithText(SrsPressable, move), findsOneWidget);
      }

      // Tapping a row plays the move on the board.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OpeningExplorerScreen)),
      );
      await tester.tap(find.widgetWithText(SrsPressable, 'e4'));
      await tester.pumpAndSettle();
      expect(
        container.read(analysisControllerProvider(options)).requireValue.currentNode.position.ply,
        equals(1),
      );

      expect(find.widgetWithText(Container, 'Top games'), findsOneWidget);
      expect(find.widgetWithText(Container, 'Recent games'), findsNothing);

      // TODO: make a custom scrollUntilVisible that works with the non-scrollable
      // board widget

      // await tester.scrollUntilVisible(
      //   find.text('Firouzja, A.'),
      //   200,
      //   scrollable: explorerViewFinder,
      // );

      // expect(
      //   find.byType(OpeningExplorerGameTile),
      //   findsNWidgets(2),
      // );
    }, variant: kPlatformVariant);

    testWidgets('lichess opening explorer loads', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const OpeningExplorerScreen(options: options),
        authUser: authUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
        defaultPreferences: {
          SessionPreferencesStorage.key(
            PrefCategory.openingExplorer.storageKey,
            authUser,
          ): jsonEncode(
            OpeningExplorerPrefs.defaults().copyWith(db: OpeningDatabase.lichess).toJson(),
          ),
        },
      );
      await tester.pumpWidget(app);

      // wait for opening explorer data to load (taking debounce delay into account)
      await tester.pump(const Duration(milliseconds: 350));

      final moves = ['d4'];
      for (final move in moves) {
        expect(find.widgetWithText(SrsPressable, move), findsOneWidget);
      }

      expect(find.widgetWithText(Container, 'Top games'), findsNothing);
      expect(find.widgetWithText(Container, 'Recent games'), findsOneWidget);

      // await tester.scrollUntilVisible(
      //   find.byType(OpeningExplorerGameTile),
      //   200,
      //   scrollable: explorerViewFinder,
      // );

      // expect(
      //   find.byType(OpeningExplorerGameTile),
      //   findsOneWidget,
      // );
    }, variant: kPlatformVariant);

    testWidgets('player opening explorer loads', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const OpeningExplorerScreen(options: options),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
        authUser: authUser,
        defaultPreferences: {
          SessionPreferencesStorage.key(
            PrefCategory.openingExplorer.storageKey,
            authUser,
          ): jsonEncode(
            OpeningExplorerPrefs.defaults(user: user).copyWith(db: OpeningDatabase.player).toJson(),
          ),
        },
      );
      await tester.pumpWidget(app);

      // wait for opening explorer data to load (taking debounce delay into account)
      await tester.pump(const Duration(milliseconds: 350));

      final moves = ['c4'];
      for (final move in moves) {
        expect(find.widgetWithText(SrsPressable, move), findsOneWidget);
      }

      expect(find.widgetWithText(Container, 'Top games'), findsNothing);
      expect(find.widgetWithText(Container, 'Recent games'), findsOneWidget);

      // await tester.scrollUntilVisible(
      //   find.byType(OpeningExplorerGameTile),
      //   200,
      //   scrollable: explorerViewFinder,
      // );

      // expect(
      //   find.byType(OpeningExplorerGameTile),
      //   findsOneWidget,
      // );
    }, variant: kPlatformVariant);

    testWidgets('chessdb opening explorer loads', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const OpeningExplorerScreen(options: options),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
        authUser: authUser,
        defaultPreferences: {
          SessionPreferencesStorage.key(
            PrefCategory.openingExplorer.storageKey,
            authUser,
          ): jsonEncode(
            OpeningExplorerPrefs.defaults(
              user: user,
            ).copyWith(db: OpeningDatabase.chessdb).toJson(),
          ),
        },
      );
      await tester.pumpWidget(app);

      // wait for opening explorer data to load (taking debounce delay into account)
      await tester.pump(const Duration(milliseconds: 350));

      final moves = ['e4'];
      for (final move in moves) {
        expect(find.widgetWithText(SrsPressable, move), findsOneWidget);
      }
    }, variant: kPlatformVariant);

    // regression test for #2726
    testWidgets('opening explorer does not use standalone analysis', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoreTabScreen(),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
        authUser: authUser,
      );
      await tester.pumpWidget(app);

      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle(); // wait for analysis screen to open

      await playMove(tester, 'e2', 'e4');
      expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isTrue);

      // Go back to "more" screen and open opening explorer
      await tester.tap(
        find.descendant(of: find.byType(SrsPageHead), matching: find.text('Review')),
      );
      await tester.pump();

      await tester.tap(find.text('Opening explorer'));
      await tester.pumpAndSettle(); // wait for opening explorer screen to open

      // Should not use saved standalone analysis here
      expect(boardHasPiece(tester, Square.e2, Piece.whitePawn), isTrue);

      // There was a bug where the opening explorer would partially load saved analysis,
      // leading to not being to move any pieces.
      await playMove(tester, 'd2', 'd4');
      expect(boardHasPiece(tester, Square.d4, Piece.whitePawn), isTrue);
    });

    // Reported as an off-by-one: the explorer decrements the move list's index before handing
    // it to jumpToNthNodeOnMainline, and jumpToNthNodeOnMainline(0) looks like it should be the
    // starting position. It is not. The loop that walks a mainline path down to its start stops
    // as soon as the next step would be empty, so it lands on the *first move* — the parameter
    // is 0-based from there, not from the root. The move list hands over a 1-based move number,
    // so the decrement is the conversion the API wants, and the two ends of the line are right.
    //
    // This test exists to keep that true. The adjustment looks like a bug to anyone reading it
    // cold, and the obvious "fix" shifts every selection in the list by one move.
    testWidgets('tapping a move in the inline list selects that move', (WidgetTester tester) async {
      // A line long enough to check both ends: the first move and the last.
      const pgn = '1. e4 e5 2. Nf3 Nc6';
      const moveOptions = AnalysisOptions.pgn(
        id: StringId('inline-moves'),
        orientation: Side.white,
        pgn: pgn,
        isComputerAnalysisAllowed: false,
        variant: Variant.standard,
      );

      final app = await makeTestProviderScopeApp(
        tester,
        home: const OpeningExplorerScreen(options: moveOptions),
        authUser: authUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );
      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 350));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OpeningExplorerScreen)),
      );
      int ply() => container
          .read(analysisControllerProvider(moveOptions))
          .requireValue
          .currentNode
          .position
          .ply;

      // The first move of the line: one node past the starting position.
      await tester.tap(find.widgetWithText(InlineMoveItem, 'e4'));
      await tester.pumpAndSettle();
      expect(ply(), equals(1), reason: 'the first move of the line is one node past the root');

      await tester.tap(find.widgetWithText(InlineMoveItem, 'Nc6'));
      await tester.pumpAndSettle();
      expect(ply(), equals(4), reason: 'the last move of 1.e4 e5 2.Nf3 Nc6 is the fourth node');
    }, variant: kPlatformVariant);
  });
}

const mastersOpeningExplorerResponse = '''
{
  "white": 834333,
  "draws": 1085272,
  "black": 600303,
  "moves": [
    {
      "uci": "e2e4",
      "san": "e4",
      "averageRating": 2399,
      "white": 372266,
      "draws": 486092,
      "black": 280238,
      "game": null
    },
    {
      "uci": "d2d4",
      "san": "d4",
      "averageRating": 2414,
      "white": 302160,
      "draws": 397224,
      "black": 209077,
      "game": null
    }
  ],
  "topGames": [
    {
      "uci": "d2d4",
      "id": "QR5UbqUY",
      "winner": null,
      "black": {
        "name": "Caruana, F.",
        "rating": 2818
      },
      "white": {
        "name": "Carlsen, M.",
        "rating": 2882
      },
      "year": 2019,
      "month": "2019-08"
    },
    {
      "uci": "e2e4",
      "id": "Sxov6E94",
      "winner": "white",
      "black": {
        "name": "Carlsen, M.",
        "rating": 2882
      },
      "white": {
        "name": "Firouzja, A.",
        "rating": 2808
      },
      "year": 2019,
      "month": "2019-08"
    }
  ],
  "opening": null
}
''';

const lichessOpeningExplorerResponse = '''
{
  "white": 2848672002,
  "draws": 225287646,
  "black": 2649860106,
  "moves": [
    {
      "uci": "d2d4",
      "san": "d4",
      "averageRating": 1604,
      "white": 1661457614,
      "draws": 129433754,
      "black": 1565161663,
      "game": null
    }
  ],
  "recentGames": [
    {
      "uci": "e2e4",
      "id": "RVb19S9O",
      "winner": "white",
      "speed": "rapid",
      "mode": "rated",
      "black": {
        "name": "Jcats1",
        "rating": 1548
      },
      "white": {
        "name": "carlosrivero32",
        "rating": 1690
      },
      "year": 2024,
      "month": "2024-06"
    }
  ],
  "topGames": [],
  "opening": null
}
''';

const playerOpeningExplorerResponse = '''
{
  "white": 1713,
  "draws": 119,
  "black": 1459,
  "moves": [
    {
      "uci": "c2c4",
      "san": "c4",
      "averageOpponentRating": 1767,
      "performance": 1796,
      "white": 1691,
      "draws": 116,
      "black": 1432,
      "game": null
    }
  ],
  "recentGames": [
    {
      "uci": "e2e4",
      "id": "RVb19S9O",
      "winner": "white",
      "speed": "bullet",
      "mode": "rated",
      "black": {
        "name": "foo",
        "rating": 1869
      },
      "white": {
        "name": "baz",
        "rating": 1912
      },
      "year": 2023,
      "month": "2023-08"
    }
  ],
  "opening": null,
  "queuePosition": 0
}
''';
