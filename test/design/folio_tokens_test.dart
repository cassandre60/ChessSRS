// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Folio palette is a verbatim copy of the look-judge demo's `:root` block
/// (`.opencode/plan/visual-demo.html`). These pins fail on a mistyped copy and on a
/// copy-paste of the Diagram values — the one failure mode of an additive palette is
/// that it is secretly the same palette, which would make the whole migration a no-op.
void main() {
  group('SrsFolioColors matches the demo', () {
    test('light', () {
      final c = SrsFolioColors.light(kSrsDefaultAccent);
      expect(c.brightness, Brightness.light);
      expect(c.ground, const Color(0xFFF7F3EC));
      expect(c.surface, const Color(0xFFFFFDF8));
      expect(c.surface2, const Color(0xFFFFF7EB));
      expect(c.ink, const Color(0xFF151A22));
      expect(c.ink2, const Color(0xFF545B6A));
      expect(c.ink3, const Color(0xFF9398A3));
      expect(c.squareLight, const Color(0xFFFFF9F1));
      expect(c.squareDark, const Color(0xFFEEE6D3));
      expect(c.halo, const Color(0xFFFFF9F1));
    });

    test('dark', () {
      final c = SrsFolioColors.dark(kSrsDefaultAccent);
      expect(c.brightness, Brightness.dark);
      expect(c.ground, const Color(0xFF0E131B));
      expect(c.surface, const Color(0xFF131A26));
      expect(c.surface2, const Color(0xFF192130));
      expect(c.ink, const Color(0xFFECEEF1));
      expect(c.squareLight, const Color(0xFF232A36));
      expect(c.squareDark, const Color(0xFF10141B));
      expect(c.halo, const Color(0xFF232A36));
    });

    test('it is actually a second palette, not Diagram renamed', () {
      // The whole point of carrying two palettes is that grounds differ. If this fails,
      // the Folio copy drifted onto the Diagram values and every surface migration
      // built on it changes nothing.
      expect(
        SrsFolioColors.light(kSrsDefaultAccent).ground,
        isNot(SrsColors.light(kSrsDefaultAccent).ground),
      );
      expect(
        SrsFolioColors.light(kSrsDefaultAccent).squareDark,
        isNot(SrsColors.light(kSrsDefaultAccent).squareDark),
      );
    });

    test('accents are shared with Diagram', () {
      for (final a in SrsAccent.values) {
        expect(SrsFolioColors.light(a).accent, SrsColors.light(a).accent);
        expect(SrsFolioColors.dark(a).accent, SrsColors.dark(a).accent);
      }
    });
  });
}
