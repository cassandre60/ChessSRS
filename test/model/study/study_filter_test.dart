// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/study/study_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StudyCategory', () {
    test('has the expected values in stable order', () {
      expect(StudyCategory.values, const [
        StudyCategory.all,
        StudyCategory.mine,
        StudyCategory.member,
        StudyCategory.public,
        StudyCategory.private,
        StudyCategory.likes,
      ]);
    });

    test('names are stable', () {
      expect(StudyCategory.all.name, 'all');
      expect(StudyCategory.mine.name, 'mine');
      expect(StudyCategory.member.name, 'member');
      expect(StudyCategory.public.name, 'public');
      expect(StudyCategory.private.name, 'private');
      expect(StudyCategory.likes.name, 'likes');
    });
  });

  group('StudyListOrder', () {
    test('has the expected values in stable order', () {
      expect(StudyListOrder.values, const [
        StudyListOrder.hot,
        StudyListOrder.popular,
        StudyListOrder.newest,
        StudyListOrder.oldest,
        StudyListOrder.updated,
      ]);
    });

    test('names are stable', () {
      expect(StudyListOrder.hot.name, 'hot');
      expect(StudyListOrder.popular.name, 'popular');
      expect(StudyListOrder.newest.name, 'newest');
      expect(StudyListOrder.oldest.name, 'oldest');
      expect(StudyListOrder.updated.name, 'updated');
    });
  });
}
