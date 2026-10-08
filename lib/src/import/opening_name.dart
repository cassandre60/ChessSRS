// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Opening-family classification, split out of the importer so the schema
/// migration that repairs historical rows judges a name by exactly the rule the
/// import path used to accept it.
///
/// A study title is not an opening. "White vs French" and "My French
/// Repertoire" both name a game or a collection, and turning either into an
/// opening hub puts a phantom entry in the drawer that no amount of reviewing
/// will ever clear (P-OPENNAME).
///
/// The rule: a family either **leads** the name ("Petrov Defense") or **closes**
/// it behind a category noun ("French Defence - Winawer" simplifies to "French
/// Defence"; "Queen's Gambit Declined"). A name that merely mentions a family
/// anywhere else matches nothing, and an unrecognised name is left to the
/// explicit `Opening` header rather than guessed at.
library;

import 'package:dartchess/dartchess.dart' show PgnHeaders;

/// Opening families whose presence at the *start* of a name identifies it.
const List<String> _familyLeads = [
  'sicilian',
  'french',
  'caro kann',
  'ruy lopez',
  'italian',
  'scotch',
  "king's indian",
  'kings indian',
  "queen's indian",
  'queens indian',
  "queen's gambit",
  'queens gambit',
  "queen's pawn",
  'queens pawn',
  "king's gambit",
  'kings gambit',
  'open game',
  'nimzo',
  'gruenfeld',
  'grunfeld',
  'dutch',
  'english',
  'reti',
  'slav',
  'london',
  'catalan',
  'scandinavian',
  'pirc',
  'modern',
  'alekhine',
  'vienna',
];

/// Category nouns that identify a family closing the name.
const List<String> _categoryTails = ['defense', 'defence', 'gambit', 'attack', 'system', 'opening'];

/// Whether [name] reads as an opening family rather than a title that mentions
/// one.
///
/// Hyphens are normalised first, so `Caro-Kann` and `Caro Kann` are one name.
bool isLikelyOpeningFamily(String name) {
  final lower = name.toLowerCase().replaceAll('-', ' ').trim();
  if (lower.isEmpty) return false;
  if (_familyLeads.any((k) => lower == k || lower.startsWith('$k '))) return true;
  return _categoryTails.any((n) => lower.endsWith(' $n'));
}

/// Whether [name] contains a known family word without *being* one.
///
/// The narrower question [isLikelyOpeningFamily] answers "no" to, asked
/// positively so a repair can tell the two failure modes apart: a name this
/// rejects because it merely mentions a family ("White vs French") was never an
/// opening, while a name it rejects because it is unrecognised ("QGD Exchange
/// Variation") may simply be a family this list has not heard of. Only the
/// first kind is safe to erase.
bool mentionsOpeningButIsNotFamily(String name) {
  if (isLikelyOpeningFamily(name)) return false;
  final lower = name.toLowerCase().replaceAll('-', ' ');
  return _familyLeads.any((k) => lower.contains(k)) ||
      _categoryTails.any((n) => lower.contains(' $n '));
}

/// Reduces a PGN opening or event header to its family.
///
/// Splits on `:` and `,` always, and on `-` only when spaced: "French Defence
/// - Winawer" separates family from variation, but "Caro-Kann" is one name.
String simplifyOpeningName(String raw) {
  final splitColon = raw.split(RegExp(r':|,|\s+-\s+'));
  if (splitColon.isNotEmpty && splitColon.first.trim().isNotEmpty) {
    return splitColon.first.trim();
  }
  return raw.trim();
}

/// Reads the opening family from [headers], or null when it carries none.
///
/// A direct `Opening` header is authoritative and passed through the
/// simplification only; `Event` and `ECO` are fallbacks that have to prove
/// themselves.
String? extractOpeningFamily(PgnHeaders headers) {
  // 1. Direct Opening header (e.g. "Sicilian Defense: Najdorf Variation")
  final opening = headers['Opening'];
  if (opening != null && opening.trim().isNotEmpty && opening != '?') {
    return simplifyOpeningName(opening.trim());
  }

  // 2. Check Event header (e.g. "Sicilian Defense", "French Defence - Winawer")
  final event = headers['Event'];
  if (event != null && event.trim().isNotEmpty && event != '?' && !event.startsWith('Game ')) {
    final simplified = simplifyOpeningName(event.trim());
    if (isLikelyOpeningFamily(simplified)) {
      return simplified;
    }
  }

  // 3. Fallback: ECO code classification (standard FIDE/ChessBase ECO families)
  final eco = headers['ECO'];
  if (eco != null && eco.trim().isNotEmpty && eco != '?') {
    return ecoToOpeningFamily(eco.trim().toUpperCase());
  }

  return null;
}

/// Maps an ECO code to its family, or null when the code is out of range.
String? ecoToOpeningFamily(String eco) {
  if (eco.length < 3) return null;
  final letter = eco[0];
  final number = int.tryParse(eco.substring(1, 3)) ?? -1;
  if (number < 0) return null;

  if (letter == 'B') {
    if (number >= 20 && number <= 99) return 'Sicilian Defense';
    if (number >= 10 && number <= 19) return 'Caro-Kann Defense';
    if (number >= 0 && number <= 9) return 'Scandinavian / Alekhine';
  } else if (letter == 'C') {
    if (number >= 0 && number <= 19) return 'French Defense';
    if (number >= 20 && number <= 59) return 'Open Game';
    if (number >= 60 && number <= 99) return 'Ruy Lopez';
  } else if (letter == 'D') {
    if (number >= 10 && number <= 19) return 'Slav Defense';
    if (number >= 0 && number <= 69) return "Queen's Gambit";
    if (number >= 70 && number <= 99) return 'Grünfeld Defense';
  } else if (letter == 'E') {
    if (number >= 20 && number <= 59) return 'Nimzo-Indian Defense';
    if (number >= 60 && number <= 99) return "King's Indian Defense";
    if (number >= 0 && number <= 9) return 'Catalan Opening';
  } else if (letter == 'A') {
    if (number >= 10 && number <= 39) return 'English Opening';
    if (number >= 40 && number <= 44) return "Queen's Pawn Game";
    if (number >= 80 && number <= 99) return 'Dutch Defense';
  }
  return null;
}
