import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'srs_test_app.dart';

void main() {
  group('SrsLiveRegion', () {
    srsPhoneTestWidgets('is a polite live region carrying the message', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, const SrsLiveRegion('Correct. Nc3.'));

      final node = tester.getSemantics(find.byType(SrsLiveRegion));
      expect(node.label, 'Correct. Nc3.');
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    srsPhoneTestWidgets('renders nothing at all while the message is empty', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, const SrsLiveRegion(''));

      expect(find.byType(SrsLiveRegion), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
      handle.dispose();
    });

    srsPhoneTestWidgets('takes no space in the layout', (tester) async {
      await pumpSrs(
        tester,
        const Column(
          children: [
            SrsLiveRegion('Correct. Nc3.'),
            SizedBox(height: 10, child: Text('after')),
          ],
        ),
      );

      final region = tester.getSize(find.byType(SrsLiveRegion));
      expect(region.height, 0.0);
      expect(region.width, 0.0);
    });

    srsPhoneTestWidgets('re-announces an identical consecutive message', (tester) async {
      // Assistive technology only speaks a live region when its content changes, so the
      // same sentence twice in a row (two identical wrong moves) must still be spoken.
      // The text node is keyed on the message, so the region reports a new node each time.
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, const SrsLiveRegion('Not this move. The repertoire move is Nc3.'));
      final first = tester.getSemantics(find.byType(SrsLiveRegion));

      await pumpSrs(tester, const SrsLiveRegion(''));
      await pumpSrs(tester, const SrsLiveRegion('Not this move. The repertoire move is Nc3.'));
      final second = tester.getSemantics(find.byType(SrsLiveRegion));

      expect(first.label, second.label);
      // Distinct nodes: the label was re-created rather than reused in place.
      expect(identical(first, second), isFalse);
      handle.dispose();
    });

    srsPhoneTestWidgets('stays silent when the message is cleared', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, const SrsLiveRegion('Correct. Nc3.'));
      await pumpSrs(tester, const SrsLiveRegion(''));

      expect(find.byType(SrsLiveRegion), findsOneWidget);
      expect(find.bySemanticsLabel('Correct. Nc3.'), findsNothing);
      handle.dispose();
    });
  });
}
