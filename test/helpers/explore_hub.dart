// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_screen.dart';
import 'package:chess_srs/src/widgets/platform.dart';
import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';

/// A plain screen carrying the Library sheet's *Explore* rows, for tests that need to reach
/// those destinations and come back.
///
/// This was `MoreTabScreen`, which lived in `lib/` and was reachable only from the two-tab
/// switcher. With that switcher gone it was unreachable in the app and alive only in tests, so
/// it belongs here rather than in `lib/`.
///
/// It is not `SrsLibrarySheet` itself: that is a sheet shown over the Review screen, and it
/// pops itself before pushing a destination, which does not survive being mounted as a test's
/// `home`. The destinations below are the real `buildRoute()`s, so only the row labels can
/// drift from the sheet -- and `design/docs/03-components.md` §7 is what fixes them.
class ExploreHubScreen extends StatelessWidget {
  const ExploreHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: const Text('Explore')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Analysis board'),
            onTap: () => Navigator.of(context).push(
              AnalysisScreen.buildRoute(
                const AnalysisOptions.standalone(variant: Variant.standard),
              ),
            ),
          ),
          ListTile(
            title: const Text('Opening explorer'),
            onTap: () => Navigator.of(context).push(
              OpeningExplorerScreen.buildRoute(
                const AnalysisOptions.pgn(
                  id: StringId('standalone_opening_explorer'),
                  orientation: Side.white,
                  pgn: '',
                  isComputerAnalysisAllowed: false,
                  variant: Variant.standard,
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Board editor'),
            onTap: () => Navigator.of(context).push(
              BoardEditorScreen.buildRoute((
                initialVariant: Variant.standard,
                initialFen: null,
                initialOrientation: Side.white,
              )),
            ),
          ),
        ],
      ),
    );
  }
}
