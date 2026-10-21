/// Placeholder for credentials removed from diagnostic output.
const kRedactedLogValue = '***';

/// Query parameters carrying credentials or authentication identifiers.
const Set<String> kSensitiveQueryParameters = {
  'code',
  'email',
  'otp',
  'password',
  'secret',
  'sessionid',
  'token',
  'username',
};

/// Routes whose following path segment contains a credential.
const Map<String, String> kSecretBearingPathPrefixes = {
  '/mobile/register/firebase': 'the FCM registration token, a long-lived device credential',
};

/// Redacts credentials without changing the request that is actually sent.
Uri redactUriForLogging(Uri uri) {
  var segments = uri.pathSegments;

  for (final entry in kSecretBearingPathPrefixes.entries) {
    final prefixSegments = entry.key.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length > prefixSegments.length && _startsWith(segments, prefixSegments)) {
      segments = [
        ...segments.take(prefixSegments.length),
        kRedactedLogValue,
        ...segments.skip(prefixSegments.length + 1),
      ];
      break;
    }
  }

  var changed = !_sameSegments(segments, uri.pathSegments);
  final parameters = {...uri.queryParametersAll};
  parameters.forEach((name, value) {
    if (kSensitiveQueryParameters.contains(name.toLowerCase()) &&
        value.any((item) => item != kRedactedLogValue)) {
      parameters[name] = List.filled(value.length, kRedactedLogValue);
      changed = true;
    }
  });

  if (!changed) return uri;
  return uri.replace(
    pathSegments: segments,
    queryParameters: parameters.isEmpty ? null : parameters,
  );
}

bool _startsWith(List<String> segments, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (segments[i] != prefix[i]) return false;
  }
  return true;
}

bool _sameSegments(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _logUriPattern = RegExp(
  r'''(["'\[({]?)(?:https?://|/)(?:(?!["'\[({]?https?://)[^\s<>])+''',
  caseSensitive: false,
);
final _afterUriWrapper = RegExp(r'^[,;:.!?]*$');

/// Redacts URLs embedded in messages, exception strings, and stack traces.
///
/// The original text survives when no credentials are present. Brackets wrapping a URL remain
/// diagnostic punctuation, not part of its final query value. A candidate that fails URI parsing
/// is withheld rather than allowed to bypass redaction. This does not classify arbitrary prose.
String redactLogText(String text) => text.replaceAllMapped(_logUriPattern, (match) {
  final original = match.group(0)!;
  final opening = match.group(1)!;
  var uriText = original.substring(opening.length);
  final closing = switch (opening) {
    '(' => ')',
    '[' => ']',
    '{' => '}',
    '"' => '"',
    "'" => "'",
    _ => '',
  };
  var suffix = '';
  if (closing.isNotEmpty) {
    final end = uriText.lastIndexOf(closing);
    if (end >= 0 && _afterUriWrapper.hasMatch(uriText.substring(end + 1))) {
      suffix = uriText.substring(end);
      uriText = uriText.substring(0, end);
    }
  }

  try {
    final uri = Uri.parse(uriText);
    final redacted = redactUriForLogging(uri);
    if (redacted == uri) return original;
    return '$opening$redacted$suffix';
  } on FormatException {
    return '$opening$kRedactedLogValue$suffix';
  }
});
