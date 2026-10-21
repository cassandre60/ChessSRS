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
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';

const _testContext = EvaluationContext(
  id: StringId('eval_mixin_test'),
  variant: Variant.standard,
  initialPosition: Chess.initial,
);

/// White to move, and the black rook on e2 has the white king in check.
final _inCheck = Chess.fromSetup(Setup.parseFen('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1'));

/// White to move, and the black king on h8 would be stalemated if it were its turn.
final _stalematesOpponent = Chess.fromSetup(Setup.parseFen('7k/5Q2/6K1/8/8/8/8/8 w - - 0 1'));

/// An evaluator that does not touch any engine: it hands out controllable streams so the test can
/// observe whether the mixin keeps the returned subscription alive or cancels it.
class _FakePositionEvaluator extends PositionEvaluator {
  _FakePositionEvaluator(super.context);

  /// Every stream handed out by [evaluate], in request order.
  final List<StreamController<EvalResult>> streams = [];

  /// Every work [evaluate] was asked for, in request order.
  final List<EvalWork> works = [];

  /// How many times the mixin stopped the search.
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

/// A socket client that records what the mixin sent and lets the test hand it events.
///
/// The real client only feeds its stream from a live WebSocket channel; a test needs to deliver
/// an `evalHit` on demand, and to read back what was sent.
class _FakeSocketClient extends SocketClient {
  _FakeSocketClient()
    : super(
        Uri(path: kDefaultSocketRoute),
        channelFactory: const WebSocketChannelFactory(),
        getSession: () => null,
        packageInfo: PackageInfo(
          appName: 'chess_srs_test',
          version: 'test',
          buildNumber: '0.0.0',
          packageName: 'chess_srs_test',
        ),
        deviceInfo: BaseDeviceInfo({
          'name': 'test',
          'model': 'test',
          'manufacturer': 'test',
          'systemName': 'test',
          'systemVersion': 'test',
          'identifierForVendor': 'test',
          'isPhysicalDevice': true,
        }),
        sri: 'testSri',
      );

  late final StreamController<SocketEvent> _controller = StreamController<SocketEvent>.broadcast(
    onListen: () => listenCount++,
    onCancel: () => cancelCount++,
  );

  /// How many times something subscribed to [stream].
  int listenCount = 0;

  /// How many times the last subscription to [stream] was cancelled.
  int cancelCount = 0;

  /// Every message the mixin sent, in order.
  final List<(String, Object?)> sent = [];

  @override
  Stream<SocketEvent> get stream => _controller.stream;

  @override
  void send(String topic, Object? data, {bool? ackable, bool? withLag, bool noRetry = false}) {
    sent.add((topic, data));
  }

  /// The `evalHit` event the server sends for a cloud evaluation.
  void emitEvalHit({
    required String path,
    required int depth,
    required int knodes,
    int? cp,
    int? mate,
    String moves = 'e2e4',
  }) {
    _controller.add(
      SocketEvent(
        topic: 'evalHit',
        data: {
          'path': path,
          'depth': depth,
          'knodes': knodes,
          'pvs': [
            {'moves': moves, 'cp': cp, 'mate': mate},
          ],
        },
      ),
    );
  }

  /// The `evalGet` messages the mixin sent, in order.
  List<Map<String, Object?>> get evalGets => [
    for (final (topic, data) in sent)
      if (topic == 'evalGet' && data is Map<String, Object?>) data,
  ];

  Future<void> shutdown() => _controller.close();
}

/// Engine preferences that are fixed, for the tests that need a particular search time.
class _FixedEvaluationPrefs extends EngineEvaluationPreferences {
  _FixedEvaluationPrefs(this.fixed);

  final EngineEvaluationPrefState fixed;

  @override
  EngineEvaluationPrefState build() => fixed;
}

/// What the screen the mixin drives looks like.
class _TestConfig {
  _TestConfig({
    this.position = Chess.initial,
    this.path = UciPath.empty,
    this.tree,
    this.socket,
    this.alwaysRequestCloudEval = false,
  });

  /// The position the screen is on.
  final Position position;

  /// The path of that position in the tree.
  final UciPath path;

  /// The tree the evaluations are stored in. Defaults to a lone root.
  final Node? tree;

  /// The socket the mixin talks to, if there is one.
  final _FakeSocketClient? socket;

  /// Whether the screen always asks the cloud first.
  final bool alwaysRequestCloudEval;
}

class _TestState with EvaluationMixinState<_TestState> {
  _TestState({
    this.position = Chess.initial,
    this.path = UciPath.empty,
    this.engineInThreatMode = false,
    this.alwaysRequestCloudEval = false,
  });

  final Position position;
  final UciPath path;

  @override
  final bool engineInThreatMode;

  @override
  final bool alwaysRequestCloudEval;

  @override
  bool isEngineAvailable(EngineEvaluationPrefState prefs) => true;

  @override
  EvaluationContext get evaluationContext => _testContext;

  @override
  UciPath get currentPath => path;

  @override
  Position? get currentPosition => position;

  @override
  _TestState withThreatMode(bool engineInThreatMode) => _TestState(
    position: position,
    path: path,
    engineInThreatMode: engineInThreatMode,
    alwaysRequestCloudEval: alwaysRequestCloudEval,
  );

  /// The same screen, on another position.
  _TestState withPath(UciPath newPath) => _TestState(
    position: position,
    path: newPath,
    engineInThreatMode: engineInThreatMode,
    alwaysRequestCloudEval: alwaysRequestCloudEval,
  );
}

class _TestController extends AsyncNotifier<_TestState> with EngineEvaluationMixin<_TestState> {
  _TestController(this.config);

  final _TestConfig config;

  /// The socket the mixin talks to.
  ///
  /// It is null until the socket exists: the mixin has to cope with a socket that is created
  /// after the screen is, which is what [config.socket] being null means.
  _FakeSocketClient? socket;

  /// The evaluation refreshes the mixin signalled, in order.
  final List<bool> evalChanged = [];

  late final Node _tree = config.tree ?? Root(position: config.position);

  @override
  Future<_TestState> build() async => _TestState(
    position: config.position,
    path: config.path,
    alwaysRequestCloudEval: config.alwaysRequestCloudEval,
  );

  @override
  SocketClient? get socketClient => socket ?? config.socket;

  @override
  Node get positionTree => _tree;

  @override
  void onCurrentPathEvalChanged(bool isSameEvalString) {
    evalChanged.add(isSameEvalString);
  }

  /// Moves the screen to another position of the tree.
  void moveTo(UciPath newPath) {
    state = AsyncData(state.requireValue.withPath(newPath));
  }
}

final _testControllerProvider = AsyncNotifierProvider.autoDispose
    .family<_TestController, _TestState, _TestConfig>(
      _TestController.new,
      name: 'TestEvalControllerProvider',
    );

/// Builds a tree whose mainline is the given UCI moves, played from the standard start.
Node _buildTree(List<String> uciMoves) {
  final root = Root(position: Chess.initial);
  Node parent = root;
  var position = root.position;
  for (final uci in uciMoves) {
    final move = Move.parse(uci)!;
    final (newPosition, san) = position.makeSanUnchecked(move);
    final branch = Branch(position: newPosition, sanMove: SanMove(san, move));
    parent.addChild(branch);
    parent = branch;
    position = newPosition;
  }
  return root;
}

/// Builds a tree whose root has one branch per given UCI move, each played from the start.
Node _buildTreeWithBranches(List<String> uciMoves) {
  final root = Root(position: Chess.initial);
  for (final uci in uciMoves) {
    final move = Move.parse(uci)!;
    final (newPosition, san) = root.position.makeSanUnchecked(move);
    root.addChild(Branch(position: newPosition, sanMove: SanMove(san, move)));
  }
  return root;
}

/// A cloud evaluation as the server reports it over HTTP.
String _cloudEvalBody({required int depth, required int knodes, int? cp}) =>
    '{"depth": $depth, "knodes": $knodes, "pvs": [{"moves": "e2e4", "cp": $cp}]}';

/// A local evaluation as the engine reports it.
LocalEval _localEval({
  required int depth,
  required int nodes,
  required Duration searchTime,
  int? cp = 30,
  bool threatMode = false,
}) => LocalEval(
  position: Chess.initial,
  depth: depth,
  nodes: nodes,
  pvs: IList([
    PvData(moves: const IListConst(['e2e4']), cp: cp),
  ]),
  millis: searchTime.inMilliseconds,
  searchTime: searchTime,
  threatMode: threatMode,
);

/// A cloud evaluation as the server reports it.
CloudEval _cloudEval({required int depth, required int nodes, int? cp = 30}) => CloudEval(
  position: Chess.initial,
  depth: depth,
  nodes: nodes,
  pvs: IList([
    PvData(moves: const IListConst(['e2e4']), cp: cp),
  ]),
);

void main() {
  TestLichessBinding.ensureInitialized();

  late _FakePositionEvaluator fakeEvaluator;

  Future<ProviderContainer> makeTestContainer({
    http.Client Function()? httpClient,
    Duration? searchTime,
  }) => makeContainer(
    overrides: {
      positionEvaluatorProvider: positionEvaluatorProvider.overrideWith2((_) => fakeEvaluator),
      if (httpClient != null)
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(httpClient),
        ),
      if (searchTime != null)
        engineEvaluationPreferencesProvider: engineEvaluationPreferencesProvider.overrideWith(
          () => _FixedEvaluationPrefs(
            EngineEvaluationPrefState.defaults.copyWith(engineSearchTime: searchTime),
          ),
        ),
    },
  );

  setUp(() {
    fakeEvaluator = _FakePositionEvaluator(_testContext);
  });

  test('a new eval request cancels the subscription of the replaced request', () async {
    final container = await makeTestContainer();
    final config = _TestConfig();
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

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
    final config = _TestConfig();
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

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

  // SPEC INV-020. The engine's answer is the app's answer, and the app may not put a verdict of
  // its own where the engine's belongs. The threat mode is the engine's verdict seen from the
  // other side, so it is only offered where that other side could actually answer: a king in
  // check cannot be asked what it would do, and a stalemated opponent has no move to report.
  test('threat mode is only offered where the opponent could answer', () {
    expect(
      _TestState().canShowThreat,
      isTrue,
      reason: 'a quiet position can be looked at from the other side',
    );
    expect(
      _TestState(position: _inCheck).canShowThreat,
      isFalse,
      reason: 'the side in check has no move to report',
    );
    expect(
      _TestState(position: _stalematesOpponent).canShowThreat,
      isFalse,
      reason: 'a stalemated opponent has no move to report either',
    );
  });

  // SPEC INV-020. The threat mode is the engine's verdict from the other side; refusing to ask
  // for it would leave the user with a mode they could never leave.
  test('threat mode can be turned on where it is offered', () async {
    final container = await makeTestContainer();
    final config = _TestConfig();
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    expect(controller.state.requireValue.engineInThreatMode, isFalse);

    await controller.toggleEngineThreatMode();

    expect(controller.state.requireValue.engineInThreatMode, isTrue);
  });

  // SPEC INV-020. The engine's verdict is only useful against a comparison that can be made.
  // A search that has measured no time has no rate to project from, and dividing by that zero
  // is not a number; `likely_nodes_test.dart` covers that case. What it does not cover is a
  // search that visited nothing: it visited nothing at a rate of zero, and zero is a rate.
  test('a search that visited no node still has a rate', () {
    expect(
      likelyNodesFor(
        targetTime: const Duration(seconds: 1),
        nodes: 0,
        elapsed: const Duration(milliseconds: 100),
      ),
      0,
      reason: 'a search that visited nothing is a rate of zero, not an absent one',
    );
  });

  // SPEC INV-020. The cloud evaluation is the server's verdict; the local one is the engine's.
  // The deeper one is the better one, and the app shows what it was told.
  test('a cloud evaluation of the same depth does not replace the local one', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);

    final local = _localEval(depth: 30, nodes: 5000, searchTime: const Duration(seconds: 1));
    tree.eval = local;

    socket.emitEvalHit(path: '', depth: 30, knodes: 5, cp: 30);
    await pumpEventQueue();

    expect(
      tree.eval,
      same(local),
      reason: 'the local evaluation is kept unless the cloud one is deeper',
    );
  });

  // SPEC INV-020. The screen is told whether the evaluation it shows changed. An evaluation
  // that was not applied changed nothing, so the screen is told there is nothing new to draw.
  test('a cloud evaluation that was not applied tells the screen nothing changed', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _localEval(depth: 30, nodes: 5000, searchTime: const Duration(seconds: 1));

    socket.emitEvalHit(path: '', depth: 20, knodes: 5, cp: 30);
    await pumpEventQueue();

    expect(controller.evalChanged, [
      true,
    ], reason: 'the stored evaluation did not change, so the screen need not be refreshed');
  });

  // SPEC INV-020. The server counts the nodes it visited in thousands; the app compares node
  // counts against the engine's own, which are single nodes.
  test('a cloud evaluation reports the node count the server counted', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);

    socket.emitEvalHit(path: '', depth: 20, knodes: 5, cp: 30);
    await pumpEventQueue();

    final eval = tree.eval;
    expect(eval, isA<CloudEval>());
    expect(eval!.depth, 20);
    expect(eval.nodes, 5000, reason: 'the server counts in thousands, the app counts in nodes');
    expect(eval.cp, 30);
  });

  // SPEC INV-020. An evaluation for another position is another position's verdict; the screen
  // the user is looking at is not the one it belongs to.
  test('an evaluation for another path does not refresh the screen', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final path = UciPath.fromUciMoves(['e2e4']);
    final config = _TestConfig(
      position: tree.branchAt(path)!.position,
      path: path,
      tree: tree,
      socket: socket,
    );
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    // The evaluation is for the root, the screen is on the move after it.
    socket.emitEvalHit(path: '', depth: 20, knodes: 5, cp: 30);
    await pumpEventQueue();

    expect(tree.eval, isA<CloudEval>(), reason: 'the evaluation is still stored where it belongs');
    expect(
      controller.evalChanged,
      isEmpty,
      reason: 'the screen is on another position, so it has nothing new to draw',
    );
  });

  // SPEC INV-020. The screen is told whether the evaluation it shows is the same one it was
  // showing, so that an unchanged evaluation does not cost a redraw.
  test('an unchanged evaluation string is reported as unchanged', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 10, nodes: 1000, cp: 30);

    socket.emitEvalHit(path: '', depth: 20, knodes: 5, cp: 30);
    await pumpEventQueue();

    expect(controller.evalChanged, [
      true,
    ], reason: 'the score is the same one the screen was already showing');
  });

  // SPEC INV-020. The cloud is asked once for a position: its answer does not change, and
  // asking again spends a request on a verdict the app already has.
  test('the cloud is not asked again for a position that already has a cloud evaluation', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 10, nodes: 1000, cp: 30);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
    });

    expect(
      socket.evalGets,
      isEmpty,
      reason: 'the app already holds the cloud verdict for this position',
    );
  });

  // SPEC INV-020. The cloud cannot answer for a position that may have been reached before:
  // its verdict would be about a different history.
  test('the cloud is not asked for a position that can be reached again', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    // Knight moves only: a pawn move would make the repetition impossible and the cloud would
    // be asked after all. The last move plays the position of the first one again, so the
    // repetition is only visible at the far end of the line.
    final uciMoves = ['g1f3', 'g8f6', 'f3g1', 'f6g8', 'g1f3'];
    final tree = _buildTree(uciMoves);
    final path = UciPath.fromUciMoves(uciMoves);
    final config = _TestConfig(
      position: tree.branchAt(path)!.position,
      path: path,
      tree: tree,
      socket: socket,
    );
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
    });

    expect(
      socket.evalGets,
      isEmpty,
      reason:
          'the position has been reached before, so the cloud verdict would be about '
          'another history',
    );
  });

  // SPEC INV-020. A position that cannot repeat is one the cloud can answer for.
  test('the cloud is asked for a position that cannot be reached again', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final uciMoves = ['g1f3'];
    final tree = _buildTree(uciMoves);
    final path = UciPath.fromUciMoves(uciMoves);
    final config = _TestConfig(
      position: tree.branchAt(path)!.position,
      path: path,
      tree: tree,
      socket: socket,
    );
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
    });

    expect(
      socket.evalGets,
      hasLength(1),
      reason: 'the cloud is asked for a position it can answer',
    );
  });

  // SPEC INV-020. The cloud is asked for a position that cannot repeat, even when a pawn has
  // already moved: from there on the position is new by definition.
  test('the cloud is asked for a position a pawn move has already made new', () async {
    final container = await makeTestContainer();
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final uciMoves = ['e2e4'];
    final tree = _buildTree(uciMoves);
    final path = UciPath.fromUciMoves(uciMoves);
    final config = _TestConfig(
      position: tree.branchAt(path)!.position,
      path: path,
      tree: tree,
      socket: socket,
    );
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
    });

    expect(
      socket.evalGets,
      hasLength(1),
      reason: 'the cloud is asked for a position it can answer',
    );
  });

  // SPEC INV-020. The socket may be created after the screen is; the evaluations the server
  // sends are then still the screen's verdicts, and they must reach it.
  test('the mixin attaches to the socket once the screen has a position', () async {
    final container = await makeTestContainer();
    final config = _TestConfig();
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    final controller = container.read(_testControllerProvider(config).notifier);

    // The socket is created after the screen is, but before the screen has a position to show:
    // that is the window the mixin has to attach in.
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    controller.socket = socket;

    await container.read(_testControllerProvider(config).future);
    await pumpEventQueue();

    expect(socket.listenCount, 1, reason: 'the mixin subscribes to the socket exactly once');

    socket.emitEvalHit(path: '', depth: 20, knodes: 5, cp: 30);
    await pumpEventQueue();

    expect(
      controller.evalChanged,
      hasLength(1),
      reason: 'the evaluation the server sent reached the screen',
    );
  });

  // SPEC INV-020. The engine's verdict is the app's verdict; a worse one does not replace a
  // better one that is already on file.
  test('a local evaluation does not replace a better one already stored', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    final stored = _localEval(depth: 30, nodes: 5000, searchTime: const Duration(seconds: 1));
    tree.eval = stored;

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    expect(work.isDeeper, isNull, reason: 'an ordinary request is not a deeper one');
    expect(work.searchTime, isNot(kMaxEngineSearchTime));

    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 20, nodes: 1000, searchTime: const Duration(seconds: 1)),
    ));
    await pumpEventQueue();

    expect(tree.eval, same(stored), reason: 'the deeper evaluation is the better one');
  });

  // SPEC INV-020. The cloud's verdict and the engine's verdict are both about the position;
  // the deeper one is the better one.
  test('a local evaluation of the same depth does not replace the cloud evaluation', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    final cloud = _cloudEval(depth: 30, nodes: 100000);
    tree.eval = cloud;

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 30, nodes: 1000, searchTime: const Duration(milliseconds: 100)),
    ));
    await pumpEventQueue();

    expect(tree.eval, same(cloud), reason: 'neither verdict is deeper than the other');
    expect(controller.evalChanged, [
      true,
    ], reason: 'the evaluation on file did not change, so the screen need not be refreshed');
  });

  // SPEC INV-020. A deeper engine verdict is a better one, and it replaces what was on file.
  test('a deeper local evaluation replaces the cloud evaluation', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 10, nodes: 100000);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    final local = _localEval(
      depth: 30,
      nodes: 1000,
      searchTime: const Duration(milliseconds: 100),
      cp: 50,
    );
    fakeEvaluator.streams.first.add((work, local));
    await pumpEventQueue();

    expect(tree.eval, same(local), reason: 'the deeper engine verdict is the better one');
    expect(controller.evalChanged, [
      false,
    ], reason: 'the score on file changed, so the screen has something new to draw');
  });

  // SPEC INV-020. "Go deeper" is the user asking for a better answer than the one on file; the
  // search runs for as long as it takes, and its answer is the one that counts.
  test('go deeper searches for the maximum time and replaces the cloud evaluation', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 30, nodes: 100000);

    controller.requestEval(goDeeper: true);
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    expect(work.searchTime, kMaxEngineSearchTime);
    expect(work.isDeeper, isTrue);

    final local = _localEval(depth: 30, nodes: 1000, searchTime: const Duration(milliseconds: 100));
    fakeEvaluator.streams.first.add((work, local));
    await pumpEventQueue();

    expect(tree.eval, same(local), reason: 'the deeper search is the answer the user asked for');
  });

  // SPEC INV-020. The search time the user chose is the one the engine is given; a search that
  // runs for the maximum time is still the engine's answer, and it replaces what was on file.
  test('a search that runs for the maximum time replaces the cloud evaluation', () async {
    final container = await makeTestContainer(searchTime: kMaxEngineSearchTime);
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 30, nodes: 100000);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    expect(work.searchTime, kMaxEngineSearchTime);
    expect(work.isDeeper, isNull, reason: 'the search time was the user\'s, not "go deeper"');

    final local = _localEval(depth: 30, nodes: 1000, searchTime: const Duration(milliseconds: 100));
    fakeEvaluator.streams.first.add((work, local));
    await pumpEventQueue();

    expect(tree.eval, same(local), reason: 'the search for the maximum time is the answer');
  });

  // SPEC INV-020. The local search is stopped when the cloud has already done the work: the
  // engine's time is better spent elsewhere.
  test('the local engine stops when the cloud evaluation is ahead', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    // The local search ran at a thousand nodes per second and would reach the projected count
    // in the time it was given; the cloud is further ahead than that.
    final projected = likelyNodesFor(
      targetTime: work.searchTime,
      nodes: 1000,
      elapsed: const Duration(milliseconds: 100),
    )!;
    tree.eval = _cloudEval(depth: 30, nodes: projected + 1);

    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 20, nodes: 1000, searchTime: const Duration(milliseconds: 100)),
    ));
    await pumpEventQueue();

    expect(fakeEvaluator.stopCount, 1, reason: 'the cloud has already been there');
  });

  // SPEC INV-020. A search that has not measured any time cannot be projected onto one; the
  // comparison is skipped rather than made on a number that does not exist.
  test('the local engine is not stopped on a comparison it cannot make', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    tree.eval = _cloudEval(depth: 30, nodes: 100000);

    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 20, nodes: 1000, searchTime: Duration.zero),
    ));
    await pumpEventQueue();

    expect(
      fakeEvaluator.stopCount,
      0,
      reason: 'the rate of a search that measured nothing cannot be compared',
    );
  });

  // SPEC INV-020. The engine is stopped only when the cloud is strictly ahead: an equal
  // verdict is no reason to give up the search.
  test('the local engine keeps searching when the cloud is exactly as thorough', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    // The cloud is exactly where the local search would be in the time it was given.
    final projected = likelyNodesFor(
      targetTime: work.searchTime,
      nodes: 1000,
      elapsed: const Duration(milliseconds: 100),
    )!;
    tree.eval = _cloudEval(depth: 30, nodes: projected);

    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 20, nodes: 1000, searchTime: const Duration(milliseconds: 100)),
    ));
    await pumpEventQueue();

    expect(
      fakeEvaluator.stopCount,
      0,
      reason: 'the cloud is no further ahead than the local search would be',
    );
  });

  // SPEC INV-020. The cloud verdict reaches the screen over HTTP as well as over the socket.
  test('a cloud evaluation fetched over HTTP reaches the tree', () async {
    final container = await makeTestContainer(
      httpClient: () =>
          MockClient((_) async => http.Response(_cloudEvalBody(depth: 20, knodes: 5, cp: 30), 200)),
    );
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
    });

    final eval = tree.eval;
    expect(eval, isA<CloudEval>());
    expect(eval!.depth, 20);
    expect(eval.nodes, 5000);
    expect(eval.cp, 30);
    expect(eval.pvs.first.moves.toList(), [
      'e2e4',
    ], reason: 'the line the engine searched is the line the app shows');
  });

  // SPEC INV-020. A verdict without a depth is not a verdict: there is nothing to show, and
  // showing it would replace a better evaluation with an empty one.
  test('a cloud evaluation without a depth is ignored', () async {
    var calls = 0;
    final container = await makeTestContainer(
      httpClient: () => MockClient((_) async {
        calls++;
        return http.Response(_cloudEvalBody(depth: 0, knodes: 0, cp: 30), 200);
      }),
    );
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
    });

    expect(calls, 1, reason: 'the cloud was asked');
    expect(tree.eval, isNull, reason: 'a verdict without a depth is not a verdict');
  });

  // SPEC INV-020. A request the server refused carries no verdict; nothing may be made of it.
  test('a cloud evaluation the server refused is ignored', () async {
    var calls = 0;
    final container = await makeTestContainer(
      httpClient: () => MockClient((_) async {
        calls++;
        return http.Response(_cloudEvalBody(depth: 20, knodes: 5, cp: 30), 500);
      }),
    );
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();
    });

    expect(calls, 1, reason: 'the cloud was asked');
    expect(tree.eval, isNull, reason: 'a refused request carries no verdict');
  });

  // SPEC INV-020. The screen may have moved on while the answer was in flight; an answer
  // about a position the user has left is an answer to a question nobody asked any more.
  test('a cloud evaluation that arrives after the screen moved on is ignored', () async {
    final pending = <Completer<http.Response>>[];
    final container = await makeTestContainer(
      httpClient: () => MockClient((_) {
        final completer = Completer<http.Response>();
        pending.add(completer);
        return completer.future;
      }),
    );
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();

      // The screen asks again: the first request is now about a position nobody looks at.
      controller.requestEval();
      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();

      expect(pending, hasLength(2));

      pending.first.complete(http.Response(_cloudEvalBody(depth: 20, knodes: 5, cp: 30), 200));
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(tree.eval, isNull, reason: 'the answer is about a position the screen has left');

      pending.last.complete(http.Response(_cloudEvalBody(depth: 20, knodes: 5, cp: 30), 200));
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(tree.eval, isA<CloudEval>(), reason: 'the answer the screen is waiting for lands');
    });
  });

  // SPEC INV-020. The local engine is the answer the user is waiting for; it does not wait for
  // a cloud verdict nobody asked for.
  test('the local engine starts at once when the cloud is not asked first', () async {
    final container = await makeTestContainer();
    final config = _TestConfig();
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(kRequestEvalDebounceDelay);
    });

    expect(
      fakeEvaluator.works,
      hasLength(1),
      reason: 'the local engine does not wait for a cloud verdict nobody asked for',
    );
  });

  // SPEC INV-020. The cloud is asked first when the screen wants the cloud's verdict; the
  // local engine gives it the chance to answer first.
  test('the local engine waits for the cloud when the cloud is asked first', () async {
    final container = await makeTestContainer();
    final config = _TestConfig(alwaysRequestCloudEval: true);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    fakeAsync((async) {
      controller.requestEval();
      async.elapse(kRequestEvalDebounceDelay);

      expect(fakeEvaluator.works, isEmpty, reason: 'the local engine waits for the cloud verdict');

      async.elapse(kLocalEngineAfterCloudEvalDelay);

      expect(
        fakeEvaluator.works,
        hasLength(1),
        reason: 'the local engine runs once the cloud has had its chance',
      );
    });
  });

  // SPEC INV-020. The cloud has to be asked about the variant the position is played in: the
  // verdict of a different variant is a verdict about a different game.
  test('the cloud request names the variant the position is played in', () async {
    final urls = <Uri>[];
    final container = await makeTestContainer(
      httpClient: () => MockClient((request) async {
        urls.add(request.url);
        return http.Response('', 200);
      }),
    );
    final socket = _FakeSocketClient();
    addTearDown(socket.shutdown);
    final tree = Root(position: Antichess.initial);
    final config = _TestConfig(position: Antichess.initial, tree: tree, socket: socket);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    controller.requestEval();
    await waitUntil(() => socket.evalGets.isNotEmpty);

    expect(socket.evalGets.single['variant'], 'antichess');

    await waitUntil(() => urls.isNotEmpty);
    expect(urls.single.queryParameters['variant'], 'antichess');
  });

  // SPEC INV-020. The evaluations on file were made for a number of lines; when the number
  // changes, they are about a question the user is no longer asking.
  test('changing the number of eval lines clears the evaluations on file', () async {
    final container = await makeTestContainer();
    final tree = _buildTree(['e2e4']);
    final config = _TestConfig(tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    tree.eval = _cloudEval(depth: 10, nodes: 1000, cp: 30);

    controller.setNumEvalLines(1);
    await pumpEventQueue();

    expect(
      tree.eval,
      isNull,
      reason: 'the evaluations on file were made for another number of lines',
    );
    expect(controller.evalChanged, [
      false,
    ], reason: 'the screen has to be told the evaluation it was showing is gone');
  });

  // SPEC INV-020. The answer belongs to the position it is about; a screen that has moved on
  // is not answered by it.
  test('an evaluation for a position the screen has left does not refresh it', () async {
    final container = await makeTestContainer();
    final tree = _buildTreeWithBranches(['e2e4', 'd2d4']);
    final e4Path = UciPath.fromUciMoves(['e2e4']);
    final d4Path = UciPath.fromUciMoves(['d2d4']);
    final config = _TestConfig(position: tree.branchAt(e4Path)!.position, path: e4Path, tree: tree);
    final subscription = container.listen(_testControllerProvider(config), (_, _) {});
    addTearDown(subscription.close);

    await container.read(_testControllerProvider(config).future);
    final controller = container.read(_testControllerProvider(config).notifier);

    controller.requestEval();
    await waitUntil(() => fakeEvaluator.works.isNotEmpty);

    final work = fakeEvaluator.works.first;
    expect(work.path, e4Path);

    // The user moves on before the engine answers.
    controller.moveTo(d4Path);
    await pumpEventQueue();

    fakeEvaluator.streams.first.add((
      work,
      _localEval(depth: 20, nodes: 1000, searchTime: const Duration(seconds: 1)),
    ));
    await pumpEventQueue();

    expect(
      tree.branchAt(e4Path)!.eval,
      isA<LocalEval>(),
      reason: 'the answer still belongs to the position it is about',
    );
    expect(
      controller.evalChanged,
      isEmpty,
      reason: 'the screen is on another position, so it has nothing new to draw',
    );
  });
}
