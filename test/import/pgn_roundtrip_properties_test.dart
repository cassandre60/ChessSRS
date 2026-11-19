// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-003, INV-010, INV-012, INV-014.

import 'dart:math';

import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministically generates a valid PGN string with optional branching (RAVs),
/// NAGs, comments, and custom starting FENs.
String _generateRandomPgn(
  Random rng, {
  required Position startPos,
  String? customStartFen,
  required int maxDepth,
}) {
  final buffer = StringBuffer();
  if (customStartFen != null) {
    buffer.writeln('[SetUp "1"]');
    buffer.writeln('[FEN "$customStartFen"]');
    buffer.writeln();
  }

  void writeLine(Position pos, int depth, int moveNumber, {required bool forceMoveNumber}) {
    if (depth >= maxDepth) return;
    final legal = _allLegalMoves(pos);
    if (legal.isEmpty) return;

    final mainIdx = rng.nextInt(legal.length);
    final mainMove = legal[mainIdx];
    final (nextPos, san) = pos.makeSan(mainMove);

    if (pos.turn == Side.white) {
      buffer.write('$moveNumber. $san ');
    } else if (forceMoveNumber) {
      buffer.write('$moveNumber... $san ');
    } else {
      buffer.write('$san ');
    }

    if (rng.nextDouble() < 0.25) {
      const nags = [1, 2, 3, 5, 6, 14, 15];
      buffer.write('\$${nags[rng.nextInt(nags.length)]} ');
    }
    if (rng.nextDouble() < 0.25) {
      final commentId = rng.nextInt(1000);
      buffer.write('{Note $commentId: solid plan} ');
    }

    // Add a variation branch with probability 0.3 when alternatives exist
    var varied = false;
    if (depth < maxDepth - 1 && legal.length > 1 && rng.nextDouble() < 0.3) {
      final altMove = legal[(mainIdx + 1) % legal.length];
      final (altPos, altSan) = pos.makeSan(altMove);
      buffer.write('(');
      if (pos.turn == Side.white) {
        buffer.write('$moveNumber. $altSan ');
      } else {
        buffer.write('$moveNumber... $altSan ');
      }
      writeLine(
        altPos,
        depth + 2,
        pos.turn == Side.black ? moveNumber + 1 : moveNumber,
        forceMoveNumber: false,
      );
      buffer.write(') ');
      varied = true;
    }

    writeLine(
      nextPos,
      depth + 1,
      pos.turn == Side.black ? moveNumber + 1 : moveNumber,
      forceMoveNumber: varied,
    );
  }

  writeLine(startPos, 0, startPos.fullmoves, forceMoveNumber: startPos.turn == Side.black);
  buffer.write('*');
  return buffer.toString();
}

List<NormalMove> _allLegalMoves(Position pos) {
  final result = <NormalMove>[];
  for (final entry in pos.legalMoves.entries) {
    for (final toSq in entry.value.squares) {
      final base = NormalMove(from: entry.key, to: toSq);
      if (isPromotionPawnMove(pos, base)) {
        result.add(NormalMove(from: entry.key, to: toSq, promotion: Role.queen));
      } else {
        result.add(base);
      }
    }
  }
  return result;
}

void main() {
  group('PGN export/re-import round-trip properties', () {
    test('INV-003/INV-010/INV-014 random repertoire trees survive export and re-import', () {
      // SPEC INV-003, INV-010, INV-014. Exporting a study and re-importing the PGN
      // preserves the tree hash, variation structure, and canonical decision set.
      final rng = Random(303);
      for (var seed = 0; seed < 25; seed++) {
        final side = seed.isEven ? Side.white : Side.black;
        final pgn = _generateRandomPgn(rng, startPos: Chess.initial, maxDepth: 6);

        final first = importPgn(pgn, studyTitle: 'Prop-$seed', repertoireSide: side);
        expect(first.errors, isEmpty, reason: 'generated PGN must import cleanly (seed $seed)');
        expect(first.chapters.length, equals(1));

        final treeHash1 = computeRepertoireTreeHash(first.chapters);
        expect(first.study.pgnHash, equals(treeHash1));

        final exported = studyToPgn(first.study, first.chapters);
        final second = importPgn(exported, studyTitle: 'Prop-$seed', repertoireSide: side);
        expect(second.errors, isEmpty, reason: 'exported PGN must re-import cleanly (seed $seed)');

        final treeHash2 = computeRepertoireTreeHash(second.chapters);
        expect(
          treeHash2,
          equals(treeHash1),
          reason: 'INV-014: tree hash must be preserved across export/re-import (seed $seed)',
        );

        final canonicalSet1 = first.decisions.map((d) => d.canonicalId).toSet();
        final canonicalSet2 = second.decisions.map((d) => d.canonicalId).toSet();
        expect(
          canonicalSet2,
          equals(canonicalSet1),
          reason: 'INV-014: canonical decision identities must be preserved (seed $seed)',
        );
      }
    });

    test(
      'INV-012/INV-014 custom starting FENs survive export and re-import with normalized key',
      () {
        // SPEC INV-012, INV-014. Custom starting positions are normalized and preserved.
        const customFens = [
          'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
          'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
          'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
        ];
        final rng = Random(404);

        for (var i = 0; i < customFens.length; i++) {
          final fen = customFens[i];
          final startPos = Chess.fromSetup(Setup.parseFen(fen));
          final pgn = _generateRandomPgn(rng, startPos: startPos, customStartFen: fen, maxDepth: 5);

          final first = importPgn(pgn, studyTitle: 'CustomFen-$i', repertoireSide: startPos.turn);
          expect(first.errors, isEmpty);

          final exported = studyToPgn(first.study, first.chapters);
          final second = importPgn(
            exported,
            studyTitle: 'CustomFen-$i',
            repertoireSide: startPos.turn,
          );
          expect(second.errors, isEmpty);

          expect(
            computeRepertoireTreeHash(second.chapters),
            equals(computeRepertoireTreeHash(first.chapters)),
          );
          expect(second.chapters.first.root!.fenKey, equals(first.chapters.first.root!.fenKey));
        }
      },
    );
  });
}
