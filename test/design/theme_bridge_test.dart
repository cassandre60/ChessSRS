// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/theme_bridge.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The Material bridge must read as the Folio system: the only filled control is ink,
/// never the accent. Fails on base, where the bridge painted Material-accent (purple)
/// buttons, switches and segmented selections onto un-migrated screens.
void main() {
  group('srsThemeData interactive colours', () {
    for (final colors in [SrsColors.light(kSrsDefaultAccent), SrsColors.dark(kSrsDefaultAccent)]) {
      final mode = colors.isDark ? 'dark' : 'light';

      test('filled button is ink on ground ($mode)', () {
        final style = srsThemeData(colors).filledButtonTheme.style!;
        expect(
          style.backgroundColor!.resolve({WidgetState.selected}),
          colors.ink,
          reason: 'a Material-accent button leaks the old purple into auth/import screens',
        );
        expect(style.foregroundColor!.resolve({WidgetState.selected}), colors.ground);
      });

      test('selected segmented item is ink on ground ($mode)', () {
        final style = srsThemeData(colors).segmentedButtonTheme.style!;
        expect(style.backgroundColor!.resolve({WidgetState.selected}), colors.ink);
        expect(style.foregroundColor!.resolve({WidgetState.selected}), colors.ground);
      });

      test('selected switch track is ink ($mode)', () {
        final theme = srsThemeData(colors).switchTheme;
        expect(theme.trackColor!.resolve({WidgetState.selected}), colors.ink);
        expect(theme.thumbColor!.resolve({WidgetState.selected}), colors.ground);
      });

      test('input decoration is filled ($mode)', () {
        final theme = srsThemeData(colors);
        expect(
          theme.inputDecorationTheme.filled,
          isTrue,
          reason: 'un-migrated input fields must keep the filled surface treatment',
        );
      });

      test('slider uses the post-2023 style ($mode)', () {
        final theme = srsThemeData(colors);
        expect(
          theme.sliderTheme.year2023,
          isFalse,
          reason: 'the slider opts out of the deprecated 2023 appearance',
        );
      });
    }
  });
}
