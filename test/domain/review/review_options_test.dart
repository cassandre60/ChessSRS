import 'package:chess_srs/src/domain/review/review_continuity.dart';
import 'package:chess_srs/src/domain/review/review_mode.dart';
import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewMode', () {
    test('exposes expected values in declaration order', () {
      expect(ReviewMode.values, const [ReviewMode.srs, ReviewMode.practice]);
      expect(ReviewMode.srs.name, 'srs');
      expect(ReviewMode.practice.name, 'practice');
    });
  });

  group('ReviewContinuity', () {
    test('exposes expected values in declaration order', () {
      expect(ReviewContinuity.values, const [ReviewContinuity.dueOnly, ReviewContinuity.fullLine]);
      expect(ReviewContinuity.dueOnly.name, 'dueOnly');
      expect(ReviewContinuity.fullLine.name, 'fullLine');
    });
  });

  group('ReviewOrder', () {
    test('exposes expected values in declaration order', () {
      expect(ReviewOrder.values, const [
        ReviewOrder.dueDate,
        ReviewOrder.byLine,
        ReviewOrder.random,
      ]);
      expect(ReviewOrder.dueDate.name, 'dueDate');
      expect(ReviewOrder.byLine.name, 'byLine');
      expect(ReviewOrder.random.name, 'random');
    });
  });

  group('TransposeScope', () {
    test('exposes expected values in declaration order', () {
      expect(TransposeScope.values, const [
        TransposeScope.off,
        TransposeScope.withinStudy,
        TransposeScope.inScope,
      ]);
      expect(TransposeScope.off.name, 'off');
      expect(TransposeScope.withinStudy.name, 'withinStudy');
      expect(TransposeScope.inScope.name, 'inScope');
    });
  });
}
