import 'dart:async';

import 'package:chess_srs/src/app.dart';
import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/init.dart';
import 'package:chess_srs/src/intl.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/log/app_log_service.dart';
import 'package:chess_srs/src/utils/riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  final lichessBinding = AppLichessBinding.ensureInitialized();

  // Show splash screen until app is ready
  // See src/app.dart for splash screen removal
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await lichessBinding.preloadSharedPreferences();

  // Must run before [initializeApp], which uses the system colors to pick the default board theme
  // on first run.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await androidDisplayInitialization(widgetsBinding);
  }

  setupIntl(widgetsBinding);

  // Background initialization tasks (non-blocking for first frame)
  unawaited(preloadPieceImages());
  unawaited(initializeApp());
  unawaited(SoundService.initialize());

  runApp(
    ProviderScope(
      observers: [ProviderLogger()],
      retry: lichessProviderRetry,
      child: const AppInitializationScreen(),
    ),
  );
}
