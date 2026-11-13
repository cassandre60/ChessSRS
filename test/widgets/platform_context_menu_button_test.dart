import 'package:chess_srs/src/widgets/platform.dart';
import 'package:chess_srs/src/widgets/platform_context_menu_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test_helpers.dart';
import '../test_provider_scope.dart';

void main() {
  testWidgets('opens the menu and runs an action', variant: kPlatformVariant, (tester) async {
    var pressed = 0;

    final app = await makeTestProviderScopeApp(
      tester,
      home: PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('Title'),
          actions: [
            ContextMenuIconButton(
              icon: const Icon(Icons.more_horiz),
              semanticsLabel: 'Menu',
              actions: [
                ContextMenuAction(
                  icon: Icons.settings,
                  label: 'Settings',
                  onPressed: () => pressed++,
                ),
              ],
            ),
          ],
        ),
        body: const SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(app);

    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(pressed, 1);
    // ContextMenuAction.dismissOnPress defaults to true: the menu must close.
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('defaults to a non-compact icon button', variant: kPlatformVariant, (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('Title'),
          actions: [
            ContextMenuIconButton(
              icon: const Icon(Icons.more_horiz),
              semanticsLabel: 'Menu',
              actions: [
                ContextMenuAction(icon: Icons.settings, label: 'Settings', onPressed: () {}),
              ],
            ),
          ],
        ),
        body: const SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(app);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.iconSize, isNull);
    expect(button.style, isNull);
  });
}
