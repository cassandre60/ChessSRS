// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-027, INV-028, INV-029, INV-068.

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'in_memory_review_state_repository.dart';

void main() {
  final baseNow = DateTime.utc(2026, 6, 15, 12);

  group('graph contagion & exposure properties', () {
    test(
      'INV-027 lapse contagion is bounded to depth 3, shrinks stability, and skips unlearned',
      () {
        // SPEC INV-027. Across random chains of depth 6 with mixed learned/unlearned states,
        // contagion never reaches depth >= 4, never contaminates unlearned nodes (and stops
        // at unlearned barriers), and monotonically shrinks stability for contiguous learned
        // descendants within depth <= 3 without exceeding [1.0, 10.0] difficulty.
        final rng = Random(505);

        for (var trial = 0; trial < 30; trial++) {
          final initialStates = <String, ReviewState>{};
          final childrenMap = <String, List<String>>{};

          // Build a 6-deep chain: d0 -> d1 -> d2 -> d3 -> d4 -> d5
          for (var d = 0; d < 6; d++) {
            final id = 'node-$trial-$d';
            if (d < 5) {
              childrenMap[id] = ['node-$trial-${d + 1}'];
            }
            final isLearned = d == 0 || rng.nextBool();
            if (isLearned) {
              final stabilityDays = 2 + rng.nextInt(25);
              initialStates[id] = ReviewState(
                decisionId: id,
                firstReviewedAt: baseNow.subtract(const Duration(days: 10)),
                lastReviewedAt: baseNow.subtract(const Duration(days: 2)),
                nextDueAt: baseNow.add(Duration(days: stabilityDays)),
                repetitionCount: 1 + rng.nextInt(4),
                lapseCount: rng.nextInt(2),
                stability: Duration(days: stabilityDays).inMilliseconds.toDouble(),
                difficulty: 3.0 + rng.nextDouble() * 5.0,
              );
            } else {
              initialStates[id] = ReviewState.initial(decisionId: id);
            }
          }

          final repo = InMemoryReviewStateRepository(
            initialStates: initialStates,
            childrenMap: childrenMap,
          );
          final coordinator = GraphAwareReviewCoordinator(
            scheduler: const SimpleScheduler(),
            repo: repo,
          );

          coordinator.recordActiveReview(
            node: GraphNode(
              decisionId: 'node-$trial-0',
              fen4: 'fen-$trial-0',
              expectedMoveUci: 'e2e4',
              hasCanonicalIdentity: true,
            ),
            result: ReviewResult.incorrect,
            now: baseNow,
          );

          var chainBrokenByUnlearned = false;
          for (var d = 1; d < 6; d++) {
            final id = 'node-$trial-$d';
            final before = initialStates[id]!;
            final after = repo.get(id)!;

            if (before.stability <= 0) {
              chainBrokenByUnlearned = true;
            }

            if (d > 3 || chainBrokenByUnlearned) {
              // Unlearned, behind an unlearned barrier, or beyond maxContagionDepth (3): untouched
              expect(
                after,
                equals(before),
                reason:
                    'depth $d (broken=$chainBrokenByUnlearned) must not be modified (trial $trial)',
              );
            } else {
              expect(after.stability, lessThan(before.stability));
              expect(after.stability, greaterThan(0));
              expect(after.difficulty, greaterThanOrEqualTo(before.difficulty));
              expect(after.difficulty, inInclusiveRange(1.0, 10.0));
            }
          }
        }
      },
    );

    test(
      'INV-028 auto-traversal exposure credit is micro, once-per-day, and skips due/unlearned',
      () {
        // SPEC INV-028. Exposure credit never applies to unlearned or due items, and
        // applies at most once per calendar day for learned non-due items.
        final rng = Random(606);

        for (var trial = 0; trial < 30; trial++) {
          final id = 'exp-$trial';
          final isLearned = rng.nextBool();
          final isDueNow = rng.nextBool();

          final initial = !isLearned
              ? ReviewState.initial(decisionId: id)
              : ReviewState(
                  decisionId: id,
                  firstReviewedAt: baseNow.subtract(const Duration(days: 5)),
                  lastReviewedAt: baseNow.subtract(const Duration(days: 2)),
                  nextDueAt: isDueNow
                      ? baseNow.subtract(Duration(hours: 1 + rng.nextInt(24)))
                      : baseNow.add(Duration(days: 1 + rng.nextInt(14))),
                  repetitionCount: 2,
                  stability: const Duration(days: 5).inMilliseconds.toDouble(),
                  difficulty: 5.0,
                );

          final repo = InMemoryReviewStateRepository(initialStates: {id: initial});
          final coordinator = GraphAwareReviewCoordinator(
            scheduler: const SimpleScheduler(),
            repo: repo,
          );
          final node = GraphNode(
            decisionId: id,
            fen4: 'fen-$id',
            expectedMoveUci: 'd2d4',
            hasCanonicalIdentity: true,
          );

          final firstGrant = coordinator.recordAutoTraversalExposure(node: node, now: baseNow);
          if (!isLearned || isDueNow) {
            expect(firstGrant, equals(initial));
          } else {
            expect(firstGrant!.stability, greaterThan(initial.stability));
            expect(firstGrant.repetitionCount, equals(initial.repetitionCount));
            expect(firstGrant.lapseCount, equals(initial.lapseCount));

            // Second exposure on the same calendar day is throttled
            final secondGrant = coordinator.recordAutoTraversalExposure(
              node: node,
              now: baseNow.add(const Duration(hours: 3)),
            );
            expect(
              secondGrant,
              equals(firstGrant),
              reason: 'INV-028: same-day exposure must be throttled (trial $trial)',
            );
          }
        }
      },
    );

    test(
      'INV-029 sibling coupling bumps only the sibling whose expected move matches playedMoveUci',
      () {
        // SPEC INV-029. Siblings couple only on genuine confusion.
        final rng = Random(707);
        const moves = ['e2e4', 'd2d4', 'c2c4', 'g1f3'];

        for (var trial = 0; trial < 20; trial++) {
          final initialStates = <String, ReviewState>{
            'primary': ReviewState(
              decisionId: 'primary',
              firstReviewedAt: baseNow.subtract(const Duration(days: 4)),
              lastReviewedAt: baseNow.subtract(const Duration(days: 2)),
              nextDueAt: baseNow,
              repetitionCount: 1,
              stability: 86400000.0,
              difficulty: 5.0,
            ),
          };
          final siblings = <GraphNode>[];
          for (var i = 0; i < moves.length; i++) {
            final sibId = 'sib-$i';
            initialStates[sibId] = ReviewState(
              decisionId: sibId,
              firstReviewedAt: baseNow.subtract(const Duration(days: 4)),
              lastReviewedAt: baseNow.subtract(const Duration(days: 2)),
              nextDueAt: baseNow.add(const Duration(days: 3)),
              repetitionCount: 2,
              stability: 172800000.0,
              difficulty: 4.0 + rng.nextDouble() * 3.0,
            );
            siblings.add(
              GraphNode(
                decisionId: sibId,
                fen4: 'fen-$sibId',
                expectedMoveUci: moves[i],
                hasCanonicalIdentity: true,
              ),
            );
          }

          final playedIdx = rng.nextInt(moves.length);
          final playedMove = moves[playedIdx];
          final repo = InMemoryReviewStateRepository(initialStates: initialStates);
          final coordinator = GraphAwareReviewCoordinator(
            scheduler: const SimpleScheduler(),
            repo: repo,
          );

          coordinator.recordActiveReview(
            node: const GraphNode(
              decisionId: 'primary',
              fen4: 'fen-primary',
              expectedMoveUci: 'b1c3',
              hasCanonicalIdentity: true,
            ),
            result: ReviewResult.incorrect,
            now: baseNow,
            playedMoveUci: playedMove,
            siblings: siblings,
          );

          for (var i = 0; i < moves.length; i++) {
            final sibId = 'sib-$i';
            final before = initialStates[sibId]!;
            final after = repo.get(sibId)!;
            if (i == playedIdx) {
              expect(after.difficulty, greaterThan(before.difficulty));
            } else {
              expect(after, equals(before));
            }
          }
        }
      },
    );

    test('INV-068 ReviewSession respects remainingNewQuota cap while preserving due work', () {
      // SPEC INV-068. A position is due only once it has been presented; fresh introductions
      // are capped at remainingNewQuota while due positions are never held back by new-quota.
      final rng = Random(808);
      final study = Study.create(title: 'CapStudy');
      final root = RepertoireNode.root(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      );
      final chapter = Chapter.create(studyId: study.id, title: 'Ch1', sourceOrder: 0, root: root);

      for (var trial = 0; trial < 25; trial++) {
        final totalCount = 5 + rng.nextInt(16);
        final decisions = <RepertoireDecision>[];
        final states = <String, ReviewState>{};
        var expectedDue = 0;
        var expectedFresh = 0;

        for (var i = 0; i < totalCount; i++) {
          final id = 'dec-$trial-$i';
          final fen4 = '8/8/8/8/8/8/8/K6k w - - $i';
          final dec = RepertoireDecision(
            id: id,
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: root.id,
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: id,
            fenKey: fen4,
          );
          decisions.add(dec);

          final kind = rng.nextInt(3); // 0 = fresh, 1 = due, 2 = scheduled future
          if (kind == 0) {
            expectedFresh++;
          } else if (kind == 1) {
            expectedDue++;
            states[id] = ReviewState(
              decisionId: id,
              firstReviewedAt: baseNow.subtract(const Duration(days: 3)),
              lastReviewedAt: baseNow.subtract(const Duration(days: 1)),
              nextDueAt: baseNow.subtract(const Duration(hours: 2)),
              repetitionCount: 1,
              stability: 86400000.0,
            );
          } else {
            states[id] = ReviewState(
              decisionId: id,
              firstReviewedAt: baseNow.subtract(const Duration(days: 3)),
              lastReviewedAt: baseNow.subtract(const Duration(hours: 2)),
              nextDueAt: baseNow.add(const Duration(days: 4)),
              repetitionCount: 2,
              stability: 345600000.0,
            );
          }
        }

        final newCap = rng.nextInt(expectedFresh + 3);
        final session = ReviewSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: states,
          clock: FixedClock(baseNow),
          remainingNewQuota: newCap,
        );

        expect(session.scopeDueCount, equals(expectedDue));
        expect(session.scopeFreshCount, equals(expectedFresh));
        expect(session.initialDueCount, equals(expectedDue));
        final admittedFresh = min(expectedFresh, newCap);
        expect(session.initialQueueCount, equals(expectedDue + admittedFresh));
      }
    });
  });
}
