/// Placeholder for credentials removed from diagnostic output.
const kRedactedLogValue = '***';

/// Query parameters whose value is a credential or a personal identifier.
///
/// This is a denylist rather than an allowlist on purpose. Its opposite —
/// allowlisting the parameters known to be safe — fails quietly and in the
/// direction nobody notices: a parameter added later is blanked, the log gets
/// less informative exactly when a new feature is being debugged, and no test
/// fails. A denylist keeps the log useful. What stops a new secret-bearing
/// parameter slipping past this list is review discipline, not automation:
/// there is no app-wide scan (an earlier classification-guard attempt produced
/// only false positives and was dropped). So when a credential is put in a
/// query string, its name must be added here in the same change — and the
/// sweep is part of every network review.
///
/// Add a name when a credential is put in a query string, not when an ordinary
/// parameter is.
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

/// Path prefixes whose following segment is a credential, with the reason.
///
/// Matched by prefix rather than by guessing "long opaque segment", which would
/// mangle ordinary paths and make the log useless for the case it exists to
/// serve.
const Map<String, String> kSecretBearingPathPrefixes = {
  '/mobile/register/firebase': 'the FCM registration token, a long-lived device credential',
};

/// Returns [uri] with anything that must not be logged replaced by
/// [kRedactedLogValue].
///
/// Applied on the way *into* storage and logging, never to the request that is
/// sent: the client has to deliver the real one-time code and the real token,
/// so redacting at the source would break sign-in. What is stored is what has
/// to be safe.
///
/// Only the secret parts are replaced. The path, the remaining parameters and
/// the host are left alone, because "which request was made, and what came
/// back" is the whole diagnostic value of the log.
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
