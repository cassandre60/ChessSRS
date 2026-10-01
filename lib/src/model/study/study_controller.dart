import 'dart:async';

import 'package:chess_srs/src/model/analysis/analysis_summary.dart';
import 'package:chess_srs/src/model/analysis/common_analysis_state.dart';
import 'package:chess_srs/src/model/analysis/opening_explorer_mixin.dart';
import 'package:chess_srs/src/model/analysis/server_analysis_mixin.dart';
import 'package:chess_srs/src/model/analysis/server_analysis_service.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/chat/chat_mixin.dart';
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
import 'package:chess_srs/src/model/game/game_socket_events.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/study/study_repository.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:chess_srs/src/utils/rate_limit.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:chess_srs/src/widgets/pgn.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'study_controller.freezed.dart';

typedef StudyOptions = ({StudyId id, StudyChapterId? initialChapter});

final studyControllerProvider = AsyncNotifierProvider.autoDispose
    .family<StudyController, StudyState, StudyOptions>(
      StudyController.new,
      name: 'StudyControllerProvider',
    );

enum ChapterServerAnalysisStatus { canRequest, notEnoughMoves, notWriteable, available }

class StudyController extends AsyncNotifier<StudyState>
    with
        EngineEvaluationMixin,
        ServerAnalysisMixin,
        ChatMixin<StudyState>,
        OpeningExplorerMixin<StudyState>
    implements PgnTreeNotifier {
  StudyController(this.options);

  final StudyOptions options;

  late Root _root;

  Timer? _opponentFirstMoveTimer;

  /// Gamebook chapters advance themselves after a move when they carry no comment saying why
  /// the move was right or wrong. Kept so a chapter change can call it off.
  Timer? _gamebookNavTimer;

  /// Bumped on every chapter request. A load whose generation is stale has been superseded.
  int _chapterGeneration = 0;
  StreamSubscription<SocketEvent>? _socketSubscription;
  final _likeDebouncer = Debouncer(const Duration(milliseconds: 500));

  SocketClient? _socketClient;

  @override
  @protected
  SocketClient? get socketClient => _socketClient;

  @override
  @protected
  Root get positionTree => _root;

  // Studies with an illegal starting position do not build a position tree, so
  // there is nothing to fetch openings for in that case.
  @override
  bool get canFetchMainlineOpenings => state.value?.root != null;

  @override
  @protected
  StringId get chatId => options.id;

  @override
  @protected
  String get chatReportResource => 'study/${options.id}';

  @override
  @protected
  bool get chatIsPublic => true;

  @override
  Future<StudyState> build() async {
    ref.onDispose(() {
      _opponentFirstMoveTimer?.cancel();
      _gamebookNavTimer?.cancel();
      _socketSubscription?.cancel();
      _likeDebouncer.cancel();
    });
    final socketPool = ref.watch(socketPoolProvider);
    final (study, analysisSummary, pgn) = await ref
        .read(studyRepositoryProvider)
        .getStudy(id: options.id, chapterId: options.initialChapter);

    if (study.socketVersion != null) {
      _socketClient = socketPool.open(
        Uri(path: '/study/${options.id}/socket/v6'),
        version: study.socketVersion,
      );
      _socketSubscription?.cancel();
      _socketSubscription = _socketClient?.stream.listen(handleSocketEvent);
    }

    final chapter = await _loadChapter(
      study,
      pgn,
      analysisSummary: analysisSummary,
      chapterId: options.initialChapter,
    );

    return chapter.copyWith(chatState: await initChat(chapter.study.chat));
  }

  @override
  void onCurrentPathEvalChanged(bool isSameEvalString) {
    _refreshCurrentNode(recomputeRootView: !isSameEvalString);
  }

  void _refreshCurrentNode({bool recomputeRootView = false}) {
    state = AsyncData(
      state.requireValue.copyWith(
        root: recomputeRootView ? _root.view : state.requireValue.root,
        currentNode: StudyCurrentNode.fromNode(_root.nodeAt(state.requireValue.currentPath)),
      ),
    );
  }

  @override
  void refreshCurrentBranchOpening() {
    final curState = state.requireValue;
    state = AsyncData(
      curState.copyWith(
        currentNode: StudyCurrentNode.fromNode(_root.nodeAt(curState.currentPath)),
        currentBranchOpening: currentBranchOpeningAt(curState.currentPath),
      ),
    );
  }

  Future<void> nextChapter() async {
    if (state.hasValue) {
      final chapters = state.requireValue.study.chapters;
      final currentChapterIndex = chapters.indexWhere(
        (chapter) => chapter.id == state.requireValue.study.chapter.id,
      );
      // There is no chapter after the last one, and a chapter that is not in the list at all
      // has no meaningful neighbour. Reading one past the end threw a RangeError, and an
      // index of -1 silently jumped to the first chapter instead.
      if (currentChapterIndex < 0 || currentChapterIndex + 1 >= chapters.length) return;
      await goToChapter(chapters[currentChapterIndex + 1].id);
    }
  }

  Future<void> goToChapter(StudyChapterId chapterId) async {
    // Whatever was going to happen to the board next was for the chapter being left behind.
    _opponentFirstMoveTimer?.cancel();
    _gamebookNavTimer?.cancel();

    final generation = ++_chapterGeneration;
    final (study, analysisSummary, pgn) = await ref
        .read(studyRepositoryProvider)
        .getStudy(id: options.id, chapterId: chapterId);

    // A request the user has moved past must not load. Two chapters tapped in quick succession
    // resolve in whatever order the repository happens to answer, and the slower one was
    // putting the chapter they had already left back on screen.
    if (generation != _chapterGeneration) return;

    final chapter = await _loadChapter(
      study,
      pgn,
      chapterId: chapterId,
      analysisSummary: analysisSummary,
    );

    // _loadChapter returns the new state rather than assigning it — `build` publishes what it
    // gets back, and this path used to discard it. With nothing published, state.study.chapter
    // stayed on the chapter the study opened on for the rest of the session: `nextChapter`
    // resolved the same neighbour every time it was pressed, and the chapter's own orientation,
    // gamebook flag and feature set never took effect.
    state = AsyncData(chapter.copyWith(chatState: state.requireValue.chatState));

    // Switching chapters does not re-run [runBuild], so fetch the new mainline's
    // openings explicitly here.
    initMainlineOpenings();
    _ensureItsOurTurnIfGamebook();
  }

  Future<StudyState> _loadChapter(
    Study study,
    String pgn, {
    AnalysisSummary? analysisSummary,
    StudyChapterId? chapterId,
  }) async {
    final game = PgnGame.parsePgn(pgn);

    final pgnHeaders = IMap(game.headers);
    final rootComments = IList(game.comments.map((c) => PgnComment.fromPgn(c)));

    final variant = study.chapter.setup.variant;
    final orientation = study.chapter.setup.orientation;

    final UserId? me = ref.read(authControllerProvider)?.user.id;

    // Some studies have illegal starting positions. This is usually the case for introductory chapters.
    // We do not treat this as an error, but display a static board instead.
    try {
      _root = Root.fromPgnGame(game);
    } on PositionSetupException {
      final illegalPositionState = StudyState(
        myId: me,
        variant: variant,
        study: study,
        currentPath: UciPath.empty,
        clocks: null,
        isOnMainline: true,
        root: null,
        currentNode: StudyCurrentNode.illegalPosition(),
        // EvaluationContext needs an initial posiiton, but it doesn't matter what we pass here,
        // since the position is illegal and `isComputerAnalysisAllowed` is false anyway.
        evaluationContext: EvaluationContext(
          id: study.chapter.id,
          variant: variant,
          initialPosition: Variant.standard.initialPosition,
        ),
        pgnRootComments: rootComments,
        pgnHeaders: pgnHeaders,
        pov: orientation,
        isComputerAnalysisAllowed: false,
        gamebookActive: false,
        pgn: pgn,
      );
      state = AsyncData(illegalPositionState);
      return illegalPositionState;
    }

    // If server analysis has already been requested for this chapter,
    // assume that any comment that has an eval is actually a lichess analysis comment.
    // (Note that regular comments by the study author might also exist.)
    if (analysisSummary != null) {
      for (final node in _root.mainline) {
        final lichessCommentIndex = (node.comments ?? []).indexWhere((c) => c.eval != null);
        if (lichessCommentIndex != -1) {
          node.lichessAnalysisComments = [node.comments![lichessCommentIndex]];
          node.comments!.removeAt(lichessCommentIndex);
        }
      }
    }

    const currentPath = UciPath.empty;
    Move? lastMove;

    final studyState = StudyState(
      myId: me,
      variant: variant,
      study: study,
      currentPath: currentPath,
      clocks: _getClocks(currentPath),
      isOnMainline: true,
      root: _root.view,
      currentNode: StudyCurrentNode.fromNode(_root),
      currentBranchOpening: currentBranchOpeningAt(currentPath),
      evaluationContext: EvaluationContext(
        id: study.chapter.id,
        variant: variant,
        initialPosition: _root.position,
      ),
      pgnRootComments: rootComments,
      pgnHeaders: pgnHeaders,
      lastMove: lastMove,
      pov: orientation,
      isComputerAnalysisAllowed: study.chapter.features.computer && !study.chapter.gamebook,
      gamebookActive: study.chapter.gamebook,
      pgn: pgn,
      analysisSummary: analysisSummary,
      acplChartData: analysisSummary != null ? makeAcplChartData() : null,
    );

    // We need to define the state value in the build method because `requestEval` require the state
    // to have a value.
    state = AsyncData(studyState);

    if (state.requireValue.isEngineAvailable(evaluationPrefs)) {
      socketClient?.firstConnection.then((_) {
        if (!ref.mounted) return;
        requestEval();
      });
    }

    return studyState;
  }

  void toggleLike() {
    _likeDebouncer(() {
      if (!state.hasValue) return;
      final liked = state.requireValue.study.liked;
      _socketClient?.send('like', {'liked': !liked});
      state = AsyncValue.data(
        state.requireValue.copyWith(study: state.requireValue.study.copyWith(liked: !liked)),
      );
    });
  }

  @protected
  @override
  void updateChatState(ChatState newState) {
    state = AsyncValue.data(state.requireValue.copyWith(chatState: newState));
  }

  @protected
  @override
  void handleSocketEvent(SocketEvent event) {
    super.handleSocketEvent(event);

    if (!state.hasValue) {
      assert(false, 'received a study SocketEvent while StudyState is null');
      return;
    }

    if (event.topic == 'liking') {
      _applyLiking(event);
      return;
    }

    if (!_isRemoteEditForCurrentChapter(event)) return;

    switch (event.topic) {
      case 'promote':
        final data = _editPayload(event);
        if (data == null) return;
        final toMainline = data['toMainline'];
        final path = data['path'];
        if (toMainline is! bool || path is! String) return;
        // `promoteAt` only reorders a variation that is not already first, so a replayed event
        // changes nothing the second time.
        _root.promoteAt(UciPath(path), toMainline: toMainline);
        _refreshTreeView();

      case 'deleteNode':
        final data = _editPayload(event);
        if (data == null) return;
        final path = data['path'];
        final jumpTo = data['jumpTo'];
        if (path is! String || jumpTo is! String) return;
        final deleted = UciPath(path);
        // Already gone: a replayed delete must not take the view with it.
        if (_root.nodeAtOrNull(deleted) == null) return;
        _root.deleteAt(deleted);
        // The view is only moved when the deletion took the node being looked at out from under
        // it. A deletion elsewhere in the tree is a background change.
        final current = state.requireValue.currentPath;
        if (current == deleted || deleted.contains(current)) {
          _setPath(UciPath(jumpTo), shouldRecomputeRootView: true);
        } else {
          _refreshTreeView();
        }

      case 'anaMove':
        final data = _editPayload(event);
        if (data == null) return;
        final orig = data['orig'];
        final dest = data['dest'];
        final path = data['path'];
        if (orig is! String || dest is! String || path is! String) return;
        final move = NormalMove(from: Square.fromName(orig), to: Square.fromName(dest));
        // `addMoveAt` does not add a node that is already there, so a replayed move is a no-op.
        final (_, added) = _root.addMoveAt(UciPath(path), move);
        if (added) _refreshTreeView();

      case 'anaDrop':
        final data = _editPayload(event);
        if (data == null) return;
        final roleName = data['role'];
        final pos = data['pos'];
        final path = data['path'];
        if (roleName is! String || pos is! String || path is! String) return;
        final role = Role.fromChar(roleName);
        // A role the build does not know is a variant this client cannot represent; applying a
        // guessed one would corrupt the tree.
        if (role == null) return;
        final (_, added) = _root.addMoveAt(
          UciPath(path),
          DropMove(role: role, to: Square.fromName(pos)),
        );
        if (added) _refreshTreeView();
    }
  }

  /// Whether [event] is a collaboration edit addressed to the chapter on screen.
  ///
  /// Every outgoing edit carries the chapter id (see `_recordChange`), and this controller holds
  /// the tree of exactly one chapter. An edit for another chapter belongs to a tree that is not
  /// loaded here, so applying it would graft a stranger's move onto the position on screen.
  ///
  /// Ordering is deliberately not re-checked. The study socket is opened with a version, and
  /// `SocketClient` discards an event it has already applied and refuses a stream that has a hole
  /// in it, so an event that reaches this point is already the next one in order.
  bool _isRemoteEditForCurrentChapter(SocketEvent event) {
    const editTopics = {'promote', 'deleteNode', 'anaMove', 'anaDrop'};
    if (!editTopics.contains(event.topic)) return false;
    final payload = _editPayload(event);
    if (payload == null) return false;
    return payload['ch'] == state.requireValue.currentChapter.id.value;
  }

  /// The event body as a map, or null when it is not one.
  ///
  /// A frame that is not a JSON object is dropped rather than cast: the subscription is opened
  /// with `cancelOnError`, so a throw here would silently take the study's socket down with it.
  Map<String, dynamic>? _editPayload(SocketEvent event) {
    final data = event.data;
    return data is Map<String, dynamic> ? data : null;
  }

  void _applyLiking(SocketEvent event) {
    final outer = _editPayload(event);
    final likes = outer?['l'];
    if (likes is! Map) return;
    final count = likes['likes'];
    final me = likes['me'];
    if (count is! int || me is! bool) return;
    state = AsyncValue.data(
      state.requireValue.copyWith(
        study: state.requireValue.study.copyWith(liked: me, likes: count),
      ),
    );
  }

  /// Rebuilds the view after the tree changed underneath it, without moving the reader.
  ///
  /// Someone else making a move is a background event. Only a deletion that removes the node
  /// being looked at moves the view, and that is handled where it happens.
  void _refreshTreeView() {
    if (!state.hasValue) return;
    final current = state.requireValue;
    state = AsyncValue.data(
      current.copyWith(
        root: _root.view,
        currentNode: StudyCurrentNode.fromNode(_root.nodeAt(current.currentPath)),
        isOnMainline: _root.isOnMainline(current.currentPath),
      ),
    );
  }

  // The PGNs of some gamebook studies start with the opponent's turn, so trigger their move after a delay
  void _ensureItsOurTurnIfGamebook() {
    _opponentFirstMoveTimer?.cancel();
    if (state.requireValue.isAtStartOfChapter &&
        state.requireValue.gamebookActive &&
        state.requireValue.gamebookComment == null &&
        state.requireValue.currentPosition != null &&
        state.requireValue.currentPosition!.turn != state.requireValue.pov) {
      final chapter = state.requireValue.study.chapter.id;
      _opponentFirstMoveTimer = Timer(const Duration(milliseconds: 750), () {
        // Fenced to the chapter that scheduled it. A chapter change cancels this timer, but the
        // change can land in the gap before the cancel, and playing the move then would advance
        // a chapter this was never asked about.
        if (!state.hasValue || state.requireValue.study.chapter.id != chapter) return;
        userNext();
      });
    }
  }

  void onUserMove(Move move) {
    if (!state.hasValue || state.requireValue.currentPosition == null) return;

    if (!state.requireValue.currentPosition!.isLegal(move)) return;

    _sendMoveToSocket(move);

    final (newPath, isNewNode) = _root.addMoveAt(state.requireValue.currentPath, move);
    if (newPath != null) {
      _setPath(newPath, shouldRecomputeRootView: isNewNode, shouldForceShowVariation: true);
    }

    if (state.requireValue.gamebookActive) {
      final comment = state.requireValue.gamebookComment;
      // If there's no explicit comment why the move was good/bad, trigger next/previous move automatically
      if (comment == null) {
        // Stored, and fenced to the chapter it was started in. Held only by the event loop, this
        // fired 750ms later against whatever was on screen by then, stepping through a chapter
        // it was never scheduled for.
        _gamebookNavTimer?.cancel();
        final chapter = state.requireValue.study.chapter.id;
        _gamebookNavTimer = Timer(const Duration(milliseconds: 750), () {
          if (!state.hasValue || state.requireValue.study.chapter.id != chapter) return;
          if (state.requireValue.isOnMainline) {
            userNext();
          } else {
            userPrevious();
          }
        });
      }
    }
  }

  void showGamebookSolution() {
    onUserMove(state.requireValue.currentNode.children.first);
  }

  void userPrevious({bool fastSeek = false}) {
    if (state.hasValue) {
      _setPath(
        state.requireValue.currentPath.penultimate,
        isNavigating: true,
        keepCollapsed: fastSeek,
      );
    }
  }

  void userNext({bool fastSeek = false}) {
    final state = this.state.value;
    if (state!.currentNode.children.isEmpty) return;
    _setPath(
      state.currentPath + _root.nodeAt(state.currentPath).children.first.id,
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
    final state = this.state.value;
    if (state != null) {
      this.state = AsyncValue.data(state.copyWith(pov: state.pov.opposite));
    }
  }

  void reset() {
    if (state.hasValue) {
      _setPath(UciPath.empty);
      _ensureItsOurTurnIfGamebook();
    }
  }

  @override
  void userJump(UciPath path) {
    _setPath(path);
  }

  @override
  void expandVariations(UciPath path) {
    if (!state.hasValue) return;

    final node = _root.nodeAt(path);

    final childrenToShow = _root.isOnMainline(path) ? node.children.skip(1) : node.children;

    for (final child in childrenToShow) {
      child.isCollapsed = false;
      for (final grandChild in child.children) {
        grandChild.isCollapsed = false;
      }
    }
    state = AsyncValue.data(state.requireValue.copyWith(root: _root.view));
  }

  @override
  void collapseVariations(UciPath path) {
    if (!state.hasValue) return;

    final node = _root.nodeAt(path);

    for (final child in node.children) {
      child.isCollapsed = true;
    }

    state = AsyncValue.data(state.requireValue.copyWith(root: _root.view));
  }

  @override
  void promoteVariation(UciPath path, bool toMainline) {
    final state = this.state.value;
    if (state == null) return;
    _root.promoteAt(path, toMainline: toMainline);
    this.state = AsyncValue.data(
      state.copyWith(isOnMainline: _root.isOnMainline(state.currentPath), root: _root.view),
    );

    _recordChange('promote', {
      'toMainline': toMainline,
      'path': path.value,
      'ch': state.currentChapter.id.value,
    });
  }

  @override
  void deleteFromHere(UciPath path) {
    if (!state.hasValue) return;

    _root.deleteAt(path);
    _recordChange('deleteNode', {'path': path.value, 'jumpTo': path.penultimate.value});
    _setPath(path.penultimate, shouldRecomputeRootView: true);
  }

  @override
  String makeLinePgn(UciPath path, {required bool includeVariations}) => _root.makeLinePgn(
    path,
    variant: state.requireValue.variant,
    includeVariations: includeVariations,
  );

  void _sendMoveToSocket(Move move) {
    if (state.requireValue.isWriteable == false) return;

    switch (move) {
      case NormalMove():
        _recordChange('anaMove', {
          'orig': move.from.name,
          'dest': move.to.name,
          'path': state.requireValue.currentPath.value,
        });
      case DropMove():
        _recordChange('anaDrop', {
          'role': move.role.name,
          'pos': move.to.name,
          'path': state.requireValue.currentPath.value,
        });
    }
  }

  void _recordChange(String socketEvent, Map<String, dynamic> data) {
    if (!state.hasValue) return;
    if (state.requireValue.isWriteable == false) return;

    _socketClient?.send(socketEvent, {...data, 'ch': state.requireValue.study.chapter.id.value});
  }

  void _setPath(
    UciPath path, {
    bool shouldForceShowVariation = false,
    bool shouldRecomputeRootView = false,

    /// Whether the user is navigating through the moves (as opposed to playing a move).
    bool isNavigating = false,
    bool keepCollapsed = false,
  }) {
    final state = this.state.value;
    if (state == null) return;

    final pathChange = state.currentPath != path;
    final (currentNode, branchOpening) = nodeOpeningAt(_root, path);

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
        : state.root;

    final isForward = path.size > state.currentPath.size;
    if (currentNode is Branch) {
      // normal move feedback
      if (!isNavigating && isForward) {
        final isCheck = currentNode.sanMove.isCheck;
        if (currentNode.sanMove.isCapture) {
          ref.read(moveFeedbackServiceProvider).captureFeedback(state.variant, check: isCheck);
        } else {
          ref.read(moveFeedbackServiceProvider).moveFeedback(check: isCheck);
        }
      }
      // if navigating, only sound feedback
      else {
        final soundService = ref.read(soundServiceProvider);
        if (currentNode.sanMove.isCapture) {
          soundService.play(Sound.capture);
        } else {
          soundService.play(Sound.move);
        }
      }

      maybeFetchOpeningAt(currentNode, path);

      this.state = AsyncValue.data(
        state.copyWith(
          currentPath: path,
          clocks: _getClocks(path),
          isOnMainline: _root.isOnMainline(path),
          currentNode: StudyCurrentNode.fromNode(currentNode),
          currentBranchOpening: branchOpening,
          lastMove: currentNode.sanMove.move,
          root: rootView,
        ),
      );
    } else {
      this.state = AsyncValue.data(
        state.copyWith(
          currentPath: path,
          clocks: _getClocks(path),
          isOnMainline: _root.isOnMainline(path),
          currentNode: StudyCurrentNode.fromNode(currentNode),
          currentBranchOpening: branchOpening,
          lastMove: null,
          root: rootView,
        ),
      );
    }

    if (pathChange) {
      this.state = AsyncData(this.state.requireValue.copyWith(engineInThreatMode: false));
      requestEval();
    }
  }

  @override
  Future<void> onServerAnalysisEvent(ServerEvalEvent event) async {
    state = AsyncData(
      state.requireValue.copyWith(
        acplChartData: makeAcplChartData(),
        analysisSummary: event.analysis != null
            ? (
                division: event.division != null
                    ? Division(middlegame: event.division!.middle, endgame: event.division!.end)
                    : state.requireValue.analysisSummary?.division,
                white: event.analysis!.white,
                black: event.analysis!.black,
              )
            : null,
        root: _root.view,
      ),
    );
  }

  ({Duration? parentClock, Duration? clock}) _getClocks(UciPath path) {
    final node = _root.nodeAt(path);
    final parent = _root.parentAt(path);

    return (
      parentClock: (parent is Branch) ? parent.clock : null,
      clock: (node is Branch) ? node.clock : null,
    );
  }
}

enum GamebookState { startLesson, findTheMove, correctMove, incorrectMove, lessonComplete }

@freezed
sealed class StudyState
    with
        _$StudyState,
        AnalysisExplosionMixin,
        EvaluationMixinState<StudyState>,
        ChatMixinState,
        ServerAnalysisMixinState,
        OpeningExplorerMixinState
    implements CommonAnalysisState {
  const StudyState._();

  @override
  ViewRoot? get analysisRoot => root;

  @override
  StudyState withThreatMode(bool engineInThreatMode) =>
      copyWith(engineInThreatMode: engineInThreatMode);

  const factory StudyState({
    UserId? myId,
    bool? isAdmin,
    required Study study,
    required String pgn,

    /// The variant of the current chapter
    required Variant variant,

    /// Immutable view of the whole tree. Null if the chapter's starting position is illegal.
    required ViewRoot? root,

    /// The current node in the study tree view.
    ///
    /// This is an immutable copy of the actual [Node] at the `currentPath`.
    /// We don't want to use [Node.view] here because it'd copy the whole tree
    /// under the current node and it's expensive.
    required StudyCurrentNode currentNode,

    /// The path to the current node in the analysis view.
    required UciPath currentPath,

    /// Whether the current path is on the mainline.
    required bool isOnMainline,

    /// The context that the local engine is initialized with.
    required EvaluationContext evaluationContext,

    /// The side to display the board from.
    required Side pov,

    /// Whether local evaluation is allowed for this study.
    required bool isComputerAnalysisAllowed,

    /// Clocks if available.
    required ({Duration? parentClock, Duration? clock})? clocks,

    /// Whether we're currently in gamebook mode, where the user has to find the right moves.
    required bool gamebookActive,

    /// The PGN headers of the study chapter.
    required IMap<String, String> pgnHeaders,

    /// The last move played.
    Move? lastMove,

    /// The opening of the current branch, if any.
    Opening? currentBranchOpening,

    /// The PGN root comments of the study
    IList<PgnComment>? pgnRootComments,

    @Default(false) bool engineInThreatMode,

    /// Server analysis summary if a server analysis has been triggered on this chapter.
    AnalysisSummary? analysisSummary,

    /// Optional ACPL chart data of the game, coming from lichess server analysis.
    IList<ExternalEval>? acplChartData,

    ChatState? chatState,
  }) = _StudyState;

  /// Whether the current user is the owner of the study.
  bool get amIOwner => myId == study.ownerId || (isAdmin == true && canIContribute);

  /// The current user's member information, if available.
  StudyMember? get myMember => myId != null ? study.members[myId!] : null;

  /// Whether the current user can contribute to the study.
  bool get canIContribute => myMember?.role == 'w';

  /// Whether the study is writeable by the current user
  bool get isWriteable => canIContribute && !gamebookActive;

  @override
  bool get alwaysRequestCloudEval => false;

  /// Whether the engine is available for evaluation
  @override
  bool isEngineAvailable(EngineEvaluationPrefState prefs) => isLocalEngineOffered(
    allowed: isComputerAnalysisAllowed,
    enabled: prefs.isEnabled,
    supported: isNativeEngineSupported,
  );

  bool get isOpeningExplorerAvailable => !gamebookActive && study.chapter.features.explorer;

  bool get isServerAnalysisAllowed => !gamebookActive && study.chapter.features.computer;

  ChapterServerAnalysisStatus get chapterServerAnalysisStatus {
    if (analysisSummary != null) {
      return ChapterServerAnalysisStatus.available;
    }

    if (root == null || root!.mainline.length < 4) {
      return ChapterServerAnalysisStatus.notEnoughMoves;
    }
    if (!isWriteable) {
      return ChapterServerAnalysisStatus.notWriteable;
    }
    return ChapterServerAnalysisStatus.canRequest;
  }

  @override
  ServerAnalysisSource? get serverAnalysisSource =>
      ServerAnalysisSource.studyChapter(studyId: study.id, chapterId: study.chapter.id);

  EngineGaugeParams? engineGaugeParams(EngineEvaluationPrefState prefs) => isEngineAvailable(prefs)
      ? (
          isLocalEngineAvailable: isEngineAvailable(prefs),
          orientation: pov,
          position: currentPosition!,
          savedEval: currentNode.eval,
          serverEval: null,
          filters: (context: evaluationContext, path: currentPath),
        )
      : null;

  @override
  Position? get currentPosition => currentNode.position;

  StudyChapter get currentChapter => study.chapter;
  bool get canGoNext => currentNode.children.isNotEmpty;
  bool get canGoBack => currentPath.size > UciPath.empty.size;

  String get currentChapterTitle {
    final index = study.getChapterIndex(currentChapter.id);
    return '${index + 1}. ${study.chapters[index].name}';
  }

  bool get hasNextChapter => study.chapter.id != study.chapters.last.id;

  bool get isAtEndOfChapter => isOnMainline && currentNode.children.isEmpty;

  bool get isAtStartOfChapter => currentPath.isEmpty;

  String? get gamebookComment {
    final comment = (currentNode.isRoot ? pgnRootComments : currentNode.comments)
        ?.map((comment) => comment.text)
        .nonNulls
        .join('\n');
    return comment?.isNotEmpty == true
        ? comment
        : gamebookState == GamebookState.incorrectMove
        ? gamebookDeviationComment
        : null;
  }

  String? get gamebookHint => study.hints.getOrNull(currentPath.size);

  String? get gamebookDeviationComment => study.deviationComments.getOrNull(currentPath.size);

  GamebookState get gamebookState {
    if (isAtEndOfChapter) return GamebookState.lessonComplete;

    final bool myTurn = currentNode.position!.turn == pov;
    if (isAtStartOfChapter && !myTurn) return GamebookState.startLesson;

    return myTurn
        ? GamebookState.findTheMove
        : isOnMainline
        ? GamebookState.correctMove
        : GamebookState.incorrectMove;
  }

  bool get isIntroductoryChapter => currentNode.isRoot && currentNode.children.isEmpty;

  IList<PgnCommentShape> get pgnShapes => IList(
    (currentNode.isRoot ? pgnRootComments : currentNode.comments)
        ?.map((comment) => comment.shapes)
        .flattened,
  );

  PlayerSide get playerSide =>
      gamebookActive ? (pov == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.both;

  PlayersAnalysis? get playersAnalysis => analysisSummary != null
      ? (white: analysisSummary!.white, black: analysisSummary!.black)
      : null;

  @override
  bool get chatEnabled => study.chat != null;
}

@freezed
sealed class StudyCurrentNode with _$StudyCurrentNode implements AnalysisCurrentNodeInterface {
  const StudyCurrentNode._();

  const factory StudyCurrentNode({
    // Null if the chapter's starting position is illegal.
    required Position? position,
    required List<Move> children,
    required bool isRoot,
    SanMove? sanMove,
    Opening? opening,
    IList<PgnComment>? startingComments,
    IList<PgnComment>? comments,
    IList<int>? nags,
    ClientEval? eval,
  }) = _StudyCurrentNode;

  factory StudyCurrentNode.illegalPosition() {
    return const StudyCurrentNode(position: null, children: [], isRoot: true);
  }

  factory StudyCurrentNode.fromNode(Node node) {
    final children = node.children.map((n) => n.sanMove.move).toList();
    if (node is Branch) {
      return StudyCurrentNode(
        sanMove: node.sanMove,
        position: node.position,
        isRoot: false,
        children: children,
        eval: node.eval,
        opening: node.opening,
        startingComments: IList(node.startingComments),
        comments: IList(node.comments),
        nags: IList(node.nags),
      );
    } else {
      return StudyCurrentNode(
        position: node.position,
        children: children,
        eval: node.eval,
        opening: node.opening,
        isRoot: true,
      );
    }
  }
}
