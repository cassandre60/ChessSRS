import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/common/time_increment.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Speed.fromTimeIncrement', () {
    test('maps boundary durations to expected speeds', () {
      expect(Speed.fromTimeIncrement(const TimeIncrement(0, 0)), Speed.correspondence);
      expect(Speed.fromTimeIncrement(const TimeIncrement(1, 0)), Speed.ultraBullet);
      expect(Speed.fromTimeIncrement(const TimeIncrement(29, 0)), Speed.ultraBullet);
      expect(Speed.fromTimeIncrement(const TimeIncrement(30, 0)), Speed.bullet);
      expect(Speed.fromTimeIncrement(const TimeIncrement(179, 0)), Speed.bullet);
      expect(Speed.fromTimeIncrement(const TimeIncrement(180, 0)), Speed.blitz);
      expect(Speed.fromTimeIncrement(const TimeIncrement(479, 0)), Speed.blitz);
      expect(Speed.fromTimeIncrement(const TimeIncrement(480, 0)), Speed.rapid);
      expect(Speed.fromTimeIncrement(const TimeIncrement(1499, 0)), Speed.rapid);
      expect(Speed.fromTimeIncrement(const TimeIncrement(1500, 0)), Speed.classical);
      expect(Speed.fromTimeIncrement(const TimeIncrement(21599, 0)), Speed.classical);
      expect(Speed.fromTimeIncrement(const TimeIncrement(21600, 0)), Speed.correspondence);
    });

    test('uses estimated duration including increment', () {
      // 60s + 3*40s = 180s -> blitz
      expect(Speed.fromTimeIncrement(const TimeIncrement(60, 3)), Speed.blitz);
    });
  });

  group('Speed.nameMap', () {
    test('contains all speed values by name', () {
      for (final speed in Speed.values) {
        expect(Speed.nameMap[speed.name], speed);
      }
    });
  });

  group('SpeedExtension.asSpeedOrThrow', () {
    test('returns Speed values directly', () {
      expect(pick(Speed.rapid).asSpeedOrThrow(), Speed.rapid);
    });

    test('parses known speed names', () {
      expect(pick('bullet').asSpeedOrThrow(), Speed.bullet);
      expect(pick('correspondence').asSpeedOrThrow(), Speed.correspondence);
    });

    test('throws for unknown speed names', () {
      expect(() => pick('hyperbullet').asSpeedOrThrow(), throwsA(isA<PickException>()));
    });

    test('throws for non-string, non-Speed values', () {
      expect(() => pick(42).asSpeedOrThrow(), throwsA(isA<PickException>()));
    });
  });

  group('TimeIncrementSpeed', () {
    test('exposes speed getter', () {
      expect(const TimeIncrement(300, 0).speed, Speed.blitz);
      expect(const TimeIncrement(600, 0).speed, Speed.rapid);
    });
  });
}
