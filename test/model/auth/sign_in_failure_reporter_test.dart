import 'package:chess_srs/src/model/auth/sign_in_failure_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import '../../binding.dart';
import '../../test_container.dart';

void main() {
  TestLichessBinding.ensureInitialized();

  test('reportSignInFailure logs a warning and never throws', () async {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    Logger.root.level = Level.ALL;

    final container = await makeContainer();
    // Obtain a Ref via a provider.
    final refProvider = Provider<Ref>((r) => r);
    final actualRef = container.read(refProvider);

    await reportSignInFailure(actualRef, StateError('boom'), StackTrace.current);

    await subscription.cancel();

    expect(
      records.any((r) => r.loggerName == 'Auth' && r.level == Level.WARNING && r.message == 'Sign-in failed'),
      isTrue,
      reason: 'a sign-in failure must be recorded as a warning',
    );
  });
}
