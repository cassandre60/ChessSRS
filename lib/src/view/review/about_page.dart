// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show AppBar, Scaffold;
import 'package:url_launcher/url_launcher.dart';

/// Dedicated About page (matches `about` in `chesssrs-design-demo.html`).
///
/// Diagram `.pg` layout: wordmark, title, version lede, source links,
/// and attribution rows for the fork's GPL-3.0 dependencies.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const lichessMobileUrl = 'https://github.com/lichess-org/mobile';
  static const chessSrsUrl = 'https://github.com/mansourvery-hub/chess-repertoire-srs';

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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final version = ref.watch(preloadedDataProvider).whenData((data) => data.packageInfo.version).value;

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.ink, elevation: 0),
      body: SingleChildScrollView(
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
                Wrap(
                  spacing: 22,
                  runSpacing: 8,
                  children: [
                    _Link(
                      label: 'Lichess Mobile source',
                      uri: Uri.parse(lichessMobileUrl),
                    ),
                    _Link(label: 'ChessSRS source', uri: Uri.parse(chessSrsUrl)),
                  ],
                ),
                const SizedBox(height: 30),
                for (final (name, licence) in _attributions) ...[
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
    );
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
