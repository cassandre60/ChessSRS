import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/localizations.dart';
import 'package:chess_srs/src/navigation.dart';
import 'package:chess_srs/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';

/// Provider for the [QuickActionService].
final quickActionServiceProvider = Provider<QuickActionService>((Ref ref) {
  return QuickActionService(ref);
});

class QuickActionService {
  QuickActionService(this.ref);

  final Ref ref;
  AppLocalizations get l10n => ref.read(localizationsProvider).strings;

  final QuickActions quickActions = const QuickActions();

  TargetPlatform get platform => defaultTargetPlatform;

  void start() {
    // Quick actions are only supported on Android and iOS; the plugin has no
    // implementation on desktop targets.
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return;
    }

    quickActions.initialize((String shortcutType) {
      final context = ref.read(rootNavigatorKeyProvider).currentContext;
      if (context == null || !context.mounted) return;

      if (shortcutType == 'play_computer') {
        Navigator.of(context, rootNavigator: true).push(OfflineComputerGameScreen.buildRoute());
      }
    });
    setQuickActions();
  }

  void setQuickActions() {
    quickActions.setShortcutItems(<ShortcutItem>[
      ShortcutItem(
        type: 'play_computer',
        localizedTitle: l10n.playAgainstComputer,
        icon: platform == TargetPlatform.iOS ? 'ComputerIcon' : 'computer',
      ),
    ]);
  }
}
