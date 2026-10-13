import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PreferencesStorage');

abstract class Serializable {
  Map<String, dynamic> toJson();
}

/// A preference category with its storage key
enum PrefCategory {
  general('preferences.general'),
  home('preferences.home'),
  board('preferences.board'),
  analysis('preferences.analysis'),
  study('preferences.study'),
  overTheBoard('preferences.overTheBoard'),
  challenge('preferences.challenge'),
  gameSetup('preferences.gameSetup'),
  gameSeeks('preferences.gameSeeks'),
  game('preferences.game'),
  coordinateTraining('preferences.coordinateTraining'),
  openingExplorer('preferences.opening_explorer'),
  gameHistory('preferences.gameHistory'),
  puzzle('preferences.puzzle'),
  engineEvaluation('preferences.engineEvaluation'),
  offlineComputerGame('preferences.offlineComputerGame'),
  account('preferences.account'),
  log('preferences.log');

  const PrefCategory(this.storageKey);

  final String storageKey;
}

/// A [Notifier] mixin to provide a way to store and retrieve preferences.
mixin PreferencesStorage<T extends Serializable> on Notifier<T> {
  T fromJson(Map<String, dynamic> json);
  T get defaults;

  PrefCategory get prefCategory;

  Future<void> save(T value) async {
    await LichessBinding.instance.sharedPreferences.setString(
      prefCategory.storageKey,
      jsonEncode(value.toJson()),
    );

    if (!ref.mounted) return;

    state = value;
  }

  T fetch() {
    final stored = LichessBinding.instance.sharedPreferences.getString(prefCategory.storageKey);
    if (stored == null) {
      return defaults;
    }
    try {
      return fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (e, st) {
      // Preserve the unparseable blob before it is lost: the next save overwrites the key,
      // destroying the evidence. The backup is never read by the app; it exists so a support
      // session can recover it via file access. Overwritten only if corruption recurs, which
      // is correct — the newest corruption is the relevant one.
      // Fire-and-forget: fetch is sync (called from build), and the app must still boot on
      // corrupted prefs even if the backup write itself were to fail.
      unawaited(
        LichessBinding.instance.sharedPreferences.setString(
          '${prefCategory.storageKey}.corrupt-backup',
          stored,
        ),
      );
      _logger.severe(
        'Preferences "${prefCategory.storageKey}" failed to parse (${e.runtimeType}); '
        'backed up to "${prefCategory.storageKey}.corrupt-backup" and reset to defaults',
        e,
        st,
      );
      return defaults;
    }
  }
}

/// A [Notifier] mixin to provide a way to store and retrieve preferences per authUser.
mixin SessionPreferencesStorage<T extends Serializable> on Notifier<T> {
  T fromJson(Map<String, dynamic> json);
  T defaults({LightUser? user});

  PrefCategory get prefCategory;

  Future<void> save(T value) async {
    final authUser = ref.read(authControllerProvider);
    await LichessBinding.instance.sharedPreferences.setString(
      key(prefCategory.storageKey, authUser),
      jsonEncode(value.toJson()),
    );

    if (!ref.mounted) return;

    state = value;
  }

  T fetch() {
    final authUser = ref.watch(authControllerProvider);
    final resolvedKey = key(prefCategory.storageKey, authUser);
    final stored = LichessBinding.instance.sharedPreferences.getString(resolvedKey);
    if (stored == null) {
      return defaults(user: authUser?.user);
    }
    try {
      return fromJson(jsonDecode(stored) as Map<String, dynamic>);
    } catch (e, st) {
      // Same backup contract as PreferencesStorage.fetch: preserve the blob under the resolved
      // (per-user) key before it is lost, fire-and-forget because fetch is sync.
      unawaited(
        LichessBinding.instance.sharedPreferences.setString('$resolvedKey.corrupt-backup', stored),
      );
      _logger.severe(
        'Preferences "$resolvedKey" failed to parse (${e.runtimeType}); '
        'backed up to "$resolvedKey.corrupt-backup" and reset to defaults',
        e,
        st,
      );
      return defaults(user: authUser?.user);
    }
  }

  static String key(String key, AuthUser? authUser) => '$key.${authUser?.user.id ?? '**anon**'}';
}
