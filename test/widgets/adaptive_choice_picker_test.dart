import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test_helpers.dart';

enum TestEnumLarge { one, two, three, four, five, six, seven, eight, nine, ten, eleven }

enum TestEnumSmall { one, two, three }

void main() {
  testWidgets('showChoicePicker call onSelectedItemChanged (large choices)', (
    WidgetTester tester,
  ) async {
    final List<TestEnumLarge> selectedItems = <TestEnumLarge>[];

    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: ElevatedButton(
                    child: const Text('Show picker'),
                    onPressed: () {
                      showChoicePicker(
                        context,
                        choices: TestEnumLarge.values,
                        selectedItem: TestEnumLarge.one,
                        labelBuilder: (choice) => Text(choice.name),
                        onSelectedItemChanged: (choice) {
                          selectedItems.add(choice);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show picker'));
    await tester.pumpAndSettle();

    // with large choices (>= 6), on iOS the picker scrolls
    if (debugDefaultTargetPlatformOverride == TargetPlatform.iOS) {
      // scroll 2 items (2 * 40 height)
      await tester.drag(
        find.text('one'),
        const Offset(0.0, -80.0),
        warnIfMissed: false,
      ); // has an IgnorePointer
      expect(selectedItems, <TestEnumLarge>[]);
      await tester.pumpAndSettle(); // await for scroll ends
      // only third item is selected as the scroll ends
      expect(selectedItems, [TestEnumLarge.three]);
    } else {
      await tester.tap(find.text('three'));
      expect(selectedItems, [TestEnumLarge.three]);
    }
  }, variant: kPlatformVariant);

  testWidgets('showChoicePicker call onSelectedItemChanged (small choices)', (
    WidgetTester tester,
  ) async {
    final List<TestEnumSmall> selectedItems = <TestEnumSmall>[];

    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: ElevatedButton(
                    child: const Text('Show picker'),
                    onPressed: () {
                      showChoicePicker(
                        context,
                        choices: TestEnumSmall.values,
                        selectedItem: TestEnumSmall.one,
                        labelBuilder: (choice) => Text(choice.name),
                        onSelectedItemChanged: (choice) {
                          selectedItems.add(choice);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show picker'));
    await tester.pumpAndSettle();

    // With small choices, on iOS the picker is an action sheet
    await tester.tap(find.text('three'));
    expect(selectedItems, [TestEnumSmall.three]);
  }, variant: kPlatformVariant);

  group('the Diagram picker', () {
    Future<void> openPicker(
      WidgetTester tester,
      Widget Function(TestEnumSmall) labelBuilder,
    ) async {
      await tester.pumpWidget(
        SrsTheme(
          colors: SrsColors.light(SrsAccent.ultramarine),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    child: const Text('Show picker'),
                    onPressed: () => showChoicePicker(
                      context,
                      choices: TestEnumSmall.values,
                      selectedItem: TestEnumSmall.one,
                      labelBuilder: labelBuilder,
                      onSelectedItemChanged: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show picker'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens an SrsDialog, not a Material AlertDialog', (tester) async {
      await openPicker(tester, (choice) => Text(choice.name));

      expect(find.byType(SrsDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('marks exactly the selected choice', (tester) async {
      await openPicker(tester, (choice) => Text(choice.name));

      final marked = tester
          .widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow))
          .where((r) => r.selected ?? false)
          .toList();
      expect(marked, hasLength(1));
    });

    testWidgets('renders a rich label with its swatch intact', (tester) async {
      // The shape-colour picker passes a Text.rich carrying a colour swatch. Flattening a label
      // widget to its text would drop the swatch and, for a Text.rich, the text too, since
      // `.data` is null on it -- the row rendered blank.
      var built = 0;
      await openPicker(tester, (choice) {
        built++;
        return const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Green'),
              WidgetSpan(child: SizedBox(width: 15, height: 15)),
            ],
          ),
        );
      });

      expect(built, TestEnumSmall.values.length, reason: 'every choice gets a label');
      expect(find.textContaining('Green'), findsNWidgets(TestEnumSmall.values.length));
    });
  });

  testWidgets('a short list of tall labels still fits on screen', (tester) async {
    // The card used to size itself to its content, so a nine-item list of two-line labels --
    // the chess variants, each a name and a description -- filled the whole screen and the last
    // option could not be reached at all.
    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  child: const Text('Show picker'),
                  onPressed: () => showChoicePicker<TestEnumSmall>(
                    context,
                    choices: TestEnumSmall.values,
                    selectedItem: TestEnumSmall.one,
                    labelBuilder: (choice) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [Text(choice.name), const Text('a description line')],
                    ),
                    onSelectedItemChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show picker'));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(SrsDialog.cardKey));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(
      card.height,
      lessThanOrEqualTo(screen.height),
      reason: 'the card must not grow past the screen it is shown on',
    );
    // And the last option is reachable, which is the point of capping it.
    await tester.scrollUntilVisible(find.text('three'), 80);
    expect(find.text('three'), findsOneWidget);
  });
}
