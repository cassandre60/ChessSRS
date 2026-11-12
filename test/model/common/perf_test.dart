import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Perf.fromVariantAndSpeed', () {
    test('maps standard speeds', () {
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.ultraBullet), Perf.ultraBullet);
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.bullet), Perf.bullet);
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.blitz), Perf.blitz);
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.rapid), Perf.rapid);
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.classical), Perf.classical);
      expect(Perf.fromVariantAndSpeed(Variant.standard, Speed.correspondence), Perf.correspondence);
    });

    test('maps variants regardless of speed', () {
      expect(Perf.fromVariantAndSpeed(Variant.chess960, Speed.blitz), Perf.chess960);
      expect(Perf.fromVariantAndSpeed(Variant.fromPosition, Speed.rapid), Perf.fromPosition);
      expect(Perf.fromVariantAndSpeed(Variant.antichess, Speed.bullet), Perf.antichess);
      expect(Perf.fromVariantAndSpeed(Variant.kingOfTheHill, Speed.classical), Perf.kingOfTheHill);
      expect(Perf.fromVariantAndSpeed(Variant.threeCheck, Speed.ultraBullet), Perf.threeCheck);
      expect(Perf.fromVariantAndSpeed(Variant.atomic, Speed.blitz), Perf.atomic);
      expect(Perf.fromVariantAndSpeed(Variant.horde, Speed.rapid), Perf.horde);
      expect(Perf.fromVariantAndSpeed(Variant.racingKings, Speed.bullet), Perf.racingKings);
      expect(Perf.fromVariantAndSpeed(Variant.crazyhouse, Speed.correspondence), Perf.crazyhouse);
    });
  });

  group('Perf.nameMap', () {
    test('contains all perf enum names', () {
      for (final perf in Perf.values) {
        expect(Perf.nameMap[perf.name], perf);
      }
    });
  });

  group('Pick perf extensions', () {
    test('asPerfOrThrow returns Perf value directly', () {
      expect(pick(Perf.blitz).asPerfOrThrow(), Perf.blitz);
    });

    test('asPerfOrThrow parses exact name strings', () {
      expect(pick('rapid').asPerfOrThrow(), Perf.rapid);
      expect(pick('chess960').asPerfOrThrow(), Perf.chess960);
    });

    test('asPerfOrThrow parses normalized title strings and aliases', () {
      expect(pick('UltraBullet').asPerfOrThrow(), Perf.ultraBullet);
      expect(pick('ultra bullet').asPerfOrThrow(), Perf.ultraBullet);
      expect(pick('ultra-bullet').asPerfOrThrow(), Perf.ultraBullet);
      expect(pick('king_of_the_hill').asPerfOrThrow(), Perf.kingOfTheHill);
      expect(pick('puzzles').asPerfOrThrow(), Perf.puzzle);
      expect(pick('From Position').asPerfOrThrow(), Perf.fromPosition);
    });

    test('asPerfOrThrow parses map payload with key', () {
      expect(pick({'key': 'blitz'}).asPerfOrThrow(), Perf.blitz);
    });

    test('asPerfOrThrow throws on unknown value', () {
      expect(() => pick('not-a-perf').asPerfOrThrow(), throwsA(isA<PickException>()));
    });

    test('asPerfOrNull returns null for null/missing and invalid', () {
      expect(pick(null).asPerfOrNull(), isNull);
      expect(pick('not-a-perf').asPerfOrNull(), isNull);
    });
  });
}
