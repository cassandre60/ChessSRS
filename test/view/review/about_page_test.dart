// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/review/about_page.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// The About page is now reachable from the Library sheet, where it replaced `showLicensePage`
/// — the stock page lists package licences and says nothing about the fork, while
/// `AGENTS.md` §7 requires attributing the GPL-3.0 code this is built on.
///
/// So the assertion is the attribution itself: if a dependency is dropped or relicensed, the
/// licence page goes stale silently otherwise, and nothing else in the build would notice.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  testWidgets('names every GPL dependency the fork is built on', (tester) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: const AboutPage()));
    await tester.pumpAndSettle();

    for (final (dependency, licence) in const [
      ('Lichess Mobile', 'GPL-3.0'),
      ('chessground', 'GPL-3.0'),
      ('dartchess', 'GPL-3.0'),
      ('Instrument Sans', 'SIL Open Font Licence 1.1'),
      ('Newsreader', 'SIL Open Font Licence 1.1'),
    ]) {
      expect(
        find.text(dependency),
        findsOneWidget,
        reason: '$dependency is used by this app and must be attributed',
      );
      expect(find.text(licence), findsWidgets);
    }
  });

  testWidgets('uses the Diagram head, since it is a screen the user reaches', (tester) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: const AboutPage()));
    await tester.pumpAndSettle();

    expect(find.byType(SrsPageHead), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets("the Library sheet's About row lands here, not on the stock licence page", (
    tester,
  ) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: const SrsLibrarySheet()));
    await tester.pumpAndSettle();

    expect(find.text('About and licences'), findsOneWidget);
    expect(find.byType(AboutPage), findsNothing);

    await tester.tap(find.text('About and licences'));
    await tester.pumpAndSettle();

    // The row used to open showLicensePage, which is a Material dialog listing package
    // licences. This is the change the wiring exists for, so it is the thing to assert.
    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.byType(LicensePage), findsNothing);
  });
}
