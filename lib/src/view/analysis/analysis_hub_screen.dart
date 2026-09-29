// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_screen.dart';
import 'package:chess_srs/src/view/review/study_chapters_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Scaffold, showModalBottomSheet;

/// The Explore area, as one screen called Analysis.
///
/// Owner decision 2026-09-28 on `00-agent-brief.md` open decision 1. Before it, these three tools
/// were three flat rows in the Library sheet, which left the sheet doing two jobs: choosing a
/// repertoire to review, and listing unrelated tools.
///
/// The chapter list is here to *browse* a repertoire's chapters. It is deliberately not a second
/// home for the study list: the scope drawer still owns choosing what to review, and this screen
/// only reaches the existing `StudyChaptersScreen`. The two overlap in subject matter and not in
/// purpose, which is why the entry only appears once a study actually exists.
///
/// Tapping a chapter opens it in the analysis board: free browsing of all
/// moves, variations and notes with no quizzing and no SRS writes — the
/// answers to review's questions (owner decision 2026-09-29 Q7).
/// Minimal PGN carrying a single FEN, so the analysis and explorer screens
/// open on the review board's live position instead of the start position
/// (owner report 2026-09-29). `PgnGame.parsePgn` honours the FEN header.
String reviewPositionPgn(String fen) => '[FEN "$fen"]\n\n*';

/// Analysis options for the review board's live position, falling back to a
/// blank standalone board when no review position exists (e.g. hub opened
/// with nothing imported yet).
AnalysisOptions analysisOptionsForReviewPosition({String? fen, required Side orientation}) {
  if (fen == null) return const AnalysisOptions.standalone(variant: Variant.standard);
  return AnalysisOptions.pgn(
    id: const StringId('review_position'),
    orientation: orientation,
    pgn: reviewPositionPgn(fen),
    isComputerAnalysisAllowed: true,
    variant: Variant.standard,
  );
}

/// Explorer options for the review board's live position, falling back to the
/// start position when there is none.
AnalysisOptions explorerOptionsForReviewPosition({String? fen, required Side orientation}) {
  return AnalysisOptions.pgn(
    id: const StringId('review_position_explorer'),
    orientation: orientation,
    pgn: fen == null ? '' : reviewPositionPgn(fen),
    isComputerAnalysisAllowed: false,
    variant: Variant.standard,
  );
}

class AnalysisHubScreen extends ConsumerWidget {
  const AnalysisHubScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const AnalysisHubScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    // The live review position, so the tools open where the user already is
    // rather than on the start position (owner report 2026-09-29).
    final reviewState = ref.watch(reviewControllerProvider).value;
    final reviewFen = reviewState?.boardPosition?.fen;
    final orientation = reviewState?.boardOrientation ?? Side.white;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SrsPageHead(label: 'Analysis', onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              // Centred and width-capped like the settings screen, so the rows are not a single
              // line of text stretched across a desktop window. `SrsSettingsRow` carries no
              // horizontal padding of its own -- its callers supply it, and without this the labels
              // sit flush against the screen edge.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 660),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 40),
                    children: [
                      SrsSettingsRow(
                        label: 'Analysis board',
                        help: 'Work through a position with the engine',
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          AnalysisScreen.buildRoute(
                            analysisOptionsForReviewPosition(
                              fen: reviewFen,
                              orientation: orientation,
                            ),
                          ),
                        ),
                      ),
                      SrsSettingsRow(
                        label: 'Opening explorer',
                        help: 'Browse openings by name and ECO',
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          OpeningExplorerScreen.buildRoute(
                            explorerOptionsForReviewPosition(
                              fen: reviewFen,
                              orientation: orientation,
                            ),
                          ),
                        ),
                      ),
                      SrsSettingsRow(
                        label: 'Board editor',
                        help: 'Build a position and check it',
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          BoardEditorScreen.buildRoute((
                            initialVariant: Variant.standard,
                            initialFen: reviewFen,
                            initialOrientation: orientation,
                          )),
                        ),
                      ),
                      const _SectionHeader('Repertoires'),
                      SrsSettingsRow(
                        label: 'Explore study',
                        help: 'Browse a repertoire\u2019s moves and notes freely, no quizzing',
                        onTap: () => _pickStudyToBrowse(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the study picker, then the chosen study's chapters.
  ///
  /// A sheet rather than a study list inline on this screen. Inlining it was the first attempt and
  /// it was wrong twice over: it put a *second* list of the user's repertoires next to the scope
  /// drawer, which already owns that list, and it meant the hub's one job -- offering tools -- grew
  /// a second purpose. The picker keeps the duplication one level deeper, where it is a choice
  /// rather than a competing home.
  Future<void> _pickStudyToBrowse(BuildContext context, WidgetRef ref) async {
    final studies = await ref.read(_studiesProvider.future);
    if (!context.mounted) return;

    if (studies.isEmpty) {
      showSnackBar(context, 'Import a repertoire first.');
      return;
    }

    final study = await showModalBottomSheet<Study>(
      context: context,
      builder: (sheetContext) => _StudyPickerSheet(studies: studies),
    );
    if (study == null || !context.mounted) return;

    final repo = await ref.read(srsStudyRepositoryProvider.future);
    final chapters = await repo.getChaptersByStudy(study.id);
    if (!context.mounted) return;
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(StudyChaptersScreen.buildRoute(study: study, chapters: chapters));
  }
}

/// The user's repertoires, for the chapters picker.
///
/// Plain [Study]s, not a wrapper carrying chapter counts: the picker does not display counts, and
/// fetching one per study to decorate a list the user is about to leave is work with no reader.
final _studiesProvider = FutureProvider.autoDispose<List<Study>>((ref) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return await repo.getAllStudies();
});

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Padding(
      // No horizontal padding: the list supplies it, and doubling it here left the header indented
      // 20px past the rows it was labelling.
      padding: const EdgeInsets.only(top: 26, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: c.ink3,
        ),
      ),
    );
  }
}

/// The study list, as a sheet.
///
/// [Study]s only -- the chapter count is fetched on the way in, so showing it here would mean
/// awaiting a count per study purely to decorate a picker.
class _StudyPickerSheet extends StatelessWidget {
  const _StudyPickerSheet({required this.studies});

  final List<Study> studies;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          for (final study in studies)
            SrsSettingsRow(label: study.title, onTap: () => Navigator.of(context).pop(study)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
