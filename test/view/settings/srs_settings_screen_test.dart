// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/view/settings/srs_settings_copy.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  testWidgets('renders the design rows in the design order', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    // design/docs/03-components.md §11 order, with the Advanced section collapsed.
    final rows = [
      kSrsSettingDailyLimit,
      kSrsSettingTargetRetention,
      kSrsSettingShowNotation,
      kSrsSettingShowNotes,
      kSrsSettingShowAnnotations,
      kSrsSettingAccent,
      kSrsSettingTheme,
      kSrsSettingSound,
      kSrsSettingAdvanced,
    ];
    var previousTop = -1.0;
    for (final label in rows) {
      final top = tester.getTopLeft(find.text(label).first).dy;
      expect(top, greaterThan(previousTop), reason: '$label is out of order');
      previousTop = top;
    }
  });

  // The Theme row is the one place the screen states the current theme, so it has to agree
  // with the rest of the app. It used to read only the two explicit dark modes, which made
  // `system` — the default — report Light on a dark desktop.
  group('the Theme row reports the theme actually in use', () {
    Future<bool> reportedIsDark(
      WidgetTester tester, {
      required String themeMode,
      required Brightness platform,
    }) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Builder(
          // Override the platform brightness on the screen's own MediaQuery rather than
          // through the dispatcher: this is what the screen reads, and it makes the test
          // independent of whether the binding plumbs a test value into MaterialApp's
          // MediaQuery. Everything else about the MediaQuery is preserved, so the screen's
          // size-driven layout is untouched.
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(platformBrightness: platform),
            child: const SrsSettingsScreen(),
          ),
        ),
        brightness: platform,
        defaultPreferences: {
          // The whole object, not a fragment: GeneralPrefs.fromJson declares most fields
          // required, so a partial JSON fails to parse and the provider silently falls back
          // to defaults — which is themeMode `system`, and made the explicit-mode cases
          // below look like they had failed.
          PrefCategory.general.storageKey: jsonEncode(
            GeneralPrefs.defaults
                .copyWith(themeMode: BackgroundThemeMode.values.byName(themeMode))
                .toJson(),
          ),
        },
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The only SrsSegmented<bool> on the screen is the Theme row; the other segmented
      // controls are <int>, <double> and <SchedulerType>.
      final control = tester.widget<SrsSegmented<bool>>(find.byType(SrsSegmented<bool>));
      return control.value;
    }

    testWidgets('system on a dark platform reports dark', (tester) async {
      expect(await reportedIsDark(tester, themeMode: 'system', platform: Brightness.dark), isTrue);
    });

    testWidgets('system on a light platform reports light', (tester) async {
      expect(
        await reportedIsDark(tester, themeMode: 'system', platform: Brightness.light),
        isFalse,
      );
    });

    testWidgets('an explicit light mode beats a dark platform', (tester) async {
      expect(
        await reportedIsDark(tester, themeMode: 'light', platform: Brightness.dark),
        isFalse,
        reason: 'the user chose Light, so a dark system must not override them',
      );
    });

    testWidgets('an explicit dark mode beats a light platform', (tester) async {
      expect(await reportedIsDark(tester, themeMode: 'dark', platform: Brightness.light), isTrue);
    });
  });

  testWidgets('uses the design labels, not the build-invented ones', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // The board draws arrows and highlighted squares; the design names what the user
    // sees, not the mechanism.
    expect(find.text(kSrsSettingShowAnnotations), findsOneWidget);
    expect(find.text('Show board annotations'), findsNothing);
    expect(find.text('Review Diagnostics HUD'), findsNothing);
  });

  testWidgets('has no uppercase section headers', (tester) async {
    // The demo's settings screen is one continuous group of hairline-separated rows.
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    for (final header in const [
      'REVIEW & SPACED REPETITION',
      'APPEARANCE & THEME',
      'BOARD & PIECES',
      'SOUND & AUDIO',
      'CHESS ENGINE',
      'DATA & DIAGNOSTICS',
      'ABOUT',
    ]) {
      expect(find.text(header), findsNothing, reason: header);
    }
  });

  testWidgets('hides the algorithm and diagnostics behind Advanced', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.byType(SrsDisclosure), findsOneWidget);
    expect(find.text(kSrsSettingScheduler), findsNothing);
    expect(find.text(kSrsSettingDiagnostics), findsNothing);

    await tester.ensureVisible(find.text(kSrsSettingAdvanced));
    await tester.tap(find.text(kSrsSettingAdvanced));
    await tester.pumpAndSettle();

    expect(find.text(kSrsSettingScheduler), findsOneWidget);
    expect(find.text(kSrsSettingDiagnostics), findsOneWidget);
    expect(find.text('FSRS'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Ease'), findsOneWidget);
  });

  testWidgets('updates preferences', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('25'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('95%'));
    await tester.tap(find.text('95%'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(kSrsSettingShowNotes));
    await tester.tap(find.text(kSrsSettingShowNotes));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(kSrsSettingShowAnnotations));
    await tester.tap(find.text(kSrsSettingShowAnnotations));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.bySemanticsLabel('violet'));
    await tester.tap(find.bySemanticsLabel('violet'));
    await tester.pumpAndSettle();

    // The settings the design does not cover stay reachable.
    expect(find.text('Board & pieces'), findsOneWidget);
    expect(find.text('Sound & audio details'), findsOneWidget);
    expect(find.text('Chess engine'), findsOneWidget);
    expect(find.text('Local database size'), findsOneWidget);
    expect(find.text('HTTP network logs'), findsOneWidget);
    expect(find.text('App diagnostics logs'), findsOneWidget);

    await tester.ensureVisible(find.text(kSrsSettingAdvanced));
    await tester.tap(find.text(kSrsSettingAdvanced));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Simple'));
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(kSrsSettingDiagnostics));
    await tester.tap(find.text(kSrsSettingDiagnostics));
    await tester.pumpAndSettle();
  });
}
