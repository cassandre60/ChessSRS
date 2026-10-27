import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../binding.dart';
import '../../../test_container.dart';

class _FakeGeneralPreferencesNotifier extends GeneralPreferencesNotifier {
  _FakeGeneralPreferencesNotifier(this._initialState);
  final GeneralPrefs _initialState;

  @override
  GeneralPrefs build() => _initialState;
}

/// Stands in for the Linux audio backend (the platform under test here), so the
/// assertions can say what the service played instead of only that play()
/// completed. The process-wide default player is never touched.
class _RecordingLinuxPlayer implements LinuxSoundPlayer {
  final List<(String, double)> played = [];
  final List<(SoundTheme, String, String)> loaded = [];
  int releases = 0;

  @override
  void initialize() {}

  @override
  Future<void> load(SoundTheme theme, String soundId, String fullPath) async =>
      loaded.add((theme, soundId, fullPath));

  @override
  void play(String soundId, {double volume = 1.0}) => played.add((soundId, volume));

  @override
  void release() => releases++;
}

void main() {
  TestLichessBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('SoundService plays the requested sounds at the resolved volume when enabled', () async {
    final player = _RecordingLinuxPlayer();
    final container = await makeContainer(
      overrides: {
        generalPreferencesProvider: generalPreferencesProvider.overrideWith(
          () => _FakeGeneralPreferencesNotifier(
            GeneralPrefs.defaults.copyWith(isSoundEnabled: true, masterVolume: 0.8),
          ),
        ),
        soundServiceProvider: soundServiceProvider.overrideWith(
          (ref) => SoundService(ref, linuxPlayer: player),
        ),
      },
    );

    final soundService = container.read(soundServiceProvider);

    await soundService.play(Sound.move);
    await soundService.play(Sound.capture, volume: 0.5);

    expect(player.played.map((p) => p.$1), [
      'move',
      'capture',
    ], reason: 'both requests must reach the audio backend when sound is enabled');
    expect(player.played[0].$2, closeTo(0.8, 0.0001));
    expect(player.played[1].$2, closeTo(0.4, 0.0001));

    // Release does not throw.
    await soundService.release();
  });

  test('SoundService does not reach the audio backend when sound is disabled', () async {
    final player = _RecordingLinuxPlayer();
    final container = await makeContainer(
      overrides: {
        generalPreferencesProvider: generalPreferencesProvider.overrideWith(
          () => _FakeGeneralPreferencesNotifier(
            GeneralPrefs.defaults.copyWith(isSoundEnabled: false),
          ),
        ),
        soundServiceProvider: soundServiceProvider.overrideWith(
          (ref) => SoundService(ref, linuxPlayer: player),
        ),
      },
    );

    final soundService = container.read(soundServiceProvider);
    await soundService.play(Sound.move);

    expect(
      player.played,
      isEmpty,
      reason: 'a disabled request must be dropped before the backend, not merely completed',
    );
  });

  test('SoundService does not reach the audio backend at zero master volume', () async {
    final player = _RecordingLinuxPlayer();
    final container = await makeContainer(
      overrides: {
        generalPreferencesProvider: generalPreferencesProvider.overrideWith(
          () => _FakeGeneralPreferencesNotifier(
            GeneralPrefs.defaults.copyWith(isSoundEnabled: true, masterVolume: 0.0),
          ),
        ),
        soundServiceProvider: soundServiceProvider.overrideWith(
          (ref) => SoundService(ref, linuxPlayer: player),
        ),
      },
    );

    final soundService = container.read(soundServiceProvider);
    await soundService.play(Sound.move);

    expect(
      player.played,
      isEmpty,
      reason: 'a fully muted master must drop the request before the backend',
    );
  });

  test(
    'SoundService.changeTheme reloads every sound of the theme and plays nothing by default',
    () async {
      final player = _RecordingLinuxPlayer();
      final soundService = await _soundServiceWith(player);

      await soundService.changeTheme(SoundTheme.standard);

      expect(
        player.loaded.map((load) => load.$2).toSet(),
        Sound.values.map((sound) => sound.name).toSet(),
        reason: 'a theme change must load every sound the service can play',
      );
      expect(
        player.loaded.map((load) => load.$3),
        everyElement(allOf(startsWith('assets/sounds/standard/'), endsWith('.mp3'))),
        reason: 'Linux resolves mp3 assets for every sound of the requested theme',
      );
      expect(
        player.releases,
        1,
        reason: 'the previous theme must be released on the Linux backend',
      );
      expect(
        player.played,
        isEmpty,
        reason: 'changeTheme must not play a preview unless playSound is requested',
      );
    },
  );

  test('SoundService.changeTheme plays the move sound only when asked', () async {
    final player = _RecordingLinuxPlayer();
    final soundService = await _soundServiceWith(player);

    await soundService.changeTheme(SoundTheme.standard, playSound: true);

    expect(player.played.map((p) => p.$1), [
      'move',
    ], reason: 'a requested preview is exactly one move sound');
  });

  test('SoundService.playCaptureSound maps the atomic variant to the explosion sound', () async {
    final player = _RecordingLinuxPlayer();
    final soundService = await _soundServiceWith(player);

    await soundService.playCaptureSound(Variant.atomic);
    await soundService.playCaptureSound(Variant.standard);
    await soundService.playCaptureSound(Variant.crazyhouse);

    expect(player.played.map((p) => p.$1), [
      'explosion',
      'capture',
      'capture',
    ], reason: 'only atomic captures explode; every other variant uses the capture sound');
  });

  test(
    'SoundService.play accepts the inclusive volume bounds and rejects out-of-range values',
    () async {
      final player = _RecordingLinuxPlayer();
      final soundService = await _soundServiceWith(player);

      // Zero is a legitimate per-request volume: it is dropped by the resolved
      // volume guard, not by the bounds assertion.
      await soundService.play(Sound.move, volume: 0.0);
      expect(player.played, isEmpty, reason: 'a zero request volume resolves to silence');

      await expectLater(soundService.play(Sound.move, volume: 1.0), completes);
      expect(player.played.single.$1, 'move', reason: 'the upper bound is inclusive');

      await expectLater(
        soundService.play(Sound.move, volume: 1.5),
        throwsA(isA<AssertionError>()),
        reason: 'the service must reject a volume above 1.0 instead of amplifying past it',
      );
      await expectLater(
        soundService.play(Sound.move, volume: -0.1),
        throwsA(isA<AssertionError>()),
        reason: 'the service must reject a negative volume instead of muting silently',
      );
    },
  );

  test('SoundService.release releases the Linux backend', () async {
    final player = _RecordingLinuxPlayer();
    final soundService = await _soundServiceWith(player);

    await soundService.release();

    expect(player.releases, 1, reason: 'release must reach the Linux backend');
  });
}

Future<SoundService> _soundServiceWith(_RecordingLinuxPlayer player) {
  return makeContainer(
    overrides: {
      generalPreferencesProvider: generalPreferencesProvider.overrideWith(
        () => _FakeGeneralPreferencesNotifier(GeneralPrefs.defaults),
      ),
      soundServiceProvider: soundServiceProvider.overrideWith(
        (ref) => SoundService(ref, linuxPlayer: player),
      ),
    },
  ).then((container) => container.read(soundServiceProvider));
}
