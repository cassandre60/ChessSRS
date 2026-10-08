import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/settings/board_choice_screen.dart';
import 'package:chess_srs/src/view/settings/piece_set_screen.dart';
import 'package:chess_srs/src/view/settings/sound_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// These three were Material `ListTile` lists behind a `PlatformAppBar` and had no test at all.
///
/// The assertions are deliberately about the frame rather than the contents: that each screen
/// uses the Diagram head and rows, and that every option is reachable. Asserting the exact set
/// of board themes or piece sets would break on every upstream addition without catching a
/// regression, and asserting the *absence* of `PlatformAppBar` would stop compiling the moment
/// the reskin deletes the type.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Future<void> open(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: screen));
    await tester.pumpAndSettle();
  }

  group('board choice', () {
    testWidgets('uses the Diagram head and marks the selected theme', (tester) async {
      await open(tester, const BoardChoiceScreen());

      expect(find.byType(SrsPageHead), findsOneWidget);
      expect(find.byType(SrsSettingsRow), findsWidgets);

      // Exactly one row is marked chosen.
      final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(rows.where((r) => r.selected ?? false), hasLength(1));

      // The thumbnail is shown, so the choice is not made blind.
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('every theme is reachable by tapping its row', (tester) async {
      await open(tester, const BoardChoiceScreen());
      final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(rows.length, greaterThan(1));

      await tester.tap(find.byType(SrsSettingsRow).last);
      await tester.pumpAndSettle();

      // Tapping the last row moves the marker, so the tap was not swallowed by a clipped row.
      final after = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(after.last.selected, isTrue);
    });
  });

  group('piece set', () {
    testWidgets('uses the Diagram head and previews each set', (tester) async {
      await open(tester, const PieceSetScreen());

      expect(find.byType(SrsPageHead), findsOneWidget);
      expect(find.byType(Image), findsWidgets, reason: 'each row previews its pieces');

      final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(rows.where((r) => r.selected ?? false), hasLength(1));
    });
  });

  group('curated choices', () {
    // The picker shows only the curated themes (Diagram + Wood + Paper + Slate).
    // Fails on base, which listed all 28 Lichess themes.
    testWidgets('board choice shows only the curated themes', (tester) async {
      await open(tester, const BoardChoiceScreen());

      final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(rows.length, 4);

      final labels = rows.map((r) => r.label).toSet();
      expect(labels, contains('Diagram'));
      expect(labels, contains('Wood'));
      expect(labels, contains('Paper'));
      expect(labels, contains('Slate'));
    });

    // Fails on base, which listed all ~40 piece sets.
    testWidgets('piece set shows only the curated sets', (tester) async {
      await open(tester, const PieceSetScreen());

      final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
      expect(rows.length, 5);
    });
  });

  group('sound settings', () {
    testWidgets('uses the Diagram head, a volume row and a segmented theme control', (
      tester,
    ) async {
      await open(tester, const SoundSettingsScreen());

      expect(find.byType(SrsPageHead), findsOneWidget);
      expect(find.text('Master volume'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(SrsSegmented<String>), findsOneWidget);

      // The row's percentage is the slider's value, not a hardcoded default -- asserting "50%"
      // would only ever be true by coincidence.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(
        find.text(volumeLabel(slider.value)),
        findsOneWidget,
        reason: 'the row label must be derived from the slider, not restated',
      );
    });

    testWidgets('the volume slider is notched, so its label is reachable', (tester) async {
      await open(tester, const SoundSettingsScreen());

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, isNotNull, reason: 'a continuous slider cannot land on 50%');
    });
  });
}
