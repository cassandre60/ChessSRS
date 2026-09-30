import 'dart:async';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app_links_service.dart';
import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/theme_bridge.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/account/account_service.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/log/app_log_service.dart';
import 'package:chess_srs/src/model/notifications/notification_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/quick_actions.dart';
import 'package:chess_srs/src/shared_pgn_service.dart';
import 'package:chess_srs/src/tab_navigation.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:material_ui/material_ui.dart';

/// Application initialization and main entry point.
class AppInitializationScreen extends ConsumerWidget {
  const AppInitializationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<PreloadedData>>(preloadedDataProvider, (_, state) {
      if (state.hasValue || state.hasError) {
        FlutterNativeSplash.remove();
      }
    });

    switch (ref.watch(preloadedDataProvider)) {
      case AsyncData():
        return const Application();
      case AsyncError(:final error, :final stackTrace):
        debugPrint('SEVERE: [App] could not initialize app; $error\n$stackTrace');
        return const SizedBox.shrink();
      case _:
        // loading screen is handled by the native splash screen
        return const SizedBox.shrink();
    }
  }
}

/// The main application widget.
///
/// This widget is the root of the application and is responsible for setting up
/// the theme, locale, and other global settings.
class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => _AppState();
}

class _AppState extends ConsumerState<Application> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  // Adjusts some settings for small screens based on the MediaQuery data.
  Future<void> _screenSizeBasedInitialization(WidgetRef ref) async {
    // Bump version here in case we adjust the thresholds for screen size based initialization
    // and want it to run again for users who already launched the app with a previous version.
    const kDoneScreenSizeInitKey = 'done_screen_size_init_v1';

    final prefs = LichessBinding.instance.sharedPreferences;
    if (prefs.getBool(kDoneScreenSizeInitKey) == true) {
      return;
    }

    final mediaQueryData = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.first,
    );
    final isTablet = mediaQueryData.size.shortestSide > FormFactor.tablet;
    final isSmallScreen = estimateHeightMinusBoard(mediaQueryData) < kSmallHeightMinusBoard;
    final showEngineLines =
        isTablet || estimateHeightMinusBoard(mediaQueryData) > kSmallHeightMinusBoard - 30;

    // For tablets in portrait mode using the full board size makes the bottom analysis tabs tiny,
    // see https://github.com/lichess-org/mobile/issues/3150,
    // so use a small board there by default as well.
    final smallBoard = isTablet || isSmallScreen;

    await ref
        .read(analysisPreferencesProvider.notifier)
        .save(
          ref
              .read(analysisPreferencesProvider)
              .copyWith(smallBoard: smallBoard, showEngineLines: showEngineLines),
        );
    await ref
        .read(studyPreferencesProvider.notifier)
        .save(
          ref
              .read(studyPreferencesProvider)
              .copyWith(smallBoard: smallBoard, showEngineLines: showEngineLines),
        );

    await prefs.setBool(kDoneScreenSizeInitKey, true);
  }

  @override
  void initState() {
    _screenSizeBasedInitialization(ref);

    // Validate the stored session token, if there is one. Read once and left unawaited: the app is
    // usable while it is in flight, and an invalid token signs the user out when it lands.
    ref.read(startupTokenCheckProvider);

    // Start services
    ref.read(appLogServiceProvider).start();
    ref.read(notificationServiceProvider).start();
    ref.read(accountServiceProvider).start();
    ref.read(quickActionServiceProvider).start();
    ref.read(appLinksServiceProvider).start();
    ref.read(sharedPgnServiceProvider).start();

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    // Brightness is the theme mode and nothing else. It used to also be forced dark whenever a
    // background colour or image was set, which is gone with the background setting: the
    // Diagram palette is light or dark by choice, and every token's contrast is specified
    // against the matching `ground`.
    final brightness = switch (generalPrefs.themeMode) {
      BackgroundThemeMode.light => Brightness.light,
      BackgroundThemeMode.dark || BackgroundThemeMode.amoled => Brightness.dark,
      BackgroundThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

    final accent = ref.watch(srsAccentProvider);
    final srsColors = SrsColors.forBrightness(brightness, accent);

    // Material ThemeData bridge for un-migrated screens.
    final theme = srsThemeData(srsColors);

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return SrsTheme(
      colors: srsColors,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          MaterialLocalizationsEo.delegate,
          CupertinoLocalizationsEo.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        title: 'ChessSRS',
        locale: generalPrefs.locale,
        theme: theme.copyWith(
          navigationBarTheme: isIOS
              ? null
              : NavigationBarTheme.of(
                  context,
                ).copyWith(height: isShortVerticalScreen(context) ? 60 : null),
        ),
        builder: (context, child) => SrsTheme(colors: srsColors, child: child!),
        home: const ReviewScreen(),
        navigatorObservers: [rootNavPageRouteObserver, rootNavRouteStackObserver],
      ),
    );
  }
}
