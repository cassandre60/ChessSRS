import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';

final _random = Random.secure();

String genRandomString(int len) {
  final values = List<int>.generate(len, (i) => _random.nextInt(256));
  // base64url without padding: '=' is legal in URLs but not in the alphabet,
  // and these strings travel in SRI-style tokens where padding carries nothing.
  return base64UrlEncode(values).replaceAll('=', '');
}

extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

extension NumberLocalizationExtension on String {
  String localizeNumbers() {
    return replaceAllMapped(
      RegExp(r'\d+(\.\d+)?'),
      (m) => NumberFormat().format(double.parse(m.group(0)!)),
    );
  }
}
