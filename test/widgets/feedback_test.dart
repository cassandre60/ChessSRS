import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signal_strength_indicator/signal_strength_indicator.dart';

class FakeSocketPingNotifier extends SocketPingNotifier {
  FakeSocketPingNotifier(this.state, {required Uri? route}) : super(route);

  @override
  final SocketPingState state;

  @override
  SocketPingState build({Uri? route}) => state;
}

Widget pingTestApp(SocketPingState state, Widget child) {
  return ProviderScope(
    overrides: [
      socketPingProvider.overrideWith2((Uri? uri) => FakeSocketPingNotifier(state, route: uri)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('LagIndicator', () {
    // lagRating=0 requires a size >= 30 to avoid SpinKitThreeBounce overflow
    // (SpinKitThreeBounce internally sizes to Size(bounceSize * 2, bounceSize) = Size(30, 15))
    testWidgets('shows loading indicator when lagRating is 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LagIndicator(lagRating: 0, size: 40.0))),
      );

      expect(find.byType(SpinKitThreeBounce), findsOneWidget);
      expect(find.byType(SignalStrengthIndicator), findsOneWidget);
    });

    testWidgets('does not show loading indicator when lagRating is 0 but inactive', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LagIndicator(lagRating: 0, isActive: false, size: 40.0)),
        ),
      );

      expect(find.byType(SpinKitThreeBounce), findsNothing);
      expect(find.byType(SignalStrengthIndicator), findsOneWidget);
    });

    testWidgets('does not show loading indicator when lagRating is > 0', (
      WidgetTester tester,
    ) async {
      for (final rating in [1, 2, 3, 4]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: LagIndicator(lagRating: rating)),
          ),
        );

        expect(find.byType(SpinKitThreeBounce), findsNothing, reason: 'lagRating=$rating');
        expect(find.byType(SignalStrengthIndicator), findsOneWidget, reason: 'lagRating=$rating');
      }
    });

    testWidgets('respects the size parameter', (WidgetTester tester) async {
      const testSize = 32.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LagIndicator(lagRating: 2, size: testSize)),
        ),
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, testSize);
      expect(sizedBox.height, testSize);
    });

    testWidgets('uses default size of 20.0', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LagIndicator(lagRating: 1))));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 20.0);
      expect(sizedBox.height, 20.0);
    });

    test('throws assertion for lagRating below 0', () {
      expect(() => LagIndicator(lagRating: -1), throwsA(isA<AssertionError>()));
    });

    test('throws assertion for lagRating above 4', () {
      expect(() => LagIndicator(lagRating: 5), throwsA(isA<AssertionError>()));
    });
  });

  group('SocketPingRatingListTile', () {
    testWidgets('shows the offline label and stays disabled while the socket has no lag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        pingTestApp((
          averageLag: Duration.zero,
          rating: 0,
          isActive: false,
        ), const Scaffold(body: SocketPingRatingListTile())),
      );

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.enabled, isFalse);
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('shows the ping lag and stays enabled while the socket has lag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        pingTestApp((
          averageLag: const Duration(milliseconds: 42),
          rating: 1,
          isActive: true,
        ), const Scaffold(body: SocketPingRatingListTile())),
      );

      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.enabled, isTrue);
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'PING 42 ms'),
        findsOneWidget,
      );
    });
  });

  group('SocketPingRatingIcon', () {
    testWidgets('popover shows the unknown marker while the socket has no lag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        pingTestApp((
          averageLag: Duration.zero,
          rating: 0,
          isActive: false,
        ), const Scaffold(body: SocketPingRatingIcon())),
      );

      await tester.tap(find.byType(SocketPingRatingIcon));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'PING: ? ms'),
        findsOneWidget,
      );
    });

    testWidgets('popover shows the measured lag while the socket has lag', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        pingTestApp((
          averageLag: const Duration(milliseconds: 42),
          rating: 1,
          isActive: true,
        ), const Scaffold(body: SocketPingRatingIcon())),
      );

      await tester.tap(find.byType(SocketPingRatingIcon));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == 'PING: 42 ms'),
        findsOneWidget,
      );
    });
  });

  group('FeedbackTile', () {
    testWidgets('renders the title when leading is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: FeedbackTile(title: Text('Hello'))),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(SizedBox), findsNothing);
    });

    testWidgets('renders the leading and its spacer when leading is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FeedbackTile(leading: Icon(Icons.info), title: Text('Hello')),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byIcon(Icons.info), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is SizedBox && w.width == 16.0), findsOneWidget);
    });
  });
}
