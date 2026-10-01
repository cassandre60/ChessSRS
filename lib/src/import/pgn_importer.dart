// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/position_knowledge_state.dart';
import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/study.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:crypto/crypto.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';

final Logger _logger = Logger('StudyImporter');

/// Computes a canonical SHA-256 fingerprint for PGN content based on its
/// starting positions and move variation trees (Listudy tree_hash pattern).
///
/// Strips volatile metadata tags (Event, Site, Date, Round, etc.) so that
/// renaming a study or modifying PGN headers preserves the repertoire identity.
String computePgnHash(String pgnText, [List<PgnGame<PgnNodeData>>? games]) {
  try {
    final parsed = games ?? PgnGame.parseMultiGamePgn(pgnText);
    if (parsed.isNotEmpty) {
      final buffer = StringBuffer();
      for (final game in parsed) {
        // The starting position is resolved exactly as importPgn resolves it, rather than read
        // off the header. dartchess rewrites a legal FEN on the way in — an en-passant square no
        // pawn can capture becomes '-', castling rights come back in canonical order — and a
        // Chapter stores that normalised form as its startingFen. Hashing the raw header text
        // instead gave this function a different answer from computeRepertoireTreeHash for
        // every PGN that starts from a FEN, which is what stopped a backfilled study from ever
        // being recognised as a duplicate of the file it came from.
        if (game.headers['FEN'] != null && game.headers['FEN']!.trim().isNotEmpty) {
          try {
            buffer.write('FEN:${fenKey(PgnGame.startingPosition(game.headers).fen)};');
          } catch (_) {
            // An unusable FEN makes the whole chapter unimportable, so it contributes no moves
            // either; hashing it here would make this fingerprint depend on bytes the import
            // path ignores.
          }
        }
        _appendPgnNodeMoves(game.moves, buffer);
        buffer.write('|');
      }
      final canonicalStr = buffer.toString();
      if (canonicalStr.isNotEmpty) {
        return sha256.convert(utf8.encode(canonicalStr)).toString();
      }
    }
  } catch (e, st) {
    _logger.warning('Tree-based PGN hash failed, falling back to text hash', e, st);
  }

  // Fallback if parsing fails
  final normalized = pgnText.trim();
  return sha256.convert(utf8.encode(normalized)).toString();
}

/// Asynchronously computes a canonical SHA-256 fingerprint for PGN content on a background isolate,
/// avoiding UI thread hitching on large multi-megabyte PGN files.
Future<String> computePgnHashAsync(String pgnText) {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST') || pgnText.length < 8192) {
    return Future.value(computePgnHash(pgnText));
  }
  return Isolate.run(() => computePgnHash(pgnText));
}

void _appendPgnNodeMoves(PgnNode<PgnNodeData> node, StringBuffer buffer) {
  for (final child in node.children) {
    buffer.write(child.data.san);
    buffer.write(',');
    _appendPgnNodeMoves(child, buffer);
  }
}

/// Computes a canonical SHA-256 fingerprint from domain [Chapter] trees.
///
/// Guaranteed to produce the exact same fingerprint as [computePgnHash] for
/// identical chess material, allowing automatic backfilling of existing studies.
String computeRepertoireTreeHash(List<Chapter> chapters) {
  final buffer = StringBuffer();
  for (final ch in chapters) {
    if (ch.startingFen != null && ch.startingFen!.trim().isNotEmpty) {
      buffer.write('FEN:${fenKey(ch.startingFen!)};');
    }
    if (ch.root != null) {
      _appendRepertoireNodeMoves(ch.root!, buffer);
    }
    buffer.write('|');
  }
  final canonicalStr = buffer.toString();
  return sha256.convert(utf8.encode(canonicalStr)).toString();
}

void _appendRepertoireNodeMoves(RepertoireNode node, StringBuffer buffer) {
  for (final child in node.children) {
    if (child.incomingMove != null) {
      buffer.write(child.incomingMove!.san);
      buffer.write(',');
    }
    _appendRepertoireNodeMoves(child, buffer);
  }
}

/// Structured error produced during PGN import.
///
/// Contains enough context (chapter title + move index) to let the user
/// locate the offending move (QUALITY.md §3.1: Graceful Degradation).
class ImportError {
  const ImportError({required this.chapterTitle, required this.moveIndex, required this.message});

  /// Chapter (game) in which the error occurred.
  final String chapterTitle;

  /// 0-based index of the move in the game that triggered the error.
  /// -1 means the error applies to the whole chapter (e.g. bad FEN header).
  final int moveIndex;

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() =>
      'ImportError(chapter: "$chapterTitle", moveIndex: $moveIndex, message: "$message")';
}

/// Complete result of a PGN import operation.
class ImportResult {
  const ImportResult({
    required this.study,
    required this.chapters,
    required this.decisions,
    required this.errors,
    this.isDuplicate = false,
  });

  /// The created [Study] container.
  final Study study;

  /// Successfully imported chapters (one per PGN game).
  final List<Chapter> chapters;

  /// All [RepertoireDecision]s derived from the imported chapters.
  final List<RepertoireDecision> decisions;

  /// Structured errors encountered during import.
  /// Non-empty means some chapters or moves were skipped or quarantined.
  final List<ImportError> errors;

  /// Whether this import was identified as an exact duplicate of an existing study.
  final bool isDuplicate;

  bool get hasErrors => errors.isNotEmpty;
  bool get isEmpty => chapters.isEmpty;

  @override
  String toString() =>
      'ImportResult(chapters: ${chapters.length}, decisions: ${decisions.length}, '
      'errors: ${errors.length}, duplicate: $isDuplicate)';
}

/// Derives a 4-field FEN position key from a full 6-field FEN.
///
/// The key is: `<placement> <turn> <castling> <ep>`
/// (QUALITY.md §2.3: Position Identity Integrity). The contract itself lives with the chess
/// primitives in [positionIdentity]; this stays as the name the importer has always used.
String fenKey(String fullFen) => positionIdentity(fullFen);

/// Converts a dartchess [NormalMove] and [Position] into a domain [RepertoireMove].
RepertoireMove normalmoveToRepertoireMove(NormalMove move, Position position) {
  final (_, san) = position.makeSan(move);
  return RepertoireMove(
    from: move.from.name,
    to: move.to.name,
    promotion: move.promotion?.letter,
    san: san,
  );
}

/// Imports a multi-game PGN string into a [Study] with [Chapter]s and [RepertoireDecision]s.
///
/// The [repertoireSide] is the [Side] whose moves become [RepertoireDecision]s.
/// Opponent moves are recorded in the tree but not scheduled.
/// When [repertoireSide] is null, every node with at least one continuation
/// becomes a decision (useful for training both sides).
///
/// Errors are collected rather than thrown. A chapter with a fatal error
/// (e.g. bad starting FEN) is omitted from [ImportResult.chapters]; a
/// chapter with recoverable move errors is included with a truncated tree.
ImportResult importPgn(
  String pgnText, {
  String studyTitle = 'Imported Study',
  Side? repertoireSide,
  String? pgnHash,
  List<PgnGame<PgnNodeData>>? parsedGames,
}) {
  final sw = Stopwatch()..start();
  final hash =
      pgnHash ??
      (parsedGames != null ? computePgnHash(pgnText, parsedGames) : computePgnHash(pgnText));
  _logger.info(
    'Starting PGN import for "$studyTitle" (${pgnText.length} chars, hash: ${hash.substring(0, 8)})...',
  );

  final List<PgnGame<PgnNodeData>> games;
  if (parsedGames != null) {
    games = parsedGames;
  } else {
    try {
      games = PgnGame.parseMultiGamePgn(pgnText);
    } catch (e) {
      // Catastrophic parse failure — return an empty result with one error.
      _logger.severe('Catastrophic PGN parse failure for "$studyTitle": $e');
      final study = Study.create(title: studyTitle, pgnHash: hash);
      return ImportResult(
        study: study,
        chapters: const [],
        decisions: const [],
        errors: [ImportError(chapterTitle: studyTitle, moveIndex: -1, message: e.toString())],
      );
    }
  }

  if (games.isEmpty) {
    _logger.warning('PGN import for "$studyTitle" found 0 games');
    final study = Study.create(title: studyTitle, pgnHash: hash);
    return ImportResult(
      study: study,
      chapters: const [],
      decisions: const [],
      errors: [
        ImportError(
          chapterTitle: studyTitle,
          moveIndex: -1,
          message: 'No games found in the PGN. Check that the text is a PGN and not empty.',
        ),
      ],
    );
  }

  final study = Study.create(title: studyTitle, pgnHash: hash);
  final chapters = <Chapter>[];
  final decisions = <RepertoireDecision>[];
  final errors = <ImportError>[];

  for (var i = 0; i < games.length; i++) {
    final game = games[i];
    final headers = game.headers;

    // Derive a human-readable chapter title from PGN headers.
    final chapterTitle = _chapterTitle(headers, i);

    // Resolve starting position.
    Position startPosition;
    String startingFen;
    try {
      startPosition = PgnGame.startingPosition(headers);
      startingFen = startPosition.fen;
    } catch (e) {
      errors.add(
        ImportError(
          chapterTitle: chapterTitle,
          moveIndex: -1,
          message: 'Invalid starting position: $e',
        ),
      );
      continue; // skip this chapter
    }

    // Build the RepertoireNode tree, collecting any per-move errors.
    final chapterErrors = <ImportError>[];
    final root = _buildRoot(game.moves, startPosition, startingFen, chapterTitle, chapterErrors);

    errors.addAll(chapterErrors);

    final opening = extractOpeningFamily(headers);
    final chapterOrientation = resolveChapterOrientation(
      headers,
      explicitSide: repertoireSide,
      startTurn: startPosition.turn,
    );

    final chapter = Chapter.create(
      studyId: study.id,
      sourceOrder: i,
      title: chapterTitle,
      startingFen: headers.containsKey('FEN') ? startingFen : null,
      root: root,
      opening: opening,
      orientation: chapterOrientation,
    );
    chapters.add(chapter);

    // Derive decisions for this chapter.
    if (root != null) {
      final explicitTag = headers['Orientation']?.trim().toLowerCase();
      final effectiveDecisionSide =
          repertoireSide ??
          (explicitTag == 'black'
              ? Side.black
              : explicitTag == 'white'
              ? Side.white
              : chapterOrientation);

      _deriveDecisions(
        root,
        study.id,
        chapter.id,
        startPosition.turn,
        effectiveDecisionSide,
        decisions,
      );
    }
  }

  sw.stop();

  // A chapter whose tree holds no move for the repertoire side contributes no decision, so an
  // import can parse cleanly, build chapters, and still contain nothing to train. Reporting that
  // as a success is what let an empty file — or a line of plain text — be announced as imported
  // and stored as a study. Only raised when nothing else has already explained the failure:
  // a specific bad-FEN or illegal-move error says more than this summary would.
  if (decisions.isEmpty && errors.isEmpty) {
    errors.add(
      ImportError(
        chapterTitle: chapters.isEmpty ? studyTitle : chapters.map((c) => c.title).join(', '),
        moveIndex: -1,
        message:
            'No repertoire positions were found. The PGN parsed, but it contains no moves for '
            'the selected side.',
      ),
    );
  }

  _logger.info(
    'PGN import completed for "$studyTitle": ${chapters.length} chapters, '
    '${decisions.length} decisions, ${errors.length} errors in ${sw.elapsedMilliseconds}ms',
  );
  if (errors.isNotEmpty) {
    _logger.warning(
      'PGN import encountered ${errors.length} error(s): ${errors.take(5).join("; ")}',
    );
  }

  return ImportResult(study: study, chapters: chapters, decisions: decisions, errors: errors);
}

/// Asynchronously imports a multi-game PGN string on a background worker isolate,
/// preventing frame drops on the main UI thread during heavy tree building and parsing.
Future<ImportResult> importPgnAsync(
  String pgnText, {
  String studyTitle = 'Imported Study',
  Side? repertoireSide,
  String? pgnHash,
}) {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST') || pgnText.length < 8192) {
    return Future.value(
      importPgn(pgnText, studyTitle: studyTitle, repertoireSide: repertoireSide, pgnHash: pgnHash),
    );
  }
  return Isolate.run(
    () => importPgn(
      pgnText,
      studyTitle: studyTitle,
      repertoireSide: repertoireSide,
      pgnHash: pgnHash,
    ),
  );
}

// ---------------------------------------------------------------------------
// Orientation & Title resolution
// ---------------------------------------------------------------------------

/// Derives the intended player perspective / repertoire side for a chapter from PGN headers.
///
/// Priority:
/// 1. Explicit override: if [explicitSide] is provided (e.g. user selected 'White' or 'Black'), honor it.
/// 2. Explicit PGN header tag `[Orientation "black"]` / `[Orientation "white"]` (case-insensitive).
/// 3. Title / Event / ChapterName / StudyName keyword heuristics:
///    - "for Black", "(Black)", "[Black]", "as Black", "vs White" -> Black
///    - "for White", "(White)", "[White]", "as White", "vs Black" -> White
/// 4. Player tags: e.g. White "?" vs Black "Sicilian", or player containing "Repertoire"
/// 5. Start position turn: if the custom FEN has Black to move
/// 6. Default: White.
Side resolveChapterOrientation(
  PgnHeaders headers, {
  Side? explicitSide,
  Side startTurn = Side.white,
}) {
  if (explicitSide != null) return explicitSide;

  // 2. Explicit Orientation tag
  final orientationTag = headers['Orientation']?.trim().toLowerCase();
  if (orientationTag == 'black') {
    _logger.fine('Orientation resolved via explicit header: black');
    return Side.black;
  }
  if (orientationTag == 'white') {
    _logger.fine('Orientation resolved via explicit header: white');
    return Side.white;
  }

  // 3. Event / ChapterName / StudyName keyword heuristics. Also read the
  // plain Chapter/Study tags our own exporter writes (Lichess uses
  // ChapterName/StudyName), so self round-trips keep the signal.
  final titleCandidates = [
    headers['ChapterName'],
    headers['Chapter'],
    headers['Event'],
    headers['StudyName'],
    headers['Study'],
  ];
  final blackKeywords = RegExp(
    r'(\bfor black\b|\bas black\b|\[black\]|\(black\)|\bblack repertoire\b|\bvs white\b)',
    caseSensitive: false,
  );
  final whiteKeywords = RegExp(
    r'(\bfor white\b|\bas white\b|\[white\]|\(white\)|\bwhite repertoire\b|\bvs black\b)',
    caseSensitive: false,
  );

  for (final candidate in titleCandidates) {
    if (candidate == null || candidate.trim().isEmpty) continue;
    if (blackKeywords.hasMatch(candidate)) {
      _logger.fine('Orientation resolved via keyword in "$candidate": black');
      return Side.black;
    }
    if (whiteKeywords.hasMatch(candidate)) {
      _logger.fine('Orientation resolved via keyword in "$candidate": white');
      return Side.white;
    }
  }

  // 4. Player tags heuristic
  final white = headers['White']?.trim();
  final black = headers['Black']?.trim();
  final whiteIsPlaceholder = white == null || white == '?' || white == '*' || white.isEmpty;
  final blackIsPlaceholder = black == null || black == '?' || black == '*' || black.isEmpty;

  if (whiteIsPlaceholder && !blackIsPlaceholder) {
    _logger.fine('Orientation resolved via placeholder opponent: black');
    return Side.black;
  }
  if (blackIsPlaceholder && !whiteIsPlaceholder) {
    _logger.fine('Orientation resolved via placeholder opponent: white');
    return Side.white;
  }

  if (black != null && black.toLowerCase().contains('repertoire')) {
    _logger.fine('Orientation resolved via player tag "black": black');
    return Side.black;
  }
  if (white != null && white.toLowerCase().contains('repertoire')) {
    _logger.fine('Orientation resolved via player tag "white": white');
    return Side.white;
  }

  // 4. The side to move in a custom starting position. With no other signal this is the only
  //    thing left that says whose moves the chapter is about, and defaulting to White instead
  //    shifts the whole tree a ply: every decision derived from it asks the player for a move
  //    their opponent plays.
  if (startTurn == Side.black) {
    _logger.fine('Orientation resolved via starting position turn: black');
    return Side.black;
  }

  return Side.white;
}

String _chapterTitle(PgnHeaders headers, int index) {
  // A dedicated title tag wins outright. This app's own exporter writes one ([Chapter], and
  // [Study] for the parent), so reading it first is what makes export -> re-import preserve the
  // name instead of collapsing every chapter onto the exporter's placeholder player tags.
  for (final key in ['Chapter', 'ChapterName']) {
    final v = headers[key];
    if (v != null && v.trim().isNotEmpty && v != '?') return v.trim();
  }

  // Then a meaningful player matchup, but only when both names are real. The exporter always
  // writes "Repertoire"/"Opponent" here, so those are placeholders, not a matchup to display.
  final white = headers['White']?.trim();
  final black = headers['Black']?.trim();
  if (!_isPlaceholderPlayerTag(white) && !_isPlaceholderPlayerTag(black)) {
    return '$white vs $black';
  }

  // Fall back to Event or Site.
  for (final key in ['Event', 'Site']) {
    final v = headers[key];
    if (v != null && v.trim().isNotEmpty && v != '?') return v.trim();
  }

  return 'Game ${index + 1}';
}

/// Whether a PGN player tag is a placeholder rather than a person.
///
/// `?` and `*` are the PGN conventions. `Repertoire` and `Opponent` are this app's own: the
/// exporter writes them into [White]/[Black] to record which side the chapter is about, and
/// writes the real names nowhere else. Treating them as a matchup to display is what made every
/// exported chapter come back as "Repertoire vs Opponent".
bool _isPlaceholderPlayerTag(String? name) {
  if (name == null || name.isEmpty) return true;
  final n = name.toLowerCase();
  return n == '?' || n == '*' || n == 'repertoire' || n == 'opponent';
}

/// Builds a [RepertoireNode] root from the PGN node tree, or null on fatal error.
RepertoireNode? _buildRoot(
  PgnNode<PgnNodeData> pgnRoot,
  Position startPosition,
  String startingFen,
  String chapterTitle,
  List<ImportError> errors,
) {
  final root = RepertoireNode.root(fen: startingFen, fenKey: fenKey(startingFen));

  // If there are no moves, return the empty root (a chapter can be a position study).
  if (pgnRoot.children.isEmpty) return root;

  final result = _buildChildren(pgnRoot, root, startPosition, chapterTitle, errors, 0);
  return result;
}

/// Counts the moves in the subtree rooted at [node], excluding [node] itself.
///
/// Used to tell the user how much of a line is dropped along with an
/// unparseable or illegal move, whose whole continuation is skipped.
int _countDescendantMoves(PgnNode<PgnNodeData> node) {
  var count = 0;
  for (final child in node.children) {
    count += 1 + _countDescendantMoves(child);
  }
  return count;
}

/// Recursively builds children from a [PgnNode], returning the updated parent.
RepertoireNode _buildChildren(
  PgnNode<PgnNodeData> pgnNode,
  RepertoireNode parent,
  Position position,
  String chapterTitle,
  List<ImportError> errors,
  int moveIndex,
) {
  var current = parent;
  for (final pgnChild in pgnNode.children) {
    final data = pgnChild.data;
    final san = data.san;

    // Parse the SAN move against the current position.
    final Move? parsed;
    try {
      parsed = position.parseSan(san);
    } catch (e) {
      final skipped = _countDescendantMoves(pgnChild);
      errors.add(
        ImportError(
          chapterTitle: chapterTitle,
          moveIndex: moveIndex,
          message:
              'Could not parse move "$san": $e. '
              'Skipping it and $skipped following move(s) in this line.',
        ),
      );
      continue;
    }

    if (parsed == null) {
      final skipped = _countDescendantMoves(pgnChild);
      errors.add(
        ImportError(
          chapterTitle: chapterTitle,
          moveIndex: moveIndex,
          message:
              'Illegal or unrecognized move "$san" at position ${position.fen}. '
              'Skipping it and $skipped following move(s) in this line.',
        ),
      );
      continue;
    }

    if (parsed is! NormalMove) {
      // Drop moves are not part of opening repertoires; skip silently.
      continue;
    }

    final reperMove = normalmoveToRepertoireMove(parsed, position);
    final nextPosition = position.play(parsed);
    final nextFen = nextPosition.fen;

    // Concatenate pre-move (starting) and post-move comments: studies
    // routinely carry both ("{before} 1. e4 {after}"), and either/or drops one.
    final comment = [...?data.startingComments, ...?data.comments].join(' ').trim();

    var childNode = RepertoireNode.child(
      fen: nextFen,
      fenKey: fenKey(nextFen),
      incomingMove: reperMove,
      comment: comment.isNotEmpty ? comment : null,
    );

    // Recurse into this child's subtree.
    childNode = _buildChildren(
      pgnChild,
      childNode,
      nextPosition,
      chapterTitle,
      errors,
      moveIndex + 1,
    );

    current = current.addChild(childNode);
  }

  return current;
}

/// Derives [RepertoireDecision]s from a position tree.
///
/// A decision is created at any node where:
/// - The side to move matches [repertoireSide] (or [repertoireSide] is null), AND
/// - The node has at least one child (there is a move to recall).
void _deriveDecisions(
  RepertoireNode node,
  String studyId,
  String chapterId,
  Side nodeSideToMove,
  Side? repertoireSide,
  List<RepertoireDecision> out,
) {
  if (node.children.isNotEmpty) {
    final isRepertoireSide = repertoireSide == null || nodeSideToMove == repertoireSide;

    if (isRepertoireSide) {
      // A decision is identified by the position *and* every move it accepts, not by one
      // representative child: two positions sharing a FEN and a first move but offering
      // different continuations are different questions and must not share SRS memory.
      final cKey = canonicalKeyForPosition(node.fenKey, node.childMoves.map((move) => move.uci));
      out.add(
        RepertoireDecision.create(
          studyId: studyId,
          chapterId: chapterId,
          nodeId: node.id,
          expectedMoves: node.childMoves,
          canonicalStateId: cKey,
        ),
      );
    }

    // Recurse into children, flipping the side to move.
    final nextSide = nodeSideToMove == Side.white ? Side.black : Side.white;
    for (final child in node.children) {
      _deriveDecisions(child, studyId, chapterId, nextSide, repertoireSide, out);
    }
  }
}

/// Automatically extracts a normalized opening family name from PGN headers.
String? extractOpeningFamily(PgnHeaders headers) {
  // 1. Direct Opening header (e.g. "Sicilian Defense: Najdorf Variation")
  final opening = headers['Opening'];
  if (opening != null && opening.trim().isNotEmpty && opening != '?') {
    return _simplifyOpeningName(opening.trim());
  }

  // 2. Check Event header (e.g. "Sicilian Defense", "French Defence - Winawer")
  final event = headers['Event'];
  if (event != null && event.trim().isNotEmpty && event != '?' && !event.startsWith('Game ')) {
    final simplified = _simplifyOpeningName(event.trim());
    if (_isLikelyOpeningName(simplified)) {
      return simplified;
    }
  }

  // 3. Fallback: ECO code classification (standard FIDE/ChessBase ECO families)
  final eco = headers['ECO'];
  if (eco != null && eco.trim().isNotEmpty && eco != '?') {
    return _ecoToOpeningFamily(eco.trim().toUpperCase());
  }

  return null;
}

String _simplifyOpeningName(String raw) {
  // Split on ':' and ',' always, and on '-' only when spaced: "French Defence
  // - Winawer" separates family from variation, but "Caro-Kann" is one name.
  final splitColon = raw.split(RegExp(r':|,|\s+-\s+'));
  if (splitColon.isNotEmpty && splitColon.first.trim().isNotEmpty) {
    return splitColon.first.trim();
  }
  return raw.trim();
}

bool _isLikelyOpeningName(String name) {
  final lower = name.toLowerCase();
  const keywords = [
    'defense',
    'defence',
    'game',
    'gambit',
    'opening',
    'attack',
    'system',
    'sicilian',
    'french',
    'caro-kann',
    'caro',
    'ruy lopez',
    'italian',
    'scotch',
    "king's indian",
    'kings indian',
    "queen's indian",
    'queens indian',
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
  return keywords.any((k) => lower.contains(k));
}

String? _ecoToOpeningFamily(String eco) {
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
