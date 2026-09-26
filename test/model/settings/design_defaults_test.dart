// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Defaults that the design dictates, pinned so they cannot drift back.
//
// Each of these was the opposite once. All three were changed together with the owner's
// agreement, and each cites the spec that decided it, because a bare `true`/`false` in a
// constructor is exactly the kind of value that gets flipped in passing by a later commit —
// which is how all three went wrong in the first place.

import 'dart:convert';

import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the notation line is on by default', () {
    // design/docs/03-components.md §111 calls it "the headline" and specifies a "3. ____"
    // placeholder that fills in accent on answer. design/docs/01-identity.md §7 says the
    // typography "treats the line of moves as the headline". A first-run user cannot see
    // any of that with it off.
    test('StudyPrefs.defaults shows it', () {
      expect(StudyPrefs.defaults.showMoveHistory, isTrue);
    });

    // The field default and the @JsonKey default are two separate values that used to
    // disagree in intent — both were false, but they are set in different places, and a
    // stored preference with the key absent is parsed by the annotation, not the field.
    // Pinning only the field would leave the deserialised default wrong.
    test('a stored preference with the key absent deserialises to shown', () {
      final json = jsonDecode(jsonEncode(StudyPrefs.defaults.toJson())) as Map<String, dynamic>
        ..remove('showMoveHistory');

      expect(StudyPrefs.fromJson(json).showMoveHistory, isTrue);
    });
  });

  group('sound is off by default', () {
    // design/docs/02-tokens.md §6: "Default off (setting: Sound)". The demo agrees
    // independently: its own control is `data-sound="off" aria-pressed="true"`.
    test('GeneralPrefs.defaults is off', () {
      expect(GeneralPrefs.defaults.isSoundEnabled, isFalse);
    });
  });

  group('the diagram sound set is the default', () {
    // design/docs/07 §1 wants the design's own sounds and calls the bundled Lichess sets
    // placeholders. It cannot be satisfied literally — the diagram set has one sound and
    // Sound has eleven — so the middle path: a fresh install gets the design's knock for a
    // move, and the Lichess sets stay available to anyone who picks them.
    test('GeneralPrefs.defaults is diagram', () {
      expect(GeneralPrefs.defaults.soundTheme, SoundTheme.diagram);
    });

    test('diagram is offered in the picker, not just used as a default', () {
      // A default nobody can choose is a dead end for anyone who wants the bundled sets back.
      expect(SoundTheme.values, contains(SoundTheme.diagram));
      expect(
        SoundTheme.values.map((t) => t.name),
        containsAll(<String>['diagram', 'standard', 'piano', 'nes', 'sfx', 'futuristic', 'lisp']),
      );
    });
  });
}
