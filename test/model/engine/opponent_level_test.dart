import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/engine/opponent_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StockfishLevel', () {
    test('has 12 ordered levels with expected metadata', () {
      expect(StockfishLevel.values, hasLength(12));
      expect(StockfishLevel.level1.level, 1);
      expect(StockfishLevel.level12.level, 12);
      expect(StockfishLevel.level1.skill, -12);
      expect(StockfishLevel.level12.skill, 20);
      expect(StockfishLevel.level4.multiPv, 5);
      expect(StockfishLevel.level6.threads, 2);
      expect(StockfishLevel.level12.searchTime, const Duration(seconds: 2));
    });

    test('default and lookup', () {
      expect(StockfishLevel.defaultLevel, StockfishLevel.level4);
      expect(StockfishLevel.fromLevel(1), StockfishLevel.level1);
      expect(StockfishLevel.fromLevel(12), StockfishLevel.level12);
      expect(StockfishLevel.fromLevel(0), isNull);
      expect(StockfishLevel.fromLevel(13), isNull);
    });
  });

  group('MaiaRating', () {
    test('exposes rating metadata and file names', () {
      expect(MaiaRating.values, hasLength(10));
      expect(MaiaRating.maia1500.rating, 1500);
      expect(MaiaRating.maia1500.fileName, 'maia-1500.pb.gz');
      expect(MaiaRating.maia1100.sha256Prefix, hasLength(12));
      expect(MaiaRating.maia2200.expectedSize, greaterThan(0));
    });

    test('bundled/default/lookup', () {
      expect(MaiaRating.bundledRatings, {MaiaRating.maia1500});
      expect(MaiaRating.maia1500.isBundled, isTrue);
      expect(MaiaRating.maia1100.isBundled, isFalse);
      expect(MaiaRating.defaultRating, MaiaRating.maia1500);
      expect(MaiaRating.fromRating(1500), MaiaRating.maia1500);
      expect(MaiaRating.fromRating(999), isNull);
    });
  });

  group('OpponentSpec.fromJson', () {
    test('parses stockfish and maia specs', () {
      expect(
        OpponentSpec.fromJson({'type': 'stockfish', 'level': 'level7'}),
        const StockfishOpponentSpec(StockfishLevel.level7),
      );
      expect(
        OpponentSpec.fromJson({'type': 'maia', 'rating': 'maia1900'}),
        const MaiaOpponentSpec(MaiaRating.maia1900),
      );
    });

    test('falls back to default stockfish on unknown/invalid data', () {
      expect(
        OpponentSpec.fromJson({'type': 'stockfish', 'level': 'nope'}),
        OpponentSpec.defaultSpec,
      );
      expect(OpponentSpec.fromJson({'type': 'maia', 'rating': 'nope'}), OpponentSpec.defaultSpec);
      expect(OpponentSpec.fromJson({'type': 'unknown'}), OpponentSpec.defaultSpec);
      expect(OpponentSpec.fromJson(<String, dynamic>{}), OpponentSpec.defaultSpec);
      expect(OpponentSpec.defaultSpec, const StockfishOpponentSpec(StockfishLevel.level4));
    });
  });

  group('StockfishOpponentSpec', () {
    const spec = StockfishOpponentSpec(StockfishLevel.level8);

    test('basic properties and variant support', () {
      expect(spec.level, StockfishLevel.level8);
      expect(spec.engineSpec, isNotNull);
      expect(spec.displayName, 'Stockfish level 8');
      expect(spec.supportsVariant(Variant.standard), isTrue);
      expect(spec.supportsVariant(Variant.chess960), isTrue);
      expect(spec.supportsVariant(Variant.fromPosition), isTrue);
    });

    test('serialization and equality', () {
      expect(spec.toJson(), {'type': 'stockfish', 'level': 'level8'});
      expect(spec, const StockfishOpponentSpec(StockfishLevel.level8));
      expect(spec.hashCode, const StockfishOpponentSpec(StockfishLevel.level8).hashCode);
      expect(spec == const StockfishOpponentSpec(StockfishLevel.level1), isFalse);
      expect(spec.toString(), 'StockfishOpponentSpec(level8)');
    });
  });

  group('MaiaOpponentSpec', () {
    const spec = MaiaOpponentSpec(MaiaRating.maia1500);

    test('basic properties and variant support', () {
      expect(spec.rating, MaiaRating.maia1500);
      expect(spec.engineSpec, isNotNull);
      expect(spec.displayName, 'Maia 1500');
      expect(spec.supportsVariant(Variant.standard), isTrue);
      expect(spec.supportsVariant(Variant.fromPosition), isTrue);
      expect(spec.supportsVariant(Variant.chess960), isFalse);
      expect(spec.supportsVariant(Variant.atomic), isFalse);
    });

    test('serialization and equality', () {
      expect(spec.toJson(), {'type': 'maia', 'rating': 'maia1500'});
      expect(spec, const MaiaOpponentSpec(MaiaRating.maia1500));
      expect(spec.hashCode, const MaiaOpponentSpec(MaiaRating.maia1500).hashCode);
      expect(spec == const MaiaOpponentSpec(MaiaRating.maia1100), isFalse);
      expect(spec.toString(), 'MaiaOpponentSpec(maia1500)');
    });
  });
}
