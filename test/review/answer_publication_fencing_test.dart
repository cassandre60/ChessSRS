// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC INV-032. An answer may finish persisting after a replacement scope loads,
// but its verdict, animation and error recovery must not take that scope over.

import 'dart:async';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';
import '../model/common/service/fake_sound_service.dart';

/// Holds one answer before its real SQLite transaction, not the grader or loader.
class _PendingAnswerRepository extends SqliteStudyRepository {
  _PendingAnswerRepository(super.db);

  final reachedWrite = Completer<void>();
  final releaseWrite = Completer<void>();
  bool holdAnswer = false;
  final failure = StateError('answer transaction failed');
  bool failAnswer = false;

  @override
  Future<void> saveAnswerBatch({
    required List<PositionKnowledgeState> knowledgeStates,
    ReviewEvent? event,
  }) async {
    if (holdAnswer) {
      reachedWrite.complete();
      await releaseWrite.future;
      holdAnswer = false;
      if (failAnswer) throw failure;
    }
    await super.saveAnswerBatch(knowledgeStates: knowledgeStates, event: event);
  }
}

class _TestReviewPreferences extends StudyPreferencesNotifier {
  @override
  StudyPrefs build() => StudyPrefs.defaults.copyWith(animateOpponentPreMove: false);
}

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late _PendingAnswerRepository repo;
  late ProviderContainer container;
  late FixedClock clock;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    final batch = db.batch();
    createSrsTables(batch);
    await batch.commit();
    repo = _PendingAnswerRepository(db);
    clock = FixedClock(DateTime.utc(2026, 10, 22, 10));
    container = ProviderContainer(
      overrides: [
        srsStudyRepositoryProvider.overrideWith((ref) => repo),
        clockProvider.overrideWithValue(clock),
        soundServiceProvider.overrideWithValue(FakeSoundService()),
        studyPreferencesProvider.overrideWith(_TestReviewPreferences.new),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  for (final scenario in [
    (name: 'correct', retry: false, fail: false, annotated: false),
    (name: 'correct with commentary', retry: false, fail: false, annotated: true),
    (name: 'incorrect', retry: false, fail: false, annotated: false),
    (name: 'failed initial write', retry: false, fail: true, annotated: false),
    (name: 'correct retry', retry: true, fail: false, annotated: false),
    (name: 'failed retry write', retry: true, fail: true, annotated: false),
  ]) {
    test(
      '${scenario.name} answer finishing after a scope switch leaves the new scope intact',
      () async {
        // Import real, legal trees with different orientations and board positions.
        // A's learned continuation earns exposure on retry, so retry really awaits
        // saveAnswerBatch rather than only exercising its synchronous no-write arm.
        final comment = scenario.annotated ? ' {Remember this move}' : '';
        final a = importPgn('1. e4$comment e5 2. Nf3 Nc6 *', repertoireSide: Side.white);
        final b = importPgn('1. d4 d5 2. c4 e6 *', repertoireSide: Side.black);
        await repo.saveImportResult(a);
        await repo.saveImportResult(b);
        final previousDay = clock.now().subtract(const Duration(days: 1));
        for (final decision in [...a.decisions, ...b.decisions]) {
          final isContinuation = decision.expectedMoves.first.uci == 'g1f3';
          await repo.savePositionKnowledgeState(
            PositionKnowledgeState.fromReviewState(
              ReviewState(
                decisionId: decision.id,
                firstReviewedAt: previousDay,
                lastReviewedAt: previousDay,
                repetitionCount: 1,
                stability: const Duration(days: 1).inMilliseconds.toDouble(),
                nextDueAt: isContinuation ? clock.now().add(const Duration(days: 1)) : previousDay,
              ),
              canonicalId: decision.canonicalId,
            ),
          );
        }

        await container.read(reviewControllerProvider.future);
        final controller = container.read(reviewControllerProvider.notifier);
        final service = container.read(reviewServiceProvider);
        await controller.changeScope(ReviewScope.study(a.study.id));
        final decisionA = container
            .read(reviewControllerProvider)
            .requireValue
            .currentPrompt!
            .decision;
        const correct = NormalMove(from: Square.e2, to: Square.e4);
        const incorrect = NormalMove(from: Square.d2, to: Square.d4);
        if (scenario.retry) {
          final lapse = await controller.onUserMove(incorrect);
          expect(lapse?.isCorrect, isFalse);
        }
        final beforeWrite = await repo.getPositionKnowledgeState(decisionA.canonicalId);
        final beforeEvents = await repo.getReviewEvents(decisionA.id);
        final sessionA = service.activeSession!;
        final checkpointPrompt = sessionA.currentPrompt;

        repo.holdAnswer = true;
        repo.failAnswer = scenario.fail;
        final answer = controller.onUserMove(scenario.name == 'incorrect' ? incorrect : correct);
        final Future<void>? errorCheck = scenario.fail
            ? expectLater(answer, throwsA(same(repo.failure)))
            : null;
        await repo.reachedWrite.future.timeout(const Duration(seconds: 5));

        await controller.changeScope(ReviewScope.study(b.study.id));
        final stateB = container.read(reviewControllerProvider).requireValue;
        final sessionB = stateB.session!;
        final promptB = sessionB.currentPrompt!;
        expect(stateB.scope.studyId, b.study.id);
        expect(stateB.currentPrompt!.studyId, b.study.id);
        expect(stateB.boardPosition!.fen, promptB.fen);
        expect(stateB.boardOrientation, Side.black);
        expect(service.activeSession, same(sessionB));
        expect(sessionB, isNot(same(sessionA)));

        final publications = <ReviewScreenState>[];
        final subscription = container.listen(reviewControllerProvider, (previous, next) {
          if (next.asData != null) publications.add(next.requireValue);
        });
        repo.releaseWrite.complete();
        if (errorCheck != null) {
          await errorCheck;
        } else {
          final result = await answer;
          expect(result, isNotNull);
          expect(result!.isCorrect, scenario.name != 'incorrect');
        }
        // Check every publication, not just a final snapshot: even a brief old
        // verdict/comment/Continue repaint violates the ownership contract.
        expect(publications, isEmpty, reason: 'the stale answer republished its old scope');
        expect(container.read(reviewControllerProvider).requireValue, same(stateB));
        expect(service.activeSession, same(sessionB));
        expect(sessionB.currentPrompt, same(promptB));
        subscription.close();

        final storedA = await repo.getPositionKnowledgeState(decisionA.canonicalId);
        final eventsA = await repo.getReviewEvents(decisionA.id);
        if (scenario.fail) {
          expect(storedA, beforeWrite);
          expect(eventsA, beforeEvents);
          expect(sessionA.currentPrompt?.decision.id, checkpointPrompt?.decision.id);
        } else if (scenario.retry) {
          expect(
            storedA,
            beforeWrite,
            reason: 'retry must not erase or re-grade the persisted lapse',
          );
          expect(eventsA, beforeEvents);
          final continuation = a.decisions.singleWhere((d) => d.expectedMoves.first.uci == 'g1f3');
          expect(
            (await repo.getPositionKnowledgeState(continuation.canonicalId))!.lastExposedAt,
            clock.now(),
          );
        } else {
          expect(eventsA, hasLength(beforeEvents.length + 1));
          expect(storedA!.lastReviewedAt, clock.now());
          expect(storedA.lapseCount, scenario.name == 'incorrect' ? 1 : 0);
        }
        expect(await repo.getReviewEvents(promptB.decision.id), isEmpty);

        // The old finally block must release input, and the next move must be
        // judged by B's real grader, not A's now-completed session.
        final resultB = await controller.onUserMove(Move.parse(promptB.expectedMoves.first.uci)!);
        expect(resultB?.isCorrect, isTrue);
        expect(
          (await repo.getReviewEvents(promptB.decision.id)).single.decisionId,
          promptB.decision.canonicalId,
        );
      },
    );
  }
}
