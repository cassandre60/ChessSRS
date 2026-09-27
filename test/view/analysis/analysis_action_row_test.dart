import 'dart:convert';

import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The action row must stay at two lines on a phone.
///
/// It was three. Its items totalled 669px plus 90px of spacing against 360px available, so at
/// 390px wide it wrapped to three lines and left the tab viewport 93px for a 143px move-times
/// chart. The chart then overflowed its clipping viewport and taps below the fold were dropped
/// without dispatch -- the same failure mode as the viewport crush in #15, still live for
/// archived games while the standalone screen sat at a comfortable 174px.
///
/// Three lines measures ~138px tall, two ~92px, so the height distinguishes them.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  for (final entry in {
    'archived game': const AnalysisOptions.archivedGame(
      orientation: Side.white,
      gameId: GameId('xze7RH66'),
    ),
    'standalone board': const AnalysisOptions.standalone(variant: Variant.standard),
  }.entries) {
    testWidgets('${entry.key}: action row is at most two lines at 390px', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockClient = MockClient((request) {
        if (request.url.path == '/game/export/xze7RH66') {
          return mockResponse(
            jsonEncode({
              'id': 'xze7RH66',
              'rated': true,
              'source': 'lobby',
              'variant': 'standard',
              'speed': 'bullet',
              'perf': 'bullet',
              'createdAt': 1706185945680,
              'lastMoveAt': 1706186170504,
              'status': 'resign',
              'players': {
                'white': {
                  'user': {'name': 'veloce', 'id': 'veloce'},
                  'rating': 1789,
                },
                'black': {
                  'user': {'name': 'chabrot', 'id': 'chabrot'},
                  'rating': 1810,
                },
              },
              'winner': 'white',
              'moves': 'e4 e5 Nf3 Nc6 Bb5 a6',
              'clock': {'initial': 120, 'increment': 1, 'totalTime': 160},
            }),
            200,
          );
        }
        return mockResponse('', 404);
      });

      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: AnalysisScreen(options: entry.value),
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (ref) => FakeHttpClientFactory(() => mockClient),
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      // The action row is the only Wrap in the bottom third of the screen.
      final candidates = <Rect>[];
      for (final element in find.byType(Wrap).evaluate()) {
        final ro = element.renderObject;
        if (ro is RenderBox && ro.hasSize) {
          candidates.add(ro.localToGlobal(Offset.zero) & ro.size);
        }
      }
      expect(candidates, isNotEmpty, reason: 'action row must be present');
      final row = candidates.reduce((a, b) => a.bottom > b.bottom ? a : b);

      expect(
        row.height,
        lessThan(120),
        reason:
            'action row is ${row.height.toStringAsFixed(0)}px tall at y=${row.top.toStringAsFixed(0)}'
            ' -- three lines means the tab viewport is crushed again',
      );
    });
  }
}
