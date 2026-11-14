import 'package:chess_srs/src/utils/request_generation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestGeneration', () {
    test('claim returns incrementing generations starting at 1', () {
      final generation = RequestGeneration();

      expect(generation.claim(), 1);
      expect(generation.claim(), 2);
      expect(generation.claim(), 3);
    });

    test('isCurrent is true only for the newest claimed generation', () {
      final generation = RequestGeneration();

      final first = generation.claim();
      expect(generation.isCurrent(first), isTrue);

      final second = generation.claim();
      expect(generation.isCurrent(first), isFalse);
      expect(generation.isCurrent(second), isTrue);

      final third = generation.claim();
      expect(generation.isCurrent(first), isFalse);
      expect(generation.isCurrent(second), isFalse);
      expect(generation.isCurrent(third), isTrue);
    });

    test('a newer claim fences all older generations', () {
      final generation = RequestGeneration();

      final stale = generation.claim();
      generation.claim();

      expect(generation.isCurrent(stale), isFalse);
    });
  });
}
