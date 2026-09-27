import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Matches a bare `SettingsScreen` reference -- not the longer names that end in it
/// (`SrsSettingsScreen`, `BoardSettingsScreen`, `EngineSettingsScreen`, and so on).
final _bareSettingsScreen = RegExp('(?<![A-Za-z])SettingsScreen(?![A-Za-z])');

/// Guards against the legacy settings screen coming back.
///
/// It was 283 lines of Material `ListTile` / `PlatformAppBar` that no user could reach:
/// `SettingsScreen.buildRoute()` forwarded to `SrsSettingsScreen`, so the class itself was
/// instantiated only by its own test. And it was not merely unreachable but redundant --
/// `SrsSettingsScreen` already surfaces every row it had (board and pieces, sound, engine, local
/// database size, HTTP logs, app logs, spaced repetition), which
/// `srs_settings_screen_test.dart` asserts.
///
/// Worth guarding because it was easy to mis-scope: a grep for unreskinned settings screens
/// counted it as pending work, and this project has already shipped two parallel
/// implementations of the same screen because of a stale reference.
void main() {
  test('the legacy Material settings screen stays deleted', () {
    expect(
      File(p.join('lib', 'src', 'view', 'settings', 'settings_screen.dart')).existsSync(),
      isFalse,
      reason:
          'That screen is dead code and SrsSettingsScreen supersedes every row it had. If a real '
          'settings entry point is needed, add it to SrsSettingsScreen, which is what the app '
          'actually reaches.',
    );
  });

  test('nothing references the deleted screen', () {
    final offenders = <String>[];
    for (final dir in [Directory('lib'), Directory('test')]) {
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        // This file names the symbol on purpose.
        if (file.path.endsWith('legacy_settings_screen_test.dart')) continue;

        for (final line in file.readAsStringSync().split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//')) continue;
          if (_bareSettingsScreen.hasMatch(trimmed)) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: 'a reference to the deleted SettingsScreen remains');
  });
}
