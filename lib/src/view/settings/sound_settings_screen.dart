import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const kMasterVolumeValues = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];

class SoundSettingsScreen extends StatelessWidget {
  const SoundSettingsScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const SoundSettingsScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.srs.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(label: context.l10n.sound, onBack: () => Navigator.of(context).maybePop()),
            Expanded(child: _Body()),
          ],
        ),
      ),
    );
  }
}

/// Localize the sound theme.
String soundThemeL10n(BuildContext context, SoundTheme theme) =>
    theme == SoundTheme.standard ? context.l10n.standard : theme.label;

/// Returns a volume label in percentage.
String volumeLabel(double value) => '${(value * 100).round()}%';

class _Body extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final generalPrefs = ref.watch(generalPreferencesProvider);

    void onChanged(SoundTheme? value) {
      ref.read(generalPreferencesProvider.notifier).setSoundTheme(value ?? SoundTheme.standard);
      ref.read(soundServiceProvider).changeTheme(value ?? SoundTheme.standard, playSound: true);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        const SrsGroupHeader('Volume'),
        SrsSettingsRow(
          label: 'Master volume',
          value: volumeLabel(generalPrefs.masterVolume),
          preview: Slider(
            value: generalPrefs.masterVolume,
            max: 1,
            // Discrete notches at 10%, so the percentage in the row is not a rounding of a
            // continuous value the user cannot actually land on.
            divisions: 10,
            label: volumeLabel(generalPrefs.masterVolume),
            onChanged: (value) =>
                ref.read(generalPreferencesProvider.notifier).setMasterVolume(value),
          ),
        ),
        const SrsGroupHeader('Theme'),
        SrsSegmented<String>(
          value: generalPrefs.soundTheme.name,
          options: {
            for (final theme in SoundTheme.values) theme.name: soundThemeL10n(context, theme),
          },
          onChanged: (name) => onChanged(SoundTheme.values.byName(name)),
        ),
      ],
    );
  }
}
