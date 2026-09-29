// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/view/analysis/analysis_hub_screen.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// Where the Library sheet's Explore destinations live, per design/docs/03-components.md §7 and
/// owner decision 2026-09-28 on `00-agent-brief.md` open decision 1.
///
/// This file used to mount a test-only `ExploreHubScreen` and compare it against the sheet, to stop
/// the copy drifting from the product. `AnalysisHubScreen` is now real product code, so the copy is
/// gone and with it the drift it was guarding against. What is worth pinning now is the move
/// itself: the sheet must offer the hub, and must no longer offer the three tools directly —
/// otherwise the destinations are reachable by two paths, or by none.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Future<List<String>> rowLabels(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: home));
    await tester.pumpAndSettle();
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  const destinations = ['Analysis board', 'Opening explorer', 'Board editor'];

  testWidgets('the sheet offers the hub, not the tools it now contains', (tester) async {
    final sheet = await rowLabels(tester, const SrsLibrarySheet());

    expect(sheet, contains('Analysis'), reason: 'the sheet must offer the hub');
    for (final destination in destinations) {
      expect(
        sheet,
        isNot(contains(destination)),
        reason: '"$destination" moved into the hub; leaving it here gives two paths to one screen',
      );
    }
  });

  testWidgets('the hub offers each destination the sheet used to', (tester) async {
    final hub = await rowLabels(tester, const AnalysisHubScreen());

    for (final destination in destinations) {
      expect(hub, contains(destination), reason: 'the hub must reach $destination');
    }
  });

  testWidgets('study management lives in the scope drawer, not the Library sheet', (tester) async {
    final sheet = await rowLabels(tester, const SrsLibrarySheet());

    expect(
      sheet,
      isNot(contains('Import PGN')),
      reason: 'Import PGN lives in the scope drawer pill; duplicating it here gives two paths',
    );
    expect(
      sheet,
      isNot(contains('Studies & Repertoires')),
      reason: 'scope button already opens the drawer; this row was a redundant hop',
    );
    // Guard the survivors so a future edit cannot empty the sheet silently.
    expect(sheet, contains('Analysis'));
    expect(sheet, contains('Settings'));
  });
}
