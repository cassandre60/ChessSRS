import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/explorer/explorer_view.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class OpeningNameHeader extends StatelessWidget {
  const OpeningNameHeader({required this.opening, super.key});

  final Opening opening;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: kExplorerTableRowPadding,
      decoration: BoxDecoration(color: ColorScheme.of(context).surfaceDim),
      child: GestureDetector(
        onTap: opening.name == context.l10n.startPosition
            ? null
            : () => launchUrl(Uri.parse('https://lichess.org/opening/${opening.name}')),
        child: Row(
          children: [
            if (opening.name != context.l10n.startPosition) ...[
              Icon(Icons.open_in_browser_outlined, color: ColorScheme.of(context).onSurface),
              const SizedBox(width: 6.0),
            ],
            Expanded(
              child: Text(
                opening.eco.isNotEmpty ? '${opening.eco} ${opening.name}' : opening.name,
                style: TextStyle(
                  color: ColorScheme.of(context).onSurface,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A centered, padded informational message shown in place of explorer or tablebase results
/// (e.g. max depth reached, offline, no data).
class ExplorerMessage extends StatelessWidget {
  const ExplorerMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

/// Table of moves for the opening explorer.
class OpeningExplorerMoveTable extends ConsumerWidget {
  const OpeningExplorerMoveTable({
    required this.moves,
    required this.whiteWins,
    required this.draws,
    required this.blackWins,
    this.onMoveSelected,
    this.isIndexing = false,
  }) : _isLoading = false;

  const OpeningExplorerMoveTable.loading()
    : _isLoading = true,
      moves = const IListConst([]),
      whiteWins = 0,
      draws = 0,
      blackWins = 0,
      isIndexing = false,
      onMoveSelected = null;

  final IList<OpeningMove> moves;
  final int whiteWins;
  final int draws;
  final int blackWins;
  final void Function(Move)? onMoveSelected;
  final bool isIndexing;

  final bool _isLoading;

  String formatNum(int num) => NumberFormat.decimalPatternDigits().format(num);

  static const columnWidths = {
    0: FractionColumnWidth(0.15),
    1: FractionColumnWidth(0.35),
    2: FractionColumnWidth(0.50),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_isLoading) {
      return loadingTable;
    }

    final c = context.srs;
    final pieceNotation = ref
        .watch(pieceNotationProvider)
        .maybeWhen(data: (value) => value, orElse: () => defaultAccountPreferences.pieceNotation);
    final games = whiteWins + draws + blackWins;

    // Demo `.xh` header: quiet labels, hairline below.
    final headerStyle = SrsText.groupTitle(c.ink3);
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(context.l10n.move, style: headerStyle)),
          Expanded(child: Text(context.l10n.games, style: headerStyle)),
          SizedBox(
            width: 128,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.whiteDrawBlack,
                    style: headerStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isIndexing) const IndexingIndicator(),
              ],
            ),
          ),
        ],
      ),
    );

    Widget moveSan(OpeningMove move) {
      if (pieceNotation == PieceNotation.symbol) {
        return Text(move.san, style: const TextStyle(fontFamily: 'ChessFont'));
      }
      return SrsSan(
        move.san,
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: c.ink,
          fontFeatures: SrsText.tabular,
        ),
      );
    }

    Widget resultBar({required int white, required int draws, required int black}) {
      // Reuses the memory-bar shapes for White/Draws/Black (demo legend),
      // with a corrected screen-reader label.
      return Semantics(
        label: 'White $white, draws $draws, Black $black',
        child: ExcludeSemantics(
          child: SrsMemoryBar(
            retained: white,
            learning: draws,
            fresh: black,
            height: 6,
            gap: 2,
            radius: 1,
            width: 128,
          ),
        ),
      );
    }

    Widget rowButton({
      required VoidCallback? onTap,
      required String semanticLabel,
      required List<Widget> cells,
    }) {
      return SrsPressable(
        onPressed: onTap,
        semanticLabel: semanticLabel,
        radius: 8,
        builder: (_, hover, _) => Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: hover ? c.hairlineSoft : const Color(0x00000000),
            border: Border(bottom: BorderSide(color: c.hairline)),
          ),
          child: Row(
            children: [
              SizedBox(width: 64, child: cells[0]),
              Expanded(child: cells[1]),
              SizedBox(width: 128, child: cells[2]),
            ],
          ),
        ),
      );
    }

    final gamesStyle = TextStyle(
      fontFamily: SrsText.ui,
      fontSize: 14.5,
      color: c.ink,
      fontFeatures: SrsText.tabular,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        ...List.generate(moves.length, (int index) {
          final move = moves.get(index);
          final percentGames = ((move.games / games) * 100).round();
          return rowButton(
            onTap: onMoveSelected == null ? null : () => onMoveSelected!(Move.parse(move.uci)!),
            semanticLabel: '${move.san}, ${formatNum(move.games)} games',
            cells: [
              moveSan(move),
              Text('${formatNum(move.games)} ($percentGames%)', style: gamesStyle),
              resultBar(white: move.white, draws: move.draws, black: move.black),
            ],
          );
        }),
        if (moves.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                SizedBox(width: 64, child: Text('Total', style: SrsText.rowSub(c.ink3))),
                Expanded(child: Text('${formatNum(games)} (100%)', style: gamesStyle)),
                SizedBox(
                  width: 128,
                  child: resultBar(white: whiteWins, draws: draws, black: blackWins),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [Expanded(child: Text(context.l10n.noGameFound, style: gamesStyle))],
            ),
          ),
      ],
    );
  }

  static final loadingTable = Table(
    columnWidths: columnWidths,
    children: List.generate(
      10,
      (int index) => TableRow(
        children: [
          Padding(
            padding: kExplorerTableRowPadding,
            child: Container(
              height: 20,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Padding(
            padding: kExplorerTableRowPadding,
            child: Container(
              height: 20,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Padding(
            padding: kExplorerTableRowPadding,
            child: Container(
              height: 20,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class IndexingIndicator extends StatefulWidget {
  const IndexingIndicator();

  @override
  State<IndexingIndicator> createState() => _IndexingIndicatorState();
}

class _IndexingIndicatorState extends State<IndexingIndicator> with TickerProviderStateMixin {
  late AnimationController controller;

  @override
  void initState() {
    controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..addListener(() {
        setState(() {});
      });
    controller.repeat();
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12.0,
      height: 12.0,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        value: controller.value,
        // TODO: l10n
        semanticsLabel: 'Indexing',
      ),
    );
  }
}

class OpeningExplorerHeaderTile extends StatelessWidget {
  const OpeningExplorerHeaderTile({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: kExplorerTableRowPadding,
      decoration: BoxDecoration(color: ColorScheme.of(context).surfaceDim),
      child: child,
    );
  }
}

/// A game tile for the opening explorer.
class OpeningExplorerGameTile extends ConsumerStatefulWidget {
  const OpeningExplorerGameTile({
    required this.pov,
    required this.game,
    required this.color,
    required this.ply,
    super.key,
  });

  final Side pov;
  final OpeningExplorerGame game;
  final Color color;
  final int ply;

  @override
  ConsumerState<OpeningExplorerGameTile> createState() => _OpeningExplorerGameTileState();
}

class _OpeningExplorerGameTileState extends ConsumerState<OpeningExplorerGameTile> {
  @override
  Widget build(BuildContext context) {
    const widthResultBox = 50.0;
    const paddingResultBox = EdgeInsets.all(5);

    return Container(
      padding: kExplorerTableRowPadding,
      color: widget.color,
      child: InkWell(
        onTap: () async {
          final client = ref.read(defaultClientProvider);
          await client.get(lichessUri('/import/master/${widget.game.id}/${widget.pov.name}'));
          if (!context.mounted) return;
          Navigator.of(context).push(
            AnalysisScreen.buildRoute(
              AnalysisOptions.archivedGame(
                orientation: widget.pov,
                gameId: widget.game.id,
                initialMoveCursor: widget.ply,
              ),
            ),
          );
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.game.white.rating.toString()),
                Text(widget.game.black.rating.toString()),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.game.white.name, overflow: TextOverflow.ellipsis),
                  Text(widget.game.black.name, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Row(
              children: [
                if (widget.game.winner == 'white')
                  Container(
                    width: widthResultBox,
                    padding: paddingResultBox,
                    decoration: BoxDecoration(
                      color: whiteBoxColor(context),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '1-0',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black),
                    ),
                  )
                else if (widget.game.winner == 'black')
                  Container(
                    width: widthResultBox,
                    padding: paddingResultBox,
                    decoration: BoxDecoration(
                      color: blackBoxColor(context),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '0-1',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                else
                  Container(
                    width: widthResultBox,
                    padding: paddingResultBox,
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '½-½',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                if (widget.game.month != null) ...[
                  const SizedBox(width: 10.0),
                  Text(
                    widget.game.month!,
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
                if (widget.game.speed != null) ...[
                  const SizedBox(width: 10.0),
                  Icon(widget.game.speed!.icon, size: 20),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
