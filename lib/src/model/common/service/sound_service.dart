import 'dart:convert';

import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException, PlatformException, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sound_effect/sound_effect.dart';

/// Maximum number of concurrent sounds that can be played.
const _kMaxConcurrentStreams = 2;

final _soundEffectPlugin = SoundEffect();

final _logger = Logger('SoundService');

// Must match name of files in assets/sounds/standard
enum Sound {
  move,
  capture,
  explosion,
  lowTime,
  dong,
  error,
  confirmation,
  puzzleStormEnd,
  clock,
  berserk,
}

/// The design's own feedback set, per `design/docs/02-tokens.md` §6.
///
/// Deliberately not a [SoundTheme] and not part of [Sound]. The Lichess themes ship as
/// .mp3/.aifc inside their own folders and are resolved by name with a fallback to
/// `standard/`; these ship as .wav under `assets/sounds/diagram/`. Folding them into
/// [Sound] would make every theme switch try to resolve `wrong` and `done`, neither of
/// which exists in any Lichess theme, and the loader's fallback would hand the plugin a
/// path that is not there.
enum ReviewSound {
  /// ~120 ms soft knock. A piece landing, whether the user's or the repertoire's.
  move,

  /// ~300 ms, two lower knocks. A move that was rejected.
  wrong,

  /// ~950 ms, two gentle sine notes. Reaching "Nothing due".
  done,
}

/// Where [ReviewSound] assets live. Unlike the themes this is a fixed path with a fixed
/// extension — the files are .wav, which both SoundPool and AVAudioPlayer read natively,
/// so there is nothing to transcode and no per-platform variant to pick.
const _kReviewSoundPath = 'assets/sounds/diagram';

/// A provider for [SoundService].
final soundServiceProvider = Provider<SoundService>((Ref ref) {
  final service = SoundService(ref);
  ref.onDispose(() => service.release());
  return service;
}, name: 'SoundServiceProvider');

final _extension = defaultTargetPlatform == TargetPlatform.iOS ? 'aifc' : 'mp3';

const Set<Sound> _emtpySet = {};

/// Loads all sounds of the given [SoundTheme].
Future<void> _loadAllSounds(SoundTheme soundTheme, {Set<Sound> excluded = _emtpySet}) async {
  await Future.wait(
    Sound.values.where((s) => !excluded.contains(s)).map((sound) => _loadSound(soundTheme, sound)),
  );
}

/// Loads a single sound from the given [SoundTheme].
Future<void> _loadSound(SoundTheme theme, Sound sound) async {
  final themePath = 'assets/sounds/${theme.name}';
  const standardPath = 'assets/sounds/standard';
  final soundId = sound.name;
  final file = '$soundId.$_extension';
  String fullPath = '$themePath/$file';
  // If the sound file is not found in the theme, fallback to the standard theme.
  try {
    await rootBundle.load(fullPath);
  } catch (_) {
    fullPath = '$standardPath/$file';
  }
  await _soundEffectPlugin.load(soundId, fullPath);
}

/// Preloads the design's own review sounds.
Future<void> _loadAllReviewSounds() async {
  await Future.wait(ReviewSound.values.map(_loadReviewSound));
}

Future<void> _loadReviewSound(ReviewSound sound) async {
  await _soundEffectPlugin.load(sound.name, '$_kReviewSoundPath/${sound.name}.wav');
}

/// Service to play game sounds.
class SoundService {
  SoundService(this._ref);

  final Ref _ref;

  /// Initialize the sound service.
  ///
  /// This will load the sounds from assets and make them ready to be played.
  /// This should be called once when the app starts.
  static Future<void> initialize() async {
    try {
      final stored = LichessBinding.instance.sharedPreferences.getString(
        PrefCategory.general.storageKey,
      );
      final theme =
          (stored != null
                  ? GeneralPrefs.fromJson(jsonDecode(stored) as Map<String, dynamic>)
                  : GeneralPrefs.defaults)
              .soundTheme;
      await _soundEffectPlugin.initialize(maxStreams: _kMaxConcurrentStreams);
      await _loadAllSounds(theme);
      await _loadAllReviewSounds();
    } catch (e, st) {
      _logger.warning('Failed to initialize sound service:', e, st);
    }
  }

  /// Play the given sound if sound is enabled.
  Future<void> play(Sound sound, {double volume = 1.0}) async {
    assert((volume >= 0.0) && (volume <= 1.0));
    final isEnabled = _ref.read(generalPreferencesProvider).isSoundEnabled;
    final finalVolume = _ref.read(generalPreferencesProvider).masterVolume * volume;
    if (!isEnabled || finalVolume == 0.0) {
      return;
    }
    try {
      await _soundEffectPlugin.play(sound.name, volume: finalVolume);
    } on PlatformException catch (_) {
      // The sound plugin has no implementation on some platforms (e.g. Linux
      // desktop); sounds are optional feedback and must never crash the app.
    } on MissingPluginException catch (_) {
      // Same as above: missing plugin implementation for this platform.
    }
  }

  /// Play the capture sound for the given chess [variant].
  Future<void> playCaptureSound(Variant variant, {double volume = 1.0}) async {
    await play(variant == Variant.atomic ? Sound.explosion : Sound.capture, volume: volume);
  }

  /// Play one of the design's own review sounds, if sound is enabled.
  ///
  /// Honours the same Sound setting and master volume as [play] — `design/docs/02-tokens.md`
  /// §6 puts them under the one "Sound" switch, described in the design as "Soft move and
  /// correction sounds."
  Future<void> playReviewSound(ReviewSound sound, {double volume = 1.0}) async {
    assert((volume >= 0.0) && (volume <= 1.0));
    final prefs = _ref.read(generalPreferencesProvider);
    if (!prefs.isSoundEnabled) return;
    final finalVolume = prefs.masterVolume * volume;
    if (finalVolume == 0.0) return;
    try {
      await _soundEffectPlugin.play(sound.name, volume: finalVolume);
    } on PlatformException catch (_) {
      // The sound plugin has no implementation on some platforms (e.g. Linux
      // desktop); sounds are optional feedback and must never crash the app.
    } on MissingPluginException catch (_) {
      // Same as above: missing plugin implementation for this platform.
    }
  }

  /// Change the sound theme and optionally play a move sound.
  ///
  /// This will release the previous sounds and load the new ones.
  ///
  /// If [playSound] is true, a move sound will be played.
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {
    await _soundEffectPlugin.release();
    await _soundEffectPlugin.initialize(maxStreams: _kMaxConcurrentStreams);
    await _loadSound(theme, Sound.move);
    if (playSound) {
      play(Sound.move);
    }
    await _loadAllSounds(theme, excluded: {Sound.move});
    // release() above drops every loaded sound, theme and review alike, so the review
    // set has to come back too or the feedback goes silent after any theme change.
    await _loadAllReviewSounds();
  }

  Future<void> release() async {
    await _soundEffectPlugin.release();
  }
}
