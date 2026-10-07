import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
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
      if (kDebugMode) {
        developer.log(
          record.message,
          time: record.time,
          name: record.loggerName,
          level: record.level.value,
          error: record.error,
          stackTrace: record.stackTrace,
        );

        if (_loggersToShowInTerminal.contains(record.loggerName) &&
            record.level >= Level.FINE &&
            !Platform.environment.containsKey('FLUTTER_TEST')) {
          debugPrint(
            '[${record.loggerName}] ${record.message}${record.error != null ? ' (${record.error})' : ''}',
          );
        }
      } else {
        // Redact credentials before persisting
      }

      _logs.put(record);

      // Persist to database asynchronously (fire-and-forget).
      // In tests, avoid asynchronous database writes for log records to prevent lock contention.
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        scheduleMicrotask(() {
          try {
            ref
                .read(appLogStorageProvider.future)
                .then(
                  (storage) => storage.save(AppLogEntry.fromLogRecord(record)),
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
