// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-012, INV-015, INV-016, INV-020, INV-021, INV-022, INV-023,
//   INV-030, INV-031, INV-032, INV-033, INV-065, INV-066, INV-068.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/analysis/analysis_options.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

/// Raw repository snapshot used by the brute-force differential oracles so
/// verification never depends on [ReviewSession] internal indexes or caches.
class RepertoireOracleSnapshot {
  const RepertoireOracleSnapshot({
    required this.studies,
    required this.chapters,
    required this.decisions,
    required this.reviewStates,
    required this.unlockedDecisionIds,
  });

  final List<Study> studies;
  final List<Chapter> chapters;
  final List<RepertoireDecision> decisions;
  final Map<String, ReviewState> reviewStates;
  final Set<String> unlockedDecisionIds;

  static Future<RepertoireOracleSnapshot> capture(StudyRepository repo) async {
    final studies = await repo.getAllStudies();
    final rawChapters = await repo.getAllChapters();
    final chapters = <Chapter>[];
    for (final ch in rawChapters) {
      if (ch.root != null) {
        chapters.add(ch);
      } else {
        chapters.add(ch.copyWith(root: await repo.getPositionTree(ch.id)));
      }
    }
    final decisions = await repo.getAllDecisions();
    final reviewStates = <String, ReviewState>{};
    for (final rs in await repo.getAllReviewStates()) {
      reviewStates[rs.decisionId] = rs;
    }
    for (final ks in await repo.getAllKnowledgeStates()) {
      reviewStates[ks.canonicalId] = ks.toReviewState();
    }
    final unlockedIds = await repo.getUnlockedDecisionIds();
    return RepertoireOracleSnapshot(
      studies: studies,
      chapters: chapters,
      decisions: decisions,
      reviewStates: reviewStates,
      unlockedDecisionIds: unlockedIds,
    );
  }

  Chapter? chapterById(String chapterId) {
    for (final c in chapters) {
      if (c.id == chapterId) return c;
    }
    return null;
  }

  RepertoireNode? findNodeInChapter(String chapterId, String nodeId) {
    final root = chapterById(chapterId)?.root;
    if (root == null) return null;
    return _findNode(root, nodeId);
  }

  /// Returns the unique descendant node path strictly between [fromNode] (via
  /// [firstChild]) and [targetNodeId], or null if [targetNodeId] is not under
  /// [firstChild].
  List<RepertoireNode>? strictIntermediateNodes({
    required String chapterId,
    required RepertoireNode firstChild,
    required String targetNodeId,
  }) {
    final path = <RepertoireNode>[];
    bool dfs(RepertoireNode current) {
      if (current.id == targetNodeId) return true;
      for (final child in current.children) {
        if (dfs(child)) {
          path.add(current);
          return true;
        }
      }
      return false;
    }

    if (!dfs(firstChild)) return null;
    // `path` currently contains ancestors from target's parent up to `firstChild`
    // inclusive; reverse so it reads top-down, and keep `firstChild` only if
    // `firstChild` itself is not `targetNodeId` (opponent moves are on
    // `firstChild` and intermediate nodes; user decisions sit on even plies).
    return path.reversed.toList();
  }

  bool isDecisionActiveInDynamicMode(RepertoireDecision decision) {
    final st = reviewStates[decision.canonicalId] ?? reviewStates[decision.id];
    final hasHistory = st != null && (st.repetitionCount > 0 || st.lapseCount > 0);
    return hasHistory ||
        unlockedDecisionIds.contains(decision.id) ||
        unlockedDecisionIds.contains(decision.canonicalId);
  }

  RepertoireDecision? decisionForNode(String nodeId) {
    for (final d in decisions) {
      if (d.nodeId == nodeId) return d;
    }
    return null;
  }

  /// All decisions inside [subtreeRoot] (inclusive) that are currently
  /// inactive under dynamic repertoire mode.
  List<String> inactiveDecisionIdsInSubtree(RepertoireNode subtreeRoot) {
    final out = <String>[];
    void walk(RepertoireNode node) {
      final d = decisionForNode(node.id);
      if (d != null && !isDecisionActiveInDynamicMode(d)) {
        out.add(d.id);
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(subtreeRoot);
    return out;
  }

  RepertoireDecision? firstDecisionInSubtree(RepertoireNode subtreeRoot) {
    final d = decisionForNode(subtreeRoot.id);
    if (d != null) return d;
    for (final child in subtreeRoot.children) {
      final found = firstDecisionInSubtree(child);
      if (found != null) return found;
    }
    return null;
  }

  static RepertoireNode? _findNode(RepertoireNode node, String nodeId) {
    if (node.id == nodeId) return node;
    for (final child in node.children) {
      final found = _findNode(child, nodeId);
      if (found != null) return found;
    }
    return null;
  }
}

/// Brute-force differential oracle for board-only FEN truth (INV-020, INV-065)
/// computed directly from raw [Study]/[Chapter] trees without touching
/// [ReviewSession]'s internal indices.
class BoardTruthOracle {
  BoardTruthOracle({required this.snapshot, required this.scope, required this.transposeScope});

  final RepertoireOracleSnapshot snapshot;
  final ReviewScope scope;
  final TransposeScope transposeScope;

  List<Chapter> inScopeChapters({String? promptStudyId}) {
    final activeStudyIds = {
      for (final s in snapshot.studies)
        if (s.isActive) s.id,
    };
    final restrictToActiveStudies = scope.studyId == null && scope.chapterId == null;
    final out = <Chapter>[];
    for (final c in snapshot.chapters) {
      if (restrictToActiveStudies && !activeStudyIds.contains(c.studyId)) continue;
      if (!scope.matches(
        studyId: c.studyId,
        chapterId: c.id,
        openingFamily: c.opening,
        side: c.orientation,
      )) {
        continue;
      }
      if (transposeScope == TransposeScope.withinStudy &&
          promptStudyId != null &&
          c.studyId != promptStudyId) {
        continue;
      }
      out.add(c);
    }
    return out;
  }

  Set<String> inScopeTreeFenKeys({String? promptStudyId}) {
    final keys = <String>{};
    void walk(RepertoireNode node) {
      keys.add(node.fenKey);
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final ch in inScopeChapters(promptStudyId: promptStudyId)) {
      final root = ch.root;
      if (root != null) walk(root);
    }
    return keys;
  }

  List<RepertoireDecision> inScopeDecisionsAtFenKey(String targetFenKey, {String? promptStudyId}) {
    final chapters = {for (final c in inScopeChapters(promptStudyId: promptStudyId)) c.id: c};
    final out = <RepertoireDecision>[];
    for (final d in snapshot.decisions) {
      final ch = chapters[d.chapterId];
      if (ch == null) continue;
      final node = snapshot.findNodeInChapter(ch.id, d.nodeId);
      final nodeKey = node?.fenKey ?? d.fenKey;
      if (nodeKey == targetFenKey) {
        out.add(d);
      }
    }
    return out;
  }

  List<RepertoireMove> expectedMergedMoves(ReviewPrompt prompt) {
    final merged = <RepertoireMove>[...prompt.decision.expectedMoves];
    if (transposeScope == TransposeScope.off) return merged;
    for (final d in inScopeDecisionsAtFenKey(prompt.fenKey, promptStudyId: prompt.studyId)) {
      if (d.id == prompt.decision.id) continue;
      for (final m in d.expectedMoves) {
        if (!merged.any((existing) => existing.matches(m))) {
          merged.add(m);
        }
      }
    }
    return merged;
  }

  bool isMoveAccepted({
    required ReviewPrompt prompt,
    required Position boardPosition,
    required NormalMove played,
  }) {
    final playedRepertoireMove = RepertoireMove(
      from: played.from.name,
      to: played.to.name,
      promotion: played.promotion?.letter,
    );
    if (prompt.decision.expectedMoves.any((m) => m.matches(playedRepertoireMove))) {
      return true;
    }
    if (transposeScope == TransposeScope.off) return false;

    for (final d in inScopeDecisionsAtFenKey(prompt.fenKey, promptStudyId: prompt.studyId)) {
      if (d.id == prompt.decision.id) continue;
      final match = d.expectedMoves.where((m) => m.matches(playedRepertoireMove)).firstOrNull;
      if (match != null) {
        final dNode = snapshot.findNodeInChapter(d.chapterId, d.nodeId);
        if (dNode?.childForMove(match) != null) {
          return true;
        }
      }
    }

    final playable = playableNormalMove(boardPosition, played);
    if (playable == null) return false;
    final nextPos = boardPosition.play(playable);
    final nextKey = fenKey(nextPos.fen);
    return inScopeTreeFenKeys(promptStudyId: prompt.studyId).contains(nextKey);
  }
}

/// Normalizes a [NormalMove] so both standard (`e1g1`) and king-takes-rook
/// (`e1h1`) castling representations are accepted when legal on [position].
NormalMove? playableNormalMove(Position position, NormalMove move) {
  if (position.isLegal(move)) return move;
  final altUci = kingTakesRookCastles[move.uci] ?? altCastles[move.uci];
  if (altUci != null) {
    final alt = Move.parse(altUci);
    if (alt is NormalMove && position.isLegal(alt)) return alt;
  }
  return null;
}

bool normalMoveMatchesRepertoire(NormalMove move, RepertoireMove rep) {
  if ((move.promotion?.letter ?? '') != (rep.promotion?.toLowerCase() ?? '')) {
    return false;
  }
  return normalizeUci(move.uci) == normalizeUci(rep.uci);
}

bool repertoireMovesMatch(RepertoireMove a, RepertoireMove b) => a.matches(b);

String normalizeFen(String fen) {
  try {
    return Chess.fromSetup(Setup.parseFen(fen)).fen;
  } catch (_) {
    return Chess.initial.fen;
  }
}

/// Checks physical coherence between [boardPosition] and [lastMove]:
/// `lastMove.to` (or the king's castled destination for king-takes-rook UCI)
/// must hold a piece of the opposite color to `boardPosition.turn`, and
/// `lastMove.from` must be empty.
String? checkLastMoveCoherence(Position boardPosition, Move lastMove) {
  if (lastMove is! NormalMove) {
    return 'Non-normal lastMove $lastMove is unsupported in standard repertoire review';
  }
  if (lastMove.from == lastMove.to) {
    return 'Degenerate lastMove $lastMove has identical from and to squares';
  }
  final pieceAtFrom = boardPosition.board.pieceAt(lastMove.from);
  if (pieceAtFrom != null) {
    return 'Incoherent lastMove ${lastMove.uci} on ${boardPosition.fen}: '
        'origin square ${lastMove.from.name} is still occupied by $pieceAtFrom';
  }

  final pieceAtTo = boardPosition.board.pieceAt(lastMove.to);
  if (pieceAtTo != null) {
    if (pieceAtTo.color == boardPosition.turn) {
      return 'Stale lastMove ${lastMove.uci} on ${boardPosition.fen}: '
          'destination ${lastMove.to.name} holds ${pieceAtTo.color.name} ${pieceAtTo.role.name}, '
          'which is the side to move (${boardPosition.turn.name})';
    }
    return null;
  }

  // King-takes-rook castling UCIs leave the rook square empty while the king
  // lands on g1/c1/g8/c8 and the rook lands on f1/d1/f8/d8.
  final castledLanding = switch (lastMove.uci) {
    'e1h1' => (kingSq: Square.g1, rookSq: Square.f1, side: Side.white),
    'e1a1' => (kingSq: Square.c1, rookSq: Square.d1, side: Side.white),
    'e8h8' => (kingSq: Square.g8, rookSq: Square.f8, side: Side.black),
    'e8a8' => (kingSq: Square.c8, rookSq: Square.d8, side: Side.black),
    _ => null,
  };
  if (castledLanding != null &&
      boardPosition.turn != castledLanding.side &&
      boardPosition.board.pieceAt(castledLanding.kingSq) ==
          Piece(color: castledLanding.side, role: Role.king) &&
      boardPosition.board.pieceAt(castledLanding.rookSq) ==
          Piece(color: castledLanding.side, role: Role.rook)) {
    return null;
  }

  return 'Stale or phantom lastMove ${lastMove.uci} on ${boardPosition.fen}: '
      'destination square ${lastMove.to.name} is empty';
}

/// Checks Open-in-Analysis fidelity (PR #581 invariant):
/// `analysisOptionsForReviewPosition` must parse via `Root.fromPgnGame` with
/// zero dropped moves, cursor at the live board FEN, and expected continuation
/// moves present at the prompt node.
void verifyOpenInAnalysisFidelity(ReviewScreenState state) {
  final prompt = state.currentPrompt;
  final boardPos = state.boardPosition;
  if (prompt == null || boardPos == null) return;

  final chapter = state.session?.getChapter(prompt.chapterId);
  final expected = state.expectedMove ?? prompt.expectedMoves.firstOrNull;
  final continuationMoves = _continuationMovesForAnalysis(state);
  final playedSan = state.isAwaitingAdvance ? state.lastStepResult?.movePlayed.san : null;
  final effectiveHistory = [...prompt.moveHistory, ?playedSan];

  final options = analysisOptionsForReviewPosition(
    fen: boardPos.fen,
    startingFen: chapter?.startingFen,
    orientation: state.boardOrientation,
    moveHistory: effectiveHistory,
    continuationMoves: continuationMoves,
  );

  expect(options, isA<Pgn>(), reason: 'Open in analysis must produce Pgn analysis options');
  final pgnOption = options as Pgn;
  final game = PgnGame.parsePgn(pgnOption.pgn);

  var cursorPath = UciPath.empty;
  final root = Root.fromPgnGame(
    game,
    onVisitNode: (root, branch, isMainline) {
      if (isMainline &&
          pgnOption.initialMoveCursor != null &&
          branch.position.ply <= root.position.ply + pgnOption.initialMoveCursor!) {
        cursorPath = cursorPath + branch.id;
      }
    },
  );

  final expectedMainline = [...effectiveHistory, ...continuationMoves];
  final actualMainline = <String>[];
  Node cursor = root;
  while (cursor.children.isNotEmpty) {
    final next = cursor.children.first;
    actualMainline.add(next.sanMove.san);
    cursor = next;
  }

  expect(
    actualMainline.length,
    expectedMainline.length,
    reason:
        'Open in analysis dropped moves! expected=$expectedMainline actual=$actualMainline '
        'startingFen=${chapter?.startingFen} pgn=${pgnOption.pgn}',
  );
  for (var i = 0; i < expectedMainline.length; i++) {
    expect(
      actualMainline[i],
      expectedMainline[i],
      reason: 'Open in analysis mainline mismatch at ply $i: ${pgnOption.pgn}',
    );
  }

  final nodeAtCursor = pgnOption.initialMoveCursor != null ? root.nodeAt(cursorPath) : root;
  expect(
    fenKey(nodeAtCursor.position.fen),
    fenKey(boardPos.fen),
    reason:
        'Open in analysis cursor landed on ${fenKey(nodeAtCursor.position.fen)} '
        'instead of board FEN ${fenKey(boardPos.fen)} (pgn=${pgnOption.pgn})',
  );

  // When still at the prompt position (open prompt or lapse, before advancing past userMove),
  // the expected continuation must be available as a child at the cursor.
  if (!state.isAwaitingAdvance && expected != null && continuationMoves.isNotEmpty) {
    expect(
      nodeAtCursor.children,
      isNotEmpty,
      reason: 'Open in analysis omitted continuation moves at cursor for ${prompt.fenKey}',
    );
    final firstChild = nodeAtCursor.children.first;
    final expectedSan = expected.san;
    if (expectedSan != null) {
      expect(
        firstChild.sanMove.san,
        expectedSan,
        reason:
            'Open in analysis first continuation was ${firstChild.sanMove.san}, expected $expectedSan',
      );
    }
  }
}

List<String> _continuationMovesForAnalysis(ReviewScreenState state) {
  final prompt = state.currentPrompt;
  if (prompt == null) return const [];
  final expected = state.expectedMove ?? prompt.expectedMoves.firstOrNull;
  final node = prompt.currentNode;
  if (node != null && node.children.isNotEmpty) {
    final out = <String>[];
    RepertoireNode? child =
        (expected != null ? node.childForMove(expected) : null) ?? node.children.first;
    if (state.isAwaitingAdvance) {
      child = child.children.firstOrNull;
    }
    while (child != null) {
      final m = child.incomingMove;
      if (m != null) {
        out.add(m.san ?? m.uci);
      }
      child = child.children.firstOrNull;
    }
    if (out.isNotEmpty) return out;
  }
  if (expected != null && !state.isAwaitingAdvance) {
    return [expected.san ?? expected.uci];
  }
  return const [];
}

/// Continuous real-time invariant monitor attached to [reviewControllerProvider].
///
/// Validates every emitted [ReviewScreenState] frame and provides settled-state
/// and step-level differential oracle checks.
class ReviewInvariantMonitor {
  ReviewInvariantMonitor.attach(this.container, {required this.repository}) {
    _subscription = container.listen<AsyncValue<ReviewScreenState>>(
      reviewControllerProvider,
      _onEmission,
      fireImmediately: true,
    );
  }

  final ProviderContainer container;
  final StudyRepository repository;
  late final ProviderSubscription<AsyncValue<ReviewScreenState>> _subscription;

  final List<String> violations = [];
  int frameCount = 0;

  ReviewSession? _trackedSession;
  ReviewPrompt? _awaitingPreMovePrompt;
  final Set<String> _answeredCorrectlyFenKeys = {};
  final Set<String> _requeuedCanonicalIds = {};

  void dispose() {
    _subscription.close();
  }

  void _recordViolation(String message) {
    violations.add('[frame $frameCount] $message');
  }

  void assertClean() {
    if (violations.isNotEmpty) {
      fail(
        'ReviewInvariantMonitor detected ${violations.length} violation(s):\n${violations.join('\n')}',
      );
    }
  }

  void _resetSessionTracking(ReviewSession? session) {
    _trackedSession = session;
    _answeredCorrectlyFenKeys.clear();
    _requeuedCanonicalIds.clear();
  }

  bool _animatePreMoveSetting() {
    try {
      return container.read(studyPreferencesProvider).animateOpponentPreMove;
    } catch (_) {
      return true;
    }
  }

  bool _activeStudiesChanged(List<Study> prev, List<Study> next) {
    if (prev.length != next.length) return true;
    final prevActive = {for (final s in prev) s.id: s.isActive};
    for (final s in next) {
      if (prevActive[s.id] != s.isActive) return true;
    }
    return false;
  }

  void _onEmission(
    AsyncValue<ReviewScreenState>? prevAsync,
    AsyncValue<ReviewScreenState> nextAsync,
  ) {
    if (nextAsync.hasError) return;
    final next = nextAsync.asData?.value;
    if (next == null) return;
    frameCount++;

    final prev = prevAsync?.asData?.value;

    // 1. Board & lastMove Physical Coherence on EVERY emitted frame.
    if (next.lastMove != null && next.boardPosition != null) {
      final err = checkLastMoveCoherence(next.boardPosition!, next.lastMove!);
      if (err != null) _recordViolation(err);
    }

    // Track session switches.
    if (!identical(next.session, _trackedSession)) {
      _resetSessionTracking(next.session);
    }

    // Track multi-study answered FENs when a correct step result is published.
    if (prev != null &&
        next.lastStepResult != null &&
        !identical(prev.lastStepResult, next.lastStepResult)) {
      final res = next.lastStepResult!;
      final answeredPrompt = prev.currentPrompt;
      if (answeredPrompt != null) {
        if (res.isCorrect) {
          final lapsedIds = next.session?.checkpoint().lapsedDecisionIds ?? const {};
          if (!lapsedIds.contains(answeredPrompt.decision.canonicalId)) {
            _requeuedCanonicalIds.remove(answeredPrompt.decision.canonicalId);
            _answeredCorrectlyFenKeys.add(answeredPrompt.fenKey);
          }
        } else {
          _requeuedCanonicalIds.add(answeredPrompt.decision.canonicalId);
        }
      }
    }

    final prompt = next.currentPrompt;
    if (prompt != null) {
      // Orientation always matches sideToMove.
      if (next.boardOrientation != prompt.sideToMove) {
        _recordViolation(
          'Board orientation ${next.boardOrientation} disagrees with prompt.sideToMove ${prompt.sideToMove} '
          'for ${prompt.decision.id}',
        );
      }

      final promptReplaced = !identical(prev?.currentPrompt, prompt);
      final animatePreMove = _animatePreMoveSetting();
      final isStudyMutationRefresh =
          prev != null && _activeStudiesChanged(prev.studies, next.studies);

      if (promptReplaced) {
        _awaitingPreMovePrompt = null;

        // Multi-study general review uniqueness (PR #585, INV-020, INV-065).
        final activeStudyCount = next.studies.where((s) => s.isActive).length;
        final isMultiStudyGeneral =
            next.scope.studyId == null &&
            next.scope.chapterId == null &&
            activeStudyCount > 1 &&
            next.mode == ReviewMode.srs &&
            next.session?.transposeScope == TransposeScope.inScope;
        final lapsedIds = next.session?.checkpoint().lapsedDecisionIds ?? const {};
        final isLapsedReTest = lapsedIds.contains(prompt.decision.canonicalId);
        if (isMultiStudyGeneral &&
            !isLapsedReTest &&
            !_requeuedCanonicalIds.contains(prompt.decision.canonicalId) &&
            _answeredCorrectlyFenKeys.contains(prompt.fenKey)) {
          _recordViolation(
            'Duplicate fenKey prompted in multi-study general review: ${prompt.fenKey} '
            '(decision=${prompt.decision.id}, study=${prompt.studyId})',
          );
        }

        // Pre-Move Animation State-Machine Law (PR #618).
        if (!isStudyMutationRefresh && prompt.incomingMove != null && prompt.parentFen != null) {
          final alreadyAnimated = _wasAlreadyAnimatedAsSingleOpponentReply(prev, prompt);
          if (animatePreMove) {
            if (alreadyAnimated) {
              if (next.boardPosition?.fen != normalizeFen(prompt.fen)) {
                _recordViolation(
                  'alreadyAnimatedNextPrompt expected boardPosition=${normalizeFen(prompt.fen)}, '
                  'got ${next.boardPosition?.fen}',
                );
              }
              if (next.lastMove is! NormalMove ||
                  !normalMoveMatchesRepertoire(
                    next.lastMove! as NormalMove,
                    prompt.incomingMove!,
                  )) {
                _recordViolation(
                  'alreadyAnimatedNextPrompt expected lastMove=${prompt.incomingMove}, '
                  'got ${next.lastMove}',
                );
              }
            } else {
              if (next.boardPosition?.fen != normalizeFen(prompt.parentFen!)) {
                _recordViolation(
                  'Pre-move transition to ${prompt.decision.id} (${prompt.incomingMove}) '
                  'must start at parentFen=${normalizeFen(prompt.parentFen!)}, '
                  'got boardPosition=${next.boardPosition?.fen} (lastMove=${next.lastMove})',
                );
              }
              if (next.lastMove != null) {
                _recordViolation(
                  'Pre-move transition to ${prompt.decision.id} (${prompt.incomingMove}) '
                  'must clear lastMove before animating incomingMove, got lastMove=${next.lastMove}',
                );
              }
              _awaitingPreMovePrompt = prompt;
            }
          } else {
            if (next.boardPosition?.fen != normalizeFen(prompt.fen)) {
              _recordViolation(
                'Non-animated transition to ${prompt.decision.id} expected fen=${normalizeFen(prompt.fen)}, '
                'got ${next.boardPosition?.fen}',
              );
            }
            if (!alreadyAnimated && next.lastMove != null) {
              _recordViolation(
                'Non-animated branch transition to ${prompt.decision.id} left stale lastMove=${next.lastMove}',
              );
            }
          }
        }
      } else if (_awaitingPreMovePrompt != null && identical(_awaitingPreMovePrompt, prompt)) {
        // Same prompt while pre-move animation is pending: if boardPosition moved
        // to prompt.fen, either _playIncomingPreMove completed with incomingMove
        // or cancelPreMoveAnimation snapped with lastMove == null.
        if (next.boardPosition?.fen == normalizeFen(prompt.fen)) {
          if (next.lastMove != null &&
              (next.lastMove is! NormalMove ||
                  !normalMoveMatchesRepertoire(
                    next.lastMove! as NormalMove,
                    prompt.incomingMove!,
                  ))) {
            _recordViolation(
              'Pre-move settlement for ${prompt.decision.id} produced unexpected lastMove=${next.lastMove}, '
              'expected ${prompt.incomingMove} or null (if cancelled)',
            );
          }
          _awaitingPreMovePrompt = null;
        }
      }
    } else {
      _awaitingPreMovePrompt = null;
    }
  }

  bool _wasAlreadyAnimatedAsSingleOpponentReply(ReviewScreenState? prev, ReviewPrompt nextPrompt) {
    final step = prev?.lastStepResult;
    if (prev == null || step == null) return false;
    final oppMoves = step.autoPlayedMoves.where((m) => !m.isUserMove).toList();
    if (oppMoves.length != 1) return false;
    if (step.autoPlayedMoves.lastOrNull?.fenAfter != nextPrompt.fen) return false;
    final incoming = nextPrompt.incomingMove;
    if (incoming != null && !oppMoves.single.move.matches(incoming)) return false;
    if (prev.boardPosition?.fen != normalizeFen(nextPrompt.fen)) return false;
    final prevLast = prev.lastMove;
    if (incoming != null &&
        (prevLast is! NormalMove || !normalMoveMatchesRepertoire(prevLast, incoming))) {
      return false;
    }
    return true;
  }

  /// Notes that `skip()` was invoked for [skippedCanonicalId] so returning to
  /// that decision later in a multi-study session is not flagged as a duplicate.
  void noteSkip(String skippedCanonicalId) {
    _requeuedCanonicalIds.add(skippedCanonicalId);
  }

  /// Waits for any pending pre-move animation to settle, then verifies all
  /// settled-state invariants and differential oracles.
  Future<void> waitAndVerifySettled({
    required RepertoireOracleSnapshot snapshot,
    bool checkWidgetBoard = false,
    WidgetTester? tester,
  }) async {
    assertClean();
    final current = container.read(reviewControllerProvider).requireValue;
    final prompt = current.currentPrompt;
    if (prompt == null) {
      assertClean();
      return;
    }

    if (current.feedback == ReviewFeedback.none && !current.isAwaitingAdvance) {
      await waitUntil(() {
        final s = container.read(reviewControllerProvider).value;
        if (s == null || s.currentPrompt == null) return true;
        final p = s.currentPrompt!;
        final animate = _animatePreMoveSetting();
        final fenReady = s.boardPosition?.fen == normalizeFen(p.fen);
        if (!animate || p.incomingMove == null || p.parentFen == null) return fenReady;
        return fenReady && s.lastMove != null;
      });
    }
    assertClean();

    final settled = container.read(reviewControllerProvider).requireValue;
    verifySettledState(settled, snapshot: snapshot);

    if (checkWidgetBoard && tester != null && settled.currentPrompt != null) {
      await tester.pump();
      expect(
        getBoardLastMove(tester),
        settled.lastMove,
        reason: 'Rendered Chessboard lastMove disagrees with ReviewScreenState.lastMove',
      );
      final boardPos = settled.boardPosition;
      if (boardPos != null) {
        final renderedPieces = getBoardPieces(tester);
        for (final sq in Square.values) {
          expect(
            renderedPieces[sq],
            boardPos.board.pieceAt(sq),
            reason: 'Rendered piece mismatch on ${sq.name} for ${boardPos.fen}',
          );
        }
      }
    }
  }

  void verifySettledState(ReviewScreenState state, {required RepertoireOracleSnapshot snapshot}) {
    assertClean();
    final prompt = state.currentPrompt;
    if (prompt == null) return;

    final boardPos = state.boardPosition;
    expect(boardPos, isNotNull, reason: 'Active prompt must have a non-null boardPosition');
    if (state.feedback == ReviewFeedback.none && !state.isAwaitingAdvance) {
      expect(
        boardPos!.fen,
        normalizeFen(prompt.fen),
        reason: 'Settled boardPosition.fen must match prompt.fen',
      );
      if (_animatePreMoveSetting() && prompt.incomingMove != null && prompt.parentFen != null) {
        expect(
          state.lastMove,
          isA<NormalMove>(),
          reason: 'Settled prompt with incomingMove must highlight incomingMove',
        );
        expect(
          normalMoveMatchesRepertoire(state.lastMove! as NormalMove, prompt.incomingMove!),
          isTrue,
          reason:
              'Settled lastMove ${state.lastMove} does not match prompt.incomingMove ${prompt.incomingMove}',
        );
      }
    }
    expect(state.boardOrientation, prompt.sideToMove);

    // Every move in prompt.expectedMoves must be legal on the prompt position.
    final promptPos = Chess.fromSetup(Setup.parseFen(normalizeFen(prompt.fen)));
    for (final exp in prompt.expectedMoves) {
      final parsed = Move.parse(exp.uci);
      expect(parsed, isA<NormalMove>(), reason: 'Expected move ${exp.uci} must parse');
      expect(
        playableNormalMove(promptPos, parsed! as NormalMove),
        isNotNull,
        reason: 'Expected move ${exp.uci} (${exp.san}) is illegal on ${promptPos.fen}',
      );
    }

    // Differential Board-Only FEN Truth check for prompt.expectedMoves.
    final session = state.session;
    if (session != null) {
      final oracle = BoardTruthOracle(
        snapshot: snapshot,
        scope: state.scope,
        transposeScope: session.transposeScope,
      );
      final expectedFromOracle = oracle.expectedMergedMoves(prompt);
      for (final m in expectedFromOracle) {
        expect(
          prompt.expectedMoves.any((p) => p.matches(m)),
          isTrue,
          reason:
              'prompt.expectedMoves (${prompt.expectedMoves}) missing in-scope move $m at ${prompt.fenKey}',
        );
      }
      for (final m in prompt.expectedMoves) {
        expect(
          expectedFromOracle.any((o) => o.matches(m)),
          isTrue,
          reason:
              'prompt.expectedMoves contains unexpected out-of-scope move $m at ${prompt.fenKey}',
        );
      }
    }

    // Open-in-Analysis Fidelity check.
    verifyOpenInAnalysisFidelity(state);
  }

  /// Plays [move] via `ReviewController.onUserMove` and verifies grading,
  /// continuity path integrity (INV-022), dynamic branch adoption, and
  /// settled invariants against [snapshot].
  Future<ReviewStepResult?> playAndVerifyMove(
    NormalMove move, {
    required RepertoireOracleSnapshot snapshot,
  }) async {
    final controller = container.read(reviewControllerProvider.notifier);
    final preState = container.read(reviewControllerProvider).requireValue;
    final prePrompt = preState.currentPrompt;
    if (prePrompt == null) return null;

    // Ensure pre-move animation settled or let onUserMove cancel it cleanly.
    final promptPos = Chess.fromSetup(Setup.parseFen(normalizeFen(prePrompt.fen)));
    final session = preState.session!;
    final oracle = BoardTruthOracle(
      snapshot: snapshot,
      scope: preState.scope,
      transposeScope: session.transposeScope,
    );
    final expectedAccepted = oracle.isMoveAccepted(
      prompt: prePrompt,
      boardPosition: promptPos,
      played: move,
    );

    final result = await controller.onUserMove(move);
    assertClean();
    expect(result, isNotNull, reason: 'onUserMove(${move.uci}) unexpectedly returned null');
    expect(
      result!.isCorrect,
      expectedAccepted,
      reason:
          'Differential BoardTruthOracle mismatch on ${move.uci} at ${prePrompt.fenKey} '
          '(scope=${preState.scope}, transpose=${session.transposeScope}): '
          'expected=$expectedAccepted, got=${result.isCorrect}',
    );

    final postState = container.read(reviewControllerProvider).requireValue;
    if (postState.isAwaitingAdvance) {
      verifyOpenInAnalysisFidelity(postState);
      await controller.continueAdvancement();
      assertClean();
    }

    if (result.isCorrect) {
      _verifyContinuityAndAdoption(
        preState: preState,
        prePrompt: prePrompt,
        played: move,
        result: result,
        preSnapshot: snapshot,
      );
      if (preState.mode == ReviewMode.srs && session.dynamicRepertoireMode) {
        final dbUnlocked = await repository.getUnlockedDecisionIds();
        for (final adoptedId in result.adoptedDecisionIds) {
          expect(
            dbUnlocked.contains(adoptedId),
            isTrue,
            reason: 'Adopted decision $adoptedId was not persisted to repository',
          );
        }
      }
    } else {
      // Lapse state must still satisfy Open in analysis fidelity!
      verifySettledState(postState, snapshot: snapshot);
    }

    final afterSnapshot = await RepertoireOracleSnapshot.capture(repository);
    await waitAndVerifySettled(snapshot: afterSnapshot);
    return result;
  }

  void _verifyContinuityAndAdoption({
    required ReviewScreenState preState,
    required ReviewPrompt prePrompt,
    required NormalMove played,
    required ReviewStepResult result,
    required RepertoireOracleSnapshot preSnapshot,
  }) {
    final session = preState.session!;
    final preNode = prePrompt.currentNode;
    final playedRep = RepertoireMove(
      from: played.from.name,
      to: played.to.name,
      promotion: played.promotion?.letter,
    );
    final playedChild = preNode?.childForMove(playedRep);

    // 1. FullLine continuity path oracle (INV-022): no active decision may be
    // skipped along the unique path from playedChild to result.nextPrompt,
    // and no user move may be auto-played in fullLine mode unless quota
    // halted the walk.
    if (session.continuity == ReviewContinuity.fullLine) {
      expect(
        result.autoPlayedMoves.where((m) => m.isUserMove),
        isEmpty,
        reason:
            'fullLine continuity auto-played user move(s) ${result.autoPlayedMoves} '
            'after ${played.uci}',
      );
      if (playedChild != null &&
          result.nextPrompt != null &&
          result.nextPrompt!.chapterId == prePrompt.chapterId) {
        final intermediate = preSnapshot.strictIntermediateNodes(
          chapterId: prePrompt.chapterId,
          firstChild: playedChild,
          targetNodeId: result.nextPrompt!.nodeId,
        );
        if (intermediate != null) {
          for (final n in intermediate) {
            final d = preSnapshot.decisionForNode(n.id);
            if (d == null) continue;
            if (!session.dynamicRepertoireMode || preSnapshot.isDecisionActiveInDynamicMode(d)) {
              if (session.remainingDailyQuota == null) {
                fail(
                  'fullLine continuity skipped active intermediate decision ${d.id} '
                  '(node=${n.id}) between ${prePrompt.nodeId} and ${result.nextPrompt!.nodeId}',
                );
              }
            }
          }
        }
      }
    }

    // 2. Dynamic repertoire branch adoption check (PR #590):
    if (preState.mode == ReviewMode.srs &&
        session.dynamicRepertoireMode &&
        preNode != null &&
        preNode.children.length > 1 &&
        playedChild != null) {
      final head = preSnapshot.firstDecisionInSubtree(playedChild);
      if (head != null && !preSnapshot.isDecisionActiveInDynamicMode(head)) {
        final expectedAdopted = preSnapshot.inactiveDecisionIdsInSubtree(playedChild);
        for (final id in expectedAdopted) {
          expect(
            result.adoptedDecisionIds,
            contains(id),
            reason: 'Playing inactive alternative branch ${played.uci} failed to adopt $id',
          );
          expect(
            session.unlockedDecisionIds,
            contains(id),
            reason: 'Session unlockedDecisionIds missing adopted $id',
          );
        }
      }
    }
  }
}
