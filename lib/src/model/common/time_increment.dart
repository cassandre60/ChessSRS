import 'package:chess_srs/src/model/common/speed.dart';
import 'package:flutter/widgets.dart';

/// A pair of time and increment in seconds used as game clock
@immutable
class TimeIncrement implements Comparable<TimeIncrement> {
  const TimeIncrement(this.time, this.increment) : assert(time >= 0 && increment >= 0);

  TimeIncrement.fromDurations(Duration time, Duration increment)
    : time = time.inSeconds,
      increment = increment.inSeconds,
      assert(time >= Duration.zero && increment >= Duration.zero);

  const TimeIncrement.infinite() : time = 0, increment = 0;

  /// Clock initial time in seconds
  final int time;

  /// Clock increment in seconds
  final int increment;

  TimeIncrement.fromJson(Map<String, dynamic> json)
    : time = json['time'] as int,
      increment = json['increment'] as int;

  Map<String, dynamic> toJson() => {'time': time, 'increment': increment};

  /// Returns the estimated duration of the game, with increment * 40 added to
  /// the initial time.
  Duration get estimatedDuration => Duration(seconds: time + increment * 40);

  Speed get speed => Speed.fromTimeIncrement(this);

  bool get isInfinite => time == 0 && increment == 0;

  String get display {
    if (isInfinite) {
      return '∞';
    } else {
      return '${clockLabelInMinutes(time)}+$increment';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeIncrement &&
          runtimeType == other.runtimeType &&
          time == other.time &&
          increment == other.increment;

  @override
  int get hashCode => Object.hash(time, increment);

  @override
  String toString() => 'TimeIncrement($time+$increment)';

  @override
  int compareTo(TimeIncrement other) {
    return estimatedDuration.compareTo(other.estimatedDuration);
  }

  static const presets = [
    TimeIncrement(0, 1),
    TimeIncrement(60, 0),
    TimeIncrement(60, 1),
    TimeIncrement(120, 1),
    TimeIncrement(180, 0),
    TimeIncrement(180, 2),
    TimeIncrement(300, 0),
    TimeIncrement(300, 3),
    TimeIncrement(600, 0),
    TimeIncrement(600, 5),
    TimeIncrement(900, 0),
    TimeIncrement(900, 10),
    TimeIncrement(1500, 0),
    TimeIncrement(1800, 0),
    TimeIncrement(1800, 20),
    TimeIncrement(3600, 0),
  ];
}

/// Displays a chess clock time in minutes from an amount of seconds
String clockLabelInMinutes(num seconds) {
  switch (seconds) {
    case 0:
      return '0';
    case 45:
      return '¾';
    case 30:
      return '½';
    case 15:
      return '¼';
    default:
      return (seconds / 60).toString().replaceAll('.0', '');
  }
}

const kAvailableTimesInSeconds = [
  0,
  15,
  30,
  45,
  60,
  90,
  2 * 60,
  3 * 60,
  4 * 60,
  5 * 60,
  6 * 60,
  7 * 60,
  8 * 60,
  9 * 60,
  10 * 60,
  11 * 60,
  12 * 60,
  13 * 60,
  14 * 60,
  15 * 60,
  16 * 60,
  17 * 60,
  18 * 60,
  19 * 60,
  20 * 60,
  25 * 60,
  30 * 60,
  35 * 60,
  40 * 60,
  45 * 60,
  60 * 60,
  75 * 60,
  90 * 60,
  105 * 60,
  120 * 60,
  135 * 60,
  150 * 60,
  165 * 60,
  180 * 60,
];

const kAvailableIncrementsInSeconds = [
  0,
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  25,
  30,
  35,
  40,
  45,
  60,
  90,
  120,
  150,
  180,
];
