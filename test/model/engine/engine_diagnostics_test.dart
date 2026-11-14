import 'package:chess_srs/src/model/engine/engine_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineDiagnostics', () {
    test('stores constructor fields', () {
      const diagnostics = EngineDiagnostics(
        phase: 'engineBooting',
        step: 'nnue',
        elapsed: Duration(milliseconds: 1234),
        looksStuck: false,
        lastError: 'some error',
      );

      expect(diagnostics.phase, 'engineBooting');
      expect(diagnostics.step, 'nnue');
      expect(diagnostics.elapsed, const Duration(milliseconds: 1234));
      expect(diagnostics.looksStuck, isFalse);
      expect(diagnostics.lastError, 'some error');
    });

    test('toString includes phase, step, and elapsed', () {
      const diagnostics = EngineDiagnostics(
        phase: 'uciLoop',
        step: 'engine_teardown',
        elapsed: Duration(milliseconds: 250),
        looksStuck: false,
      );

      expect(diagnostics.toString(), 'phase=uciLoop step=engine_teardown for 250ms');
    });

    test('toString omits step when empty', () {
      const diagnostics = EngineDiagnostics(
        phase: 'searching',
        step: '',
        elapsed: Duration(milliseconds: 10),
        looksStuck: false,
      );

      expect(diagnostics.toString(), 'phase=searching for 10ms');
    });

    test('toString appends STUCK marker when looksStuck is true', () {
      const diagnostics = EngineDiagnostics(
        phase: 'engineBooting',
        step: 'weights',
        elapsed: Duration(seconds: 30),
        looksStuck: true,
      );

      expect(diagnostics.toString(), 'phase=engineBooting step=weights for 30000ms (STUCK)');
    });

    test('toString appends native error when present', () {
      const diagnostics = EngineDiagnostics(
        phase: 'engineBooting',
        step: 'nnue',
        elapsed: Duration(milliseconds: 5),
        looksStuck: false,
        lastError: 'failed to open network',
      );

      expect(
        diagnostics.toString(),
        'phase=engineBooting step=nnue for 5ms; native error: failed to open network',
      );
    });

    test('toString appends STUCK marker and native error together', () {
      const diagnostics = EngineDiagnostics(
        phase: 'uciLoop',
        step: '',
        elapsed: Duration(milliseconds: 9001),
        looksStuck: true,
        lastError: 'engine did not respond',
      );

      expect(
        diagnostics.toString(),
        'phase=uciLoop for 9001ms (STUCK); native error: engine did not respond',
      );
    });
  });
}
