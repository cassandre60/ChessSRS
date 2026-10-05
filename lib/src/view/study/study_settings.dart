// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/study/study_controller.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/engine_settings_widget.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class StudySettingsScreen extends ConsumerWidget {
  const StudySettingsScreen(this.options);

  final StudyOptions options;

  static Route<dynamic> buildRoute(StudyOptions options) {
    return buildScreenRoute(screen: StudySettingsScreen(options));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studyController = studyControllerProvider(options);
    final c = context.srs;

    final isComputerAnalysisAllowed = ref.watch(
      studyController.select((s) => s.requireValue.isComputerAnalysisAllowed),
    );

    final studyPrefs = ref.watch(studyPreferencesProvider);
    final studyNotifier = ref.read(studyPreferencesProvider.notifier);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(label: 'Review', onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  const SrsGroupHeader('Display'),
                  SrsSettingsRow(
                    label: context.l10n.inlineNotation,
                    control: SrsSwitch(
                      value: studyPrefs.inlineNotation,
                      semanticLabel: context.l10n.inlineNotation,
                      onChanged: (_) => studyNotifier.toggleInlineNotation(),
                    ),
                  ),
                  SrsSettingsRow(
                    label: 'Show engine lines',
                    control: SrsSwitch(
                      value: studyPrefs.showEngineLines,
                      semanticLabel: 'Show engine lines',
                      onChanged: (_) => studyNotifier.toggleShowEngineLines(),
                    ),
                  ),
                  SrsSettingsRow(
                    label: 'Small board',
                    control: SrsSwitch(
                      value: studyPrefs.smallBoard,
                      semanticLabel: 'Small board',
                      onChanged: (_) => studyNotifier.toggleSmallBoard(),
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.openingExplorer,
                    onTap: () => showSrsSheet<void>(context, const OpeningExplorerSettings()),
                  ),
                  const SrsGroupHeader('Annotations'),
                  SrsSettingsRow(
                    label: context.l10n.bestMoveArrow,
                    control: SrsSwitch(
                      value: studyPrefs.showBestMoveArrow,
                      semanticLabel: context.l10n.bestMoveArrow,
                      onChanged: (_) => studyNotifier.toggleShowBestMoveArrow(),
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.showVariationArrows,
                    control: SrsSwitch(
                      value: studyPrefs.showVariationArrows,
                      semanticLabel: context.l10n.showVariationArrows,
                      onChanged: (_) => studyNotifier.toggleShowVariationArrows(),
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.toggleGlyphAnnotations,
                    control: SrsSwitch(
                      value: studyPrefs.showAnnotations,
                      semanticLabel: context.l10n.toggleGlyphAnnotations,
                      onChanged: (_) => studyNotifier.toggleAnnotations(),
                    ),
                  ),
                  if (isComputerAnalysisAllowed)
                    EngineSettingsWidget(
                      onSetEngineSearchTime: (value) =>
                          ref.read(studyController.notifier).setEngineSearchTime(value),
                      onSetNumEvalLines: (value) =>
                          ref.read(studyController.notifier).setNumEvalLines(value),
                      onSetEngineCores: (value) =>
                          ref.read(studyController.notifier).setEngineCores(value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
