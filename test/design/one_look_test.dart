// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app looks the same on every platform.
///
/// `design/docs/00-agent-brief.md` open decision 4, resolved 2026-09-28: keep platform
/// *behaviours* -- back gestures, scroll physics, haptics -- but not platform-specific *looks*.
///
/// This reads the source rather than rendering anything, because a Cupertino sheet and a Diagram
/// sheet are the same widgets in the tree as far as most assertions are concerned, and a widget
/// test that pumps a screen on `TargetPlatform.iOS` only covers the screens it remembers to
/// mention. The reachability list below is the part that can go stale, and it says so.
void main() {
  group('no iOS-native look on a reachable screen', () {
    // The screens a user can actually get to. Legacy Lichess screens that survived the cuts
    // (`view/study/`, `view/game/`, `view/chat/`, `view/user/`) are deliberately absent: they are
    // reachable only from a deep link at best, and the right answer for them is a cut, not a
    // reskin. `view/retro` is Lichess's game-review screen and goes with them.
// `view/offline_computer/` is one of the two ways into a game, so it is here: the bar, both
    // sheets and the result dialog were all converted off the inherited look in 2026-10.
    // Sign-in and PGN import are on the list because they carry a real flow -- importing a private
    // study is how the app is fed -- so a second design language on either is a visible defect.
    const reachable = <String>[
      'lib/src/app.dart',
      'lib/src/design/',
      'lib/src/widgets/adaptive_action_sheet.dart',
      'lib/src/widgets/adaptive_choice_picker.dart',
      'lib/src/widgets/adaptive_bottom_sheet.dart',
      'lib/src/view/analysis/analysis_hub_screen.dart',
      'lib/src/view/analysis/analysis_screen.dart',
      'lib/src/view/analysis/analysis_settings_screen.dart',
      'lib/src/view/analysis/analysis_share_screen.dart',
      'lib/src/view/board_editor/',
      'lib/src/view/explorer/opening_explorer_screen.dart',
      'lib/src/view/explorer/opening_explorer_settings.dart',
      'lib/src/view/offline_computer/',
      'lib/src/view/review/',
      'lib/src/view/settings/',
      'lib/src/view/auth/sign_in_options.dart',
      'lib/src/view/auth/email_login_screen.dart',
      'lib/src/view/more/import_pgn_screen.dart',
      'lib/src/view/account/account_menu.dart',
      // The study bottom bar is the exception to the study-is-a-cut-candidate rule above:
      // it renders on the reachable StudyScreen and was converted off CupertinoIcons.
      'lib/src/view/study/study_bottom_bar.dart',
    ];

    /// Widgets that are a *look*, as opposed to `cupertino_ui` the package.
    ///
    /// `CupertinoClient` in `network/http.dart` is an HTTP implementation and is not a look, and
    /// it is deliberately not matched here.
    const looks = <String>[
      'CupertinoActionSheet',
      'CupertinoActionSheetAction',
      'CupertinoButton',
      'CupertinoAlertDialog',
      'CupertinoDialogAction',
      'CupertinoSwitch',
      'CupertinoTextField',
      'CupertinoSearchTextField',
      'CupertinoPicker',
      'CupertinoScrollbar',
      'CupertinoActivityIndicator',
      'CupertinoPageRoute',
      'showCupertinoModalPopup',
      'showCupertinoDialog',
      'CupertinoIcons.',
      'CupertinoListTileChevron',
      // `CupertinoTheme`/`CupertinoColors` are excluded: both are usable as plain colour sources,
      // and `platform_context_menu_button.dart` -- the last file that leans on them -- is out of
      // reach of the list above.
    ];

    test('a reachable screen renders no Cupertino widget', () {
      final offenders = <String>[];

      for (final entry in reachable) {
        final files = Directory(entry).existsSync()
            ? Directory(entry).listSync(recursive: true).whereType<File>()
            : <File>[File(entry)];
        for (final file in files) {
          if (!file.path.endsWith('.dart')) continue;
          // Generated files are not hand-written and would drag in upstream's own usage.
          if (file.path.endsWith('.g.dart') || file.path.endsWith('.freezed.dart')) continue;

          final source = _stripComments(file.readAsStringSync());
          for (final look in looks) {
            if (source.contains(look)) offenders.add('${file.path}: $look');
          }

          // One deliberate exception, and it is not a look. `analysis_share_screen.dart` shows a
          // `CupertinoDatePicker` wheel on iOS and a Material calendar elsewhere. That is the same
          // control reached two different ways -- spin-and-stop against tap-a-day -- which is a
          // platform *behaviour* as much as an appearance, and open decision 4's own rule keeps
          // behaviours. Owner decision 2026-09-28: keep the wheel. Replacing it with a Material
          // calendar would impose Android UX on iOS users for a control reached while editing a PGN
          // header date -- already the least-tapped corner of the app -- for no gain. This exception
          // is permanent: remove it only if the decision is revisited, not as cleanup.
          if (file.path.endsWith('analysis_share_screen.dart')) {
            offenders.removeWhere((o) => o.startsWith('${file.path}: '));
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A Cupertino widget on a reachable screen means the same control looks different per\n'
            'device. Move it to lib/src/design/ and use the Diagram primitive instead. If the\n'
            'screen is genuinely unreachable, cut it rather than reskinning it.',
      );
    });

    test('the reachable list still points at files that exist', () {
      // Stale entries in the list above would silently stop checking a screen, which is the
      // failure mode that lets this regress unnoticed.
      for (final entry in reachable) {
        expect(
          Directory(entry).existsSync() || File(entry).existsSync(),
          isTrue,
          reason: '$entry is listed as reachable but does not exist',
        );
      }
    });
  });
}

/// Drops `//` and `/* */` comments before scanning.
///
/// Without this the guard flags the very files that were fixed, because a good fix says in a doc
/// comment which Cupertino widget it replaced -- and "this file mentions CupertinoActionSheet"
/// cannot tell a fixed file from a live one. A real usage is never inside a comment, so stripping
/// them costs nothing and removes the false positive that would otherwise train everyone to ignore
/// this test.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((line) {
        final start = line.indexOf('//');
        return start == -1 ? line : line.substring(0, start);
      })
      .join('\n');
}
