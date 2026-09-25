// Launcher that stands in for the app's entry point to the Explore scenes.
//
// The tests that navigate Analysis → Board editor → Analysis used to start from
// `MoreTabScreen`, the bottom-tab hub the visual identity removed. The design's equivalent
// is the Library sheet, which carries the same `Analysis board` / `Opening explorer` /
// `Board editor` rows, so this helper drives that real sheet rather than a stand-in.
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A home screen with one button that opens the Library sheet.
class LibraryLauncher extends StatelessWidget {
  const LibraryLauncher({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: SrsTextButton(label: 'Open library', onPressed: () => SrsLibrarySheet.show(context)),
  );
}

/// Opens the Library sheet and taps [row], e.g. `kSrsAnalysisBoardLabel`.
Future<void> openLibraryRow(WidgetTester tester, String row) async {
  await tester.tap(find.text('Open library'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

/// Returns to the launcher, the way the user leaves an Explore scene.
Future<void> goBackToLibrary(WidgetTester tester) async {
  // The scene's sub-head names its destination; tap that.
  await tester.tap(find.text('Library').last);
  await tester.pumpAndSettle();
}
