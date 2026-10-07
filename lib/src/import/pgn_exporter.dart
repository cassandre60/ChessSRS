// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/study.dart';
import 'package:dartchess/dartchess.dart';

/// Exports a [Chapter] to standard PGN string format.
String chapterToPgn(Chapter chapter, {String? studyTitle}) {
  final buffer = StringBuffer();

  // Headers
  final event = (chapter.title != null && !chapter.title!.startsWith('Game '))
      ? chapter.title!
      : (studyTitle ?? chapter.title ?? 'Untitled Study');
  buffer.writeln('[Event "$event"]');
  buffer.writeln('[Site "ChessSRS"]');
  buffer.writeln('[Date "${_formatDate(chapter.createdAt ?? DateTime.now())}"]');
  final isBlack = chapter.orientation == Side.black;
  buffer.writeln('[White "${isBlack ? 'Opponent' : 'Repertoire'}"]');
  buffer.writeln('[Black "${isBlack ? 'Repertoire' : 'Opponent'}"]');
  buffer.writeln('[Orientation "${isBlack ? 'black' : 'white'}"]');
  buffer.writeln('[Result "*"]');
  if (studyTitle != null && studyTitle.trim().isNotEmpty) {
    buffer.writeln('[Study "${studyTitle.trim()}"]');
  }
  if (chapter.title != null && chapter.title!.trim().isNotEmpty) {
    buffer.writeln('[Chapter "${chapter.title!.trim()}"]');
  }
  // Preserve opening classification across export → re-import so opening
  // scopes and breakdowns survive the round-trip (`extractOpeningFamily`
  // reads `Opening` first, before `Event`/ECO fallbacks).
  if (chapter.opening != null && chapter.opening!.trim().isNotEmpty) {
    buffer.writeln('[Opening "${chapter.opening!.trim()}"]');
  }

  // A corrupt stored FEN must never crash export: fall back to the initial
  // position and omit the SetUp/FEN headers rather than emitting lies.
  var validStartingFen = false;
  Position startPos = Chess.initial;
  if (chapter.startingFen != null && chapter.startingFen!.isNotEmpty) {
    try {
      startPos = Chess.fromSetup(Setup.parseFen(chapter.startingFen!));
      validStartingFen = true;
    } catch (_) {
      startPos = Chess.initial;
    }
  }
  if (validStartingFen) {
    buffer.writeln('[SetUp "1"]');
    buffer.writeln('[FEN "${chapter.startingFen}"]');
  }

  buffer.writeln();

  if (chapter.root != null && chapter.root!.children.isNotEmpty) {
    _writeNodeMoves(buffer, chapter.root!, position: startPos);
  }

  buffer.writeln('*');
  buffer.writeln();

  return buffer.toString();
}

/// Exports all chapters in a [Study] to a multi-game PGN string.
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
    buffer.write('${_exportSan(position, move)} ');

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
        varBuffer.write('${_exportSan(position, varMove)} ');

        if (variation.comment != null && variation.comment!.trim().isNotEmpty) {
          varBuffer.write('{${variation.comment!.trim()}} ');
        }

        final varNextPos = _playMove(position, varMove);
        if (varNextPos != null) {
          _writeNodeMoves(varBuffer, variation, position: varNextPos, forceMoveNumber: false);
        }
        buffer.write('(${varBuffer.toString().trim()}) ');
      }
    }

    if (nextPos != null) {
      _writeNodeMoves(buffer, mainline, position: nextPos, forceMoveNumber: variations.isNotEmpty);
    }
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

Position? _playMove(Position pos, RepertoireMove move) {
  try {
    final from = Square.fromName(move.from);
    final to = Square.fromName(move.to);
    final promotion = move.promotion != null ? Role.fromChar(move.promotion!) : null;
    return pos.play(NormalMove(from: from, to: to, promotion: promotion));
  } catch (_) {
    return null;
  }
}

/// SAN label for [move] in [position] for export.
///
/// Stored labels are trusted when present; a missing label is derived from the
/// position so export never writes the literal "null". An unplayable move
/// falls back to UCI: the importer quarantines it with a structured error
/// instead of the export silently dropping the line.
String _exportSan(Position position, RepertoireMove move) {
  final stored = move.san;
  if (stored != null && stored.isNotEmpty) return stored;
  try {
    final from = Square.fromName(move.from);
    final to = Square.fromName(move.to);
    final promotion = move.promotion != null ? Role.fromChar(move.promotion!) : null;
    final (_, san) = position.makeSan(NormalMove(from: from, to: to, promotion: promotion));
    return san;
  } catch (_) {
    return move.uci;
  }
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y.$m.$d';
}
