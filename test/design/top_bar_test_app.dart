import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';

// SPEC INV-062. SrsTopBar is stateless: it needs localization and theme, not providers or a
// socket. Keep Flutter's test error handler intact so RenderFlex overflow remains observable.
Future<Widget> makeTopBarTestApp(
  WidgetTester tester, {
  required Widget home,
  Size surfaceSize = const Size(390, 844),
}) async {
  final binding = TestLichessBinding.ensureInitialized();
  addTearDown(binding.reset);
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  return SrsTheme(
    colors: SrsColors.light(kSrsDefaultAccent),
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        MaterialLocalizationsEo.delegate,
        CupertinoLocalizationsEo.delegate,
      ],
      home: home,
    ),
  );
}
