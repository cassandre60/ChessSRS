// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-061.

import 'dart:math' as math;
import 'dart:ui';

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.2 relative luminance of an opaque sRGB colour.
double _luminance(Color color) {
  double linearize(int byte) {
    final c = byte / 255;
    if (c <= 0.03928) return c / 12.92;
    return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize((color.r * 255).round()) +
      0.7152 * linearize((color.g * 255).round()) +
      0.0722 * linearize((color.b * 255).round());
}

/// WCAG 2.2 contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// design/docs/04-screens-and-flows.md §6 requires WCAG 2.2 AA: 4.5:1 for normal text, 3:1 for
/// large text and graphics. The quiet-ink role once shipped at 3.05:1 in the light theme, so a
/// dozen small-text usages (row subs, group titles, note attributions, the `due` word) failed
/// AA while the doc claimed it. This pins the tokens mechanically, in both themes, on both
/// surfaces text sits on — `page` is the prototype's background, not part of the app.
void main() {
  group('SrsColors text contrast (INV-061)', () {
    for (final MapEntry(key: name, value: colors) in {
      'light': SrsColors.light(SrsAccent.ultramarine),
      'dark': SrsColors.dark(SrsAccent.ultramarine),
    }.entries) {
      group(name, () {
        test('ink, ink2 and ink3 reach 4.5:1 on ground and surface', () {
          for (final background in [colors.ground, colors.surface]) {
            for (final ink in [colors.ink, colors.ink2, colors.ink3]) {
              expect(
                _contrast(ink, background),
                greaterThanOrEqualTo(4.5),
                reason: '$ink on $background in $name must meet AA normal text',
              );
            }
          }
        });
      });
    }

    test('every selectable accent reaches 4.5:1 on ground in both themes', () {
      for (final accent in SrsAccent.values) {
        expect(
          _contrast(kSrsAccents[accent]!.light, const Color(0xFFF1F3F4)),
          greaterThanOrEqualTo(4.5),
          reason: '$accent light must meet AA normal text',
        );
        expect(
          _contrast(kSrsAccents[accent]!.dark, const Color(0xFF0D0F13)),
          greaterThanOrEqualTo(4.5),
          reason: '$accent dark must meet AA normal text',
        );
      }
    });
  });
}
