import 'package:chess_srs/src/widgets/platform_alert_dialog.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('PlatformDialogAction', () {
    testWidgets('builds a TextButton on Android', (tester) async {
      var pressed = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: PlatformDialogAction(
              onPressed: () => pressed++,
              child: const Text('OK'),
            ),
          ),
        ),
      );

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(CupertinoDialogAction), findsNothing);
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pump();

      expect(pressed, 1);
    });

    testWidgets('builds a CupertinoDialogAction on iOS with flags', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) => Theme(
              data: Theme.of(context).copyWith(platform: TargetPlatform.iOS),
              child: const CupertinoPageScaffold(
                child: Center(
                  child: PlatformDialogAction(
                    onPressed: null,
                    cupertinoIsDefaultAction: true,
                    cupertinoIsDestructiveAction: true,
                    child: Text('Delete'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CupertinoDialogAction), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);

      final action = tester.widget<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(action.isDefaultAction, isTrue);
      expect(action.isDestructiveAction, isTrue);
      expect(find.text('Delete'), findsOneWidget);
    });
  });
}
