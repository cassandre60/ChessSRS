// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The app's own fonts, registered with the test engine.
//
// `flutter test` runs the engine with `--use-test-fonts --disable-asset-fonts`
// (`flutter_tools/lib/src/test/flutter_tester_device.dart`), so the engine never
// registers the fonts the app ships. Every string in the widget suite is then
// measured with the square test glyphs — one em per character, whatever the
// letter — which makes every string about twice as wide as it is in the app.
//
// The families come from the app's own `FontManifest.json`: the file the build
// generates from the `fonts:` block of `pubspec.yaml`. This file therefore
// holds no list of its own, and cannot drift from what the app declares.

import 'dart:convert';

import 'package:flutter/services.dart';

/// The asset directory the app's own font assets live under.
///
/// The manifest also lists the families the Flutter SDK and the packages
/// contribute (`MaterialIcons`, `MaterialSymbolsRounded`, `CupertinoIcons`).
/// Those are not the app's fonts, and registering them would change what the
/// design-review captures draw, so they are left alone.
const String _appFontAssetPrefix = 'assets/fonts/';

/// The in-flight or completed load.
///
/// The fonts are registered once per test file, not once per test: the engine
/// keeps them for the life of the process.
Future<void>? _loading;

/// Whether the fonts are registered.
///
/// A flag rather than only the future, because a future created inside one
/// test's fake-async zone cannot be awaited from the next test's: the
/// continuation is scheduled in the zone that is gone, and the test hangs.
bool _loaded = false;

/// Registers the app's font families with the engine.
///
/// Safe to call from every test: the work happens once, and later calls await
/// nothing.
Future<void> loadAppFonts() {
  if (_loaded) {
    return Future<void>.value();
  }
  return _loading ??= _loadAppFonts().then<void>(
    (_) {
      _loaded = true;
    },
    onError: (Object error, StackTrace stackTrace) {
      // A failed load must not be cached: the next test has to try again, and
      // it cannot await a future that belongs to this test's zone.
      _loading = null;
      Error.throwWithStackTrace(error, stackTrace);
    },
  );
}

Future<void> _loadAppFonts() async {
  final raw = await rootBundle.loadString('FontManifest.json');
  final manifest = (json.decode(raw) as List<dynamic>).cast<Map<String, Object?>>();

  for (final entry in manifest) {
    final family = entry['family'];
    final fonts = entry['fonts'];
    if (family is! String || fonts is! List<dynamic>) {
      continue;
    }

    final assets = <String>[];
    for (final font in fonts) {
      final asset = (font as Map<String, Object?>)['asset'];
      if (asset is String && asset.startsWith(_appFontAssetPrefix)) {
        assets.add(asset);
      }
    }
    if (assets.isEmpty) {
      continue;
    }

    final loader = FontLoader(family);
    for (final asset in assets) {
      // The manifest percent-encodes the brackets in the variable fonts' file
      // names; the asset bundle keys them decoded.
      loader.addFont(rootBundle.load(Uri.decodeComponent(asset)));
    }
    await loader.load();
  }
}
