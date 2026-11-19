import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeneralPrefs.defaults', () {
    test('has expected default values', () {
      const prefs = GeneralPrefs.defaults;

      expect(prefs.themeMode, BackgroundThemeMode.system);
      expect(prefs.isSoundEnabled, isTrue);
      expect(prefs.soundTheme, SoundTheme.standard);
      expect(prefs.masterVolume, 0.8);
      expect(prefs.systemColors, isTrue);
      expect(prefs.accent, kSrsDefaultAccent);
      expect(prefs.locale, isNull);
    });
  });

  group('GeneralPrefs JSON', () {
    test('toJson/fromJson round-trips explicit values', () {
      const prefs = GeneralPrefs(
        themeMode: BackgroundThemeMode.dark,
        isSoundEnabled: false,
        soundTheme: SoundTheme.piano,
        masterVolume: 0.4,
        systemColors: false,
        accent: SrsAccent.violet,
      );

      final json = prefs.toJson();
      final restored = GeneralPrefs.fromJson(json);

      expect(json['themeMode'], 'dark');
      expect(json['isSoundEnabled'], isFalse);
      expect(json['soundTheme'], 'piano');
      expect(json['masterVolume'], 0.4);
      expect(json['systemColors'], isFalse);
      expect(json['accent'], 'violet');
      expect(restored, prefs);
    });

    test('fromJson applies defaults and unknown-enum fallbacks', () {
      final prefs = GeneralPrefs.fromJson({
        'themeMode': 'unknownTheme',
        'isSoundEnabled': true,
        'soundTheme': 'unknownSound',
        'accent': 'unknownAccent',
      });

      expect(prefs.themeMode, BackgroundThemeMode.system);
      expect(prefs.isSoundEnabled, isTrue);
      expect(prefs.soundTheme, SoundTheme.standard);
      expect(prefs.masterVolume, 0.8);
      expect(prefs.systemColors, isTrue);
      expect(prefs.accent, kSrsDefaultAccent);
      expect(prefs.locale, isNull);
    });

    test('fromJson omits accent/volume/systemColors using documented defaults', () {
      final prefs = GeneralPrefs.fromJson({
        'themeMode': 'light',
        'isSoundEnabled': false,
        'soundTheme': 'nes',
      });

      expect(prefs.themeMode, BackgroundThemeMode.light);
      expect(prefs.isSoundEnabled, isFalse);
      expect(prefs.soundTheme, SoundTheme.nes);
      expect(prefs.masterVolume, 0.8);
      expect(prefs.systemColors, isTrue);
      expect(prefs.accent, kSrsDefaultAccent);
    });
  });

  group('SoundTheme', () {
    test('exposes human-readable labels', () {
      expect(SoundTheme.standard.label, 'Standard');
      expect(SoundTheme.piano.label, 'Piano');
      expect(SoundTheme.nes.label, 'NES');
      expect(SoundTheme.sfx.label, 'SFX');
      expect(SoundTheme.futuristic.label, 'Futuristic');
      expect(SoundTheme.lisp.label, 'Lisp');
    });
  });
}
