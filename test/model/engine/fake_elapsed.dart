import 'package:clock/clock.dart';

/// How long a wait took, on the clock the wait was scheduled on.
///
/// A [Stopwatch] measures the machine, which is the one thing a test that asserts on a
/// duration must not do: the same wait takes longer on a loaded runner, and the assertion
/// then fails for a reason that has nothing to do with the code under test. This reads the
/// clock the wait was scheduled on instead, so the number is the schedule's.
///
/// Build it inside the `fakeAsync` zone — the zone's clock is the fake one — and call
/// [markEnded] when the wait is over.
class FakeElapsed {
  FakeElapsed() : _start = clock.now();

  final DateTime _start;
  DateTime? _endedAt;

  /// The moment the wait ended.
  void markEnded() => _endedAt ??= clock.now();

  /// How long the wait took, on the clock it was scheduled on.
  Duration get elapsed => (_endedAt ?? clock.now()).difference(_start);
}
