import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/utils/lichess_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lichessAssetUrl', () {
    test('builds a CDN URL with a six-character asset hash', () {
      final url = lichessAssetUrl('piece/wK.svg');
      final pattern = RegExp(
        '^${RegExp.escape(kLichessCDNHost)}/assets/_[A-Za-z0-9]{6}/piece/wK\\.svg\$',
      );
      expect(url, matches(pattern));
    });

    test('uses the same asset hash across calls', () {
      final first = lichessAssetUrl('a.png');
      final second = lichessAssetUrl('b.png');
      final hashRegex = RegExp('/assets/(_[A-Za-z0-9]{6})/');
      final h1 = hashRegex.firstMatch(first)!.group(1);
      final h2 = hashRegex.firstMatch(second)!.group(1);
      expect(h1, equals(h2));
    });
  });

  group('lichessFlagSrc', () {
    test('builds a flag URL from the country code', () {
      expect(lichessFlagSrc('FR'), equals('$kLichessCDNHost/assets/flags/FR.webp'));
    });
  });

  group('lichessFlairSrc', () {
    test('builds a flair URL from the flair name', () {
      expect(lichessFlairSrc('fire'), equals('$kLichessCDNHost/assets/flair/img/fire.webp'));
    });
  });
}
