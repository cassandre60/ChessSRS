import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/utils/chessboard.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class PieceSetScreen extends ConsumerStatefulWidget {
  const PieceSetScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const PieceSetScreen());
  }

  @override
  ConsumerState<PieceSetScreen> createState() => _PieceSetScreenState();
}

class _PieceSetScreenState extends ConsumerState<PieceSetScreen> {
  bool isLoading = false;

  Future<void> onChanged(PieceSet? value) async {
    if (value != null) {
      ref.read(boardPreferencesProvider.notifier).setPieceSet(value);
      setState(() {
        isLoading = true;
      });
      try {
        await precachePieceImages(value);
      } finally {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    }
  }

  List<AssetImage> getPieceImages(PieceSet set) {
    return [
      set.assets[PieceKind.whiteKing]!,
      set.assets[PieceKind.blackQueen]!,
      set.assets[PieceKind.whiteRook]!,
      set.assets[PieceKind.blackBishop]!,
      set.assets[PieceKind.whiteKnight]!,
      set.assets[PieceKind.blackPawn]!,
    ];
  }

  // Only show curated piece sets — the full Lichess set is kept in the enum
  // for data compatibility but hidden from the picker.
  static const _allowedPieceSets = {
    PieceSet.cburnett,
    PieceSet.merida,
    PieceSet.pirouetti,
    PieceSet.alpha,
    PieceSet.mpchess,
  };

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final c = context.srs;
    final visibleSets = PieceSet.values.where((s) => _allowedPieceSets.contains(s)).toList();

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.pieceSet,
              onBack: () => Navigator.of(context).maybePop(),
              // Precaching a piece set takes a moment, so the head carries the progress rather
              // than the screen showing a spinner with nothing to attach it to.
              trailing: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                itemCount: visibleSets.length,
                itemBuilder: (context, index) {
                  final pieceSet = visibleSets[index];
                  return SrsSettingsRow(
                    label: pieceSet.label,
                    selected: boardPrefs.pieceSet == pieceSet,
                    enabled: !isLoading,
                    onTap: () => onChanged(pieceSet),
                    preview: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 264),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: c.hairline)),
                          child: Stack(
                            children: [
                              BrightnessHueFilter(
                                brightness: boardPrefs.brightness,
                                hue: boardPrefs.hue,
                                child: boardPrefs.boardTheme.thumbnail,
                              ),
                              Row(
                                children: [
                                  for (final img in getPieceImages(pieceSet))
                                    Image(image: img, height: 44),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
