import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:chess_srs/src/widgets/misc.dart';
import 'package:chess_srs/src/widgets/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountPreferencesScreen extends ConsumerStatefulWidget {
  const AccountPreferencesScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const AccountPreferencesScreen());
  }

  @override
  ConsumerState<AccountPreferencesScreen> createState() => _AccountPreferencesScreenState();
}

class _AccountPreferencesScreenState extends ConsumerState<AccountPreferencesScreen>
    with WidgetsBindingObserver {
  bool isLoading = false;
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

  Future<void> _setPref(Future<void> Function() f) async {
    setState(() {
      isLoading = true;
    });
    try {
      await f();
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountPrefs = ref.watch(accountPreferencesProvider);
    final authUser = ref.watch(authControllerProvider);
    final kidMode = ref.watch(kidModeProvider).value ?? false;

    final c = context.srs;
    final content = accountPrefs.when(
      data: (data) {
        if (authUser == null) {
          return Center(child: Text(context.l10n.mobileMustBeLoggedIn));
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
              child: Text(context.l10n.mobileAccountPreferencesHelp, style: SrsText.meta(c.ink2)),
            ),
            ListSection(
              header: const SrsGroupHeader('Display'),
              hasLeading: false,
              children: [
                SrsSettingsRow(
                  label: context.l10n.preferencesShowPlayerRatings,
                  help: context.l10n.preferencesExplainShowPlayerRatings,
                  value: data.showRatings.label(context.l10n),
                  onTap: () => showChoicePicker(
                    context,
                    choices: ShowRatings.values,
                    selectedItem: data.showRatings,
                    labelBuilder: (t) => Text(t.label(context.l10n)),
                    onSelectedItemChanged: (ShowRatings? value) {
                      _setPref(
                        () => ref
                            .read(accountPreferencesProvider.notifier)
                            .setShowRatings(value ?? data.showRatings),
                      );
                    },
                  ),
                ),
              ],
            ),
            ListSection(
              header: const SrsGroupHeader('Privacy'),
              hasLeading: false,
              children: [
                SrsSettingsRow(
                  label: context.l10n.letOtherPlayersFollowYou,
                  enabled: !isLoading,
                  control: SrsSwitch(
                    value: data.follow.value,
                    semanticLabel: context.l10n.letOtherPlayersFollowYou,
                    onChanged: isLoading
                        ? null
                        : (value) {
                            _setPref(
                              () => ref
                                  .read(accountPreferencesProvider.notifier)
                                  .setFollow(BooleanPref(value)),
                            );
                          },
                  ),
                ),
                SrsSettingsRow(
                  label: context.l10n.letOtherPlayersChallengeYou,
                  value: data.challenge.label(context.l10n),
                  enabled: !isLoading,
                  onTap: () {
                    showChoicePicker(
                      context,
                      choices: Challenge.values,
                      selectedItem: data.challenge,
                      labelBuilder: (t) => Text(t.label(context.l10n)),
                      onSelectedItemChanged: isLoading
                          ? null
                          : (Challenge? value) {
                              _setPref(
                                () => ref
                                    .read(accountPreferencesProvider.notifier)
                                    .setChallenge(value ?? data.challenge),
                              );
                            },
                    );
                  },
                ),
                SrsSettingsRow(
                  label: context.l10n.letOtherPlayersMessageYou,
                  value: data.message.label(context.l10n),
                  enabled: !isLoading,
                  onTap: () {
                    showChoicePicker(
                      context,
                      choices: Message.values,
                      selectedItem: data.message,
                      labelBuilder: (t) => Text(t.label(context.l10n)),
                      onSelectedItemChanged: isLoading
                          ? null
                          : (Message? value) {
                              _setPref(
                                () => ref
                                    .read(accountPreferencesProvider.notifier)
                                    .setMessage(value ?? data.message),
                              );
                            },
                    );
                  },
                ),
              ],
            ),
            ListSection(
              header: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsSectionTitle(context.l10n.kidMode),
                  Text(
                    context.l10n.kidModeExplanation,
                    maxLines: 5,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              hasLeading: true,
              children: [
                SrsSettingsRow(
                  label: kidMode ? context.l10n.disableKidMode : context.l10n.enableKidMode,
                  help: context.l10n.kidModeExplanation,
                  control: const OpenInNewIcon(),
                  onTap: () {
                    _pendingKidModeRefresh = true;
                    launchUrl(lichessUri('/account/kid'));
                  },
                ),
              ],
            ),
            ListSection(
              header: const SrsGroupHeader('Security'),
              hasLeading: true,
              children: [
                SrsSettingsRow(
                  label: context.l10n.changePassword,
                  control: const OpenInNewIcon(),
                  onTap: () => launchUrl(lichessUri('/account/passwd')),
                ),
                SrsSettingsRow(
                  label: context.l10n.tfaTwoFactorAuth,
                  control: const OpenInNewIcon(),
                  onTap: () => launchUrl(lichessUri('/account/twofactor')),
                ),
              ],
            ),
            ListSection(
              header: const SrsGroupHeader('Danger zone'),
              hasLeading: true,
              children: [
                // iOS deletes the account, everything else closes it. Kept as one row rather
                // than two near-identical branches of a tile.
                if (Theme.of(context).platform == TargetPlatform.iOS)
                  SrsSettingsRow(
                    label: 'Delete your account',
                    destructive: true,
                    control: const OpenInNewIcon(),
                    onTap: () => launchUrl(lichessUri('/account/delete')),
                  )
                else
                  SrsSettingsRow(
                    label: context.l10n.settingsCloseAccount,
                    destructive: true,
                    control: const OpenInNewIcon(),
                    onTap: () => launchUrl(lichessUri('/account/close')),
                  ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, _) {
        return FullScreenRetryRequest(onRetry: () => ref.invalidate(accountPreferencesProvider));
      },
    );

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.mobileAccountPreferences,
              onBack: () => Navigator.of(context).maybePop(),
              // The whole screen round-trips a preference to the account API, so the progress
              // belongs on the head rather than on one row.
              trailing: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
