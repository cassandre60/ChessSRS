// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-015, INV-016, INV-017.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PositionKnowledgeState & canonicalKey', () {
    test('canonicalKey produces deterministic SHA-1 hash for FEN4 and UCI move', () {
      const fenKey = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
      const uci = 'e7e5';

      final key1 = canonicalKey(fenKey, uci);
      final key2 = canonicalKey(fenKey, uci);

      expect(key1, equals(key2));
      expect(key1.length, 40); // SHA-1 hex string
    });

    test('canonicalKey is pinned to the exact separator format', () {
      // SPEC INV-015/INV-016. The canonical id is the persisted identity of
      // every memory row: a changed digest input would silently orphan the
      // whole store on the next run, so the digest value itself is pinned,
      // not just its determinism.
      const fenKey = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';

      expect(
        canonicalKey(fenKey, 'e7e5'),
        '848edc0b8842724df73f154fa05c25cca8d91603',
        reason: 'sha1("<fenKey>|<uci>"), recomputed with python hashlib as an '
            'independent oracle — dropping or moving the separator changes it',
      );
    });

    test('canonicalKey differs when FEN or move differs', () {
      const fen1 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
      const fen2 = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3';

      expect(canonicalKey(fen1, 'e7e5'), isNot(equals(canonicalKey(fen2, 'e7e5'))));
      expect(canonicalKey(fen1, 'e7e5'), isNot(equals(canonicalKey(fen1, 'c7c5'))));
    });

    group('canonicalKeyForPosition', () {
      const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

      test('is deterministic and a SHA-1 hex string', () {
        final a = canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.white);
        final b = canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.white);

        expect(a, equals(b));
        expect(a.length, 40);
      });

      test('is pinned to the side|fen|sorted-moves digest format', () {
        // SPEC INV-016/INV-017. Side, position, and the sorted accepted set
        // all participate in the identity; pinning the digest pins all of
        // them at once, where equality-only tests can each miss one.
        expect(
          canonicalKeyForPosition(
            start,
            ['e2e4', 'd2d4', 'g1f3'],
            repertoireSide: Side.white,
          ),
          'f0f16b372de0231d55826e53d2a81c977fe65b15',
          reason: 'sha1("white|<fen>|d2d4|e2e4|g1f3"), recomputed with python '
              'hashlib as an independent oracle',
        );
      });

      test('ignores the order the accepted moves are listed in', () {
        expect(
          canonicalKeyForPosition(start, ['e2e4', 'd2d4', 'g1f3'], repertoireSide: Side.white),
          equals(
            canonicalKeyForPosition(start, ['g1f3', 'd2d4', 'e2e4'], repertoireSide: Side.white),
          ),
          reason: 'reordered branches must not fork the same repertoire',
        );
      });

      test('differs when the accepted set differs even if the first move matches', () {
        // This is the collision the first-child key could not see.
        expect(
          canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.white),
          isNot(
            equals(canonicalKeyForPosition(start, ['e2e4', 'd2d4'], repertoireSide: Side.white)),
          ),
        );
        expect(
          canonicalKeyForPosition(start, ['e2e4', 'd2d4'], repertoireSide: Side.white),
          isNot(
            equals(canonicalKeyForPosition(start, ['e2e4', 'c2c4'], repertoireSide: Side.white)),
          ),
        );
      });

      test('differs when the position differs even if the accepted set matches', () {
        const elsewhere = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
        expect(
          canonicalKeyForPosition(start, ['e7e5'], repertoireSide: Side.white),
          isNot(equals(canonicalKeyForPosition(elsewhere, ['e7e5'], repertoireSide: Side.white))),
          reason: 'distinct positions must never share SRS memory',
        );
      });

      test('differs when the trained colour differs even if the move matches', () {
        // White and Black copies of the same lines are separate repertoires: reviewing one
        // must not mark the position in the other one learned.
        expect(
          canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.white),
          isNot(equals(canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.black))),
        );
      });

      test('a single-move set agrees with no other set', () {
        // Regression guard: an earlier attempt hashed the moves alone, dropping the position
        // entirely, which merged every position offering the same move.
        const elsewhereFEN = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3';
        expect(
          canonicalKeyForPosition(start, ['e2e4'], repertoireSide: Side.white),
          isNot(
            equals(canonicalKeyForPosition(elsewhereFEN, ['e2e4'], repertoireSide: Side.white)),
          ),
        );
      });
    });

    test('PositionKnowledgeState cold defaults and due calculation', () {
      final now = DateTime(2026, 9, 18, 12);
      final cold = PositionKnowledgeState.cold('canonical-123');

      expect(cold.canonicalId, 'canonical-123');
      expect(cold.isNew, isTrue);
      expect(cold.isLearned, isFalse);
      expect(cold.isDueAt(now), isTrue);
      expect(cold.stability, 0.0);
      expect(cold.difficulty, 0.0);
      expect(cold.latencySampleCount, 0);
      expect(cold.lapseCount, 0);
      expect(cold.firstReviewedAt, isNull);
      expect(cold.lastReviewedAt, isNull);
      expect(cold.nextDueAt, isNull);
      expect(cold.latencyEmaMs, isNull);
      expect(cold.lastExposedAt, isNull);
    });

    test('converts cleanly to ReviewState', () {
      final now = DateTime(2026, 9, 18, 12);
      final kState = PositionKnowledgeState(
        canonicalId: 'c-1',
        firstReviewedAt: now,
        lastReviewedAt: now,
        nextDueAt: now.add(const Duration(days: 2)),
        repetitionCount: 3,
        lapseCount: 1,
        stability: 172800000.0,
        difficulty: 4.5,
      );

      final rState = kState.toReviewState('dec-custom-id');
      expect(rState.decisionId, 'dec-custom-id');
      expect(rState.repetitionCount, 3);
      expect(rState.lapseCount, 1);
      expect(rState.stability, 172800000.0);
      expect(rState.difficulty, 4.5);
    });

    test('fromReviewState maps every scheduling field; latency stays unmeasured', () {
      // SPEC INV-016. The decision-keyed → canonical bridge must not lose
      // review memory: every field ReviewState carries lands on the
      // canonical state, and the latency family defaults to "never
      // measured" because ReviewState has no counterpart for it.
      final now = DateTime(2026, 9, 18, 12);
      final source = ReviewState(
        decisionId: 'c-bridge',
        firstReviewedAt: now,
        lastReviewedAt: now.add(const Duration(hours: 6)),
        nextDueAt: now.add(const Duration(days: 2)),
        repetitionCount: 3,
        lapseCount: 1,
        stability: 172800000.0,
        difficulty: 4.5,
      );

      final mapped = PositionKnowledgeState.fromReviewState(source, canonicalId: 'c-bridge');

      expect(mapped.firstReviewedAt, now);
      expect(mapped.lastReviewedAt, now.add(const Duration(hours: 6)));
      expect(mapped.nextDueAt, now.add(const Duration(days: 2)));
      expect(mapped.repetitionCount, 3);
      expect(mapped.lapseCount, 1);
      expect(mapped.stability, 172800000.0);
      expect(mapped.difficulty, 4.5);
      expect(mapped.latencyEmaMs, isNull, reason: 'no samples were passed');
      expect(mapped.latencySampleCount, 0);

      // Inverse direction: toReviewState without an override falls back to
      // the canonical id, so the plain round trip returns the source state.
      expect(mapped.toReviewState(), equals(source));
    });

    test('isDueAt boundary: exactly-due is due, past is due, future is not', () {
      final now = DateTime(2026, 9, 18, 12);
      final dueNow = PositionKnowledgeState(canonicalId: 'c-due', nextDueAt: now);
      final future = PositionKnowledgeState(
        canonicalId: 'c-future',
        nextDueAt: now.add(const Duration(milliseconds: 1)),
      );
      final past = PositionKnowledgeState(
        canonicalId: 'c-past',
        nextDueAt: now.subtract(const Duration(days: 3)),
      );

      expect(dueNow.isDueAt(now), isTrue, reason: 'a card due at this instant is reviewable now');
      expect(future.isDueAt(now), isFalse, reason: 'not yet due');
      expect(past.isDueAt(now), isTrue, reason: 'an overdue card is still due');
    });

    test('copyWith preserves every unspecified field', () {
      // SPEC INV-016. copyWith is the update path for every scheduling
      // transition; a dropped keep-fallback would silently null a field no
      // caller asked to change.
      final t0 = DateTime.utc(2026, 1, 1);
      final base = PositionKnowledgeState(
        canonicalId: 'canonical-1',
        firstReviewedAt: t0,
        lastReviewedAt: t0.add(const Duration(hours: 1)),
        nextDueAt: t0.add(const Duration(days: 1)),
        repetitionCount: 3,
        lapseCount: 1,
        stability: 172800000.0,
        difficulty: 4.5,
        latencyEmaMs: 1200.0,
        latencySampleCount: 4,
        lastExposedAt: t0.add(const Duration(days: 2)),
      );

      expect(base.copyWith(), equals(base), reason: 'no-arg copyWith is the identity update');
    });

    test('equality compares every field of the canonical state', () {
      // SPEC INV-016. The canonical state is a value: two separately built
      // instances with the same fields must be equal — and must not be the
      // same object, or `identical` would answer before the field chain runs.
      final t0 = DateTime.utc(2026, 1, 1);
      PositionKnowledgeState make({String canonicalId = 'canonical-1'}) {
        return PositionKnowledgeState(
          canonicalId: canonicalId,
          firstReviewedAt: t0,
          lastReviewedAt: t0.add(const Duration(hours: 1)),
          nextDueAt: t0.add(const Duration(days: 1)),
          repetitionCount: 3,
          lapseCount: 1,
          stability: 172800000.0,
          difficulty: 4.5,
          latencyEmaMs: 1200.0,
          latencySampleCount: 4,
          lastExposedAt: t0.add(const Duration(days: 2)),
        );
      }

      final a = make();
      final b = make();
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == Object(), isFalse);

      final base = make();
      final variants = <String, PositionKnowledgeState>{
        'canonicalId': make(canonicalId: 'canonical-2'),
        'firstReviewedAt': base.copyWith(firstReviewedAt: t0.add(const Duration(days: 9))),
        'lastReviewedAt': base.copyWith(lastReviewedAt: t0.add(const Duration(days: 9))),
        'nextDueAt': base.copyWith(nextDueAt: t0.add(const Duration(days: 9))),
        'repetitionCount': base.copyWith(repetitionCount: 4),
        'lapseCount': base.copyWith(lapseCount: 2),
        'stability': base.copyWith(stability: 259200000.0),
        'difficulty': base.copyWith(difficulty: 5.5),
        'latencyEmaMs': base.copyWith(latencyEmaMs: 4321.0),
        'latencySampleCount': base.copyWith(latencySampleCount: 5),
        'lastExposedAt': base.copyWith(lastExposedAt: t0.add(const Duration(days: 3))),
      };

      for (final entry in variants.entries) {
        expect(
          base == entry.value,
          isFalse,
          reason: 'a state differing in ${entry.key} must not compare equal',
        );
      }
    });

    test('an answered state is not new even without a due date', () {
      // Domain API parity with ReviewState's isNew (pinned by the scheduler
      // suite): "new" cannot be true for a state that has been answered.
      const answered = PositionKnowledgeState(
        canonicalId: 'canonical-answered',
        repetitionCount: 3,
      );

      expect(answered.isNew, isFalse);
      expect(answered.isLearned, isTrue);
    });
  });
}
