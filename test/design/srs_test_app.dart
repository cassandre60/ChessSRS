// Harness for design-system widget tests.
//
// The design system (`lib/src/design/`) had no tests before C1, so every contract in
// docs/DESIGN_V2_GAP_CLOSURE.md needs a cheap way to pump a bare design widget with the
// SrsTheme ancestor it depends on, at a controlled surface size and platform.
//
// `defaultTargetPlatform` is the host platform in `flutter test` (linux), and the design
// system hides keyboard hints on non-desktop platforms, so every test must pin the
// platform. It can only be pinned through `TargetPlatformVariant`: the framework restores
// it inside the test body, before it asserts no foundation debug variable leaked.
import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone surface, matches the demo's 390x800 frame.
const Size kSrsPhoneSurface = Size(390, 800);

/// Desktop surface, matches the demo's 1280x800 frame.
const Size kSrsDesktopSurface = Size(1280, 800);

/// A touch platform, where the design system hides keyboard hints.
final TargetPlatformVariant kSrsTouchPlatform = TargetPlatformVariant.only(TargetPlatform.android);

/// A desktop platform, where the design system shows keyboard hints.
final TargetPlatformVariant kSrsDesktopPlatform = TargetPlatformVariant.only(TargetPlatform.linux);

/// [testWidgets] pinned to a touch platform.
void srsPhoneTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  TargetPlatformVariant? variant,
}) => testWidgets(description, body, variant: variant ?? kSrsTouchPlatform);

/// [testWidgets] pinned to a desktop platform.
void srsDesktopTestWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  TargetPlatformVariant? variant,
}) => testWidgets(description, body, variant: variant ?? kSrsDesktopPlatform);

/// Pumps [child] inside the minimum tree the design system needs: `SrsTheme` above
/// `WidgetsApp` (for `DefaultTextStyle`, `Directionality`) and an [Overlay] (for
/// [showSrsToast] and anything else that inserts an overlay entry).
///
/// Calling it again with a different [child] swaps the child. A bare
/// `Overlay(initialEntries: …)` cannot do that — it ignores `initialEntries` on rebuild —
/// so the overlay lives inside [_SrsHost], which marks the entry dirty instead.
///
/// Design widgets are deliberately built on `package:flutter/widgets.dart` only, so this
/// harness never installs a `Material` ancestor: if a design widget reaches for one, that is
/// a contract violation and the test should fail.
Future<void> pumpSrs(
  WidgetTester tester,
  Widget child, {
  Size surface = kSrsPhoneSurface,
  Brightness brightness = Brightness.light,
  SrsAccent accent = kSrsDefaultAccent,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    SrsTheme(
      colors: srsTestColors(brightness: brightness, accent: accent),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => MediaQuery(
          data: MediaQueryData(size: surface),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: _SrsHost(child: child),
          ),
        ),
      ),
    ),
  );
}

/// Holds the single [Overlay] the design system inserts into, and can swap its child.
class _SrsHost extends StatefulWidget {
  const _SrsHost({required this.child});

  final Widget child;

  @override
  State<_SrsHost> createState() => _SrsHostState();
}

class _SrsHostState extends State<_SrsHost> {
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_SrsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

/// The [SrsColors] a bare design widget resolves, for asserting token values.
SrsColors srsTestColors({
  Brightness brightness = Brightness.light,
  SrsAccent accent = kSrsDefaultAccent,
}) => SrsColors.forBrightness(brightness, accent);
