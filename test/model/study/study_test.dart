import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

StudyChapterMeta _meta(String id, String name) =>
    StudyChapterMeta(id: StudyChapterId(id), name: name, fen: null);

StudyChapter _chapter(String id) => StudyChapter(
  id: StudyChapterId(id),
  setup: const StudyChapterSetup(
    id: null,
    orientation: Side.white,
    variant: Variant.standard,
    fromFen: false,
  ),
  practise: false,
  conceal: null,
  gamebook: false,
  features: (computer: false, explorer: false),
);

StudyMember _member(String userId, String name) => StudyMember(
  user: LightUser(id: UserId(userId), name: name),
  role: 'w',
);

Study _study({
  required IList<StudyChapterMeta> chapters,
  required StudyChapter chapter,
  UserId? ownerId,
  IMap<UserId, StudyMember>? members,
}) {
  return Study(
    id: const StudyId('study-1'),
    name: 'Test study',
    liked: false,
    likes: 0,
    ownerId: ownerId,
    features: (cloneable: false, sticky: false),
    topics: const IListConst(<String>[]),
    chapters: chapters,
    chapter: chapter,
    members: members ?? IMap<UserId, StudyMember>(),
    hints: const IListConst(<String?>[]),
    deviationComments: const IListConst(<String?>[]),
  );
}

void main() {
  group('Study.getChapterIndex', () {
    test('returns index of matching chapter id', () {
      final study = _study(
        chapters: IList([_meta('c1', 'One'), _meta('c2', 'Two'), _meta('c3', 'Three')]),
        chapter: _chapter('c1'),
      );

      expect(study.getChapterIndex(const StudyChapterId('c1')), 0);
      expect(study.getChapterIndex(const StudyChapterId('c2')), 1);
      expect(study.getChapterIndex(const StudyChapterId('c3')), 2);
    });

    test('returns -1 when chapter id is absent', () {
      final study = _study(
        chapters: IList([_meta('c1', 'One'), _meta('c2', 'Two')]),
        chapter: _chapter('c1'),
      );

      expect(study.getChapterIndex(const StudyChapterId('missing')), -1);
    });
  });

  group('Study.currentChapterMeta', () {
    test('returns meta matching the current chapter id', () {
      final currentMeta = _meta('c2', 'Current');
      final study = _study(
        chapters: IList([_meta('c1', 'One'), currentMeta, _meta('c3', 'Three')]),
        chapter: _chapter('c2'),
      );

      expect(study.currentChapterMeta, currentMeta);
      expect(study.currentChapterMeta.name, 'Current');
    });
  });

  group('Study.owner', () {
    test('returns null when ownerId is null', () {
      final study = _study(
        chapters: IList([_meta('c1', 'One')]),
        chapter: _chapter('c1'),
        ownerId: null,
        members: IMap({const UserId('alice'): _member('alice', 'Alice')}),
      );

      expect(study.owner, isNull);
    });

    test('returns matching member when ownerId is present', () {
      final alice = _member('alice', 'Alice');
      final bob = _member('bob', 'Bob');
      final study = _study(
        chapters: IList([_meta('c1', 'One')]),
        chapter: _chapter('c1'),
        ownerId: const UserId('bob'),
        members: IMap({const UserId('alice'): alice, const UserId('bob'): bob}),
      );

      expect(study.owner, bob);
      expect(study.owner?.user.name, 'Bob');
    });
  });

  group('studyChapterFeaturesFromJson', () {
    test('defaults computer/explorer to false when keys are absent', () {
      // Mutation pins: flipping either `?? false` default to `?? true` makes a
      // chapter JSON without explicit feature keys silently enable the
      // computer analysis/explorer features.
      final features = studyChapterFeaturesFromJson(<String, Object?>{});

      expect(features.computer, isFalse);
      expect(features.explorer, isFalse);
    });

    test('defaults to false for null values and passes explicit values through', () {
      final features = studyChapterFeaturesFromJson(<String, Object?>{
        'computer': null,
        'explorer': true,
      });

      expect(features.computer, isFalse);
      expect(features.explorer, isTrue);
    });
  });
}
