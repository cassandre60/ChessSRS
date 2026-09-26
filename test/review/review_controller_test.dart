// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' as lichess_study;
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';
import '../model/common/service/fake_sound_service.dart';
import 'gated_study_repository.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ReviewController', () {
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
      clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
    });

    tearDown(() async {
      await db.close();
    });

    ProviderContainer createContainer({
      List<Override> extraOverrides = const [],
      StudyRepository? repository,
      FakeSoundService? soundService,
    }) {
      // The service and the repository provider must be handed the same instance: the service
      // reads through whatever repository it was built with, and a test that gates one but not
      // the other would be gating a call the session start never makes.
      final store = repository ?? repo;
      final container = ProviderContainer(
        overrides: [
          srsStudyRepositoryProvider.overrideWith((ref) => store),
          clockProvider.overrideWithValue(clock),
          soundServiceProvider.overrideWithValue(soundService ?? FakeSoundService()),
          reviewServiceProvider.overrideWith(
            (ref) => ReviewService(
              repository: store,
              scheduler: ref.watch(schedulerProvider),
              clock: clock,
            ),
          ),
          ...extraOverrides,
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('refuses an import with nothing in it instead of storing an untrainable study', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await expectLater(
        controller.importPgnText(pgnText: '', title: 'Empty'),
        throwsA(isA<FormatException>()),
        reason: 'a study with no positions is not reviewable and must not be persisted',
      );

      final studies = await repo.getAllStudies();
      expect(
        studies.where((s) => s.title == 'Empty'),
        isEmpty,
        reason: 'the failed import left a study behind',
      );
    });

    test('still stores an import that produced positions alongside errors', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Illegal move after a real opening: the usable part must survive.
      const partial = '1. e4 e5 2. Nf3 Qxh8 *';
      final result = await controller.importPgnText(pgnText: partial, title: 'Partial');

      expect(result.errors, isNotEmpty, reason: 'the illegal move should be reported');
      expect(result.decisions, isNotEmpty, reason: 'the moves before the error are usable');
      final studies = await repo.getAllStudies();
      expect(studies.where((s) => s.title == 'Partial'), hasLength(1));
    });

    test('the same tree imported for the other side is a different repertoire', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '1. e4 e5 2. Nf3 Nc6 *';

      final white = await controller.importPgnText(
        pgnText: pgn,
        title: 'Openings',
        repertoireSide: Side.white,
      );
      final black = await controller.importPgnText(
        pgnText: pgn,
        title: 'Openings',
        repertoireSide: Side.black,
      );

      expect(
        black.isDuplicate,
        isFalse,
        reason: 'White and Black repertoires are different questions and different SRS memory',
      );
      expect(
        black.study.id,
        isNot(equals(white.study.id)),
        reason: 'the Black import was silently redirected to the White study',
      );

      final whiteMoves = (await repo.getDecisionsByStudy(
        white.study.id,
      )).map((d) => d.expectedMoves.first.san).toList();
      final blackMoves = (await repo.getDecisionsByStudy(
        black.study.id,
      )).map((d) => d.expectedMoves.first.san).toList();

      expect(whiteMoves, isNotEmpty);
      expect(blackMoves, isNotEmpty);
      expect(
        whiteMoves.toSet().intersection(blackMoves.toSet()),
        isEmpty,
        reason: "the two sides must not be trained on each other's moves",
      );
    });

    test('duplicate detection still works for a PGN past the offload threshold', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Past the 8KiB threshold the hash is computed on a worker isolate. The value it returns
      // has to be the same one the synchronous path produced, or every large re-import stops
      // being recognised as a duplicate.
      final filler = List.generate(1500, (i) => ';note $i').join('\n');
      final bigPgn = '[Event "Big"]\n\n$filler\n\n1. e4 e5 2. Nf3 Nc6 *';

      expect(bigPgn.length, greaterThan(8192));

      final first = await controller.importPgnText(
        pgnText: bigPgn,
        title: 'Big',
        repertoireSide: Side.white,
      );
      final second = await controller.importPgnText(
        pgnText: bigPgn,
        title: 'Big',
        repertoireSide: Side.white,
      );

      expect(first.isDuplicate, isFalse);
      expect(
        second.isDuplicate,
        isTrue,
        reason: 'the worker-computed hash must match the stored one',
      );
      expect(second.study.id, equals(first.study.id));
    });

    test('a duplicate import is reported as up to date, not rejected as empty', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '1. e4 e5 *';
      final first = await controller.importPgnText(
        pgnText: pgn,
        title: 'King Pawn',
        repertoireSide: Side.white,
      );
      final second = await controller.importPgnText(
        pgnText: pgn,
        title: 'King Pawn',
        repertoireSide: Side.white,
      );

      // A duplicate legitimately carries no chapters and no decisions — nothing was imported
      // because the study is already there. That must not read as an import that found nothing.
      expect(first.isDuplicate, isFalse);
      expect(second.isDuplicate, isTrue);
      expect(second.study.id, equals(first.study.id));
    });

    test('initializes with empty repository: 0 studies, no prompt', () async {
      final container = createContainer();
      final state = await container.read(reviewControllerProvider.future);

      expect(state.hasStudies, isFalse);
      expect(state.studies, isEmpty);
      expect(state.totalDueCount, 0);
      expect(state.currentPrompt, isNull);
      expect(state.boardPosition, isNull);
    });

    test('imports PGN, initializes session with due prompt and board orientation', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Import French Defence for Black
      const pgn = '''
[Event "French Defence"]
[Site "?"]
[Date "2026.09.16"]
[Round "1"]
[White "Opponent"]
[Black "Hero"]
[Result "*"]

1. e4 e6 2. d4 d5 *
''';

      final importResult = await controller.importPgnText(
        pgnText: pgn,
        title: 'French Defence',
        repertoireSide: Side.black,
      );

      expect(importResult.decisions.length, 2); // e6 and d5 for Black

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.hasStudies, isTrue);
      expect(state.scope, ReviewScope.study(importResult.study.id));
      expect(state.totalDueCount, 2);
      expect(state.currentPrompt, isNotNull);
      expect(state.boardOrientation, Side.black);
      expect(state.boardPosition, isNotNull);

      // Pre-move animation: starts at parent position (White's turn before 1. e4),
      // then animates White's 1. e4 onto the board so Black sees opponent's move!
      expect(state.boardPosition!.turn, Side.white);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final stateAfterPreMove = container.read(reviewControllerProvider).requireValue;
      expect(stateAfterPreMove.boardPosition!.turn, Side.black);
      expect(stateAfterPreMove.lastMove, const NormalMove(from: Square.e2, to: Square.e4));
    });

    test('handles correct move and advances queue', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Italian Game"]
1. e4 e5 2. Nf3 Nc6 *
''';

      await controller.importPgnText(pgnText: pgn, title: 'Italian', repertoireSide: Side.white);

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 2);
      expect(state.boardOrientation, Side.white);

      // Play 1. e4
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));

      expect(result, isNotNull);
      expect(result!.isCorrect, isTrue);

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.none);
      expect(state.totalDueCount, 1);
      // Auto-traversal played 1... e5, so next prompt is for 2. Nf3
      expect(state.currentPrompt, isNotNull);
      expect(state.currentPrompt!.expectedMoves.first.san, 'Nf3');
    });

    test('handles incorrect move (lapse) and allows user to reguess on the board', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Queen Pawn"]
1. d4 d5 *
''';

      await controller.importPgnText(pgnText: pgn, title: 'Queen Pawn', repertoireSide: Side.white);

      // Play wrong move 1. e4 instead of 1. d4
      final result1 = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));

      expect(result1, isNotNull);
      expect(result1!.isCorrect, isFalse);

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.incorrect);
      expect(state.expectedMove, isNotNull);
      expect(state.expectedMove!.san, 'd4');

      // Reguess on board with correct move 1. d4
      final result2 = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));

      expect(result2, isNotNull);
      expect(result2!.isCorrect, isTrue);

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.none);
      expect(state.expectedMove, isNull);
    });

    // `design/docs/02-tokens.md` §6: "Play `move` for both the user's and the opponent's
    // piece landing." The opponent's reply already sounded; the user's own landing did not.
    //
    // The line deliberately ends after 1. d4 so there is no opponent reply. An earlier
    // version of this test used "1. d4 d5" and asserted `>= 1`, which passed even with the
    // hook removed: the reply sounds too, so the assertion could not tell the two apart.
    // With no reply, exactly one move sound can only be the user's own landing.
    test('a correct move by the user plays the move sound', () async {
      final sound = FakeSoundService();
      final container = createContainer(soundService: sound);
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 *',
        title: 'One move',
        repertoireSide: Side.white,
      );
      await container.read(reviewControllerProvider.future);

      expect(sound.themeSounds, isEmpty, reason: 'nothing has been played yet');

      await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(
        sound.countTheme(Sound.move),
        1,
        reason:
            "the line has no opponent reply, so the only move sound can be the user's "
            'own landing',
      );
    });

    // A second wrong attempt is still a rejected move, and used to pass unacknowledged
    // because only the first attempt's rejection was wired.
    test('a failed reguess plays the wrong sound again', () async {
      final sound = FakeSoundService();
      final container = createContainer(soundService: sound);
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await container.read(reviewControllerProvider.future);

      // Wrong, then wrong again.
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(sound.countOf(ReviewSound.wrong), 1);

      await controller.onUserMove(const NormalMove(from: Square.c7, to: Square.c6));

      expect(
        sound.countOf(ReviewSound.wrong),
        2,
        reason: 'the reguess was rejected too, so it should be heard',
      );
    });

    // `design/docs/02-tokens.md` §6: "Play ... `wrong` on a rejected move."
    test('a rejected move plays the wrong sound', () async {
      final sound = FakeSoundService();
      final container = createContainer(soundService: sound);
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await container.read(reviewControllerProvider.future);

      expect(
        sound.reviewSounds,
        isEmpty,
        reason: 'nothing has been rejected yet, so nothing should sound',
      );

      // 1. e4 where the repertoire has 1. d4.
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result!.isCorrect, isFalse);

      expect(sound.countOf(ReviewSound.wrong), 1);
    });

    // `design/docs/02-tokens.md` §6: "`done` when reaching 'Nothing due'."
    test('running the queue out plays the done sound exactly once', () async {
      final sound = FakeSoundService();
      final container = createContainer(soundService: sound);
      final controller = container.read(reviewControllerProvider.notifier);

      // One decision only, so reviewing it empties the queue.
      await controller.importPgnText(
        pgnText: '1. d4 *',
        title: 'One move',
        repertoireSide: Side.white,
      );
      await container.read(reviewControllerProvider.future);

      expect(
        container.read(reviewControllerProvider).requireValue.isComplete,
        isFalse,
        reason: 'there is still a due position, so the session is not over',
      );
      expect(sound.countOf(ReviewSound.done), 0);

      await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(container.read(reviewControllerProvider).requireValue.isComplete, isTrue);
      expect(
        sound.countOf(ReviewSound.done),
        1,
        reason:
            'the state is re-emitted while the session stays finished; done is the edge, '
            'not the level, so it must not repeat',
      );
    });

    // A cold start with nothing in the database must stay quiet. `isComplete` already
    // requires studies to exist, so this guards the guard: without that conjunct the first
    // emission of an empty app would satisfy isComplete and sound done on launch.
    test('an empty app does not play the done sound on startup', () async {
      final sound = FakeSoundService();
      final container = createContainer(soundService: sound);

      await container.read(reviewControllerProvider.future);

      expect(container.read(reviewControllerProvider).requireValue.isComplete, isFalse);
      expect(sound.reviewSounds, isEmpty);
    });

    test(
      'handles incorrect move (lapse), shows expected move, and continues on acknowledge',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '''
[Event "Queen Pawn"]
1. d4 d5 *
''';

        await controller.importPgnText(
          pgnText: pgn,
          title: 'Queen Pawn',
          repertoireSide: Side.white,
        );

        // Play wrong move 1. e4 instead of 1. d4
        final result = await controller.onUserMove(
          const NormalMove(from: Square.e2, to: Square.e4),
        );

        expect(result, isNotNull);
        expect(result!.isCorrect, isFalse);

        var state = container.read(reviewControllerProvider).requireValue;
        expect(state.feedback, ReviewFeedback.incorrect);
        expect(state.expectedMove, isNotNull);
        expect(state.expectedMove!.san, 'd4');
        expect(state.isLapseAcknowledged, isFalse);

        // Acknowledge lapse
        controller.acknowledgeLapse();
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.feedback, ReviewFeedback.none);
        expect(state.expectedMove, isNull);
        expect(state.isLapseAcknowledged, isTrue);
      },
    );

    test('skip moves current prompt to back of queue', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn1 = '1. e4 e5 *';
      const pgn2 = '1. d4 d5 *';

      await controller.importPgnText(pgnText: pgn1, title: 'Open', repertoireSide: Side.white);
      await controller.importPgnText(pgnText: pgn2, title: 'Closed', repertoireSide: Side.white);
      await controller.changeScope(const ReviewScope.all());

      final firstPrompt = container.read(reviewControllerProvider).requireValue.currentPrompt;
      controller.skip();

      final skippedPrompt = container.read(reviewControllerProvider).requireValue.currentPrompt;
      expect(skippedPrompt, isNotNull);
      expect(skippedPrompt!.decision.id, isNot(firstPrompt!.decision.id));
    });

    test('toggleStudyActive updates study status and recalculates all-scope queue', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'Open',
        repertoireSide: Side.white,
      );
      final res2 = await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Closed',
        repertoireSide: Side.white,
      );

      await controller.changeScope(const ReviewScope.all());
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 2);

      // Suspend the 'Closed' study from daily review pool
      await controller.toggleStudyActive(res2.study.id, false);

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 1);
      final updatedStudies = state.studies;
      expect(updatedStudies.firstWhere((s) => s.id == res2.study.id).isActive, isFalse);
    });

    test(
      'a scope change overtaken mid-load leaves the board and the grader on the same session',
      () async {
        final gated = GatedStudyRepository(db);
        final container = createContainer(repository: gated);
        final controller = container.read(reviewControllerProvider.notifier);

        final open = await controller.importPgnText(
          pgnText: '1. e4 e5 *',
          title: 'Open',
          repertoireSide: Side.white,
        );
        final closed = await controller.importPgnText(
          pgnText: '1. d4 d5 *',
          title: 'Closed',
          repertoireSide: Side.white,
        );

        // Hold the first scope change open inside the repository, then ask for the second one.
        // The user tapped 'Closed' last, so 'Closed' is the session the screen shows and the
        // session every move has to be graded against.
        gated.gatedStudyId = open.study.id;
        gated.gate = Completer<void>();
        gated.reachedGate = Completer<void>();

        final overtaken = controller.changeScope(ReviewScope.study(open.study.id));
        await gated.reachedGate!.future;

        await controller.changeScope(ReviewScope.study(closed.study.id));

        gated.gate!.complete();
        await overtaken;

        final state = container.read(reviewControllerProvider).requireValue;
        final service = container.read(reviewServiceProvider);

        expect(state.scope, ReviewScope.study(closed.study.id));
        expect(
          service.activeSession!.scope,
          ReviewScope.study(closed.study.id),
          reason: 'the session that grades moves must be the one the user last asked for',
        );
        // The two halves of the review are separate objects: the state carries the session the
        // board renders, and the service holds the one that decides right from wrong. If they
        // are not the same session the board looks correct while every answer is graded against
        // a different position, which is the failure this guards.
        expect(
          state.session,
          same(service.activeSession),
          reason: 'screen and grader disagreed on which session is current',
        );
      },
    );

    test(
      'renameStudy updates title in-place without setting loading or resetting session',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        final res = await controller.importPgnText(
          pgnText: '1. e4 e5 *',
          title: 'Original Title',
          repertoireSide: Side.white,
        );

        final stateBefore = container.read(reviewControllerProvider).requireValue;
        expect(stateBefore.studies.first.title, 'Original Title');
        final promptBefore = stateBefore.currentPrompt;

        // Rename study
        await controller.renameStudy(res.study.id, 'Renamed Title');

        final asyncState = container.read(reviewControllerProvider);
        expect(asyncState.isLoading, isFalse);
        expect(asyncState.hasValue, isTrue);
        final stateAfter = asyncState.requireValue;
        expect(stateAfter.studies.first.title, 'Renamed Title');
        // Prompt and session remain stable
        expect(stateAfter.currentPrompt?.decision.id, promptBefore?.decision.id);
      },
    );

    test('startPracticeMode trains study without updating SRS review states', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final res = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 Nc6 *',
        title: 'Openings',
        repertoireSide: Side.white,
      );

      // Complete all items in normal review so due count is 0
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);
      expect(state.isComplete, isTrue);

      // Enter Practice Mode (Cram)
      await controller.startPracticeMode(scope: ReviewScope.study(res.study.id));

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isPracticeMode, isTrue);
      expect(state.isComplete, isFalse);
      expect(state.currentPrompt, isNotNull);

      // Exit Practice Mode
      await controller.exitPracticeMode();
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isPracticeMode, isFalse);
      expect(state.isComplete, isTrue);
    });

    test('branch transition plays opponent pre-move when line changes', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Repertoire for White with 2 branches:
      // Line 1: 1. e4 e5 2. Nf3
      // Line 2: 1. e4 c5 2. Nf3
      const pgn = '1. e4 e5 (1... c5 2. Nf3) 2. Nf3 *';
      await controller.importPgnText(
        pgnText: pgn,
        title: 'Two Branches',
        repertoireSide: Side.white,
      );

      // Prompt 1: 1. e4 (at initial position, incomingMove is null)
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);
      expect(state.currentPrompt!.incomingMove, isNull);

      // User plays 1. e4
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      // Auto-reply plays 1... e5
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // User plays 2. Nf3 to complete branch 1
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Now transitioning to the other branch: White to play against opponent's response.
      // Initially, board is at parent position (before opponent's move)
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);
      final incoming = state.currentPrompt!.incomingMove;
      expect(incoming, isNotNull);

      // Wait for pre-move animation of the opponent's incoming branch move
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final stateAfterPreMove = container.read(reviewControllerProvider).requireValue;
      expect(
        stateAfterPreMove.lastMove,
        NormalMove(from: Square.fromName(incoming!.from), to: Square.fromName(incoming.to)),
      );
    });

    test('acknowledgeLapse (skip after error) plays opponent pre-move on next prompt', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Repertoire for Black: White plays 1. e4 (Prompt 1: 1... e6)
      // Then next line: White plays 1. d4 (Prompt 2: 1... d5)
      const pgn = '''
[Event "French"]
1. e4 e6 *

[Event "Queen Pawn"]
1. d4 d5 *
''';
      await controller.importPgnText(
        pgnText: pgn,
        title: 'Black Repertoire',
        repertoireSide: Side.black,
      );

      // Wait for pre-move of Prompt 1
      await Future<void>.delayed(const Duration(milliseconds: 400));
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);

      // User plays wrong move
      await controller.onUserMove(const NormalMove(from: Square.a7, to: Square.a6));
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.incorrect);

      // User taps "Skip" after error (calls acknowledgeLapse)
      controller.acknowledgeLapse();
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.none);
      expect(state.isLapseAcknowledged, isTrue);

      // Next prompt has an incoming move (White's move)
      final nextIncoming = state.currentPrompt?.incomingMove;
      expect(nextIncoming, isNotNull);

      // Wait for pre-move animation of White's move onto the board
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final stateAfter = container.read(reviewControllerProvider).requireValue;
      expect(
        stateAfter.lastMove,
        NormalMove(from: Square.fromName(nextIncoming!.from), to: Square.fromName(nextIncoming.to)),
      );
    });

    test('user playing O-O on board is accepted when expected move is castling', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      // Simple Italian line where White castles O-O:
      // 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O *
      const pgn = '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O *';
      await controller.importPgnText(
        pgnText: pgn,
        title: 'Castling Test',
        repertoireSide: Side.white,
      );

      // Move 1: 1. e4
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // Move 2: 2. Nf3
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // Move 3: 3. Bc4
      await controller.onUserMove(const NormalMove(from: Square.f1, to: Square.c4));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // Move 4: User plays O-O by dragging King from e1 to g1 on board!
      final result = await controller.onUserMove(const NormalMove(from: Square.e1, to: Square.g1));
      expect(result, isNotNull);
      expect(result!.isCorrect, isTrue);
      expect(container.read(reviewControllerProvider).requireValue.feedback, ReviewFeedback.none);
    });

    test(
      'correct move with annotations pauses auto-advancement and advances on continueAdvancement',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '1. e4 {[%cal Ge4d5] Controls d5} e5 2. Nf3 *';
        await controller.importPgnText(
          pgnText: pgn,
          title: 'King Pawn Annotated',
          repertoireSide: Side.white,
        );

        var state = container.read(reviewControllerProvider).requireValue;
        expect(state.totalDueCount, 2);

        // Play 1. e4
        final result = await controller.onUserMove(
          const NormalMove(from: Square.e2, to: Square.e4),
        );
        expect(result, isNotNull);
        expect(result!.isCorrect, isTrue);

        // Should be paused awaiting continue, NOT auto-advanced!
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isTrue);
        expect(state.feedback, ReviewFeedback.correct);
        expect(state.revealedComment, contains('Controls d5'));
        expect(state.revealedComment, contains('[%cal Ge4d5]'));
        // Position is White's move 1. e4 (opponent has not replied yet)
        expect(state.lastMove, const NormalMove(from: Square.e2, to: Square.e4));
        expect(state.totalDueCount, 2);

        // Wait a moment: queue must remain paused and not auto-advance
        await Future<void>.delayed(const Duration(milliseconds: 500));
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isTrue);

        // Learner continues
        await controller.continueAdvancement();

        // Opponent reply 1... e5 is played and next prompt (2. Nf3) is loaded
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isFalse);
        expect(state.feedback, ReviewFeedback.none);
        expect(state.totalDueCount, 1);
        expect(state.currentPrompt, isNotNull);
        expect(state.currentPrompt!.expectedMoves.first.san, 'Nf3');
      },
    );

    test(
      'correct move with annotations disabled in preferences auto-advances without pausing',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        // Disable annotations and comments in preferences
        final studyPrefs = container.read(studyPreferencesProvider.notifier);
        await studyPrefs.toggleAnnotations();
        await studyPrefs.togglePgnComments();

        const pgn = '1. e4 {[%cal Ge4d5] Controls d5} e5 2. Nf3 *';
        await controller.importPgnText(
          pgnText: pgn,
          title: 'King Pawn Disabled Annotations',
          repertoireSide: Side.white,
        );

        // Play 1. e4
        final result = await controller.onUserMove(
          const NormalMove(from: Square.e2, to: Square.e4),
        );
        expect(result, isNotNull);
        expect(result!.isCorrect, isTrue);

        // Does not pause awaiting continue
        final state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isFalse);
        expect(state.totalDueCount, 1);
        expect(state.currentPrompt!.expectedMoves.first.san, 'Nf3');
      },
    );

    test('moving on the board while awaiting advance continues advancement', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '1. e4 {Good move} *';
      await controller.importPgnText(
        pgnText: pgn,
        title: 'Single Move Annotated',
        repertoireSide: Side.white,
      );

      // Play 1. e4
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.isAwaitingAdvance, isTrue);

      // User interacts with board by playing/tapping a move
      await controller.onUserMove(const NormalMove(from: Square.e4, to: Square.e5));

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isAwaitingAdvance, isFalse);
      expect(state.isComplete, isTrue);
    });

    test('importing identical PGN detects duplicate and avoids data duplication', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '1. e4 e5 2. Nf3 *';
      final res1 = await controller.importPgnText(
        pgnText: pgn,
        title: 'Original Study',
        repertoireSide: Side.white,
      );
      expect(res1.isDuplicate, isFalse);

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.studies.length, 1);
      expect(state.studies.first.title, 'Original Study');

      // Re-importing identical PGN content
      final res2 = await controller.importPgnText(
        pgnText: pgn,
        title: 'Duplicate Attempt',
        repertoireSide: Side.white,
      );
      expect(res2.isDuplicate, isTrue);
      expect(res2.study.id, equals(res1.study.id));

      // Repository still contains exactly 1 study
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.studies.length, 1);
    });

    test(
      'renaming study inside the app does not cause PGN re-import to be treated as new',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '1. e4 c5 2. Nf3 d6 *';
        final res1 = await controller.importPgnText(
          pgnText: pgn,
          title: 'Sicilian Defense',
          repertoireSide: Side.white,
        );
        expect(res1.isDuplicate, isFalse);

        // Rename the study inside the app
        await controller.renameStudy(res1.study.id, 'My Custom Sicilian');
        var state = container.read(reviewControllerProvider).requireValue;
        expect(state.studies.first.title, 'My Custom Sicilian');

        // Re-import the original PGN file
        final res2 = await controller.importPgnText(
          pgnText: pgn,
          title: 'Sicilian Defense',
          repertoireSide: Side.white,
        );

        // It must be recognized as duplicate, NOT treated as a new study!
        expect(res2.isDuplicate, isTrue);
        expect(res2.study.id, equals(res1.study.id));

        // Still exactly 1 study in repository
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.studies.length, 1);
        expect(state.studies.first.title, 'My Custom Sicilian');
      },
    );

    test(
      'changing scheduler preference automatically reloads session with new scheduler',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '1. e4 e5 2. Nf3 *';
        await controller.importPgnText(pgnText: pgn, repertoireSide: Side.white);

        var session = container.read(reviewControllerProvider).requireValue.session!;
        expect(session.scheduler, isA<SimpleScheduler>());

        // Switch to EaseScalingScheduler in preferences
        final prefsNotifier = container.read(studyPreferencesProvider.notifier);
        await prefsNotifier.setSchedulerType(SchedulerType.easeScaling);
        await prefsNotifier.setSchedulerEase(3.0);
        await controller.reload();

        session = container.read(reviewControllerProvider).requireValue.session!;
        expect(session.scheduler, isA<EaseScalingScheduler>());
        expect((session.scheduler as EaseScalingScheduler).ease, 3.0);
      },
    );

    group('importLichessStudy', () {
      test('fetches PGN from Lichess and derives title from headers', () async {
        final mockClient = MockClient((request) async {
          if (request.url.path == '/api/study/t3St1234.pgn') {
            return http.Response(
              '''
[Event "Catalan Opening: Closed Variation"]
[Site "https://lichess.org/study/t3St1234"]
1. d4 Nf6 2. c4 e6 3. g3 d5 4. Bg2 *
''',
              200,
              headers: {'content-type': 'application/x-chess-pgn'},
            );
          }
          return http.Response('Not Found', 404);
        });

        final container = createContainer(
          extraOverrides: [
            lichess_study.studyRepositoryProvider.overrideWith(
              (ref) => lichess_study.StudyRepository(ref, mockClient),
            ),
          ],
        );
        final controller = container.read(reviewControllerProvider.notifier);

        final result = await controller.importLichessStudy(
          studyIdOrUrl: 'https://lichess.org/study/t3St1234',
          repertoireSide: Side.white,
        );

        expect(result.study.title, 'Catalan Opening');
        expect(result.decisions.length, greaterThan(0));

        final state = container.read(reviewControllerProvider).requireValue;
        expect(state.studies.length, 1);
        expect(state.studies.first.title, 'Catalan Opening');
        expect(state.scope, ReviewScope.study(result.study.id));
      });

      test('throws FormatException on malformed URL or invalid ID', () {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        expect(
          () => controller.importLichessStudy(studyIdOrUrl: 'not_a_valid_id'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws friendly FormatException on 404 response', () {
        final mockClient = MockClient((request) async {
          return http.Response('Study not found', 404);
        });

        final container = createContainer(
          extraOverrides: [
            lichess_study.studyRepositoryProvider.overrideWith(
              (ref) => lichess_study.StudyRepository(ref, mockClient),
            ),
          ],
        );
        final controller = container.read(reviewControllerProvider.notifier);

        expect(
          () => controller.importLichessStudy(studyIdOrUrl: 'm1AbCd2E'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Study not found on Lichess'),
            ),
          ),
        );
      });
    });

    test('maxDailyReviews limit caps session and marks isDailyLimitReached', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '1. e4 e5 2. Nf3 Nc6 *';
      await controller.importPgnText(pgnText: pgn, repertoireSide: Side.white);

      // Set daily review limit to 1 and reload
      final prefsNotifier = container.read(studyPreferencesProvider.notifier);
      await prefsNotifier.setMaxDailyReviews(1);
      await controller.reload();

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.maxDailyReviews, 1);
      expect(state.dailyReviewedCount, 0);
      expect(state.isDailyLimitReached, isFalse);
      expect(state.currentPrompt, isNotNull);

      // Play 1. e4 (first position)
      final step = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(step?.isCorrect, isTrue);

      // Session completes because limit of 1 position was reached!
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.dailyReviewedCount, 1);
      expect(state.isDailyLimitReached, isTrue);
      expect(state.isComplete, isTrue);
      expect(state.currentPrompt, isNull);

      // Starting Free Practice allows training even when daily limit is reached
      await controller.startPracticeMode();
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isPracticeMode, isTrue);
      expect(state.isDailyLimitReached, isFalse);
      expect(state.currentPrompt, isNotNull);
    });

    test('onUserMove rejects concurrent moves while move animation delay is in flight', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Italian Game"]
1. e4 e5 2. Nf3 Nc6 *
''';

      await controller.importPgnText(pgnText: pgn, title: 'Italian', repertoireSide: Side.white);

      // Trigger first move: 1. e4 (animates opponent response over 300ms)
      final firstMoveFuture = controller.onUserMove(
        const NormalMove(from: Square.e2, to: Square.e4),
      );

      // Attempt concurrent second move while the first is still processing/animating
      final concurrentResult = await controller.onUserMove(
        const NormalMove(from: Square.g1, to: Square.f3),
      );

      // Concurrent move should be locked out and return null
      expect(concurrentResult, isNull);

      final firstResult = await firstMoveFuture;
      expect(firstResult, isNotNull);
      expect(firstResult!.isCorrect, isTrue);
    });

    test(
      'reviewing an already-learned decision decrements due but does not increment learnedDecisions',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '''
[Event "Single Move Study"]
1. e4 *
''';

        final importRes = await controller.importPgnText(
          pgnText: pgn,
          title: 'Learned Test',
          repertoireSide: Side.white,
        );

        final decision = importRes.decisions.first;
        final past = clock.now().subtract(const Duration(days: 2));

        // Seed an already-learned state (reps: 3) that is overdue
        await repo.saveReviewState(
          ReviewState(
            decisionId: decision.id,
            repetitionCount: 3,
            stability: 1000.0,
            nextDueAt: past,
          ),
        );

        await controller.reload();
        var state = container.read(reviewControllerProvider).requireValue;
        final initialStudyProg = state.studyProgress[importRes.study.id]!;
        expect(initialStudyProg.learnedDecisions, 1);
        expect(initialStudyProg.dueDecisions, 1);

        // Play correct move
        final step = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
        expect(step?.isCorrect, isTrue);

        state = container.read(reviewControllerProvider).requireValue;
        final updatedStudyProg = state.studyProgress[importRes.study.id]!;
        // Due count decrements, but learned count does NOT increment beyond 1!
        expect(updatedStudyProg.dueDecisions, 0);
        expect(updatedStudyProg.learnedDecisions, 1);
      },
    );
  });
}
