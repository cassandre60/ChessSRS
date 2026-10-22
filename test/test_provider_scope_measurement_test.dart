// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The shared scope has to measure text the way the app does.
//
// `flutter test` runs the engine with `--use-test-fonts --disable-asset-fonts`, so
// a family nothing registers falls back to the square test glyphs -- one em per
// character, whatever the letter -- and a `MaterialApp` without a theme hands a
// `Text` with no style of its own the framework's 48px monospace fallback, the
// debugging aid for "you forgot a Material". Both make every string in the suite
// about twice as wide as it is on a device, which is how most of the measured
// layout overflows turned out to be artefacts of the harness rather than defects
// of the app.
//
// These tests pin the three things the measurement rests on: the app's font is
// registered, the app's theme is applied, and there is a `Material` under the
// tree to give an unstyled `Text` the app's body style.

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_provider_scope.dart';

/// A string whose letters have different widths, so a proportional font and the
/// square test glyphs measure it differently.
const String _probe = 'R: 100% (New)';

/// The size the probe is measured at.
const double _size = 14;

/// Pumps the probe text through the shared scope, with [style] on it.
Future<void> _pumpProbe(WidgetTester tester, TextStyle style) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(
      tester,
      home: Center(child: Text(_probe, style: style)),
    ),
  );
}

void main() {
  testWidgets('the shared scope registers the app font', (tester) async {
    await _pumpProbe(tester, const TextStyle(fontFamily: SrsText.ui, fontSize: _size));
    final withTheAppFont = tester.getSize(find.text(_probe)).width;

    // A family nothing registers falls back to the test glyphs, whose advance is
    // the font size for every character.
    await _pumpProbe(tester, const TextStyle(fontFamily: 'NoSuchFontFamily', fontSize: _size));
    final withTheTestFont = tester.getSize(find.text(_probe)).width;

    // Equal widths would mean the app's font was not registered and the suite is
    // measuring the square test glyphs.
    expect(withTheAppFont, lessThan(withTheTestFont));
  });

  testWidgets('the shared scope applies the app theme', (tester) async {
    await _pumpProbe(tester, const TextStyle());

    final theme = Theme.of(tester.element(find.text(_probe)));
    expect(theme.textTheme.bodyMedium?.fontFamily, SrsText.ui);
    expect(theme.textTheme.bodyMedium?.fontSize, _size);
  });

  testWidgets('the shared scope gives an unstyled Text the app body style', (tester) async {
    // No Scaffold, so no Material of its own: the scope has to supply one, as the
    // app's screens get theirs from their Scaffold.
    await _pumpProbe(tester, const TextStyle());

    final style = DefaultTextStyle.of(tester.element(find.text(_probe))).style;
    expect(style.fontSize, _size);
    expect(style.fontFamily, SrsText.ui);
  });
}
