import 'package:chess_srs/src/model/account/flair_provider.dart';
import 'package:chess_srs/src/utils/lichess_assets.dart';
import 'package:chess_srs/src/widgets/emoji_picker/emoji_picker_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_container.dart';

// A flair list that spans several categories, includes a multi-part name
// (to exercise keyword splitting) and contains a blank line (which the
// provider must ignore rather than treat as an empty flair).
const _flairList =
    'smileys.grinning\n'
    'people.waving-hand\n'
    'nature.rose\n'
    'food-drink.coffee\n'
    '\n'
    'activity.running\n';

Future<EmojiData> loadFlairs() async {
  final client = MockClient((request) async => http.Response(_flairList, 200));
  final container = await lichessClientContainer(client);
  return await container.read(flairListProvider.future);
}

void main() {
  test('groups flairs into their declared category by id prefix', () async {
    final data = await loadFlairs();

    expect(data.categories, hasLength(categories.length));
    final byId = {for (final category in data.categories) category.id: category};
    expect(byId['smileys']!.emojiIds, ['smileys.grinning']);
    expect(byId['people']!.emojiIds, ['people.waving-hand']);
    expect(byId['nature']!.emojiIds, ['nature.rose']);
    expect(byId['food-drink']!.emojiIds, ['food-drink.coffee']);
    expect(byId['activity']!.emojiIds, ['activity.running']);
    expect(byId['objects']!.emojiIds, isEmpty);
    expect(byId['symbols']!.emojiIds, isEmpty);
  });

  test('ignores blank lines in the remote list', () async {
    final data = await loadFlairs();

    expect(data.emojis, hasLength(5));
    expect(data.emojis.keys, isNot(contains('')));
    for (final category in data.categories) {
      expect(category.emojiIds, isNot(contains('')));
    }
  });

  test('derives name, keywords and flair image src from each line', () async {
    final data = await loadFlairs();

    final waving = data.emojis['people.waving-hand']!;
    expect(waving.id, 'people.waving-hand');
    expect(waving.name, 'waving-hand');
    expect(waving.keywords, {'people', 'waving', 'hand'});
    expect(waving.skins.single.src, lichessFlairSrc('people.waving-hand'));
  });

  test('category metadata follows the declared category order', () async {
    final data = await loadFlairs();

    expect(data.categories.map((c) => c.id), categories.map((c) => c[0]));
    expect(data.categories.first.name, 'Smileys');
    expect(data.categories.last.name, 'Symbols');
  });

  test('getEmojiById resolves the flair image src', () async {
    final data = await loadFlairs();

    expect(data.getEmojiById('smileys.grinning'), lichessFlairSrc('smileys.grinning'));
  });
}
