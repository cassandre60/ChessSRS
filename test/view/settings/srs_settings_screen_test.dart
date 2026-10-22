// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/view/review/about_page.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  /// Finds segmented option [option] inside the settings row labelled [label].
  ///
  /// The Daily limit and New positions rows share option labels ('50', '100',
  /// 'None'), so a bare find.text is ambiguous. The row root is the Container
  /// ancestor of the label whose subtree holds the option — robust to row
  /// reordering, unlike positional (.first/.last) picks.
  Finder settingOption(WidgetTester tester, String label, String option) {
    final containers = find.ancestor(of: find.text(label), matching: find.byType(Container));
    final row = containers.evaluate().firstWhere(
      (e) => find
          .descendant(of: find.byWidget(e.widget), matching: find.text(option))
          .evaluate()
          .isNotEmpty,
      orElse: () => throw StateError('no $label row contains $option'),
    );
    return find.descendant(of: find.byWidget(row.widget), matching: find.text(option));
  }

  Finder settingSwitch(String semanticLabel) {
    return find.byWidgetPredicate((w) => w is SrsSwitch && w.semanticLabel == semanticLabel);
  }

  /// The segmented control in the settings row labelled [label].
  ///
  /// The row root is the Container ancestor of the label whose subtree holds
  /// the control -- the same scoping [settingOption] uses for the options, so
  /// a row that shares option labels with another row is still found on its
  /// own.
  Finder settingSelector(WidgetTester tester, String label) {
    final containers = find.ancestor(of: find.text(label), matching: find.byType(Container));
    final row = containers.evaluate().firstWhere(
      (e) => find
          .descendant(
            of: find.byWidget(e.widget),
            matching: find.bySubtype<SrsSegmented<Object?>>(),
          )
          .evaluate()
          .isNotEmpty,
      orElse: () => throw StateError('no $label row holds a selector'),
    );
    return find.descendant(
      of: find.byWidget(row.widget),
      matching: find.bySubtype<SrsSegmented<Object?>>(),
    );
  }

  /// The value the segmented control in the row labelled [label] is set to.
  Object? selectorValue(WidgetTester tester, String label) {
    return tester.widget<SrsSegmented<Object?>>(settingSelector(tester, label)).value;
  }

  /// Whether [option] is the marked one -- the option the selector reports as
  /// the current value -- in the row labelled [label].
  ///
  /// The marked option is drawn with the ground ink on the ink fill; the others
  /// are drawn in the second ink on no fill.
  bool optionIsMarked(WidgetTester tester, String label, String option) {
    final colors = SrsTheme.of(tester.element(find.byType(SrsSettingsScreen)));
    final text = tester.widget<Text>(
      find.descendant(of: settingSelector(tester, label), matching: find.text(option)),
    );
    return text.style?.color == colors.ground;
  }

  /// The state the switch in the row labelled [label] is set to.
  bool switchState(WidgetTester tester, String label) {
    return tester.widget<SrsSwitch>(settingSwitch(label)).value;
  }

  /// The row that holds the label [label] -- the closest Container ancestor of
  /// the label text, which is the row itself.
  Finder labelRow(WidgetTester tester, String label) {
    final containers = find.ancestor(of: find.text(label), matching: find.byType(Container));
    return find.byWidget(containers.evaluate().first.widget);
  }

  /// The row that holds the label [label] -- the first Row ancestor of the label
  /// text, which is the label's own row inside the setting's row.
  Finder labelTextRow(WidgetTester tester, String label) {
    return find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
  }

  /// The distance from the top of the row [label] to the top of its label row.
  ///
  /// The row's own vertical padding is part of it, and the padding is what
  /// tells the wide layout (18px) from the narrow one (8px).
  ///
  /// The label *row*, not the label *text*: the text is centred in that row,
  /// and how far it sits from the row's top depends on the font's line height
  /// and on the 44px info button the narrow layout puts next to the label. The
  /// row's own top is the row's padding, whatever the font measures.
  double labelInset(WidgetTester tester, String label) {
    return tester.getRect(labelTextRow(tester, label)).top -
        tester.getRect(labelRow(tester, label)).top;
  }

  /// The chevron painter in the row labelled [label].
  ///
  /// The row also holds the shape painter of the material behind it, so the
  /// chevron is picked out by its own painter type.
  CustomPaint rowChevron(WidgetTester tester, String label) {
    final chevrons = find
        .descendant(of: labelRow(tester, label), matching: find.byType(CustomPaint))
        .evaluate()
        .map((e) => e.widget as CustomPaint)
        .where((w) => w.painter?.runtimeType.toString().contains('Chevron') ?? false);
    return chevrons.first;
  }

  testWidgets('SrsSettingsScreen renders Diagram layout and updates preferences', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SrsSettingsScreen)));

    // Verify title and back button
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    // Verify main rows exist
    expect(find.text('Daily limit'), findsOneWidget);
    expect(find.text('Target retention'), findsOneWidget);
    expect(find.text('Show notes after a move'), findsOneWidget);
    // The design's words (01-identity.md:89); the row gates studyPrefs.showAnnotations.
    expect(find.text('Show arrows and circles'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Accent'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Scheduling algorithm'), findsOneWidget);

    // Segmented daily limits (scoped: the New positions row shares '50'/'100'/'None')
    expect(find.text('25'), findsOneWidget);
    expect(settingOption(tester, 'Daily limit', '50'), findsOneWidget);
    expect(settingOption(tester, 'Daily limit', '100'), findsOneWidget);
    expect(settingOption(tester, 'Daily limit', 'None'), findsOneWidget);

    // Tap 50 daily limit
    await tester.tap(settingOption(tester, 'Daily limit', '50'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).maxDailyReviews, 50);

    // New positions per day (INV-068): the introduction allowance beside the daily limit.
    expect(find.text('New positions per day'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    await tester.tap(settingOption(tester, 'New positions per day', '10'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).maxNewPerDay, 10);
    await tester.tap(settingOption(tester, 'New positions per day', '20'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).maxNewPerDay, 20);
    expect(tester.takeException(), isNull);

    // Tap 95% retention
    expect(find.text('95%'), findsOneWidget);
    await tester.tap(find.text('95%'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).targetRetention, 0.95);

    // Toggle notes.
    final notesBefore = container.read(studyPreferencesProvider).showPgnComments;
    await tester.scrollUntilVisible(settingSwitch('Show notes after a move'), 200);
    await tester.tap(settingSwitch('Show notes after a move'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).showPgnComments, !notesBefore);

    // Collapsible list groups: same row-tap pattern, gates the drawer collapse switch.
    final collapsibleBefore = container.read(studyPreferencesProvider).collapsibleScopeGroups;
    await tester.scrollUntilVisible(settingSwitch('Collapsible list groups'), 200);
    await tester.tap(settingSwitch('Collapsible list groups'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).collapsibleScopeGroups, !collapsibleBefore);

    // Transposed moves: the P-TRANSPOSE three-way scope (default In scope).
    await tester.scrollUntilVisible(find.text('Transposed moves'), 200);
    expect(find.text('Transposed moves'), findsOneWidget);
    await tester.tap(find.text('Within study'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).transposeScope, TransposeScope.withinStudy);

    // Toggle arrows -- the design's label for the row that gates showAnnotations.
    final arrowsBefore = container.read(studyPreferencesProvider).showAnnotations;
    await tester.scrollUntilVisible(settingSwitch('Show arrows and circles'), 200);
    await tester.tap(settingSwitch('Show arrows and circles'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).showAnnotations, !arrowsBefore);

    // Toggle theme to Dark
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(container.read(generalPreferencesProvider).themeMode, BackgroundThemeMode.dark);

    // Select violet accent dot
    await tester.ensureVisible(find.bySemanticsLabel('violet'));
    await tester.tap(find.bySemanticsLabel('violet'));
    await tester.pumpAndSettle();
    expect(container.read(srsAccentProvider), SrsAccent.violet);

    // Verify navigation links to legacy settings — Board & pieces and Sound sub-screens
    // are now inlined; only Chess engine remains a nav row.
    expect(find.text('Chess engine'), findsOneWidget);

    // Board/appearance settings are now inline
    expect(find.text('Board theme'), findsOneWidget);
    expect(find.text('Piece set'), findsOneWidget);
    expect(find.text('Board coordinates'), findsOneWidget);
    expect(find.text('Piece animation'), findsOneWidget);

    // Sound is now inline with a volume slider
    expect(find.text('Volume'), findsOneWidget);

    // Verify algorithm controls are visible
    expect(find.text('Scheduling algorithm'), findsOneWidget);
    expect(find.text('FSRS'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Ease'), findsOneWidget);
    expect(find.text('Review Diagnostics HUD'), findsOneWidget);
    expect(find.text('Local database size'), findsOneWidget);
    expect(find.text('HTTP network logs'), findsOneWidget);
    expect(find.text('App diagnostics logs'), findsOneWidget);

    // Switch algorithm to Simple
    await tester.ensureVisible(find.text('Simple'));
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).schedulerType, SchedulerType.simple);

    // Toggle diagnostics
    final diagBefore = container.read(studyPreferencesProvider).srsDiagnostics;
    await tester.ensureVisible(settingSwitch('Review Diagnostics HUD'));
    await tester.tap(settingSwitch('Review Diagnostics HUD'));
    await tester.pumpAndSettle();
    expect(container.read(studyPreferencesProvider).srsDiagnostics, !diagBefore);
  });

  testWidgets('phone settings keep small controls inline and disclose help on demand', (
    tester,
  ) async {
    const width = 320.0;
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      surfaceSize: const Size(width, 800),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // Account navigation remains tappable; its explanation is opt-in on phones.
    const accountHelp = 'Sign in to import private and unlisted studies.';
    expect(find.text(accountHelp), findsNothing);
    await tester.tap(find.byTooltip('About Lichess account'));
    await tester.pumpAndSettle();
    expect(find.text(accountHelp), findsOneWidget);
    expect(find.byType(SrsSettingsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Hide details for Lichess account'));
    await tester.pumpAndSettle();
    expect(find.text(accountHelp), findsNothing);

    // The six-way control wraps inside a narrow viewport rather than overflowing.
    await tester.ensureVisible(find.text('Daily limit'));
    expect(
      tester.getRect(settingOption(tester, 'Daily limit', 'None')).right,
      lessThanOrEqualTo(width),
    );
    expect(
      (tester.getCenter(find.text('Daily limit')).dy - tester.getCenter(find.text('25')).dy).abs(),
      greaterThan(20),
    );
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Show move notation'), 200);
    final switchFinder = find.byWidgetPredicate(
      (widget) => widget is SrsSwitch && widget.semanticLabel == 'Show move notation',
    );
    expect(
      (tester.getCenter(find.text('Show move notation')).dy - tester.getCenter(switchFinder).dy)
          .abs(),
      lessThan(20),
    );
    const moveHelp = 'Display preceding moves (e.g. 1. e4 e5) in the review screen.';
    expect(find.text(moveHelp), findsNothing);
    await tester.tap(find.byTooltip('About Show move notation'));
    await tester.pumpAndSettle();
    expect(find.text(moveHelp), findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Short selectors like Theme and Accent dots fit inline even on phones.
    await tester.scrollUntilVisible(find.text('Theme'), 200);
    expect(
      (tester.getCenter(find.text('Theme')).dy - tester.getCenter(find.text('Light')).dy).abs(),
      lessThan(20),
    );

    await tester.scrollUntilVisible(find.text('Accent'), 200);
    // The 44px dots (04 §6) no longer fit beside the label at 320px, so the sanctioned narrow
    // fallback applies instead of overflowing: the control stacks beneath its label (04 §Reflow;
    // P-#30 keeps controls inline only when horizontal space allows).
    expect(
      (tester.getCenter(find.text('Accent')).dy - tester.getCenter(find.byType(SrsAccentDots)).dy)
          .abs(),
      greaterThan(20),
      reason: '210px of dots cannot sit beside the label in 320px; they stack per the reflow rule',
    );
    expect(
      tester.getRect(find.byType(SrsAccentDots)).right,
      lessThanOrEqualTo(320),
      reason: 'stacked is fine, overflowing is not',
    );
  });

  testWidgets('phone settings put selectors inline when width allows', (tester) async {
    const width = 500.0;
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      surfaceSize: const Size(width, 800),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // At 500px, Scheduling algorithm has enough space to be inline beside its label.
    await tester.ensureVisible(find.text('Scheduling algorithm'));
    expect(
      (tester.getCenter(find.text('Scheduling algorithm')).dy -
              tester.getCenter(find.text('FSRS')).dy)
          .abs(),
      lessThan(20),
    );
  });

  testWidgets('wide settings retain visible descriptions', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      surfaceSize: const Size(900, 800),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to import private and unlisted studies.'), findsOneWidget);
    expect(find.byTooltip('About Lichess account'), findsNothing);
  });

  testWidgets('About section links to AboutPage and disables Rate this app for now', (
    tester,
  ) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // Rate this app is disabled until app store release.
    expect(find.text('Rate this app'), findsNothing);

    // About and licences is reachable and opens AboutPage.
    await tester.scrollUntilVisible(find.text('About and licences'), 200);
    expect(find.text('About and licences'), findsOneWidget);

    await tester.tap(find.text('About and licences'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Mutation round on lib/src/view/settings/srs_settings_screen.dart.
  //
  // Every test below was written against a named mutant: with that mutant
  // applied to the screen the test fails, and it passes on the committed
  // source. The mutant and the line it sits on are named above the test.
  // ---------------------------------------------------------------------------
  group('settings screen mutation survivors', () {
    testWidgets('the theme control marks the theme that is in force', (tester) async {
      // SPEC INV-061. Feedback stays readable in both themes.
      //
      // Mutants: srs_settings_screen.dart:96 `themeMode == dark` inverted,
      // :96 `||` conjugated to `&&`, :97 `themeMode == amoled` inverted. Each
      // one leaves the Theme control marking a theme the app is not in, so the
      // filled option and the screen disagree about the theme in force.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The app starts on the system theme, which the harness pins to light.
      expect(optionIsMarked(tester, 'Theme', 'Light'), isTrue);
      expect(optionIsMarked(tester, 'Theme', 'Dark'), isFalse);

      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(optionIsMarked(tester, 'Theme', 'Dark'), isTrue);
      expect(optionIsMarked(tester, 'Theme', 'Light'), isFalse);
    });

    testWidgets('the ease parameters belong to the Ease scheduler alone', (tester) async {
      // SPEC INV-024, INV-026. Scheduling is a pure function of state, event
      // and time; intervals stay within configured bounds.
      //
      // Mutant: srs_settings_screen.dart:314 `schedulerType == easeScaling`
      // inverted -- the two Ease rows are then offered for every other
      // scheduler, where an ease factor and an interval scaling mean nothing.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The default scheduler is Simple, so the Ease parameters are not offered.
      expect(find.text('Initial ease factor'), findsNothing);
      expect(find.text('Interval scaling'), findsNothing);

      await tester.scrollUntilVisible(find.text('Ease'), 200);
      await tester.tap(find.text('Ease'));
      await tester.pumpAndSettle();

      expect(find.text('Initial ease factor'), findsOneWidget);
      expect(find.text('Interval scaling'), findsOneWidget);
      // They show the stored parameters.
      expect(selectorValue(tester, 'Initial ease factor'), 2.5);
      expect(selectorValue(tester, 'Interval scaling'), 1.5);

      // And they go away again with the scheduler that does not use them.
      await tester.tap(find.text('Simple'));
      await tester.pumpAndSettle();
      expect(find.text('Initial ease factor'), findsNothing);
      expect(find.text('Interval scaling'), findsNothing);
    });

    testWidgets("a setting's help never moves to another setting", (tester) async {
      // SPEC INV-062. Interactive targets stay tappable.
      //
      // Mutants: srs_settings_screen.dart:683 `oldWidget.label != widget.label`
      // inverted, and `expanded = false` conjugated to `expanded = true`. Both
      // let the help of one setting be shown under another one when the rows
      // shift, so the 44px help target opens the wrong explanation.
      const width = 320.0;
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(width, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      const moveHelp = 'Display preceding moves (e.g. 1. e4 e5) in the review screen.';
      await tester.scrollUntilVisible(find.text('Show move notation'), 200);
      await tester.tap(find.byTooltip('About Show move notation'));
      await tester.pumpAndSettle();
      expect(find.text(moveHelp), findsOneWidget);

      // A change elsewhere on the screen rebuilds it, and the open help must
      // survive that: the disclosure belongs to the setting it was opened on.
      await tester.scrollUntilVisible(settingSwitch('Show notes after a move'), 200);
      await tester.tap(settingSwitch('Show notes after a move'));
      await tester.pumpAndSettle();
      expect(find.text(moveHelp), findsOneWidget);

      // Choosing the Ease scheduler inserts two rows above, so every row below
      // takes the place of another one.
      await tester.scrollUntilVisible(find.text('Ease'), 200);
      await tester.tap(find.text('Ease'));
      await tester.pumpAndSettle();

      // The row that took the place of the expanded one starts closed: the
      // help of 'Show move notation' is not shown under 'Initial ease factor'.
      expect(find.text(moveHelp), findsNothing);
      expect(find.text('Multiplier applied on first success.'), findsNothing);
    });

    testWidgets('the local database size row shows the size it read', (tester) async {
      // No SPEC invariant names the debug-only size row; the mutation round is
      // the anchor for this one.
      //
      // Mutant: srs_settings_screen.dart:581 `dbSize.value != null` inverted
      // -- the row then shows its loading placeholder for ever.
      // The size comes from a provider that reads the database file, so the
      // provider is given a size of its own here: the test then needs no wait
      // on the disk.
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        overrides: {
          getDbSizeInBytesProvider: getDbSizeInBytesProvider.overrideWith((ref) => 5 * 1024 * 1024),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      expect(labels, contains(matches(RegExp(r'^\d+\.\d{2} MB$'))));
    });

    testWidgets('the settings body uses the wide layout from 520px', (tester) async {
      // SPEC INV-062. Interactive targets stay tappable.
      //
      // Mutant: srs_settings_screen.dart:100 `size.width < 520` loosened to
      // `<= 520` -- at exactly 520px the screen then takes the narrow layout,
      // with the narrow padding and the narrow section spacing.
      var app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(519, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Settings')).left, moreOrLessEquals(16, epsilon: 0.01));

      app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(520, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Settings')).left, moreOrLessEquals(24, epsilon: 0.01));
    });

    testWidgets('a settings row uses the wide layout from 520px of content width', (tester) async {
      // SPEC INV-062. Interactive targets stay tappable.
      //
      // Mutants: srs_settings_screen.dart:783 and :880 `maxWidth < 520`
      // loosened to `<= 520` -- a row whose content column is exactly 520px
      // wide then takes the narrow layout, with the narrow vertical padding.
      //
      // The content column is the screen minus its 24px padding on each side,
      // so a 568px screen leaves exactly 520px of content and a 567px screen
      // leaves 519px of it.
      var app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(567, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final narrowRow = labelInset(tester, 'Daily limit');
      final narrowNav = labelInset(tester, 'Board theme');

      app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(568, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final wideRow = labelInset(tester, 'Daily limit');
      final wideNav = labelInset(tester, 'Board theme');

      // The wide layout pads the row by 18px, the narrow one by 8px.
      expect(wideRow - narrowRow, moreOrLessEquals(10, epsilon: 0.01));
      expect(wideNav - narrowNav, moreOrLessEquals(10, epsilon: 0.01));
    });

    testWidgets('a switch and the volume slider stay beside their labels', (tester) async {
      // SPEC INV-062. Interactive targets stay tappable.
      //
      // Mutants: srs_settings_screen.dart:793 `control is SrsSwitch || control
      // is SizedBox || control is Text || fitsInline` conjugated to `&&` twice.
      // Switches and the volume slider are then kept inline only when they
      // happen to fit, and drop under their label on a narrow screen.
      const width = 240.0;
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        surfaceSize: const Size(width, 800),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Show move notation'), 200);
      final label = tester.getRect(find.text('Show move notation'));
      final toggle = tester.getRect(settingSwitch('Show move notation'));
      expect(toggle.left, greaterThan(label.left + 20));

      await tester.scrollUntilVisible(find.text('Volume'), 200);
      final volumeLabel = tester.getRect(find.text('Volume'));
      final slider = tester.getRect(find.byType(Slider));
      expect(slider.left, greaterThan(volumeLabel.left + 20));
    });

    testWidgets('the chevrons repaint when the palette changes', (tester) async {
      // SPEC INV-061. Feedback stays readable in both themes.
      //
      // Mutants: srs_settings_screen.dart:840 and :864 `shouldRepaint`
      // compares the two colours with `==` instead of `!=`, so a chevron keeps
      // the ink of the palette it was built in.
      var app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        brightness: Brightness.light,
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final lightBack = rowChevron(tester, 'Review').painter!;
      final lightNav = rowChevron(tester, 'Chess engine').painter!;

      app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSettingsScreen(),
        brightness: Brightness.dark,
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final darkBack = rowChevron(tester, 'Review').painter!;
      final darkNav = rowChevron(tester, 'Chess engine').painter!;

      expect(darkBack.shouldRepaint(lightBack), isTrue);
      expect(darkNav.shouldRepaint(lightNav), isTrue);
    });

    testWidgets('each selector shows the value of the preference it controls', (tester) async {
      // SPEC INV-024, INV-031, INV-066, INV-065. Scheduling is a pure function
      // of state, event and time; the daily quota counts positions; by-line
      // review order presents the same due set in line order; an out-of-line
      // move is accepted when its position is in scope.
      //
      // Hand-curated mutants: srs_settings_screen.dart:213 the daily limit
      // reading the new-position cap, :229 the new-position cap reading the
      // daily limit, :245 the retention reading the ease factor.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SrsSettingsScreen)));
      final study = container.read(studyPreferencesProvider);
      final board = container.read(boardPreferencesProvider);
      final general = container.read(generalPreferencesProvider);

      expect(selectorValue(tester, 'Daily limit'), study.maxDailyReviews);
      expect(selectorValue(tester, 'New positions per day'), study.maxNewPerDay);
      expect(selectorValue(tester, 'Target retention'), study.targetRetention);
      expect(selectorValue(tester, 'Scheduling algorithm'), study.schedulerType);
      expect(selectorValue(tester, 'Review order'), study.reviewOrder);
      expect(selectorValue(tester, 'Line continuity'), study.reviewContinuity);
      expect(selectorValue(tester, 'Transposed moves'), study.transposeScope);
      expect(selectorValue(tester, 'How you move pieces'), board.pieceShiftMethod);
      expect(selectorValue(tester, 'Castling method'), board.castlingMethod);

      // The theme selector shows the theme in force.
      final themeMode = general.themeMode;
      expect(
        selectorValue(tester, 'Theme'),
        themeMode == BackgroundThemeMode.dark || themeMode == BackgroundThemeMode.amoled,
      );
    });

    testWidgets('each switch shows the state of the preference it controls', (tester) async {
      // SPEC INV-063, INV-062. Comment shapes never leak during recall;
      // interactive targets stay tappable.
      //
      // Hand-curated mutants: srs_settings_screen.dart:309, :339, :350, :359,
      // :369, :379, :428, :437, :446, :455, :477, :500 and :534 -- a switch
      // reading the state of another setting.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SrsSettingsScreen)));

      // The states are set apart first, so a switch that shows another
      // setting's state cannot pass by accident.
      await container.read(studyPreferencesProvider.notifier).toggleAnnotations();
      await container.read(studyPreferencesProvider.notifier).toggleCollapsibleScopeGroups();
      await container.read(studyPreferencesProvider.notifier).toggleSrsDiagnostics();
      await container.read(boardPreferencesProvider.notifier).toggleEnableShapeDrawings();
      await tester.pumpAndSettle();

      expect(switchState(tester, 'Show move notation'), isTrue); // showMoveHistory
      expect(switchState(tester, 'Show arrows and circles'), isFalse); // showAnnotations
      expect(switchState(tester, 'Show notes after a move'), isTrue); // showPgnComments
      expect(switchState(tester, 'Collapsible list groups'), isFalse); // collapsibleScopeGroups
      expect(switchState(tester, 'Review Diagnostics HUD'), isTrue); // srsDiagnostics
      expect(switchState(tester, 'Dynamic repertoire mode'), isFalse); // dynamicRepertoireMode
      expect(switchState(tester, 'Board coordinates'), isTrue); // coordinates
      expect(switchState(tester, 'Piece animation'), isFalse); // pieceAnimation
      expect(switchState(tester, 'Board highlights'), isTrue); // boardHighlights
      expect(switchState(tester, 'Shape drawing'), isFalse); // enableShapeDrawings
      expect(switchState(tester, 'Premoves'), isTrue); // premoves
      expect(switchState(tester, 'Move on release'), isFalse); // moveOnRelease
      expect(switchState(tester, 'Sound'), isTrue); // isSoundEnabled
    });

    testWidgets("a switch's accessible name is the name on screen", (tester) async {
      // SPEC INV-062. Interactive targets stay tappable.
      //
      // Hand-curated mutant: srs_settings_screen.dart:340 the 'Show move
      // notation' switch announced as 'Show move history' -- a screen reader
      // then names a setting the owner cannot see on the screen.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final toggles = find.byType(SrsSwitch);
      expect(toggles, findsNWidgets(13));
      for (final element in toggles.evaluate()) {
        final semanticLabel = (element.widget as SrsSwitch).semanticLabel;
        expect(
          find.text(semanticLabel),
          findsOneWidget,
          reason: 'the switch announced as "$semanticLabel" must name the setting it belongs to',
        );
      }
    });

    testWidgets('a switch writes the preference it names and no other', (tester) async {
      // SPEC INV-063, INV-031, INV-068. Comment shapes never leak during
      // recall; the daily quota counts positions; a position is due only once
      // it has been presented.
      //
      // Hand-curated mutants: srs_settings_screen.dart:311 the dynamic
      // repertoire switch toggling the move history, :341 the 'Show move
      // notation' switch toggling the annotations, :430 the 'Board coordinates'
      // switch toggling the premoves, :536 the sound switch setting the
      // volume.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SrsSettingsScreen)));

      // 'Show move notation' -- the move history, and nothing else.
      final studyBefore = container.read(studyPreferencesProvider);
      final boardBefore = container.read(boardPreferencesProvider);
      final generalBefore = container.read(generalPreferencesProvider);
      await tester.scrollUntilVisible(settingSwitch('Show move notation'), 200);
      await tester.tap(settingSwitch('Show move notation'));
      await tester.pumpAndSettle();
      final studyAfter = container.read(studyPreferencesProvider);
      expect(studyAfter.showMoveHistory, isNot(studyBefore.showMoveHistory));
      expect(studyAfter.copyWith(showMoveHistory: studyBefore.showMoveHistory), studyBefore);
      expect(container.read(boardPreferencesProvider), boardBefore);
      expect(container.read(generalPreferencesProvider), generalBefore);

      // 'Dynamic repertoire mode' -- the dynamic repertoire, and nothing else.
      final studyBefore2 = container.read(studyPreferencesProvider);
      await tester.scrollUntilVisible(settingSwitch('Dynamic repertoire mode'), 200);
      await tester.tap(settingSwitch('Dynamic repertoire mode'));
      await tester.pumpAndSettle();
      final studyAfter2 = container.read(studyPreferencesProvider);
      expect(studyAfter2.dynamicRepertoireMode, isNot(studyBefore2.dynamicRepertoireMode));
      expect(
        studyAfter2.copyWith(dynamicRepertoireMode: studyBefore2.dynamicRepertoireMode),
        studyBefore2,
      );

      // 'Board coordinates' -- the coordinates, and nothing else.
      final boardBefore2 = container.read(boardPreferencesProvider);
      await tester.scrollUntilVisible(settingSwitch('Board coordinates'), 200);
      await tester.tap(settingSwitch('Board coordinates'));
      await tester.pumpAndSettle();
      final boardAfter2 = container.read(boardPreferencesProvider);
      expect(boardAfter2.coordinates, isNot(boardBefore2.coordinates));
      expect(boardAfter2.copyWith(coordinates: boardBefore2.coordinates), boardBefore2);

      // 'Sound' -- the sound, and nothing else.
      final generalBefore2 = container.read(generalPreferencesProvider);
      await tester.scrollUntilVisible(settingSwitch('Sound'), 200);
      await tester.tap(settingSwitch('Sound'));
      await tester.pumpAndSettle();
      final generalAfter2 = container.read(generalPreferencesProvider);
      expect(generalAfter2.isSoundEnabled, isNot(generalBefore2.isSoundEnabled));
      expect(generalAfter2.copyWith(isSoundEnabled: generalBefore2.isSoundEnabled), generalBefore2);
    });

    testWidgets('the volume slider shows the stored volume and stores the new one', (tester) async {
      // No SPEC invariant names the volume slider; the mutation round is the
      // anchor for this one.
      //
      // Hand-curated mutant: srs_settings_screen.dart:544 the slider reading a
      // fixed 1 instead of the stored volume -- the control then shows a
      // volume the owner never chose.
      final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(SrsSettingsScreen)));
      final general = container.read(generalPreferencesProvider);

      expect(tester.widget<Slider>(find.byType(Slider)).value, general.masterVolume);

      await tester.scrollUntilVisible(find.byType(Slider), 200);
      await tester.drag(find.byType(Slider), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(
        container.read(generalPreferencesProvider).masterVolume,
        lessThan(general.masterVolume),
      );
    });
  });
}
