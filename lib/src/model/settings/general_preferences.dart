import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart'
    show BoardPrefs, BoardTheme, boardPreferencesProvider;
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/utils/json.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';

part 'general_preferences.freezed.dart';
part 'general_preferences.g.dart';

final generalPreferencesProvider = NotifierProvider<GeneralPreferencesNotifier, GeneralPrefs>(
  GeneralPreferencesNotifier.new,
  name: 'GeneralPreferencesProvider',
);

class GeneralPreferencesNotifier extends Notifier<GeneralPrefs>
    with PreferencesStorage<GeneralPrefs> {
  @override
  @protected
  final prefCategory = PrefCategory.general;

  @override
  @protected
  GeneralPrefs get defaults => GeneralPrefs.defaults;

  @override
  GeneralPrefs fromJson(Map<String, dynamic> json) => GeneralPrefs.fromJson(json);

  @override
  GeneralPrefs build() {
    return fetch();
  }

  Future<void> setBackgroundThemeMode(BackgroundThemeMode themeMode) {
    return save(state.copyWith(themeMode: themeMode));
  }

  Future<void> toggleSoundEnabled() {
    return save(state.copyWith(isSoundEnabled: !state.isSoundEnabled));
  }

  Future<void> setLocale(Locale? locale) {
    return save(state.copyWith(locale: locale));
  }

  Future<void> setSoundTheme(SoundTheme soundTheme) {
    return save(state.copyWith(soundTheme: soundTheme));
  }

  Future<void> setMasterVolume(double volume) {
    return save(state.copyWith(masterVolume: volume));
  }

  /// The accent the design system's colours are built from.
  ///
  /// Held here rather than in the theme bridge, which used to keep it in memory only: the
  /// settings screen offers a choice, so a choice that did not outlive the process was a setting
  /// the app quietly forgot (design/docs/05-flutter-implementation.md §6).
  Future<void> setAccent(SrsAccent accent) {
    return save(state.copyWith(accent: accent));
  }

  Future<void> toggleSystemColors() {
    final newState = state.copyWith(systemColors: !state.systemColors);
    return Future.wait([
      save(newState),
      ref
          .read(boardPreferencesProvider.notifier)
          .setBoardTheme(
            newState.systemColors ? BoardTheme.system : BoardPrefs.defaults.boardTheme,
          ),
    ]).then((_) => {});
  }
}

@Freezed(fromJson: true, toJson: true)
sealed class GeneralPrefs with _$GeneralPrefs implements Serializable {
  const GeneralPrefs._();

  @Assert('masterVolume >= 0 && masterVolume <= 1')
  const factory GeneralPrefs({
    @JsonKey(unknownEnumValue: BackgroundThemeMode.system, defaultValue: BackgroundThemeMode.system)
    required BackgroundThemeMode themeMode,
    required bool isSoundEnabled,
    @JsonKey(unknownEnumValue: SoundTheme.standard) required SoundTheme soundTheme,
    @JsonKey(defaultValue: 0.8) required double masterVolume,

    /// Whether to use system colors on android 10+.
    @JsonKey(defaultValue: true) required bool systemColors,

    /// The accent colour the design system is themed with.
    ///
    /// Optional with a default so that preferences stored before accents existed — and the
    /// `GeneralPrefs.defaults` used as a fallback wherever JSON is unreadable — keep working
    /// without every one of them naming this field. An accent this build does not recognise falls
    /// back to the default rather than failing the whole decode, which is what would take the
    /// user's other settings down with it.
    @JsonKey(unknownEnumValue: kSrsDefaultAccent) @Default(kSrsDefaultAccent) SrsAccent accent,

    /// App theme seed
    @Deprecated('Use systemColors instead')
    @JsonKey(unknownEnumValue: AppThemeSeed.board, defaultValue: AppThemeSeed.board)
    required AppThemeSeed appThemeSeed,

    /// Locale to use in the app, use system locale if null
    @LocaleConverter() Locale? locale,
  }) = _GeneralPrefs;

  static const defaults = GeneralPrefs(
    themeMode: BackgroundThemeMode.system,
    isSoundEnabled: true,
    soundTheme: SoundTheme.standard,
    masterVolume: 0.8,
    systemColors: true,
    appThemeSeed: AppThemeSeed.board,
  );

  factory GeneralPrefs.fromJson(Map<String, dynamic> json) {
    return _$GeneralPrefsFromJson(json);
  }
}

enum AppThemeSeed {
  /// The app theme is based on the user's system theme (only available on Android 10+).
  system,

  /// The app theme is based on the chessboard.
  board,
}

/// Describes the background theme of the app.
enum BackgroundThemeMode {
  /// Use either the light or dark theme based on what the user has selected in
  /// the system settings.
  system,

  /// Always use the light mode regardless of system preference.
  light,

  /// Always use the dark mode (if available) regardless of system preference.
  dark,

  /// Pure black for amoled screens.
  amoled;

  String title(AppLocalizations l10n) {
    switch (this) {
      case BackgroundThemeMode.system:
        return l10n.deviceTheme;
      case BackgroundThemeMode.dark:
        return l10n.dark;
      case BackgroundThemeMode.light:
        return l10n.light;
      case BackgroundThemeMode.amoled:
        return 'Amoled black';
    }
  }
}

enum SoundTheme {
  standard('Standard'),
  piano('Piano'),
  nes('NES'),
  sfx('SFX'),
  futuristic('Futuristic'),
  lisp('Lisp');

  final String label;

  const SoundTheme(this.label);
}
