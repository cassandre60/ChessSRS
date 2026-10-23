import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app.dart';
import 'package:chess_srs/src/app_links_service.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/account/account_service.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/log/app_log_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/quick_actions.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/shared_pgn_service.dart';
import 'package:chess_srs/src/tab_navigation.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'test_helpers.dart';
import 'test_provider_scope.dart';

/// A stand-in for the platform binding that owns the native splash.
///
/// The real one is a [WidgetsBinding], and [FlutterNativeSplash.preserve] and
/// [FlutterNativeSplash.remove] only ever call `deferFirstFrame` and
/// `allowFirstFrame` on it. Counting those calls is the only way to observe
/// that the native splash was actually dismissed.
class _FakeSplashBinding extends Fake implements WidgetsBinding {
  int allowFirstFrameCalls = 0;

  @override
  void allowFirstFrame() => allowFirstFrameCalls++;

  @override
  void deferFirstFrame() {}
}

/// The preload the app waits for before it boots.
///
/// The shared scope resolves the preload in a microtask, which is too fast:
/// the app root would already see the loaded data on its first build, and the
/// splash would never be observed in the state it is in on a device, where
/// the preload takes real time.
PreloadedData _preloadedData() => (
  sri: 'test-sri',
  packageInfo: PackageInfo(
    appName: 'chess_srs_test',
    version: '0.0.0',
    buildNumber: '0',
    packageName: 'chess_srs_test',
  ),
  deviceInfo: BaseDeviceInfo(const {
    'name': 'test',
    'model': 'test',
    'manufacturer': 'test',
    'systemName': 'test',
    'systemVersion': 'test',
    'identifierForVendor': 'test',
    'isPhysicalDevice': true,
  }),
  authUser: null,
  engineMaxMemoryInMb: 256,
  appDocumentsDirectory: null,
  appSupportDirectory: null,
);

/// Mounts [child] in the shared test scope and returns the container its providers live in.
///
/// The app root starts asynchronous work in `initState` (the screen-size
/// initialisation, the startup session check) and rebuilds when the preload
/// resolves, so the tree is pumped twice: once to mount it and once to let
/// that work land before anything is asserted.
///
/// The [key] gives the scope its own container. A scope that is rebuilt with
/// the same key keeps the providers it already built, so a test that mounts
/// the app more than once with different preferences has to change the key.
Future<ProviderContainer> mountApp(
  WidgetTester tester, {
  Widget child = const Application(),
  Type childType = Application,
  Key? key,
  Map<String, Object>? defaultPreferences,
  Map<ProviderOrFamily, Override>? overrides,
  Size surfaceSize = kTestSurfaceSize,
}) async {
  final app = await makeTestProviderScope(
    tester,
    child: child,
    key: key,
    defaultPreferences: defaultPreferences,
    overrides: overrides,
    surfaceSize: surfaceSize,
  );
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return ProviderScope.containerOf(tester.element(find.byType(childType)));
}

/// The general preferences as the storage layer sees them.
Map<String, Object> _generalPrefs(GeneralPrefs prefs) => {
  PrefCategory.general.storageKey: jsonEncode(prefs.toJson()),
};

void main() {
  testWidgets('App loads', (tester) async {
    final app = await makeTestProviderScope(tester, child: const Application());

    await tester.pumpWidget(app);

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ReviewScreen), findsOneWidget);
  }, variant: kPlatformVariant);

  testWidgets('App loads with system theme, which defaults to light', (tester) async {
    final app = await makeTestProviderScope(tester, child: const Application());

    await tester.pumpWidget(app);

    expect(Theme.of(tester.element(find.byType(MaterialApp))).brightness, Brightness.light);
    // The assertion above reads the theme *above* the MaterialApp, which in this
    // scope is Flutter's fallback theme: light whatever the app builds. The
    // theme the app actually installs is the one below the MaterialApp.
    expect(Theme.of(tester.element(find.byType(ReviewScreen))).brightness, Brightness.light);
  }, variant: kPlatformVariant);

  testWidgets(
    'Updating sound preference does not rebuild root Application or MaterialApp',
    variant: kPlatformVariant,
    (tester) async {
      final app = await makeTestProviderScope(tester, child: const Application());
      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 100));

      final materialAppBefore = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final element = tester.element(find.byType(Application));
      final container = ProviderScope.containerOf(element);

      // Toggle sound preference (which shouldn't touch theme or locale)
      await container.read(generalPreferencesProvider.notifier).toggleSoundEnabled();
      await tester.pump();

      final materialAppAfter = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(identical(materialAppBefore, materialAppAfter), isTrue);
    },
  );

  testWidgets(
    'Root screen has no bottom navigation and mounts ReviewScreen',
    variant: kPlatformVariant,
    (tester) async {
      final app = await makeTestProviderScope(tester, child: const Application());

      await tester.pumpWidget(app);

      expect(find.byType(ReviewScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
    },
  );

  testWidgets('language support', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      final app = await makeTestProviderScope(
        tester,
        child: const Application(),
        defaultPreferences: {
          PrefCategory.general.storageKey: jsonEncode(
            GeneralPrefs.defaults.copyWith(locale: locale).toJson(),
          ),
        },
        key: ValueKey('locale_$locale'),
      );

      await tester.pumpWidget(app);

      expect(find.byType(MaterialApp), findsOneWidget, reason: 'app loads with locale: $locale');

      // TODO find the reason why home does not load with eo
      // expect(find.byType(HomeTabScreen), findsOneWidget, reason: 'Home loads with locale: $locale');
    }
  }, variant: kPlatformVariant);

  // ---------------------------------------------------------------------
  // Startup: the initialization screen, the native splash, the prewarm.
  //
  // No SPEC invariant names the app root's startup behaviour, so the
  // contracts pinned below are the ones the code states in its own comments
  // and in the modules it wires up (`tab_navigation.dart` documents the
  // observer registration, `preloaded_data.dart` documents the startup token
  // check). They are cited here as such rather than under a loose INV id.
  // ---------------------------------------------------------------------
  group('startup', () {
    testWidgets('the app boots once the preload has resolved', (tester) async {
      final preload = Completer<PreloadedData>();

      await mountApp(
        tester,
        child: const AppInitializationScreen(),
        childType: AppInitializationScreen,
        overrides: {
          preloadedDataProvider: preloadedDataProvider.overrideWith((ref) => preload.future),
        },
      );

      // The splash is still up: the app has not booted yet.
      expect(find.byType(Application), findsNothing);

      preload.complete(_preloadedData());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Application), findsOneWidget);
      expect(find.byType(ReviewScreen), findsOneWidget);
    });

    testWidgets('the native splash is removed once the preload has resolved', (tester) async {
      final splash = _FakeSplashBinding();
      FlutterNativeSplash.preserve(widgetsBinding: splash);
      addTearDown(FlutterNativeSplash.remove);
      final preload = Completer<PreloadedData>();

      await mountApp(
        tester,
        child: const AppInitializationScreen(),
        childType: AppInitializationScreen,
        overrides: {
          preloadedDataProvider: preloadedDataProvider.overrideWith((ref) => preload.future),
        },
      );

      // The splash is still up while the app is loading.
      expect(splash.allowFirstFrameCalls, 0);

      preload.complete(_preloadedData());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(splash.allowFirstFrameCalls, 1);
    });

    testWidgets('the native splash is removed when the preload fails', (tester) async {
      final splash = _FakeSplashBinding();
      FlutterNativeSplash.preserve(widgetsBinding: splash);
      addTearDown(FlutterNativeSplash.remove);
      final preload = Completer<PreloadedData>();

      await mountApp(
        tester,
        child: const AppInitializationScreen(),
        childType: AppInitializationScreen,
        overrides: {
          preloadedDataProvider: preloadedDataProvider.overrideWith((ref) => preload.future),
        },
      );

      expect(splash.allowFirstFrameCalls, 0);

      preload.completeError(Exception('preload failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(splash.allowFirstFrameCalls, 1);
    });

    testWidgets('a failed preload does not boot the app', (tester) async {
      final preload = Completer<PreloadedData>();

      await mountApp(
        tester,
        child: const AppInitializationScreen(),
        childType: AppInitializationScreen,
        overrides: {
          preloadedDataProvider: preloadedDataProvider.overrideWith((ref) => preload.future),
        },
      );

      // The failure is an [Error], not an [Exception]: the shared scope retries
      // an [Exception] (the app's own retry policy does too), and a retrying
      // provider stays in `AsyncLoading` with the error attached, which is the
      // loading branch. Only a non-retryable failure reaches the error branch.
      preload.completeError(StateError('preload failed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Application), findsNothing);
    });

    testWidgets('the review session is prewarmed while the splash is up', (tester) async {
      // The preload never resolves, so the app stays behind the native splash.
      // The review session is built during that time, so the first board is
      // ready the moment the splash goes away.
      final container = await mountApp(
        tester,
        child: const AppInitializationScreen(),
        childType: AppInitializationScreen,
        overrides: {
          preloadedDataProvider: preloadedDataProvider.overrideWith(
            (ref) => Completer<PreloadedData>().future,
          ),
        },
      );

      expect(container.exists(reviewControllerProvider), isTrue);
    });

    testWidgets('the stored session is validated at startup', (tester) async {
      final container = await mountApp(tester);

      expect(container.exists(startupTokenCheckProvider), isTrue);
    });

    testWidgets('the app starts its services at boot', (tester) async {
      final container = await mountApp(tester);

      expect(container.exists(appLogServiceProvider), isTrue);
      expect(container.exists(accountServiceProvider), isTrue);
      expect(container.exists(quickActionServiceProvider), isTrue);
      expect(container.exists(appLinksServiceProvider), isTrue);
      expect(container.exists(sharedPgnServiceProvider), isTrue);
    });
  });

  // ---------------------------------------------------------------------
  // Theme: the theme mode, the platform brightness, the accent.
  // ---------------------------------------------------------------------
  group('theme', () {
    testWidgets('the theme mode picks the brightness', (tester) async {
      const expected = {
        BackgroundThemeMode.light: Brightness.light,
        BackgroundThemeMode.dark: Brightness.dark,
        BackgroundThemeMode.amoled: Brightness.dark,
        BackgroundThemeMode.system: Brightness.light,
      };

      for (final entry in expected.entries) {
        await mountApp(
          tester,
          key: ValueKey('theme_${entry.key.name}'),
          defaultPreferences: _generalPrefs(GeneralPrefs.defaults.copyWith(themeMode: entry.key)),
        );

        expect(
          Theme.of(tester.element(find.byType(ReviewScreen))).brightness,
          entry.value,
          reason: 'theme mode ${entry.key.name}',
        );
      }
    });

    testWidgets('the system theme mode follows the platform brightness', (tester) async {
      // The app root reads the platform brightness from the MediaQuery above
      // it, so the brightness is injected there rather than on the platform.
      await mountApp(
        tester,
        child: const MediaQuery(
          data: MediaQueryData(size: kTestSurfaceSize, platformBrightness: Brightness.dark),
          child: Application(),
        ),
        defaultPreferences: _generalPrefs(
          GeneralPrefs.defaults.copyWith(themeMode: BackgroundThemeMode.system),
        ),
      );

      expect(Theme.of(tester.element(find.byType(ReviewScreen))).brightness, Brightness.dark);
    });

    testWidgets('the accent preference themes the app', (tester) async {
      await mountApp(
        tester,
        defaultPreferences: _generalPrefs(GeneralPrefs.defaults.copyWith(accent: SrsAccent.violet)),
      );

      final context = tester.element(find.byType(ReviewScreen));
      expect(SrsTheme.of(context).accentId, SrsAccent.violet);
      expect(Theme.of(context).colorScheme.primary, kSrsAccents[SrsAccent.violet]!.light);
    });
  });

  // ---------------------------------------------------------------------
  // Localisation: the stored locale and the supported locales.
  // ---------------------------------------------------------------------
  group('localisation', () {
    testWidgets('the stored locale is applied', (tester) async {
      await mountApp(
        tester,
        defaultPreferences: _generalPrefs(
          GeneralPrefs.defaults.copyWith(locale: const Locale('eo')),
        ),
      );

      expect(Localizations.localeOf(tester.element(find.byType(ReviewScreen))), const Locale('eo'));
    });

    testWidgets('every supported locale is honoured', (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        await mountApp(
          tester,
          key: ValueKey('locale_$locale'),
          defaultPreferences: _generalPrefs(GeneralPrefs.defaults.copyWith(locale: locale)),
        );

        expect(
          Localizations.localeOf(tester.element(find.byType(ReviewScreen))),
          locale,
          reason: 'locale ${locale.languageCode}',
        );
      }
    });
  });

  // ---------------------------------------------------------------------
  // Chrome: the window title, the navigation bar, the route stack.
  // ---------------------------------------------------------------------
  group('chrome', () {
    testWidgets('the window title is the app name', (tester) async {
      await mountApp(tester);

      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'ChessSRS');
    });

    testWidgets('a short screen gets a 60px navigation bar off iOS', (tester) async {
      await mountApp(
        tester,
        child: Theme(
          data: ThemeData(platform: TargetPlatform.android),
          child: const Application(),
        ),
        surfaceSize: const Size(390, 600),
      );

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.navigationBarTheme.height,
        60,
      );
    });

    testWidgets('a tall screen keeps the stock navigation bar height', (tester) async {
      await mountApp(
        tester,
        child: Theme(
          data: ThemeData(platform: TargetPlatform.android),
          child: const Application(),
        ),
      );

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.navigationBarTheme.height,
        isNull,
      );
    });

    testWidgets('iOS keeps the stock navigation bar height', (tester) async {
      await mountApp(
        tester,
        child: Theme(
          data: ThemeData(platform: TargetPlatform.iOS),
          child: const Application(),
        ),
        surfaceSize: const Size(390, 600),
      );

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme?.navigationBarTheme.height,
        isNull,
      );
    });

    testWidgets('the root navigator route stack is tracked', (tester) async {
      await mountApp(tester);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/probe'),
          builder: (_) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      expect(rootNavRouteStackObserver.containsRoute('/probe'), isTrue);

      navigator.pop();
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------------
  // Screen-size initialisation: the thresholds it computes from, and the
  // fact that it runs once per install.
  //
  // The height left over after the board is estimated as
  // `height - width - kToolbarHeight - kBottomBarHeight`, i.e. `height - width - 112`.
  // The surfaces below are chosen so that the leftover lands exactly on a
  // threshold, which is where an off-by-one changes the answer.
  // ---------------------------------------------------------------------
  group('screen-size initialisation', () {
    testWidgets('a device exactly at the tablet threshold is not a tablet', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(600, 1000));

      expect(container.read(analysisPreferencesProvider).smallBoard, isFalse);
      expect(container.read(studyPreferencesProvider).smallBoard, isFalse);
    });

    testWidgets('exactly the small-screen threshold is not a small screen', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(390, 702));

      expect(container.read(analysisPreferencesProvider).smallBoard, isFalse);
      expect(container.read(studyPreferencesProvider).smallBoard, isFalse);
      expect(container.read(analysisPreferencesProvider).showEngineLines, isTrue);
    });

    testWidgets('a tablet gets the small board', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(820, 1180));

      expect(container.read(analysisPreferencesProvider).smallBoard, isTrue);
      expect(container.read(studyPreferencesProvider).smallBoard, isTrue);
    });

    testWidgets('a tablet shows engine lines even when little room is left', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(820, 1100));

      expect(container.read(analysisPreferencesProvider).showEngineLines, isTrue);
      expect(container.read(studyPreferencesProvider).showEngineLines, isTrue);
    });

    testWidgets('exactly the engine-lines threshold hides the engine lines', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(390, 672));

      expect(container.read(analysisPreferencesProvider).showEngineLines, isFalse);
      expect(container.read(studyPreferencesProvider).showEngineLines, isFalse);
    });

    testWidgets('a small phone gets the small board', (tester) async {
      final container = await mountApp(tester, surfaceSize: const Size(390, 600));

      expect(container.read(analysisPreferencesProvider).smallBoard, isTrue);
      expect(container.read(studyPreferencesProvider).smallBoard, isTrue);
      expect(container.read(analysisPreferencesProvider).showEngineLines, isFalse);
    });

    testWidgets('the screen-size initialisation does not run twice', (tester) async {
      // First launch: the app works out the board size for this screen.
      final container = await mountApp(tester, surfaceSize: const Size(390, 600));
      expect(container.read(analysisPreferencesProvider).smallBoard, isTrue);

      // The user turns the small board off.
      await container.read(analysisPreferencesProvider.notifier).toggleSmallBoard();
      await tester.pump();
      expect(container.read(analysisPreferencesProvider).smallBoard, isFalse);

      // Second launch of the same install: the app must not overwrite the
      // user's choice with the size it computed for itself.
      final second = await mountApp(
        tester,
        key: const ValueKey('second-launch'),
        surfaceSize: const Size(390, 600),
      );
      expect(second.read(analysisPreferencesProvider).smallBoard, isFalse);
    });
  });
}
