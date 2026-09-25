import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider for [MoveFeedbackService].
final moveFeedbackServiceProvider = Provider<MoveFeedbackService>((Ref ref) {
  final soundService = ref.watch(soundServiceProvider);
  return MoveFeedbackService(soundService, ref);
}, name: 'MoveFeedbackServiceProvider');

class MoveFeedbackService {
  MoveFeedbackService(this._soundService, this._ref);

  final SoundService _soundService;
  final Ref _ref;

  void moveFeedback({bool check = false}) {
    _soundService.play(Sound.move);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  void captureFeedback(Variant variant, {bool check = false}) {
    _soundService.playCaptureSound(variant);

    if (_ref.read(boardPreferencesProvider).hapticFeedback) {
      if (check) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  /// A move was rejected: the two lower knocks from `design/docs/02-tokens.md` §6.
  ///
  /// The review flow was silent here before. Nothing else in the app plays on a rejected
  /// move — [Sound.error] is declared but has no call site anywhere — so this is the only
  /// signal the user gets that the move was not the repertoire's.
  Future<void> wrongFeedback() => _soundService.playReviewSound(ReviewSound.wrong);

  /// The session ran out: the two gentle notes from `design/docs/02-tokens.md` §6.
  Future<void> doneFeedback() => _soundService.playReviewSound(ReviewSound.done);
}
