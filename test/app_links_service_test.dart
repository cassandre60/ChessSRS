// SPEC coverage: INV-008.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app_links_service.dart';
import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_repository.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/tab_navigation.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/study/study_screen.dart';
import 'package:chess_srs/src/view/user/user_screen.dart';
import 'package:chess_srs/src/widgets/rich_link_text.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'example_data.dart';
import 'model/game/game_socket_example_data.dart';
import 'network/fake_http_client_factory.dart';
import 'network/fake_websocket_channel.dart';
import 'test_provider_scope.dart';

class MockAppLinks extends Mock implements AppLinks {}

class MockGameRepository extends Mock implements GameRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class _TestWidget extends ConsumerWidget {
  const _TestWidget({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () async {
        await ref.read(appLinksServiceProvider).start();
        await ref.read(appLinksServiceProvider).handleAppLink(context, uri);
      },
      child: const Text('test link'),
    );
  }
}

/// Starts the [AppLinksService] when mounted, as the real app does at launch.
class _ColdStartLauncher extends ConsumerStatefulWidget {
  const _ColdStartLauncher();

  @override
  ConsumerState<_ColdStartLauncher> createState() => _ColdStartLauncherState();
}

class _ColdStartLauncherState extends ConsumerState<_ColdStartLauncher> {
  @override
  void initState() {
    super.initState();
    ref.read(appLinksServiceProvider).start();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

Future<void> triggerAppLink(
  WidgetTester tester,
  Uri appLinkUri, {
  Map<ProviderOrFamily, Override>? overrides,
}) async {
  final app = await makeTestProviderScopeApp(
    tester,
    overrides: overrides,
    home: Scaffold(body: _TestWidget(uri: appLinkUri)),
  );
  await tester.pumpWidget(app);
  await tester.tap(find.text('test link'));
}

class _LinkifyTestWidget extends ConsumerWidget {
  const _LinkifyTestWidget({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () async {
        await ref.read(appLinksServiceProvider).onLinkifyOpen(context, UrlElement(url));
      },
      child: const Text('test linkify'),
    );
  }
}

Future<void> triggerLinkifyOpen(WidgetTester tester, String url) async {
  final app = await makeTestProviderScopeApp(
    tester,
    home: Scaffold(body: _LinkifyTestWidget(url: url)),
  );
  await tester.pumpWidget(app);
  await tester.tap(find.text('test linkify'));
}

void main() {
  group('resolveAppLinkUri', () {
    testWidgets('Nothing happens for an empty path', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle(); // Wait for any navigation to complete
      expect(find.text('test link'), findsOneWidget); // Still on the same screen
    });

    testWidgets('a /study link with no id resolves to nothing rather than throwing', (
      WidgetTester tester,
    ) async {
      // Reading the id unconditionally raised a RangeError. The link handler logged and dropped
      // it, so a truncated link did nothing at all with nothing shown — indistinguishable from a
      // link that had simply not loaded. Asserted against the resolver directly, because going
      // through the handler hides the throw and the test would pass either way.
      final uri = Uri.parse('https://lichess.org/study');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();

      final context = tester.element(find.text('test link'));
      final service = ProviderScope.containerOf(context).read(appLinksServiceProvider);
      expect(await service.resolveAppLinkUri(context, uri), isNull);
      expect(find.text('test link'), findsOneWidget, reason: 'still on the same screen');
    });

    testWidgets('a /@ link with no user name resolves to nothing rather than throwing', (
      WidgetTester tester,
    ) async {
      final uri = Uri.parse('https://lichess.org/@');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();

      final context = tester.element(find.text('test link'));
      final service = ProviderScope.containerOf(context).read(appLinksServiceProvider);
      expect(await service.resolveAppLinkUri(context, uri), isNull);
      expect(find.text('test link'), findsOneWidget, reason: 'still on the same screen');
    });

    testWidgets('resolves /study/{id} to StudyScreen route', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/study/p9uY0321');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle(); // Wait study screen to load
      expect(
        tester.widget(find.byType(StudyScreen)),
        isA<StudyScreen>()
            .having((s) => s.options.id, 'id', 'p9uY0321')
            .having((s) => s.options.initialChapter, 'initialChapter', isNull),
      );
    });

    testWidgets('resolves /study/{id}/{chapter} to StudyScreen route with initial chapter', (
      WidgetTester tester,
    ) async {
      final uri = Uri.parse('https://lichess.org/study/p9uY0321/abcd1234');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle(); // Wait study screen to load
      expect(
        tester.widget(find.byType(StudyScreen)),
        isA<StudyScreen>()
            .having((s) => s.options.id, 'id', 'p9uY0321')
            .having((s) => s.options.initialChapter, 'initialChapter', 'abcd1234'),
      );
    });

    testWidgets('resolves bare /editor to BoardEditorScreen with default position', (
      WidgetTester tester,
    ) async {
      final uri = Uri.parse('https://lichess.org/editor');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();
      expect(
        tester.widget(find.byType(BoardEditorScreen)),
        isA<BoardEditorScreen>()
            .having((s) => s.params?.initialFen, 'initialFen', isNull)
            .having((s) => s.params?.initialOrientation, 'orientation', Side.white),
      );
    });

    testWidgets('resolves trailing-slash /editor/ to BoardEditorScreen with default position', (
      WidgetTester tester,
    ) async {
      // /editor/ parses to an empty trailing path segment, so the reconstructed FEN is
      // empty: it must fall back to the default position rather than fail validation.
      final uri = Uri.parse('https://lichess.org/editor/?color=black');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid FEN'), findsNothing);
      expect(
        tester.widget(find.byType(BoardEditorScreen)),
        isA<BoardEditorScreen>()
            .having((s) => s.params?.initialFen, 'initialFen', isNull)
            .having((s) => s.params?.initialOrientation, 'orientation', Side.black),
      );
    });

    testWidgets('resolves /editor/{fen} reconstructing the FEN from path segments', (
      WidgetTester tester,
    ) async {
      // Ranks are split by '/' and metadata spaces are encoded as '_'.
      final uri = Uri.parse(
        'https://lichess.org/editor/rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR_w_KQkq_-_0_1',
      );
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();
      expect(
        tester.widget(find.byType(BoardEditorScreen)),
        isA<BoardEditorScreen>()
            .having(
              (s) => s.params?.initialFen,
              'initialFen',
              'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1',
            )
            .having((s) => s.params?.initialOrientation, 'orientation', Side.white),
      );
    });

    testWidgets('resolves /editor/{fen}?color=black with black orientation', (
      WidgetTester tester,
    ) async {
      final uri = Uri.parse(
        'https://lichess.org/editor/rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR_w_KQkq_-_0_1?color=black',
      );
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();
      expect(
        tester.widget(find.byType(BoardEditorScreen)),
        isA<BoardEditorScreen>().having(
          (s) => s.params?.initialOrientation,
          'orientation',
          Side.black,
        ),
      );
    });

    testWidgets(
      'shows error snackbar but still opens editor with default position for invalid FEN',
      (WidgetTester tester) async {
        final uri = Uri.parse('https://lichess.org/editor/not-a-valid-fen');
        await triggerAppLink(tester, uri);
        await tester.pumpAndSettle();
        expect(find.textContaining('Invalid FEN'), findsOneWidget);
        expect(
          tester.widget(find.byType(BoardEditorScreen)),
          isA<BoardEditorScreen>().having((s) => s.params?.initialFen, 'initialFen', isNull),
        );
      },
    );

    final finishedGame = generateExportedGames(count: 1).first.copyWith(status: GameStatus.draw);

    testWidgets('resolves /gameid link for finished game', (WidgetTester tester) async {
      // lichess.org/gameid -> Opens analysis at the first move
      final uri = Uri.parse('https://lichess.org/${finishedGame.id.value}');
      final mockGameRepository = MockGameRepository();
      when(() => mockGameRepository.getGame(finishedGame.id)).thenAnswer((_) async => finishedGame);

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          gameRepositoryProvider: gameRepositoryProvider.overrideWith((_) => mockGameRepository),
        },
      );
      await tester.pumpAndSettle(); // Wait analysis screen to load

      expect(
        tester.widget(find.byType(AnalysisScreen)),
        isA<AnalysisScreen>()
            .having((s) => s.options.gameId, 'id', finishedGame.id.value)
            .having((s) => s.options.initialMoveCursor, 'move number', 0),
      );
    });

    testWidgets('resolves /gameid link for finished game with ply fragment', (
      WidgetTester tester,
    ) async {
      // lichess.org/gameid#20 -> Opens analysis at move 20
      final uri = Uri.parse('https://lichess.org/${finishedGame.id.value}#20');
      final mockGameRepository = MockGameRepository();
      when(() => mockGameRepository.getGame(finishedGame.id)).thenAnswer((_) async => finishedGame);

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          gameRepositoryProvider: gameRepositoryProvider.overrideWith((_) => mockGameRepository),
        },
      );
      await tester.pumpAndSettle(); // Wait for analysis screen to load

      expect(
        tester.widget(find.byType(AnalysisScreen)),
        isA<AnalysisScreen>()
            .having((s) => s.options.gameId, 'id', finishedGame.id.value)
            .having((s) => s.options.initialMoveCursor, 'move number', 20),
      );
    });

    testWidgets('resolves /gameid/black finished game link', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/${finishedGame.id.value}/black');
      final mockGameRepository = MockGameRepository();
      when(() => mockGameRepository.getGame(finishedGame.id)).thenAnswer((_) async => finishedGame);

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          gameRepositoryProvider: gameRepositoryProvider.overrideWith((_) => mockGameRepository),
        },
      );
      await tester.pumpAndSettle(); // Wait for analysis screen to load

      expect(
        tester.widget(find.byType(AnalysisScreen)),
        isA<AnalysisScreen>()
            .having((s) => s.options.gameId, 'id', finishedGame.id.value)
            .having((s) => s.options.orientation, 'player color', Side.black),
      );
    });

    testWidgets('resolves /gameid link for imported game to analysis', (WidgetTester tester) async {
      final mockGameRepository = MockGameRepository();
      final importedGame = generateExportedGames(count: 1).first.copyWith(
        status: GameStatus.started,
        source: GameSource.import,
        black: const Player(),
        white: const Player(),
      );
      when(() => mockGameRepository.getGame(importedGame.id)).thenAnswer((_) async => importedGame);

      final uri = Uri.parse('https://lichess.org/${importedGame.id.value}');

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          gameRepositoryProvider: gameRepositoryProvider.overrideWith((_) => mockGameRepository),
        },
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget(find.byType(AnalysisScreen)),
        isA<AnalysisScreen>().having((s) => s.options.gameId, 'id', importedGame.id.value),
      );
    });

    testWidgets('replaces existing screen instead of stacking a duplicate', (tester) async {
      AppLinksService? capturedService;
      BuildContext? capturedContext;

      final uri = Uri.parse('https://lichess.org/study/p9uY0321');

      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, ref, _) {
            capturedService = ref.read(appLinksServiceProvider);
            capturedContext = context;
            return ElevatedButton(
              onPressed: () async {
                await ref.read(appLinksServiceProvider).handleAppLink(context, uri);
              },
              child: const Text('go to study'),
            );
          },
        ),
      );
      await tester.pumpWidget(app);

      // First tap: pushes StudyScreen.
      await tester.tap(find.text('go to study'));
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsOneWidget);

      // Second call from the home context (still mounted below StudyScreen):
      // should replace rather than push. Fire-and-forget: the push future only
      // resolves when the route is popped, so we drive it via pumpAndSettle.
      unawaited(capturedService!.handleAppLink(capturedContext!, uri));
      await tester.pumpAndSettle();

      // Pressing back must return to the home widget — no extra StudyScreen in the stack.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('go to study'), findsOneWidget);
      expect(find.byType(StudyScreen), findsNothing);
    });

    testWidgets('resolves /@/user link', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/@/thibault');
      final mockUserRepository = MockUserRepository();
      when(() => mockUserRepository.getUser(const UserId('thibault'))).thenAnswer(
        (_) async => const User(id: UserId('thibault'), username: 'Thibault', perfs: IMap.empty()),
      );

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          userRepositoryProvider: userRepositoryProvider.overrideWith((_) => mockUserRepository),
        },
      );
      await tester.pumpAndSettle(); // Wait for user screen to load

      expect(
        tester.widget(find.byType(UserScreen)),
        isA<UserScreen>().having((s) => s.user.id, 'user id', const UserId('thibault')),
      );
    });

    testWidgets('Shows error snackbar for invalid user', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/@/hikaru');
      final mockUserRepository = MockUserRepository();
      when(
        () => mockUserRepository.getUser(const UserId('hikaru')),
      ).thenThrow(Exception('User not found'));

      await triggerAppLink(
        tester,
        uri,
        overrides: {
          userRepositoryProvider: userRepositoryProvider.overrideWith((_) => mockUserRepository),
        },
      );
      await tester.pumpAndSettle(); // Wait for snackbar to show

      expect(find.byType(UserScreen), findsNothing);

      expect(find.text('Cannot find user hikaru'), findsOneWidget);
    });

    testWidgets('Shows tv screen for /tv/<channel> link', (WidgetTester tester) async {
      final uri = Uri.parse('https://lichess.org/tv/blitz');
      await triggerAppLink(
        tester,
        uri,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(
              () => MockClient((request) async {
                if (request.url.path == '/api/tv/channels') {
                  const body = '''
                  {
                    "blitz": {"color": "white", "gameId": "v3pIFdTz", "rating": 2615, "user": {"id": "whitePlayer", "name": "whitePlayer"}}
                  }''';
                  return http.Response(body, 200, headers: {'content-type': 'application/json'});
                }
                return http.Response('', 404);
              }),
            );
          }),
        },
      );

      // First frame resolves the channel and mounts the game controller, which
      // opens the game socket; the lag pump lets it connect before the server
      // sends the full event.
      await tester.pump();
      await tester.pump(kFakeWebSocketConnectionLag);
      sendServerSocketMessages(Uri(path: '/watch/v3pIFdTz/white/v6'), [
        makeFullEvent(
          const GameId('gameid11'),
          '',
          whiteUserName: 'whitePlayer',
          blackUserName: 'blackPlayer',
        ),
      ]);
      await tester.pump(); // Process socket message

      await tester.pumpAndSettle(); // Wait for TV screen to load
    });
  });

  group('onLinkifyOpen', () {
    testWidgets('routes a first-party url to the in-app screen', (WidgetTester tester) async {
      await triggerLinkifyOpen(tester, 'https://$kLichessHost/editor');
      await tester.pumpAndSettle();

      expect(find.byType(BoardEditorScreen), findsOneWidget);
    });

    testWidgets('does not treat a host prefixed with the lichess host as first-party', (
      WidgetTester tester,
    ) async {
      await triggerLinkifyOpen(tester, 'https://$kLichessHost.evil.com/editor');
      await tester.pumpAndSettle();

      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not treat userinfo disguising an attacker host as first-party', (
      WidgetTester tester,
    ) async {
      await triggerLinkifyOpen(tester, 'https://$kLichessHost@evil.com/editor');
      await tester.pumpAndSettle();

      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('start (deep link subscription)', () {
    testWidgets('a cold-start link is handled exactly once', (tester) async {
      // An invalid-FEN editor link shows a toast. Toasts replace rather than queue, so a
      // double-handled link cannot leave two on screen: the guarantee to assert is that
      // exactly one appears and it goes away on the design's 2.4 s dwell.
      final coldStartUri = Uri.parse('https://lichess.org/editor/not-a-valid-fen');
      final navigatorKey = GlobalKey<NavigatorState>();

      final mockAppLinks = MockAppLinks();
      // The stream emits the cold-start link as its first (and only) event.
      when(() => mockAppLinks.uriLinkStream).thenAnswer((_) => Stream.value(coldStartUri));
      // getInitialLink() also returns it, so handling it too would duplicate.
      when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => coldStartUri);

      final app = await makeTestProviderScope(
        tester,
        overrides: {
          currentNavigatorKeyProvider: currentNavigatorKeyProvider.overrideWithValue(navigatorKey),
          appLinksServiceProvider: appLinksServiceProvider.overrideWith((ref) {
            final service = AppLinksService(ref, appLinks: mockAppLinks);
            ref.onDispose(service.dispose);
            return service;
          }),
        },
        // SrsTheme, because this test builds its own tree instead of going through
        // makeTestProviderScopeApp, which is the helper that supplies it. The deep link navigates
        // to BoardEditorScreen, which resolves its colours through SrsContext and asserts the
        // theme is there. Without the wrapper the build throws, navigation swallows it, and the
        // failure surfaces two assertions later as a missing "Invalid FEN" snackbar.
        //
        // The fourth restyle branch to need this, after #23, #29 and #30. It cannot go on main,
        // where BoardEditorScreen does not require a theme.
        child: SrsTheme(
          colors: SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const _ColdStartLauncher(),
          ),
        ),
      );
      await tester.pumpWidget(app);
      // Bounded pumps, not pumpAndSettle: the toast's dwell is 2.4 s by design where a
      // SnackBar defaulted to 4 s, so settling to quiescence runs past its lifetime and the
      // assertion below would be looking for something already gone.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(find.textContaining('Invalid FEN'), findsOneWidget);
      verifyNever(() => mockAppLinks.getInitialLink());

      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.textContaining('Invalid FEN'), findsNothing);
    });
  });
}
