// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Clock abstraction for deterministic domain testing.
library;

/// The UTC calendar day of [instant], as a comparable key.
///
/// `yyyyMMdd`, so two keys are equal exactly when the two instants fall on
/// the same UTC day.
int utcDayKey(DateTime instant) {
  final utc = instant.toUtc();
  return utc.year * 10000 + utc.month * 100 + utc.day;
}

/// Clock abstraction for injectable time source in SRS logic.
///
/// All time-dependent domain functions accept a [Clock] so that test suites
/// can run deterministically without depending on system wall-clock time
/// (QUALITY.md §3.2: Deterministic Time Testing).
abstract class Clock {
  /// Returns the current instant.
  DateTime now();

  /// The local calendar day [instant] falls on, as a comparable key.
  ///
  /// Day-scoped rules compare instants that reach them from two frames: the
  /// clock's own time, and the UTC instants the store reloads. The day has to
  /// be decided in one frame (INV-028), and the frame is the reader's local
  /// day — a grant made at 00:30 local belongs to that local day, not to the
  /// UTC day it falls on.
  ///
  /// The default is the UTC day: the frame the store speaks, and the one a
  /// fixed clock's instants are already in. A clock that reports the reader's
  /// local time overrides this, so a stored instant lands on the day the
  /// reader experienced it.
  int localDayKey(DateTime instant) => utcDayKey(instant);
}

/// Production clock: delegates to [DateTime.now].
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  /// The reader's local day.
  ///
  /// The store reloads timestamps as UTC instants, so placing one on a
  /// calendar day needs the reader's wall clock rather than UTC's. The offset
  /// is the one in effect now, which is the same approximation the store's
  /// own local-midnight boundary makes.
  @override
  int localDayKey(DateTime instant) {
    final local = instant.toLocal();
    return local.year * 10000 + local.month * 100 + local.day;
  }
}

/// Fixed clock for deterministic unit tests.
///
/// [value] can be mutated between test steps to simulate time passing.
class FixedClock implements Clock {
  FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  /// The UTC day, like the default: a fixed clock's instants are already in
  /// the frame it reports.
  @override
  int localDayKey(DateTime instant) => utcDayKey(instant);

  /// Advance the clock by [duration].
  void advance(Duration duration) {
    value = value.add(duration);
  }
}
