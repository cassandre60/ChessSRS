// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-012, INV-015, INV-016, INV-020, INV-021, INV-022, INV-023,
//   INV-030, INV-031, INV-032, INV-033, INV-065, INV-066, INV-068.

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';
import '../model/common/service/fake_sound_service.dart';
import '../test_helpers.dart';
import '../test_provider_scope.dart';
import 'review_invariant_oracle.dart';

/// Deterministic seeded generator of pathological repertoires covering:
/// - trailing opponent leaf moves followed by branches with incoming pre-moves,
/// - custom [FEN "..."] chapters (White-to-move, Black-to-move, castling, promotions),
/// - cross-study shared fenKeys with disjoint expected moves and non-due studies,
/// - dynamic-mode mid-line holes (reps=0 && lapseCount>0, unreviewed bridges),
/// - PGN comments and board shape annotations.
class _PathologicalRepertoireGenerator {
  _PathologicalRepertoireGenerator(this.rng);

  final Random rng;

  static const _customStartingFens = <String>[
    // Standard starting position
    kInitialFEN,
    // After 1. e4 (Black to move)
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
    // After 1. d4 d5 2. c4 (Black to move)
    'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2',
    // Castling-ready Italian position (White to move, O-O legal)
    'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
    // Promotion-ready endgame position (White pawn on e7, Black pawn on a2)
    '4k3/4P3/8/8/8/8/p7/4K3 w - - 0 1',
    // En-passant ready position (White pawn on e5 after 1... d5)
    'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2',
  ];

  /// Generates a legal random PGN tree from [startFen] with [minPlies]..[maxPlies]
  /// depth, optional variations, optional annotations, and configurable
  /// trailing-opponent-move frequency.
  String generateChapterPgn({
    required String title,
    required String startFen,
    required Side repertoireSide,
    int minPlies = 2,
    int maxPlies = 6,
    double variationProbability = 0.25,
    double trailingOpponentProbability = 0.5,
    double commentProbability = 0.15,
  }) {
    final startPos = Chess.fromSetup(Setup.parseFen(startFen));
    final root = PgnNode<PgnNodeData>();
    _growPgnSubtree(
      node: root,
      pos: startPos,
      repertoireSide: repertoireSide,
      depth: 0,
      targetDepth: minPlies + rng.nextInt(maxPlies - minPlies + 1),
      variationProbability: variationProbability,
      trailingOpponentProbability: trailingOpponentProbability,
      commentProbability: commentProbability,
      branchBudget: 4,
    );

    // Ensure at least one move for repertoireSide exists.
    if (!_hasMoveForSide(root, startPos.turn, repertoireSide)) {
      _forceOneRepertoireMove(root, startPos, repertoireSide);
    }

    final headers = <String, String>{
      'Event': title,
      'Chapter': title,
      'Orientation': repertoireSide == Side.white ? 'white' : 'black',
      if (startFen != kInitialFEN) ...{'SetUp': '1', 'FEN': startFen},
    };
    return PgnGame<PgnNodeData>(headers: headers, moves: root, comments: const []).makePgn();
  }

  void _growPgnSubtree({
    required PgnNode<PgnNodeData> node,
    required Position pos,
    required Side repertoireSide,
    required int depth,
    required int targetDepth,
    required double variationProbability,
    required double trailingOpponentProbability,
    required double commentProbability,
    required int branchBudget,
  }) {
    if (pos.isGameOver || depth >= targetDepth) {
      // Optionally terminate on a trailing opponent reply if it's opponent's turn.
      if (!pos.isGameOver &&
          pos.turn != repertoireSide &&
          rng.nextDouble() < trailingOpponentProbability) {
        final oppMoves = _allLegalMoves(pos);
        if (oppMoves.isNotEmpty) {
          final pick = oppMoves[rng.nextInt(oppMoves.length)];
          final (_, san) = pos.makeSan(pick);
          node.children.add(PgnChildNode(PgnNodeData(san: san)));
        }
      }
      return;
    }

    final legal = _allLegalMoves(pos);
    if (legal.isEmpty) return;

    // Prefer castling or promotions when available so special moves get covered.
    final special = legal.where((m) {
      final (_, san) = pos.makeSan(m);
      return san.startsWith('O-O') || m.promotion != null;
    }).toList();
    final mainMove = (special.isNotEmpty && rng.nextDouble() < 0.65)
        ? special[rng.nextInt(special.length)]
        : legal[rng.nextInt(legal.length)];

    final chosen = <NormalMove>[mainMove];
    if (branchBudget > 0 && legal.length > 1 && rng.nextDouble() < variationProbability) {
      final remaining = legal.where((m) => m != mainMove).toList();
      chosen.add(remaining[rng.nextInt(remaining.length)]);
    }

    for (var i = 0; i < chosen.length; i++) {
      final move = chosen[i];
      final (nextPos, san) = pos.makeSan(move);
      final comments = (rng.nextDouble() < commentProbability)
          ? ['[%cal G${move.from.name}${move.to.name}] Note on $san']
          : null;
      final child = PgnChildNode(PgnNodeData(san: san, comments: comments));
      node.children.add(child);
      _growPgnSubtree(
        node: child,
        pos: nextPos,
        repertoireSide: repertoireSide,
        depth: depth + 1,
        targetDepth: targetDepth,
        variationProbability: variationProbability * 0.6,
        trailingOpponentProbability: trailingOpponentProbability,
        commentProbability: commentProbability,
        branchBudget: branchBudget - (i > 0 ? 1 : 0),
      );
    }
  }

  bool _hasMoveForSide(PgnNode<PgnNodeData> node, Side turn, Side target) {
    if (node.children.isEmpty) return false;
    if (turn == target) return true;
    return node.children.any((c) => _hasMoveForSide(c, turn.opposite, target));
  }

  void _forceOneRepertoireMove(PgnNode<PgnNodeData> root, Position pos, Side target) {
    var cursor = root;
    var curPos = pos;
    while (!curPos.isGameOver) {
      final legal = _allLegalMoves(curPos);
      if (legal.isEmpty) break;
      final m = legal[rng.nextInt(legal.length)];
      final (nextPos, san) = curPos.makeSan(m);
      final child = PgnChildNode(PgnNodeData(san: san));
      cursor.children.add(child);
      if (curPos.turn == target) break;
      cursor = child;
      curPos = nextPos;
    }
  }

  static List<NormalMove> _allLegalMoves(Position pos) {
    final moves = <NormalMove>[];
    for (final entry in pos.legalMoves.entries) {
      final from = entry.key;
      for (final to in entry.value.squares) {
        final piece = pos.board.pieceAt(from);
        final isPromotion =
            piece?.role == Role.pawn &&
            ((pos.turn == Side.white && to.rank == Rank.eighth) ||
                (pos.turn == Side.black && to.rank == Rank.first));
        if (isPromotion) {
          moves.add(NormalMove(from: from, to: to, promotion: Role.queen));
          moves.add(NormalMove(from: from, to: to, promotion: Role.knight));
        } else {
          moves.add(NormalMove(from: from, to: to));
        }
      }
    }
    return moves;
  }

  /// Generates a multi-study repertoire containing standard lines, custom FEN
  /// lines, trailing opponent leaves, and deliberate cross-study transpositions.
  Future<List<ImportResult>> seedPathologicalLibrary(
    StudyRepository repo, {
    required DateTime now,
    int studyCount = 3,
    bool allowComments = true,
  }) async {
    final imports = <ImportResult>[];
    for (var s = 0; s < studyCount; s++) {
      final side = s == 0 ? Side.white : (rng.nextBool() ? Side.white : Side.black);
      final chapterCount = 2 + rng.nextInt(2);
      final pgns = <String>[];
      for (var c = 0; c < chapterCount; c++) {
        final fenIdx = (s == 0 && c == 0) ? 0 : rng.nextInt(_customStartingFens.length);
        final startFen = _customStartingFens[fenIdx];
        pgns.add(
          generateChapterPgn(
            title: 'S${s}_C$c',
            startFen: startFen,
            repertoireSide: side,
            minPlies: 2,
            maxPlies: 5,
            variationProbability: 0.35,
            trailingOpponentProbability: 0.75,
            commentProbability: allowComments ? 0.15 : 0.0,
          ),
        );
      }

      // Inject a cross-study transposition pair on study 0 and study 1 so
      // shared-fenKey and different-expected-move cases always appear.
      if (side == Side.white && s == 0) {
        pgns.add('''
[Event "Transposition A"]
[Orientation "white"]
1. e4 e5 2. Nf3 Nc6 3. Bc4 *
''');
      } else if (side == Side.white && s == 1) {
        pgns.add('''
[Event "Transposition B"]
[Orientation "white"]
1. e4 Nc6 2. Nf3 e5 3. Bb5 *
''');
      }

      final combined = pgns.join('\n\n');
      final res = importPgn(combined, studyTitle: 'Fuzz Study $s', repertoireSide: side);
      if (res.decisions.isEmpty) continue;
      await repo.saveImportResult(res);
      imports.add(res);

      // Randomly deactivate a non-first study on ~25% of seeds to test INV-030.
      if (s >= 2 && rng.nextDouble() < 0.3) {
        await repo.updateStudyActive(res.study.id, false);
      }
    }

    // Seed mixed SRS states (fresh, due, future scheduled, lapsed with reps=0).
    final allDecisions = await repo.getAllDecisions();
    final statesToSave = <PositionKnowledgeState>[];
    final toUnlock = <String>{};
    for (final d in allDecisions) {
      final roll = rng.nextDouble();
      if (roll < 0.35) {
        // Due learned
        final past = now.subtract(Duration(hours: 1 + rng.nextInt(72)));
        statesToSave.add(
          PositionKnowledgeState.fromReviewState(
            ReviewState(
              decisionId: d.id,
              firstReviewedAt: past.subtract(const Duration(days: 2)),
              lastReviewedAt: past.subtract(const Duration(days: 1)),
              repetitionCount: 1 + rng.nextInt(3),
              stability: 86400000.0,
              nextDueAt: past,
            ),
            canonicalId: d.canonicalId,
          ),
        );
      } else if (roll < 0.55) {
        // Future scheduled (not due)
        final future = now.add(Duration(days: 1 + rng.nextInt(10)));
        statesToSave.add(
          PositionKnowledgeState.fromReviewState(
            ReviewState(
              decisionId: d.id,
              firstReviewedAt: now.subtract(const Duration(days: 3)),
              lastReviewedAt: now.subtract(const Duration(days: 1)),
              repetitionCount: 2,
              stability: 259200000.0,
              nextDueAt: future,
            ),
            canonicalId: d.canonicalId,
          ),
        );
      } else if (roll < 0.72) {
        // PR #590 case: lapsed card with repetitionCount == 0 && lapseCount > 0!
        final past = now.subtract(Duration(minutes: 10 + rng.nextInt(300)));
        statesToSave.add(
          PositionKnowledgeState.fromReviewState(
            ReviewState(
              decisionId: d.id,
              firstReviewedAt: now.subtract(const Duration(days: 1)),
              lastReviewedAt: past,
              repetitionCount: 0,
              lapseCount: 1 + rng.nextInt(2),
              stability: 3600000.0,
              nextDueAt: past,
            ),
            canonicalId: d.canonicalId,
          ),
        );
      } else if (roll < 0.85) {
        // Fresh but unlocked in dynamic mode.
        toUnlock.add(d.id);
      }
      // Remaining ~15% stay fresh and locked.
    }
    if (statesToSave.isNotEmpty) {
      await repo.savePositionKnowledgeStates(statesToSave);
    }
    if (toUnlock.isNotEmpty) {
      await repo.unlockDecisions(toUnlock);
    }
    return imports;
  }
}

NormalMove _repertoireToNormalMove(RepertoireMove m) {
  return NormalMove(
    from: Square.fromName(m.from),
    to: Square.fromName(m.to),
    promotion: m.promotion != null ? Role.fromChar(m.promotion!) : null,
  );
}

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Review Invariant & Stateful Property Oracle', () {
    late Database db;
    late SqliteStudyRepository repo;
    late FixedClock clock;

    setUp(() async {
      await TestLichessBinding.instance.sharedPreferences.clear();
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
      repo = SqliteStudyRepository(db);
      clock = FixedClock(DateTime.utc(2026, 11, 12, 10, 0));
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer createMonitoredContainer({
      ReviewOrder order = ReviewOrder.byLine,
      ReviewContinuity continuity = ReviewContinuity.dueOnly,
      TransposeScope transposeScope = TransposeScope.inScope,
      bool dynamicMode = false,
      bool animatePreMove = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider.overrideWithValue(clock),
          soundServiceProvider.overrideWithValue(FakeSoundService()),
          reviewServiceProvider.overrideWith(
            (ref) => ReviewService(
              repository: repo,
              scheduler: ref.watch(schedulerProvider),
              clock: clock,
              reviewOrder: ref.watch(studyPreferencesProvider.select((p) => p.reviewOrder)),
              reviewContinuity: ref.watch(
                studyPreferencesProvider.select((p) => p.reviewContinuity),
              ),
              transposeScope: ref.watch(studyPreferencesProvider.select((p) => p.transposeScope)),
              dynamicRepertoireMode: ref.watch(
                studyPreferencesProvider.select((p) => p.dynamicRepertoireMode),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Apply initial preferences synchronously via notifier after build if needed.
      return container;
    }

    Future<void> configurePrefs(
      ProviderContainer container, {
      ReviewOrder? order,
      ReviewContinuity? continuity,
      TransposeScope? transposeScope,
      bool? dynamicMode,
    }) async {
      final prefs = container.read(studyPreferencesProvider.notifier);
      if (order != null) await prefs.setReviewOrder(order);
      if (continuity != null) await prefs.setReviewContinuity(continuity);
      if (transposeScope != null) await prefs.setTransposeScope(transposeScope);
      if (dynamicMode != null &&
          container.read(studyPreferencesProvider).dynamicRepertoireMode != dynamicMode) {
        await prefs.toggleDynamicRepertoireMode();
      }
    }

    // -----------------------------------------------------------------------
    // 1. Retrospective Bug-Catcher Verification (PR #618)
    //    No hardcoded PGN: generated repertoire with trailing opponent reply +
    //    branch transition carrying an incoming move. Fails on origin/main,
    //    passes with PR #618's fix.
    // -----------------------------------------------------------------------
    test(
      'PR #618 bug-catcher: trailing opponent auto-reply onto incoming-move branch preserves pre-move and lastMove invariants',
      () async {
        final gen = _PathologicalRepertoireGenerator(Random(618));
        // Generate two chapters: chapter 0 ends with an opponent leaf reply,
        // chapter 1 requires an incoming opponent move before the first user prompt.
        final pgnA = gen.generateChapterPgn(
          title: 'Generated Trailing Reply',
          startFen: kInitialFEN,
          repertoireSide: Side.white,
          minPlies: 1,
          maxPlies: 2,
          variationProbability: 0.0,
          trailingOpponentProbability: 1.0,
          commentProbability: 0.0,
        );
        final pgnB = gen.generateChapterPgn(
          title: 'Generated Incoming Branch',
          startFen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
          repertoireSide: Side.white,
          minPlies: 2,
          maxPlies: 3,
          variationProbability: 0.0,
          trailingOpponentProbability: 0.0,
          commentProbability: 0.0,
        );
        final imported = importPgn(
          '$pgnA\n\n$pgnB',
          studyTitle: 'Generated Branch Transition',
          repertoireSide: Side.white,
        );
        await repo.saveImportResult(imported);
        // Mark every decision due so both chapters enter the queue in by-line order.
        final past = clock.now().subtract(const Duration(hours: 2));
        await repo.savePositionKnowledgeStates([
          for (final d in imported.decisions)
            PositionKnowledgeState.fromReviewState(
              ReviewState(
                decisionId: d.id,
                firstReviewedAt: past.subtract(const Duration(days: 1)),
                lastReviewedAt: past,
                repetitionCount: 1,
                stability: 86400000.0,
                nextDueAt: past,
              ),
              canonicalId: d.canonicalId,
            ),
        ]);

        final container = createMonitoredContainer();
        await configurePrefs(container, order: ReviewOrder.byLine);
        final monitor = ReviewInvariantMonitor.attach(container, repository: repo);
        addTearDown(monitor.dispose);

        await container.read(reviewControllerProvider.future);

        var snapshot = await RepertoireOracleSnapshot.capture(repo);
        await monitor.waitAndVerifySettled(snapshot: snapshot);

        // Walk through the generated session playing the expected moves;
        // ReviewInvariantMonitor inspects every emitted frame in real time.
        var safety = 0;
        while (safety++ < 20) {
          final st = container.read(reviewControllerProvider).requireValue;
          if (st.isComplete || st.currentPrompt == null) break;
          final exp = st.currentPrompt!.expectedMoves.first;
          await monitor.playAndVerifyMove(_repertoireToNormalMove(exp), snapshot: snapshot);
          snapshot = await RepertoireOracleSnapshot.capture(repo);
        }
        monitor.assertClean();
      },
    );

    // -----------------------------------------------------------------------
    // 2. Retrospective Bug-Catcher Verification (PR #585: Board-only FEN truth)
    // -----------------------------------------------------------------------
    test(
      'PR #585 oracle: cross-study same-FEN moves, non-due study indexing, and single-ask uniqueness (INV-020, INV-065)',
      () async {
        final studyDue = importPgn(
          '[Event "Line A"]\n1. e4 e5 2. Nf3 Nc6 3. Bc4 *',
          studyTitle: 'Study Due',
          repertoireSide: Side.white,
        );
        final studyNonDue = importPgn(
          '[Event "Line B"]\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *',
          studyTitle: 'Study NonDue',
          repertoireSide: Side.white,
        );
        final studyInactive = importPgn(
          '[Event "Line C"]\n1. e4 e5 2. Nf3 Nc6 3. d4 *',
          studyTitle: 'Study Inactive',
          repertoireSide: Side.white,
        );
        await repo.saveImportResult(studyDue);
        await repo.saveImportResult(studyNonDue);
        await repo.saveImportResult(studyInactive);
        await repo.updateStudyActive(studyInactive.study.id, false);

        final past = clock.now().subtract(const Duration(hours: 2));
        final future = clock.now().add(const Duration(days: 5));
        await repo.savePositionKnowledgeStates([
          for (final d in studyDue.decisions)
            PositionKnowledgeState.fromReviewState(
              ReviewState(
                decisionId: d.id,
                repetitionCount: 1,
                stability: 86400000.0,
                nextDueAt: past,
              ),
              canonicalId: d.canonicalId,
            ),
          for (final d in studyNonDue.decisions)
            if (d.expectedMoves.first.san == 'Bb5')
              PositionKnowledgeState.fromReviewState(
                ReviewState(
                  decisionId: d.id,
                  repetitionCount: 1,
                  stability: 86400000.0,
                  nextDueAt: future,
                ),
                canonicalId: d.canonicalId,
              ),
        ]);

        final container = createMonitoredContainer();
        await configurePrefs(
          container,
          order: ReviewOrder.byLine,
          transposeScope: TransposeScope.inScope,
        );
        final monitor = ReviewInvariantMonitor.attach(container, repository: repo);
        addTearDown(monitor.dispose);

        await container.read(reviewControllerProvider.future);
        var snapshot = await RepertoireOracleSnapshot.capture(repo);
        await monitor.waitAndVerifySettled(snapshot: snapshot);

        // Play 1. e4, then 2. Nf3, reaching 2... Nc6 where Study Due expects Bc4
        // and non-due Study NonDue expects Bb5 (while inactive Study Inactive has d4).
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.e2, to: Square.e4),
          snapshot: snapshot,
        );
        snapshot = await RepertoireOracleSnapshot.capture(repo);
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.g1, to: Square.f3),
          snapshot: snapshot,
        );
        snapshot = await RepertoireOracleSnapshot.capture(repo);

        final atNc6 = container.read(reviewControllerProvider).requireValue;
        expect(atNc6.currentPrompt, isNotNull);
        expect(atNc6.currentPrompt!.expectedMoves.map((m) => m.san), containsAll(['Bc4', 'Bb5']));
        expect(atNc6.currentPrompt!.expectedMoves.map((m) => m.san), isNot(contains('d4')));

        // Inactive study's 3. d4 must be rejected by both oracle and controller.
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.d2, to: Square.d4),
          snapshot: snapshot,
        );
        snapshot = await RepertoireOracleSnapshot.capture(repo);

        // Non-due study's 3. Bb5 must be accepted by both oracle and controller!
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.f1, to: Square.b5),
          snapshot: snapshot,
        );
        monitor.assertClean();
      },
    );

    // -----------------------------------------------------------------------
    // 3. Retrospective Bug-Catcher Verification (PR #590: Dynamic continuity)
    // -----------------------------------------------------------------------
    test(
      'PR #590 oracle: reps=0 lapseCount>0 mid-line cards stay active and alternative branches auto-adopt (INV-022, INV-068)',
      () async {
        final imported = importPgn(
          '''
[Event "Dynamic Line"]
[Orientation "white"]
1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 (3... Nf6 4. d3) 4. c3 *
''',
          studyTitle: 'Dynamic Continuity',
          repertoireSide: Side.white,
        );
        await repo.saveImportResult(imported);

        final past = clock.now().subtract(const Duration(hours: 3));
        final future = clock.now().add(const Duration(days: 5));
        // Decision 0 (1. e4): due
        // Decision 1 (2. Nf3): lapsed with reps=0 && lapseCount=1!
        // Decision 2 (3. Bc4): due
        // Sideline (3... Nf6 -> 4. d3): locked/fresh
        final states = <PositionKnowledgeState>[];
        for (final d in imported.decisions) {
          final san = d.expectedMoves.first.san;
          if (san == 'e4' || san == 'Bc4' || san == 'c3') {
            states.add(
              PositionKnowledgeState.fromReviewState(
                ReviewState(
                  decisionId: d.id,
                  firstReviewedAt: past,
                  lastReviewedAt: past,
                  repetitionCount: 1,
                  stability: 86400000.0,
                  nextDueAt: san == 'c3' ? future : past,
                ),
                canonicalId: d.canonicalId,
              ),
            );
          } else if (san == 'Nf3') {
            states.add(
              PositionKnowledgeState.fromReviewState(
                ReviewState(
                  decisionId: d.id,
                  firstReviewedAt: past,
                  lastReviewedAt: past,
                  repetitionCount: 0,
                  lapseCount: 1,
                  stability: 3600000.0,
                  nextDueAt: past,
                ),
                canonicalId: d.canonicalId,
              ),
            );
          }
        }
        await repo.savePositionKnowledgeStates(states);

        final container = createMonitoredContainer();
        await configurePrefs(
          container,
          order: ReviewOrder.byLine,
          continuity: ReviewContinuity.fullLine,
          dynamicMode: true,
        );
        final monitor = ReviewInvariantMonitor.attach(container, repository: repo);
        addTearDown(monitor.dispose);

        await container.read(reviewControllerProvider.future);
        var snapshot = await RepertoireOracleSnapshot.capture(repo);
        await monitor.waitAndVerifySettled(snapshot: snapshot);

        // 1. e4 -> must NOT skip 2. Nf3 (reps=0, lapseCount=1)!
        final step1 = await monitor.playAndVerifyMove(
          const NormalMove(from: Square.e2, to: Square.e4),
          snapshot: snapshot,
        );
        expect(step1!.nextPrompt?.expectedMoves.first.san, 'Nf3');
        snapshot = await RepertoireOracleSnapshot.capture(repo);

        // 2. Nf3 -> 3. Bc4 -> 4. c3
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.g1, to: Square.f3),
          snapshot: snapshot,
        );
        snapshot = await RepertoireOracleSnapshot.capture(repo);

        // Play 3. Bc4 (or explore sibling if available); fullLine walks 4. c3.
        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.f1, to: Square.c4),
          snapshot: snapshot,
        );
        snapshot = await RepertoireOracleSnapshot.capture(repo);
        final st4 = container.read(reviewControllerProvider).requireValue;
        expect(st4.currentPrompt?.expectedMoves.first.san, 'c3');

        await monitor.playAndVerifyMove(
          const NormalMove(from: Square.c2, to: Square.c3),
          snapshot: snapshot,
        );
        monitor.assertClean();
      },
    );

    // -----------------------------------------------------------------------
    // 4. High-volume Fast Service/Session Differential Fuzzing (25 seeds)
    //    Exercises ReviewService + SqliteStudyRepository + ReviewSession
    //    across all combinations of ReviewOrder, ReviewContinuity,
    //    TransposeScope, dynamicRepertoireMode, ReviewScope, Practice/SRS,
    //    custom [FEN "..."], castling, promotions, and lapses.
    // -----------------------------------------------------------------------
    test(
      'seeded stateful fuzzing over ReviewService + SqliteStudyRepository satisfies all domain/analysis/continuity/FEN-truth invariants (25 seeds)',
      () async {
        const seedCount = 25;
        for (var seed = 1; seed <= seedCount; seed++) {
          final rng = Random(seed * 7919);
          // Fresh DB per seed for full isolation.
          final seedDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
          final batch = seedDb.batch();
          createSrsTables(batch);
          await batch.commit();
          final seedRepo = SqliteStudyRepository(seedDb);

          try {
            final gen = _PathologicalRepertoireGenerator(rng);
            final imports = await gen.seedPathologicalLibrary(
              seedRepo,
              now: clock.now(),
              studyCount: 2 + rng.nextInt(2),
            );
            if (imports.isEmpty) continue;

            final order = ReviewOrder.values[rng.nextInt(ReviewOrder.values.length)];
            final continuity = ReviewContinuity.values[rng.nextInt(ReviewContinuity.values.length)];
            final transposeScope = TransposeScope.values[rng.nextInt(TransposeScope.values.length)];
            final dynamicMode = rng.nextBool();
            final mode = rng.nextDouble() < 0.2 ? ReviewMode.practice : ReviewMode.srs;
            final scopeChoices = <ReviewScope>[
              const ReviewScope.all(),
              const ReviewScope.white(),
              const ReviewScope.black(),
              ReviewScope.study(imports.first.study.id),
            ];
            final scope = scopeChoices[rng.nextInt(scopeChoices.length)];
            final dailyQuota = rng.nextDouble() < 0.3 ? (2 + rng.nextInt(4)) : null;
            final newQuota = rng.nextDouble() < 0.3 ? (1 + rng.nextInt(3)) : null;

            final service = ReviewService(
              repository: seedRepo,
              clock: clock,
              reviewOrder: order,
              reviewContinuity: continuity,
              transposeScope: transposeScope,
              dynamicRepertoireMode: dynamicMode,
            );

            final session = await service.startSession(
              scope: scope,
              mode: mode,
              remainingDailyQuota: dailyQuota,
              remainingNewQuota: newQuota,
            );

            final answeredCorrectlyFens = <String>{};
            final requeuedCanonicalIds = <String>{};
            var snapshot = await RepertoireOracleSnapshot.capture(seedRepo);

            for (var step = 0; step < 30; step++) {
              final prompt = session.currentPrompt;
              if (prompt == null || session.isComplete) break;

              final promptPos = Chess.fromSetup(Setup.parseFen(normalizeFen(prompt.fen)));
              final oracle = BoardTruthOracle(
                snapshot: snapshot,
                scope: scope,
                transposeScope: transposeScope,
              );

              // Multi-study duplicate FEN check (INV-020, INV-065).
              final activeStudyCount = snapshot.studies.where((s) => s.isActive).length;
              final isMultiStudyGeneral =
                  scope.studyId == null &&
                  scope.chapterId == null &&
                  activeStudyCount > 1 &&
                  mode == ReviewMode.srs &&
                  transposeScope == TransposeScope.inScope;
              final lapsedIds = session.checkpoint().lapsedDecisionIds;
              final isLapsedReTest = lapsedIds.contains(prompt.decision.canonicalId);
              if (isMultiStudyGeneral &&
                  !isLapsedReTest &&
                  !requeuedCanonicalIds.contains(prompt.decision.canonicalId)) {
                expect(
                  answeredCorrectlyFens.contains(prompt.fenKey),
                  isFalse,
                  reason:
                      '[seed=$seed step=$step] Duplicate fenKey ${prompt.fenKey} prompted in multi-study general review',
                );
              }

              // Expected moves differential check.
              final oracleExpected = oracle.expectedMergedMoves(prompt);
              for (final m in oracleExpected) {
                expect(
                  prompt.expectedMoves.any((p) => p.matches(m)),
                  isTrue,
                  reason: '[seed=$seed step=$step] Missing expected move $m at ${prompt.fenKey}',
                );
              }
              for (final exp in prompt.expectedMoves) {
                expect(
                  playableNormalMove(promptPos, _repertoireToNormalMove(exp)),
                  isNotNull,
                  reason: '[seed=$seed step=$step] Illegal expected move $exp at ${prompt.fen}',
                );
              }

              // Open-in-Analysis fidelity check on every prompt!
              final syntheticState = ReviewScreenState(
                studies: snapshot.studies,
                scope: scope,
                totalDueCount: 0,
                totalFreshCount: 0,
                studyDueCounts: const {},
                session: session,
                currentPrompt: prompt,
                boardPosition: promptPos,
                boardOrientation: prompt.sideToMove,
                mode: mode,
              );
              verifyOpenInAnalysisFidelity(syntheticState);

              // Pick an adversarial action: skip, wrong move, alternative/transposed move, or primary move.
              final actionRoll = rng.nextDouble();
              if (actionRoll < 0.08) {
                requeuedCanonicalIds.add(prompt.decision.canonicalId);
                session.skip();
                continue;
              }

              final legal = _PathologicalRepertoireGenerator._allLegalMoves(promptPos);
              NormalMove chosenMove;
              if (actionRoll < 0.25) {
                // Deliberately pick an out-of-scope / wrong move if one exists.
                final wrong = legal.where(
                  (m) =>
                      !oracle.isMoveAccepted(prompt: prompt, boardPosition: promptPos, played: m),
                );
                chosenMove = wrong.isNotEmpty
                    ? wrong.elementAt(rng.nextInt(wrong.length))
                    : _repertoireToNormalMove(prompt.expectedMoves.first);
              } else {
                // Pick an accepted move (preferring non-primary / transposed moves when available).
                final accepted = legal
                    .where(
                      (m) => oracle.isMoveAccepted(
                        prompt: prompt,
                        boardPosition: promptPos,
                        played: m,
                      ),
                    )
                    .toList();
                final alternatives = accepted.where(
                  (m) =>
                      !prompt.decision.expectedMoves.any((e) => normalMoveMatchesRepertoire(m, e)),
                );
                if (alternatives.isNotEmpty && rng.nextDouble() < 0.65) {
                  chosenMove = alternatives.elementAt(rng.nextInt(alternatives.length));
                } else {
                  chosenMove = _repertoireToNormalMove(
                    prompt.expectedMoves[rng.nextInt(prompt.expectedMoves.length)],
                  );
                  // Randomly test standard castling UCI e1g1/e1c1/e8g8/e8c8 when castling!
                  final altCastle = altCastles[chosenMove.uci];
                  if (altCastle != null && rng.nextBool()) {
                    chosenMove = Move.parse(altCastle)! as NormalMove;
                  }
                }
              }

              final expectedAccepted = oracle.isMoveAccepted(
                prompt: prompt,
                boardPosition: promptPos,
                played: chosenMove,
              );
              final stepResult = await service.submitMove(
                from: chosenMove.from.name,
                to: chosenMove.to.name,
                promotion: chosenMove.promotion?.letter,
              );
              expect(
                stepResult.isCorrect,
                expectedAccepted,
                reason:
                    '[seed=$seed step=$step] Grading mismatch on ${chosenMove.uci} at ${prompt.fenKey} '
                    '(scope=$scope transpose=$transposeScope): expected=$expectedAccepted',
              );

              if (stepResult.isCorrect) {
                final isLapsed = session.checkpoint().lapsedDecisionIds.contains(
                  prompt.decision.canonicalId,
                );
                if (!isLapsed) {
                  requeuedCanonicalIds.remove(prompt.decision.canonicalId);
                  answeredCorrectlyFens.add(prompt.fenKey);
                }

                // FullLine continuity path oracle: no user move may be auto-played!
                if (continuity == ReviewContinuity.fullLine) {
                  expect(
                    stepResult.autoPlayedMoves.where((m) => m.isUserMove),
                    isEmpty,
                    reason: '[seed=$seed step=$step] fullLine auto-played a user move',
                  );
                }

                // Dynamic mode branch adoption persistence check.
                if (mode == ReviewMode.srs &&
                    dynamicMode &&
                    stepResult.adoptedDecisionIds.isNotEmpty) {
                  final unlocked = await seedRepo.getUnlockedDecisionIds();
                  expect(unlocked, containsAll(stepResult.adoptedDecisionIds));
                }
              } else {
                requeuedCanonicalIds.add(prompt.decision.canonicalId);
                // Verify lapse Open-in-Analysis fidelity too!
                final lapseState = syntheticState.copyWith(
                  feedback: ReviewFeedback.incorrect,
                  expectedMove: stepResult.expectedMoves.firstOrNull,
                  isLapseAcknowledged: false,
                );
                verifyOpenInAnalysisFidelity(lapseState);

                if (rng.nextBool()) {
                  service.continueAfterIncorrect();
                } else {
                  // Retry with a correct move (sometimes transposed/castling).
                  final retryMove = _repertoireToNormalMove(prompt.expectedMoves.first);
                  final retryRes = await service.retryMove(
                    from: retryMove.from.name,
                    to: retryMove.to.name,
                    promotion: retryMove.promotion?.letter,
                  );
                  expect(retryRes.isCorrect, isTrue);
                }
              }

              snapshot = await RepertoireOracleSnapshot.capture(seedRepo);
            }
          } finally {
            await seedDb.close();
          }
        }
      },
    );

    // -----------------------------------------------------------------------
    // 5. End-to-End ReviewController + ReviewInvariantMonitor Fuzzing
    //    Exercises real async timers (_executeAdvancement, _playIncomingPreMove,
    //    cancelPreMoveAnimation), lapses, skips, scope switches, and settings
    //    toggles across multiple deterministic seeds.
    // -----------------------------------------------------------------------
    test(
      'seeded ReviewController stateful fuzzing satisfies real-time frame and state-machine invariants',
      () async {
        for (final seed in const [101, 202, 303]) {
          final seedDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
          final batch = seedDb.batch();
          createSrsTables(batch);
          await batch.commit();
          final seedRepo = SqliteStudyRepository(seedDb);

          final rng = Random(seed);
          final gen = _PathologicalRepertoireGenerator(rng);
          final imports = await gen.seedPathologicalLibrary(
            seedRepo,
            now: clock.now(),
            studyCount: 2,
          );

          final container = ProviderContainer(
            overrides: [
              srsStudyRepositoryProvider.overrideWith((ref) => seedRepo),
              clockProvider.overrideWithValue(clock),
              soundServiceProvider.overrideWithValue(FakeSoundService()),
              reviewServiceProvider.overrideWith(
                (ref) => ReviewService(
                  repository: seedRepo,
                  scheduler: ref.watch(schedulerProvider),
                  clock: clock,
                  reviewOrder: ref.watch(studyPreferencesProvider.select((p) => p.reviewOrder)),
                  reviewContinuity: ref.watch(
                    studyPreferencesProvider.select((p) => p.reviewContinuity),
                  ),
                  transposeScope: ref.watch(
                    studyPreferencesProvider.select((p) => p.transposeScope),
                  ),
                  dynamicRepertoireMode: ref.watch(
                    studyPreferencesProvider.select((p) => p.dynamicRepertoireMode),
                  ),
                ),
              ),
            ],
          );

          final monitor = ReviewInvariantMonitor.attach(container, repository: seedRepo);
          try {
            await configurePrefs(
              container,
              order: ReviewOrder.byLine,
              continuity: seed.isOdd ? ReviewContinuity.fullLine : ReviewContinuity.dueOnly,
              transposeScope: TransposeScope.inScope,
              dynamicMode: seed == 202,
            );
            await container.read(reviewControllerProvider.future);
            final controller = container.read(reviewControllerProvider.notifier);

            var snapshot = await RepertoireOracleSnapshot.capture(seedRepo);
            await monitor.waitAndVerifySettled(snapshot: snapshot);

            for (var step = 0; step < 8; step++) {
              final state = container.read(reviewControllerProvider).requireValue;
              if (state.isComplete || state.currentPrompt == null) {
                // Switch to practice or another study scope to keep fuzzing transitions.
                if (rng.nextBool() && imports.isNotEmpty) {
                  await controller.changeScope(ReviewScope.study(imports.first.study.id));
                } else {
                  await controller.startPracticeMode();
                }
                snapshot = await RepertoireOracleSnapshot.capture(seedRepo);
                await monitor.waitAndVerifySettled(snapshot: snapshot);
                continue;
              }

              final prompt = state.currentPrompt!;
              final roll = rng.nextDouble();
              if (roll < 0.15) {
                monitor.noteSkip(prompt.decision.canonicalId);
                controller.skip();
                await monitor.waitAndVerifySettled(snapshot: snapshot);
              } else if (roll < 0.30) {
                // Play a wrong move, then either retry or acknowledgeLapse.
                final promptPos = Chess.fromSetup(Setup.parseFen(normalizeFen(prompt.fen)));
                final oracle = BoardTruthOracle(
                  snapshot: snapshot,
                  scope: state.scope,
                  transposeScope: state.session!.transposeScope,
                );
                final wrong = _PathologicalRepertoireGenerator._allLegalMoves(promptPos).where(
                  (m) =>
                      !oracle.isMoveAccepted(prompt: prompt, boardPosition: promptPos, played: m),
                );
                if (wrong.isNotEmpty) {
                  await monitor.playAndVerifyMove(wrong.first, snapshot: snapshot);
                  if (rng.nextBool()) {
                    controller.acknowledgeLapse();
                    await monitor.waitAndVerifySettled(snapshot: snapshot);
                  } else {
                    await monitor.playAndVerifyMove(
                      _repertoireToNormalMove(prompt.expectedMoves.first),
                      snapshot: snapshot,
                    );
                  }
                }
              } else {
                // Play a valid move (occasionally toggling animateOpponentPreMove or selecting side).
                await monitor.playAndVerifyMove(
                  _repertoireToNormalMove(prompt.expectedMoves.first),
                  snapshot: snapshot,
                );
                if (step == 3) {
                  await controller.selectSide(
                    state.activeSide == Side.white ? Side.black : Side.white,
                  );
                  await monitor.waitAndVerifySettled(snapshot: snapshot);
                }
              }
              snapshot = await RepertoireOracleSnapshot.capture(seedRepo);
            }
            monitor.assertClean();
          } finally {
            monitor.dispose();
            container.dispose();
            await seedDb.close();
          }
        }
      },
    );

    // -----------------------------------------------------------------------
    // 6. Widget-level ReviewScreen + ChessboardController + Monitor check
    // -----------------------------------------------------------------------
    testWidgets(
      'ReviewScreen widget tree keeps rendered Chessboard lastMove and pieces coherent with ReviewInvariantMonitor',
      (tester) async {
        final imported = importPgn(
          '''
[Event "Branch A"]
[Orientation "white"]
1. e4 e5 *

[Event "Branch B"]
[Orientation "white"]
[SetUp "1"]
[FEN "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"]
1... d5 2. c4 *
''',
          studyTitle: 'Widget Oracle Study',
          repertoireSide: Side.white,
        );
        await tester.runAsync(() async {
          await repo.saveImportResult(imported);
        });

        final app = await makeTestProviderScopeApp(
          tester,
          home: const ReviewScreen(),
          overrides: {
            srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
            clockProvider: clockProvider.overrideWithValue(clock),
            reviewServiceProvider: reviewServiceProvider.overrideWith(
              (ref) =>
                  ReviewService(repository: repo, clock: clock, reviewOrder: ReviewOrder.byLine),
            ),
          },
        );

        await tester.pumpWidget(app);
        await pumpUntilFound(tester, find.byType(Chessboard));

        final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScreen)));
        final monitor = ReviewInvariantMonitor.attach(container, repository: repo);
        addTearDown(monitor.dispose);

        final snapshot = (await tester.runAsync(() => RepertoireOracleSnapshot.capture(repo)))!;
        await pumpAsyncUntil(tester, () {
          final st = container.read(reviewControllerProvider).value;
          return st?.currentPrompt != null &&
              st?.boardPosition?.fen == normalizeFen(st!.currentPrompt!.fen);
        });
        monitor.assertClean();
        monitor.verifySettledState(
          container.read(reviewControllerProvider).requireValue,
          snapshot: snapshot,
        );

        // Play 1. e4 on the rendered board; opponent auto-replies 1... e5 (leaf),
        // transitioning to Branch B (1... d5 pre-move -> 2. c4).
        await playMove(tester, 'e2', 'e4');
        await pumpAsyncUntil(tester, () {
          final st = container.read(reviewControllerProvider).value;
          final prompt = st?.currentPrompt;
          if (prompt == null) return false;
          return prompt.expectedMoves.any((m) => m.san == 'c4') &&
              st?.boardPosition?.fen == normalizeFen(prompt.fen) &&
              st?.lastMove != null;
        });

        monitor.assertClean();
        final settled = container.read(reviewControllerProvider).requireValue;
        monitor.verifySettledState(settled, snapshot: snapshot);
        expect(getBoardLastMove(tester), settled.lastMove);
      },
    );
  });
}
