// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/study/study_filter.dart';
import 'package:chess_srs/src/model/study/study_list_paginator.dart';
import 'package:chess_srs/src/model/study/study_repository.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockStudyRepository extends Mock implements StudyRepository {}

StudyList _page(List<String> ids, {int? nextPage}) => (
  studies: ids
      .map(
        (id) => StudyPageItem(
          id: StudyId(id),
          name: id,
          liked: false,
          likes: 0,
          updatedAt: DateTime.utc(2026, 11, 18),
          owner: null,
          topics: IList(const <String>[]),
          members: IList(const <StudyMember>[]),
          chapters: IList(const <String>[]),
          flair: null,
          visibility: StudyVisibility.public,
        ),
      )
      .toIList(),
  nextPage: nextPage,
);

void main() {
  setUpAll(() {
    registerFallbackValue(StudyCategory.all);
    registerFallbackValue(StudyListOrder.hot);
  });

  ({ProviderContainer container, StudyListNotifierParams params}) setup(
    MockStudyRepository repo, {
    String? search,
  }) {
    final params = (category: StudyCategory.mine, order: StudyListOrder.newest, search: search);
    final container = ProviderContainer(
      overrides: [studyRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // autoDispose: a bare read is collected straight back, so keep the notifier alive.
    final subscription = container.listen(studyListPaginatorProvider(params), (_, _) {});
    addTearDown(subscription.close);
    return (container: container, params: params);
  }

  group('StudyListPaginatorNotifier', () {
    test('first page comes from getStudies with category, order and page 1', () async {
      final repo = MockStudyRepository();
      when(
        () => repo.getStudies(
          category: any(named: 'category'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => _page(['a', 'b'], nextPage: 2));

      final ctx = setup(repo);
      final state = await ctx.container.read(studyListPaginatorProvider(ctx.params).future);

      expect(state.studies.map((s) => s.id.value), equals(['a', 'b']));
      expect(state.nextPage, 2);
      verify(
        () => repo.getStudies(category: StudyCategory.mine, order: StudyListOrder.newest, page: 1),
      ).called(1);
      verifyNever(
        () => repo.searchStudies(
          query: any(named: 'query'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      );
    });

    test('next appends the following page and advances the cursor', () async {
      final repo = MockStudyRepository();
      when(
        () => repo.getStudies(
          category: any(named: 'category'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((invocation) async {
        final page = invocation.namedArguments[#page] as int;
        return switch (page) {
          1 => _page(['a', 'b'], nextPage: 2),
          2 => _page(['c']),
          _ => throw StateError('unexpected page $page'),
        };
      });

      final ctx = setup(repo);
      await ctx.container.read(studyListPaginatorProvider(ctx.params).future);
      final notifier = ctx.container.read(studyListPaginatorProvider(ctx.params).notifier);

      await notifier.next();

      final state = ctx.container.read(studyListPaginatorProvider(ctx.params)).requireValue;
      expect(state.studies.map((s) => s.id.value), equals(['a', 'b', 'c']));
      expect(state.nextPage, isNull);
      verify(
        () => repo.getStudies(category: StudyCategory.mine, order: StudyListOrder.newest, page: 2),
      ).called(1);
    });

    test('next is a no-op on the last page', () async {
      final repo = MockStudyRepository();
      when(
        () => repo.getStudies(
          category: any(named: 'category'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => _page(['a']));

      final ctx = setup(repo);
      await ctx.container.read(studyListPaginatorProvider(ctx.params).future);
      final notifier = ctx.container.read(studyListPaginatorProvider(ctx.params).notifier);

      await notifier.next();

      final state = ctx.container.read(studyListPaginatorProvider(ctx.params)).requireValue;
      expect(state.studies.map((s) => s.id.value), equals(['a']));
      verify(
        () => repo.getStudies(category: StudyCategory.mine, order: StudyListOrder.newest, page: 1),
      ).called(1);
    });

    test('search routes the first page to searchStudies', () async {
      final repo = MockStudyRepository();
      when(
        () => repo.searchStudies(
          query: any(named: 'query'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((_) async => _page(['x'], nextPage: 3));

      final ctx = setup(repo, search: 'foo');
      final state = await ctx.container.read(studyListPaginatorProvider(ctx.params).future);

      expect(state.studies.map((s) => s.id.value), equals(['x']));
      expect(state.nextPage, 3);
      verify(
        () => repo.searchStudies(query: 'foo', order: StudyListOrder.newest, page: 1),
      ).called(1);
      verifyNever(
        () => repo.getStudies(
          category: any(named: 'category'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      );
    });

    test('search paging uses the cursor from the previous page', () async {
      final repo = MockStudyRepository();
      when(
        () => repo.searchStudies(
          query: any(named: 'query'),
          order: any(named: 'order'),
          page: any(named: 'page'),
        ),
      ).thenAnswer((invocation) async {
        final page = invocation.namedArguments[#page] as int;
        return switch (page) {
          1 => _page(['x'], nextPage: 3),
          3 => _page(['y']),
          _ => throw StateError('unexpected page $page'),
        };
      });

      final ctx = setup(repo, search: 'foo');
      await ctx.container.read(studyListPaginatorProvider(ctx.params).future);
      final notifier = ctx.container.read(studyListPaginatorProvider(ctx.params).notifier);

      await notifier.next();

      final state = ctx.container.read(studyListPaginatorProvider(ctx.params)).requireValue;
      expect(state.studies.map((s) => s.id.value), equals(['x', 'y']));
      expect(state.nextPage, isNull);
      verify(
        () => repo.searchStudies(query: 'foo', order: StudyListOrder.newest, page: 3),
      ).called(1);
    });
  });
}
