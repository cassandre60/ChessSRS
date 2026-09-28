// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActionSheet;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The action sheet behind `Menu` in the board editor, `Variant`, and eight other call sites.
///
/// It branched on platform: a `CupertinoActionSheet` on iOS, a Material `Dialog` elsewhere. So the
/// same menu -- Start position, Load position, Variant, Continue from here, Clear board -- was
/// two different-looking things on the two screens decision 1 just put behind the Analysis hub.
///
/// `00-agent-brief.md` open decision 4, resolved 2026-09-28.
void main() {
  Future<void> openSheet(
    WidgetTester tester, {
    required List<BottomSheetAction> actions,
    Widget? title,
    String? tapAction,
  }) async {
    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAdaptiveActionSheet<void>(
                    context: context,
                    title: title,
                    actions: actions,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (tapAction != null) {
      await tester.tap(find.text(tapAction));
      await tester.pumpAndSettle();
    }
  }

  group('one look on every platform', () {
    testWidgets('iOS gets a Diagram sheet, not a Cupertino one', (tester) async {
      await openSheet(
        tester,
        actions: [BottomSheetAction(makeLabel: (_) => const Text('Clear board'), onPressed: () {})],
      );

      expect(find.byType(SrsSheetSurface), findsOneWidget);
      expect(find.byType(CupertinoActionSheet), findsNothing);
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('the sheet surface is the same on Android', (tester) async {
      await openSheet(
        tester,
        actions: [BottomSheetAction(makeLabel: (_) => const Text('Clear board'), onPressed: () {})],
      );

      expect(find.byType(SrsSheetSurface), findsOneWidget);
    }, variant: const TargetPlatformVariant({TargetPlatform.android}));
  });

  group('behaviour the platform branch used to differ on', () {
    testWidgets('tapping an action fires it and dismisses', (tester) async {
      var fired = 0;
      await openSheet(
        tester,
        actions: [
          BottomSheetAction(makeLabel: (_) => const Text('Clear board'), onPressed: () => fired++),
        ],
        tapAction: 'Clear board',
      );

      expect(fired, 1);
      expect(find.byType(SrsSheetSurface), findsNothing, reason: 'the sheet closes on press');
    }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));

    testWidgets('dismissOnPress: false keeps the sheet open', (tester) async {
      var fired = 0;
      await openSheet(
        tester,
        actions: [
          BottomSheetAction(
            makeLabel: (_) => const Text('Clear board'),
            onPressed: () => fired++,
            dismissOnPress: false,
          ),
        ],
        tapAction: 'Clear board',
      );

      // The board editor's `Continue from here` opens a second sheet from the first, and the first
      // has to survive it. Both old implementations honoured this, and losing it is the obvious way
      // to get this conversion wrong.
      expect(fired, 1);
      expect(find.byType(SrsSheetSurface), findsOneWidget);
    });

    testWidgets('a rich label is rendered, not flattened to its text', (tester) async {
      // `labelBuilder` returns a Widget, and several call sites pass rich labels. Flattening to
      // `.data` drops a `Text.rich` entirely -- `.data` is null on it -- and the row renders blank.
      await openSheet(
        tester,
        actions: [
          BottomSheetAction(
            makeLabel: (_) => const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Chess960'),
                  WidgetSpan(child: SizedBox(width: 12, height: 12)),
                ],
              ),
            ),
            onPressed: () {},
          ),
        ],
      );

      expect(find.textContaining('Chess960'), findsOneWidget);
    });

    testWidgets('a leading widget and a trailing widget both survive', (tester) async {
      // The old Material branch rendered these and the Cupertino one dropped them, so the same
      // action looked different *within* the platform branch too.
      await openSheet(
        tester,
        actions: [
          BottomSheetAction(
            makeLabel: (_) => const Text('With both'),
            onPressed: () {},
            leading: const Icon(Icons.abc),
            trailing: const Icon(Icons.arrow_forward),
          ),
        ],
      );

      expect(find.byIcon(Icons.abc), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('the title renders above the rows', (tester) async {
      await openSheet(
        tester,
        title: const Text('Start position'),
        actions: [BottomSheetAction(makeLabel: (_) => const Text('Clear board'), onPressed: () {})],
      );

      expect(find.text('Start position'), findsOneWidget);
      expect(find.text('Clear board'), findsOneWidget);
    });
  });
}
