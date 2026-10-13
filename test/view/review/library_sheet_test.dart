// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

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

  testWidgets('the sheet does not offer Analysis or the tools it contains', (tester) async {
    final sheet = await rowLabels(tester, const SrsLibrarySheet());

    expect(
      sheet,
      isNot(contains('Analysis')),
      reason: 'Analysis is reached directly via repertoires in the scope drawer',
    );
    for (final destination in destinations) {
      expect(
        sheet,
        isNot(contains(destination)),
        reason: '"$destination" is not in the library sheet',
      );
    }
  });

  // Rewritten when the Explore hub was deleted for having no caller in lib/. This used to assert
  // that the hub offered the three destinations the sheet had given up. The hub is gone, but the
  // property it guarded is not: each destination must still be reachable from a live surface.
  // Asserted against the source, because the routing lives in the openers rather than in a
  // screen we can mount — and a mount-based version would pass even if every opener were deleted.
  test('the destinations the sheet gave up are still reachable from live surfaces', () {
    final actions = File('lib/src/view/analysis/analysis_actions.dart').readAsStringSync();
    expect(
      actions,
      contains('BoardEditorScreen.buildRoute'),
      reason: 'the board editor must stay reachable without the hub',
    );

    // The board editor's opener is imported by StudyScreen's bottom bar, which the scope drawer
    // pushes, so the destination is reachable and not merely defined.
    final bottomBar = File('lib/src/view/study/study_bottom_bar.dart').readAsStringSync();
    expect(bottomBar, contains('analysis_actions.dart'));
    expect(
      bottomBar,
      contains('AnalysisScreen.buildRoute'),
      reason: 'the analysis board must stay reachable without the hub',
    );

    // The opening explorer survives as the inline panel inside the analysis board, which is why
    // the standalone explorer screen could go without taking the feature with it.
    final analysisScreen = File('lib/src/view/analysis/analysis_screen.dart').readAsStringSync();
    expect(analysisScreen, contains('ExplorerView('));
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
    expect(sheet, isNot(contains('Analysis')));
    expect(sheet, contains('Settings'));
    expect(sheet, contains('About and licences'));
  });
}
