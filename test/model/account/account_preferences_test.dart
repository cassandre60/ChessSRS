import 'dart:convert';

import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';
import '../auth/fake_auth_storage.dart';

/// Builds a valid `/api/account/preferences` server response, with the `zen`
/// value overridable so tests can assert parsing and refetching.
String prefsResponse({int zen = 0}) =>
    '''
{
  "prefs": {
    "autoQueen": 2,
    "autoThreefold": 2,
    "takeback": 3,
    "moretime": 3,
    "clockTenths": 1,
    "clockSound": true,
    "premove": true,
    "follow": true,
    "challenge": 4,
    "message": 3,
    "submitMove": 4,
    "confirmResign": 1,
    "zen": $zen,
    "pieceNotation": 0,
    "ratings": 1
  },
  "language": "en-GB"
}
''';

void main() {
  group('AccountPrefState serialization', () {
    test('round-trips local preferences through JSON storage', () {
      final prefs = defaultAccountPreferences.copyWith(
        showRatings: ShowRatings.no,
        clockSound: const BooleanPref(false),
      );

      // Encode the way local storage does, then inspect the primitive JSON.
      final json = jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>;

      // Enums serialize to their integer value, booleans to JSON booleans.
      expect(json['showRatings'], ShowRatings.no.value);
      expect(json['clockSound'], isFalse);

      final decoded = AccountPrefState.fromJson(json);

      expect(decoded.showRatings, ShowRatings.no);
      expect(decoded.clockSound.value, isFalse);
    });

    test('falls back to defaults on malformed json', () {
      expect(AccountPrefState.fromJson({'zen': 'not-an-int'}), defaultAccountPreferences);
    });
  });

  group('AccountPreferences when signed out', () {
    test('uses local defaults when nothing is stored', () async {
      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    test('loads persisted local preferences', () async {
      final binding = TestLichessBinding.ensureInitialized();
      final stored = defaultAccountPreferences.copyWith(
        showRatings: ShowRatings.no,
        pieceNotation: PieceNotation.letter,
        clockSound: const BooleanPref(false),
        submitMove: SubmitMove({SubmitMoveChoice.blitz, SubmitMoveChoice.rapid}),
      );
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: jsonEncode(stored.toJson()),
      });

      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs.showRatings, ShowRatings.no);
      expect(prefs.pieceNotation, PieceNotation.letter);
      expect(prefs.clockSound.value, isFalse);
      expect(prefs.submitMove.choices, {SubmitMoveChoice.blitz, SubmitMoveChoice.rapid});
    });

    test('falls back to defaults when stored local preferences are corrupt', () async {
      final binding = TestLichessBinding.ensureInitialized();
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: 'not valid json {',
      });

      final container = await makeContainer();

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    // Resetting to defaults is the correct behaviour; what was missing is any record of *why*.
    // The user sees their customisations vanish with no explanation, and support has nothing to
    // look at. The corruption has to reach the Logger pipeline so it appears in the in-app log
    // viewer, with the stack that says where the decode failed.
    test('corrupt stored preferences are reported through the Logger, with a stack', () async {
      final binding = TestLichessBinding.ensureInitialized();
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: 'not valid json {',
      });

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      final container = await makeContainer();
      await container.read(accountPreferencesProvider.future);

      final report = records.where((r) => r.level >= Level.SEVERE).toList();
      expect(
        report,
        isNotEmpty,
        reason: 'a silent reset to defaults left no trace of the corrupted payload',
      );
      expect(report.first.message, contains('corrupt'));
      expect(report.first.error, isNotNull);
      expect(report.first.stackTrace, isNotNull);
    });

    test('setting a preference updates the in-memory state without any network call', () async {
      final requests = <http.BaseRequest>[];
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() {
              return MockClient((request) async {
                requests.add(request);
                return http.Response('', 200);
              });
            });
          }),
        },
      );

      await container.read(accountPreferencesProvider.future);
      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);

      final prefs = await container.read(accountPreferencesProvider.future);
      expect(prefs.showRatings, ShowRatings.no);
      expect(requests, isEmpty);
    });

    test('setting a preference persists it to local storage', () async {
      final container = await makeContainer();

      await container.read(accountPreferencesProvider.future);
      await container.read(accountPreferencesProvider.notifier).setClockTenths(ClockTenths.always);

      final stored = testBinding.sharedPreferences.getString(PrefCategory.account.storageKey);
      expect(stored, isNotNull);

      final decoded = AccountPrefState.fromJson(jsonDecode(stored!) as Map<String, dynamic>);
      expect(decoded.clockTenths, ClockTenths.always);
    });

    // SPEC names no invariant for locally stored account preferences. What is
    // pinned here is the behaviour the class documents: a signed-out preference
    // lives on the device, under its own field, and survives later writes.
    test('every local setter stores its own field and keeps the others', () async {
      final container = await makeContainer();
      final notifier = container.read(accountPreferencesProvider.notifier);

      await notifier.setZen(Zen.gameAuto);
      await notifier.setPieceNotation(PieceNotation.letter);
      await notifier.setShowRatings(ShowRatings.no);
      await notifier.setTakeback(Takeback.never);
      await notifier.setAutoQueen(AutoQueen.always);
      await notifier.setAutoThreefold(AutoThreefold.time);
      await notifier.setMoretime(Moretime.casual);
      await notifier.setClockTenths(ClockTenths.always);
      await notifier.setClockSound(const BooleanPref(false));
      await notifier.setSubmitMove(SubmitMove({SubmitMoveChoice.rapid, SubmitMoveChoice.blitz}));
      await notifier.setFollow(const BooleanPref(false));
      await notifier.setChallenge(Challenge.always);
      await notifier.setMessage(Message.friends);

      final expected = defaultAccountPreferences.copyWith(
        zenMode: Zen.gameAuto,
        pieceNotation: PieceNotation.letter,
        showRatings: ShowRatings.no,
        takeback: Takeback.never,
        autoQueen: AutoQueen.always,
        autoThreefold: AutoThreefold.time,
        moretime: Moretime.casual,
        clockTenths: ClockTenths.always,
        clockSound: const BooleanPref(false),
        submitMove: SubmitMove({SubmitMoveChoice.rapid, SubmitMoveChoice.blitz}),
        follow: const BooleanPref(false),
        challenge: Challenge.always,
        message: Message.friends,
      );

      // Each setter reads the stored state, applies its own change and writes
      // the whole state back, so the last write has to carry all thirteen.
      // Asserted field by field: the nested pref types have no value equality.
      final prefs = await container.read(accountPreferencesProvider.future);
      expect(prefs.zenMode, expected.zenMode);
      expect(prefs.pieceNotation, expected.pieceNotation);
      expect(prefs.showRatings, expected.showRatings);
      expect(prefs.takeback, expected.takeback);
      expect(prefs.autoQueen, expected.autoQueen);
      expect(prefs.autoThreefold, expected.autoThreefold);
      expect(prefs.moretime, expected.moretime);
      expect(prefs.clockTenths, expected.clockTenths);
      expect(prefs.clockSound.value, isFalse);
      expect(prefs.submitMove.choices, {SubmitMoveChoice.rapid, SubmitMoveChoice.blitz});
      expect(prefs.follow.value, isFalse);
      expect(prefs.challenge, expected.challenge);
      expect(prefs.message, expected.message);

      final stored = testBinding.sharedPreferences.getString(PrefCategory.account.storageKey);
      expect(stored, isNotNull);
      final decoded = AccountPrefState.fromJson(jsonDecode(stored!) as Map<String, dynamic>);
      expect(decoded.zenMode, Zen.gameAuto);
      expect(decoded.pieceNotation, PieceNotation.letter);
      expect(decoded.showRatings, ShowRatings.no);
      expect(decoded.takeback, Takeback.never);
      expect(decoded.autoQueen, AutoQueen.always);
      expect(decoded.autoThreefold, AutoThreefold.time);
      expect(decoded.moretime, Moretime.casual);
      expect(decoded.clockTenths, ClockTenths.always);
      expect(decoded.clockSound.value, isFalse);
      expect(decoded.submitMove.choices, {SubmitMoveChoice.rapid, SubmitMoveChoice.blitz});
      expect(decoded.follow.value, isFalse);
      expect(decoded.challenge, Challenge.always);
      expect(decoded.message, Message.friends);
    });

    // A setter is awaited by its caller, so "await" has to mean the value is
    // both written and published; a fire-and-forget write would lose the change
    // on a slow store or a crash between the call and the flush.
    test('a local setter has written and published before it returns', () async {
      final binding = TestLichessBinding.ensureInitialized();
      final previous = binding.sharedPreferences;
      binding.sharedPreferences = _SlowSharedPreferences();
      addTearDown(() => binding.sharedPreferences = previous);

      final container = await makeContainer();
      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);

      final stored = binding.sharedPreferences.getString(PrefCategory.account.storageKey);
      expect(stored, isNotNull);
      expect(
        AccountPrefState.fromJson(jsonDecode(stored!) as Map<String, dynamic>).showRatings,
        ShowRatings.no,
      );
      expect(container.read(accountPreferencesProvider).value?.showRatings, ShowRatings.no);
    });

    test('the corrupt payload itself is quoted in the report', () async {
      final binding = TestLichessBinding.ensureInitialized();
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: 'not valid json {"marker":"PAYLOAD-MARKER"}',
      });

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      final container = await makeContainer();
      await container.read(accountPreferencesProvider.future);

      final report = records.where((r) => r.level >= Level.SEVERE).single;
      expect(
        report.message,
        contains('PAYLOAD-MARKER'),
        reason: 'the shape of the damaged payload is the only diagnostic the user has',
      );
    });

    test('a corrupt payload at the summariser limit is quoted whole', () async {
      final binding = TestLichessBinding.ensureInitialized();
      final payload = _corruptPayload(200);
      await binding.setInitialSharedPreferencesValues({PrefCategory.account.storageKey: payload});

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      final container = await makeContainer();
      await container.read(accountPreferencesProvider.future);

      final report = records.where((r) => r.level >= Level.SEVERE).single;
      expect(report.message, contains(payload));
      expect(report.message, isNot(contains('…')));
    });

    test('a long corrupt payload is truncated with its original length', () async {
      final binding = TestLichessBinding.ensureInitialized();
      final payload = _corruptPayload(250, tail: 'TAIL-MARKER');
      await binding.setInitialSharedPreferencesValues({PrefCategory.account.storageKey: payload});

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      final container = await makeContainer();
      await container.read(accountPreferencesProvider.future);

      final report = records.where((r) => r.level >= Level.SEVERE).single;
      expect(report.message, contains(payload.substring(0, 200)));
      expect(report.message, contains('… (250 chars)'));
      expect(
        report.message,
        isNot(contains('TAIL-MARKER')),
        reason: 'the log keeps a bounded prefix, not the whole payload',
      );
    });

    test('local settings feed public preference providers', () async {
      final container = await makeContainer();

      await container.read(accountPreferencesProvider.notifier).setShowRatings(ShowRatings.no);
      await container
          .read(accountPreferencesProvider.notifier)
          .setPieceNotation(PieceNotation.letter);
      await container
          .read(accountPreferencesProvider.notifier)
          .setClockSound(const BooleanPref(false));
      await container.read(accountPreferencesProvider.notifier).setClockTenths(ClockTenths.always);

      expect(await container.read(showRatingsPrefProvider.future), ShowRatings.no);
      expect(await container.read(pieceNotationProvider.future), PieceNotation.letter);
      expect(await container.read(clockSoundProvider.future), isFalse);
      expect(await container.read(clockTenthsProvider.future), ClockTenths.always);
    });
  });

  group('AccountPreferences when signed in', () {
    test('fetches preferences from the server', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/account/preferences') {
          return mockResponse(prefsResponse(), 200);
        }
        return mockResponse('', 404);
      });

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs.autoQueen, AutoQueen.premove);
      expect(prefs.challenge, Challenge.registered);
      expect(prefs.showRatings, ShowRatings.yes);
    });

    test('falls back to defaults when the server request fails', () async {
      final mockClient = MockClient((request) => mockResponse('', 500));

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });

    test('setting a preference posts it to the server and refetches', () async {
      final requests = <http.Request>[];
      var storedZen = 0;
      final mockClient = MockClient((request) {
        if (request.method == 'GET' && request.url.path == '/api/account/preferences') {
          return mockResponse(prefsResponse(zen: storedZen), 200);
        }
        if (request.method == 'POST' && request.url.path == '/api/account/preferences/zen') {
          requests.add(request);
          // The server now reflects the new value on the next fetch.
          storedZen = Zen.yes.value;
          return mockResponse('{"ok": true}', 200);
        }
        return mockResponse('', 404);
      });

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final initial = await container.read(accountPreferencesProvider.future);
      expect(initial.zenMode, Zen.no);

      await container.read(accountPreferencesProvider.notifier).setZen(Zen.yes);

      // The setter posted the form-encoded value to the server.
      expect(requests, hasLength(1));
      expect(requests.single.bodyFields['zen'], Zen.yes.toFormData);

      // invalidateSelf triggered a refetch that now returns the updated value.
      final updated = await container.read(accountPreferencesProvider.future);
      expect(updated.zenMode, Zen.yes);
    });

    // The server keys are not the property names (`ratings`, not `showRatings`),
    // and a wrong key silently writes a different preference. Every setter is
    // checked so none can inherit a neighbour's key.
    test('every signed-in setter posts its value under its own key', () async {
      final posts = <String, Map<String, String>>{};
      final mockClient = MockClient((request) {
        if (request.method == 'GET') {
          return mockResponse(prefsResponse(), 200);
        }
        posts[request.url.pathSegments.last] = request.bodyFields;
        return mockResponse('{"ok": true}', 200);
      });

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final notifier = container.read(accountPreferencesProvider.notifier);
      await container.read(accountPreferencesProvider.future);

      await notifier.setZen(Zen.gameAuto);
      await notifier.setPieceNotation(PieceNotation.letter);
      await notifier.setShowRatings(ShowRatings.no);
      await notifier.setTakeback(Takeback.never);
      await notifier.setAutoQueen(AutoQueen.always);
      await notifier.setAutoThreefold(AutoThreefold.time);
      await notifier.setMoretime(Moretime.casual);
      await notifier.setClockTenths(ClockTenths.always);
      await notifier.setClockSound(const BooleanPref(false));
      await notifier.setSubmitMove(SubmitMove({SubmitMoveChoice.rapid}));
      await notifier.setFollow(const BooleanPref(false));
      await notifier.setChallenge(Challenge.always);
      await notifier.setMessage(Message.friends);

      expect(posts['zen'], {'zen': Zen.gameAuto.toFormData});
      expect(posts['pieceNotation'], {'pieceNotation': PieceNotation.letter.toFormData});
      expect(posts['ratings'], {'ratings': ShowRatings.no.toFormData});
      expect(posts['takeback'], {'takeback': Takeback.never.toFormData});
      expect(posts['autoQueen'], {'autoQueen': AutoQueen.always.toFormData});
      expect(posts['autoThreefold'], {'autoThreefold': AutoThreefold.time.toFormData});
      expect(posts['moretime'], {'moretime': Moretime.casual.toFormData});
      expect(posts['clockTenths'], {'clockTenths': ClockTenths.always.toFormData});
      expect(posts['clockSound'], {'clockSound': const BooleanPref(false).toFormData});
      expect(posts['submitMove'], {
        'submitMove': SubmitMove({SubmitMoveChoice.rapid}).toFormData,
      });
      expect(posts['follow'], {'follow': const BooleanPref(false).toFormData});
      expect(posts['challenge'], {'challenge': Challenge.always.toFormData});
      expect(posts['message'], {'message': Message.friends.toFormData});
      expect(posts, hasLength(13));
    });

    // The class documents "If the server returns an error, default values are
    // returned". A signed-in user's device may still hold whatever a previous
    // anonymous session wrote, and that must not become the account's settings.
    test('a server failure falls back to defaults, not to stale local values', () async {
      final binding = TestLichessBinding.ensureInitialized();
      await binding.setInitialSharedPreferencesValues({
        PrefCategory.account.storageKey: jsonEncode(
          defaultAccountPreferences.copyWith(showRatings: ShowRatings.no).toJson(),
        ),
      });

      final mockClient = MockClient((request) => mockResponse('', 500));

      final container = await makeContainer(
        authUser: fakeAuthUser,
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
        },
      );

      final prefs = await container.read(accountPreferencesProvider.future);

      expect(prefs, defaultAccountPreferences);
    });
  });
}

/// A JSON payload of [length] characters that `jsonDecode` cannot parse: the
/// string literal is never closed. [tail] marks content past the prefix.
String _corruptPayload(int length, {String tail = ''}) {
  const head = '{"broken": "';
  return head + 'x' * (length - head.length - tail.length) + tail;
}

/// A preferences store whose writes take a turn of the event loop, so a setter
/// that forgets to await its own write becomes observable.
class _SlowSharedPreferences extends FakeSharedPreferences {
  @override
  Future<bool> setString(String key, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return await super.setString(key, value);
  }
}
