import 'dart:async';
import 'dart:io';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/app_links_service.dart';
import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/theme_bridge.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/account/account_service.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/log/app_log_service.dart';
import 'package:chess_srs/src/model/notifications/notification_service.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/navigation.dart';
import 'package:chess_srs/src/quick_actions.dart';
import 'package:chess_srs/src/shared_pgn_service.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:material_ui/material_ui.dart';

const String _kIosAppGroupId = 'group.org.chesssrs.app.LichessWidgets';

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

    // Start services
    ref.read(appLogServiceProvider).start();
    ref.read(notificationServiceProvider).start();
    ref.read(accountServiceProvider).start();
    ref.read(quickActionServiceProvider).start();
    ref.read(appLinksServiceProvider).start();
    ref.read(sharedPgnServiceProvider).start();

    // Home-screen widgets are only supported on iOS and Android; the plugin
    // has no implementation on desktop platforms.
    if (Platform.isIOS || Platform.isAndroid) {
      if (Platform.isIOS) {
        HomeWidget.setAppGroupId(_kIosAppGroupId);
      }
      HomeWidget.saveWidgetData<String>('lichessHost', kLichessHost);
    }

    if (Platform.isIOS) {
      ref.listenManual(boardPreferencesProvider, (prev, state) {
        if (prev == null ||
            prev.boardTheme != state.boardTheme ||
            prev.pieceSet != state.pieceSet) {
          Future.wait([
            HomeWidget.saveWidgetData<String>('boardTheme', state.boardTheme.name),
            HomeWidget.saveWidgetData<String>('pieceSet', state.pieceSet.name),
          ]).then((_) {
            HomeWidget.updateWidget(iOSName: 'DailyPuzzleLargeWidget');
          });
        }
      }, fireImmediately: true);
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    // Resolve brightness: system, forced, or explicit.
    final brightness = generalPrefs.isForcedDarkMode
        ? Brightness.dark
        : switch (generalPrefs.themeMode) {
            BackgroundThemeMode.light => Brightness.light,
            BackgroundThemeMode.dark || BackgroundThemeMode.amoled => Brightness.dark,
            BackgroundThemeMode.system => MediaQuery.platformBrightnessOf(context),
          };

    final accent = ref.watch(srsAccentProvider);
    final srsColors = SrsColors.forBrightness(brightness, accent);

    // Material ThemeData bridge for un-migrated screens.
    final theme = srsThemeData(srsColors);

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    // The same key services read to push routes: deep links, quick actions, share
    // intents, engine errors and the weights download. See lib/src/navigation.dart.
    final navigatorKey = ref.watch(rootNavigatorKeyProvider);

    return SrsTheme(
      colors: srsColors,
      child: MaterialApp(
        navigatorKey: navigatorKey,
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
