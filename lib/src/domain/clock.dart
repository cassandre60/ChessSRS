// Copyright (C) 2024 ChessSRS contributors
library chess_srs.domain.clock;

// SPDX-License-Identifier: GPL-3.0-or-later

/// Clock abstraction for injectable time source in SRS logic.
///
/// All time-dependent domain functions accept a [Clock] so that test suites
/// can run deterministically without depending on system wall-clock time
/// (QUALITY.md §3.2: Deterministic Time Testing).
abstract class Clock {
  /// Returns the current instant.
  DateTime now();
}

/// Production clock: delegates to [DateTime.now].
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Fixed clock for deterministic unit tests.
///
/// [value] can be mutated between test steps to simulate time passing.
class FixedClock implements Clock {
  FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  /// Advance the clock by [duration].
  void advance(Duration duration) {
    value = value.add(duration);
  }
}
