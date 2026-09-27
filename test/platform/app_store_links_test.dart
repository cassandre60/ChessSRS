// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "rate this app" links have to point at *this* app.
///
/// The identifiers were inherited with the rest of upstream and were never changed with the
/// package name, so the tile opened the upstream project's Play listing and its App Store page.
/// Nothing about that is visible from inside the app: the tile looks correct, the browser or store
/// opens, and the user is invited to rate a different application under someone else's name.
///
/// These assertions are deliberately about identity rather than about a particular URL, so that
/// changing how the link is built cannot quietly reintroduce a foreign listing.
void main() {
  group('app store listings', () {
    test("the package name is this app's own application id", () {
      // Read from the build config rather than restated, so a rename of the app cannot leave the
      // store links pointing at the old package.
      final gradle = File('android/app/build.gradle.kts').existsSync()
          ? File('android/app/build.gradle.kts').readAsStringSync()
          : File('android/app/build.gradle').readAsStringSync();

      expect(
        gradle,
        contains('applicationId = "$kAppStorePackageName"'),
        reason: 'the store link must be built from the id the app is actually published under',
      );
    });

    test('the Play links name this app', () {
      final links = androidAppStoreLinks();

      expect(links.native.scheme, 'market');
      expect(links.native.queryParameters['id'], kAppStorePackageName);
      expect(links.web.host, 'play.google.com');
      expect(links.web.queryParameters['id'], kAppStorePackageName);
    });

    test("the App Store link is either this app's listing or a search, never another app", () {
      final url = appStoreListingUrl(isAndroid: false);

      expect(url.host, 'apps.apple.com');
      // A listing is addressed by the numeric id Apple assigned; there is no way to derive it, so
      // the honest options are the real id or a search — never a hardcoded path that happens to
      // name a different application.
      final isListing = url.pathSegments.contains('id');
      final isSearch = url.pathSegments.contains('search');
      expect(
        isListing || isSearch,
        isTrue,
        reason: 'got $url, which is neither a listing id nor a search',
      );
      if (isListing) {
        expect(url.pathSegments.last, kAppStoreListingId);
      }
    });

    test('no listing points at the upstream project it was forked from', () {
      const upstream = 'org.lichess.mobile';
      final links = androidAppStoreLinks();
      for (final url in [
        links.native.toString(),
        links.web.toString(),
        appStoreListingUrl(isAndroid: false).toString(),
      ]) {
        expect(
          url,
          isNot(contains(upstream)),
          reason: 'a store link naming the upstream app sends users to a different application',
        );
      }
    });

    test('the settings screen hardcodes no store identifier of its own', () {
      // The build-time assertions above cannot see a link written straight into a widget, which
      // is exactly how the upstream listing got here: three string literals in the tile's onTap.
      // This reads the source so that shape cannot come back unnoticed.
      //
      // Scans the settings screen the app actually shows. This was `settings_screen.dart` until
      // that file went as dead code — its buildRoute forwarded to SrsSettingsScreen, so nothing
      // could reach it, and its "rate this app" row moved to SrsSettingsScreen rather than being
      // dropped. The scan follows the row, and now covers every settings entry point.
      const sources = [
        'lib/src/view/settings/srs_settings_screen.dart',
        'lib/src/view/settings/account_preferences_screen.dart',
        'lib/src/view/more/more_tab_screen.dart',
        'lib/src/view/account/account_menu.dart',
      ];

      for (final path in sources) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();

        for (final pattern in [
          RegExp(r'market://details\?id='),
          RegExp(r'play\.google\.com/store/apps/details'),
          RegExp(r'apps\.apple\.com'),
        ]) {
          expect(
            source,
            isNot(matches(pattern)),
            reason:
                '$path builds a store URL inline; build it from constants.dart so it cannot '
                'name an app this project does not own',
          );
        }
      }
    });
  });
}
