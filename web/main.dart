import 'dart:async';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/widgets/board.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Web-specific providers that replace native ones
final webStorageProvider = Provider<WebStorage>((ref) => WebStorage());

class WebStorage {
  Future<String?> getString(String key) async {
    // Use localStorage via JS interop or just return null for demo
    return null;
  }
  Future<void> setString(String key, String value) async {}
  Future<void> delete(String key) async {}
}

/// Web entry point
Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Skip native splash
  // FlutterNativeSplash.remove();

  // Initialize web-specific providers
  // ...

  runApp(
    ProviderScope(
      observers: [ProviderLogger()],
      overrides: [
        // Replace native storage with web storage
        // sharedPreferencesProvider: webStorageProvider,
      ],
      child: const WebApp(),
    ),
  );
}

class WebApp extends ConsumerWidget {
  const WebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final srsColors = SrsColors.forBrightness(Brightness.dark, SrsAccent.ultramarine);
    final theme = srsThemeData(srsColors);

    return SrsTheme(
      colors: srsColors,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        title: 'ChessSRS',
        theme: theme,
        builder: (context, child) => SrsTheme(colors: srsColors, child: child!),
        home: const ReviewScreen(),
      ),
    );
  }
}

// ProviderLogger from app.dart
class ProviderLogger extends ProviderObserver {
  @override
  void didAddProvider(ProviderBase provider, Object? value, ProviderContainer container) {
    debugPrint('[PROVIDER] Added $provider = $value');
  }

  @override
  void didDisposeProvider(ProviderBase provider, ProviderContainer container) {
    debugPrint('[PROVIDER] Disposed $provider');
  }

  @override
  void providerDidFail(ProviderBase provider, Object error, StackTrace stackTrace, ProviderContainer container) {
    debugPrint('[PROVIDER] FAILED $provider: $error\n$stackTrace');
  }
}
