import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/view/game/game_list_tile.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

LightExportedGame makeGame({
  required GameSource source,
  required Player white,
  Player? black,
  String? importDate,
}) {
  return LightExportedGame(
    id: const GameId('qVChCOTc'),
    source: source,
    importDate: importDate,
    rated: false,
    speed: Speed.classical,
    perf: Perf.classical,
    createdAt: DateTime(2021, 1, 1),
    lastMoveAt: DateTime(2021, 1, 1),
    status: GameStatus.mate,
    white: white,
    black: black ?? const Player(name: 'Spassky, Boris'),
    variant: Variant.standard,
    winner: Side.white,
  );
}

void main() {
  group('GameListTile', () {
    testWidgets('imported game shows both players and no result icon', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListTile(
            item: (
              game: makeGame(
                source: GameSource.import,
                white: const Player(name: 'Fischer, Robert J.'),
                importDate: '1972.08.31',
              ),
              pov: Side.black,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Fischer, Robert J. vs Spassky, Boris'), findsOneWidget);
      expect(find.text('August 31, 1972'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.plus_square_fill), findsNothing);
      expect(find.byIcon(CupertinoIcons.minus_square_fill), findsNothing);
    });

    testWidgets('regular game shows the opponent and the result icon', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListTile(
            item: (
              game: makeGame(
                source: GameSource.lobby,
                white: const Player(
                  user: LightUser(id: UserId('white'), name: 'White'),
                ),
                black: const Player(
                  user: LightUser(id: UserId('black'), name: 'Black'),
                ),
              ),
              pov: Side.white,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Black'), findsOneWidget);
      expect(find.text('White vs Black'), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
      expect(find.byIcon(CupertinoIcons.plus_square_fill), findsOneWidget);
    });

    // SPEC INV-062.
    testWidgets('the result mark stays beside the row on a narrow viewport', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;

      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListTile(
            item: (
              game: makeGame(
                source: GameSource.lobby,
                white: const Player(
                  user: LightUser(id: UserId('white'), name: 'White'),
                ),
                black: const Player(
                  user: LightUser(id: UserId('black'), name: 'Black'),
                ),
              ),
              pov: Side.white,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      // `SrsSettingsRow` drops its control under the label below 520px, which is right for a
      // switch and wrong for a two-glyph mark: the mark would stop annotating the row and start
      // reading as a second line of it. 360px is the narrowest phone worth laying out for.
      final name = tester.getCenter(find.text('Black'));
      final mark = tester.getCenter(find.byIcon(CupertinoIcons.plus_square_fill));
      expect(
        (mark.dy - name.dy).abs(),
        lessThan(20),
        reason: 'the result mark dropped below the opponent name instead of sitting beside it',
      );

      // And the row's own target clears the platform minimum rather than only the mark's.
      expect(tester.getSize(find.byType(SrsSettingsRow)).height, greaterThanOrEqualTo(48));
    });

    // SPEC INV-062.
    testWidgets('a long press still opens the row actions', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: GameListTile(
            item: (
              game: makeGame(
                source: GameSource.lobby,
                white: const Player(
                  user: LightUser(id: UserId('white'), name: 'White'),
                ),
                black: const Player(
                  user: LightUser(id: UserId('black'), name: 'Black'),
                ),
              ),
              pov: Side.white,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(BottomSheet), findsNothing);
      await tester.longPress(find.byType(SrsSettingsRow));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });
}
