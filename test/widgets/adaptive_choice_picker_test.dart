import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoActionSheet, CupertinoDialogAction, CupertinoPicker;
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

    // Every platform taps. This used to branch: on iOS a long list was a `CupertinoPicker` wheel
    // that selected by scrolling and stopping, so the same list needed a different gesture
    // depending on the device. `00-agent-brief.md` open decision 4 resolved 2026-09-28 keeps
    // platform behaviours but not platform-specific looks, and the wheel was both.
    await tester.tap(find.text('three'));
    expect(selectedItems, [TestEnumLarge.three]);
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

    // With small choices, the Diagram dialog; no platform difference remains.
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

  group('one look on every platform', () {
    // `00-agent-brief.md` open decision 4, resolved 2026-09-28: keep platform *behaviours*, not
    // platform-specific *looks*. The picker's Android path was already the Diagram one; iOS still
    // got a `CupertinoActionSheet`, or a `CupertinoPicker` wheel past ten choices. The two tests
    // above asserted that iOS behaviour, which is the point — it was the only thing keeping the
    // branch alive, and nothing said the two looks were meant to differ.
    Future<void> openPicker(WidgetTester tester) async {
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
                      labelBuilder: (choice) => Text(choice.name),
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

    testWidgets('iOS gets the Diagram dialog, not a Cupertino sheet', (tester) async {
      await openPicker(tester);

      expect(find.byType(SrsDialog), findsOneWidget);
      expect(find.byType(CupertinoActionSheet), findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('a long list on iOS is a scrollable dialog, not a picker wheel', (tester) async {
      // The Cupertino wheel was the >10 branch. A wheel selects by scrolling and stopping, which
      // is a behaviour difference rather than only a look, and it made long lists unreachable by
      // tapping. The Diagram dialog caps and scrolls, so every option is reachable the same way
      // on every platform.
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
                      choices: TestEnumLarge.values,
                      selectedItem: TestEnumLarge.one,
                      labelBuilder: (choice) => Text(choice.name),
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

      expect(find.byType(CupertinoPicker), findsNothing);
      expect(find.byType(SrsDialog), findsOneWidget);
      // The last option is reachable, which the wheel made a matter of scroll-and-stop.
      await tester.scrollUntilVisible(find.text('eleven'), 80);
      expect(find.text('eleven'), findsOneWidget);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
  });

  group('one look for the multi-select too', () {
    // The second picker in this file was `showAdaptiveDialog` + `AlertDialog.adaptive` +
    // `CheckboxListTile.adaptive`, with `CupertinoDialogAction` buttons on iOS. It backs the
    // board settings "submit move" row, so it is a preference a user can actually reach.
    Future<void> openMulti(WidgetTester tester) async {
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
                    onPressed: () => showMultipleChoicesPicker(
                      context,
                      choices: TestEnumSmall.values,
                      selectedItems: const {TestEnumSmall.one},
                      labelBuilder: (choice) => Text(choice.name),
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

    testWidgets('iOS gets an SrsDialog, not an adaptive Material dialog', (tester) async {
      await openMulti(tester);

      expect(find.byType(SrsDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CupertinoDialogAction), findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('marks every selected choice, not only the first', (tester) async {
      await openMulti(tester);

      final marked = tester
          .widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow))
          .where((r) => r.selected ?? false)
          .toList();
      // A single-select marker on a multi-select list has to mean "included", so more than one row
      // can carry it. One here would mean the others silently dropped their selection.
      expect(marked, hasLength(1), reason: 'only `one` was selected to begin with');
    });

    testWidgets('tapping a row toggles it and OK returns the set', (tester) async {
      Set<TestEnumSmall>? result;
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
                    onPressed: () async {
                      result = await showMultipleChoicesPicker(
                        context,
                        choices: TestEnumSmall.values,
                        selectedItems: const {TestEnumSmall.one},
                        labelBuilder: (choice) => Text(choice.name),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show picker'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, {TestEnumSmall.one, TestEnumSmall.two});
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
