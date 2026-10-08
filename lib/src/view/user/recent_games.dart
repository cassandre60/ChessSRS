import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game_history.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/game/game_list_tile.dart';
import 'package:chess_srs/src/view/user/game_history_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A widget that show a list of recent games.
///
/// The [user] should be provided only if the games are for a specific user. If the
/// games are for the current logged in user, the [user] should be null.
class RecentGamesWidget extends ConsumerWidget {
  const RecentGamesWidget({
    required this.recentGames,
    required this.user,
    required this.nbOfGames,
    this.maxGamesToShow = kNumberOfRecentGames,
    super.key,
  });

  final LightUser? user;
  final AsyncValue<IList<LightExportedGameWithPov>> recentGames;
  final int nbOfGames;
  final int maxGamesToShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);

    return recentGames.when(
      data: (data) {
        if (data.isEmpty) {
          return const SizedBox.shrink();
        }
        final list = data.take(maxGamesToShow);
        final c = context.srs;
        // A tappable group header rather than `ListSection.onHeaderTap`: the words name
        // where a tap goes, so the control is the words themselves.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SrsPressable(
              onPressed: nbOfGames > list.length
                  ? () => Navigator.of(
                      context,
                    ).push(GameHistoryScreen.buildRoute(user: user, isOnline: isOnline))
                  : null,
              semanticLabel: context.l10n.recentGames,
              builder: (_, hover, _) => Padding(
                padding: EdgeInsets.only(top: 18, bottom: 6, left: hover ? 2 : 0),
                child: Text(context.l10n.recentGames, style: SrsText.groupTitle(c.ink3)),
              ),
            ),
            for (final item in list) GameListTile(item: item),
          ],
        );
      },
      error: (error, stackTrace) {
        debugPrint('SEVERE: [RecentGames] could not load recent games: $error\n$stackTrace');
        return const Padding(
          padding: Styles.bodySectionPadding,
          child: Text('Could not load recent games.'),
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SrsGroupHeader('Recent games'),
          for (var i = 0; i < 10; i++)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: SrsRowRule()),
        ],
      ),
    );
  }
}
