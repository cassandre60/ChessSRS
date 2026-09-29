// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// Owner report 2026-09-29 Q8: on a small phone the study actions sheet
/// clipped its last rows — Delete was unreachable because the sheet's body
/// was a plain Column with no scroll. This pins Delete reachable by scroll
/// on a short viewport.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  testWidgets('Delete stays reachable by scrolling on a small phone', (tester) async {
    var deleted = false;
    const study = Study(id: 's1', title: 'My repertoire');

    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(360, 500),
        home: StudyActionsSheet(
          study: study,
          onDismiss: () {},
          onTogglePause: () {},
          onChapters: () {},
          onAnalyze: () {},
          onPractice: () {},
          onExport: () {},
          onRename: () {},
          onDelete: () => deleted = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Without a scrollable body this throws UnableToFind / stays hidden.
    await tester.scrollUntilVisible(find.text('Delete'), 200);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue, reason: 'Delete must be tappable, not clipped off-screen');
  });
}
