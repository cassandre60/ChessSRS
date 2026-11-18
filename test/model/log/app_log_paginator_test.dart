// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/log/app_log_paginator.dart';
import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppLogStorage extends Mock implements AppLogStorage {}

/// Supplies the default log level without touching platform preferences.
class _FixedLogPreferencesNotifier extends LogPreferencesNotifier {
  @override
  LogPrefs build() => LogPrefs.defaults;
}

AppLogEntry _entry(String message) => AppLogEntry(
  logTime: DateTime.utc(2026, 11, 18),
  loggerName: 'TestLogger',
  levelValue: 800,
  levelName: 'INFO',
  message: message,
);

AppLogPage _page(List<String> messages, {int? next}) =>
    AppLogPage(items: messages.map(_entry).toList().toIList(), next: next);

ProviderContainer _container(AppLogStorage storage, AppLogQuery query) {
  final container = ProviderContainer(
    overrides: [
      appLogStorageProvider.overrideWith((ref) => Future.value(storage)),
      logPreferencesProvider.overrideWith(_FixedLogPreferencesNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  // autoDispose: keep the paginator alive across the async paging calls below.
  final subscription = container.listen(appLogPaginatorProvider(query), (_, _) {});
  addTearDown(subscription.close);
  return container;
}

Map<Symbol, dynamic> _pageArgs(Invocation invocation) => invocation.namedArguments;

void main() {
  group('AppLogState derived getters', () {
    test('an empty data list is uninitialized and hides the delete button', () {
      final state = AppLogState(data: IList<AsyncValue<AppLogPage>>(const []));

      expect(state.initialized, isFalse);
      expect(state.logs, isEmpty);
      expect(state.nextPage, isNull);
      expect(state.hasMore, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.isDeleteButtonVisible, isFalse);
    });

    test('logs flatten data pages and skip loading and error pages', () {
      final state = AppLogState(
        data: IList([
          AsyncData<AppLogPage>(_page(['a'])),
          const AsyncLoading<AppLogPage>(),
          AsyncValue<AppLogPage>.error(Exception('boom'), StackTrace.empty),
          AsyncData<AppLogPage>(_page(['b'])),
        ]),
      );

      expect(state.logs.map((e) => e.message), equals(['a', 'b']));
      expect(state.isDeleteButtonVisible, isTrue);
    });

    test('nextPage and hasMore follow the last page, not the first', () {
      final withMore = AppLogState(
        data: IList([
          AsyncData<AppLogPage>(_page(['a'], next: 7)),
          AsyncData<AppLogPage>(_page(['b'], next: 3)),
        ]),
      );
      expect(withMore.nextPage, 3);
      expect(withMore.hasMore, isTrue);

      final exhausted = AppLogState(
        data: IList([
          AsyncData<AppLogPage>(_page(['a'], next: 7)),
          AsyncData<AppLogPage>(_page(['b'])),
        ]),
      );
      expect(exhausted.nextPage, isNull);
      expect(exhausted.hasMore, isFalse, reason: 'an initialized last page with no cursor is done');
    });

    test('isLoading follows the last page only', () {
      final loadingTail = AppLogState(
        data: IList([
          AsyncData<AppLogPage>(_page(['a'])),
          const AsyncLoading<AppLogPage>(),
        ]),
      );
      expect(loadingTail.isLoading, isTrue);

      final dataTail = AppLogState(
        data: IList([
          const AsyncLoading<AppLogPage>(),
          AsyncData<AppLogPage>(_page(['a'])),
        ]),
      );
      expect(dataTail.isLoading, isFalse);
    });
  });

  group('AppLogPaginator paging', () {
    test('overlapping next() calls fetch the same page once', () async {
      final storage = MockAppLogStorage();
      var calls = 0;
      when(
        () => storage.page(
          cursor: any(named: 'cursor'),
          minLevelValue: any(named: 'minLevelValue'),
          searchQuery: any(named: 'searchQuery'),
          loggerNamePrefixes: any(named: 'loggerNamePrefixes'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((invocation) async {
        calls++;
        final cursor = _pageArgs(invocation)[#cursor] as int?;
        return cursor == null ? _page(['3', '2', '1'], next: 1) : _page(['0']);
      });

      const query = AppLogQuery();
      final container = _container(storage, query);
      await container.read(appLogPaginatorProvider(query).future);
      expect(calls, 1, reason: 'the opening page');

      final paginator = container.read(appLogPaginatorProvider(query).notifier);
      // Two scroll notifications arriving before either fetch has landed.
      await Future.wait([paginator.next(), paginator.next()]);

      expect(calls, 2, reason: 'a duplicate fetch would read the same cursor twice');
      final state = container.read(appLogPaginatorProvider(query)).requireValue;
      expect(state.logs.map((e) => e.message), equals(['3', '2', '1', '0']));
      expect(state.hasMore, isFalse);
    });

    test('sequential next() calls advance the cursor and stop at the last page', () async {
      final storage = MockAppLogStorage();
      final cursors = <int?>[];
      when(
        () => storage.page(
          cursor: any(named: 'cursor'),
          minLevelValue: any(named: 'minLevelValue'),
          searchQuery: any(named: 'searchQuery'),
          loggerNamePrefixes: any(named: 'loggerNamePrefixes'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((invocation) async {
        final cursor = _pageArgs(invocation)[#cursor] as int?;
        cursors.add(cursor);
        if (cursor == null) return _page(['3', '2', '1'], next: 1);
        if (cursor == 1) return _page(['2', '0'], next: 2);
        return _page(['final']);
      });

      const query = AppLogQuery();
      final container = _container(storage, query);
      await container.read(appLogPaginatorProvider(query).future);
      final paginator = container.read(appLogPaginatorProvider(query).notifier);

      await paginator.next();
      await paginator.next();

      expect(cursors, equals([null, 1, 2]));
      final state = container.read(appLogPaginatorProvider(query)).requireValue;
      expect(state.logs.map((e) => e.message), equals(['3', '2', '1', '2', '0', 'final']));
      expect(state.hasMore, isFalse, reason: 'the last page reported no further cursor');

      // Paging is not wedged after the tail page: a further call is a no-op.
      await paginator.next();
      expect(cursors, equals([null, 1, 2]));
    });

    test('query, log level and page size are forwarded to storage', () async {
      final storage = MockAppLogStorage();
      Map<Symbol, dynamic>? args;
      when(
        () => storage.page(
          cursor: any(named: 'cursor'),
          minLevelValue: any(named: 'minLevelValue'),
          searchQuery: any(named: 'searchQuery'),
          loggerNamePrefixes: any(named: 'loggerNamePrefixes'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((invocation) async {
        args = _pageArgs(invocation);
        return _page([]);
      });

      const query = AppLogQuery(search: 'checkmate');
      final container = _container(storage, query);
      await container.read(appLogPaginatorProvider(query).future);

      expect(args, isNotNull);
      expect(args![#cursor], isNull);
      expect(args![#searchQuery], 'checkmate');
      expect(args![#loggerNamePrefixes], isEmpty);
      expect(args![#minLevelValue], LogPrefs.defaults.level.value);
      expect(args![#limit], 20);
    });

    test('category prefixes are forwarded when there is no free-text search', () async {
      final storage = MockAppLogStorage();
      Map<Symbol, dynamic>? args;
      when(
        () => storage.page(
          cursor: any(named: 'cursor'),
          minLevelValue: any(named: 'minLevelValue'),
          searchQuery: any(named: 'searchQuery'),
          loggerNamePrefixes: any(named: 'loggerNamePrefixes'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((invocation) async {
        args = _pageArgs(invocation);
        return _page([]);
      });

      const query = AppLogQuery(loggerPrefixes: ['Engine', 'Review']);
      final container = _container(storage, query);
      await container.read(appLogPaginatorProvider(query).future);

      expect(args, isNotNull);
      expect(args![#searchQuery], isNull);
      expect(args![#loggerNamePrefixes], equals(['Engine', 'Review']));
    });
  });
}
