import 'package:chess_srs/src/model/user/profile.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Profile.fromPick', () {
    test('reads scalar fields and country from flag or country key', () {
      final profile = Profile.fromPick(
        pick(<String, dynamic>{
          'flag': 'FR',
          'location': 'Paris',
          'bio': 'Hello',
          'realName': 'Jane Doe',
          'fideRating': 2100,
          'uscfRating': 2200,
          'ecfRating': 2000,
          'rcfRating': 2300,
          'cfcRating': 2400,
          'dsbRating': 1900,
        }).required(),
      );

      expect(profile.country, 'FR');
      expect(profile.location, 'Paris');
      expect(profile.bio, 'Hello');
      expect(profile.realName, 'Jane Doe');
      expect(profile.fideRating, 2100);
      expect(profile.uscfRating, 2200);
      expect(profile.ecfRating, 2000);
      expect(profile.rcfRating, 2300);
      expect(profile.cfcRating, 2400);
      expect(profile.dsbRating, 1900);
      expect(profile.links, isNull);
    });

    test('prefers flag over country and falls back to country', () {
      final fromFlag = Profile.fromPick(
        pick(<String, dynamic>{'flag': 'FR', 'country': 'Germany'}).required(),
      );
      final fromCountry = Profile.fromPick(pick(<String, dynamic>{'country': 'DE'}).required());

      expect(fromFlag.country, 'FR');
      expect(fromCountry.country, 'DE');
    });

    test('parses newline-separated links, trims empties, and keeps unknown hosts', () {
      final profile = Profile.fromJson(<String, dynamic>{
        'links': 'https://github.com/octocat\n\n  \nexample.com/path\n',
      });

      expect(profile.links, isNotNull);
      expect(profile.links!.length, 2);
      expect(profile.links![0].site, LinkSite.github);
      expect(profile.links![0].url.toString(), 'https://github.com/octocat');
      expect(profile.links![1].site, isNull);
      expect(profile.links![1].url.toString(), 'example.com/path');
    });

    test('drops unparseable link entries', () {
      final profile = Profile.fromJson(<String, dynamic>{
        'links': 'https://github.com/octocat\nhttp://[::1',
      });

      expect(profile.links, isNotNull);
      expect(profile.links!.map((l) => l.url.toString()), ['https://github.com/octocat']);
    });
  });

  group('SocialLink.fromUrl', () {
    test('adds https scheme when missing and detects known site', () {
      final link = SocialLink.fromUrl('twitter.com/chess');

      expect(link, isNotNull);
      expect(link!.site, LinkSite.twitter);
      expect(link.url.scheme, 'https');
      expect(link.url.host, 'twitter.com');
    });

    test('strips leading www when matching site domains', () {
      final link = SocialLink.fromUrl('https://www.youtube.com/@lichess');

      expect(link, isNotNull);
      expect(link!.site, LinkSite.youtube);
      expect(link.url.toString(), 'https://www.youtube.com/@lichess');
    });

    test('returns null for unknown domains and invalid urls', () {
      expect(SocialLink.fromUrl('https://example.org/profile'), isNull);
      expect(SocialLink.fromUrl('http://[::1'), isNull);
    });

    test('recognizes representative supported domains', () {
      expect(SocialLink.fromUrl('https://x.com/user')!.site, LinkSite.twitter);
      expect(SocialLink.fromUrl('https://bsky.app/profile/x')!.site, LinkSite.bluesky);
      expect(SocialLink.fromUrl('https://masto.ai/@user')!.site, LinkSite.mastodon);
      expect(SocialLink.fromUrl('https://t.me/user')!.site, LinkSite.telegram);
      expect(SocialLink.fromUrl('https://chess.com/member/user')!.site, LinkSite.chessCom);
    });
  });
}
