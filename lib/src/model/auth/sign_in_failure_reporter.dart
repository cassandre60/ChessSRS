import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _logger = Logger('Auth');

/// Records a sign-in failure.
///
/// This never throws: telemetry must not interfere with the sign-in flow.
Future<void> reportSignInFailure(Ref ref, Object error, StackTrace stack) async {
  _logger.warning('Sign-in failed', error, stack);
}
