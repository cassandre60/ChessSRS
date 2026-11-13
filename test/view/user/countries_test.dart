import 'package:chess_srs/src/view/user/countries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('countries', () {
    test('contains expected country and region entries', () {
      expect(countries['FR'], 'France');
      expect(countries['US'], 'United States');
      expect(countries['GB-ENG'], 'England');
      expect(countries['ES-CT'], 'Catalonia');
      expect(countries['RU-TAT'], 'Tatarstan');
      expect(countries['_adygea'], 'Adygea');
    });

    test('uses non-empty codes and names', () {
      expect(countries, isNotEmpty);
      for (final entry in countries.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.key, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
        expect(entry.value.trim(), isNotEmpty);
      }
    });
  });
}
