import 'package:chess_srs/src/design/hatch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HatchPainter', () {
    test('shouldRepaint is false for identical parameters', () {
      const painter = HatchPainter(color: Color(0x11000000), gap: 6, width: 2);
      const same = HatchPainter(color: Color(0x11000000), gap: 6, width: 2);

      expect(painter.shouldRepaint(same), isFalse);
    });

    test('shouldRepaint is true when color changes', () {
      const painter = HatchPainter(color: Color(0x11000000), gap: 6, width: 2);
      const other = HatchPainter(color: Color(0x22000000), gap: 6, width: 2);

      expect(painter.shouldRepaint(other), isTrue);
    });

    test('shouldRepaint is true when gap changes', () {
      const painter = HatchPainter(color: Color(0x11000000), gap: 6, width: 2);
      const other = HatchPainter(color: Color(0x11000000), gap: 8, width: 2);

      expect(painter.shouldRepaint(other), isTrue);
    });

    test('shouldRepaint is true when width changes', () {
      const painter = HatchPainter(color: Color(0x11000000), gap: 6, width: 2);
      const other = HatchPainter(color: Color(0x11000000), gap: 6, width: 3);

      expect(painter.shouldRepaint(other), isTrue);
    });
  });
}
