// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/study.dart';
import 'package:dartchess/dartchess.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PgnExporter');

/// Thrown when a chapter cannot be exported faithfully.
///
/// Export used to truncate silently at the first unreplayable move — dropping
/// it and its whole continuation from the file — and to fail with a raw
/// dartchess error when a stored starting FEN was unparseable. Both now refuse
/// with a message that names the chapter: a PGN that re-imports with lines
/// missing is worse than a refused export (#166).
class PgnExportException implements Exception {
  const PgnExportException(this.message);

  final String message;

  @override
  String toString() => 'PgnExportException: $message';
}

/// Exports a [Chapter] to standard PGN string format.
///
/// Throws [PgnExportException] when the chapter cannot be replayed faithfully:
/// an unparseable starting FEN, or a stored move that is not legal in the
/// position it claims to follow.
String chapterToPgn(Chapter chapter, {String? studyTitle}) {
  final buffer = StringBuffer();

  // Headers
  final event = (chapter.title != null && !chapter.title!.startsWith('Game '))
      ? chapter.title!
      : (studyTitle ?? chapter.title ?? 'Untitled Study');
  buffer.writeln('[Event "${_tagValue(event)}"]');
  buffer.writeln('[Site "ChessSRS"]');
  buffer.writeln('[Date "${_formatDate(chapter.createdAt ?? DateTime.now())}"]');
  final isBlack = chapter.orientation == Side.black;
  buffer.writeln('[White "${isBlack ? 'Opponent' : 'Repertoire'}"]');
  buffer.writeln('[Black "${isBlack ? 'Repertoire' : 'Opponent'}"]');
  buffer.writeln('[Orientation "${isBlack ? 'black' : 'white'}"]');
  buffer.writeln('[Result "*"]');
  if (studyTitle != null && studyTitle.trim().isNotEmpty) {
    buffer.writeln('[Study "${_tagValue(studyTitle.trim())}"]');
  }
  if (chapter.title != null && chapter.title!.trim().isNotEmpty) {
    buffer.writeln('[Chapter "${_tagValue(chapter.title!.trim())}"]');
  }
  // Preserve opening classification across export → re-import so opening
  // scopes and breakdowns survive the round-trip (`extractOpeningFamily`
  // reads `Opening` first, before `Event`/ECO fallbacks).
  if (chapter.opening != null && chapter.opening!.trim().isNotEmpty) {
    buffer.writeln('[Opening "${_tagValue(chapter.opening!.trim())}"]');
  }

  if (chapter.startingFen != null && chapter.startingFen!.isNotEmpty) {
    buffer.writeln('[SetUp "1"]');
    buffer.writeln('[FEN "${chapter.startingFen}"]');
  }

  buffer.writeln();

  if (chapter.root != null && chapter.root!.children.isNotEmpty) {
    _writeNodeMoves(buffer, chapter.root!, position: _startingPosition(chapter));
  }

  buffer.writeln('*');
  buffer.writeln();

  return buffer.toString();
}

/// Exports all chapters in a [Study] to a multi-game PGN string.
///
/// Throws [PgnExportException] if any chapter cannot be replayed faithfully;
/// the first failing chapter refuses the whole export rather than shipping a
/// file with that chapter's moves missing.
String studyToPgn(Study study, List<Chapter> chapters) {
  if (chapters.isEmpty) {
    return chapterToPgn(
      Chapter(id: study.id, studyId: study.id, sourceOrder: 0, title: study.title),
      studyTitle: study.title,
    );
  }

  final sortedChapters = List<Chapter>.from(chapters)
    ..sort((a, b) => a.sourceOrder.compareTo(b.sourceOrder));

  final buffer = StringBuffer();
  for (final chapter in sortedChapters) {
    buffer.write(chapterToPgn(chapter, studyTitle: study.title));
  }
  return buffer.toString();
}

void _writeNodeMoves(
  StringBuffer buffer,
  RepertoireNode node, {
  required Position position,
  bool forceMoveNumber = false,
}) {
  if (node.children.isEmpty) return;

  final mainline = node.children.first;
  final variations = node.children.sublist(1);

  final move = mainline.incomingMove;
  if (move != null) {
    final isWhite = position.turn == Side.white;
    if (isWhite) {
      buffer.write('${position.fullmoves}. ');
    } else if (forceMoveNumber) {
      buffer.write('${position.fullmoves}... ');
    }
    buffer.write('${move.san} ');

    if (mainline.comment != null && mainline.comment!.trim().isNotEmpty) {
      buffer.write('{${mainline.comment!.trim()}} ');
    }

    final nextPos = _playMove(position, move);

    // Write sibling variations in parentheses
    for (final variation in variations) {
      final varMove = variation.incomingMove;
      if (varMove != null) {
        final varBuffer = StringBuffer();
        if (isWhite) {
          varBuffer.write('${position.fullmoves}. ');
        } else {
          varBuffer.write('${position.fullmoves}... ');
        }
        varBuffer.write('${varMove.san} ');

        if (variation.comment != null && variation.comment!.trim().isNotEmpty) {
          varBuffer.write('{${variation.comment!.trim()}} ');
        }

        final varNextPos = _playMove(position, varMove);
        _writeNodeMoves(varBuffer, variation, position: varNextPos, forceMoveNumber: false);
        buffer.write('(${varBuffer.toString().trim()}) ');
      }
    }

    _writeNodeMoves(buffer, mainline, position: nextPos, forceMoveNumber: variations.isNotEmpty);
  } else {
    // Root node: recurse through children
    for (var i = 0; i < node.children.length; i++) {
      if (i == 0) {
        _writeNodeMoves(buffer, node.children[i], position: position, forceMoveNumber: true);
      } else {
        buffer.write('(');
        _writeNodeMoves(buffer, node.children[i], position: position, forceMoveNumber: true);
        buffer.write(') ');
      }
    }
  }
}

/// The chapter's starting position.
///
/// Refuses the export when the stored FEN cannot be parsed, instead of taking
/// the whole export down with a raw dartchess error that names nothing.
Position _startingPosition(Chapter chapter) {
  final fen = chapter.startingFen;
  if (fen == null || fen.isEmpty) return Chess.initial;
  try {
    return Chess.fromSetup(Setup.parseFen(fen));
  } catch (e) {
    final title = chapter.title ?? 'Untitled';
    _logger.warning('Refusing to export "$title": unparseable starting FEN "$fen".', e);
    throw PgnExportException(
      'Chapter "$title" has an unparseable starting position ("$fen"); '
      'refusing to export rather than dropping its moves.',
    );
  }
}

/// Plays [move] on [pos], refusing the export when the stored move is illegal.
///
/// Silently skipping was the old behaviour: the rest of the line vanished from
/// the file with no log and no error, so an exported PGN could re-import with
/// everything after the unreplayable move gone (#166).
Position _playMove(Position pos, RepertoireMove move) {
  try {
    final from = Square.fromName(move.from);
    final to = Square.fromName(move.to);
    final promotion = move.promotion != null ? Role.fromChar(move.promotion!) : null;
    return pos.play(NormalMove(from: from, to: to, promotion: promotion));
  } catch (e) {
    final label = move.san ?? '${move.from}${move.to}${move.promotion ?? ''}';
    _logger.warning('Refusing to export: "$label" does not replay at ${pos.fen}.', e);
    throw PgnExportException(
      'Move "$label" cannot be replayed against the stored position; '
      'refusing to export rather than truncating the line.',
    );
  }
}

/// Escapes a value for a quoted PGN tag. PGN (section 8.1.1) allows only `\"` and `\\` inside the
/// quotes, and a tag occupies a single line. Unescaped, a title such as `Najdorf "Poisoned"` closed
/// the tag early and left the rest of the header malformed in every file it was exported to.
String _tagValue(String value) {
  final quoted = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return quoted.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y.$m.$d';
}
