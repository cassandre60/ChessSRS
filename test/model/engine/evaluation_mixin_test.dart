import 'dart:async';

import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/socket.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/engine/work.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';

const _testContext = EvaluationContext(
  id: StringId('eval_mixin_test'),
  variant: Variant.standard,
  initialPosition: Chess.initial,
);

/// The position after 1. f3 e5 2. g4 Qh4 — the side to move is in check.
final _inCheckPosition = _positionAfter(['f3', 'e5', 'g4', 'Qh4']);

/// A position in which the side that would be to move in threat mode is stalemated.
///
/// White is to move and Black has no legal move if it were his turn: the queen on b6 covers
/// a7, b7 and b8, and Black is not in check.
final _stalematesTheOpponentPosition = Chess.fromSetup(
  Setup.parseFen('k7/8/1Q6/8/8/8/8/K7 w - - 0 1'),
);

/// A variant position, so that the requests the screen sends have to name the variant.
final _variantPosition = Antichess.fromSetup(
  Setup.parseFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b - - 0 1'),
);

Position _positionAfter(List<String> sans) {
  Position position = Chess.initial;
  for (final san in sans) {
    position = position.playUnchecked(position.parseSan(san)!);
  }
  return position;
}

/// The cloud evaluation body served by the fake HTTP client.
String _cloudEvalBody({int depth = 20, int cp = 25, String moves = 'e2e4 e7e5'}) =>
    '{"depth": $depth, "knodes": 1000, "pvs": [{"moves": "$moves", "cp": $cp}]}';

/// A cloud evaluation for the start position.
CloudEval _cloudEval({int depth = 20, int cp = 25, int nodes = 4000}) => CloudEval(
  position: Chess.initial,
  depth: depth,
  nodes: nodes,
  pvs: IList([
    PvData(moves: ['e2e4'].toIList(), cp: cp),
  ]),
);

/// A local evaluation for the start position.
LocalEval _localEval({int depth = 10, int cp = 50, int nodes = 500, Duration? elapsed}) =>
    LocalEval(
      position: Chess.initial,
      depth: depth,
      nodes: nodes,
      pvs: IList([
        PvData(moves: ['e2e4'].toIList(), cp: cp),
      ]),
      millis: (elapsed ?? const Duration(seconds: 1)).inMilliseconds,
      searchTime: elapsed ?? const Duration(seconds: 1),
      threatMode: false,
    );

/// An evaluator that does not touch any engine: it hands out controllable streams so the test can
/// observe whether the mixin keeps the returned subscription alive or cancels it.
class _FakePositionEvaluator extends PositionEvaluator {
  _FakePositionEvaluator(super.context);

  /// Every stream handed out by [evaluate], in request order.
  final List<StreamController<EvalResult>> streams = [];

  /// Every work [evaluate] was asked for, in request order.
  final List<EvalWork> works = [];

  /// How many times the evaluation was stopped.
  int stopCount = 0;

  @override
  EngineEvaluationState build() => PositionEvaluator.defaultState;

  @override
  Stream<EvalResult>? evaluate(EvalWork work, {bool goDeeper = false}) {
    works.add(work);
    final controller = StreamController<EvalResult>.broadcast();
    streams.add(controller);
    return controller.stream.where((result) => result.$1 == work);
  }

  @override
  void stop() {
    stopCount++;
    super.stop();
  }
}

/// A socket that records what was sent through it and lets the test push events back.
class _FakeSocketClient implements SocketClient {
  final StreamController<SocketEvent> events = StreamController<SocketEvent>.broadcast();

  /// The events sent through this socket, in order.
  final List<(String, Object?)> sent = [];

  /// How many times the event stream was read.
  ///
  /// The mixin reads it once per socket subscription, so this says how many times it subscribed.
  int streamReads = 0;

  @override
  Stream<SocketEvent> get stream {
    streamReads++;
    return events.stream;
  }

  @override
  void send(String topic, Object? data, {bool? ackable, bool? withLag, bool noRetry = false}) {
    sent.add((topic, data));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The state of the screen under test.
class _TestState with EvaluationMixinState<_TestState> {
  _TestState({
    this.currentPosition = Chess.initial,
    this.currentPath = UciPath.empty,
    this.engineInThreatMode = false,
    this.alwaysRequestCloudEval = false,
  });

  @override
  final Position? currentPosition;

  /// Mutable on purpose: a screen that has moved on keeps the same state object.
  @override
  UciPath currentPath;

  @override
  final bool engineInThreatMode;

  @override
  final bool alwaysRequestCloudEval;

  @override
  bool isEngineAvailable(EngineEvaluationPrefState prefs) => true;

  @override
  EvaluationContext get evaluationContext => _testContext;

  @override
  _TestState withThreatMode(bool engineInThreatMode) => _TestState(
    currentPosition: currentPosition,
    currentPath: currentPath,
    engineInThreatMode: engineInThreatMode,
    alwaysRequestCloudEval: alwaysRequestCloudEval,
  );
}

class _TestController extends AsyncNotifier<_TestState> with EngineEvaluationMixin<_TestState> {
  @override
  Future<_TestState> build() async {
    final gate = buildGate;
    if (gate != null) await gate.future;
    return _TestState(
      currentPosition: testPosition,
      currentPath: testPath,
      engineInThreatMode: testThreatMode,
      alwaysRequestCloudEval: testAlwaysRequestCloudEval,
    );
  }

  @override
  SocketClient? get socketClient => testSocket;

  @override
  Node get positionTree => testTree;

  @override
  void onCurrentPathEvalChanged(bool isSameEvalString) {
    evalChanges.add(isSameEvalString);
  }
}

final _testControllerProvider = AsyncNotifierProvider.autoDispose<_TestController, _TestState>(
  _TestController.new,
  name: 'TestEvalControllerProvider',
);

/// The socket the controller sees. Null until the test says otherwise.
_FakeSocketClient? testSocket;

/// The tree the controller evaluates into.
late Node testTree;

/// The position the screen shows.
late Position? testPosition;

/// The path the screen is on.
late UciPath testPath;

/// Whether the screen is in threat mode.
late bool testThreatMode;

/// Whether the screen always asks for a cloud evaluation.
late bool testAlwaysRequestCloudEval;

/// Holds the screen's state back, so a test can make the socket arrive first.
Completer<void>? buildGate;

/// Whether the screen reported the evaluation as changed, for each report.
late List<bool> evalChanges;

void main() {
  TestLichessBinding.ensureInitialized();

  late _FakePositionEvaluator fakeEvaluator;
  late _FakeSocketClient fakeSocket;
  late List<http.Request> httpRequests;

  /// A container whose HTTP client answers cloud evaluation requests with [body].
  Future<ProviderContainer> makeTestContainer({String? body, int status = 200}) {
    httpRequests = [];
    final cloudEvalBody = body ?? _cloudEvalBody();
    final client = MockClient((request) async {
      if (request.url.path == '/api/cloud-eval') {
        httpRequests.add(request);
        return http.Response(cloudEvalBody, status);
      }
      return http.Response('Not found', 404);
    });
    return makeContainer(
      overrides: {
        positionEvaluatorProvider: positionEvaluatorProvider.overrideWith2((_) => fakeEvaluator),
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => client);
        }),
      },
    );
  }

  /// A container whose screen is up and whose state has a value.
  Future<ProviderContainer> readyContainer(ProviderContainer container) async {
    final subscription = container.listen(_testControllerProvider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(_testControllerProvider.future);
    return container;
  }

  setUp(() {
    fakeEvaluator = _FakePositionEvaluator(_testContext);
    fakeSocket = _FakeSocketClient();
    testSocket = fakeSocket;
    testTree = Root(position: Chess.initial);
    testPosition = Chess.initial;
    testPath = UciPath.empty;
    testThreatMode = false;
    testAlwaysRequestCloudEval = false;
    buildGate = null;
    evalChanges = [];
  });

  group('threat mode availability', () {
    test('threat mode is available in a position that is neither a check nor a stalemate', () {
      // SPEC INV-020.
      final state = _TestState(currentPosition: Chess.initial);

      expect(state.canShowThreat, isTrue);
    });

    test('threat mode is not available when the side to move is in check', () {
      // SPEC INV-020.
      final state = _TestState(currentPosition: _inCheckPosition);

      expect(state.canShowThreat, isFalse);
    });

    test('threat mode is not available when the opponent would be stalemated', () {
      // SPEC INV-020.
      final state = _TestState(currentPosition: _stalematesTheOpponentPosition);

      expect(state.canShowThreat, isFalse);
    });

    test('threat mode is not available when there is no position', () {
      // SPEC INV-020.
      final state = _TestState(currentPosition: null);

      expect(state.canShowThreat, isFalse);
    });
  });

  group('threat mode', () {
    test('threat mode is turned on when it can be shown', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());

      container.read(_testControllerProvider.notifier).toggleEngineThreatMode();

      expect(container.read(_testControllerProvider).requireValue.engineInThreatMode, isTrue);
    });

    test('threat mode is not turned on when it cannot be shown', () async {
      // SPEC INV-020.
      testPosition = _inCheckPosition;
      final container = await readyContainer(await makeTestContainer());

      container.read(_testControllerProvider.notifier).toggleEngineThreatMode();

      expect(container.read(_testControllerProvider).requireValue.engineInThreatMode, isFalse);
    });
  });

  group('evaluation request', () {
    test('an evaluation request is sent for the current position', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      final (topic, data) = fakeSocket.sent.first;
      expect(topic, 'evalGet');
      expect((data! as Map<String, Object?>)['fen'], Chess.initial.fen);
    });

    test(
      'no evaluation request is sent for a position that already has a cloud evaluation',
      () async {
        // SPEC INV-020.
        testTree = Root(position: Chess.initial, eval: _cloudEval());
        final container = await readyContainer(await makeTestContainer());
        final controller = container.read(_testControllerProvider.notifier);

        controller.requestEval();

        // The local engine still runs; only the cloud request is skipped.
        await waitUntil(() => fakeEvaluator.works.isNotEmpty, timeout: const Duration(seconds: 2));
        expect(fakeSocket.sent, isEmpty);
        expect(httpRequests, isEmpty);
      },
    );

    test('no evaluation request is sent for a repeated position', () async {
      // SPEC INV-020.
      // The position after 3. Nf3 is the one after 1. Nf3: the position has repeated.
      testTree = Root.fromPgnMoves('Nf3 Nf6 Ng1 Ng8 Nf3');
      testPath = testTree.mainlinePath;
      testPosition = testTree.nodeAt(testPath).position;
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeEvaluator.works.isNotEmpty, timeout: const Duration(seconds: 2));
      expect(fakeSocket.sent, isEmpty);
    });

    test('an evaluation request is sent for a position reached by a pawn move', () async {
      // SPEC INV-020.
      // The last move is a pawn move, so the position cannot have repeated: the search may go on.
      testTree = Root.fromPgnMoves('Nf3 Nf6 Ng1 Ng8 Nf3 d5');
      testPath = testTree.mainlinePath;
      testPosition = testTree.nodeAt(testPath).position;
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      expect(fakeSocket.sent.first.$1, 'evalGet');
    });

    test('an evaluation request asks for the number of lines the user chose', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);
      final numEvalLines = container.read(engineEvaluationPreferencesProvider).numEvalLines;

      controller.requestEval();

      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      expect((fakeSocket.sent.first.$2! as Map<String, Object?>)['mpv'], numEvalLines);
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      expect(fakeEvaluator.works.single.multiPv, numEvalLines);
    });

    test('an evaluation request names the variant of a variant game', () async {
      // SPEC INV-020.
      testPosition = _variantPosition;
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      expect((fakeSocket.sent.first.$2! as Map<String, Object?>)['variant'], 'antichess');
      await waitUntil(() => httpRequests.isNotEmpty);
      expect(httpRequests.single.url.queryParameters['variant'], 'antichess');
    });

    test('an evaluation request names no variant for a standard game', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      expect((fakeSocket.sent.first.$2! as Map<String, Object?>).containsKey('variant'), isFalse);
      await waitUntil(() => httpRequests.isNotEmpty);
      expect(httpRequests.single.url.queryParameters.containsKey('variant'), isFalse);
    });
  });

  group('cloud evaluation', () {
    test('a cloud evaluation is applied to the node it belongs to', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => testTree.eval != null);
      expect(testTree.eval, isA<CloudEval>());
      expect((testTree.eval! as CloudEval).depth, 20);
      expect((testTree.eval! as CloudEval).cp, 25);
      // The server counts the nodes in thousands.
      expect((testTree.eval! as CloudEval).nodes, 1000 * 1000);
      expect((testTree.eval! as CloudEval).pvs.first.moves, ['e2e4', 'e7e5']);
    });

    test('a failed cloud evaluation request is ignored', () async {
      // SPEC INV-020.
      final container = await readyContainer(
        await makeTestContainer(body: _cloudEvalBody(), status: 404),
      );
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => httpRequests.isNotEmpty);
      await pumpEventQueue();
      expect(testTree.eval, isNull);
    });

    test('a cloud evaluation without a depth is ignored', () async {
      // SPEC INV-020.
      final container = await readyContainer(
        await makeTestContainer(body: _cloudEvalBody(depth: 0)),
      );
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => httpRequests.isNotEmpty);
      await pumpEventQueue();
      expect(testTree.eval, isNull);
    });

    test('a cloud evaluation of the same depth does not replace the one the node has', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 20, cp: 25));
      await readyContainer(await makeTestContainer());

      fakeSocket.events.add(
        const SocketEvent(
          topic: 'evalHit',
          data: {
            'path': '',
            'knodes': 1000,
            'depth': 20,
            'pvs': [
              {'moves': 'e2e4', 'cp': 50},
            ],
          },
        ),
      );

      await waitUntil(() => evalChanges.isNotEmpty);
      expect((testTree.eval! as CloudEval).cp, 25);
    });

    test('a cloud evaluation of the same value is reported as unchanged', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 10));
      await readyContainer(await makeTestContainer());

      fakeSocket.events.add(
        const SocketEvent(
          topic: 'evalHit',
          data: {
            'path': '',
            'knodes': 1000,
            'depth': 20,
            'pvs': [
              {'moves': 'e2e4', 'cp': 25},
            ],
          },
        ),
      );

      await waitUntil(() => evalChanges.isNotEmpty);
      expect(evalChanges, everyElement(isTrue));
    });
  });

  group('local evaluation', () {
    test('the local evaluation is stored on the node it belongs to', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 30)));

      await waitUntil(() => testTree.eval != null);
      expect(testTree.eval, isA<LocalEval>());
      expect((testTree.eval! as LocalEval).depth, 30);
    });

    test('a cloud evaluation that is at least as deep as the local one is kept', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 20));
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 10)));

      await pumpEventQueue();
      expect(testTree.eval, isA<CloudEval>());
    });

    test('a cloud evaluation of the same depth is not replaced by the local one', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 10));
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 10)));

      await pumpEventQueue();
      expect(testTree.eval, isA<CloudEval>());
    });

    test('a deeper local evaluation replaces a shallower cloud evaluation', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 10));
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 20)));

      await waitUntil(() => testTree.eval is LocalEval);
      expect((testTree.eval! as LocalEval).depth, 20);
    });

    test('the local evaluation is reported as changed when its value changed', () async {
      // SPEC INV-020.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 5, cp: 25));
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 10, cp: 50)));

      await waitUntil(() => evalChanges.isNotEmpty);
      expect(evalChanges.single, isFalse);
    });

    test('a local evaluation for a path the tree does not have reports no change', () async {
      // SPEC INV-020.
      testPath = const UciPath('aa');
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval()));

      await waitUntil(() => evalChanges.isNotEmpty);
      expect(evalChanges, everyElement(isTrue));
    });

    test('a cloud evaluation for a path the tree does not have reports no change', () async {
      // SPEC INV-020.
      testPath = const UciPath('aa');
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeSocket.sent.isNotEmpty);
      fakeSocket.events.add(
        const SocketEvent(
          topic: 'evalHit',
          data: {
            'path': 'aa',
            'knodes': 1000,
            'depth': 20,
            'pvs': [
              {'moves': 'e2e4', 'cp': 25},
            ],
          },
        ),
      );

      await waitUntil(() => evalChanges.isNotEmpty);
      expect(evalChanges, everyElement(isTrue));
    });

    test('a cloud evaluation for another path does not refresh the current path', () async {
      // SPEC INV-020.
      // The node already holds a cloud evaluation, so the screen asks for none over HTTP and
      // only the socket can deliver one.
      testTree = Root(position: Chess.initial, eval: _cloudEval());
      testPath = const UciPath('aa');
      await readyContainer(await makeTestContainer());

      fakeSocket.events.add(
        const SocketEvent(
          topic: 'evalHit',
          data: {
            'path': 'bb',
            'knodes': 1000,
            'depth': 20,
            'pvs': [
              {'moves': 'e2e4', 'cp': 25},
            ],
          },
        ),
      );

      await pumpEventQueue();
      expect(evalChanges, isEmpty);
    });

    test('a local evaluation that arrives after the screen moved on does not refresh it', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      // The screen moved on while the search was running.
      evalChanges.clear();
      container.read(_testControllerProvider).requireValue.currentPath = const UciPath('bb');
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval()));

      await pumpEventQueue();
      expect(evalChanges, isEmpty);
    });

    test('the local engine is stopped only when the cloud evaluation is likely better', () async {
      // SPEC INV-020.
      // The configured search time is four seconds, so a search that found 500 nodes in one
      // second would reach 2000 of them in four.
      testTree = Root(position: Chess.initial, eval: _cloudEval(depth: 20, nodes: 4000));
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      // 500 nodes in one second: 2000 in four, which is less than the 4000 of the cloud eval.
      fakeEvaluator.streams.last.add((fakeEvaluator.works.last, _localEval(depth: 10, nodes: 500)));
      await waitUntil(() => fakeEvaluator.stopCount == 1);

      // The same search reaching exactly what the cloud evaluation reached is no better.
      fakeEvaluator.stopCount = 0;
      fakeEvaluator.streams.last.add((
        fakeEvaluator.works.last,
        _localEval(depth: 10, nodes: 1000),
      ));
      await pumpEventQueue();
      expect(fakeEvaluator.stopCount, 0);
    });
  });

  group('node estimate', () {
    test('a search with no elapsed time yields no estimate', () {
      // SPEC INV-020.
      expect(
        likelyNodesFor(targetTime: const Duration(seconds: 4), nodes: 1000, elapsed: Duration.zero),
        isNull,
      );
    });

    test('a search that reported no nodes yields an estimate of zero', () {
      // SPEC INV-020.
      expect(
        likelyNodesFor(
          targetTime: const Duration(seconds: 4),
          nodes: 0,
          elapsed: const Duration(seconds: 1),
        ),
        0,
      );
    });

    test('the estimate scales the node count with the time the search took', () {
      // SPEC INV-020.
      expect(
        likelyNodesFor(
          targetTime: const Duration(seconds: 4),
          nodes: 1000,
          elapsed: const Duration(seconds: 1),
        ),
        4000,
      );
    });
  });

  group('evaluation lines', () {
    test(
      'changing the number of evaluation lines clears the evaluations saved in the tree',
      () async {
        // SPEC INV-020.
        testTree = Root(position: Chess.initial, eval: _cloudEval());
        final container = await readyContainer(await makeTestContainer());

        container.read(_testControllerProvider.notifier).setNumEvalLines(3);

        expect(testTree.eval, isNull);
      },
    );

    test('changing the number of evaluation lines reports that the evaluation changed', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());

      container.read(_testControllerProvider.notifier).setNumEvalLines(3);

      expect(evalChanges, [false]);
    });
  });

  group('evaluation work', () {
    test('an ordinary evaluation is not marked as a deeper search', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();

      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      expect(fakeEvaluator.works.single.isDeeper, isNull);
    });

    test('a deeper search is marked as one', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval(goDeeper: true);

      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      expect(fakeEvaluator.works.single.isDeeper, isTrue);
    });

    test('an ordinary evaluation searches for the configured time', () async {
      // SPEC INV-020.
      final container = await readyContainer(await makeTestContainer());
      final controller = container.read(_testControllerProvider.notifier);
      final searchTime = container.read(engineEvaluationPreferencesProvider).engineSearchTime;

      controller.requestEval();

      await waitUntil(() => fakeEvaluator.works.isNotEmpty);
      expect(fakeEvaluator.works.single.searchTime, searchTime);
    });

    test(
      'the local engine waits for the cloud evaluation when the screen always asks for one',
      () async {
        // SPEC INV-020.
        testAlwaysRequestCloudEval = true;
        final container = await readyContainer(await makeTestContainer());
        final controller = container.read(_testControllerProvider.notifier);

        fakeAsync((async) {
          controller.requestEval();
          async.elapse(kRequestEvalDebounceDelay + const Duration(milliseconds: 10));
          expect(fakeEvaluator.works, isEmpty);
          async.elapse(kLocalEngineAfterCloudEvalDelay);
          expect(fakeEvaluator.works, hasLength(1));
          async.flushTimers();
        });
      },
    );

    test('the local engine starts at once when the engine searches for the maximum time', () async {
      // SPEC INV-020.
      testAlwaysRequestCloudEval = true;
      final container = await readyContainer(await makeTestContainer());
      await container
          .read(engineEvaluationPreferencesProvider.notifier)
          .setEngineSearchTime(kMaxEngineSearchTime);
      final controller = container.read(_testControllerProvider.notifier);

      fakeAsync((async) {
        controller.requestEval();
        async.elapse(kRequestEvalDebounceDelay + const Duration(milliseconds: 10));
        expect(fakeEvaluator.works, hasLength(1));
        async.flushTimers();
      });
    });
  });

  group('evaluator subscription', () {
    test('a new eval request cancels the subscription of the replaced request', () async {
      final container = await makeTestContainer();
      final subscription = container.listen(_testControllerProvider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(_testControllerProvider.future);
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      // Poll for the dispatch instead of sleeping out the debounce plus a margin: the debounce is
      // a real 250ms timer, and under contention the margin is what decides whether the request
      // has gone out yet.
      await waitUntil(
        () => fakeEvaluator.streams.length == 1 && fakeEvaluator.streams.single.hasListener,
      );

      expect(fakeEvaluator.streams, hasLength(1));
      expect(fakeEvaluator.streams.single.hasListener, isTrue);

      controller.requestEval();
      await waitUntil(
        () => fakeEvaluator.streams.length == 2 && fakeEvaluator.streams.last.hasListener,
      );

      expect(fakeEvaluator.streams, hasLength(2));
      expect(
        fakeEvaluator.streams.first.hasListener,
        isFalse,
        reason: 'the replaced request must not leave a listener on the evaluator stream',
      );
      expect(fakeEvaluator.streams.last.hasListener, isTrue);
    });

    test('disposing the notifier cancels the eval stream subscription', () async {
      final container = await makeTestContainer();
      final subscription = container.listen(_testControllerProvider, (_, _) {});

      await container.read(_testControllerProvider.future);
      final controller = container.read(_testControllerProvider.notifier);

      controller.requestEval();
      await waitUntil(
        () => fakeEvaluator.streams.length == 1 && fakeEvaluator.streams.single.hasListener,
      );
      expect(fakeEvaluator.streams.single.hasListener, isTrue);

      // closing the last listener disposes the autoDispose notifier
      subscription.close();
      // A deterministic settle, not a timed wait: the disposal runs in the turn close()
      // schedules, and the check below is an absence — a poll cannot express "still gone".
      await pumpEventQueue();

      expect(
        fakeEvaluator.streams.single.hasListener,
        isFalse,
        reason: 'a disposed notifier must not leave a listener on the evaluator stream',
      );
    });
  });

  group('socket', () {
    test(
      'a socket that arrives after the screen was built still delivers the evaluation events',
      () async {
        // SPEC INV-020.
        buildGate = Completer<void>();
        testSocket = null;
        final container = await makeTestContainer();
        final subscription = container.listen(_testControllerProvider, (_, _) {});
        addTearDown(subscription.close);
        container.read(_testControllerProvider.notifier);

        // The socket arrives while the screen is still loading.
        testSocket = fakeSocket;
        buildGate!.complete();
        await container.read(_testControllerProvider.future);

        fakeSocket.events.add(
          const SocketEvent(
            topic: 'evalHit',
            data: {
              'path': '',
              'knodes': 1000,
              'depth': 20,
              'pvs': [
                {'moves': 'e2e4', 'cp': 25},
              ],
            },
          ),
        );

        await waitUntil(() => testTree.eval != null);
        expect(testTree.eval, isA<CloudEval>());

        // The socket is subscribed once, and stays subscribed: the screen changing again must not
        // tear the subscription down and build it again.
        final streamReads = fakeSocket.streamReads;
        container.read(_testControllerProvider.notifier).toggleEngineThreatMode();
        await pumpEventQueue();
        expect(fakeSocket.streamReads, streamReads);
      },
    );
  });
}
