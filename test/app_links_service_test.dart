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
import 'package:chess_srs/src/tab_navigation.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/study/study_screen.dart';
import 'package:chess_srs/src/view/user/user_screen.dart';
import 'package:chess_srs/src/widgets/rich_link_text.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import 'example_data.dart';
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

/// A single-shot stream that delivers its event inside `listen()` itself, the
/// way the platform delivers the cold-start link before the first frame has
/// been built. (A `StreamController(sync: true)` cannot do this: an `add()`
/// from `onListen` lands on a microtask, after the first frame.)
class _ImmediateStream extends Stream<Uri> {
  _ImmediateStream(this.uri);

  final Uri uri;

  @override
  StreamSubscription<Uri> listen(
    void Function(Uri)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (onData != null) onData(uri);
    return const _DoneSubscription();
  }
}

class _DoneSubscription implements StreamSubscription<Uri> {
  const _DoneSubscription();

  @override
  Future<void> cancel() async {}

  @override
  void onData(void Function(Uri)? handleData) {}

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  bool get isPaused => false;

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  Future<E> asFuture<E>([E? futureValue]) => Future.value(futureValue);
}

/// Records pushed and replaced routes so a test can assert on their
/// [Route.transitionDuration], which is how the service's `animated` flag is
/// observable.
class _RecordingNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> replaced = [];

  /// The route's transition duration — how the service's `animated` flag is
  /// observable on the route it pushes.
  static Duration transitionOf(Route<dynamic> route) =>
      (route as TransitionRoute<dynamic>).transitionDuration;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) replaced.add(newRoute);
  }
}

/// Mocks the url_launcher platform channel, recording every url the app asks
/// the platform to launch. `launch` answers true so [launchUrl] returns
/// normally instead of throwing a missing-plugin error.
List<String> mockUrlLauncher(WidgetTester tester) {
  final launched = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    final args = call.arguments;
    if (call.method == 'launch' && args is Map<Object?, Object?>) {
      final url = args['url'];
      if (url is String) launched.add(url);
    }
    return true;
  });
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  return launched;
}

/// Pumps an app whose deep-link stream is a live controller, so a test can
/// emit links on demand and observe navigation through [observer]. The first
/// emitted link is the stream's first event, i.e. the cold-start link; links
/// emitted afterwards arrive while the app is "running".
Future<(StreamController<Uri>, _RecordingNavigatorObserver)> pumpDeepLinkApp(
  WidgetTester tester, {
  Map<ProviderOrFamily, Override>? overrides,
}) async {
  final links = StreamController<Uri>.broadcast();
  final observer = _RecordingNavigatorObserver();
  final navigatorKey = GlobalKey<NavigatorState>();
  final mockAppLinks = MockAppLinks();
  when(() => mockAppLinks.uriLinkStream).thenAnswer((_) => links.stream);
  when(() => mockAppLinks.getInitialLink()).thenAnswer((_) async => null);

  final app = await makeTestProviderScope(
    tester,
    overrides: {
      currentNavigatorKeyProvider: currentNavigatorKeyProvider.overrideWithValue(navigatorKey),
      appLinksServiceProvider: appLinksServiceProvider.overrideWith((ref) {
        final service = AppLinksService(ref, appLinks: mockAppLinks);
        ref.onDispose(service.dispose);
        return service;
      }),
      ...?overrides,
    },
    // SrsTheme and the l10n delegates because this harness builds its own tree
    // instead of makeTestProviderScopeApp: the deep-linked screens (BoardEditor
    // in particular) resolve their colours and strings through them.
    child: SrsTheme(
      colors: SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const _ColdStartLauncher(),
      ),
    ),
  );
  await tester.pumpWidget(app);
  return (links, observer);
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
      // The head uses a custom chevron rather than a platform back button, so pageBack()
      // (which looks for BackButton/CupertinoNavigationBarBackButton) cannot see it.
      await tester.tap(find.bySemanticsLabel('Back to Review'));
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

    testWidgets('unsupported /tv/<channel> link does not navigate and resolves to null', (
      WidgetTester tester,
    ) async {
      // The Watch tab (TV/broadcasts) was cut in C7, so TV links have no in-app route. The
      // test previously had zero assertions and simulated a socket for a screen that never
      // opened; this asserts the link resolves to null and leaves the screen unchanged.
      final uri = Uri.parse('https://lichess.org/tv/blitz');
      await triggerAppLink(tester, uri);
      await tester.pumpAndSettle();

      final context = tester.element(find.text('test link'));
      final service = ProviderScope.containerOf(context).read(appLinksServiceProvider);
      expect(await service.resolveAppLinkUri(context, uri), isNull);
      expect(find.text('test link'), findsOneWidget, reason: 'cut TV route must not navigate');
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

    testWidgets(
      'a first-party url with no in-app route falls back to the browser from linkified text',
      (tester) async {
        // Linkified text is user content, not an app link, so unlike the app-link
        // stream the fallback IS allowed: a first-party url the app cannot resolve
        // in-app (the cut TV route) opens in the browser. INV-008: the url is
        // first-party, so the app handles its navigation.
        final launched = mockUrlLauncher(tester);
        await triggerLinkifyOpen(tester, 'https://$kLichessHost/tv/blitz');
        await tester.pumpAndSettle();

        expect(launched, ['https://$kLichessHost/tv/blitz']);
      },
    );

    testWidgets('navigation from linkified text uses the normal animated transition', (
      tester,
    ) async {
      final observer = _RecordingNavigatorObserver();
      final app = await makeTestProviderScope(
        tester,
        child: SrsTheme(
          colors: SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent),
          child: MaterialApp(
            navigatorObservers: [observer],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: const Scaffold(body: _LinkifyTestWidget(url: 'https://lichess.org/editor')),
          ),
        ),
      );
      await tester.pumpWidget(app);
      await tester.tap(find.text('test linkify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(_RecordingNavigatorObserver.transitionOf(observer.pushed.last), isNot(Duration.zero));
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

    testWidgets(
      'a cold-start link arriving before the first frame is deferred until the navigator exists',
      (tester) async {
        // The cold-start link can arrive before the first frame (the code comment's
        // exact scenario). A synchronous controller is not enough for that — a
        // sync controller's onListen-add lands on a microtask, after the first
        // frame — so this stream delivers inside listen() itself, while the
        // navigator key still has no context. Handling the link immediately
        // would read that null context and silently drop the link; the deferral
        // must hold it until the post-frame callback, when the navigator exists.
        final mockAppLinks = MockAppLinks();
        when(
          () => mockAppLinks.uriLinkStream,
        ).thenAnswer((_) => _ImmediateStream(Uri.parse('https://lichess.org/editor')));
        final navigatorKey = GlobalKey<NavigatorState>();

        final app = await makeTestProviderScope(
          tester,
          overrides: {
            currentNavigatorKeyProvider: currentNavigatorKeyProvider.overrideWithValue(
              navigatorKey,
            ),
            appLinksServiceProvider: appLinksServiceProvider.overrideWith((ref) {
              final service = AppLinksService(ref, appLinks: mockAppLinks);
              ref.onDispose(service.dispose);
              return service;
            }),
          },
          child: SrsTheme(
            colors: SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent),
            child: MaterialApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: const _ColdStartLauncher(),
            ),
          ),
        );
        // One pump builds the first frame (the link already arrived during
        // initState); the second builds the route the post-frame callback pushed.
        await tester.pumpWidget(app);
        await tester.pump();

        expect(find.byType(BoardEditorScreen), findsOneWidget);
      },
    );

    testWidgets('a cold-start link pushes without a transition, a link while running is animated', (
      tester,
    ) async {
      final (links, observer) = await pumpDeepLinkApp(tester);

      // First stream event: the cold-start link. Pushed without a transition —
      // the user launched the app via this link so the screen should just be there.
      links.add(Uri.parse('https://lichess.org/editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BoardEditorScreen), findsOneWidget);
      expect(_RecordingNavigatorObserver.transitionOf(observer.pushed.last), Duration.zero);

      // Second event: the app is running now, so the link gets a normal
      // transition. Same screen type, so the push replaces the existing route.
      links.add(Uri.parse('https://lichess.org/editor?color=black'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(observer.replaced, isNotEmpty);
      expect(
        _RecordingNavigatorObserver.transitionOf(observer.replaced.last),
        isNot(Duration.zero),
      );
    });

    testWidgets('an open-web link opens the encoded web url and refuses a non-web url', (
      tester,
    ) async {
      // org.chesssrs.app://open-web?url=... comes from the platform widget and must
      // open exactly the encoded url in the in-app browser. Only web urls: launchUrl
      // hands any scheme to the platform, so a `tel:` url must be refused here.
      final launched = mockUrlLauncher(tester);
      final (links, _) = await pumpDeepLinkApp(tester);

      links.add(
        Uri.parse(
          'org.chesssrs.app://open-web?url=${Uri.encodeComponent('https://lichess.org/faq')}',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(launched, ['https://lichess.org/faq']);

      links.add(
        Uri.parse('org.chesssrs.app://open-web?url=${Uri.encodeComponent('tel:+15550123')}'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(launched, ['https://lichess.org/faq'], reason: 'a non-web url must not be launched');
    });

    testWidgets('a custom-scheme link whose host is not open-web or shared-pgn still navigates', (
      tester,
    ) async {
      // The custom-scheme guards must match the host exactly: a custom-scheme link
      // with any other host (here a platform widget naming a fake host) falls
      // through to normal route resolution.
      final (links, _) = await pumpDeepLinkApp(tester);

      links.add(Uri.parse('org.chesssrs.app://widget/editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BoardEditorScreen), findsOneWidget);
    });

    testWidgets('a shared-pgn custom-scheme link is skipped before any resolution', (tester) async {
      // Shared PGN links are handled natively by SharePlugin; the service must not
      // resolve their path at all. The path names a real route so that any
      // fall-through would be observable as navigation.
      final (links, _) = await pumpDeepLinkApp(tester);

      links.add(Uri.parse('org.chesssrs.app://shared-pgn/editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BoardEditorScreen), findsNothing);
    });

    testWidgets('a file link is skipped rather than resolved as a route', (tester) async {
      // File links belong to the sharing-intent logic. The path names a real route
      // so a removed guard would navigate instead of being silently inert.
      final launched = mockUrlLauncher(tester);
      final (links, _) = await pumpDeepLinkApp(tester);

      links.add(Uri.parse('file:///editor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('an app link that resolves to nothing never falls back to the browser', (
      tester,
    ) async {
      // App links must not fall back to the browser: re-launching the browser with
      // the link can loop between browser and app. An unresolvable link (the cut TV
      // route) must do nothing at all.
      final launched = mockUrlLauncher(tester);
      final (links, _) = await pumpDeepLinkApp(tester);

      links.add(Uri.parse('https://lichess.org/tv/blitz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(BoardEditorScreen), findsNothing);
      expect(launched, isEmpty);
    });
  });
}
