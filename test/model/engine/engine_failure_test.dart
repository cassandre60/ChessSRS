import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/engine/engine_diagnostics.dart';
import 'package:chess_srs/src/model/engine/engine_failure.dart';
import 'package:flutter_test/flutter_test.dart';

EngineDiagnostics diagnostics({bool looksStuck = false, String? lastError}) {
  return EngineDiagnostics(
    phase: 'uciLoop',
    step: 'search',
    elapsed: const Duration(milliseconds: 250),
    looksStuck: looksStuck,
    lastError: lastError,
  );
}

EngineFailure failure({
  EngineFailureKind kind = EngineFailureKind.runtime,
  String message = 'boom',
  String engine = 'stockfish',
  Variant? variant,
  String? engineState,
  EngineDiagnostics? diagnostics,
  int? maxMemoryInMb,
  int? hashSizeInMb,
  Object? error,
  StackTrace? stackTrace,
}) {
  return EngineFailure(
    kind: kind,
    message: message,
    engine: engine,
    variant: variant,
    engineState: engineState,
    diagnostics: diagnostics,
    maxMemoryInMb: maxMemoryInMb,
    hashSizeInMb: hashSizeInMb,
    error: error,
    stackTrace: stackTrace,
  );
}

void main() {
  group('EngineFailure.isUnrecoverable', () {
    test('is true when kind is stuck', () {
      final f = failure(kind: EngineFailureKind.stuck);
      expect(f.isUnrecoverable, isTrue);
    });

    test('is true when diagnostics report the engine looks stuck', () {
      final f = failure(diagnostics: diagnostics(looksStuck: true));
      expect(f.isUnrecoverable, isTrue);
    });

    test('is false for a non-stuck runtime failure without stuck diagnostics', () {
      final f = failure(kind: EngineFailureKind.runtime, diagnostics: diagnostics());
      expect(f.isUnrecoverable, isFalse);
    });

    test('is false when there are no diagnostics and kind is recoverable', () {
      final f = failure(kind: EngineFailureKind.command);
      expect(f.isUnrecoverable, isFalse);
    });
  });

  group('EngineFailure.withContext', () {
    test('fills missing variant and memory context', () {
      final base = failure();
      final updated = base.withContext(
        variant: Variant.standard,
        maxMemoryInMb: 256,
        hashSizeInMb: 64,
      );

      expect(updated.variant, Variant.standard);
      expect(updated.maxMemoryInMb, 256);
      expect(updated.hashSizeInMb, 64);
      expect(updated.kind, base.kind);
      expect(updated.message, base.message);
      expect(updated.engine, base.engine);
    });

    test('preserves existing context over provided fallbacks', () {
      final base = failure(variant: Variant.chess960, maxMemoryInMb: 512, hashSizeInMb: 128);
      final updated = base.withContext(
        variant: Variant.standard,
        maxMemoryInMb: 256,
        hashSizeInMb: 64,
      );

      expect(updated.variant, Variant.chess960);
      expect(updated.maxMemoryInMb, 512);
      expect(updated.hashSizeInMb, 128);
    });
  });

  group('EngineFailure.toString', () {
    test('includes kind, message, engine, state, budget, hash and diagnostics', () {
      final f = failure(
        kind: EngineFailureKind.start,
        message: 'failed to start',
        engine: 'lc0',
        variant: Variant.standard,
        engineState: 'idle',
        diagnostics: diagnostics(lastError: 'weights missing'),
        maxMemoryInMb: 256,
        hashSizeInMb: 64,
        error: 'boom',
      );

      final text = f.toString();
      expect(text, contains('EngineFailure(start): failed to start'));
      expect(text, contains('engine=lc0'));
      expect(text, contains('variant=standard'));
      expect(text, contains('state=idle'));
      expect(text, contains('budget=256MB'));
      expect(text, contains('hash=64MB'));
      expect(text, contains('phase=uciLoop'));
      expect(text, contains('native error: weights missing'));
      expect(text, contains('Error: boom'));
    });

    test('uses unknown placeholders when optional fields are absent', () {
      final f = failure(kind: EngineFailureKind.command, message: 'nope');
      final text = f.toString();

      expect(text, contains('variant=unknown'));
      expect(text, contains('state=unknown'));
      expect(text, contains('budget=unknown'));
      expect(text, contains('hash=unknown'));
      expect(text, contains('No diagnostics.'));
      expect(text, isNot(contains('Error:')));
    });
  });

  test('reportEngineFailure completes without throwing', () async {
    await expectLater(reportEngineFailure(failure(error: Exception('x'))), completes);
  });
}
