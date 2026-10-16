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
/// anywhere else matches nothing. The importer asks this question of the
/// explicit `Opening` header too, so an import cannot recreate a hub the repair
/// migration removed; a name this build does not recognise is kept rather than
/// guessed at (INV-067).
library;

import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:dartchess/dartchess.dart';

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

/// Normalizes an opening family name: standardizes UK/US spelling variants
/// (e.g. "Defence" -> "Defense", "Grunfeld" -> "Grünfeld").
String normalizeOpeningFamily(String name) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'\bdefence\b', caseSensitive: false), 'Defense');
  s = s.replaceAll(RegExp(r'\bGrunfeld\b', caseSensitive: false), 'Grünfeld');
  return s;
}

/// Reduces a PGN opening or event header to its family.
///
/// Splits on `:` and `,` always, and on `-` only when spaced: "French Defence
/// - Winawer" separates family from variation, but "Caro-Kann" is one name.
String simplifyOpeningName(String raw) {
  final splitColon = raw.split(RegExp(r':|,|\s+-\s+'));
  if (splitColon.isNotEmpty && splitColon.first.trim().isNotEmpty) {
    return normalizeOpeningFamily(splitColon.first.trim());
  }
  return normalizeOpeningFamily(raw.trim());
}

/// Detects opening family by inspecting the mainline moves in [root].
String? detectOpeningFamilyFromMoves(RepertoireNode? root) {
  if (root == null) return null;
  final sans = <String>[];
  var current = root;
  while (current.children.isNotEmpty && sans.length < 8) {
    final next = current.children.first;
    final san = next.incomingMove?.san;
    if (san != null) {
      sans.add(san);
    }
    current = next;
  }
  if (sans.isEmpty) return null;

  final m1 = sans[0];
  final m2 = sans.length > 1 ? sans[1] : null;
  final m3 = sans.length > 2 ? sans[2] : null;
  final m4 = sans.length > 3 ? sans[3] : null;
  final m5 = sans.length > 4 ? sans[4] : null;
  final m6 = sans.length > 5 ? sans[5] : null;

  if (m1 == 'e4') {
    if (m2 == 'e6') return 'French Defense';
    if (m2 == 'c5') return 'Sicilian Defense';
    if (m2 == 'c6') return 'Caro-Kann Defense';
    if (m2 == 'd5') return 'Scandinavian Defense';
    if (m2 == 'Nf6') return 'Alekhine Defense';
    if (m2 == 'd6') return 'Pirc Defense';
    if (m2 == 'g6') return 'Modern Defense';
    if (m2 == 'e5') {
      if (m3 == 'Nf3') {
        if (m4 == 'Nc6') {
          if (m5 == 'Bb5') return 'Ruy Lopez';
          if (m5 == 'Bc4') return 'Italian Game';
          if (m5 == 'd4') return 'Scotch Game';
          if (m5 != null) return 'Open Game';
        }
        if (m4 == 'Nf6') return 'Petrov Defense';
        if (m4 == 'd6') return 'Philidor Defense';
      } else if (m3 == 'f4') {
        return "King's Gambit";
      } else if (m3 == 'Nc3') {
        return 'Vienna Game';
      }
    }
  } else if (m1 == 'd4') {
    if (m2 == 'd5') {
      if (m3 == 'c4') {
        if (m4 == 'c6') return 'Slav Defense';
        return "Queen's Gambit";
      }
      if (m3 == 'Bf4' || (m3 == 'Nf3' && m5 == 'Bf4')) return 'London System';
      return "Queen's Pawn Game";
    }
    if (m2 == 'Nf6') {
      if (m3 == 'c4') {
        if (m4 == 'g6') {
          if (m6 == 'd5') return 'Grünfeld Defense';
          return "King's Indian Defense";
        }
        if (m4 == 'e6') {
          if (m5 == 'Nc3' && m6 == 'Bb4') return 'Nimzo-Indian Defense';
          if (m5 == 'Nf3' && m6 == 'b6') return "Queen's Indian Defense";
          if (m5 == 'g3') return 'Catalan Opening';
          return "Queen's Pawn Game";
        }
        if (m4 == 'c5') return 'Benoni Defense';
        return "Queen's Pawn Game";
      }
      if (m3 == 'Bf4' || (m3 == 'Nf3' && m5 == 'Bf4')) return 'London System';
      return "Queen's Pawn Game";
    }
    if (m2 == 'f5') return 'Dutch Defense';
    return "Queen's Pawn Game";
  } else if (m1 == 'c4') {
    return 'English Opening';
  } else if (m1 == 'Nf3') {
    return 'Réti Opening';
  }
  return null;
}

/// Detects opening family by inspecting piece placement in a custom starting [fen].
String? detectOpeningFamilyFromFen(String fen) {
  try {
    final setup = Setup.parseFen(fen.trim());
    final board = setup.board;

    bool isPawn(Square sq, Side color) {
      final p = board.pieceAt(sq);
      return p != null && p.role == Role.pawn && p.color == color;
    }

    final e6Black = isPawn(Square.fromName('e6'), Side.black);
    final c5Black = isPawn(Square.fromName('c5'), Side.black);
    final c6Black = isPawn(Square.fromName('c6'), Side.black);
    final d5Black = isPawn(Square.fromName('d5'), Side.black);
    final g6Black = isPawn(Square.fromName('g6'), Side.black);

    final e4White = isPawn(Square.fromName('e4'), Side.white);
    final e5White = isPawn(Square.fromName('e5'), Side.white);
    final d4White = isPawn(Square.fromName('d4'), Side.white);
    final c4White = isPawn(Square.fromName('c4'), Side.white);

    // French Defense: Black has e6, White has d4 and (e4 or e5)
    if (e6Black && (e4White || e5White) && d4White) {
      return 'French Defense';
    }
    // Sicilian Defense: Black has c5, White has e4
    if (c5Black && e4White) {
      return 'Sicilian Defense';
    }
    // Caro-Kann Defense: Black has c6, White has e4
    if (c6Black && e4White) {
      return 'Caro-Kann Defense';
    }
    // Scandinavian Defense: Black has d5, White has e4, no d4
    if (d5Black && e4White && !d4White) {
      return 'Scandinavian Defense';
    }
    // Queen's Gambit / Slav: White has d4 and c4, Black has d5
    if (d4White && c4White && d5Black) {
      if (c6Black) return 'Slav Defense';
      return "Queen's Gambit";
    }
    // Indian defenses: White has d4 and c4, Black has g6
    if (d4White && c4White && g6Black) {
      if (d5Black) return 'Grünfeld Defense';
      return "King's Indian Defense";
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Reads the opening family from [headers], or falls back to move/FEN tree inspection.
///
/// A direct `Opening` header is trusted through the simplification, with one
/// check: a name that merely mentions a family is dropped by exactly the rule
/// the repair migration applies to stored rows
/// ([mentionsOpeningButIsNotFamily]), so an import cannot recreate a hub the
/// repair removed. `Event` and `ECO` are fallbacks that have to prove
/// themselves; an `Opening` header this build does not recognise is kept
/// as-is. If headers yield nothing, [root] and [startingFen] are inspected.
String? extractOpeningFamily(PgnHeaders headers, {RepertoireNode? root, String? startingFen}) {
  // 1. Direct Opening header (e.g. "Sicilian Defense: Najdorf Variation").
  // A header that merely mentions a family ("White vs French") is not an
  // opening either: the one-shot repair cleared rows like it, and an import
  // after the repair must not put the phantom hub back (INV-067).
  final opening = headers['Opening'];
  if (opening != null && opening.trim().isNotEmpty && opening != '?') {
    final simplified = simplifyOpeningName(opening.trim());
    if (!mentionsOpeningButIsNotFamily(simplified)) {
      return simplified;
    }
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
    final fromEco = ecoToOpeningFamily(eco.trim().toUpperCase());
    if (fromEco != null) return fromEco;
  }

  // 4. Move tree inspection fallback
  final fromMoves = detectOpeningFamilyFromMoves(root);
  if (fromMoves != null) return fromMoves;

  // 5. Custom FEN piece-placement inspection fallback
  if (startingFen != null) {
    final fromFen = detectOpeningFamilyFromFen(startingFen);
    if (fromFen != null) return fromFen;
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
