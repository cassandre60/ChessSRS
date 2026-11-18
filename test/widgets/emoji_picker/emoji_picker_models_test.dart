import 'package:chess_srs/src/widgets/emoji_picker/emoji_picker_models.dart';
import 'package:flutter_test/flutter_test.dart';

Emoji _emoji(
  String id,
  String name,
  Set<String> keywords, {
  List<String> skinSrcs = const ['skin-default'],
}) => Emoji(
  id: id,
  name: name,
  keywords: keywords,
  skins: [for (final src in skinSrcs) Skin(src: src)],
);

EmojiData _fixture() {
  final emojis = <Emoji>[
    _emoji('grinning-face', 'grinning face', {'happy', 'smile'}),
    _emoji('smiling-eye', 'smiling face with smiling eyes', {'happy', 'eyes'}),
    _emoji('rocket', 'rocket ship', {'space'}, skinSrcs: ['rocket-a', 'rocket-b']),
  ];
  return EmojiData(
    emojis: {for (final emoji in emojis) emoji.id: emoji},
    categories: [
      const Category(id: 'smileys', name: 'Smileys', emojiIds: ['grinning-face', 'smiling-eye']),
      const Category(id: 'travel', name: 'Travel', emojiIds: ['rocket']),
    ],
  );
}

void main() {
  group('Category JSON', () {
    test('fromJson reads emoji ids from the "emojis" key', () {
      final category = Category.fromJson(<String, Object?>{
        'id': 'smileys',
        'name': 'Smileys & People',
        'emojis': ['grinning-face', 'smiling-eye'],
      });

      expect(category.id, 'smileys');
      expect(category.name, 'Smileys & People');
      expect(category.emojiIds, ['grinning-face', 'smiling-eye']);
    });
  });

  group('EmojiData.getEmojiById', () {
    test('returns the first skin src for a known id', () {
      expect(_fixture().getEmojiById('rocket'), 'rocket-a');
    });

    test('throws ArgumentError for an unknown id', () {
      expect(() => _fixture().getEmojiById('does-not-exist'), throwsArgumentError);
    });
  });

  group('EmojiData.filterByKeyword', () {
    test('matches on emoji id, case-insensitively, and drops empty categories', () {
      final result = _fixture().filterByKeyword('GRINNING-FACE');

      expect(result.emojis.keys, {'grinning-face'});
      expect(result.categories, hasLength(1));
      expect(result.categories.single.id, 'smileys');
      expect(result.categories.single.emojiIds, ['grinning-face']);
    });

    test('matches on emoji name only', () {
      final result = _fixture().filterByKeyword('SHIP');

      expect(result.emojis.keys, {'rocket'});
      expect(result.categories, hasLength(1));
      expect(result.categories.single.id, 'travel');
      expect(result.categories.single.emojiIds, ['rocket']);
    });

    test('matches on a keyword only', () {
      final result = _fixture().filterByKeyword('smILE');

      expect(result.emojis.keys, {'grinning-face'});
    });

    test('keepEmptyCategories retains categories with no matches', () {
      final data = _fixture();

      final kept = data.filterByKeyword('unmatched', keepEmptyCategories: true);
      expect(kept.emojis, isEmpty);
      expect(kept.categories.map((c) => c.id), ['smileys', 'travel']);
      expect(kept.categories.map((c) => c.emojiIds), [isEmpty, isEmpty]);

      final dropped = data.filterByKeyword('unmatched');
      expect(dropped.emojis, isEmpty);
      expect(dropped.categories, isEmpty);
    });
  });

  group('Emoji JSON', () {
    test('fromJson maps keywords to a set and skins to Skin objects', () {
      final emoji = Emoji.fromJson(<String, dynamic>{
        'id': 'rocket',
        'name': 'rocket ship',
        'keywords': ['space', 'launch'],
        'skins': [
          {'src': 'rocket-a'},
          {'src': 'rocket-b'},
        ],
      });

      expect(emoji.id, 'rocket');
      expect(emoji.keywords, {'space', 'launch'});
      expect(emoji.skins.map((skin) => skin.src), ['rocket-a', 'rocket-b']);
    });
  });
}
