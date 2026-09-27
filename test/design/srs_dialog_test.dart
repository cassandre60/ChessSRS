import 'package:chess_srs/src/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
// material_ui, not flutter/material: the app is built against that fork, and its TextField
// looks for a Material from the same library. Mixing the two fails with "No Material widget
// found" even though a Material is right there in the tree.
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

/// Opens [child] through [SrsDialog.show], the way callers use it, rather than nesting a
/// `Dialog` in a `Center` -- the latter measures differently and hid a real right-alignment bug.
Future<void> openDialog(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => SrsDialog.show<void>(context: context, builder: (_) => child),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// design/docs/03-components.md: "centered card on `surface`, radius 16, padding 24, max width
// 400 ... title 20/600; body 15 `ink2`; actions right-aligned". The demo's `.dlg` gives the
// width as min(400px, 100% - 32px).
/// The painted card, not the [SrsDialog] element itself: `Dialog` is a full-screen route widget,
/// so its own rect spans the whole screen.
Rect cardRect(WidgetTester tester) => tester.getRect(find.byKey(SrsDialog.cardKey));

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsDialog', () {
    testWidgets('caps the card at 400px and centres it', (tester) async {
      await openDialog(
        tester,
        const SrsDialog(title: 'Rename repertoire', body: 'A sentence of body copy.'),
      );

      final card = cardRect(tester);
      final screen = tester.getSize(find.byType(Scaffold));
      expect(card.width, lessThanOrEqualTo(400));
      expect((card.center.dx - screen.width / 2).abs(), lessThanOrEqualTo(1));
    });

    testWidgets('sets the title at 20px weight 600', (tester) async {
      await openDialog(tester, const SrsDialog(title: 'Delete repertoire?'));

      final title = tester.widget<Text>(find.text('Delete repertoire?'));
      expect(title.style?.fontSize, 20);
      expect(title.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('sets the body at 15px', (tester) async {
      await openDialog(tester, const SrsDialog(body: 'Body copy.'));

      expect(tester.widget<Text>(find.text('Body copy.')).style?.fontSize, 15);
    });

    testWidgets('pads the card by 24', (tester) async {
      await openDialog(tester, const SrsDialog(title: 'Delete', body: 'Cannot be undone.'));

      final card = cardRect(tester);
      final title = tester.getRect(find.text('Delete'));
      expect(title.left - card.left, closeTo(24, 1));
      expect(title.top - card.top, closeTo(24, 1));
    });

    testWidgets('right-aligns the actions against the card edge', (tester) async {
      await openDialog(
        tester,
        const SrsDialog(
          title: 'Delete',
          body: 'Cannot be undone.',
          actions: [
            SrsTextButton(label: 'Cancel', onPressed: _noop),
            SrsPillButton(label: 'Delete', onPressed: _noop),
          ],
        ),
      );

      final card = cardRect(tester);
      // The pill, not its label: the title is also 'Delete', and the label's own 12px button
      // padding would be counted as card padding.
      final pill = tester.getRect(find.widgetWithText(SrsPillButton, 'Delete'));
      // WrapAlignment.end: the block hugs the card's right padding edge.
      expect(card.right - pill.right, closeTo(24, 1));
    });

    testWidgets('prefers content over body when both are given', (tester) async {
      await openDialog(
        tester,
        const SrsDialog(title: 'Rename', body: 'ignored', content: TextField()),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('ignored'), findsNothing);
    });

    testWidgets('omits the body gap when there is no title', (tester) async {
      await openDialog(tester, const SrsDialog(body: 'No title here.'));

      final card = cardRect(tester);
      final body = tester.getRect(find.text('No title here.'));
      expect(body.top - card.top, closeTo(24, 1));
    });
  });
}

void _noop() {}
