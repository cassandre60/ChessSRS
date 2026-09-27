import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/tab_navigation.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/account/account_menu.dart';
import 'package:chess_srs/src/view/account/profile_screen.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_screen.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:chess_srs/src/widgets/misc.dart';
import 'package:chess_srs/src/widgets/platform.dart';
import 'package:chess_srs/src/widgets/settings.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class MoreTabScreen extends ConsumerWidget {
  const MoreTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) {
          ref.read(currentBottomTabProvider.notifier).state = BottomTab.review;
        }
      },
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          title: Theme.of(context).platform == TargetPlatform.iOS
              ? AppBarLichessTitle(
                  iconSize: Theme.of(context).textTheme.headlineSmall?.fontSize ?? 24,
                )
              : const AppBarLichessTitle(),
          centerTitle: false,
          titleTextStyle: Theme.of(context).platform == TargetPlatform.iOS
              ? Theme.of(context).textTheme.headlineSmall
              : null,
          actions: const [AccountMenuButton()],
        ),
        body: const _Body(),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);

    return ListTileTheme.merge(
      iconColor: Theme.of(context).colorScheme.primary,
      child: ListView(
        controller: moreScrollController,
        children: [
          ListSection(
            header: SettingsSectionTitle(context.l10n.tools),
            hasLeading: true,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.importPgn),
                onTap: () => Navigator.of(context).push(ImportPgnScreen.buildRoute()),
              ),
              ListTile(
                leading: const Icon(Icons.biotech_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.analysis),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  AnalysisScreen.buildRoute(
                    const AnalysisOptions.standalone(variant: Variant.standard),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.openingExplorer),
                enabled: isOnline,
                onTap: () {
                  Navigator.of(context, rootNavigator: true).push(
                    OpeningExplorerScreen.buildRoute(
                      const AnalysisOptions.pgn(
                        id: StringId('standalone_opening_explorer'),
                        orientation: Side.white,
                        pgn: '',
                        isComputerAnalysisAllowed: false,
                        variant: Variant.standard,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                trailing: Theme.of(context).platform == TargetPlatform.iOS
                    ? const CupertinoListTileChevron()
                    : null,
                title: Text(context.l10n.boardEditor),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  BoardEditorScreen.buildRoute((
                    initialVariant: Variant.standard,
                    initialFen: null,
                    initialOrientation: null,
                  )),
                ),
              ),
            ],
          ),
          const _AccountSection(),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isDeviceOnlineProvider);
    final authUser = ref.watch(authControllerProvider);
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final user = authUser?.user;

    return ListSection(
      header: user != null ? SettingsSectionTitle(user.name) : null,
      hasLeading: true,
      children: [
        if (user != null)
          ListTile(
            leading: const Icon(Icons.person_outlined),
            title: Text(context.l10n.profile),
            trailing: isIOS ? const CupertinoListTileChevron() : null,
            enabled: isOnline,
            onTap: () {
              ref.invalidate(accountProvider);
              Navigator.of(context).push(ProfileScreen.buildRoute());
            },
          ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(context.l10n.settingsSettings),
          trailing: isIOS ? const CupertinoListTileChevron() : null,
          onTap: () {
            Navigator.of(context).push(SrsSettingsScreen.buildRoute());
          },
        ),
      ],
    );
  }
}
