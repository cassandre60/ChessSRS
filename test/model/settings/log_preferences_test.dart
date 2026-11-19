import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  group('LogPrefs', () {
    test('defaults to WARNING level', () {
      expect(LogPrefs.defaults.level, Level.WARNING);
    });

    test('toJson/fromJson round-trip preserves level', () {
      const prefs = LogPrefs(level: Level.SEVERE);
      final json = prefs.toJson();
      final restored = LogPrefs.fromJson(json);

      expect(json['level'], Level.SEVERE.value.toString());
      expect(restored, prefs);
      expect(restored.level, Level.SEVERE);
    });

    test('available levels include WARNING', () {
      expect(kLogPreferencesAvailableLevels, contains(Level.WARNING));
    });
  });

  group('LevelConverter', () {
    const converter = LevelConverter();

    test('toJson returns the level value as a string', () {
      expect(converter.toJson(Level.INFO), Level.INFO.value.toString());
      expect(converter.toJson(Level.WARNING), Level.WARNING.value.toString());
    });

    test('fromJson maps a valid level value to the level', () {
      final value = Level.WARNING.value.toString();
      expect(converter.fromJson(value), Level.WARNING);
    });

    test('fromJson returns default for an unknown numeric value', () {
      expect(converter.fromJson('999999'), LogPrefs.defaults.level);
    });

    test('fromJson returns default for a non-numeric string', () {
      expect(converter.fromJson('not-a-number'), LogPrefs.defaults.level);
    });

    test('fromJson returns default for an empty string', () {
      expect(converter.fromJson(''), LogPrefs.defaults.level);
    });
  });
}
