import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/http_network_image.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/lichess_assets.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/account/profile_screen.dart';
import 'package:chess_srs/src/view/auth/sign_in_error.dart';
import 'package:chess_srs/src/view/auth/sign_in_options.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Account menu screen opened by [AccountMenuButton].
///
/// On Android it is pushed as a full-screen page. On iOS it is presented
/// inside a [CupertinoSheetRoute] with nested navigation.
class AccountMenuScreen extends ConsumerStatefulWidget {
  const AccountMenuScreen({super.key});

  static Route<void> buildRoute(BuildContext context) {
    // One route. This branched on platform to present a Cupertino sheet on iOS and a
    // slide-in page elsewhere, so the same screen arrived two different ways; the Srs head
    // closes the same way on both.
    return buildScreenRoute(screen: const AccountMenuScreen());
  }

  @override
  ConsumerState<AccountMenuScreen> createState() => _AccountMenuScreenState();
}

class _AccountMenuScreenState extends ConsumerState<AccountMenuScreen> with WidgetsBindingObserver {
  bool _errorLoadingFlair = false;
  bool _pendingKidModeRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingKidModeRefresh) {
      _pendingKidModeRefresh = false;
      ref.invalidate(accountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(defaultClientProvider);
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final signInState = ref.watch(signInMutation);
    final signOutState = ref.watch(signOutMutation);
    final c = context.srs;

    ref.listen(signInMutation, (_, next) => showSignInErrorSnackBar(context, next));
    final account = ref.watch(accountProvider);
    final authUser = ref.watch(authControllerProvider);
    final kidMode = account.value?.kid ?? false;
    final LightUser? user = account.value?.lightUser ?? authUser?.user;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.mobileAccount,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  if (user != null) ...[
                    const SrsGroupHeader('Account'),
                    SrsSettingsRow(
                      label: user.name,
                      labelWidget: Text(user.name, style: SrsText.settingLabel(c.ink)),
                      leading: switch (account) {
                        AsyncData(:final value) =>
                          value == null
                              ? const Icon(Icons.account_circle_outlined, size: 30)
                              : CircleAvatar(
                                  radius: 20,
                                  foregroundImage: value.flair != null && !_errorLoadingFlair
                                      ? HttpNetworkImage(lichessFlairSrc(value.flair!), client)
                                      : null,
                                  onForegroundImageError: value.flair != null
                                      ? (error, _) => setState(() => _errorLoadingFlair = true)
                                      : null,
                                  backgroundColor: value.flair == null || _errorLoadingFlair
                                      ? null
                                      : c.surface,
                                  child: value.flair == null || _errorLoadingFlair
                                      ? Text(value.initials)
                                      : null,
                                ),
                        _ => const Icon(Icons.account_circle_outlined, size: 30),
                      },
                      enabled: isOnline,
                      onTap: () {
                        ref.invalidate(accountProvider);
                        Navigator.of(context).push(ProfileScreen.buildRoute());
                      },
                    ),
                    if (kidMode)
                      SrsSettingsRow(
                        label: context.l10n.kidModeIsEnabled,
                        selected: true,
                        onTap: () {
                          _pendingKidModeRefresh = true;
                          launchUrl(lichessUri('/account/kid'));
                        },
                      ),
                  ] else ...[
                    const SizedBox(height: 24),
                    Center(
                      child: SrsPillButton(
                        label: context.l10n.signIn,
                        onPressed: isOnline
                            ? switch (signInState) {
                                MutationPending() => null,
                                _ => () => showSignInOptions(context, ref),
                              }
                            : null,
                      ),
                    ),
                  ],
                  if (user != null) ...[
                    const SrsGroupHeader('Session'),
                    if (signOutState case MutationPending())
                      const SrsSettingsRow(
                        label: 'Logging out',
                        control: ButtonLoadingIndicator(),
                        enabled: false,
                      )
                    else
                      SrsSettingsRow(
                        label: context.l10n.logOut,
                        destructive: true,
                        enabled: isOnline,
                        onTap: () => _showSignOutConfirmDialog(context, ref),
                      ),
                  ],
                  const SocketPingRatingListTile(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSignOutConfirmDialog(BuildContext context, WidgetRef ref) {
    // One path, not a platform branch. This had its own copy of the branch: a `CupertinoActionSheet`
    // on iOS carrying a single `Log out` action and no cancel row, and a Material `AlertDialog`
    // elsewhere. So signing out asked a different question per device, and on iOS dismissing the
    // sheet was the only way to decline. `showConfirmDialog` is the shared helper and is now a
    // Diagram `SrsDialog` on every platform.
    showConfirmDialog<void>(
      context,
      title: Text(context.l10n.logOut),
      isDestructiveAction: true,
      onConfirm: () async {
        await signOutMutation.run(ref, (tsx) async {
          await tsx.get(authControllerProvider.notifier).signOut();
        });
      },
    );
  }
}

/// Avatar button that opens the account menu.
///
/// On Android opens [AccountMenuScreen] as a full-screen page sliding from the
/// right. On iOS opens the same screen inside a [CupertinoSheetRoute] with
/// nested navigation.
class AccountMenuButton extends ConsumerStatefulWidget {
  const AccountMenuButton({super.key});

  @override
  ConsumerState<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends ConsumerState<AccountMenuButton> {
  bool _errorLoadingFlair = false;

  static const _materialAnonIconSize = 30.0;
  static const _cupertinoAnonIconSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final client = ref.watch(defaultClientProvider);

    void openMenu() {
      Navigator.of(context).push(AccountMenuScreen.buildRoute(context));
    }

    return switch (account) {
      AsyncData(:final value) => IconButton(
        tooltip: value == null ? context.l10n.signIn : value.username,
        icon: value == null
            ? Icon(
                Icons.account_circle_outlined,
                size: Theme.of(context).platform == TargetPlatform.iOS
                    ? _cupertinoAnonIconSize
                    : _materialAnonIconSize,
              )
            : CircleAvatar(
                radius:
                    (Theme.of(context).platform == TargetPlatform.iOS
                        ? _cupertinoAnonIconSize / 2
                        : _materialAnonIconSize / 2) +
                    1,
                foregroundImage: value.flair != null && !_errorLoadingFlair
                    ? HttpNetworkImage(lichessFlairSrc(value.flair!), client)
                    : null,
                onForegroundImageError: value.flair != null
                    ? (error, _) => setState(() => _errorLoadingFlair = true)
                    : null,
                backgroundColor: value.flair == null || _errorLoadingFlair
                    ? null
                    : ColorScheme.of(context).surfaceContainer,
                child: value.flair == null || _errorLoadingFlair ? Text(value.initials) : null,
              ),
        onPressed: openMenu,
      ),
      _ => IconButton(
        icon: Icon(
          Icons.account_circle_outlined,
          size: Theme.of(context).platform == TargetPlatform.iOS
              ? _cupertinoAnonIconSize
              : _materialAnonIconSize,
        ),
        tooltip: context.l10n.signIn,
        onPressed: openMenu,
      ),
    };
  }
}

/// About screen with links to various lichess resources and legal information.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static Route<void> buildRoute() {
    return buildScreenRoute(screen: const AboutScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = ref.read(preloadedDataProvider).requireValue.packageInfo;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.about)),
      body: ListView(
        children: [
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outlined),
                title: Text(context.l10n.aboutX('Lichess')),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/about'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: Text(context.l10n.mobileFeedbackButton),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/contact'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(context.l10n.termsOfService),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/terms-of-service'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(context.l10n.privacyPolicy),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/privacy'));
                },
              ),
            ],
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Symbols.database),
                title: Text(context.l10n.database),
                onTap: () {
                  launchUrl(Uri.parse('https://database.lichess.org'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: Text(context.l10n.sourceCode),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/source'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(context.l10n.contribute),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/help/contribute'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.star_border_outlined),
                title: Text(context.l10n.thankYou),
                onTap: () {
                  launchUrl(Uri.parse('https://lichess.org/thanks'));
                },
              ),
            ],
          ),
          ListSection(
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.copyright_outlined),
                title: const Text('View licences'),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'ChessSRS',
                    applicationVersion: packageInfo.version,
                    applicationIcon: Image.asset(
                      'assets/brand/icon-1024.png',
                      width: 48,
                      height: 48,
                    ),
                  );
                },
              ),
            ],
          ),
          Padding(
            padding: Styles.bodySectionPadding,
            child: Text('v${packageInfo.version}', style: TextTheme.of(context).bodySmall),
          ),
        ],
      ),
    );
  }
}
