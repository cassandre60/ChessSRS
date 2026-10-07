import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/game/game_filter.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/view/user/game_history_screen.dart';
import 'package:chess_srs/src/view/user/perf_cards.dart';
import 'package:chess_srs/src/view/user/recent_games.dart';
import 'package:chess_srs/src/view/user/user_activity.dart';
import 'package:chess_srs/src/view/user/user_profile.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/haptic_refresh_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' show ClientException;
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

final _userScreenDataProvider = FutureProvider.autoDispose.family<UserScreenData, UserId>(
  (ref, id) => ref.read(userRepositoryProvider).getUserScreenData(id),
  name: 'UserScreenDataProvider',
);

class UserScreen extends ConsumerWidget {
  const UserScreen({required this.user, super.key});

  final LightUser user;

  static Route<dynamic> buildRoute(LightUser user) {
    return buildScreenRoute(screen: UserScreen(user: user));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userScreenData = ref.watch(_userScreenDataProvider(user.id));
    final updatedLightUser = userScreenData.maybeWhen(
      data: (data) => data.user.lightUser.copyWith(isOnline: data.isOnline),
      orElse: () => null,
    );
    return Scaffold(
      backgroundColor: context.srs.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: updatedLightUser?.name ?? user.name,
              onBack: () => Navigator.of(context).maybePop(),
              trailing: SrsIconButton(
                icon: Icons.ios_share,
                tooltip: 'Share profile',
                onPressed: () =>
                    launchShareDialog(context, ShareParams(uri: lichessUri('/@/${user.name}'))),
              ),
            ),
            Expanded(child: _body(context, userScreenData, ref)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AsyncValue<UserScreenData> userScreenData, WidgetRef ref) {
    return userScreenData.when(
      data: (data) => _UserProfileListView(
        data,
        onRefresh: () => ref.refresh(_userScreenDataProvider(user.id).future),
      ),
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, _) {
        if (error is ClientException && error.message.contains('404')) {
          return Center(
            child: Text(
              textAlign: TextAlign.center,
              context.l10n.usernameNotFound(user.name),
              style: Styles.bold,
            ),
          );
        }
        return FullScreenRetryRequest(
          onRetry: () => ref.invalidate(_userScreenDataProvider(user.id)),
        );
      },
    );
  }
}

class _UserProfileListView extends ConsumerWidget {
  const _UserProfileListView(this.data, {required this.onRefresh});

  final UserScreenData data;
  final RefreshCallback onRefresh;

  String _scoreDisplay(double score) {
    final integerPart = score.truncate();
    final decimalPart = score - integerPart;

    return integerPart == 0 && decimalPart == 0.5
        ? '½'
        : '$integerPart${decimalPart == 0.5 ? '½' : ''}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserScreenData(:user, :recentGames, :activity, :isPlayingLive, :crosstable) = data;

    final isOnline = ref.watch(isDeviceOnlineProvider);
    final nbOfGames = user.count?.all ?? 0;
    final authUser = ref.watch(authControllerProvider);

    if (user.disabled == true) {
      return Center(child: Text(context.l10n.settingsThisAccountIsClosed, style: Styles.bold));
    }

    return HapticRefreshIndicator(
      edgeOffset: Theme.of(context).platform == TargetPlatform.iOS
          ? MediaQuery.paddingOf(context).top + kToolbarHeight
          : 0.0,
      onRefresh: onRefresh,
      child: ListView(
        children: [
          UserProfileWidget(user: user),
          PerfCards(user: user, isMe: false),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (authUser != null && crosstable != null && (crosstable.nbGames) > 0) ...[
                () {
                  final crosstableData = crosstable;
                  final currentUserScore = crosstableData.users[authUser.user.id] ?? 0;
                  final otherUserScore = crosstableData.users[user.id] ?? 0;

                  return ListTile(
                    title: Text(
                      context.l10n.yourScore(
                        '${_scoreDisplay(currentUserScore)} - ${_scoreDisplay(otherUserScore)}',
                      ),
                    ),
                    leading: const Icon(Icons.scoreboard_outlined),
                    onTap: () {
                      Navigator.of(context).push(
                        GameHistoryScreen.buildRoute(
                          user: authUser.user,
                          isOnline: isOnline,
                          gameFilter: GameFilterState(opponent: user),
                        ),
                      );
                    },
                  );
                }(),
              ],
              if (authUser != null) ...[
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(context.l10n.reportXToModerators(user.username)),
                  onTap: () {
                    launchUrl(
                      lichessUri('/report', {'username': user.id, 'login': authUser.user.id}),
                    );
                  },
                ),
              ],
            ],
          ),
          UserActivityWidget(activity: AsyncData(activity), user: user.lightUser),
          RecentGamesWidget(
            recentGames: AsyncData(recentGames),
            nbOfGames: nbOfGames,
            user: user.lightUser,
          ),
        ],
      ),
    );
  }
}
