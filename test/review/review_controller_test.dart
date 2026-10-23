// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-003, INV-011, INV-013, INV-020, INV-021, INV-023, INV-026, INV-030, INV-031, INV-032,
//   INV-033.

import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' as lichess_study;
import 'package:chess_srs/src/model/user/user.dart';
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
import '../test_helpers.dart';
import 'gated_study_repository.dart';

/// A repository whose pgnHash lookup never matches, so the controller's pre-write duplicate
/// check cannot short-circuit an import.
///
/// Two imports of one file are *supposed* to both clear that check before either writes — it is
/// the repository's in-flight re-check that catches the loser. Leaving that window to scheduler
/// timing would make the test pass or fail depending on the interleaving, so it is opened
/// deterministically instead, in the same spirit as [GatedStudyRepository].
class _PrecheckMissRepository extends SqliteStudyRepository {
  _PrecheckMissRepository(super.db);

  @override
  Future<Study?> getStudyByPgnHash(String pgnHash, {Side? forSide}) async => null;
}

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
      SoundService? soundService,
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
              dynamicRepertoireMode: ref.watch(
                studyPreferencesProvider.select((p) => p.dynamicRepertoireMode),
              ),
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

    test('a duplicate import landing in flight resolves to the stored study (INV-003)', () async {
      // SPEC INV-003. Two imports of one file both clear the pre-write check before either
      // commits — that is the window the repository's in-flight re-check exists for. When it
      // skips the loser, the controller must resolve to the study that was actually stored:
      // the loser's own id was never persisted, and pointing the scope at it would open an
      // empty repertoire. The lookup is doctored to open that window deterministically.
      final doctored = _PrecheckMissRepository(db);
      final container = createContainer(repository: doctored);
      final controller = container.read(reviewControllerProvider.notifier);

      final results = await Future.wait([
        controller.importPgnText(pgnText: '1. e4 e5 *', switchScope: true),
        controller.importPgnText(pgnText: '1. e4 e5 *', switchScope: true),
      ]);

      final stored = (await doctored.getAllStudies()).single;
      final duplicates = results.where((r) => r.isDuplicate).toList();
      expect(
        duplicates,
        hasLength(1),
        reason:
            'exactly one of the two racing imports must be reported as the duplicate '
            'that actually landed',
      );
      expect(
        duplicates.single.study.id,
        stored.id,
        reason:
            'the duplicate must resolve to the stored study, not to the id of the import '
            'that was skipped',
      );
      expect(
        container.read(reviewControllerProvider).value!.scope.studyId,
        stored.id,
        reason: 'the scope must land on a study that exists',
      );
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

    // SPEC INV-032: controller does not emit placeholder empty state while repository is loading.
    test(
      'remains in loading state while repository initializes and does not flash empty state',
      () async {
        final repoCompleter = Completer<StudyRepository>();
        final container = ProviderContainer(
          overrides: [
            srsStudyRepositoryProvider.overrideWith((ref) => repoCompleter.future),
            clockProvider.overrideWithValue(clock),
            soundServiceProvider.overrideWithValue(FakeSoundService()),
          ],
        );
        addTearDown(container.dispose);

        final stateAsync = container.read(reviewControllerProvider);
        expect(stateAsync.isLoading, isTrue);
        expect(stateAsync.hasValue, isFalse);

        repoCompleter.complete(repo);
        final finalState = await container.read(reviewControllerProvider.future);

        expect(finalState.studies, isEmpty);
        expect(finalState.hasStudies, isFalse);
      },
    );

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
      // INV-068: freshly imported, so fresh rather than due.
      expect(state.totalDueCount, 0);
      expect(state.currentPrompt, isNotNull);
      expect(state.boardOrientation, Side.black);
      expect(state.boardPosition, isNotNull);

      // Pre-move animation: starts at parent position (White's turn before 1. e4),
      // then animates White's 1. e4 onto the board so Black sees opponent's move!
      expect(state.boardPosition!.turn, Side.white);
      await waitUntil(
        () => container.read(reviewControllerProvider).value?.boardPosition?.turn == Side.black,
      );
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
      // INV-068: never presented, so the freshly imported positions are fresh,
      // not due. They are still queued — that is what the session asks for.
      expect(state.totalDueCount, 0);
      expect(state.boardOrientation, Side.white);

      // Play 1. e4
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));

      expect(result, isNotNull);
      expect(result!.isCorrect, isTrue);

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.none);
      expect(state.totalDueCount, 0);
      // Auto-traversal played 1... e5, so next prompt is for 2. Nf3
      expect(state.currentPrompt, isNotNull);
      expect(state.currentPrompt!.expectedMoves.first.san, 'Nf3');
    });

    // SPEC INV-030: the two drawers are independent, so a White repertoire has no
    // Black counterpart until the user makes one. "I imported everything as
    // White" is the ordinary way a Black library ends up empty.
    test('a study can be created in the opposite colour', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 Nc6 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );

      final blackOrNull = await controller.createStudyInSide(white.study.id, Side.black);
      expect(blackOrNull, isNotNull, reason: 'the Black copy was not created');

      final studies = await repo.getAllStudies();
      expect(studies.length, 2);
      final black = studies.where((s) => s.id == blackOrNull!.id).first;
      final blackChapters = await repo.getChaptersByStudy(black.id);
      expect(
        blackChapters.map((c) => c.orientation),
        everyElement(Side.black),
        reason: 'the copy must land in the other drawer, not beside the original',
      );

      // Its positions are its own, not the White one's: the same tree answered in
      // the other colour is a different question (there is a test for that on
      // import, and this is the same rule reached through a different door).
      final blackDecisions = await repo.getDecisionsByStudy(black.id);
      final whiteDecisions = await repo.getDecisionsByStudy(white.study.id);
      expect(blackDecisions.length, whiteDecisions.length);
      final blackIds = blackDecisions.map((d) => d.id).toSet();
      final whiteIds = whiteDecisions.map((d) => d.id).toSet();
      expect(blackIds.intersection(whiteIds), isEmpty);
    });

    test('creating the opposite colour twice does not duplicate it', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );

      await controller.createStudyInSide(white.study.id, Side.black);
      // Null rather than a second copy: the import is deduplicated per side, so
      // the row is a no-op the user can press twice without consequence.
      final again = await controller.createStudyInSide(white.study.id, Side.black);

      expect(again, isNull);
      expect((await repo.getAllStudies()).length, 2);
    });

    test('creating the opposite colour twice does not move the session', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );
      await controller.createStudyInSide(white.study.id, Side.black);

      // The second run resolves the duplicate onto the existing Black copy; the
      // user never asked to leave the White drawer they were reviewing (#170),
      // and the queue they were part-way through must survive the tap.
      final again = await controller.createStudyInSide(white.study.id, Side.black);

      expect(again, isNull);
      final state = container.read(reviewControllerProvider).value;
      expect(state?.scope.studyId, white.study.id);
      expect(state?.activeSide, Side.white);
    });

    test('creating the opposite colour leaves the user on what they were reviewing', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );
      await controller.createStudyInSide(white.study.id, Side.black);

      // Creating the Black copy while reviewing the White one is a setup action,
      // not a change of intention: yanking the session across colours would
      // throw away the White queue the user was part-way through.
      final state = container.read(reviewControllerProvider).value;
      expect(state?.scope.studyId, white.study.id);
      expect(state?.activeSide, Side.white);
    });

    test('the starting drawer is the colour that has material', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: "Queen's Pawn",
        repertoireSide: Side.black,
      );

      // A fresh session on a library of nothing but Black material must open
      // on Black rather than on an empty White drawer.
      final container2 = createContainer();
      await container2.read(reviewControllerProvider.future);
      expect(container2.read(reviewControllerProvider).value?.scope, const ReviewScope.black());
      expect(container2.read(reviewControllerProvider).value?.activeSide, Side.black);
    });

    // SPEC INV-030: the two repertoire buttons count the review queue by side, so a tally has to
    // move as the session is worked through. The controller patches these optimistically instead of
    // reloading the whole summary, and the patch is easy to forget when a new per-scope tally is
    // added: without it the drawer keeps showing the count the session started with until the app
    // is restarted.
    test('per-side tallies follow the session as moves are reviewed', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Two Repertoires"]
1. e4 e5 2. Nf3 Nc6 *
''';

      // Two repertoires over the same tree, so both buttons start non-zero and answering the White
      // one must leave the Black one untouched.
      await controller.importPgnText(pgnText: pgn, title: 'White book', repertoireSide: Side.white);
      await controller.importPgnText(pgnText: pgn, title: 'Black book', repertoireSide: Side.black);

      // The import scoped to the study it just created; the side totals are all-scope figures, so
      // switch to a side scope and read them there. Awaited: changeScope reloads the summary, and
      // an unawaited reload would land after the move and overwrite the patched tally.
      await controller.changeScope(const ReviewScope.white());
      var state = container.read(reviewControllerProvider).requireValue;

      expect(state.sideProgress[Side.white]!.dueDecisions, 0);
      expect(state.sideProgress[Side.white]!.freshDecisions, 2);
      expect(state.sideProgress[Side.white]!.learnedDecisions, 0);
      expect(state.sideProgress[Side.black]!.dueDecisions, 0);
      expect(state.sideProgress[Side.black]!.freshDecisions, 2);
      expect(state.sideProgress[Side.black]!.learnedDecisions, 0);

      // Play 1. e4 in the White repertoire.
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));

      state = container.read(reviewControllerProvider).requireValue;

      // White's button has one less fresh and one more learned.
      // INV-068: answering retires the answered introduction (fresh 2 → 1) and
      // records the learning (learned 0 → 1), without touching due — which was
      // already 0. The unanswered continuation stays fresh until it is asked.
      expect(state.sideProgress[Side.white]!.dueDecisions, 0);
      expect(state.sideProgress[Side.white]!.freshDecisions, 1);
      expect(state.sideProgress[Side.white]!.learnedDecisions, 1);
      // Black's button is untouched — answering one repertoire must not debit the other.
      expect(
        state.sideProgress[Side.black]!.freshDecisions,
        2,
        reason: "the other side's button moved when only this repertoire was reviewed",
      );
      expect(state.sideProgress[Side.black]!.learnedDecisions, 0);
    });

    test('scope mismatch shows same due in summary and session', () async {
      // SPEC INV-031: effective scope must be used consistently for summary and session.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Two Repertoires"]
1. e4 e5 2. Nf3 Nc6 *
''';

      // White and Black chapters coexist with neither drawer selected, so the
      // bare all() resolves to the White drawer before anything is counted.
      await controller.importPgnText(pgnText: pgn, title: 'White book', repertoireSide: Side.white);
      await controller.importPgnText(pgnText: pgn, title: 'Black book', repertoireSide: Side.black);

      await controller.changeScope(const ReviewScope.all());
      final state = container.read(reviewControllerProvider).requireValue;

      expect(state.scope, const ReviewScope.white());
      // INV-068: a fresh import owes nothing, but the session must still queue
      // that side's positions — the set the summary and the session agree on is
      // now the fresh one, not the due one.
      expect(state.totalDueCount, 0);
      expect(state.totalFreshCount, greaterThan(0));
      expect(state.session?.initialQueueCount, greaterThan(0));
      expect(
        state.session?.initialDueCount,
        0,
        reason: 'summary and session were built for different scopes',
      );
      final prompt = state.currentPrompt;
      expect(prompt, isNotNull);
      final orientations = await repo.getChapterOrientations();
      expect(
        orientations[prompt!.chapterId],
        state.scope.side,
        reason: 'queued prompt is from the other drawer',
      );
    });

    test('a move the user plays makes the sound it made everywhere else in the app', () async {
      // Study and analysis both play a sound when the player moves a piece. Review training —
      // the screen this app spends most of its time on — played one for the opponent's reply and
      // for an animated pre-move, and nothing at all for the user's own move. Every position the
      // user recalls was silent, with no haptics either.
      final sounds = FakeSoundService();
      final container = createContainer(soundService: sounds);
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Italian"]
1. e4 e5 *
''';
      await controller.importPgnText(pgnText: pgn, title: 'Italian', repertoireSide: Side.white);
      sounds.recorded.clear();

      // A wrong move, on purpose: it still moves a piece on the board, and unlike a correct move
      // it triggers no auto-reply, so nothing else can be playing a sound and passing this test
      // on the user's behalf.
      await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));

      expect(sounds.recorded, contains(Sound.move), reason: "the user's own move was silent");
    });

    test('a capture the user plays gets the capture sound, not the plain move sound', () async {
      final sounds = FakeSoundService();
      final container = createContainer(soundService: sounds);
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Exchange"]
1. e4 d5 2. exd5 *
''';
      await controller.importPgnText(pgnText: pgn, title: 'Exchange', repertoireSide: Side.white);
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      sounds.recorded.clear();

      // exd5 takes the pawn, and taking a piece is audibly different from moving one.
      await controller.onUserMove(const NormalMove(from: Square.e4, to: Square.d5));

      expect(
        sounds.recorded,
        contains(Sound.capture),
        reason: 'the capture was played with the plain move sound',
      );
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

    test('lapsed item is re-tested: dues drop when the re-test is answered', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      const pgn = '''
[Event "Queen Pawn"]
1. d4 d5 *
''';

      await controller.importPgnText(pgnText: pgn, title: 'Queen Pawn', repertoireSide: Side.white);

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);

      // Lapse: play 1. e4 instead of 1. d4. The item is re-queued.
      final lapse = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(lapse, isNotNull);
      expect(lapse!.isCorrect, isFalse);
      state = container.read(reviewControllerProvider).requireValue;
      // INV-068: a lapse writes a state, so the item is no longer fresh.
      expect(state.totalDueCount, 0);

      // Reguess correctly: proves the move was seen, but the re-test is still
      // pending, so dues must NOT drop yet (the screen still shows a prompt).
      final retry = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      expect(retry, isNotNull);
      expect(retry!.isCorrect, isTrue);
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);
      expect(state.totalDueCount, 0);

      // Answer the re-test correctly first-try: now the item resolves.
      final retest = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      expect(retest, isNotNull);
      expect(retest!.isCorrect, isTrue);
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);
    });

    test('mid-advance scope change discards the stale advancement', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final importA = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );
      final importB = await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );

      // Back to study A: one queued prompt (1. e4). Never presented, so it is
      // fresh rather than due (INV-068).
      await controller.changeScope(ReviewScope.study(importA.study.id));
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);

      // Answer correctly but do not await the advancement: the 300ms+
      // opponent-reply animation is still in flight below.
      final advance = controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      // Wait until the move has been processed and advancement is awaiting
      // the opponent-reply delay, then change scope mid-advance.
      await waitUntil(() => container.read(reviewControllerProvider).value?.lastStepResult != null);

      // Switch to study B mid-advance and let it fully load.
      await controller.changeScope(ReviewScope.study(importB.study.id));
      await advance;

      // The stale advancement for A must not paint over B's fresh load:
      // scope, prompt and dues all belong to B.
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, ReviewScope.study(importB.study.id));
      expect(state.totalDueCount, 0);
      expect(state.currentPrompt, isNotNull);
      expect(state.currentPrompt!.studyId, importB.study.id);
    });

    test(
      'changeScope targeted session start reuses summary and updates due count accurately',
      () async {
        // SPEC INV-030. PERF-FIX-36: targeted scope session start without full-library re-summarisation.
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        final importA = await controller.importPgnText(
          pgnText: '1. e4 e5 2. Nf3 Nc6 *',
          title: 'King Pawn',
          repertoireSide: Side.white,
        );
        final importB = await controller.importPgnText(
          pgnText: '1. d4 d5 *',
          title: 'Queen Pawn',
          repertoireSide: Side.white,
        );

        // importPgnText leaves scope at the imported study (Study B)
        final stateB = container.read(reviewControllerProvider).requireValue;
        expect(stateB.scope, ReviewScope.study(importB.study.id));
        // INV-068: both books were just imported, so nothing is due yet — the
        // per-study figures below are the fresh counts by another name.
        expect(stateB.totalDueCount, 0);
        expect(stateB.studyProgress[importA.study.id]!.freshDecisions, 2);
        expect(stateB.studyProgress[importB.study.id]!.freshDecisions, 1);

        // Targeted changeScope to Study A
        await controller.changeScope(ReviewScope.study(importA.study.id));
        final stateA = container.read(reviewControllerProvider).requireValue;
        expect(stateA.scope, ReviewScope.study(importA.study.id));
        // INV-068: nothing is due. The reuse path keeps the all-library study
        // figures it already had, which is what PERF-FIX-36 preserved.
        expect(stateA.totalDueCount, 0);
        expect(stateA.studyProgress[importA.study.id]!.dueDecisions, 0);
        expect(stateA.studyProgress[importA.study.id]!.freshDecisions, 2);
        expect(stateA.studyProgress[importB.study.id]!.freshDecisions, 1);
        expect(stateA.session?.currentPrompt?.decision.studyId, importA.study.id);
      },
    );

    test(
      'changeScope reuse carries the scope-wide due and fresh counts, not the quota-capped queue',
      () async {
        // SPEC INV-068. #164: the reuse fast path published
        // `session.initialDueCount` — the queue after the daily quota trimmed it
        // (and `initialQueueCount - initialDueCount` for fresh) — as the
        // scope-wide figure, so the top bar fell from the scope's debt to the
        // day's allowance on every changeScope/selectSide.
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);
        final service = container.read(reviewServiceProvider);

        final importA = await controller.importPgnText(
          pgnText: '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 *',
          title: 'King Pawn',
          repertoireSide: Side.white,
        );
        await controller.importPgnText(
          pgnText: '1. d4 d5 *',
          title: 'Queen Pawn',
          repertoireSide: Side.white,
        );

        // Two overdue positions and one still-fresh position in study A. Review
        // scheduling would push the first two into the future, so the states are
        // seeded directly.
        final decisions = await repo.getDecisionsByStudy(importA.study.id);
        expect(decisions.length, greaterThanOrEqualTo(3));
        final past = clock.now().subtract(const Duration(days: 2));
        for (final decision in decisions.take(2)) {
          await repo.saveReviewState(
            ReviewState(
              decisionId: decision.id,
              repetitionCount: 3,
              stability: 1000.0,
              nextDueAt: past,
            ),
          );
        }

        // One position of daily allowance, strictly fewer than the debt.
        await container.read(studyPreferencesProvider.notifier).setMaxDailyReviews(1);

        await controller.changeScope(ReviewScope.study(importA.study.id));

        final state = container.read(reviewControllerProvider).requireValue;
        final studies = await repo.getAllStudies();
        final summary = await service.getDueSummary(
          studies: studies,
          scope: ReviewScope.study(importA.study.id),
        );

        expect(
          summary.totalDueCount,
          greaterThan(1),
          reason: 'the cap must be smaller than the debt or this proves nothing',
        );
        expect(state.totalDueCount, summary.totalDueCount);
        expect(state.totalFreshCount, summary.totalFreshCount);
      },
    );

    // SPEC INV-030: opening the active colour drawer preserves narrower scope (issue #59).
    test('selectSide on active colour preserves study and opening scope without reload', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final importA = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'King Pawn',
        repertoireSide: Side.white,
      );
      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );

      // Narrow scope to study A
      await controller.changeScope(ReviewScope.study(importA.study.id));
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, ReviewScope.study(importA.study.id));
      expect(state.activeSide, Side.white);
      final originalPosition = state.boardPosition;
      final originalPromptId = state.currentPrompt?.decision.id;

      // Tap the white square (open White drawer)
      await controller.selectSide(Side.white);

      // Must remain scoped to study A without reloading or moving the board
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, ReviewScope.study(importA.study.id));
      expect(state.boardPosition, originalPosition);
      expect(state.currentPrompt?.decision.id, originalPromptId);

      // Selecting the OTHER side switches to that side
      await controller.selectSide(Side.black);
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, const ReviewScope.black());
      expect(state.activeSide, Side.black);
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
      // INV-068: both studies are fresh, so neither owes anything yet.
      expect(state.totalDueCount, 0);
      expect(state.studies.length, 2);

      // Suspend the 'Closed' study from daily review pool
      await controller.toggleStudyActive(res2.study.id, false);

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);
      expect(state.studies.length, 2);
      final updatedStudies = state.studies;
      expect(updatedStudies.firstWhere((s) => s.id == res2.study.id).isActive, isFalse);
    });

    test('toggling a study that replaces the session discards a waiting advancement', () async {
      // A correct answer with commentary pauses for Continue: the grading is persisted, only
      // the UI step waits. Pausing the answered study replaces the session — and the waiting
      // step belongs to the old line, so it must not run (it would write the old dues math
      // onto the fresh state and resurrect its prompt).
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final res1 = await controller.importPgnText(
        pgnText: '1. e4 {Good move} e5 *',
        title: 'Open',
        repertoireSide: Side.white,
      );
      await controller.importPgnText(
        pgnText: '1. d4 {Good move} d5 *',
        title: 'Closed',
        repertoireSide: Side.white,
      );
      await controller.changeScope(const ReviewScope.all());

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt?.studyId, res1.study.id);
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isAwaitingAdvance, isTrue);

      await controller.toggleStudyActive(res1.study.id, false);

      state = container.read(reviewControllerProvider).requireValue;
      expect(
        state.isAwaitingAdvance,
        isFalse,
        reason: 'the session was replaced; nothing is waiting anymore',
      );
      expect(state.feedback, ReviewFeedback.none);
      expect(state.currentPrompt, isNotNull);

      // A Continue now must be a no-op, not the discarded line advancing.
      final promptBefore = state.currentPrompt;
      await controller.continueAdvancement();
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt?.decision.id, promptBefore?.decision.id);
    });

    test('deleting a study while an advancement waits publishes a fresh prompt', () async {
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 {Good move} e5 *',
        title: 'Open',
        repertoireSide: Side.white,
      );
      final res2 = await controller.importPgnText(
        pgnText: '1. d4 {Good move} d5 *',
        title: 'Closed',
        repertoireSide: Side.white,
      );
      await controller.changeScope(const ReviewScope.all());

      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);
      expect(container.read(reviewControllerProvider).requireValue.isAwaitingAdvance, isTrue);

      // Deleting the *other* study restarts the session (all-scope): the waiting step dies
      // with the old session instead of advancing it onto the fresh state.
      await controller.deleteStudy(res2.study.id);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.isAwaitingAdvance, isFalse);
      expect(state.feedback, ReviewFeedback.none);
      expect(state.studies.any((s) => s.id == res2.study.id), isFalse);
    });

    test('a practice rehearsal writes nothing to the store (INV-023)', () async {
      // SPEC INV-023. Practice mode rehearses rather than schedules: it grades
      // and traverses exactly as SRS mode does but performs zero writes to
      // review states and logs zero events.
      //
      // The engine test that grades practice moves can only see the session's
      // own state and event, and the service's no-write guard is below both.
      // This one drives a real practice answer through the controller, the
      // service and the store, and looks at what the store holds afterwards.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 d5 2. c4 e6 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );
      await controller.startPracticeMode();

      // A wrong move: a lapse is the write most likely to leak, because it
      // carries a state change and a contagion side effect.
      final lapse = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(lapse?.isCorrect, isFalse);

      // And a right one.
      final correct = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      expect(correct?.isCorrect, isTrue);

      // Nothing reached the store.
      expect(
        await repo.getAllKnowledgeStates(),
        isEmpty,
        reason: 'practice mode must not write canonical knowledge states',
      );
      expect(
        await repo.getAllReviewStates(),
        isEmpty,
        reason: 'practice mode must not write review states',
      );
      for (final decision in await repo.getAllDecisions()) {
        expect(
          await repo.getReviewEvents(decision.id),
          isEmpty,
          reason: 'practice mode must not log review events',
        );
      }
      expect(
        await repo.getTodayReviewedPositionsCount(clock.now()),
        0,
        reason: "practice mode must not move the day's reviewed count",
      );
    });

    test('practice rehearsals do not inflate the daily reviewed count', () async {
      // INV-031 counts persisted SRS positions; practice writes nothing, so the number on
      // screen must not move either — it is displayed against the repository total.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'Open',
        repertoireSide: Side.white,
      );
      await controller.startPracticeMode();

      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.mode, ReviewMode.practice);
      expect(
        state.dailyReviewedCount,
        0,
        reason: 'nothing was persisted, so the displayed daily count must not move',
      );
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
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'Nf3' || m.uci == 'g1f3') ==
            true,
      );
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      await waitUntil(() => container.read(reviewControllerProvider).value?.isComplete == true);

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
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'Nf3' || m.uci == 'g1f3') ==
            true,
      );

      // User plays 2. Nf3 to complete branch 1
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      // Transitioning to the other branch: White to play against opponent's response.
      await waitUntil(
        () => container.read(reviewControllerProvider).value?.currentPrompt?.incomingMove != null,
      );

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);
      final incoming = state.currentPrompt!.incomingMove;
      expect(incoming, isNotNull);

      // Wait for pre-move animation of the opponent's incoming branch move
      await waitUntil(
        () =>
            container.read(reviewControllerProvider).value?.lastMove ==
            NormalMove(from: Square.fromName(incoming!.from), to: Square.fromName(incoming.to)),
      );
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
      await waitUntil(
        () => container.read(reviewControllerProvider).value?.boardPosition?.turn == Side.black,
      );
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
      await waitUntil(
        () => container.read(reviewControllerProvider).value?.boardPosition?.turn == Side.black,
      );
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
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'Nf3' || m.uci == 'g1f3') ==
            true,
      );

      // Move 2: 2. Nf3
      await controller.onUserMove(const NormalMove(from: Square.g1, to: Square.f3));
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'Bc4' || m.uci == 'f1c4') ==
            true,
      );

      // Move 3: 3. Bc4
      await controller.onUserMove(const NormalMove(from: Square.f1, to: Square.c4));
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'O-O' || m.uci == 'e1g1') ==
            true,
      );

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
        expect(state.totalDueCount, 0);

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
        expect(state.totalDueCount, 0);

        // Queue must remain paused and not auto-advance
        await pumpEventQueue();
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isTrue);

        // Learner continues
        await controller.continueAdvancement();

        // Opponent reply 1... e5 is played and next prompt (2. Nf3) is loaded
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.isAwaitingAdvance, isFalse);
        expect(state.feedback, ReviewFeedback.none);
        expect(state.totalDueCount, 0);
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
        expect(state.totalDueCount, 0);
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

    group('importAllMyStudies', () {
      // The listing endpoint streams NDJSON, one object per study — the shape
      // verified live against /api/study/by/:username on 2026-10-14.
      String studiesNdJson(List<(String, String, int)> entries) => entries
          .map(
            (e) => jsonEncode({
              'id': e.$1,
              'name': e.$2,
              'createdAt': 1700000000000,
              'updatedAt': e.$3,
            }),
          )
          .join('\n');

      const whitePgn = '''
[Event "White Repertoire"]
[Site "https://lichess.org/study/aaaaaaaa"]
1. e4 e5 2. Nf3 *
''';

      const blackPgn = '''
[Event "Black Repertoire"]
[Site "https://lichess.org/study/bbbbbbbb"]
[Orientation "black"]
1. e4 e6 2. d4 d5 *
''';

      MockClient bulkClient({bool blackGone = false, void Function(Uri url)? onRequest}) {
        return MockClient((request) async {
          onRequest?.call(request.url);
          if (request.url.path == '/api/study/by/tester') {
            return http.Response(
              studiesNdJson([
                ('aaaaaaaa', 'White Repertoire', 1700000000000),
                ('bbbbbbbb', 'Black Repertoire', 1700000000000),
              ]),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }
          if (request.url.path == '/api/study/aaaaaaaa.pgn') {
            return http.Response(
              whitePgn,
              200,
              headers: {'content-type': 'application/x-chess-pgn'},
            );
          }
          if (request.url.path == '/api/study/bbbbbbbb.pgn') {
            if (blackGone) return http.Response('Study not found', 404);
            return http.Response(
              blackPgn,
              200,
              headers: {'content-type': 'application/x-chess-pgn'},
            );
          }
          return http.Response('Not Found', 404);
        });
      }

      ProviderContainer bulkContainer(MockClient client) {
        final container = createContainer(
          extraOverrides: [
            lichess_study.studyRepositoryProvider.overrideWith(
              (ref) => lichess_study.StudyRepository(ref, client),
            ),
          ],
        );
        // Bulk import lists /api/study/by/<signed-in username>.
        container.read(authControllerProvider.notifier).state = const AuthUser(
          token: 'test-token',
          user: LightUser(id: UserId('tester'), name: 'tester'),
        );
        return container;
      }

      test(
        'imports every owned study in one listing, each on its own side',
        // SPEC INV-013. Bulk import passes no side, so the White study trains
        // White and the Black study trains Black from their own headers.
        () async {
          final container = bulkContainer(bulkClient());
          final controller = container.read(reviewControllerProvider.notifier);

          final seen = <BulkImportProgress>[];
          final result = await controller.importAllMyStudies(onProgress: seen.add);

          expect(result.imported, 2);
          expect(result.duplicates, 0);
          expect(result.failed, isEmpty);
          expect(seen.last, (done: 2, total: 2, currentName: 'Black Repertoire'));

          final state = container.read(reviewControllerProvider).requireValue;
          expect(state.studies.length, 2);
          // The batch reloads once at the end instead of jumping per study.
          expect(state.scope.studyId, isNull);

          final chapters = <String, Side>{};
          for (final study in state.studies) {
            final stored = await repo.getChaptersByStudy(study.id);
            expect(stored, isNotEmpty);
            for (final chapter in stored) {
              chapters[chapter.id] = chapter.orientation;
            }
          }
          expect(chapters.values, containsAll([Side.white, Side.black]));
        },
      );

      test(
        'second run skips everything as duplicates without new studies',
        // SPEC INV-003. Re-running bulk import over identical material
        // creates nothing new.
        () async {
          final container = bulkContainer(bulkClient());
          final controller = container.read(reviewControllerProvider.notifier);

          await controller.importAllMyStudies();
          final rerun = await controller.importAllMyStudies();

          expect(rerun.imported, 0);
          expect(rerun.duplicates, 2);
          expect(rerun.duplicateTitles, containsAll(['White Repertoire', 'Black Repertoire']));
          expect(rerun.failed, isEmpty);

          final state = container.read(reviewControllerProvider).requireValue;
          expect(state.studies.length, 2);
        },
      );

      test(
        're-running over unchanged studies downloads no PGN',
        // SPEC INV-003. The first run records each study's remote timestamp;
        // the second run skips the download entirely instead of re-fetching
        // and re-hashing everything.
        () async {
          var pgnFetches = 0;
          final container = bulkContainer(
            bulkClient(
              onRequest: (url) {
                if (url.path.endsWith('.pgn')) pgnFetches++;
              },
            ),
          );
          final controller = container.read(reviewControllerProvider.notifier);

          final first = await controller.importAllMyStudies();
          expect(first.imported, 2);
          expect(pgnFetches, 2);

          final second = await controller.importAllMyStudies();
          expect(second.imported, 0);
          expect(second.duplicates, 2);
          expect(pgnFetches, 2);
        },
      );

      test(
        'a remotely changed study is re-fetched while the rest is skipped',
        // SPEC INV-003. A newer remote timestamp re-downloads that study
        // only; the hash still dedupes identical content.
        () async {
          var blackUpdatedAt = 1700000000000;
          var pgnFetches = 0;
          final client = MockClient((request) async {
            if (request.url.path.endsWith('.pgn')) pgnFetches++;
            if (request.url.path == '/api/study/by/tester') {
              return http.Response(
                studiesNdJson([
                  ('aaaaaaaa', 'White Repertoire', 1700000000000),
                  ('bbbbbbbb', 'Black Repertoire', blackUpdatedAt),
                ]),
                200,
                headers: {'content-type': 'application/x-ndjson'},
              );
            }
            if (request.url.path == '/api/study/aaaaaaaa.pgn') {
              return http.Response(
                whitePgn,
                200,
                headers: {'content-type': 'application/x-chess-pgn'},
              );
            }
            if (request.url.path == '/api/study/bbbbbbbb.pgn') {
              return http.Response(
                blackPgn,
                200,
                headers: {'content-type': 'application/x-chess-pgn'},
              );
            }
            return http.Response('Not Found', 404);
          });
          final container = bulkContainer(client);
          final controller = container.read(reviewControllerProvider.notifier);

          await controller.importAllMyStudies();
          expect(pgnFetches, 2);

          blackUpdatedAt = 1800000000000;
          final rerun = await controller.importAllMyStudies();
          expect(pgnFetches, 3);
          expect(rerun.imported, 0);
          expect(rerun.duplicates, 2);
        },
      );

      test(
        'a failing study is recorded and the batch continues',
        // SPEC INV-011. One gone study must not abort the rest of the batch.
        () async {
          final container = bulkContainer(bulkClient(blackGone: true));
          final controller = container.read(reviewControllerProvider.notifier);

          final result = await controller.importAllMyStudies();

          expect(result.imported, 1);
          expect(result.duplicates, 0);
          expect(result.failed.length, 1);
          expect(result.failed.first.name, 'Black Repertoire');

          final state = container.read(reviewControllerProvider).requireValue;
          expect(state.studies.length, 1);
          expect(state.studies.first.title, 'White Repertoire');
        },
      );

      test('empty library returns zeros without failing', () async {
        final emptyClient = MockClient((request) async {
          if (request.url.path == '/api/study/by/tester') {
            return http.Response('', 200, headers: {'content-type': 'application/x-ndjson'});
          }
          return http.Response('Not Found', 404);
        });
        final container = bulkContainer(emptyClient);
        final controller = container.read(reviewControllerProvider.notifier);

        final result = await controller.importAllMyStudies();

        expect(result.imported, 0);
        expect(result.duplicates, 0);
        expect(result.failed, isEmpty);

        final state = container.read(reviewControllerProvider).requireValue;
        expect(state.studies, isEmpty);
      });

      test(
        'signed out asks for sign-in without calling the server',
        // SPEC INV-011. The button is hidden while signed out, but the
        // controller must still refuse outright rather than list as nobody.
        () async {
          var called = false;
          final guardClient = MockClient((_) async {
            called = true;
            return http.Response('', 200);
          });
          final container = bulkContainer(guardClient);
          container.read(authControllerProvider.notifier).state = null;
          final controller = container.read(reviewControllerProvider.notifier);

          await expectLater(
            controller.importAllMyStudies(),
            throwsA(
              isA<BulkImportListException>().having(
                (e) => e.message,
                'message',
                contains('Sign in'),
              ),
            ),
          );
          expect(called, isFalse);
        },
      );

      test(
        'a refused study list throws the reason instead of failing silently',
        // SPEC INV-011. This is the production failure of 2026-10-14: the
        // desktop token carried no study scope, so /study/mine/... answered
        // 401 and the dialog could only say "bulk import failed". The reason
        // must travel with the exception so the screen can show it.
        () async {
          final refusedClient = MockClient((_) async => http.Response('Unauthorized', 401));
          final container = bulkContainer(refusedClient);
          final controller = container.read(reviewControllerProvider.notifier);

          await expectLater(
            controller.importAllMyStudies(),
            throwsA(
              isA<BulkImportListException>().having(
                (e) => e.message,
                'message',
                allOf(contains('401'), contains('sign out')),
              ),
            ),
          );

          final state = await container.read(reviewControllerProvider.future);
          expect(state.studies, isEmpty);
        },
      );

      test('a server error on the study list names its status', () async {
        final brokenClient = MockClient((_) async => http.Response('Error', 500));
        final container = bulkContainer(brokenClient);
        final controller = container.read(reviewControllerProvider.notifier);

        await expectLater(
          controller.importAllMyStudies(),
          throwsA(
            isA<BulkImportListException>().having((e) => e.message, 'message', contains('500')),
          ),
        );
      });

      test(
        'a forbidden study list names the missing permission and the fix',
        // SPEC INV-011. Production 2026-10-14, second sighting: after the 401
        // case was covered, the same scopeless desktop grant answered 403.
        // A bare status number sent the owner back with nothing actionable.
        () async {
          final forbiddenClient = MockClient((_) async => http.Response('Forbidden', 403));
          final container = bulkContainer(forbiddenClient);
          final controller = container.read(reviewControllerProvider.notifier);

          await expectLater(
            controller.importAllMyStudies(),
            throwsA(
              isA<BulkImportListException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('403'),
                  contains('sign out'),
                  contains('lichess.org/account/oauth/token'),
                ),
              ),
            ),
          );
        },
      );

      test(
        'answering mid-session still advances after a bulk import',
        // SPEC INV-020. Same as above but in an all-studies scope with an
        // answer already given before the batch: the owner's frozen board
        // happened while reviewing across studies, not inside one. Taps
        // landing in the pre-move animation window died silently because the
        // board showed the parent position; every tap now snaps to the live
        // prompt first (see cancelPreMoveAnimation).
        () async {
          final container = bulkContainer(bulkClient());
          final controller = container.read(reviewControllerProvider.notifier);

          await controller.importPgnText(
            pgnText: '1. e4 e5 2. Bc4 *',
            title: 'First',
            repertoireSide: Side.white,
          );
          await controller.importPgnText(
            pgnText: '1. d4 d5 *',
            title: 'Second',
            repertoireSide: Side.white,
          );
          await controller.changeScope(const ReviewScope.all());

          // Answer once before the batch so the session is mid-flight.
          var step = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
          expect(step?.isCorrect, isTrue);

          final bulk = await controller.importAllMyStudies();
          expect(bulk.imported, 2);

          var state = container.read(reviewControllerProvider).requireValue;
          final promptAfterBulk = state.currentPrompt;
          expect(promptAfterBulk, isNotNull);

          // Play whatever the reloaded session serves — the point is that the
          // screen and the grader agree after the batch, not which line wins.
          final expected = promptAfterBulk!.expectedMoves.first;
          step = await controller.onUserMove(
            NormalMove(
              from: Square.fromName(expected.from),
              to: Square.fromName(expected.to),
              promotion: expected.promotion != null ? Role.fromChar(expected.promotion!) : null,
            ),
          );
          expect(step?.isCorrect, isTrue);

          state = container.read(reviewControllerProvider).requireValue;
          expect(state.boardPosition?.fen, isNot(equals(promptAfterBulk.fen)));
        },
      );

      test(
        'answering the live prompt still advances after a bulk import',
        // SPEC INV-020. Owner-reported 2026-10-14: right after a bulk import,
        // correct moves changed nothing on the board until the scope was
        // changed. The reload at the end of the batch must leave the screen
        // and the grader on the same session.
        () async {
          final container = bulkContainer(bulkClient());
          final controller = container.read(reviewControllerProvider.notifier);

          await controller.importPgnText(
            pgnText: '1. e4 e5 *',
            title: 'First',
            repertoireSide: Side.white,
          );
          var state = container.read(reviewControllerProvider).requireValue;
          expect(state.currentPrompt, isNotNull);

          final bulk = await controller.importAllMyStudies();
          expect(bulk.imported, 2);

          final step = await controller.onUserMove(
            const NormalMove(from: Square.e2, to: Square.e4),
          );
          expect(step?.isCorrect, isTrue);

          state = container.read(reviewControllerProvider).requireValue;
          expect(state.currentPrompt, isNull);
          expect(state.totalDueCount, 0);
        },
      );
      test(
        'a second run reports each skipped study as done',
        // SPEC INV-003. The progress the dialog shows counts finished studies,
        // so a study that was skipped as already present still has to be
        // counted as done.
        () async {
          final container = bulkContainer(bulkClient());
          final controller = container.read(reviewControllerProvider.notifier);

          await controller.importAllMyStudies();

          final seen = <BulkImportProgress>[];
          final rerun = await controller.importAllMyStudies(onProgress: seen.add);

          expect(rerun.duplicates, 2);
          expect(seen.last, (done: 2, total: 2, currentName: 'Black Repertoire'));
        },
      );
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

    // SPEC INV-001. Review writes are durable and incremental.
    // Frame-0 optimistic placement displays user move immediately while persistence runs.
    test(
      'onUserMove updates board position to move destination on frame 0 before persistence finishes',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '''
[Event "Italian Game"]
1. e4 e5 2. Nf3 Nc6 *
''';

        await controller.importPgnText(pgnText: pgn, title: 'Italian', repertoireSide: Side.white);

        const userMove = NormalMove(from: Square.e2, to: Square.e4);
        final moveFuture = controller.onUserMove(userMove);

        // Frame 0 assertion: board position and lastMove are updated synchronously before future completes
        expect(controller.state.value!.lastMove, equals(userMove));
        expect(controller.state.value!.boardPosition, equals(Chess.initial.play(userMove)));

        final result = await moveFuture;
        expect(result, isNotNull);
        expect(result!.isCorrect, isTrue);
      },
    );

    // SPEC INV-050. A graded move settles within one frame.
    // Drag pre-warming pre-calculates candidate position and audio feedback during touch down.
    test(
      'prewarmMoveCandidate pre-calculates move position and feedback cues on origin square touch',
      () async {
        final container = createContainer();
        final controller = container.read(reviewControllerProvider.notifier);

        const pgn = '''
[Event "Italian Game"]
1. e4 e5 2. Nf3 Nc6 *
''';

        await controller.importPgnText(pgnText: pgn, title: 'Italian', repertoireSide: Side.white);

        // Touching an unrelated square (e.g. a2) does not prewarm the e2e4 candidate
        controller.prewarmMoveCandidate(Square.a2);
        expect(controller.prewarmedCandidateMove, isNull);
        expect(controller.prewarmedCandidatePosition, isNull);

        // Touching origin square of expected move (e2 for e2e4) prewarms candidate
        controller.prewarmMoveCandidate(Square.e2);
        final expectedMove = Move.parse('e2e4');
        expect(controller.prewarmedCandidateMove, equals(expectedMove));
        expect(controller.prewarmedCandidatePosition, equals(Chess.initial.play(expectedMove!)));
        expect(controller.prewarmedIsCapture, isFalse);
        expect(controller.prewarmedIsCheck, isFalse);

        const move = NormalMove(from: Square.e2, to: Square.e4);
        final step = await controller.onUserMove(move);

        expect(step, isNotNull);
        expect(step!.isCorrect, isTrue);
        expect(controller.prewarmedCandidateMove, isNull);
        expect(controller.prewarmedCandidatePosition, isNull);
      },
    );

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

    test(
      'dynamic repertoire mode: practice move on un-unlocked branch sets pendingUnlock and unlockBranch unlocks it',
      () async {
        final container = createContainer();
        await container.read(studyPreferencesProvider.notifier).toggleDynamicRepertoireMode();

        final controller = container.read(reviewControllerProvider.notifier);

        await controller.importPgnText(
          pgnText: '1. e4 e5 2. Nf3 *',
          title: 'Dynamic Practice Study',
          repertoireSide: Side.white,
        );

        // In dynamic mode, 0 items due initially since decisions are dormant
        var state = container.read(reviewControllerProvider).requireValue;
        expect(state.totalDueCount, 0);

        // Start Practice Mode
        await controller.startPracticeMode();
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.mode, ReviewMode.practice);

        // Play 1. e4
        final result = await controller.onUserMove(
          const NormalMove(from: Square.e2, to: Square.e4),
        );
        expect(result?.isCorrect, isTrue);

        // pendingUnlock is set!
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.pendingUnlock, isNotNull);
        expect(state.pendingUnlock?.moveSan, 'e4');

        // Call unlockBranch
        await controller.unlockBranch(
          state.pendingUnlock!.decisionId,
          state.pendingUnlock!.chapterId,
        );

        // pendingUnlock is cleared and the branch is now unlocked in DB!
        state = container.read(reviewControllerProvider).requireValue;
        expect(state.pendingUnlock, isNull);

        final unlocked = await repo.getUnlockedDecisionIds();
        expect(unlocked, isNotEmpty);
      },
    );

    // ---------------------------------------------------------------------
    // The figures the review screen reads off the state.
    //
    // They are computed from the session's own clock and its own state map —
    // never from the wall clock (QUALITY.md §3.2) — so a fixed clock pins them
    // exactly, and the session can be built directly when the figure under
    // test is a getter rather than a side effect of a move.
    // ---------------------------------------------------------------------

    /// A state whose session holds exactly [reviewStates] and nothing else.
    ReviewScreenState stateWithReviewStates(
      Map<String, ReviewState> reviewStates, {
      ReviewScope scope = const ReviewScope.all(),
    }) {
      final session = ReviewSession(
        studies: const <Study>[],
        chapters: const <Chapter>[],
        decisions: const <RepertoireDecision>[],
        reviewStates: reviewStates,
        clock: clock,
      );
      return ReviewScreenState(
        studies: const <Study>[],
        scope: scope,
        totalDueCount: 0,
        totalFreshCount: 0,
        studyDueCounts: const <String, int>{},
        session: session,
      );
    }

    test('nextReviewDueAt reports the earliest future due date in the session', () {
      // SPEC INV-031. The screen tells the player when the next position falls
      // due. That is the *earliest* scheduled date still in the future: a
      // position already overdue is not "next", and a later date must not
      // replace an earlier one just because it was seen first.
      final now = clock.now();
      final state = stateWithReviewStates({
        'never scheduled': const ReviewState(decisionId: 'never scheduled'),
        'overdue': ReviewState(
          decisionId: 'overdue',
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: now.subtract(const Duration(hours: 1)),
        ),
        'sooner': ReviewState(
          decisionId: 'sooner',
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: now.add(const Duration(hours: 2)),
        ),
        'later': ReviewState(
          decisionId: 'later',
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: now.add(const Duration(days: 1)),
        ),
      });

      expect(
        state.nextReviewDueAt,
        now.add(const Duration(hours: 2)),
        reason: 'the next review is the soonest date still ahead, not the overdue one',
      );
    });

    test('nextReviewDueAt is null when nothing is scheduled ahead', () {
      // SPEC INV-031. With only overdue positions left there is no "next" to
      // wait for, and the screen shows no countdown at all.
      final now = clock.now();
      final state = stateWithReviewStates({
        'overdue': ReviewState(
          decisionId: 'overdue',
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: now.subtract(const Duration(hours: 1)),
        ),
      });

      expect(state.nextReviewDueAt, isNull);
      expect(state.timeUntilNextReview, isNull);
    });

    test('timeUntilNextReview names the remaining time in the units that fit it', () {
      // SPEC INV-031. The countdown the screen shows has to read as English,
      // and the unit has to change with the size of the wait: minutes below
      // an hour, hours below a day, and days beyond that, with a day-plus-part
      // spelled out rather than rounded away.
      final now = clock.now();

      String countdown(Duration until) => stateWithReviewStates({
        'next': ReviewState(
          decisionId: 'next',
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: now.add(until),
        ),
      }).timeUntilNextReview!;

      expect(countdown(const Duration(minutes: 30)), 'in 30 minutes');
      expect(
        countdown(const Duration(minutes: 1)),
        'in 1 minute',
        reason: 'a single minute is not "in 1 minutes"',
      );
      expect(
        countdown(const Duration(minutes: 60)),
        'in 1 hour',
        reason: 'sixty minutes is an hour, not sixty minutes',
      );
      expect(countdown(const Duration(minutes: 90)), 'in 1 hour');
      expect(countdown(const Duration(hours: 2)), 'in 2 hours');
      expect(
        countdown(const Duration(hours: 24)),
        'in 1 day',
        reason: 'twenty-four hours is a day, and its hours part is zero',
      );
      expect(countdown(const Duration(hours: 27)), 'in 1 day, 3 hr');
      expect(countdown(const Duration(days: 2)), 'in 2 days');
    });

    test('totalProgress counts the active studies only', () async {
      // SPEC INV-030. The progress bar is the whole library's, so a study the
      // user took out of the daily pool must not keep contributing to it.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final kept = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Kept',
        repertoireSide: Side.white,
      );
      final dropped = await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Dropped',
        repertoireSide: Side.white,
      );

      await controller.toggleStudyActive(dropped.study.id, false);

      final state = container.read(reviewControllerProvider).requireValue;
      final keptProgress = state.studyProgress[kept.study.id]!;
      expect(keptProgress.totalDecisions, 2);
      expect(
        state.totalProgress.totalDecisions,
        keptProgress.totalDecisions,
        reason: 'a study that is out of the daily pool still contributed to the library total',
      );
      expect(state.totalProgress.totalDecisions, lessThan(3));
    });

    test('activeScopeProgress reports the scope the user is looking at', () async {
      // SPEC INV-030. The header reads the scope's own figures: a colour scope
      // reports that colour's tally, not the whole library's, so opening the
      // Black drawer must not show the White positions.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'White book',
        repertoireSide: Side.white,
      );
      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Black book',
        repertoireSide: Side.black,
      );

      await controller.changeScope(const ReviewScope.white());

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, const ReviewScope.white());
      expect(state.activeScopeProgress, isNotNull);
      expect(
        state.activeScopeProgress!.totalDecisions,
        state.sideProgress[Side.white]!.totalDecisions,
        reason: "the colour scope reported another scope's figures",
      );
      expect(
        state.activeScopeProgress!.totalDecisions,
        lessThan(state.totalProgress.totalDecisions),
        reason: 'the colour scope reported the whole library instead of one colour',
      );
    });

    test("deleting the study in scope falls back to that study's own colour", () async {
      // SPEC INV-030. The two drawer squares have to keep showing which one is
      // live, so deleting the study the user is looking at lands them on that
      // study's colour rather than on the other one.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final black = await controller.importPgnText(
        pgnText: '1. e4 e6 2. d4 d5 *',
        title: 'Black book',
        repertoireSide: Side.black,
      );
      await controller.changeScope(ReviewScope.study(black.study.id));
      expect(container.read(reviewControllerProvider).requireValue.activeSide, Side.black);

      await controller.deleteStudy(black.study.id);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(
        state.scope,
        const ReviewScope.black(),
        reason: 'the drawer fell back to the other colour',
      );
      expect(state.activeSide, Side.black);
      expect(state.currentPrompt, isNull, reason: 'the deleted study is still on the board');
    });

    test("flipStudyColors creates the other side's copy, titled for that side", () async {
      // SPEC INV-013 / INV-030. A White repertoire and its Black counterpart
      // are different questions, so flipping produces a second study trained
      // from Black — and it says so in its title, which is how the user tells
      // the two apart in the library.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'French',
        repertoireSide: Side.white,
      );

      final flipped = await controller.flipStudyColors(white.study.id, targetSide: Side.black);

      expect(flipped, isNotNull);
      expect(
        flipped!.study.title,
        'French (Black)',
        reason: 'the flipped copy is not titled for the side it trains',
      );
      final chapters = await repo.getChaptersByStudy(flipped.study.id);
      expect(chapters, isNotEmpty);
      expect(
        chapters.map((c) => c.orientation),
        everyElement(Side.black),
        reason: 'the flipped copy still trains from the original side',
      );
    });

    test('flipStudyColors replaces a stale side suffix instead of stacking one', () async {
      // SPEC INV-013. A study that already says which side it trains must not
      // end up called "French (White) (Black)" after being flipped.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final white = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'French (white)',
        repertoireSide: Side.white,
      );

      final flipped = await controller.flipStudyColors(white.study.id, targetSide: Side.black);

      expect(flipped, isNotNull);
      expect(
        flipped!.study.title,
        'French (Black)',
        reason: 'the side suffix was stacked instead of replaced',
      );
    });

    test("exportStudyPgn exports the study's moves", () async {
      // SPEC INV-013. The export is what the study actions sheet hands to the
      // analysis board, so a study that exports only its headers is a study
      // the user cannot analyse.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Italian',
        repertoireSide: Side.white,
      );

      final pgn = await controller.exportStudyPgn(imported.study.id);

      expect(pgn, isNotNull);
      expect(pgn, contains('e4'));
      expect(pgn, contains('e5'));
      expect(pgn, contains('Nf3'));
    });

    test("exportChapterPgn exports the chapter's moves", () async {
      // SPEC INV-013. The chapter rows are stored without their trees, so the
      // export has to load the tree back before it can write the moves; a
      // chapter that skips that step exports as an empty study.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Italian',
        repertoireSide: Side.white,
      );
      final chapters = await repo.getChaptersByStudy(imported.study.id);
      expect(chapters, isNotEmpty);

      final pgn = await controller.exportChapterPgn(chapters.first.id);

      expect(pgn, isNotNull);
      expect(pgn, contains('e4'));
      expect(pgn, contains('Nf3'));
      expect(
        pgn,
        contains('[Event "Italian"]'),
        reason: 'the exported chapter lost the title of the study it belongs to',
      );
    });

    test('dismissUnlockPrompt drops the pending unlock without unlocking anything', () async {
      // SPEC INV-030. Declining to open a line has to close the prompt, and it
      // must not open the line behind the user's back.
      final container = createContainer();
      await container.read(studyPreferencesProvider.notifier).toggleDynamicRepertoireMode();

      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Dynamic Practice Study',
        repertoireSide: Side.white,
      );
      await controller.startPracticeMode();
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);
      expect(container.read(reviewControllerProvider).requireValue.pendingUnlock, isNotNull);

      controller.dismissUnlockPrompt();

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.pendingUnlock, isNull, reason: 'the unlock prompt is still on screen');
      expect(
        await repo.getUnlockedDecisionIds(),
        isEmpty,
        reason: 'declining the prompt unlocked the line anyway',
      );
    });

    test('unlockBranch unlocks the whole branch, not only the answered decision', () async {
      // SPEC INV-030. Opening a line means the whole line: the decisions below
      // the one that was answered belong to the same branch, and leaving them
      // locked makes the unlock look successful while the branch stays shut.
      final container = createContainer();
      await container.read(studyPreferencesProvider.notifier).toggleDynamicRepertoireMode();

      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Dynamic Practice Study',
        repertoireSide: Side.white,
      );

      await controller.startPracticeMode();
      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.pendingUnlock, isNotNull);
      final pending = state.pendingUnlock!;

      await controller.unlockBranch(pending.decisionId, pending.chapterId);

      final unlocked = await repo.getUnlockedDecisionIds();
      expect(unlocked, contains(pending.decisionId));

      final continuation = imported.decisions.firstWhere((d) => d.expectedMoves.first.san == 'Nf3');
      expect(
        unlocked,
        contains(continuation.id),
        reason: 'only the answered decision was unlocked; the branch below it stayed locked',
      );
    });

    test('a daily review limit of zero means no limit at all', () async {
      // SPEC INV-031. Zero is the "unlimited" setting: the session queues the
      // whole scope and the screen does not report the day's allowance as
      // spent. Treating zero as a cap of zero would empty the queue.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 Nc6 *',
        title: 'Italian',
        repertoireSide: Side.white,
      );

      await container.read(studyPreferencesProvider.notifier).setMaxDailyReviews(0);
      await container.read(studyPreferencesProvider.notifier).setMaxNewPerDay(0);

      // The setting change rebuilds the session by itself; the screen must not
      // keep the session it had while the new allowance was read.
      await waitUntil(() => container.read(reviewControllerProvider).value?.maxDailyReviews == 0);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.maxDailyReviews, 0);
      expect(
        state.isDailyLimitReached,
        isFalse,
        reason: 'zero means unlimited, not "the allowance is spent"',
      );
      expect(state.currentPrompt, isNotNull, reason: 'the session was capped at zero positions');
      expect(state.session?.initialQueueCount, greaterThan(1));
    });

    test('answering a due position moves every due figure by exactly one', () async {
      // SPEC INV-030 / INV-031. The debt is shown in several places at once —
      // the top bar, the study's figure, the chapter's, the colour's and the
      // per-side menu. Answering one position has to move every one of them
      // by exactly one, or the numbers the user reads disagree with each
      // other. Two overdue positions make a decrement of two visible.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '[Event "Sicilian Defense"]\n1. e4 c5 2. Nf3 d6 3. Bb5 a6 *',
        title: 'Sicilian',
        repertoireSide: Side.white,
      );
      expect(imported.decisions.length, 3);

      // Two overdue positions and one still fresh.
      final past = clock.now().subtract(const Duration(days: 2));
      for (final decision in imported.decisions.take(2)) {
        await repo.saveReviewState(
          ReviewState(
            decisionId: decision.id,
            repetitionCount: 3,
            stability: 1000.0,
            nextDueAt: past,
          ),
        );
      }

      await controller.reload();
      var state = container.read(reviewControllerProvider).requireValue;
      final studyId = imported.study.id;
      final chapterId = state.currentPrompt!.chapterId;
      final opening = (await repo.getChaptersByStudy(studyId)).first.opening;
      expect(opening, isNotNull, reason: 'the fixture lost its opening family');

      expect(state.totalDueCount, 2);
      expect(state.studyDueCounts[studyId], 2);
      expect(state.studyProgress[studyId]!.dueDecisions, 2);
      expect(state.studyProgress[studyId]!.freshDecisions, 1);
      expect(state.openingDueCounts[opening], 2);
      expect(state.openingProgress[opening]!.dueDecisions, 2);

      final expected = state.currentPrompt!.expectedMoves.first;
      await controller.onUserMove(
        NormalMove(
          from: Square.fromName(expected.from),
          to: Square.fromName(expected.to),
          promotion: expected.promotion != null ? Role.fromChar(expected.promotion!) : null,
        ),
      );

      state = container.read(reviewControllerProvider).requireValue;
      expect(
        state.totalDueCount,
        1,
        reason: 'the top bar dropped by more than the one position answered',
      );
      expect(state.studyDueCounts[studyId], 1);
      expect(state.studyProgress[studyId]!.dueDecisions, 1);
      expect(
        state.studyProgress[studyId]!.learnedDecisions,
        2,
        reason: 'a position that was already learned was counted as newly learned',
      );
      expect(state.chapterProgress[chapterId]!.dueDecisions, 1);
      expect(state.openingDueCounts[opening], 1);
      expect(state.openingProgress[opening]!.dueDecisions, 1);
      expect(state.sideProgress[Side.white]!.dueDecisions, 1);
      expect(state.studySideProgress[studyId]![Side.white]!.dueDecisions, 1);
    });

    test('answering a fresh position retires the introduction and records the learning', () async {
      // SPEC INV-068 / INV-030. A never-presented position is *introduced* by
      // its first answer: the fresh count falls by one and the learned count
      // rises by one. Every figure the screen shows has to move, not only the
      // colour's — the others are read off the same session.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '[Event "Sicilian Defense"]\n1. e4 c5 2. Nf3 d6 *',
        title: 'Sicilian',
        repertoireSide: Side.white,
      );
      final studyId = imported.study.id;
      final opening = (await repo.getChaptersByStudy(studyId)).first.opening;
      expect(opening, isNotNull, reason: 'the fixture lost its opening family');

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalFreshCount, 2);
      expect(state.studyProgress[studyId]!.freshDecisions, 2);
      expect(state.studyProgress[studyId]!.learnedDecisions, 0);

      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));

      state = container.read(reviewControllerProvider).requireValue;
      final chapterId = state.currentPrompt?.chapterId ?? imported.decisions.first.chapterId;
      expect(state.totalFreshCount, 1);
      expect(
        state.studyDueCounts[studyId],
        0,
        reason: 'answering a fresh position charged the study a debt it did not owe',
      );
      expect(state.studyProgress[studyId]!.freshDecisions, 1);
      expect(state.studyProgress[studyId]!.learnedDecisions, 1);
      expect(state.chapterProgress[chapterId]!.freshDecisions, 1);
      expect(state.chapterProgress[chapterId]!.learnedDecisions, 1);
      expect(state.openingProgress[opening]!.freshDecisions, 1);
      expect(state.openingProgress[opening]!.learnedDecisions, 1);
      expect(state.sideProgress[Side.white]!.freshDecisions, 1);
      expect(state.sideProgress[Side.white]!.learnedDecisions, 1);
      expect(state.studySideProgress[studyId]![Side.white]!.freshDecisions, 1);
      expect(state.studySideProgress[studyId]![Side.white]!.learnedDecisions, 1);
    });

    test('answering a fresh position does not charge the study a debt it owes elsewhere', () async {
      // SPEC INV-030 / INV-068. The study's due figure counts the debt of the
      // whole study. Answering a position that was never presented retires
      // that position's introduction; it does not pay a debt the study owes
      // for a different position.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Mixed',
        repertoireSide: Side.white,
      );
      final studyId = imported.study.id;
      // The second position is owed; the first was never presented.
      await repo.saveReviewState(
        ReviewState(
          decisionId: imported.decisions.last.id,
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: clock.now().subtract(const Duration(days: 2)),
        ),
      );
      await controller.reload();

      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.studyDueCounts[studyId], 1);

      // The owed position is queued first; skip it so the fresh one is on the
      // board while the debt is still on the books.
      controller.skip();
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNotNull);
      expect(state.studyDueCounts[studyId], 1);

      final expected = state.currentPrompt!.expectedMoves.first;
      await controller.onUserMove(
        NormalMove(
          from: Square.fromName(expected.from),
          to: Square.fromName(expected.to),
          promotion: expected.promotion != null ? Role.fromChar(expected.promotion!) : null,
        ),
      );

      state = container.read(reviewControllerProvider).requireValue;
      expect(
        state.studyDueCounts[studyId],
        1,
        reason: 'the study was charged for a debt it did not owe',
      );
    });

    test('an opening scope reports the side its family is trained on', () async {
      // SPEC INV-030. The top bar's colour squares are the only way into a
      // drawer, so an opening scope has to show the colour that family trains
      // rather than whichever colour the board happens to be on.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '[Event "Sicilian Defense"]\n1. e4 c5 2. Nf3 d6 *',
        title: 'Black Sicilian',
        repertoireSide: Side.black,
      );
      final opening = (await repo.getChaptersByStudy(imported.study.id)).first.opening!;

      // A second, unrelated repertoire, so the library's own figures differ
      // from the opening's.
      await controller.importPgnText(
        pgnText: '1. d4 d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );

      await controller.changeScope(ReviewScope.opening(opening));

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.scope, ReviewScope.opening(opening));
      expect(state.activeSide, Side.black, reason: 'the opening scope shows the wrong colour');
      expect(
        state.activeScopeProgress!.totalDecisions,
        state.openingProgress[opening]!.totalDecisions,
        reason: "the opening scope reports another scope's figures",
      );
      expect(
        state.activeScopeProgress!.totalDecisions,
        lessThan(state.totalProgress.totalDecisions),
        reason: 'the opening scope reports the whole library instead of the family',
      );
    });

    test('a black study with nothing queued still shows the black orientation', () async {
      // SPEC INV-030. The board is shown from the repertoire's own colour, and
      // with nothing queued there is no prompt to take that colour from — the
      // study's chapters are what say which side it trains.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e6 *',
        title: 'Black book',
        repertoireSide: Side.black,
      );
      await repo.saveReviewState(
        ReviewState(
          decisionId: imported.decisions.first.id,
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: clock.now().add(const Duration(days: 3)),
        ),
      );
      await controller.reload();

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.currentPrompt, isNull, reason: 'the fixture still queues a position');
      expect(state.boardOrientation, Side.black);

      // The same colour, read from the chapter rather than from the study.
      final chapter = (await repo.getChaptersByStudy(imported.study.id)).first;
      await controller.changeScope(
        ReviewScope.chapter(studyId: imported.study.id, chapterId: chapter.id),
      );
      final chapterState = container.read(reviewControllerProvider).requireValue;
      expect(chapterState.boardOrientation, Side.black);
    });

    test('an import with nothing to train names the reason it was refused', () async {
      // SPEC INV-011. A refused import has to say why, and the reason is the
      // only thing the user gets: "nothing to train" and "the move was
      // illegal" are different problems with different fixes.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await expectLater(
        controller.importPgnText(
          pgnText: '1. e4 *',
          title: 'Wrong side',
          repertoireSide: Side.black,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no moves for the selected side'),
          ),
        ),
      );
    });

    test('importLichessStudy keeps the title it is given', () async {
      // SPEC INV-013. The title the user typed is the title their study has;
      // the PGN header is only a fallback for when they did not type one.
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/study/t3St1234.pgn') {
          return http.Response(
            '[Event "Catalan Opening"]\n1. d4 Nf6 2. c4 e6 *\n',
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
        title: 'My Catalan',
        repertoireSide: Side.white,
      );

      expect(result.study.title, 'My Catalan');
    });

    test('a shape-only annotation still pauses the advancement', () async {
      // SPEC INV-021. An arrow on the board is an annotation too: the learner
      // has to see it before the queue moves on, so a comment carrying only a
      // shape and no text still holds the advancement.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 {[%cal Ge4d5]} e5 2. Nf3 *',
        title: 'Shape only',
        repertoireSide: Side.white,
      );

      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result, isNotNull);
      expect(result!.isCorrect, isTrue);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(
        state.isAwaitingAdvance,
        isTrue,
        reason: 'the board arrow was skipped and the queue moved on without it',
      );
    });

    test('prewarming a capture reports a capture', () async {
      // SPEC INV-050. The drag pre-warm decides the sound before the move
      // lands, so it has to recognise a capture for what it is.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 d5 2. exd5 *',
        title: 'Exchange',
        repertoireSide: Side.white,
      );
      await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      await waitUntil(
        () =>
            container
                .read(reviewControllerProvider)
                .value
                ?.currentPrompt
                ?.expectedMoves
                .any((m) => m.san == 'exd5') ==
            true,
      );

      controller.prewarmMoveCandidate(Square.e4);

      expect(controller.prewarmedCandidateMove, isNotNull);
      expect(
        controller.prewarmedIsCapture,
        isTrue,
        reason: 'the capture was pre-warmed as a quiet move',
      );
    });

    test('the review is not complete while a fresh position is still queued', () async {
      // SPEC INV-068 / INV-030. "Complete" means there is nothing left to
      // answer. A position that was never presented is still work, so the
      // screen must not report the queue as finished while one is on the
      // board.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'Fresh',
        repertoireSide: Side.white,
      );

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 0);
      expect(state.totalFreshCount, 1);
      expect(state.currentPrompt, isNotNull);
      expect(
        state.isComplete,
        isFalse,
        reason: 'a fresh position was reported as nothing left to do',
      );
    });

    test('the review is not complete while a due position is still on the board', () async {
      // SPEC INV-030. A position that is owed still counts as debt, so the
      // screen must not report the queue as finished while it is on the board.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 *',
        title: 'Owed',
        repertoireSide: Side.white,
      );
      await repo.saveReviewState(
        ReviewState(
          decisionId: imported.decisions.first.id,
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: clock.now().subtract(const Duration(days: 2)),
        ),
      );

      await controller.reload();

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.totalDueCount, 1);
      expect(state.totalFreshCount, 0);
      expect(state.currentPrompt, isNotNull);
      expect(
        state.isComplete,
        isFalse,
        reason: 'an owed position was reported as nothing left to do',
      );
    });

    test('copyWith keeps the pending unlock unless it is explicitly cleared', () {
      // SPEC INV-030. Every partial update the controller publishes goes
      // through copyWith, so a field the update does not mention has to
      // survive it — otherwise an unrelated touch on the board silently
      // dismisses the question the user was asked.
      const pending = (decisionId: 'd1', chapterId: 'c1', moveSan: 'e4');
      const state = ReviewScreenState(
        studies: <Study>[],
        scope: ReviewScope.all(),
        totalDueCount: 0,
        totalFreshCount: 0,
        studyDueCounts: <String, int>{},
        pendingUnlock: pending,
      );

      expect(state.copyWith(totalDueCount: 5).pendingUnlock, pending);
    });

    test('a state built without a lapse is not marked as awaiting acknowledgement', () {
      // SPEC INV-021. The lapse banner is the screen's "that move was wrong"
      // affordance; a screen that has never seen a move must not show it.
      const state = ReviewScreenState(
        studies: <Study>[],
        scope: ReviewScope.all(),
        totalDueCount: 0,
        totalFreshCount: 0,
        studyDueCounts: <String, int>{},
      );

      expect(state.isLapseAcknowledged, isTrue);
      expect(state.feedback, ReviewFeedback.none);
    });

    test('changing the scheduler preference rebuilds the session with the new scheduler', () async {
      // SPEC INV-026. The session grades with the scheduler it was built
      // with, so a settings change has to rebuild it: the screen must not
      // keep grading with the old scheduler until the next scope change.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Italian',
        repertoireSide: Side.white,
      );
      expect(
        container.read(reviewControllerProvider).requireValue.session!.scheduler,
        isA<SimpleScheduler>(),
      );

      await container
          .read(studyPreferencesProvider.notifier)
          .setSchedulerType(SchedulerType.easeScaling);

      await waitUntil(
        () =>
            container.read(reviewControllerProvider).value?.session?.scheduler
                is EaseScalingScheduler,
      );
      expect(
        container.read(reviewControllerProvider).requireValue.session!.scheduler,
        isA<EaseScalingScheduler>(),
        reason: 'the live session still grades with the previous scheduler',
      );
    });

    test('in ordinary review the unlock prompt is not raised', () async {
      // SPEC INV-030. The unlock question belongs to practice mode, where the
      // learner is walking material they have not earned. Ordinary review must
      // not raise it, or every answer in a dynamic repertoire opens a prompt
      // the user never asked for.
      final container = createContainer();
      await container.read(studyPreferencesProvider.notifier).toggleDynamicRepertoireMode();

      final controller = container.read(reviewControllerProvider.notifier);
      final imported = await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Dynamic Review',
        repertoireSide: Side.white,
      );

      // A learned, overdue position: in dynamic mode it is unlocked, so
      // ordinary review has something to queue.
      await repo.saveReviewState(
        ReviewState(
          decisionId: imported.decisions.first.id,
          repetitionCount: 3,
          stability: 1000.0,
          nextDueAt: clock.now().subtract(const Duration(days: 2)),
        ),
      );
      await controller.reload();
      expect(container.read(reviewControllerProvider).requireValue.currentPrompt, isNotNull);

      final result = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(result?.isCorrect, isTrue);

      final state = container.read(reviewControllerProvider).requireValue;
      expect(state.isPracticeMode, isFalse);
      expect(
        state.pendingUnlock,
        isNull,
        reason: 'ordinary review raised the practice-mode unlock prompt',
      );
    });

    test('a correct answer clears the lapse banner, the comment and the step result', () async {
      // SPEC INV-021. The lapse banner, the revealed comment and the step
      // result belong to the position that was answered wrong. Once the
      // learner has the position right and the queue moves on, none of them
      // may still be on screen.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. d4 {Good move} d5 *',
        title: 'Queen Pawn',
        repertoireSide: Side.white,
      );

      final lapse = await controller.onUserMove(const NormalMove(from: Square.e2, to: Square.e4));
      expect(lapse?.isCorrect, isFalse);
      var state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.incorrect);
      expect(state.isLapseAcknowledged, isFalse);
      expect(state.revealedComment, isNotNull);

      final retry = await controller.onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
      expect(retry?.isCorrect, isTrue);
      state = container.read(reviewControllerProvider).requireValue;
      expect(state.isAwaitingAdvance, isTrue, reason: 'the comment did not hold the advancement');

      await controller.continueAdvancement();

      state = container.read(reviewControllerProvider).requireValue;
      expect(state.feedback, ReviewFeedback.none);
      expect(
        state.isLapseAcknowledged,
        isTrue,
        reason: 'the lapse banner is still on screen after the position was answered',
      );
      expect(
        state.revealedComment,
        isNull,
        reason: 'the comment of the answered position is still on screen',
      );
      expect(
        state.lastStepResult,
        isNull,
        reason: 'the result of the lapsed attempt is still on screen',
      );
    });

    test('changing the continuity preference updates the live session', () async {
      // SPEC INV-030. Line continuity steers future traversals, so it has to
      // reach the session that is already running instead of waiting for the
      // next load.
      final container = createContainer();
      final controller = container.read(reviewControllerProvider.notifier);

      await controller.importPgnText(
        pgnText: '1. e4 e5 2. Nf3 *',
        title: 'Italian',
        repertoireSide: Side.white,
      );
      final session = container.read(reviewControllerProvider).requireValue.session!;
      expect(session.continuity, ReviewContinuity.dueOnly);

      await container
          .read(studyPreferencesProvider.notifier)
          .setReviewContinuity(ReviewContinuity.fullLine);

      expect(
        session.continuity,
        ReviewContinuity.fullLine,
        reason: 'the live session kept the previous continuity setting',
      );
    });
  });
}
