import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/game/game_history.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/view/account/edit_profile_screen.dart';
import 'package:chess_srs/src/view/account/game_bookmarks_screen.dart';
import 'package:chess_srs/src/view/user/perf_cards.dart';
import 'package:chess_srs/src/view/user/recent_games.dart';
import 'package:chess_srs/src/view/user/user_activity.dart';
import 'package:chess_srs/src/view/user/user_profile.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/haptic_refresh_indicator.dart';
import 'package:chess_srs/src/widgets/shimmer.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const ProfileScreen());
  }

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

final _accountActivityProvider = FutureProvider.autoDispose<IList<UserActivity>>((ref) {
  final authUser = ref.watch(authControllerProvider);
  if (authUser == null) return IList();
  return ref.read(userRepositoryProvider).getActivity(authUser.user.id);
}, name: 'userActivityProvider');

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.mobileAccount,
              onBack: () => Navigator.of(context).maybePop(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SrsIconButton(
                    icon: Icons.edit,
                    tooltip: context.l10n.editProfile,
                    onPressed: () => Navigator.of(context).push(EditProfileScreen.buildRoute()),
                  ),
                  if (account.value case final user?) ...[
                    const SizedBox(width: 4),
                    SrsIconButton(
                      icon: Icons.ios_share,
                      tooltip: 'Share profile',
                      onPressed: () => launchShareDialog(
                        context,
                        ShareParams(uri: lichessUri('/@/${user.username}')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: _body(account, ref, c)),
          ],
        ),
      ),
    );
  }

  Widget _body(AsyncValue<User?> account, WidgetRef ref, SrsColors c) {
    return account.when(
      data: (user) {
        if (user == null) {
          return Center(child: Text(context.l10n.mobileMustBeLoggedIn));
        }
        final activity = ref.watch(_accountActivityProvider);
        final recentGames = ref.watch(myRecentGamesProvider);
        final nbOfGames = ref.watch(userNumberOfGamesProvider(null)).value ?? 0;
        return HapticRefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: () => Future.wait([
            ref.refresh(accountProvider.future),
            ref.refresh(_accountActivityProvider.future),
            ref.refresh(myRecentGamesProvider.future),
          ]),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              UserProfileWidget(user: user),
              const AccountPerfCards(),
              if (user.count != null && user.count!.bookmark > 0) ...[
                const SrsGroupHeader('Saved'),
                SrsSettingsRow(
                  label: context.l10n.nbBookmarks(user.count!.bookmark),
                  onTap: () => Navigator.of(
                    context,
                  ).push(GameBookmarksScreen.buildRoute(nbBookmarks: user.count!.bookmark)),
                ),
              ],
              UserActivityWidget(activity: activity, user: user.lightUser),
              RecentGamesWidget(recentGames: recentGames, nbOfGames: nbOfGames, user: null),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (error, _) {
        return FullScreenRetryRequest(onRetry: () => ref.invalidate(accountProvider));
      },
    );
  }
}

class AccountPerfCards extends ConsumerWidget {
  const AccountPerfCards({this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return account.when(
      data: (user) {
        if (user != null) {
          return PerfCards(user: user, isMe: true, padding: padding);
        } else {
          return const SizedBox.shrink();
        }
      },
      loading: () => Shimmer(
        child: Padding(
          padding: padding ?? Styles.bodySectionPadding,
          child: SizedBox(
            height: 106,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) => ShimmerLoading(
                isLoading: true,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}
