// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/engine_settings_widget.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_settings.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Analysis settings, as a Diagram page: a page head over a column of [SrsSettingsRow]s.
///
/// This was an `AppBar` over a `ListView` of `ListSection`s holding `SwitchSettingTile`s, and it
/// is reachable from the Library sheet, so it was the last Material a user could walk onto from a
/// Diagram path. `EngineSettingsWidget` was already reskinned, so it is the one part left as it was.
class AnalysisSettingsScreen extends ConsumerWidget {
  const AnalysisSettingsScreen(this.options);

  final AnalysisOptions options;

  static Route<dynamic> buildRoute({required AnalysisOptions options}) {
    return buildScreenRoute(screen: AnalysisSettingsScreen(options));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final ctrlProvider = analysisControllerProvider(options);
    final prefs = ref.watch(analysisPreferencesProvider);
    final asyncState = ref.watch(ctrlProvider);
    final isSoundEnabled = ref.watch(generalPreferencesProvider).isSoundEnabled;

    switch (asyncState) {
      case AsyncData(:final value):
        return Scaffold(
          backgroundColor: c.ground,
          body: SafeArea(
            child: Column(
              children: [
                SrsPageHead(label: 'Settings', onBack: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    children: [
                      SrsSettingsRow(
                        label: context.l10n.sound,
                        control: SrsSwitch(
                          value: isSoundEnabled,
                          semanticLabel: context.l10n.sound,
                          onChanged: (_) =>
                              ref.read(generalPreferencesProvider.notifier).toggleSoundEnabled(),
                        ),
                      ),
                      SrsSettingsRow(
                        label: context.l10n.inlineNotation,
                        control: SrsSwitch(
                          value: prefs.inlineNotation,
                          semanticLabel: context.l10n.inlineNotation,
                          onChanged: (_) =>
                              ref.read(analysisPreferencesProvider.notifier).toggleInlineNotation(),
                        ),
                      ),
                      SrsSettingsRow(
                        // TODO: l10n
                        label: 'Show engine lines',
                        control: SrsSwitch(
                          value: prefs.showEngineLines,
                          semanticLabel: 'Show engine lines',
                          onChanged: (_) => ref
                              .read(analysisPreferencesProvider.notifier)
                              .toggleShowEngineLines(),
                        ),
                      ),
                      SrsSettingsRow(
                        // TODO: l10n
                        label: 'Small board',
                        control: SrsSwitch(
                          value: prefs.smallBoard,
                          semanticLabel: 'Small board',
                          onChanged: (_) =>
                              ref.read(analysisPreferencesProvider.notifier).toggleSmallBoard(),
                        ),
                      ),
                      SrsSettingsRow(
                        label: context.l10n.openingExplorer,
                        onTap: () => showSrsSheet<void>(context, const OpeningExplorerSettings()),
                      ),
                      if (value.isComputerAnalysisAllowed) ...[
                        SrsGroupHeader(context.l10n.computerAnalysis),
                        SrsSettingsRow(
                          label: context.l10n.mobileServerAnalysis,
                          control: SrsSwitch(
                            value: prefs.enableServerAnalysis,
                            semanticLabel: context.l10n.mobileServerAnalysis,
                            onChanged: (_) => ref
                                .read(analysisPreferencesProvider.notifier)
                                .toggleServerAnalysis(),
                          ),
                        ),
                        SrsSettingsRow(
                          // TODO: l10n
                          label: 'Show evaluation gauge',
                          control: SrsSwitch(
                            value: prefs.showEvaluationGauge,
                            semanticLabel: 'Show evaluation gauge',
                            onChanged: (_) => ref
                                .read(analysisPreferencesProvider.notifier)
                                .toggleShowEvaluationGauge(),
                          ),
                        ),
                        SrsSettingsRow(
                          label: context.l10n.toggleGlyphAnnotations,
                          control: SrsSwitch(
                            value: prefs.showAnnotations,
                            semanticLabel: context.l10n.toggleGlyphAnnotations,
                            onChanged: (_) =>
                                ref.read(analysisPreferencesProvider.notifier).toggleAnnotations(),
                          ),
                        ),
                        SrsSettingsRow(
                          label: context.l10n.mobileShowComments,
                          control: SrsSwitch(
                            value: prefs.showPgnComments,
                            semanticLabel: context.l10n.mobileShowComments,
                            onChanged: (_) =>
                                ref.read(analysisPreferencesProvider.notifier).togglePgnComments(),
                          ),
                        ),
                        SrsSettingsRow(
                          label: context.l10n.bestMoveArrow,
                          control: SrsSwitch(
                            value: prefs.showBestMoveArrow,
                            semanticLabel: context.l10n.bestMoveArrow,
                            onChanged: (_) => ref
                                .read(analysisPreferencesProvider.notifier)
                                .toggleShowBestMoveArrow(),
                          ),
                        ),
                        EngineSettingsWidget(
                          onSetEngineSearchTime: (value) {
                            ref.read(ctrlProvider.notifier).setEngineSearchTime(value);
                          },
                          onSetEngineCores: (value) {
                            ref.read(ctrlProvider.notifier).setEngineCores(value);
                          },
                          onSetNumEvalLines: (value) {
                            ref.read(ctrlProvider.notifier).setNumEvalLines(value);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      case AsyncError(:final error):
        debugPrint('Error loading analysis: $error');
        return const SizedBox.shrink();
      case _:
        return const CenterLoadingIndicator();
    }
  }
}
