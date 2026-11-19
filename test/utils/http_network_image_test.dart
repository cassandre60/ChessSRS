import 'package:chess_srs/src/utils/http_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('HttpNetworkImage', () {
    test('obtainKey returns the same instance synchronously', () async {
      final client = http.Client();
      addTearDown(client.close);

      final image = HttpNetworkImage('https://example.com/piece.png', client);
      final key = await image.obtainKey(ImageConfiguration.empty);

      expect(key, same(image));
    });

    test('== and hashCode are based on url and scale', () {
      final client = http.Client();
      addTearDown(client.close);

      final a = HttpNetworkImage('https://example.com/a.png', client);
      final b = HttpNetworkImage('https://example.com/a.png', client);
      final c = HttpNetworkImage('https://example.com/b.png', client);
      final d = HttpNetworkImage('https://example.com/a.png', client, scale: 2.0);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('is not equal to objects of a different runtime type', () {
      final client = http.Client();
      addTearDown(client.close);

      final image = HttpNetworkImage('https://example.com/a.png', client);

      expect(image == Object(), isFalse);
    });

    test('toString includes url and scale', () {
      final client = http.Client();
      addTearDown(client.close);

      final image = HttpNetworkImage('https://example.com/a.png', client, scale: 2.0);

      expect(image.toString(), contains('https://example.com/a.png'));
      expect(image.toString(), contains('scale: 2.0'));
    });

    test('different clients with same url and scale compare equal', () {
      final client1 = http.Client();
      final client2 = http.Client();
      addTearDown(client1.close);
      addTearDown(client2.close);

      final a = HttpNetworkImage('https://example.com/a.png', client1);
      final b = HttpNetworkImage('https://example.com/a.png', client2);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('obtainKey completes as a SynchronousFuture', () {
      final client = http.Client();
      addTearDown(client.close);

      final image = HttpNetworkImage('https://example.com/a.png', client);
      final future = image.obtainKey(ImageConfiguration.empty);

      expect(future, isA<SynchronousFuture<HttpNetworkImage>>());
    });
  });
}
