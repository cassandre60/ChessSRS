// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import '../../binding.dart';

class _TestValue implements Serializable {
  _TestValue(this.marker);

  final String marker;

  @override
  Map<String, dynamic> toJson() => {'marker': marker};
}

class _TestStorage extends Notifier<_TestValue> with PreferencesStorage<_TestValue> {
  @override
  _TestValue fromJson(Map<String, dynamic> json) => _TestValue(json['marker'] as String);

  @override
  _TestValue get defaults => _TestValue('default');

  @override
  PrefCategory get prefCategory => PrefCategory.board;

  @override
  _TestValue build() => fetch();
}

final _testStorageProvider = NotifierProvider<_TestStorage, _TestValue>(_TestStorage.new);

class _TestSessionStorage extends Notifier<_TestValue> with SessionPreferencesStorage<_TestValue> {
  @override
  _TestValue fromJson(Map<String, dynamic> json) => _TestValue(json['marker'] as String);

  @override
  _TestValue defaults({LightUser? user}) => _TestValue('default');

  @override
  PrefCategory get prefCategory => PrefCategory.board;

  @override
  _TestValue build() => fetch();
}

final _testSessionStorageProvider = NotifierProvider<_TestSessionStorage, _TestValue>(
  _TestSessionStorage.new,
);

class _AnonAuth extends AuthController {
  @override
  AuthUser? build() => null;
}

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  group('PreferencesStorage corrupted blob backup (DATA-FIX-31)', () {
    test('corrupted prefs blob is backed up before defaults are returned', () async {
      const garbage = '{not valid json';
      final prefs = TestLichessBinding.instance.sharedPreferences;
      await prefs.setString(PrefCategory.board.storageKey, garbage);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(_testStorageProvider).marker, 'default');
      expect(prefs.getString('${PrefCategory.board.storageKey}.corrupt-backup'), garbage);
    });

    test('session prefs blob is backed up under the resolved key', () async {
      const garbage = '{also not valid json';
      final prefs = TestLichessBinding.instance.sharedPreferences;
      const resolvedKey = '${'preferences.board'}.**anon**';
      await prefs.setString(resolvedKey, garbage);

      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(_AnonAuth.new)],
      );
      addTearDown(container.dispose);

      expect(container.read(_testSessionStorageProvider).marker, 'default');
      expect(prefs.getString('$resolvedKey.corrupt-backup'), garbage);
    });

    test('corruption is logged at SEVERE with the parse error', () async {
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(() async {
        await subscription.cancel();
        Logger.root.level = Level.INFO;
      });

      final prefs = TestLichessBinding.instance.sharedPreferences;
      await prefs.setString(PrefCategory.board.storageKey, '{broken');

      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(_testStorageProvider);

      final severe = records.where(
        (r) => r.loggerName == 'PreferencesStorage' && r.level == Level.SEVERE,
      );
      expect(severe, isNotEmpty, reason: 'losing all user settings must log at SEVERE');
      expect(severe.first.message, contains(PrefCategory.board.storageKey));
      expect(severe.first.message, contains('corrupt-backup'));
    });

    test('valid prefs still parse and write no backup', () async {
      final prefs = TestLichessBinding.instance.sharedPreferences;
      await prefs.setString(PrefCategory.board.storageKey, '{"marker":"custom"}');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(_testStorageProvider).marker, 'custom');
      expect(prefs.getString('${PrefCategory.board.storageKey}.corrupt-backup'), isNull);
    });

    test('missing prefs return defaults and write no backup', () {
      final prefs = TestLichessBinding.instance.sharedPreferences;

      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(_testStorageProvider).marker, 'default');
      expect(prefs.getString('${PrefCategory.board.storageKey}.corrupt-backup'), isNull);
    });
  });
}
