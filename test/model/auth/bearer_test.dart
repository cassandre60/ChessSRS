import 'package:chess_srs/src/model/auth/bearer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signBearerToken', () {
    test('returns token unchanged when WS secret is the placeholder', () {
      const token = 'lip_test_token';
      expect(signBearerToken(token), token);
    });

    test('preserves arbitrary token strings in placeholder mode', () {
      const tokens = ['', 'abc', 'token:with:colons', 'тест'];
      for (final token in tokens) {
        expect(signBearerToken(token), token);
      }
    });
  });
}
