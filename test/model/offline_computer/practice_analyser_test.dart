import 'dart:async';

import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_context.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/engine/work.dart';
import 'package:chess_srs/src/model/offline_computer/practice_analyser.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_container.dart';
import '../engine/fake_engine.dart';

// Every wait in this file runs on the fake clock: containers are made outside the zone (the
// pattern of engine_providers_test and position_evaluator_test), and each settle is an
// async.elapse of the same 2 x kEngineEvalEmissionThrottleDelay window the old code slept in
// real time for. The chain under test — engine acquisition, stream delivery, and the evaluator's
// emission-throttle Timer — is pure microtasks and Timers, so nothing here needs the wall clock.
//
// Flake mode removed: a fixed real sleep is a bet that all of that work fits inside it. Under
// CPU contention the emission chain gets scheduled late relative to the sleep that was meant to
// cover it, so an assertion runs on state the sleep never waited for. On the fake clock the
// settle either has covered the boundary exactly or the test fails deterministically.

/// How long a settle advances the fake clock: long enough for the evaluator's throttle to have
/// let the last info line through — the exact window the old code slept in real time.
final _settleWindow = kEngineEvalEmissionThrottleDelay * 2;

const _context = EvaluationContext(
  id: StringId('practice'),
  variant: Variant.standard,
  initialPosition: Chess.initial,
);

/// The evaluator the analyser runs on, kept alive for the duration of the test.
PositionEvaluator readEvaluator(ProviderContainer container) {
  final provider = positionEvaluatorProvider(_context);
  container.listen(provider, (_, _) {});
  return container.read(provider.notifier);
}

EvalWork makeWork({IList<Step> steps = const IListConst<Step>([])}) => EvalWork(
  id: const StringId('practice'),
  variant: Variant.standard,
  threads: 1,
  searchTime: kPracticeMaxSearchTime,
  multiPv: 2,
  threatMode: false,
  initialPosition: Chess.initial,
  steps: steps,
);

/// The work for the position after 1. e4, which is a different position to analyse.
EvalWork makeWorkAfterE4() {
  const move = NormalMove(from: Square.e2, to: Square.e4);
  final (position, san) = Chess.initial.makeSan(move);
  return makeWork(
    steps: IList([Step(position: position, sanMove: SanMove(san, move))]),
  );
}

void main() {
  TestLichessBinding.ensureInitialized();

  late AnalysisTestEngine engine;

  setUp(() {
    engine = AnalysisTestEngine();
    fakeEngine = engine;
  });

  group('PracticeAnalyser', () {
    test('keeps searching past the usable depth, and stops at the target', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);

        engine.emitDepthRange(toDepth: kPracticeUsableDepth);
        async.elapse(_settleWindow);

        // The whole point: the player's thinking time is engine time, so a usable eval is not the
        // end of the search.
        expect(analyser.isAnalysing, isTrue);
        expect(analyser.evalFor(Chess.initial)?.depth, kPracticeUsableDepth);

        engine.emitDepthRange(toDepth: kPracticeTargetDepth);
        async.elapse(_settleWindow);

        expect(analyser.isAnalysing, isFalse);
        expect(analyser.evalFor(Chess.initial)?.depth, kPracticeTargetDepth);
        expect(engine.stopCount, 1);
      });
    });

    test('usableEval completes as soon as the analysis is deep enough', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);

        // A depth the analysis has already passed does not have to be waited for at all.
        engine.emitDepthRange(toDepth: kPracticeUsableDepth - 2);
        async.elapse(_settleWindow);

        var completed = false;
        ClientEval? served;
        unawaited(
          analyser.usableEval(Chess.initial, timeout: const Duration(seconds: 5)).then((eval) {
            completed = true;
            served = eval;
          }),
        );
        async.elapse(_settleWindow);
        expect(completed, isFalse, reason: 'the analysis is not deep enough yet');

        engine.emitDepthRange(toDepth: kPracticeUsableDepth);
        async.elapse(_settleWindow);

        expect(served?.depth, greaterThanOrEqualTo(kPracticeUsableDepth));
      });
    });

    test('waiters asking for different depths are served at their own depth', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);

        // Judging a move played asks for more depth than unlocking a hint does, and both can be
        // waiting on the same position at once.
        ClientEval? shallow;
        ClientEval? deep;
        unawaited(
          analyser
              .usableEval(Chess.initial, timeout: const Duration(seconds: 5))
              .then((eval) => shallow = eval),
        );
        unawaited(
          analyser
              .usableEval(
                Chess.initial,
                minDepth: kPracticeUsableDepth + 3,
                timeout: const Duration(seconds: 5),
              )
              .then((eval) => deep = eval),
        );

        engine.emitDepthRange(toDepth: kPracticeUsableDepth);
        async.elapse(_settleWindow);

        expect(shallow?.depth, kPracticeUsableDepth);
        expect(
          deep,
          isNull,
          reason: 'the deeper waiter is not served by an eval it did not ask for',
        );

        engine.emitDepthRange(toDepth: kPracticeUsableDepth + 3);
        async.elapse(_settleWindow);

        expect(deep?.depth, kPracticeUsableDepth + 3);
      });
    });

    test('usableEval gives up with the best it has when the deadline passes', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);
        engine.emitDepthRange(toDepth: kPracticeUsableDepth - 3);
        async.elapse(_settleWindow);

        // A slow device may never reach the depth; the shallow eval is still worth having.
        ClientEval? eval;
        unawaited(
          analyser
              .usableEval(Chess.initial, timeout: const Duration(milliseconds: 100))
              .then((value) => eval = value),
        );

        async.elapse(const Duration(milliseconds: 99));
        expect(eval, isNull, reason: '99 ms into a 100 ms deadline the waiter is still waiting');

        async.elapse(const Duration(milliseconds: 1));
        expect(eval?.depth, kPracticeUsableDepth - 3);
      });
    });

    test('yieldEngine hands the engine over, and analysing takes it back', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final evaluator = readEvaluator(container);
        final analyser = PracticeAnalyser(evaluator: () => evaluator, onEval: (_, _) {});
        addTearDown(analyser.dispose);

        final work = makeWork();
        analyser.analyse(work);
        async.elapse(_settleWindow);
        expect(evaluator.currentWork, work);

        // The opponent needs the engine — on a variant it is the same one.
        analyser.yieldEngine();
        expect(analyser.isAnalysing, isFalse);
        expect(evaluator.currentWork, isNull);

        // Asking for the same position again is how it comes back: nothing is remembered to be
        // restarted, because what is worth analysing is a question about the position now.
        analyser.analyse(makeWork());
        async.elapse(_settleWindow);

        expect(analyser.isAnalysing, isTrue);
        expect(evaluator.currentWork, work);
      });
    });

    test('an eval from elsewhere can end the search', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);
        engine.emitDepthRange(toDepth: kPracticeUsableDepth - 2);
        async.elapse(_settleWindow);

        // A cloud eval, or a tablebase lookup: deeper than the search would ever get.
        analyser.offer(
          Chess.initial,
          const CloudEval(
            position: Chess.initial,
            depth: 40,
            nodes: 0,
            pvs: IListConst([
              PvData(moves: IListConst(['e2e4']), cp: 20),
            ]),
          ),
        );

        expect(analyser.isAnalysing, isFalse);
        expect(analyser.evalFor(Chess.initial)?.depth, 40);
        expect(engine.stopCount, 1);
      });
    });

    test('a position already analysed to the target depth is not searched again', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);
        engine.emitDepthRange(toDepth: kPracticeTargetDepth);
        async.elapse(_settleWindow);
        expect(engine.requestedPositions, hasLength(1));

        // What a takeback and a replay come back to: there is nothing left to learn about it.
        analyser.analyse(makeWorkAfterE4());
        async.elapse(_settleWindow);
        expect(engine.requestedPositions, hasLength(2));

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);

        expect(engine.requestedPositions, hasLength(2));
        expect(analyser.evalFor(Chess.initial)?.depth, kPracticeTargetDepth);
      });
    });

    test('forgets everything it knows when the game is replaced', () async {
      final container = await makeContainer();

      fakeAsync((async) {
        final analyser = PracticeAnalyser(
          evaluator: () => readEvaluator(container),
          onEval: (_, _) {},
        );
        addTearDown(analyser.dispose);

        analyser.analyse(makeWork());
        async.elapse(_settleWindow);
        engine.emitDepthRange(toDepth: kPracticeTargetDepth);
        async.elapse(_settleWindow);

        analyser.clear();

        expect(analyser.evalFor(Chess.initial), isNull);
        expect(analyser.isAnalysing, isFalse);
      });
    });
  });
}
