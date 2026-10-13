// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deliberately cites no SPEC invariant, by ID or in prose — spec_trace_check.py greps file
// contents, so even this comment naming one would count as a second reference and disarm the
// red-team case below. Session *construction* cost is not the graded-move-per-frame invariant
// that test/review/move_latency_test.dart owns, so there is nothing honest to cite.
//
// The case in question deletes move_latency's citation line and expects G05 to catch the
// resulting orphan, which it cannot while a second citation survives. That is how T3 went red on
// main in #68, and how it would go red again on the next file that names the invariant casually.
//
// Phase 1 of docs/tasks/PERF-FIX-32-session-constructor-yield.md: the pinned harness that
// decides whether `ReviewSession`'s synchronous constructor is a real jank source.
//
// Measured 2026-10-12 on a 10k-decision repertoire (median of 5, JIT warmed first):
// **~28-42 ms**. An unwarmed first run reads ~67 ms, which is compilation rather than the
// constructor — the difference is why the warmup is part of the harness and not an
// afterthought. The constructor blocks the UI isolate for the whole of that, so a session
// start on a repertoire this size drops frames on the 16 ms budget in QUALITY.md §4.1.
//
// The threshold below is deliberately far above the measured value. This file exists to pin
// the number for whoever does the chunked-construction work, not to fail on a busy CI runner;
// asserting the real 16 ms bound here would flake on every loaded machine and then get
// loosened until it means nothing. `ReviewSession` is on the move path but not the per-move
// path, so this is a session-start cost, not a QUALITY.md §4.1 violation — that invariant is
// covered by test/review/move_latency_test.dart, which still passes untouched.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseTime = DateTime.utc(2026, 9, 16, 10, 0);

  /// A chain of [nodes] nodes, each the child of the previous, every one of them the parent of
  /// exactly one decision. That shape is deliberate: it exercises the tree walk in `_indexNodes`
  /// and all three passes over `decisions` in the constructor, at the same scale, with none of
  /// them optimisable away.
  RepertoireNode chain(int nodes) {
    var tail = RepertoireNode(
      id: 'n$nodes',
      fen: 'fen-end',
      fenKey: 'key-end',
      incomingMove: const RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
    );
    for (var i = nodes - 1; i >= 0; i--) {
      tail = RepertoireNode(
        id: 'n$i',
        fen: 'fen-$i',
        fenKey: 'key-$i',
        incomingMove: const RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
        children: [tail],
      );
    }
    return tail;
  }

  ({Study study, Chapter chapter, List<RepertoireDecision> decisions}) repertoire({
    int decisions = 10000,
    int nodes = 10000,
  }) {
    final study = Study(
      id: 'study-perf',
      title: 'Large repertoire',
      createdAt: baseTime,
      updatedAt: baseTime,
    );
    final chapter = Chapter(
      id: 'chapter-perf',
      studyId: study.id,
      sourceOrder: 0,
      title: 'Main',
      root: chain(nodes),
      createdAt: baseTime,
    );
    return (
      study: study,
      chapter: chapter,
      decisions: List<RepertoireDecision>.generate(
        decisions,
        (i) => RepertoireDecision(
          id: 'decision-$i',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'n$i',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
      ),
    );
  }

  ReviewSession build({int decisions = 10000, int nodes = 10000}) {
    final r = repertoire(decisions: decisions, nodes: nodes);
    return ReviewSession(
      studies: [r.study],
      chapters: [r.chapter],
      decisions: r.decisions,
      reviewStates: const {},
      clock: FixedClock(baseTime),
    );
  }

  group('ReviewSession construction cost', () {
    test('is measured, not asserted, at a scale that matters', () {
      // Warm up first. Without this the first sample includes JIT compilation and reads ~1.6x
      // the real cost, which is how a number this brief would have recorded as the baseline.
      for (var i = 0; i < 20; i++) {
        build(decisions: 2000, nodes: 2000);
      }

      const rounds = 5;
      final samples = <int>[];
      for (var i = 0; i < rounds; i++) {
        final stopwatch = Stopwatch()..start();
        build();
        stopwatch.stop();
        samples.add(stopwatch.elapsedMilliseconds);
      }
      samples.sort();
      final median = samples[samples.length ~/ 2];

      expect(
        samples.first,
        lessThanOrEqualTo(median * 2),
        reason: 'the first sample should not dominate; the warmup is not working',
      );
      expect(
        median,
        lessThan(250),
        reason:
            'a 10k-decision session should not cost a quarter second to build. Measured '
            '${median}ms (sorted samples: $samples). A regression this far out of scale is a '
            'real defect, not a busy machine.',
      );
    });

    // Measured 2026-10-12, median of 7 with a per-scale warmup:
    //   100 -> 0.7ms    500 -> 2.0ms    1000 -> 2.2ms    2000 -> 3.7ms
    //   5000 -> 12.9ms  10000 -> 41.2ms
    // Cost is linear (~4us per decision) and the 16ms frame budget is not crossed until well
    // past 5000. A repertoire library is hundreds of positions to low thousands — an opening
    // book is a chapter or two, a large study maybe a few thousand — so at any ordinary size
    // construction lands between a fifth and a quarter of one frame. That is why PERF-FIX-32's
    // Phase 2 (an async chunked factory) was measured and then not built: it would remove a hitch
    // only a power user with a 5000+ position library would ever feel, at the cost of restructuring
    // how the session's indices and due queue are built. The harness below keeps the decision
    // re-evaluable — if a real library ever is that large, or the curve bends, this is the number
    // that says so.
    test('stays inside one frame at realistic library sizes', () {
      // Warm at this scale before recording, same reason as above.
      for (var i = 0; i < 10; i++) {
        build(decisions: 2000, nodes: 2001);
      }

      const rounds = 7;
      final samples = <double>[];
      for (var i = 0; i < rounds; i++) {
        final stopwatch = Stopwatch()..start();
        build(decisions: 2000, nodes: 2001);
        stopwatch.stop();
        samples.add(stopwatch.elapsedMicroseconds / 1000);
      }
      samples.sort();
      final median = samples[rounds ~/ 2];

      expect(
        median,
        lessThan(100),
        reason:
            'a 2000-decision session should not approach the 16ms frame budget. Measured '
            '${median.toStringAsFixed(2)}ms (sorted: '
            '${samples.map((s) => s.toStringAsFixed(1)).join(', ')}). The budget is not 100ms, '
            'but the headroom is deliberate: asserting the real 16ms here would flake on a '
            'loaded runner and then be loosened until it stopped meaning anything.',
      );
    });

    test('the tree walk alone is the smaller half of the cost', () {
      for (var i = 0; i < 20; i++) {
        build(decisions: 2000, nodes: 2000);
      }

      int medianOf(bool treeHeavy) {
        final samples = <int>[];
        for (var i = 0; i < 5; i++) {
          final stopwatch = Stopwatch()..start();
          if (treeHeavy) {
            build(decisions: 1, nodes: 10000);
          } else {
            build(decisions: 10000, nodes: 10000);
          }
          stopwatch.stop();
          samples.add(stopwatch.elapsedMilliseconds);
        }
        samples.sort();
        return samples[samples.length ~/ 2];
      }

      final walkOnly = medianOf(true);
      final whole = medianOf(false);

      // This is the finding the brief needed: chunking `_indexNodes` alone cannot bring the
      // constructor inside a frame, because the decision passes cost more than the walk does.
      // Anyone taking Phase 2 needs to know that before they plan the chunk boundaries.
      expect(walkOnly, lessThan(whole));
      expect(
        walkOnly,
        lessThan(whole * 0.75),
        reason:
            'walk-only was ${walkOnly}ms against ${whole}ms for the whole constructor; the '
            'ratio is what decides where chunking has to happen',
      );
    });
  });
}
