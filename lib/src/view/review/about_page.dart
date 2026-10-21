// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/updater/app_update.dart';
import 'package:chess_srs/src/model/updater/app_update_service.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator, LinearProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Scaffold;
import 'package:url_launcher/url_launcher.dart';

/// Dedicated About page (matches `about` in `chesssrs-design-demo.html`).
///
/// Diagram `.pg` layout: wordmark, title, version lede, source links,
/// and attribution rows for the fork's GPL-3.0 dependencies.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  static const lichessMobileUrl = 'https://github.com/lichess-org/mobile';
  static const chessSrsUrl = 'https://github.com/cassandre60/ChessSRS';

  static const _attributions = [
    ('Lichess Mobile', 'GPL-3.0'),
    ('chessground', 'GPL-3.0'),
    ('dartchess', 'GPL-3.0'),
    ('Instrument Sans', 'SIL Open Font Licence 1.1'),
    ('Newsreader', 'SIL Open Font Licence 1.1'),
  ];

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const AboutPage());
  }

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appUpdateProvider.notifier).checkForUpdate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final version = ref
        .watch(preloadedDataProvider)
        .whenData((data) => data.packageInfo.version)
        .value;
    final updateState = ref.watch(appUpdateProvider);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(label: 'About', onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 660),
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 56),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SrsLogoMark(size: 22),
                            const SizedBox(width: 10),
                            Text(
                              'ChessSRS',
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: c.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text('About', style: SrsText.display(40, c.ink)),
                        const SizedBox(height: 14),
                        Text(
                          'Version ${version ?? '…'}. Based on Lichess Mobile (GPL-3.0).',
                          style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink2),
                        ),
                        const SizedBox(height: 18),
                        _UpdateCard(updateState: updateState),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 22,
                          runSpacing: 8,
                          children: [
                            _Link(
                              label: 'Lichess Mobile source',
                              uri: Uri.parse(AboutPage.lichessMobileUrl),
                            ),
                            _Link(label: 'ChessSRS source', uri: Uri.parse(AboutPage.chessSrsUrl)),
                          ],
                        ),
                        const SizedBox(height: 30),
                        for (final (name, licence) in AboutPage._attributions) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairlineSoft)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name, style: SrsText.settingLabel(c.ink)),
                                Text(
                                  licence,
                                  style: TextStyle(
                                    fontFamily: SrsText.ui,
                                    fontSize: 14,
                                    color: c.ink2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.updateState});

  final AppUpdateState updateState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final notifier = ref.read(appUpdateProvider.notifier);

    switch (updateState.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.hairlineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
              ),
              const SizedBox(width: 10),
              Text(
                'Checking for updates…',
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
            ],
          ),
        );

      case UpdateStatus.upToDate:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ChessSRS is up to date.',
              style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
            ),
            const SizedBox(width: 12),
            SrsPressable(
              onPressed: () => notifier.checkForUpdate(force: true),
              semanticLabel: 'Check for updates again',
              radius: 6,
              builder: (_, hovered, _) => Text(
                'Check again',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 14,
                  color: hovered ? c.ink : c.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        );

      case UpdateStatus.error:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.hairlineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not check for updates.',
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
              const SizedBox(width: 12),
              SrsPressable(
                onPressed: () => notifier.checkForUpdate(force: true),
                semanticLabel: 'Retry update check',
                radius: 6,
                builder: (_, hovered, _) => Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 14,
                    color: hovered ? c.ink : c.accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        );

      case UpdateStatus.available:
        final info = updateState.releaseInfo;
        final isAndroid = Platform.isAndroid;
        final sizeMb = info?.apkSize != null
            ? ' (${(info!.apkSize! / (1024 * 1024)).toStringAsFixed(1)} MB)'
            : '';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Update available: ${info?.tagName ?? ''}',
                    style: TextStyle(
                      fontFamily: SrsText.ui,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  if (sizeMb.isNotEmpty)
                    Text(
                      sizeMb,
                      style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'A new version is available to install.',
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isAndroid)
                    SrsPillButton(
                      label: 'Install update',
                      selected: true,
                      onPressed: () => notifier.downloadAndInstall(),
                    ),
                  SrsTextButton(
                    label: isAndroid ? 'Download via browser' : 'Download update',
                    onPressed: () => notifier.openInBrowser(),
                  ),
                ],
              ),
            ],
          ),
        );

      case UpdateStatus.downloading:
        final progress = (updateState.downloadProgress * 100).toInt();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.hairlineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Downloading update… $progress%',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: updateState.downloadProgress > 0 ? updateState.downloadProgress : null,
                color: c.accent,
                backgroundColor: c.hairline,
              ),
              const SizedBox(height: 12),
              SrsTextButton(
                label: 'Download via browser instead',
                onPressed: () => notifier.openInBrowser(),
              ),
            ],
          ),
        );

      case UpdateStatus.readyToInstall:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.page,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Update downloaded',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ready to install via Android package installer.',
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SrsPillButton(
                    label: 'Install now',
                    selected: true,
                    onPressed: () => notifier.installDownloadedApk(),
                  ),
                  SrsTextButton(
                    label: 'Download via browser',
                    onPressed: () => notifier.openInBrowser(),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.uri});

  final String label;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: () => launchUrl(uri),
      semanticLabel: label,
      radius: 6,
      builder: (_, hovered, _) => Text(
        label,
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 15,
          color: hovered ? c.ink : c.ink2,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
