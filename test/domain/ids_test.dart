import 'package:chess_srs/src/domain/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('newId', () {
    test('returns a UUID v4 string', () {
      final id = newId();

      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
      );
    });

    test('returns different values on successive calls', () {
      final first = newId();
      final second = newId();

      expect(first, isNot(equals(second)));
    });
  });
}
