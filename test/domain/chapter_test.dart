import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chapter.create', () {
    test('generates id and defaults', () {
      final before = DateTime.now();
      final chapter = Chapter.create(
        studyId: 'study-1',
        sourceOrder: 2,
        title: 'Main',
      );
      final after = DateTime.now();

      expect(chapter.id, isNotEmpty);
      expect(chapter.studyId, 'study-1');
      expect(chapter.sourceOrder, 2);
      expect(chapter.title, 'Main');
      expect(chapter.startingFen, isNull);
      expect(chapter.root, isNull);
      expect(chapter.opening, isNull);
      expect(chapter.orientation, Side.white);
      expect(chapter.createdAt, isNotNull);
      expect(
        chapter.createdAt!.isAfter(
              before.subtract(const Duration(seconds: 1)),
            ) &&
            chapter.createdAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('accepts explicit fields', () {
      final createdAt = DateTime.utc(2026, 11, 12);
      final root = RepertoireNode.root(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      );
      final chapter = Chapter.create(
        studyId: 'study-2',
        sourceOrder: 0,
        title: 'Sicilian',
        startingFen: 'custom-fen',
        root: root,
        createdAt: createdAt,
        opening: 'Sicilian Defense',
        orientation: Side.black,
      );

      expect(chapter.title, 'Sicilian');
      expect(chapter.startingFen, 'custom-fen');
      expect(chapter.root, same(root));
      expect(chapter.createdAt, createdAt);
      expect(chapter.opening, 'Sicilian Defense');
      expect(chapter.orientation, Side.black);
    });
  });

  group('root resolution', () {
    test('returns provided root without resolver', () {
      final root = RepertoireNode.root(fen: 'fen', fenKey: 'key');
      final chapter = Chapter(
        id: 'c1',
        studyId: 's1',
        sourceOrder: 0,
        root: root,
      );

      expect(chapter.root, same(root));
    });

    test('lazily resolves and caches root from resolver', () {
      var calls = 0;
      final resolved = RepertoireNode.root(fen: 'fen', fenKey: 'key');
      final chapter = Chapter(
        id: 'c1',
        studyId: 's1',
        sourceOrder: 0,
        rootResolver: () {
          calls++;
          return resolved;
        },
      );

      expect(calls, 0);
      expect(chapter.root, same(resolved));
      expect(chapter.root, same(resolved));
      expect(calls, 1);
    });
  });

  group('copyWith', () {
    test('updates provided fields and preserves identity/ordering', () {
      final root = RepertoireNode.root(fen: 'fen', fenKey: 'key');
      final createdAt = DateTime.utc(2026, 1, 1);
      final chapter = Chapter(
        id: 'chapter-id',
        studyId: 'study-id',
        sourceOrder: 3,
        title: 'Old',
        startingFen: 'old-fen',
        root: root,
        createdAt: createdAt,
        opening: 'Old Opening',
        orientation: Side.white,
      );

      final copy = chapter.copyWith(
        title: 'New',
        startingFen: 'new-fen',
        opening: 'New Opening',
        orientation: Side.black,
      );

      expect(copy.id, 'chapter-id');
      expect(copy.studyId, 'study-id');
      expect(copy.sourceOrder, 3);
      expect(copy.createdAt, createdAt);
      expect(copy.title, 'New');
      expect(copy.startingFen, 'new-fen');
      expect(copy.opening, 'New Opening');
      expect(copy.orientation, Side.black);
      expect(copy.root, same(root));
    });

    test('explicit root replaces resolved root and clears resolver', () {
      var calls = 0;
      final resolved = RepertoireNode.root(fen: 'old', fenKey: 'old');
      final replacement = RepertoireNode.root(fen: 'new', fenKey: 'new');
      final chapter = Chapter(
        id: 'c1',
        studyId: 's1',
        sourceOrder: 0,
        rootResolver: () {
          calls++;
          return resolved;
        },
      );
      expect(chapter.root, same(resolved));
      expect(calls, 1);

      final copy = chapter.copyWith(root: replacement);

      expect(copy.root, same(replacement));
      expect(chapter.root, same(resolved));
    });

    test('new resolver replaces previous cached root', () {
      final oldRoot = RepertoireNode.root(fen: 'old', fenKey: 'old');
      final newRoot = RepertoireNode.root(fen: 'new', fenKey: 'new');
      final chapter = Chapter(
        id: 'c1',
        studyId: 's1',
        sourceOrder: 0,
        root: oldRoot,
      );

      var calls = 0;
      final copy = chapter.copyWith(
        rootResolver: () {
          calls++;
          return newRoot;
        },
      );

      expect(calls, 0);
      expect(copy.root, same(newRoot));
      expect(calls, 1);
    });
  });

  group('equality and toString', () {
    test('equality depends on identity/content fields including root', () {
      final root = RepertoireNode.root(fen: 'fen', fenKey: 'key');
      final a = Chapter(id: 'c1', studyId: 's1', sourceOrder: 0, root: root);
      final b = Chapter(id: 'c1', studyId: 's1', sourceOrder: 0, root: root);
      final c = a.copyWith(title: 'Different');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('toString includes key fields', () {
      final chapter = Chapter(
        id: 'c1',
        studyId: 's1',
        sourceOrder: 0,
        title: 'Intro',
        opening: 'French Defense',
        orientation: Side.black,
      );

      final text = chapter.toString();
      expect(text, contains('Chapter('));
      expect(text, contains('id: c1'));
      expect(text, contains('studyId: s1'));
      expect(text, contains('title: Intro'));
      expect(text, contains('opening: French Defense'));
      expect(text, contains('orientation: Side.black'));
    });
  });
}
