import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_log_paginator.freezed.dart';

/// The number of app logs to fetch per page.
const _pageSize = 20;

/// The query the app log is read with.
///
/// [search] is the free-text filter the reader typed; [loggerPrefixes] are the logger-name
/// prefixes of the selected category. The screen offers one or the other, never both: what
/// the reader typed wins over the chip.
@freezed
sealed class AppLogQuery with _$AppLogQuery {
  const factory AppLogQuery({String? search, @Default(<String>[]) List<String> loggerPrefixes}) =
      _AppLogQuery;
}

/// A provider for [AppLogPaginator].
///
/// The family argument is the query the log is read with.
final appLogPaginatorProvider = AsyncNotifierProvider.autoDispose
    .family<AppLogPaginator, AppLogState, AppLogQuery>(
      AppLogPaginator.new,
      name: 'AppLogPaginatorProvider',
    );

/// A Riverpod controller for managing paginated app log entries.
class AppLogPaginator extends AsyncNotifier<AppLogState> {
  AppLogPaginator(this._query);

  final AppLogQuery _query;

  /// Set while a page is being fetched. See [next].
  bool _isFetchingPage = false;

  @override
  Future<AppLogState> build() async {
    final storage = await ref.read(appLogStorageProvider.future);
    final minLevelValue = ref.watch(logPreferencesProvider.select((p) => p.level.value));
    return AppLogState(
      data: IList.new([
        await AsyncValue.guard(
          () => storage.page(
            limit: _pageSize,
            minLevelValue: minLevelValue,
            searchQuery: _query.search,
            loggerNamePrefixes: _query.loggerPrefixes,
          ),
        ),
      ]),
    );
  }

  /// Fetches the next page of app logs.
  ///
  /// Ignored while a page is already in flight; the next scroll once that one lands will fetch
  /// it. Without the guard two scroll notifications both read the same cursor, fetched the same
  /// page and appended it, so its rows appeared twice and the page after it was skipped.
  Future<void> next() async {
    if (_isFetchingPage) return;
    if (!state.hasValue || !state.requireValue.hasMore) return;

    _isFetchingPage = true;
    try {
      final storage = await ref.read(appLogStorageProvider.future);
      final minLevelValue = ref.read(logPreferencesProvider.select((p) => p.level.value));
      final asyncPage = await AsyncValue.guard(
        () => storage.page(
          limit: _pageSize,
          cursor: state.requireValue.nextPage,
          minLevelValue: minLevelValue,
          searchQuery: _query.search,
          loggerNamePrefixes: _query.loggerPrefixes,
        ),
      );
      // The paginator can be disposed while the read is out — a refresh, or the log level
      // changing. Writing state afterwards throws.
      if (!ref.mounted) return;
      state = AsyncValue.data(
        state.requireValue.copyWith(data: state.requireValue.data.add(asyncPage)),
      );
    } finally {
      _isFetchingPage = false;
    }
  }

  /// Deletes all app logs from the database and refreshes.
  Future<void> deleteAll() async {
    final storage = await ref.read(appLogStorageProvider.future);
    await storage.deleteAll();
    ref.invalidateSelf();
  }

  /// Refreshes by fetching the first page again.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

@freezed
sealed class AppLogState with _$AppLogState {
  const AppLogState._();

  const factory AppLogState({required IList<AsyncValue<AppLogPage>> data}) = _AppLogState;

  bool get initialized => data.isNotEmpty;
  List<AppLogEntry> get logs =>
      data.expand<AppLogEntry>((e) => e.value?.items ?? <AppLogEntry>[]).toList();
  int? get nextPage => data.lastOrNull?.value?.next;
  bool get hasMore => initialized && nextPage != null;
  bool get isLoading => data.lastOrNull?.isLoading == true;
  bool get isDeleteButtonVisible => logs.isNotEmpty;
}
