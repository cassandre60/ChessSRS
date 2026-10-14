import 'dart:async';

import 'package:chess_srs/src/model/account/account_service.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/analysis/common_analysis_state.dart';
import 'package:chess_srs/src/model/analysis/forecast.dart';
import 'package:chess_srs/src/model/analysis/opening_explorer_mixin.dart';
import 'package:chess_srs/src/model/analysis/server_analysis_mixin.dart';
import 'package:chess_srs/src/model/analysis/server_analysis_service.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/service/move_feedback.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/common/socket.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_repository_providers.dart';
import 'package:chess_srs/src/model/game/game_socket_events.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:chess_srs/src/widgets/pgn.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

part 'analysis_controller.freezed.dart';

final _dateFormat = DateFormat('yyyy.MM.dd');

@freezed
sealed class AnalysisOptions with _$AnalysisOptions {
  const AnalysisOptions._();

  const factory AnalysisOptions.standalone({
    required Variant variant,
    @Default(null) int? initialMoveCursor,
    @Default(Side.white) Side orientation,
  }) = Standalone;

  const factory AnalysisOptions.pgn({
    required StringId id,
    required Side orientation,
    int? initialMoveCursor,
    required String pgn,
    required Variant variant,
    required bool isComputerAnalysisAllowed,
  }) = Pgn;

  const factory AnalysisOptions.archivedGame({
    required Side orientation,
    int? initialMoveCursor,
    required GameId gameId,
  }) = ArchivedGame;

  bool get isLichessGameAnalysis => this is ArchivedGame;

  GameId? get gameId => switch (this) {
    ArchivedGame(:final gameId) => gameId,
    Pgn() || Standalone() => null,
  };

  StringId get contextId => switch (this) {
    ArchivedGame(:final gameId) => gameId,
    Pgn(:final id) => id,
    Standalone() => const StringId('standalone'),
  };
}

enum AnalysisGameResult {
  whiteWins,
  blackWins,
  draw,
  other;

  static AnalysisGameResult resultFromPgnResult(String? result) {
    return switch (result) {
      '1-0' => AnalysisGameResult.whiteWins,
      '0-1' => AnalysisGameResult.blackWins,
      '½-½' => AnalysisGameResult.draw,
      '1/2-1/2' => AnalysisGameResult.draw,
      _ => AnalysisGameResult.other,
    };
  }

  String? resultToString(Side side) => switch (this) {
    whiteWins => side == Side.white ? '1' : '0',
    blackWins => side == Side.white ? '0' : '1',
    draw => '½',
    other => null,
  };
}

/// A provider for [AnalysisController].
final analysisControllerProvider = AsyncNotifierProvider.autoDispose
    .family<AnalysisController, AnalysisState, AnalysisOptions>(
      AnalysisController.new,
      name: 'AnalysisControllerProvider',
    );

({Root root, UciPath path, Variant variant})? _savedStandalone;

void clearSavedStandaloneAnalysis() {
  _savedStandalone = null;
}

class AnalysisController extends AsyncNotifier<AnalysisState>
    with
        EngineEvaluationMixin,
        ServerAnalysisMixin<AnalysisState>,
        OpeningExplorerMixin<AnalysisState>
    implements PgnTreeNotifier {
  AnalysisController(this.options);

  final AnalysisOptions options;

  static final Uri socketUri = Uri(path: '/analysis/socket/v5');

  StreamSubscription<SocketEvent>? _socketSubscription;

  late Root _root;
  late Variant _variant;
  late UciPath _currentPath;

  @override
  @protected
  late SocketClient socketClient;

  @override
  @protected
  Root get positionTree => _root;

  @override
  Future<AnalysisState> build() async {
    ref.onDispose(() {
      _socketSubscription?.cancel();
    });

    socketClient = ref.watch(socketPoolProvider).open(AnalysisController.socketUri);
    _socketSubscription?.cancel();
    _socketSubscription = socketClient.stream.listen(_handleSocketEvent);

    isOnline(ref.read(defaultClientProvider)).then((online) {
      if (!ref.mounted) return;
      if (!online) {
        socketClient.close();
      }
    });

    late final String pgn;
    late final LightOpening? opening;
    late final PlayersAnalysis? playersAnalysis;
    late final Division? division;

    ExportedGame? archivedGame;

    switch (options) {
      case ArchivedGame(:final gameId):
        {
          archivedGame = await ref.watch(archivedGameProvider(gameId).future);
          _variant = archivedGame!.meta.variant;
          pgn = archivedGame.makePgn();
          opening = archivedGame.data.opening;
          division = archivedGame.meta.division;
          playersAnalysis = archivedGame.playersAnalysis;
        }
      case Pgn(:final variant, pgn: final gamePgn):
        {
          _variant = variant;
          pgn = gamePgn;
          opening = null;
          division = null;
          playersAnalysis = null;
        }
      case Standalone(:final variant):
        {
          _variant = _savedStandalone != null ? _savedStandalone!.variant : variant;
          pgn = '';
          opening = null;
          division = null;
          playersAnalysis = null;

          // We want to keep the standalone analysis session alive even if the user navigates away
          ref.onCancel(() {
            if (_root.mainline.isNotEmpty) {
              _savedStandalone = (root: _root, path: _currentPath, variant: _variant);
            }
          });
        }
    }

    UciPath path = UciPath.empty;
    Move? lastMove;

    final game = PgnGame.parsePgn(
      pgn,
      initHeaders: () => options.isLichessGameAnalysis
          ? {}
          : {
              'Event': '?',
              'Site': '?',
              'Date': _dateFormat.format(DateTime.now()),
              'Variant': _variant.pgnName,
              'Round': '?',
              'White': '?',
              'Black': '?',
              'Result': '*',
              'WhiteElo': '?',
              'BlackElo': '?',
            },
    );

    final pgnHeaders = IMap(game.headers);
    final rootComments = IList(game.comments.map((c) => PgnComment.fromPgn(c)));

    final isGameFinished = pgnHeaders['Result'] != '*';

    final isComputerAnalysisAllowed = switch (options) {
      Pgn(:final isComputerAnalysisAllowed) => isComputerAnalysisAllowed,
      ArchivedGame() => isGameFinished || archivedGame?.source == .import,
      Standalone() => true,
    };

    _root = switch (options) {
      Standalone() when _savedStandalone != null => _savedStandalone!.root,
      _ => Root.fromPgnGame(
        game,
        isLichessAnalysis: options.isLichessGameAnalysis,
        onVisitNode: (root, branch, isMainline) {
          if (isMainline &&
              options.initialMoveCursor != null &&
              branch.position.ply <= root.position.ply + options.initialMoveCursor!) {
            path = path + branch.id;
            lastMove = branch.sanMove.move;
          }
        },
      ),
    };

    final currentPath = switch (options) {
      Standalone() when _savedStandalone != null => _savedStandalone!.path,
      _ => options.initialMoveCursor == null ? _root.mainlinePath : path,
    };
    final currentNode = _root.nodeAt(currentPath);

    const Forecast? forecast = null;

    // don't use ref.watch here: we don't want to invalidate state when the
    // analysis preferences change
    final prefs = ref.read(analysisPreferencesProvider);

    final analysisState = AnalysisState(
      variant: _variant,
      gameId: options.gameId,
      archivedGame: archivedGame,
      currentPath: currentPath,
      clocks: _getClocks(currentPath),
      mainlineClocks: _getMainlineClocks(),
      pathToLiveMove: isGameFinished || options is Standalone || options is Pgn
          ? null
          : currentPath,
      forecast: forecast,
      isOnMainline: _root.isOnMainline(currentPath),
      root: _root.view,
      currentNode: AnalysisCurrentNode.fromNode(currentNode),
      pgnHeaders: pgnHeaders,
      pgnRootComments: rootComments,
      lastMove: lastMove,
      pov: _variant == Variant.racingKings ? Side.white : options.orientation,
      contextOpening: opening,
      isComputerAnalysisAllowed: isComputerAnalysisAllowed,
      isServerAnalysisEnabled: prefs.enableServerAnalysis,
      evaluationContext: EvaluationContext(
        id: options.contextId,
        variant: _variant,
        initialPosition: _root.position,
      ),
      playersAnalysis: playersAnalysis,
      acplChartData: playersAnalysis != null ? makeAcplChartData() : null,
      division: division,
    );

    // We need to define the state value in the build method because `requestEval` require the state
    // to have a value.
    state = AsyncData(analysisState);
    _currentPath = analysisState.currentPath;

    socketClient.firstConnection
        .timeout(const Duration(seconds: 3))
        .onError((_, _) {})
        .whenComplete(() {
          if (!ref.mounted) return;
          if (state.requireValue.isEngineAvailable(evaluationPrefs)) {
            requestEval();
          }
        });

    return analysisState;
  }

  void clearSavedStandaloneAnalysis() {
    _savedStandalone = null;
    ref.invalidateSelf();
  }

  Future<void> onFocusRegained() async {}

  void _addNewLiveMoves(Iterable<Move> moves) {
    final newLiveMovePath = _root.addMovesAt(state.requireValue.pathToLiveMove!, moves);

    _root.promoteAt(newLiveMovePath!, toMainline: true);
    _setPath(
      // If the move cursor was on the live move, follow the game and move to the new live move.
      // Otherwise, stay on the current path.
      state.requireValue.pathToLiveMove == state.requireValue.currentPath
          ? newLiveMovePath
          : state.requireValue.currentPath,
      shouldRecomputeRootView: true,
      shouldForceShowVariation: true,
    );

    state = AsyncData(
      state.requireValue.copyWith(
        forecast: moves.fold(
          state.requireValue.forecast,
          (forecast, move) => forecast!.playMove(move),
        ),
        pathToLiveMove: newLiveMovePath,
      ),
    );
  }

  void _handleSocketEvent(SocketEvent event) {
    if (!state.hasValue) {
      return;
    }

    switch (event.topic) {
      case 'fen':
        _handleFenEvent(FenSocketEvent.fromJson(event.data as Map<String, dynamic>));
    }
  }

  void _handleFenEvent(FenSocketEvent fenEvent) {
    final isNewMove =
        fenEvent.id == options.gameId &&
        state.requireValue.liveMoveNode != null &&
        // The server sends an initial FEN event on connection, ignore that here
        !state.requireValue.liveMoveNode!.position.fen.startsWith(fenEvent.fen);

    if (!isNewMove) {
      return;
    }

    _addNewLiveMoves([fenEvent.lastMove]);
  }

  @override
  void onCurrentPathEvalChanged(bool isSameEvalString) {
    _refreshCurrentNode(recomputeRootView: !isSameEvalString);
  }

  void _refreshCurrentNode({bool recomputeRootView = false}) {
    state = AsyncData(
      state.requireValue.copyWith(
        root: recomputeRootView ? _root.view : state.requireValue.root,
        currentNode: AnalysisCurrentNode.fromNode(_root.nodeAt(state.requireValue.currentPath)),
      ),
    );
  }

  void onUserMove(Move move, {bool shouldReplace = false}) {
    if (!state.requireValue.currentPosition.isLegal(move)) return;

    final (newPath, isNewNode) = _root.addMoveAt(
      state.requireValue.currentPath,
      move,
      replace: shouldReplace,
      isUserAdded: options.isLichessGameAnalysis,
    );
    if (newPath != null) {
      _setPath(newPath, shouldRecomputeRootView: isNewNode, shouldForceShowVariation: true);
    }
  }

  void userPrevious({bool fastSeek = false}) {
    _setPath(
      state.requireValue.currentPath.penultimate,
      isNavigating: true,
      keepCollapsed: fastSeek,
    );
  }

  void userNext({bool fastSeek = false}) {
    final curState = state.requireValue;
    if (!curState.currentNode.hasChild) return;
    _setPath(
      curState.currentPath + _root.nodeAt(curState.currentPath).children.first.id,
      isNavigating: true,
      keepCollapsed: fastSeek,
    );
  }

  void jumpToNthNodeOnMainline(int n) {
    UciPath path = _root.mainlinePath;
    while (!path.penultimate.isEmpty) {
      path = path.penultimate;
    }
    Node? node = _root.nodeAt(path);
    int count = 0;

    while (node != null && count < n) {
      if (node.children.isNotEmpty) {
        path = path + node.children.first.id;
        node = _root.nodeAt(path);
        count++;
      } else {
        break;
      }
    }

    if (node != null) {
      userJump(path);
    }
  }

  void toggleBoard() {
    final curState = state.requireValue;
    state = AsyncData(curState.copyWith(pov: curState.pov.opposite));
  }

  @override
  void userJump(UciPath path) {
    _setPath(path);
  }

  @override
  void expandVariations(UciPath path) {
    final node = _root.nodeAt(path);

    final childrenToShow = _root.isOnMainline(path) ? node.children.skip(1) : node.children;

    for (final child in childrenToShow) {
      child.isCollapsed = false;
      for (final grandChild in child.children) {
        grandChild.isCollapsed = false;
      }
    }
    state = AsyncData(state.requireValue.copyWith(root: _root.view));
  }

  @override
  void collapseVariations(UciPath path) {
    final node = _root.nodeAt(path);

    for (final child in node.children) {
      child.isCollapsed = true;
    }

    state = AsyncData(state.requireValue.copyWith(root: _root.view));
  }

  @override
  void promoteVariation(UciPath path, bool toMainline) {
    _root.promoteAt(path, toMainline: toMainline);
    final curState = state.requireValue;
    state = AsyncData(
      curState.copyWith(isOnMainline: _root.isOnMainline(curState.currentPath), root: _root.view),
    );
  }

  @override
  void deleteFromHere(UciPath path) {
    _root.deleteAt(path);
    _setPath(path.penultimate, shouldRecomputeRootView: true);
  }

  @override
  String makeLinePgn(UciPath path, {required bool includeVariations}) => _root.makeLinePgn(
    path,
    variant: state.requireValue.variant,
    includeVariations: includeVariations,
  );

  void updatePgnHeader(String key, String value) {
    final headers = state.requireValue.pgnHeaders.add(key, value);
    state = AsyncData(state.requireValue.copyWith(pgnHeaders: headers));
  }

  @override
  void refreshCurrentBranchOpening() {
    final curState = state.requireValue;
    state = AsyncData(
      curState.copyWith(
        currentNode: AnalysisCurrentNode.fromNode(_root.nodeAt(curState.currentPath)),
        currentBranchOpening: currentBranchOpeningAt(curState.currentPath),
      ),
    );
  }

  /// Makes a full PGN string (including headers and comments) of the current game state.
  String makeExportPgn() {
    final curState = state.requireValue;
    return _root.makePgn(curState.pgnHeaders, curState.pgnRootComments);
  }

  Future<void> toggleBookmark() async {
    if (state.hasValue) {
      final game = state.requireValue.archivedGame;
      if (game == null) return;
      final toggledBookmark = !(game.data.bookmarked ?? false);
      await ref.read(accountServiceProvider).setGameBookmark(game.id, bookmark: toggledBookmark);
      if (!ref.mounted) return;
      state = AsyncValue.data(
        state.requireValue.copyWith(
          archivedGame: state.requireValue.archivedGame?.copyWith(
            data: game.data.copyWith(bookmarked: toggledBookmark),
          ),
        ),
      );
    }
  }

  void _setPath(
    UciPath path, {
    bool shouldForceShowVariation = false,
    bool shouldRecomputeRootView = false,

    /// Whether the user is navigating through the moves (as opposed to playing a move).
    bool isNavigating = false,
    bool keepCollapsed = false,
  }) {
    _currentPath = path;
    final curState = state.requireValue;
    final pathChange = curState.currentPath != path;
    final (currentNode, opening) = nodeOpeningAt(_root, path);

    bool pathWasExpanded = false;
    if (pathChange && !keepCollapsed) {
      for (final child in currentNode.children) {
        if (child.isCollapsed) {
          child.isCollapsed = false;
          pathWasExpanded = true;
        }
      }
    }

    // always show variation if the user plays a move
    if (shouldForceShowVariation && currentNode is Branch && currentNode.isCollapsed) {
      _root.updateAt(path, (node) {
        if (node is Branch) node.isCollapsed = false;
      });
    }

    // root view is only used to display move list, so we need to
    // recompute the root view only when the nodelist length changes
    // or a variation is hidden/shown
    final rootView = shouldForceShowVariation || shouldRecomputeRootView || pathWasExpanded
        ? _root.view
        : curState.root;

    final isForward = path.size > curState.currentPath.size;
    if (currentNode is Branch) {
      // normal move feedback
      if (!isNavigating && isForward) {
        final isCheck = currentNode.sanMove.isCheck;
        if (currentNode.sanMove.isCapture) {
          ref.read(moveFeedbackServiceProvider).captureFeedback(curState.variant, check: isCheck);
        } else {
          ref.read(moveFeedbackServiceProvider).moveFeedback(check: isCheck);
        }
      }
      // if navigating, only sound feedback
      else {
        final soundService = ref.read(soundServiceProvider);
        if (currentNode.sanMove.isCapture) {
          soundService.playCaptureSound(curState.variant);
        } else {
          soundService.play(Sound.move);
        }
      }

      maybeFetchOpeningAt(currentNode, path);

      state = AsyncData(
        curState.copyWith(
          currentPath: path,
          clocks: _getClocks(path),
          isOnMainline: _root.isOnMainline(path),
          currentNode: AnalysisCurrentNode.fromNode(currentNode),
          currentBranchOpening: opening,
          lastMove: currentNode.sanMove.move,
          root: rootView,
        ),
      );
    } else {
      state = AsyncData(
        curState.copyWith(
          currentPath: path,
          clocks: _getClocks(path),
          isOnMainline: _root.isOnMainline(path),
          currentNode: AnalysisCurrentNode.fromNode(currentNode),
          currentBranchOpening: opening,
          lastMove: null,
          root: rootView,
        ),
      );
    }

    if (pathChange) {
      state = AsyncData(state.requireValue.copyWith(engineInThreatMode: false));
      requestEval();
    }
  }

  /// The clock left after each mainline move, null unless every one of them carries a reading.
  IList<Duration>? _getMainlineClocks() {
    final clocks = _root.mainline.map((branch) => branch.clock).toIList();
    return clocks.isEmpty || clocks.any((clock) => clock == null)
        ? null
        : clocks.map((clock) => clock!).toIList();
  }

  /// The clocks to show either side of the board at [path].
  ///
  /// The node holds the clock of the side that has just moved, so the side to move is shown the
  /// clock of its parent — the last reading it had.
  ({Duration? parentClock, Duration? clock}) _getClocks(UciPath path) {
    final node = _root.nodeAt(path);
    final parent = _root.parentAt(path);

    return (
      parentClock: (parent is Branch) ? parent.clock : null,
      clock: (node is Branch) ? node.clock : null,
    );
  }

  @override
  Future<void> requestServerAnalysis([Side? side]) async {
    super.requestServerAnalysis(side ?? options.orientation);
  }

  @override
  Future<void> onServerAnalysisEvent(ServerEvalEvent event) async {
    state = AsyncData(
      state.requireValue.copyWith(
        acplChartData: makeAcplChartData(),
        playersAnalysis: event.analysis != null
            ? (white: event.analysis!.white, black: event.analysis!.black)
            : null,
        root: _root.view,
      ),
    );
  }
}

@freezed
sealed class AnalysisState
    with
        _$AnalysisState,
        AnalysisExplosionMixin,
        EvaluationMixinState<AnalysisState>,
        ServerAnalysisMixinState,
        OpeningExplorerMixinState
    implements CommonAnalysisState {
  const AnalysisState._();

  @override
  ViewRoot get analysisRoot => root;

  @override
  AnalysisState withThreatMode(bool engineInThreatMode) =>
      copyWith(engineInThreatMode: engineInThreatMode);

  const factory AnalysisState({
    /// The ID of the game if it's a lichess game.
    required GameId? gameId,

    /// The archived game if it's a finished lichess game.
    ExportedGame? archivedGame,

    /// The variant of the analysis.
    required Variant variant,

    /// Immutable view of the whole tree
    required ViewRoot root,

    /// The current node in the analysis view.
    ///
    /// This is an immutable copy of the actual [Node] at the `currentPath`.
    /// We don't want to use [Node.view] here because it'd copy the whole tree
    /// under the current node and it's expensive.
    required AnalysisCurrentNode currentNode,

    /// The path to the current node in the analysis view.
    required UciPath currentPath,

    /// The clocks at the current node, if the analysed game carries any.
    required ({Duration? parentClock, Duration? clock})? clocks,

    /// The clock left after each mainline move, if every one of them carries a reading.
    ///
    /// Read off the tree once, when the analysis is loaded, so moves added since are not part of
    /// it — the same way [archivedGame] holds the game as it was played.
    IList<Duration>? mainlineClocks,

    /// If this is a correspondence game, the path to the last move that has been played.
    required UciPath? pathToLiveMove,

    /// If this is a correspondence game, stores the current set of conditional premoves.
    required Forecast? forecast,

    /// Whether the current path is on the mainline.
    required bool isOnMainline,

    /// The side to display the board from.
    required Side pov,

    /// Whether computer evaluation is allowed for this analysis.
    ///
    /// Acts on both local and server analysis.
    required bool isComputerAnalysisAllowed,

    /// Whether the user has enabled server analysis.
    required bool isServerAnalysisEnabled,

    /// The context that the local engine is initialized with.
    required EvaluationContext evaluationContext,

    /// The last move played.
    Move? lastMove,

    /// Opening of the analysis context (from lichess archived games).
    Opening? contextOpening,

    /// The opening of the current branch.
    Opening? currentBranchOpening,

    /// Optional server analysis to display player stats.
    PlayersAnalysis? playersAnalysis,

    /// Optional game division data, given by the server for finished games (even without server analysis)
    Division? division,

    /// Optional ACPL chart data of the game, coming from lichess server analysis.
    IList<ExternalEval>? acplChartData,

    /// The PGN headers of the game.
    required IMap<String, String> pgnHeaders,

    /// The PGN comments of the game.
    ///
    /// This field is only used with user submitted PGNS.
    IList<PgnComment>? pgnRootComments,

    @Default(false) bool engineInThreatMode,
  }) = _AnalysisState;

  @override
  bool get alwaysRequestCloudEval => false;

  /// The clock left after each mainline move, empty if the game was played without one.
  ///
  /// A lichess game is authoritative about its own clocks; anything else is read off the tree.
  IList<Duration> get chartClocks =>
      archivedGame?.clocks ?? mainlineClocks ?? const IListConst<Duration>([]);

  /// The time spent on each mainline move, empty if the game was played without a clock.
  IList<Duration> get chartMoveTimes =>
      archivedGame?.moveTimes ?? moveTimesFromClocks(mainlineClocks, _pgnClockIncrement);

  /// The increment of a game analysed from a PGN, read off its `TimeControl` header.
  Duration get _pgnClockIncrement {
    final timeControl = pgnHeaders['TimeControl'];
    final increment = timeControl != null && timeControl.contains('+')
        ? int.tryParse(timeControl.split('+').last)
        : null;
    return Duration(seconds: increment ?? 0);
  }

  /// Whether the analysis is for a lichess game.
  bool get isLichessGameAnalysis => gameId != null;

  /// Non-null if server analysis is allowed for this analysis.
  ///
  /// It must be a finished lichess game or an imported game.
  @override
  ServerAnalysisSource? get serverAnalysisSource =>
      gameId != null && (pgnHeaders['Result'] != '*' || archivedGame?.source == .import)
      ? ServerAnalysisSource.game(gameId: gameId!)
      : null;

  /// Whether the user can request server analysis and has not yet done so.
  bool get canRequestServerAnalysis => serverAnalysisSource != null && !hasServerAnalysis;

  /// Whether the server analysis is available.
  bool get hasServerAnalysis => playersAnalysis != null;

  /// Whether an evaluation can be available
  bool hasAvailableEval(EngineEvaluationPrefState prefs) =>
      isEngineAvailable(prefs) ||
      (isComputerAnalysisAllowed && isServerAnalysisEnabled && hasServerAnalysis);

  /// Whether the engine is allowed for this analysis.
  bool get isEngineAllowed => isComputerAnalysisAllowed;

  ViewNode? get liveMoveNode => pathToLiveMove != null
      ? pathToLiveMove!.isEmpty
            ? root
            : root.branchesOn(pathToLiveMove!).last
      : null;

  bool get branchedOffFromLiveMove =>
      forecast != null &&
      pathToLiveMove != null &&
      currentPath != pathToLiveMove &&
      currentPath.contains(pathToLiveMove!);

  /// If the current node branches off from the live move and is not yet saved as a premove,
  /// the part of [AnalysisState.currentPath] that would be saved as a premove line. null otherwise.
  UciPath? get currentPremoveCandidate {
    if (!branchedOffFromLiveMove) {
      return null;
    }

    final candidate = currentPath.stripPrefix(pathToLiveMove!);
    return forecast!.isCandidate(candidate) ? candidate : null;
  }

  IList<PgnCommentShape> get pgnShapes => IList(
    (currentNode.isRoot ? pgnRootComments : currentNode.comments)
        ?.map((comment) => comment.shapes)
        .flattened,
  );

  /// If it's our turn and we have branched off from the main line, this is the move we would play
  /// if we to save the entire current path as a premove line.
  SanMove? get pendingMove => forecast?.onMyTurn == true && branchedOffFromLiveMove
      ? liveMoveNode!.childById(currentPath.stripPrefix(pathToLiveMove!).head!)?.sanMove
      : null;

  @override
  bool isEngineAvailable(EngineEvaluationPrefState prefs) => isLocalEngineOffered(
    allowed: isEngineAllowed,
    enabled: prefs.isEnabled,
    supported: isNativeEngineSupported,
  );

  @override
  Position get currentPosition => currentNode.position;

  bool get canGoNext => currentNode.hasChild;
  bool get canGoBack => currentPath.size > UciPath.empty.size;

  EngineGaugeParams engineGaugeParams(EngineEvaluationPrefState prefs) => (
    isLocalEngineAvailable: isEngineAvailable(prefs),
    orientation: pov,
    position: currentPosition,
    savedEval: currentNode.eval,
    serverEval: currentNode.serverEval,
    filters: (context: evaluationContext, path: currentPath),
  );
}

@freezed
sealed class AnalysisCurrentNode
    with _$AnalysisCurrentNode
    implements AnalysisCurrentNodeInterface {
  const AnalysisCurrentNode._();

  const factory AnalysisCurrentNode({
    required Position position,
    required bool hasChild,
    required bool isRoot,
    SanMove? sanMove,
    Opening? opening,
    ClientEval? eval,
    IList<PgnComment>? lichessAnalysisComments,
    IList<PgnComment>? startingComments,
    IList<PgnComment>? comments,
    IList<int>? nags,
  }) = _AnalysisCurrentNode;

  factory AnalysisCurrentNode.fromNode(Node node) {
    if (node is Branch) {
      return AnalysisCurrentNode(
        sanMove: node.sanMove,
        position: node.position,
        isRoot: false,
        hasChild: node.children.isNotEmpty,
        opening: node.opening,
        eval: node.eval,
        lichessAnalysisComments: IList(node.lichessAnalysisComments),
        startingComments: IList(node.startingComments),
        comments: IList(node.comments),
        nags: IList(node.nags),
      );
    } else {
      return AnalysisCurrentNode(
        position: node.position,
        hasChild: node.children.isNotEmpty,
        isRoot: node is Root,
        opening: node.opening,
        eval: node.eval,
      );
    }
  }

  /// The evaluation from the PGN comments.
  ///
  /// For now we only trust the eval coming from lichess analysis.
  ExternalEval? get serverEval {
    final pgnEval = lichessAnalysisComments?.firstWhereOrNull((c) => c.eval != null)?.eval;
    return pgnEval != null
        ? ExternalEval(
            cp: pgnEval.pawns != null ? cpFromPawns(pgnEval.pawns!) : null,
            mate: pgnEval.mate,
            depth: pgnEval.depth,
          )
        : null;
  }
}
