import 'package:chess_srs/src/utils/lru_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LRUList', () {
    test('keeps values in insertion order, oldest first', () {
      final list = LRUList<String>(capacity: 3);

      list.put('a');
      list.put('b');
      list.put('c');

      expect(list.values.toList(), ['a', 'b', 'c']);
    });

    test('evicts the oldest entry once capacity is exceeded', () {
      final list = LRUList<String>(capacity: 3);

      for (final value in ['a', 'b', 'c', 'd', 'e']) {
        list.put(value);
      }

      expect(list.values.toList(), ['c', 'd', 'e']);
    });

    test('capacity 1 keeps only the newest value', () {
      final list = LRUList<int>(capacity: 1);

      list.put(1);
      list.put(2);
      list.put(3);

      expect(list.values.toList(), [3]);
    });

    test('starts empty', () {
      expect(LRUList<int>(capacity: 4).values, isEmpty);
    });

    test('clear empties the list and capacity applies again afterwards', () {
      final list = LRUList<int>(capacity: 2);
      list.put(1);
      list.put(2);

      list.clear();

      expect(list.values, isEmpty);

      list.put(9);
      expect(list.values.toList(), [9]);
    });

    test('putting the same value twice stores it twice', () {
      // Characterisation, not endorsement. put does not look for an existing
      // entry, so a repeated value occupies two slots. app_log_service feeds it
      // one LogRecord per record, where duplicates are meaningful.
      final list = LRUList<String>(capacity: 4);

      list.put('a');
      list.put('a');

      expect(list.values.toList(), ['a', 'a']);
    });

    test('re-putting an old value does not move it to the end', () {
      // The class is named LRU but exposes no read path, so recency is never
      // updated: this is insertion-ordered eviction, not least-recently-used.
      final list = LRUList<String>(capacity: 2);

      list.put('a');
      list.put('b');
      list.put('a');

      expect(list.values.toList(), ['b', 'a']);
    });

    test('capacity 0 rejects every put', () {
      // Suspected bug: capacity is never validated, so the eviction branch runs
      // against an empty list and LinkedList's null check throws instead of the
      // put being a no-op. Asserted as Error because the concrete type depends on
      // the SDK; the point is that it is a programming error, not a graceful one.
      final list = LRUList<int>(capacity: 0);

      expect(() => list.put(1), throwsA(isA<Error>()));
      expect(list.values, isEmpty);
    });

    test('negative capacity also throws rather than being rejected', () {
      final list = LRUList<int>(capacity: -1);

      expect(() => list.put(1), throwsA(isA<Error>()));
    });

    test('holds a large capacity without evicting early', () {
      // app_log_service uses capacity 1024; check the boundary just below it.
      final list = LRUList<int>(capacity: 1024);

      for (var i = 0; i < 1024; i++) {
        list.put(i);
      }

      expect(list.values.length, 1024);
      expect(list.values.first, 0);

      list.put(1024);

      expect(list.values.length, 1024);
      expect(list.values.first, 1);
      expect(list.values.last, 1024);
    });
  });
}
