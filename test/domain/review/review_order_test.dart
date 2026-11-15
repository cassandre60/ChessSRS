import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReviewOrder has stable values and order', () {
    expect(ReviewOrder.values, const <ReviewOrder>[
      ReviewOrder.dueDate,
      ReviewOrder.byLine,
      ReviewOrder.random,
    ]);
  });

  test('ReviewOrder names are stable', () {
    expect(ReviewOrder.dueDate.name, 'dueDate');
    expect(ReviewOrder.byLine.name, 'byLine');
    expect(ReviewOrder.random.name, 'random');
  });
}
