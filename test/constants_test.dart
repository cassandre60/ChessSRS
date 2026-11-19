import 'package:chess_srs/src/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appStoreListingUrl', () {
    test('returns Play Store listing on Android', () {
      final url = appStoreListingUrl(isAndroid: true);
      expect(url.toString(), 'https://play.google.com/store/apps/details?id=org.chesssrs.app');
    });

    test('returns App Store search when no listing id on iOS', () {
      final url = appStoreListingUrl(isAndroid: false);
      expect(url.toString(), 'https://apps.apple.com/us/search?term=ChessSRS');
    });
  });

  group('androidAppStoreLinks', () {
    test('native link uses market scheme', () {
      final links = androidAppStoreLinks();
      expect(links.native.toString(), 'market://details?id=org.chesssrs.app');
    });

    test('web link matches Android listing url', () {
      final links = androidAppStoreLinks();
      expect(links.web, appStoreListingUrl(isAndroid: true));
    });
  });

  group('constants', () {
    test('kProvisionalDeviation is 110', () {
      expect(kProvisionalDeviation, 110);
    });

    test('kAppStorePackageName equals custom uri scheme', () {
      expect(kAppStorePackageName, kLichessCustomUriSchemeName);
    });

    test('boardShadows is non-empty on non-iOS platforms', () {
      expect(boardShadows, isNotEmpty);
    });
  });
}
