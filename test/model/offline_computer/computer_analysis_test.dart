import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/offline_computer/computer_analysis.dart';
import 'package:chess_srs/src/model/offline_computer/practice_comment.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

CloudEval _eval(Position position, List<PvData> pvs) =>
    CloudEval(position: position, depth: 20, nodes: 1000, pvs: pvs.toIList());

/// Start position after 1. e4 — Black to move.
Position _blackToMove() {
  const position = Chess.initial;
  return position.playUnchecked(position.parseSan('e4')!);
}

void main() {
  group('ComputerAnalysis eval-derived getters', () {
    test('are null when there is no evaluation', () {
      const analysis = ComputerAnalysis();
      expect(analysis.bestMoves, isNull);
      expect(analysis.winningChances, isNull);
      expect(analysis.evalString, isNull);
      expect(analysis.hintMoves, isNull);
    });

    test('delegate best moves and eval string to the evaluation', () {
      final eval = _eval(Chess.initial, [
        PvData(moves: ['e2e4'].toIList(), cp: 50),
      ]);
      final analysis = ComputerAnalysis(eval: eval);

      expect(analysis.bestMoves!.map((e) => e.move.uci).toList(), ['e2e4']);
      expect(analysis.evalString, '+0.5');
    });

    test('winning chances are from the side-to-move perspective', () {
      final white = _eval(Chess.initial, [
        PvData(moves: ['e2e4'].toIList(), cp: 100),
      ]);
      expect(ComputerAnalysis(eval: white).winningChances, greaterThan(0));

      final blackPosition = _blackToMove();
      final black = _eval(blackPosition, [
        PvData(moves: ['e7e5'].toIList(), cp: 100),
      ]);
      final chances = ComputerAnalysis(eval: black).winningChances;
      expect(chances, lessThan(0));
      expect(chances, closeTo(black.winningChances(blackPosition.turn), 1e-12));
    });
  });

  group('ComputerAnalysis.hintMoves', () {
    test('is null when the evaluation has no principal variations', () {
      final analysis = ComputerAnalysis(eval: _eval(Chess.initial, const []));
      expect(analysis.hintMoves, isNull);
    });

    test('drops moves that lose more than 0.1 winning chances', () {
      // cp 100 -> ~0.182, cp 50 -> ~0.092 (kept), cp 20 -> ~0.037 (dropped).
      final eval = _eval(Chess.initial, [
        PvData(moves: ['e2e4'].toIList(), cp: 100),
        PvData(moves: ['d2d4'].toIList(), cp: 50),
        PvData(moves: ['c2c4'].toIList(), cp: 20),
      ]);

      expect(ComputerAnalysis(eval: eval).hintMoves!.map((m) => m.uci).toList(), ['e2e4', 'd2d4']);
    });

    test('keeps only the best move from a given origin square', () {
      // e2e4 and e2e3 share origin e2; the lower-ranked e2e3 is dropped.
      final eval = _eval(Chess.initial, [
        PvData(moves: ['e2e4'].toIList(), cp: 100),
        PvData(moves: ['e2e3'].toIList(), cp: 90),
        PvData(moves: ['d2d4'].toIList(), cp: 80),
      ]);

      expect(ComputerAnalysis(eval: eval).hintMoves!.map((m) => m.uci).toList(), ['e2e4', 'd2d4']);
    });

    test('always keeps the top move even when all others are dropped', () {
      final eval = _eval(Chess.initial, [
        PvData(moves: ['e2e4'].toIList(), cp: 100),
        PvData(moves: ['c2c4'].toIList(), cp: -800),
      ]);

      expect(ComputerAnalysis(eval: eval).hintMoves!.map((m) => m.uci).toList(), ['e2e4']);
    });
  });

  group('ComputerAnalysis step JSON', () {
    test('fromStepJson returns null when there is no persisted comment', () {
      expect(ComputerAnalysis.fromStepJson({}), isNull);
      expect(ComputerAnalysis.fromStepJson({'practiceComment': null}), isNull);
    });

    test('fromStepJson parses the persisted practice comment', () {
      final json = const PracticeComment(
        verdict: MoveVerdict.mistake,
        moveSuggestion: null,
        evalAfter: '-0.4',
        isBookMove: true,
      ).toJson();

      final analysis = ComputerAnalysis.fromStepJson({'practiceComment': json});
      expect(analysis, isNotNull);
      expect(analysis!.eval, isNull);
      expect(analysis.practiceComment, PracticeComment.fromJson(json));
    });

    test('toStepJson is empty when there is no practice comment', () {
      expect(const ComputerAnalysis().toStepJson(), isEmpty);
    });

    test('toStepJson persists only the practice comment', () {
      const comment = PracticeComment(verdict: MoveVerdict.goodMove, evalAfter: '+0.7');
      final json = const ComputerAnalysis(practiceComment: comment).toStepJson();

      expect(json.keys, {'practiceComment'});
      expect(PracticeComment.fromJson(json['practiceComment'] as Map<String, dynamic>), comment);
    });
  });
}
