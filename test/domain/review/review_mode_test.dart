import 'package:chess_srs/src/domain/review/review_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewMode', () {
    test('has stable values and order', () {
      expect(ReviewMode.values, const [ReviewMode.srs, ReviewMode.practice]);
    });

    test('has stable names', () {
      expect(ReviewMode.srs.name, 'srs');
      expect(ReviewMode.practice.name, 'practice');
    });
  });
}
