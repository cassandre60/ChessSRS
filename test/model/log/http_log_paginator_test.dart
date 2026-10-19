// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/log/http_log_paginator.dart';
import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockHttpLogStorage extends Mock implements HttpLogStorage {}

HttpLogEntry _entry(String id) => HttpLogEntry(
  httpLogId: id,
  requestMethod: 'GET',
  requestUrl: Uri.parse('https://example.test/$id'),
  requestDateTime: DateTime.utc(2026, 9, 25),
);

HttpLog _page(List<String> ids, {int? next}) =>
    HttpLog(items: ids.map(_entry).toList().toIList(), next: next);

void main() {
  group('HttpLogPaginator paging', () {
    /// A storage whose reads are counted, so the tests can prove that two overlapping next()
    /// calls fetch the page once. [pageCalls] counts every read, including the opening one.
    ///
    /// The overlap needs no slow-read simulation: the two calls are issued synchronously, so no
    /// state update can land between them whatever the read duration is.
    ({MockHttpLogStorage storage, int Function() pageCalls}) build() {
      final storage = MockHttpLogStorage();
      var calls = 0;
      when(
        () => storage.page(
          cursor: any(named: 'cursor'),
          searchQuery: any(named: 'searchQuery'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((invocation) async {
        calls++;
        final cursor = invocation.namedArguments[#cursor] as int?;
        return cursor == null ? _page(['3', '2', '1'], next: 1) : _page(['0'], next: null);
      });
      return (storage: storage, pageCalls: () => calls);
    }

    test('two overlapping next() calls fetch the page once', () async {
      final storage = build();
      final container = ProviderContainer(
        overrides: [httpLogStorageProvider.overrideWith((ref) => Future.value(storage.storage))],
      );
      addTearDown(container.dispose);
      // autoDispose: a bare read is collected straight back, and the paginator would be
      // disposed before the overlapping calls below had finished.
      final subscription = container.listen(httpLogPaginatorProvider(null), (_, _) {});
      addTearDown(subscription.close);

      await container.read(httpLogPaginatorProvider(null).future);
      expect(storage.pageCalls(), 1, reason: 'the opening page');

      final paginator = container.read(httpLogPaginatorProvider(null).notifier);
      // Two scroll notifications arriving before either has updated the state.
      await Future.wait([paginator.next(), paginator.next()]);

      expect(
        storage.pageCalls(),
        2,
        reason: 'both calls read the same cursor and fetched the same page',
      );

      final logs = container.read(httpLogPaginatorProvider(null)).requireValue.logs;
      expect(
        logs.map((e) => e.httpLogId),
        equals(['3', '2', '1', '0']),
        reason: 'a page fetched twice is appended twice',
      );
    });

    test('a later next() still works after an ignored one', () async {
      final storage = build();
      final container = ProviderContainer(
        overrides: [httpLogStorageProvider.overrideWith((ref) => Future.value(storage.storage))],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(httpLogPaginatorProvider(null), (_, _) {});
      addTearDown(subscription.close);

      await container.read(httpLogPaginatorProvider(null).future);
      final paginator = container.read(httpLogPaginatorProvider(null).notifier);

      await Future.wait([paginator.next(), paginator.next()]);
      expect(storage.pageCalls(), 2);

      // Paging is not left permanently wedged by the guard.
      await paginator.next();
      expect(storage.pageCalls(), 2, reason: 'the last page reported no further cursor');
    });
  });
}
