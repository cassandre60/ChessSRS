// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-016, INV-030.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';
import '../model/common/service/fake_sound_service.dart';

/// Owner report 2026-10-06: a White study's `...` menu offered no way to
/// generate its Black counterpart into the Black menu, and the two colours
/// shared SRS memory instead of scheduling independently.
///
/// A flipped study is the same lines trained from the other side: the same
/// chapter and decision counts, the opposite orientation, fresh (empty) SRS
/// memory, and canonical position keys disjoint from the original's — the
/// same position with the other side to move is a different question
/// (INV-016's sharing rule keys on the position *and* its replies, and the
/// turn is part of the position). Each side scope then counts only its own
/// study (INV-030).
void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // White to move at every White decision, Black at every Black one, over the
  // same move tree — so the two derivations are counterparts, not copies.
  const whitePgn = '''
[Event "French"]
[Orientation "white"]
1. e4 e6 2. d4 d5 *
''';

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
    clock = FixedClock(DateTime.utc(2026, 10, 6, 12));
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer createContainer() {
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
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> importWhite(ReviewController controller) async {
    final result = await controller.importPgnText(pgnText: whitePgn, title: 'French');
    return result.study.id;
  }

  test('flip creates the opposite-side study over the same lines', () async {
    // SPEC INV-030.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);
    final whiteId = await importWhite(controller);

    final flipped = await controller.flipStudyColors(whiteId, targetSide: Side.black);

    expect(flipped, isNotNull, reason: 'a trainable study must flip');
    expect(flipped!.isDuplicate, isFalse);
    expect(flipped.study.title, 'French (Black)');
    final whiteChapters = await repo.getChaptersByStudy(whiteId);
    final blackChapters = await repo.getChaptersByStudy(flipped.study.id);
    expect(blackChapters, hasLength(whiteChapters.length));
    expect(blackChapters.map((c) => c.orientation).toSet(), {
      Side.black,
    }, reason: 'every chapter of the flipped study trains Black');
    final whiteDecisions = await repo.getDecisionsByStudy(whiteId);
    final blackDecisions = await repo.getDecisionsByStudy(flipped.study.id);
    expect(whiteDecisions, isNotEmpty);
    expect(
      blackDecisions,
      hasLength(whiteDecisions.length),
      reason: 'the same tree yields one counterpart decision per original',
    );
  });

  test('the flipped study starts with no SRS memory of its own', () async {
    // SPEC INV-016: sharing keys on the position and its replies, and the
    // side to move is part of the position — so the counterpart positions
    // must not collide with the original's memory.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);
    final whiteId = await importWhite(controller);

    final flipped = await controller.flipStudyColors(whiteId, targetSide: Side.black);
    final flippedId = flipped!.study.id;

    final whiteCanonicals = (await repo.getDecisionsByStudy(
      whiteId,
    )).map((d) => d.canonicalId).toSet();
    final blackCanonicals = (await repo.getDecisionsByStudy(
      flippedId,
    )).map((d) => d.canonicalId).toSet();
    expect(
      blackCanonicals.intersection(whiteCanonicals),
      isEmpty,
      reason: 'counterpart positions are different questions with independent history',
    );
    final states = await repo.getKnowledgeStatesByCanonicalIds(blackCanonicals.toList());
    expect(states, isEmpty, reason: 'the flipped study starts unlearned');
  });

  test('each side scope counts only its own study', () async {
    // SPEC INV-030.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);
    final service = container.read(reviewServiceProvider);
    final whiteId = await importWhite(controller);
    final flipped = await controller.flipStudyColors(whiteId, targetSide: Side.black);
    final blackId = flipped!.study.id;

    final studies = await repo.getAllStudies();
    final summary = await service.getDueSummary(studies: studies);

    expect(summary.sidesForStudy(whiteId), {Side.white});
    expect(summary.sidesForStudy(blackId), {Side.black});
    for (final studyId in [whiteId, blackId]) {
      var total = 0;
      var learned = 0;
      var due = 0;
      for (final side in summary.sidesForStudy(studyId)) {
        final perSide = summary.studyProgressForSide(studyId, side);
        total += perSide.totalDecisions;
        learned += perSide.learnedDecisions;
        due += perSide.dueDecisions;
      }
      final wide = summary.studyProgress[studyId]!;
      expect(total, wide.totalDecisions, reason: 'per-side figures partition the study figures');
      expect(learned, wide.learnedDecisions);
      expect(due, wide.dueDecisions);
    }

    final whiteDue = await service.getDueCount(scope: const ReviewScope.white());
    final blackDue = await service.getDueCount(scope: const ReviewScope.black());
    final whiteDecisions = await repo.getDecisionsByStudy(whiteId);
    final blackDecisions = await repo.getDecisionsByStudy(blackId);
    expect(whiteDue, whiteDecisions.length);
    expect(blackDue, blackDecisions.length);
  });

  test('answering on one side leaves the other side due', () async {
    // SPEC INV-030: the two colours schedule independently.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);
    final service = container.read(reviewServiceProvider);
    final whiteId = await importWhite(controller);
    final flipped = await controller.flipStudyColors(whiteId, targetSide: Side.black);

    final blackBefore = await service.getDueCount(scope: const ReviewScope.black());
    expect(blackBefore, greaterThan(0));

    final session = await service.startSession(scope: const ReviewScope.white());
    final prompt = session.currentPrompt;
    expect(prompt, isNotNull, reason: 'the White study has due positions to answer');
    final expected = prompt!.decision.expectedMoves.first;
    final result = await service.submitMove(
      from: expected.from,
      to: expected.to,
      promotion: expected.promotion,
    );
    expect(result.isCorrect, isTrue);

    final studies = await repo.getAllStudies();
    final blackAfter = (await service.getDueSummary(
      studies: studies,
      scope: const ReviewScope.black(),
    )).totalDueCount;
    expect(blackAfter, blackBefore, reason: 'a White answer must not touch Black scheduling');
    expect(flipped!.study.id, isNot(whiteId));
  });

  test('flipping back finds the original instead of copying it', () async {
    // SPEC INV-030.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);
    final whiteId = await importWhite(controller);
    final flipped = await controller.flipStudyColors(whiteId, targetSide: Side.black);

    final backAgain = await controller.flipStudyColors(flipped!.study.id, targetSide: Side.white);

    expect(backAgain, isNotNull);
    expect(backAgain!.isDuplicate, isTrue, reason: 'the White version already exists');
    expect(backAgain.study.id, whiteId, reason: 'the flip resolves to the original study');
    expect(backAgain.study.title, isNot('French (Black) (White)'));
    final studies = await repo.getAllStudies();
    expect(studies, hasLength(2), reason: 'no third copy was stored');
  });

  test('flipping an unknown study returns null', () async {
    // SPEC INV-030.
    final container = createContainer();
    final controller = container.read(reviewControllerProvider.notifier);

    expect(await controller.flipStudyColors('no-such-study', targetSide: Side.black), isNull);
  });
}
