import 'package:chess_srs/src/styles/lichess_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LichessIcons', () {
    test('uses the LichessIcons font family', () {
      expect(LichessIcons.patron.fontFamily, 'LichessIcons');
      expect(LichessIcons.logo_lichess.fontFamily, 'LichessIcons');
      expect(LichessIcons.chess_queen.fontFamily, 'LichessIcons');
      expect(LichessIcons.patron.fontPackage, isNull);
    });

    test('exposes stable icon code points', () {
      expect(LichessIcons.patron.codePoint, 0xe800);
      expect(LichessIcons.storm.codePoint, 0xe80c);
      expect(LichessIcons.logo_lichess.codePoint, 0xe81b);
      expect(LichessIcons.tag.codePoint, 0xf02b);
      expect(LichessIcons.tools.codePoint, 0xf7d9);
    });

    test('icons are IconData constants', () {
      expect(LichessIcons.blitz, isA<IconData>());
      expect(LichessIcons.bullet, isA<IconData>());
      expect(LichessIcons.chess_knight, isA<IconData>());
      expect(LichessIcons.step_forward, isA<IconData>());
    });
  });
}
