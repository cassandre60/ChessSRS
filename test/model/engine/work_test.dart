// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Unit coverage for [EvalWork]'s derived position/eval getters and
/// [Step.fromNode]. The cache lives on the *last* step, so "first" vs "last"
/// and "empty" vs "present" are the boundaries worth pinning here.
library;

import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/engine/work.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

EvalWork makeWork({required IList<Step> steps, Position? initialPosition}) => EvalWork(
  id: const StringId('test'),
  variant: Variant.standard,
  threads: 1,
  path: UciPath.empty,
  searchTime: const Duration(seconds: 1),
  multiPv: 1,
  initialPosition: initialPosition ?? Chess.initial,
  steps: steps,
  threatMode: false,
);

ClientEval cloudEval({int cp = 25}) => CloudEval(
  position: Chess.initial,
  depth: 20,
  nodes: 1000,
  pvs: IList([
    PvData(moves: IList([Move.parse('e2e4')!.uci]), cp: cp),
  ]),
);

Step stepWith({required Position position, ClientEval? eval}) =>
    Step(position: position, sanMove: SanMove('e4', Move.parse('e2e4')!), eval: eval);

void main() {
  group('EvalWork.position', () {
    test('falls back to initialPosition when there are no steps', () {
      final work = makeWork(steps: const IListConst<Step>([]), initialPosition: Chess.initial);

      expect(work.position, Chess.initial);
    });

    test('uses the last step position, not the first', () {
      final afterE4 = Chess.initial.playUnchecked(Move.parse('e2e4')!);
      final work = makeWork(
        steps: [stepWith(position: Chess.initial), stepWith(position: afterE4)].toIList(),
      );

      expect(work.position, afterE4);
      expect(work.position, isNot(Chess.initial));
    });
  });

  group('EvalWork.evalCache', () {
    test('is null when there are no steps', () {
      expect(makeWork(steps: const IListConst<Step>([])).evalCache, isNull);
    });

    test('is null when the last step has no eval even if an earlier step does', () {
      final work = makeWork(
        steps: [
          stepWith(position: Chess.initial, eval: cloudEval(cp: 10)),
          stepWith(position: Chess.initial),
        ].toIList(),
      );

      expect(work.evalCache, isNull);
    });

    test('returns the eval held by the last step', () {
      final early = cloudEval(cp: 10);
      final latest = cloudEval(cp: 99);
      final work = makeWork(
        steps: [
          stepWith(position: Chess.initial, eval: early),
          stepWith(position: Chess.initial, eval: latest),
        ].toIList(),
      );

      expect(work.evalCache, latest);
      expect(work.evalCache, isNot(early));
    });
  });

  group('Step.fromNode', () {
    test('copies position, sanMove and eval from the branch', () {
      final afterE4 = Chess.initial.playUnchecked(Move.parse('e2e4')!);
      final sanMove = SanMove('e4', Move.parse('e2e4')!);
      final eval = cloudEval(cp: 42);
      final branch = Branch(position: afterE4, sanMove: sanMove, eval: eval);

      final step = Step.fromNode(branch);

      expect(step.position, afterE4);
      expect(step.sanMove, sanMove);
      expect(step.eval, eval);
    });
  });
}
