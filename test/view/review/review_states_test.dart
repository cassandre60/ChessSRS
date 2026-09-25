import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/review/review_states.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ProgressIndicator;

import '../../design/srs_test_app.dart';

void main() {
  group('SrsLoadingView', () {
    srsPhoneTestWidgets('shows nothing at first — no spinner, no label', (tester) async {
      await pumpSrs(tester, const SrsLoadingView());

      expect(find.byType(ProgressIndicator), findsNothing);
      expect(find.text('Loading…'), findsOneWidget);
      // Present in the tree but fully transparent until the delay elapses.
      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 0.0);
    });

    srsPhoneTestWidgets('fades the label in once the wait is noticeable', (tester) async {
      await pumpSrs(tester, const SrsLoadingView());

      await tester.pump(kSrsLoadingLabelDelay);
      await tester.pumpAndSettle();

      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1.0);
    });

    srsPhoneTestWidgets('collapses to an instant state change under reduced motion', (
      tester,
    ) async {
      await pumpSrs(
        tester,
        const MediaQuery(data: MediaQueryData(disableAnimations: true), child: SrsLoadingView()),
      );

      await tester.pump(kSrsLoadingLabelDelay);
      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.duration, Duration.zero);
    });

    srsPhoneTestWidgets('renders the label immediately when there is no delay', (tester) async {
      await pumpSrs(tester, const SrsLoadingView(delay: Duration.zero));
      await tester.pump();

      final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1.0);
    });

    srsPhoneTestWidgets('is decorative to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, const SrsLoadingView());
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Loading…'), findsNothing);
      handle.dispose();
    });
  });

  group('SrsErrorView', () {
    srsPhoneTestWidgets('states what happened without leaking the exception', (tester) async {
      await pumpSrs(
        tester,
        const SrsErrorView(
          detail: kSrsReviewLoadFailedDetail,
          onRetry: _noop,
          onCopyDetails: _noop,
        ),
      );

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.text(kSrsReviewLoadFailedDetail), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Copy details'), findsOneWidget);
    });

    srsPhoneTestWidgets('reports both actions', (tester) async {
      var retried = 0;
      var copied = 0;
      await pumpSrs(
        tester,
        SrsErrorView(
          detail: kSrsReviewLoadFailedDetail,
          onRetry: () => retried++,
          onCopyDetails: () => copied++,
        ),
      );

      await tester.tap(find.text('Try again'));
      await tester.tap(find.text('Copy details'));
      expect(retried, 1);
      expect(copied, 1);
    });

    srsPhoneTestWidgets('offers only the actions the caller wires up', (tester) async {
      await pumpSrs(tester, const SrsErrorView(detail: 'Reviews could not be loaded.'));

      expect(find.text('Try again'), findsNothing);
      expect(find.text('Copy details'), findsNothing);
    });

    srsPhoneTestWidgets('Try again clears the 44px touch target', (tester) async {
      await pumpSrs(tester, const SrsErrorView(detail: kSrsReviewLoadFailedDetail, onRetry: _noop));

      expect(tester.getSize(find.byType(SrsPillButton)).height, greaterThanOrEqualTo(44));
    });
  });

  group('copySrsErrorDetails', () {
    srsPhoneTestWidgets('puts the technical detail on the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await copySrsErrorDetails('StateError: bad thing\n#0 frame');
      expect(copied, ['StateError: bad thing\n#0 frame']);
    });
  });
}

void _noop() {}
