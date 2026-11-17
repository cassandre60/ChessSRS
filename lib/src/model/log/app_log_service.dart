import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:chess_srs/src/utils/log_redaction.dart';
import 'package:chess_srs/src/utils/lru_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

const _loggersToShowInTerminal = {
  'HttpClient',
  'Socket',
  'PositionEvaluator',
  'Stockfish',
  'Lc0',
  'ReviewEngine',
  'ReviewController',
  'StudyRepository',
  'StudyImporter',
  'Database',
  'FsrsScheduler',
};

/// Provides an instance of [AppLogService] using Riverpod.
final appLogServiceProvider = Provider<AppLogService>(
  (Ref ref) => AppLogService(ref),
  name: 'AppLogServiceProvider',
);

/// Manages log entries created via [Logger] instances.
///
/// Log entries are stored in memory for the current session and persisted to the
/// SQLite database so they survive app restarts.
class AppLogService {
  AppLogService(this.ref);

  final Ref ref;
  final _logs = LRUList<LogRecord>(capacity: 1024);

  /// Currently stored log entries, ordered from oldest to newest.
  Iterable<LogRecord> get logs => _logs.values;

  void start() {
    if (kDebugMode) {
      Logger.root.level = Level.ALL;
    } else {
      ref.listen(logPreferencesProvider.select((prefs) => prefs.level), (prev, next) {
        if (next != prev) {
          Logger.root.level = next;
        }
      }, fireImmediately: true);
    }

    Logger.root.onRecord.listen((record) {
      final redacted = redactLogRecord(record);
      if (kDebugMode) {
        developer.log(
          redacted.message,
          time: redacted.time,
          name: redacted.loggerName,
          level: redacted.level.value,
          error: redacted.error,
          stackTrace: redacted.stackTrace,
        );

        if (_loggersToShowInTerminal.contains(redacted.loggerName) &&
            redacted.level >= Level.FINE &&
            !Platform.environment.containsKey('FLUTTER_TEST')) {
          debugPrint(
            '[${redacted.loggerName}] ${redacted.message}${redacted.error != null ? ' (${redacted.error})' : ''}',
          );
        }
      }

      _logs.put(redacted);

      // Persist to database asynchronously (fire-and-forget).
      // In tests, avoid asynchronous database writes for log records to prevent lock contention.
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        scheduleMicrotask(() {
          try {
            ref
                .read(appLogStorageProvider.future)
                .then(
                  (storage) => storage.save(AppLogEntry.fromLogRecord(redacted)),
                  onError: (_) {},
                );
          } catch (_) {}
        });
      }
    });
  }

  void clear() {
    _logs.clear();
  }
}

/// Returns [record] with credentials redacted from [LogRecord.message], [LogRecord.error], and
/// [LogRecord.stackTrace] (SPEC INV-006).
///
/// Preserves the original [LogRecord] instance when no sensitive content is present.
LogRecord redactLogRecord(LogRecord record) {
  final redactedMessage = redactLogText(record.message);

  Object? redactedError = record.error;
  if (record.error != null) {
    final errorText = record.error.toString();
    final cleanedError = redactLogText(errorText);
    if (cleanedError != errorText) {
      redactedError = cleanedError;
    }
  }

  StackTrace? redactedStackTrace = record.stackTrace;
  if (record.stackTrace != null) {
    final stackText = record.stackTrace.toString();
    final cleanedStack = redactLogText(stackText);
    if (cleanedStack != stackText) {
      redactedStackTrace = StackTrace.fromString(cleanedStack);
    }
  }

  Object? redactedObject = record.object;
  if (record.object != null) {
    final objectText = record.object.toString();
    final cleanedObject = redactLogText(objectText);
    if (cleanedObject != objectText) {
      redactedObject = cleanedObject;
    }
  }

  if (redactedMessage == record.message &&
      identical(redactedError, record.error) &&
      identical(redactedStackTrace, record.stackTrace) &&
      identical(redactedObject, record.object)) {
    return record;
  }

  return LogRecord(
    record.level,
    redactedMessage,
    record.loggerName,
    redactedError,
    redactedStackTrace,
    record.zone,
    redactedObject,
  );
}

final class ProviderLogger extends ProviderObserver {
  final _logger = Logger('Provider');

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _logger.finer('${context.provider.name ?? context.provider.runtimeType} initialized: $value');
  }

  /// Riverpod calls this whenever a provider's `onDispose` listeners run, which a rebuild does as
  /// much as a disposal: `_performRebuild` and `invalidateSelf` both go through `runOnDispose`, so
  /// a provider that merely recomputed logs this twice without going anywhere.
  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _logger.finer('${context.provider.name ?? context.provider.runtimeType} disposed or rebuilt');
  }

  @override
  void providerDidFail(ProviderObserverContext context, Object error, StackTrace stackTrace) {
    _logger.severe(
      '${context.provider.name ?? context.provider.runtimeType} error',
      error,
      stackTrace,
    );
  }
}
