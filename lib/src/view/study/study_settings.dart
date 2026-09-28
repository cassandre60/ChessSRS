import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/study/study_controller.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/engine_settings_widget.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_settings.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:chess_srs/src/widgets/settings.dart';
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

    final isComputerAnalysisAllowed = ref.watch(
      studyController.select((s) => s.requireValue.isComputerAnalysisAllowed),
    );

    final studyPrefs = ref.watch(studyPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsSettings)),
      body: ListView(
        children: [
          ListSection(
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.inlineNotation),
                value: studyPrefs.inlineNotation,
                onChanged: (value) =>
                    ref.read(studyPreferencesProvider.notifier).toggleInlineNotation(),
              ),
              SwitchSettingTile(
                // TODO: l10n
                title: const Text('Show engine lines'),
                value: studyPrefs.showEngineLines,
                onChanged: (value) =>
                    ref.read(studyPreferencesProvider.notifier).toggleShowEngineLines(),
              ),
              SwitchSettingTile(
                title: const Text('Small board'), // TODO l10n
                value: studyPrefs.smallBoard,
                onChanged: (value) =>
                    ref.read(studyPreferencesProvider.notifier).toggleSmallBoard(),
              ),
              ListTile(
                title: Text(context.l10n.openingExplorer),
                onTap: () => showSrsSheet<void>(context, const OpeningExplorerSettings()),
              ),
            ],
          ),
          ListSection(
            children: [
              SwitchSettingTile(
                title: Text(context.l10n.bestMoveArrow),
                value: studyPrefs.showBestMoveArrow,
                onChanged: (value) =>
                    ref.read(studyPreferencesProvider.notifier).toggleShowBestMoveArrow(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.showVariationArrows),
                value: studyPrefs.showVariationArrows,
                onChanged: (value) =>
                    ref.read(studyPreferencesProvider.notifier).toggleShowVariationArrows(),
              ),
              SwitchSettingTile(
                title: Text(context.l10n.toggleGlyphAnnotations),
                value: studyPrefs.showAnnotations,
                onChanged: (_) => ref.read(studyPreferencesProvider.notifier).toggleAnnotations(),
              ),
            ],
          ),
          if (isComputerAnalysisAllowed)
            EngineSettingsWidget(
              onSetEngineSearchTime: (value) =>
                  ref.read(studyController.notifier).setEngineSearchTime(value),
              onSetNumEvalLines: (value) =>
                  ref.read(studyController.notifier).setNumEvalLines(value),
              onSetEngineCores: (value) => ref.read(studyController.notifier).setEngineCores(value),
            ),
        ],
      ),
    );
  }
}
