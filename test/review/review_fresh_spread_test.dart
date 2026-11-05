// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-068 (fresh introduction under a daily allowance).
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/review/fresh_introduction_order.dart';
import 'package:flutter_test/flutter_test.dart';

/// A capped introduction must grow the whole library, not just its head.
///
/// The fresh bucket is built in database/import order. Taking
/// `sublist(0, allowance)` spent every day's introduction budget inside the
/// first-imported study — the owner's "served the same line over and over
/// everyday while all the others are lost". These tests pin the two rules that
/// replaced it: groups are visited least-presented first, and every study and
/// chapter contributes before any contributes twice.
void main() {
  late FixedClock clock;
  late DateTime baseTime;

  setUp(() {
    baseTime = DateTime.utc(2026, 11, 4, 12);
    clock = FixedClock(baseTime);
  });

  /// One study per shape entry, each with [chapters] chapters of [perChapter]
  /// fresh decisions, appended study by study — the import order the old
  /// head-of-list cut followed. Every decision expects e2e4 from the standard
  /// start position, so a prompt can be answered by playing that move.
  ({
    List<Study> studies,
    List<Chapter> chapters,
    List<RepertoireDecision> decisions,
  })
  buildLibrary({required Map<String, ({int chapters, int perChapter})> shape}) {
    final studies = <Study>[];
    final chapters = <Chapter>[];
    final decisions = <RepertoireDecision>[];
    for (final entry in shape.entries) {
      final study = Study(id: entry.key, title: 'Study ${entry.key}');
      studies.add(study);
      for (var c = 0; c < entry.value.chapters; c++) {
        final chapter = Chapter.create(studyId: study.id, sourceOrder: c);
        chapters.add(chapter);
        for (var d = 0; d < entry.value.perChapter; d++) {
          decisions.add(
            RepertoireDecision.create(
              studyId: study.id,
              chapterId: chapter.id,
              nodeId: '${study.id}-${entry.key}-$c-$d',
              expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            ),
          );
        }
      }
    }
    return (studies: studies, chapters: chapters, decisions: decisions);
  }

  /// The production fresh-ordering policy over a built library.
  FreshIntroductionOrder orderFor(
    ({
      List<Study> studies,
      List<Chapter> chapters,
      List<RepertoireDecision> decisions,
    })
    library, {
    Map<String, ReviewState> states = const {},
  }) => freshIntroductionOrderFor(decisions: library.decisions, reviewStates: states);

  /// Answers every prompt (the expected move is always e2e4) and returns the
  /// decisions the session asked. `submitMove` consumes a card; `skip` only
  /// moves it to the back, so it cannot drain a session.
  List<RepertoireDecision> answerAll(ReviewSession session) {
    final served = <RepertoireDecision>[];
    while (session.currentPrompt != null) {
      served.add(session.currentPrompt!.decision);
      session.submitMove(from: 'e2', to: 'e4');
      if (served.length > 500) break;
    }
    return served;
  }

  group('fresh introduction spread', () {
    test('a capped introduction samples every study, not the first-imported one', () {
      final library = buildLibrary(
        shape: {
          'a': (chapters: 1, perChapter: 5),
          'b': (chapters: 1, perChapter: 5),
          'c': (chapters: 1, perChapter: 5),
        },
      );

      final session = ReviewEngine(clock: clock).createSession(
        studies: library.studies,
        chapters: library.chapters,
        decisions: library.decisions,
        reviewStates: const {},
        freshIntroductionOrder: orderFor(library),
        remainingNewQuota: 3,
      );
      final served = answerAll(session);

      expect(session.initialDueCount, 0, reason: 'a wholly fresh library owes nothing yet');
      expect(served, hasLength(3));
      expect(
        served.map((d) => d.studyId).toSet(),
        {'a', 'b', 'c'},
        reason:
            "the day's three introductions must come from three studies, not the first "
            'study three times',
      );
    });

    test('a capped introduction samples every chapter of one study', () {
      final library = buildLibrary(
        shape: {
          'solo': (chapters: 2, perChapter: 5),
        },
      );

      final session = ReviewEngine(clock: clock).createSession(
        studies: library.studies,
        chapters: library.chapters,
        decisions: library.decisions,
        reviewStates: const {},
        freshIntroductionOrder: orderFor(library),
        remainingNewQuota: 2,
      );
      final served = answerAll(session);

      expect(served, hasLength(2));
      expect(
        served.map((d) => d.chapterId).toSet(),
        hasLength(2),
        reason: 'two introductions in a two-chapter study must open both chapters',
      );
    });

    test('breadth builds across sessions instead of digging one study', () {
      // Twelve studies of one chapter each, three introductions a day. After
      // four days every study must have been touched; the head cut would still
      // be inside study #1.
      final library = buildLibrary(
        shape: {
          for (var s = 0; s < 12; s++) 's$s': (chapters: 1, perChapter: 5),
        },
      );

      final learned = <String, ReviewState>{};
      final touchedStudies = <String>{};

      for (var day = 0; day < 4; day++) {
        final session = ReviewEngine(clock: clock).createSession(
          studies: library.studies,
          chapters: library.chapters,
          decisions: library.decisions,
          reviewStates: Map<String, ReviewState>.of(learned),
          freshIntroductionOrder: orderFor(library, states: learned),
          remainingNewQuota: 3,
        );
        for (final decision in answerAll(session)) {
          touchedStudies.add(decision.studyId);
          learned[decision.canonicalId] = ReviewState(
            decisionId: decision.canonicalId,
            firstReviewedAt: baseTime,
            nextDueAt: baseTime.add(const Duration(days: 1)),
            repetitionCount: 1,
          );
        }
      }

      expect(
        touchedStudies.length,
        12,
        reason: 'four days of three introductions must reach all twelve studies',
      );
    });

    test('spreading never changes how many positions are introduced', () {
      final library = buildLibrary(
        shape: {
          'a': (chapters: 3, perChapter: 4),
          'b': (chapters: 2, perChapter: 4),
        },
      );

      final session = ReviewEngine(clock: clock).createSession(
        studies: library.studies,
        chapters: library.chapters,
        decisions: library.decisions,
        reviewStates: const {},
        freshIntroductionOrder: orderFor(library),
        remainingNewQuota: 6,
      );

      expect(session.initialQueueCount, 6);
      expect(session.initialDueCount, 0);
    });
  });

  group('by-line ordering (INV-066)', () {
    test('does not decode chapters outside the queue', () {
      // Twenty chapters, one fresh decision each, allowance one: only a single
      // chapter holds queued work. Building the default by-line session must
      // index on demand, not decode the other nineteen trees before the first
      // frame (which made line order the slow path on a large library).
      final library = buildLibrary(shape: {'big': (chapters: 20, perChapter: 1)});

      final session = ReviewEngine(clock: clock).createSession(
        studies: library.studies,
        chapters: library.chapters,
        decisions: library.decisions,
        reviewStates: const {},
        order: ReviewOrder.byLine,
        remainingNewQuota: 1,
      );

      expect(session.initialQueueCount, 1);
      expect(
        session.isNodeIndexComplete,
        isFalse,
        reason: 'a by-line session must index on demand, not decode the whole library up front',
      );
    });
  });

  group('full-line continuity respects the new-position allowance (INV-068)', () {
    test('does not open a fresh ancestor the allowance held back', () {
      // One line, root decision fresh and a due descendant. With no
      // introductions allowed, full-line continuity used to open the line at its
      // fresh start, bypassing the allowance; it must ask the due target.
      const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      const study = Study(id: 'line', title: 'Line');

      final chapter = Chapter(
        id: 'ch-line',
        studyId: study.id,
        sourceOrder: 0,
        startingFen: startFen,
        createdAt: baseTime,
        root: const RepertoireNode(
          id: 'r',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'e5',
                  fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                  fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'nf3',
                      fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      const rootDecision = RepertoireDecision(
        id: 'dec-root',
        studyId: 'line',
        chapterId: 'ch-line',
        nodeId: 'r',
        expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      );
      const targetDecision = RepertoireDecision(
        id: 'dec-target',
        studyId: 'line',
        chapterId: 'ch-line',
        nodeId: 'e5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      );

      final states = <String, ReviewState>{
        targetDecision.canonicalId: ReviewState(
          decisionId: targetDecision.canonicalId,
          firstReviewedAt: baseTime.subtract(const Duration(days: 3)),
          nextDueAt: baseTime.subtract(const Duration(days: 1)),
          repetitionCount: 1,
        ),
      };

      final session = ReviewEngine(clock: clock).createSession(
        studies: const [study],
        chapters: [chapter],
        decisions: const [rootDecision, targetDecision],
        reviewStates: states,
        order: ReviewOrder.byLine,
        continuity: ReviewContinuity.fullLine,
        remainingNewQuota: 0,
      );

      expect(
        session.currentPrompt?.decision.id,
        'dec-target',
        reason: 'the fresh ancestor must not be introduced past the allowance',
      );
    });
  });
}
