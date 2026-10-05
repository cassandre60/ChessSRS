import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class BoardChoiceScreen extends StatelessWidget {
  const BoardChoiceScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BoardChoiceScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.srs.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.mobileBoardSettings,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const Expanded(child: _Body()),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardTheme = ref.watch(boardPreferencesProvider.select((p) => p.boardTheme));

    // Only show the curated board themes — the full Lichess set is kept in the
    // enum for data compatibility but hidden from the picker. To restore a
    // theme, add it to this list.
    const allowedBoardThemes = {
      BoardTheme.diagram,
      BoardTheme.wood,
      BoardTheme.paper,
      BoardTheme.slate,
    };

    final choices = BoardTheme.values.where((t) => allowedBoardThemes.contains(t)).toList();

    void onChanged(BoardTheme? value) =>
        ref.read(boardPreferencesProvider.notifier).setBoardTheme(value ?? BoardTheme.brown);

    final c = context.srs;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      itemCount: choices.length,
      itemBuilder: (context, index) {
        final t = choices[index];
        return SrsSettingsRow(
          label: t.label,
          selected: t == boardTheme,
          onTap: () => onChanged(t),
          preview: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 264),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.all(color: c.hairline)),
                child: t.thumbnail,
              ),
            ),
          ),
        );
      },
    );
  }
}
