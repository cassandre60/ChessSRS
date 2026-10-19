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

  @override
  void initialize() {}

  @override
  Future<void> load(SoundTheme theme, String soundId, String fullPath) async {}

  @override
  void play(String soundId, {double volume = 1.0}) => played.add((soundId, volume));

  @override
  void release() {}
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
}
