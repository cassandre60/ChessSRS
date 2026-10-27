import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chessground/chessground.dart' show Arrow, PieceAssets;
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart' show AssetImage;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Eval.evalString (centipawn formatting)', () {
    test('formats small positive cp with sign', () {
      expect(const ExternalEval(cp: 50, mate: null).evalString, '+0.5');
    });

    test('formats small negative cp with sign', () {
      expect(const ExternalEval(cp: -120, mate: null).evalString, '-1.2');
    });

    test('formats zero cp without sign', () {
      expect(const ExternalEval(cp: 0, mate: null).evalString, '0.0');
    });

    test('returns "-" when both cp and mate are null', () {
      expect(const ExternalEval(cp: null, mate: null).evalString, '-');
    });

    test('formats mate with leading #', () {
      expect(const ExternalEval(cp: null, mate: 3).evalString, '#3');
      expect(const ExternalEval(cp: null, mate: -2).evalString, '#-2');
    });

    test('clamps very large positive cp to +99.0', () {
      expect(const ExternalEval(cp: 20000, mate: null).evalString, '+99.0');
    });

    test('clamps very large negative cp to -99.0', () {
      expect(const ExternalEval(cp: -20000, mate: null).evalString, '-99.0');
    });

    test('does not clamp cp at exactly +/-9900 boundary', () {
      expect(const ExternalEval(cp: 9900, mate: null).evalString, '+99.0');
      expect(const ExternalEval(cp: -9900, mate: null).evalString, '-99.0');
    });

    test('clamping does not affect mate scores', () {
      expect(const ExternalEval(cp: null, mate: 200).evalString, '#200');
      expect(const ExternalEval(cp: null, mate: -150).evalString, '#-150');
    });

    test('rounds a tiny positive cp that displays as 0.0 to "0.0" (no plus)', () {
      expect(const ExternalEval(cp: 1, mate: null).evalString, '0.0');
    });

    test('rounds a tiny negative cp that displays as -0.0 to "0.0"', () {
      expect(const ExternalEval(cp: -1, mate: null).evalString, '0.0');
    });
  });

  group('ExternalEval.fromPgnEval', () {
    test('converts pawns to centipawns', () {
      const e = PgnEvaluation.pawns(pawns: 1.5, depth: 12);
      expect(ExternalEval.fromPgnEval(e).cp, 150);
      expect(ExternalEval.fromPgnEval(e).mate, isNull);
      expect(ExternalEval.fromPgnEval(e).depth, 12);
    });

    test('yields null cp when pawns is null', () {
      const e = PgnEvaluation.mate(mate: 3, depth: 5);
      expect(ExternalEval.fromPgnEval(e).cp, isNull);
      expect(ExternalEval.fromPgnEval(e).mate, 3);
    });
  });

  group('PvData.winningSide', () {
    test('mate positive -> white', () {
      expect(PvData(moves: IList(const ['e2e4']), mate: 3).winningSide, Side.white);
    });

    test('mate negative -> black', () {
      expect(PvData(moves: IList(const ['e2e4']), mate: -2).winningSide, Side.black);
    });

    test('mate zero -> black (boundary)', () {
      expect(PvData(moves: IList(const ['e2e4']), mate: 0).winningSide, Side.black);
    });

    test('cp positive -> white', () {
      expect(PvData(moves: IList(const ['e2e4']), cp: 50).winningSide, Side.white);
    });

    test('cp negative -> black', () {
      expect(PvData(moves: IList(const ['e2e4']), cp: -10).winningSide, Side.black);
    });

    test('cp zero -> black (boundary)', () {
      expect(PvData(moves: IList(const ['e2e4']), cp: 0).winningSide, Side.black);
    });

    test('mate takes precedence over cp', () {
      expect(PvData(moves: IList(const ['e2e4']), mate: -1, cp: 100).winningSide, Side.black);
    });

    test('both null -> null', () {
      expect(PvData(moves: IList(const ['e2e4'])).winningSide, isNull);
    });

    test('mate null but cp present -> uses cp', () {
      expect(PvData(moves: IList(const ['e2e4']), cp: 50).winningSide, Side.white);
    });
  });

  group('ClientEval.bestMove', () {
    test('returns null when pvs is empty', () {
      final e = CloudEval(position: Chess.initial, depth: 1, nodes: 1, pvs: IList());
      expect(e.bestMove, isNull);
    });

    test('parses the first pv move', () {
      final e = CloudEval(
        position: Chess.initial,
        depth: 1,
        nodes: 1,
        pvs: IList([
          PvData(moves: IList(const ['e2e4'])),
        ]),
      );
      expect(e.bestMove, Move.parse('e2e4'));
    });
  });

  group('ClientEval.bestMoves', () {
    test('filters out pvs with empty moves', () {
      final e = CloudEval(
        position: Chess.initial,
        depth: 1,
        nodes: 1,
        pvs: IList([
          PvData(moves: IList()),
          PvData(moves: IList(const ['e2e4']), cp: 50),
        ]),
      );
      expect(e.bestMoves.length, 1);
      expect(e.bestMoves.first.move, Move.parse('e2e4'));
    });

    test('uses the first move of a multi-move pv', () {
      final e = CloudEval(
        position: Chess.initial,
        depth: 1,
        nodes: 1,
        pvs: IList([
          PvData(moves: IList(const ['e2e4', 'e7e5']), cp: 50),
        ]),
      );
      expect(e.bestMoves.first.move, Move.parse('e2e4'));
    });

    test('sorts by winning chances descending', () {
      final e = CloudEval(
        position: Chess.initial,
        depth: 1,
        nodes: 1,
        pvs: IList([
          PvData(moves: IList(const ['d2d4']), cp: 10),
          PvData(moves: IList(const ['e2e4']), cp: 100),
        ]),
      );
      expect(e.bestMoves.first.move, Move.parse('e2e4'));
      expect(e.bestMoves.last.move, Move.parse('d2d4'));
    });
  });

  group('LocalEval.isBetter', () {
    test('deeper search is better even with fewer nodes', () {
      final a = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 1,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      final b = LocalEval(
        position: Chess.initial,
        depth: 1,
        nodes: 100,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      expect(a.isBetter(b), isTrue);
    });

    test('same depth with more nodes is better', () {
      final a = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 10,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      final b = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 5,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      expect(a.isBetter(b), isTrue);
    });

    test('same depth and same nodes is not better', () {
      final a = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 5,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      final b = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 5,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      expect(a.isBetter(b), isFalse);
    });

    test('shallower search with more nodes is not better', () {
      final a = LocalEval(
        position: Chess.initial,
        depth: 1,
        nodes: 100,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      final b = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 5,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      expect(a.isBetter(b), isFalse);
    });

    test('same depth with fewer nodes is not better', () {
      final a = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 3,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      final b = LocalEval(
        position: Chess.initial,
        depth: 2,
        nodes: 5,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: false,
      );
      expect(a.isBetter(b), isFalse);
    });
  });

  group('Eval.winningChances POV', () {
    test('white side keeps the white perspective', () {
      const e = ExternalEval(cp: 100, mate: null);
      expect(e.winningChances(Side.white), greaterThan(0));
    });

    test('black side inverts the perspective', () {
      const e = ExternalEval(cp: 100, mate: null);
      expect(e.winningChances(Side.black), lessThan(0));
    });

    test('cp zero yields zero chances', () {
      const e = ExternalEval(cp: 0, mate: null);
      expect(e.winningChances(Side.white), 0.0);
    });

    test('mate zero yields negative chances for white (boundary)', () {
      const e = ExternalEval(cp: null, mate: 0);
      expect(e.winningChances(Side.white), lessThan(0));
    });
  });

  group('PvData.winningChances POV', () {
    test('black side inverts', () {
      final p = PvData(moves: IList(const ['e2e4']), cp: 100);
      expect(p.winningChances(Side.black), lessThan(0));
      expect(p.winningChances(Side.white), greaterThan(0));
    });
  });

  group('cpToPawns / cpFromPawns', () {
    test('cpToPawns divides by 100', () {
      expect(cpToPawns(250), 2.5);
    });

    test('cpFromPawns rounds', () {
      expect(cpFromPawns(2.5), 250);
    });
  });

  group('computeBestMoveShapes', () {
    const PieceAssets emptyAssets = <PieceKind, AssetImage>{};

    test('first move uses bestMoveColor', () {
      final moves = IList<MoveWithWinningChances>([
        (move: Move.parse('e2e4')!, winningChances: 0.5),
        (move: Move.parse('d2d4')!, winningChances: 0.3),
      ]);
      final shapes = computeBestMoveShapes(
        moves,
        Side.white,
        emptyAssets,
        bestMoveColor: Colors.red,
        nextBestMovesColor: Colors.blue,
      );
      final arrow = shapes.whereType<Arrow>().firstWhere(
        (a) =>
            a.orig == (moves.first.move as NormalMove).from &&
            a.dest == (moves.first.move as NormalMove).to,
      );
      expect(arrow.color, Colors.red);
    });

    test('second move uses nextBestMovesColor', () {
      final moves = IList<MoveWithWinningChances>([
        (move: Move.parse('e2e4')!, winningChances: 0.5),
        (move: Move.parse('d2d4')!, winningChances: 0.3),
      ]);
      final shapes = computeBestMoveShapes(
        moves,
        Side.white,
        emptyAssets,
        bestMoveColor: Colors.red,
        nextBestMovesColor: Colors.blue,
      );
      final arrow = shapes.whereType<Arrow>().firstWhere(
        (a) =>
            a.orig == (moves.last.move as NormalMove).from &&
            a.dest == (moves.last.move as NormalMove).to,
      );
      expect(arrow.color, Colors.blue);
    });

    test('scale drops to minScale only when diff exceeds 0.3', () {
      final moves = IList<MoveWithWinningChances>([
        (move: Move.parse('e2e4')!, winningChances: 0.3),
        (move: Move.parse('d2d4')!, winningChances: 0.0),
      ]);
      final shapes = computeBestMoveShapes(
        moves,
        Side.white,
        emptyAssets,
        bestMoveColor: Colors.red,
        nextBestMovesColor: Colors.blue,
      );
      final arrow = shapes.whereType<Arrow>().firstWhere(
        (a) =>
            a.orig == (moves.last.move as NormalMove).from &&
            a.dest == (moves.last.move as NormalMove).to,
      );
      expect(arrow.scale, isNot(0.15));
      expect(arrow.scale, closeTo(0.25, 1e-9));
    });
  });
}
