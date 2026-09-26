// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsPageHead (demo .set-head)', () {
    testWidgets('renders destination label, fires back, shows trailing', (tester) async {
      var backed = false;
      final app = await makeTestProviderScopeApp(
        tester,
        home: SrsPageHead(
          label: 'Review',
          onBack: () => backed = true,
          trailing: const Text('Trailing'),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Trailing'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(backed, isTrue);
    });

    testWidgets('hides trailing when absent and disables without onBack', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsPageHead(label: 'Library', onBack: null),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(SrsPageHead), findsOneWidget);
    });
  });
}
