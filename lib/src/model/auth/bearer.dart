import 'dart:convert';

import 'package:chess_srs/src/constants.dart';
import 'package:crypto/crypto.dart';

final hmacSha1 = Hmac(sha1, utf8.encode(kLichessWSSecret));

/// Sign a bearer token with the lichess secret.
String signBearerToken(String token) {
  if (kLichessWSSecret == 'somethingElseInProd') {
    return token;
  }
  final digest = hmacSha1.convert(utf8.encode(token));
  return '$token:$digest';
}
