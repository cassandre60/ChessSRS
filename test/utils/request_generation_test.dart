import 'package:chess_srs/src/utils/request_generation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestGeneration', () {
    test('claim stamps generations starting at one', () {
      final generation = RequestGeneration();
      expect(generation.claim(), 1);
      expect(generation.claim(), 2);
      expect(generation.claim(), 3);
    });

    test('isCurrent is true for the latest claim', () {
      final generation = RequestGeneration();
      final first = generation.claim();
      expect(generation.isCurrent(first), isTrue);
    });

    test('a newer claim makes older generations stale', () {
      final generation = RequestGeneration();
      final first = generation.claim();
      final second = generation.claim();
      expect(generation.isCurrent(first), isFalse);
      expect(generation.isCurrent(second), isTrue);
    });

    test('a bare supersede moves the counter without a value of its own', () {
      final generation = RequestGeneration();
      final first = generation.claim();
      // Simulate a supersede by claiming again; the older claim must drop out.
      generation.claim();
      expect(generation.isCurrent(first), isFalse);
    });

    test('distinct RequestGeneration instances do not share state', () {
      final a = RequestGeneration();
      final b = RequestGeneration();
      final ga = a.claim();
      b.claim();
      expect(a.isCurrent(ga), isTrue);
    });
  });
}
