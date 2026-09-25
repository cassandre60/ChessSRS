import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'srs_test_app.dart';

/// A button that shows a toast, so the helper has a BuildContext with an Overlay under it.
class _ToastLauncher extends StatelessWidget {
  const _ToastLauncher(this.message, {this.label = 'Go'});

  final String message;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: SrsTextButton(label: label, onPressed: () => showSrsToast(context, message)),
  );
}

/// Two launchers with distinct labels, for the replace-not-stack cases.
class _TwoLaunchers extends StatelessWidget {
  const _TwoLaunchers();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      _ToastLauncher('First message', label: 'First'),
      _ToastLauncher('Second message', label: 'Second'),
    ],
  );
}

void main() {
  group('showSrsToast', () {
    srsPhoneTestWidgets('renders an ink pill with the message on the ground', (tester) async {
      await pumpSrs(tester, const _ToastLauncher('Study deleted.'));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.byType(SrsToast), findsOneWidget);

      final c = srsTestColors();
      final pill = tester.widget<Container>(find.byKey(kSrsToastPillKey));
      final decoration = pill.decoration! as BoxDecoration;
      expect(decoration.color, c.ink);
      expect(decoration.borderRadius, BorderRadius.circular(999));

      final label = tester.widget<Text>(find.text('Study deleted.'));
      expect(label.style?.color, c.ground);
      expect(label.style?.fontSize, 14.0);
      expect(label.style?.fontWeight, FontWeight.w500);
    });

    srsPhoneTestWidgets('sits 24 from the bottom, centred', (tester) async {
      await pumpSrs(tester, const _ToastLauncher('Copied to clipboard.'));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      final pillRect = tester.getRect(find.byKey(kSrsToastPillKey));
      expect(kSrsPhoneSurface.height - pillRect.bottom, 24.0);
      expect(pillRect.center.dx, closeTo(kSrsPhoneSurface.width / 2, 0.5));
    });

    srsPhoneTestWidgets('never takes pointer input', (tester) async {
      await pumpSrs(tester, const _ToastLauncher('Renamed.'));

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.byType(IgnorePointer), findsWidgets);
      // A tap in the middle of the toast must reach whatever is behind it, not the toast.
      final behind = tester.getCenter(find.text('Go'));
      await tester.tapAt(behind);
      await tester.pump();
    });

    srsPhoneTestWidgets('disappears on its own after the visible window', (tester) async {
      await pumpSrs(tester, const _ToastLauncher('Saved sample.pgn'));

      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.byType(SrsToast), findsOneWidget);

      await tester.pump(SrsMotion.toastVisible);
      await tester.pumpAndSettle();
      expect(find.byType(SrsToast), findsNothing);
    });

    srsPhoneTestWidgets('replaces the visible message instead of stacking', (tester) async {
      await pumpSrs(tester, const _TwoLaunchers());

      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(find.byType(SrsToast), findsOneWidget);

      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(find.byType(SrsToast), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text('First message'), findsNothing);
    });

    srsPhoneTestWidgets('restarts the timer when a new message arrives', (tester) async {
      await pumpSrs(tester, const _TwoLaunchers());

      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 2000));

      // Still visible even though the first toast's own window would have expired.
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.byType(SrsToast), findsOneWidget);

      await tester.pump(SrsMotion.toastVisible);
      await tester.pumpAndSettle();
      expect(find.byType(SrsToast), findsNothing);
    });
  });
}
