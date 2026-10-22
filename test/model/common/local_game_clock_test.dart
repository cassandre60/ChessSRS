// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-041.

import 'package:chess_srs/src/model/common/local_game_clock.dart';
import 'package:chess_srs/src/model/common/time_increment.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A concrete clock with a fixed time control, so a test can say what the
/// game started with.
class TestClock extends LocalGameClock {
  TestClock({this.increment = const TimeIncrement(60, 5)});

  final TimeIncrement increment;

  @override
  TimeIncrement get defaultTimeIncrement => increment;
}

final testClockProvider = NotifierProvider<TestClock, LocalGameClockState>(TestClock.new);

void main() {
  group('LocalGameClock', () {
    // SPEC INV-041. Time enters the clock only through the clock itself: the
    // countdown is charged from the app clock, so a test advances it with the
    // fake clock rather than sleeping. Nothing here waits for real time.
    test('the clock does not run before the first move', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [testClockProvider.overrideWith(() => TestClock())],
        );
        addTearDown(container.dispose);

        final state = container.read(testClockProvider);
        expect(state.activeClock, isNull);
        expect(state.active, isFalse);
        expect(state.whiteTimeLeft, const Duration(seconds: 60));
        expect(state.blackTimeLeft, const Duration(seconds: 60));

        // Time passing does not start the clock: no side is running.
        async.elapse(const Duration(seconds: 5));
        expect(container.read(testClockProvider).whiteTimeLeft, const Duration(seconds: 60));
        expect(container.read(testClockProvider).blackTimeLeft, const Duration(seconds: 60));
      });
    });

    test('the first move starts the clock and gives the increment to the mover', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [testClockProvider.overrideWith(() => TestClock())],
        );
        addTearDown(container.dispose);

        container
            .read(testClockProvider.notifier)
            .switchSide(newSideToMove: Side.black, addIncrement: true);

        final state = container.read(testClockProvider);
        // White just moved: White is credited the increment and Black is to move.
        expect(state.whiteTimeLeft, const Duration(seconds: 65));
        expect(state.blackTimeLeft, const Duration(seconds: 60));
        expect(state.activeClock, Side.black);
        expect(state.active, isTrue);
      });
    });

    test('the running side is charged and the other side is not', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [testClockProvider.overrideWith(() => TestClock())],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        notifier.switchSide(newSideToMove: Side.black, addIncrement: true);

        async.elapse(const Duration(seconds: 10));

        final state = container.read(testClockProvider);
        expect(state.blackTimeLeft, const Duration(seconds: 50));
        expect(state.whiteTimeLeft, const Duration(seconds: 65));
      });
    });

    test('a side that runs out of time is flagged', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [testClockProvider.overrideWith(() => TestClock())],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        notifier.setupClock(
          const TimeIncrement(60, 0),
          whiteTimeLeft: const Duration(seconds: 1),
          blackTimeLeft: const Duration(seconds: 1),
        );
        notifier.switchSide(newSideToMove: Side.black, addIncrement: false);

        async.elapse(const Duration(seconds: 2));

        final state = container.read(testClockProvider);
        expect(state.flagSide, Side.black);
        expect(state.blackTimeLeft, lessThanOrEqualTo(Duration.zero));
      });
    });

    test('a side whose time reaches exactly zero is flagged', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            testClockProvider.overrideWith(() => TestClock(increment: const TimeIncrement(60, 0))),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        notifier.setupClock(
          const TimeIncrement(60, 0),
          whiteTimeLeft: const Duration(seconds: 1),
          blackTimeLeft: const Duration(seconds: 1),
        );
        notifier.switchSide(newSideToMove: Side.black, addIncrement: false);

        // Exactly one second: the side to move is out of time, not a
        // millisecond short of it.
        async.elapse(const Duration(seconds: 1));

        final state = container.read(testClockProvider);
        expect(state.blackTimeLeft, Duration.zero);
        expect(state.flagSide, Side.black);
      });
    });

    test('a flagged clock does not switch sides', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            testClockProvider.overrideWith(() => TestClock(increment: const TimeIncrement(60, 0))),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        notifier.setupClock(
          const TimeIncrement(60, 0),
          whiteTimeLeft: const Duration(seconds: 1),
          blackTimeLeft: const Duration(seconds: 1),
        );
        notifier.switchSide(newSideToMove: Side.black, addIncrement: false);
        async.elapse(const Duration(seconds: 2));
        expect(container.read(testClockProvider).flagSide, Side.black);

        // The game is over: a further switch must not resurrect the clock.
        notifier.switchSide(newSideToMove: Side.white, addIncrement: true);
        expect(container.read(testClockProvider).flagSide, Side.black);
        expect(container.read(testClockProvider).activeClock, Side.black);
      });
    });

    test('a paused clock is not charged and resumes where it stopped', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [testClockProvider.overrideWith(() => TestClock())],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        notifier.switchSide(newSideToMove: Side.black, addIncrement: true);
        async.elapse(const Duration(seconds: 10));
        expect(container.read(testClockProvider).blackTimeLeft, const Duration(seconds: 50));

        notifier.pause();
        expect(container.read(testClockProvider).activeClock, isNull);
        async.elapse(const Duration(seconds: 10));
        expect(container.read(testClockProvider).blackTimeLeft, const Duration(seconds: 50));

        notifier.resume(Side.black);
        expect(container.read(testClockProvider).activeClock, Side.black);
        async.elapse(const Duration(seconds: 5));
        expect(container.read(testClockProvider).blackTimeLeft, const Duration(seconds: 45));
      });
    });

    test('an unlimited game has no clock to run', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            testClockProvider.overrideWith(
              () => TestClock(increment: const TimeIncrement.infinite()),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(testClockProvider.notifier);
        final state = container.read(testClockProvider);
        expect(state.whiteTimeLeft, isNull);
        expect(state.blackTimeLeft, isNull);

        notifier.switchSide(newSideToMove: Side.black, addIncrement: true);
        expect(container.read(testClockProvider).activeClock, isNull);
        expect(container.read(testClockProvider).active, isFalse);
      });
    });

    test('the starting time is the larger of the time and the increment', () {
      // A game with 3 seconds and a 10-second increment starts with 10
      // seconds on the clock, not 3.
      final state = LocalGameClockState.fromTimeIncrement(const TimeIncrement(3, 10));
      expect(state.whiteTimeLeft, const Duration(seconds: 10));
      expect(state.blackTimeLeft, const Duration(seconds: 10));
      expect(state.activeClock, isNull);
      expect(state.flagSide, isNull);
    });

    test('timeLeft reads the side it is asked about', () {
      final state = LocalGameClockState.fromTimeIncrement(
        const TimeIncrement(60, 0),
        whiteTimeLeft: const Duration(seconds: 11),
        blackTimeLeft: const Duration(seconds: 22),
      );
      expect(state.timeLeft(Side.white), const Duration(seconds: 11));
      expect(state.timeLeft(Side.black), const Duration(seconds: 22));
    });
  });
}
