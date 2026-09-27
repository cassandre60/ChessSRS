// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../helpers/explore_hub.dart';
import '../../test_provider_scope.dart';

/// The Library sheet's Explore group, per design/docs/03-components.md §7: Analysis board,
/// Opening explorer, Board editor.
///
/// Four tests reach those destinations through [ExploreHubScreen] rather than the sheet,
/// because the sheet pops itself before pushing and so cannot be mounted as a test's `home`.
/// That makes the hub a copy of a piece of the product, and a copy can drift silently — the
/// tests would go on passing while checking a route the app no longer offers. So the two are
/// compared directly.
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

  testWidgets('the hub offers exactly the sheet Explore destinations', (tester) async {
    final sheet = await rowLabels(tester, const SrsLibrarySheet());
    final hub = await rowLabels(tester, const ExploreHubScreen());

    for (final destination in const ['Analysis board', 'Opening explorer', 'Board editor']) {
      expect(sheet, contains(destination), reason: 'the sheet must offer $destination');
      expect(hub, contains(destination), reason: 'the hub must reach $destination');
    }

    // Nothing extra in the hub: every row it has is a destination the sheet also has.
    final hubRows = hub.where((s) => s.endsWith('board') || s.contains('explorer')).toList();
    expect(hubRows.toSet(), sheet.toSet().intersection(hubRows.toSet()));
  });
}
