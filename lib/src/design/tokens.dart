// ChessSRS design tokens — adapted from design/flutter/chesssrs_tokens.dart.
// Mirrors design/tokens/tokens.json. Depends only on package:flutter/widgets.dart.
// ignore_for_file: avoid_classes_with_only_static_members
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// Accents
// ---------------------------------------------------------------------------
enum SrsAccent { ultramarine, violet, verdigris, ochre }

class SrsAccentPair {
  const SrsAccentPair(this.light, this.dark);
  final Color light;
  final Color dark;
}

/// Every value passes 4.5:1 against ground and surface in its own theme.
const Map<SrsAccent, SrsAccentPair> kSrsAccents = {
  SrsAccent.ultramarine: SrsAccentPair(Color(0xFF2A3FD9), Color(0xFF8A9BFF)),
  SrsAccent.violet: SrsAccentPair(Color(0xFF6B3FD4), Color(0xFFB7A0FF)),
  SrsAccent.verdigris: SrsAccentPair(Color(0xFF0B7A83), Color(0xFF5FCBD3)),
  SrsAccent.ochre: SrsAccentPair(Color(0xFF9A5500), Color(0xFFF2B04D)),
};
const SrsAccent kSrsDefaultAccent = SrsAccent.ultramarine;

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------
@immutable
class SrsColors {
  const SrsColors._({
    required this.brightness,
    required this.accentId,
    required this.page,
    required this.ground,
    required this.surface,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.hairline,
    required this.hairlineSoft,
    required this.scrim,
    required this.squareLight,
    required this.squareDark,
    required this.hatch,
    required this.halo,
    required this.accent,
    required this.accentSoft,
    required this.accentMid,
  });

  final Brightness brightness;
  final SrsAccent accentId;
  final Color page;
  final Color ground;
  final Color surface;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color hairline;
  final Color hairlineSoft;
  final Color scrim;
  final Color squareLight;
  final Color squareDark;
  final Color hatch;
  final Color halo;
  final Color accent;
  final Color accentSoft;
  final Color accentMid;

  factory SrsColors.light(SrsAccent a) {
    final accent = kSrsAccents[a]!.light;
    return SrsColors._(
      brightness: Brightness.light,
      accentId: a,
      page: const Color(0xFFE2E6E9),
      ground: const Color(0xFFF1F3F4),
      surface: const Color(0xFFFAFBFB),
      ink: const Color(0xFF101318),
      ink2: const Color(0xFF4B5361),
      ink3: const Color(0xFF868D98),
      hairline: const Color.fromRGBO(16, 19, 24, 0.13),
      hairlineSoft: const Color.fromRGBO(16, 19, 24, 0.055),
      scrim: const Color.fromRGBO(16, 19, 24, 0.22),
      squareLight: const Color(0xFFF8F9FA),
      squareDark: const Color(0xFFE7EAED),
      hatch: const Color.fromRGBO(16, 19, 24, 0.30),
      halo: const Color(0xFFF8F9FA),
      accent: accent,
      accentSoft: accent.withValues(alpha: 0.11),
      accentMid: accent.withValues(alpha: 0.24),
    );
  }

  factory SrsColors.dark(SrsAccent a) {
    final accent = kSrsAccents[a]!.dark;
    return SrsColors._(
      brightness: Brightness.dark,
      accentId: a,
      page: const Color(0xFF050608),
      ground: const Color(0xFF0D0F13),
      surface: const Color(0xFF151920),
      ink: const Color(0xFFECEEF1),
      ink2: const Color(0xFF9BA2AE),
      ink3: const Color(0xFF666D79),
      hairline: const Color.fromRGBO(236, 238, 241, 0.14),
      hairlineSoft: const Color.fromRGBO(236, 238, 241, 0.06),
      scrim: const Color.fromRGBO(0, 0, 0, 0.5),
      squareLight: const Color(0xFF11141A),
      squareDark: const Color(0xFF161A22),
      hatch: const Color.fromRGBO(236, 238, 241, 0.22),
      halo: const Color(0xFF11141A),
      accent: accent,
      accentSoft: accent.withValues(alpha: 0.15),
      accentMid: accent.withValues(alpha: 0.30),
    );
  }

  factory SrsColors.forBrightness(Brightness b, SrsAccent a) =>
      b == Brightness.dark ? SrsColors.dark(a) : SrsColors.light(a);

  bool get isDark => brightness == Brightness.dark;

  @override
  bool operator ==(Object other) =>
      other is SrsColors && other.brightness == brightness && other.accentId == accentId;

  @override
  int get hashCode => Object.hash(brightness, accentId);
}

/// Provide once near the root (below WidgetsApp), fed by user settings.
class SrsTheme extends InheritedWidget {
  const SrsTheme({super.key, required this.colors, required super.child});
  final SrsColors colors;

  static SrsColors of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<SrsTheme>();
    assert(w != null, 'No SrsTheme found in context');
    return w!.colors;
  }

  static SrsColors? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SrsTheme>()?.colors;
  }

  @override
  bool updateShouldNotify(SrsTheme oldWidget) => colors != oldWidget.colors;
}

extension SrsContext on BuildContext {
  SrsColors get srs => SrsTheme.of(this);
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------
abstract final class SrsMotion {
  static const Curve ease = Cubic(0.2, 0.7, 0.2, 1);
  static const Duration pieceMove = Duration(milliseconds: 170);
  static const Duration viewFade = Duration(milliseconds: 160);
  static const Duration noteFade = Duration(milliseconds: 200);
  static const Duration fillIn = Duration(milliseconds: 240);
  static const Duration sheetOpen = Duration(milliseconds: 180);
  static const Duration scrim = Duration(milliseconds: 140);
  static const Duration arrowDraw = Duration(milliseconds: 260);
  static const Duration toggle = Duration(milliseconds: 160);
  static const Duration press = Duration(milliseconds: 100);
  static const Duration quietAdvance = Duration(milliseconds: 560);
  static const Duration toastVisible = Duration(milliseconds: 2400);
  static const double pressScale = 0.97;
  static const double dragLiftScale = 1.08;

  /// Respect the platform reduce-motion flag.
  static Duration resolve(BuildContext c, Duration d) =>
      MediaQuery.disableAnimationsOf(c) ? Duration.zero : d;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
abstract final class SrsLayout {
  static const double wideBreakpoint = 720;
  static bool isWide(double width) => width >= wideBreakpoint;

  static const double topbarNarrow = 56;
  static const double topbarWide = 60;
  static const double coordGutter = 24;
  static const double wideColumnGap = 44;
  static const double wideSideMinWidth = 350;
  static const double wideSideMaxWidth = 560;
  static const EdgeInsets reviewPaddingNarrow = EdgeInsets.fromLTRB(12, 0, 12, 6);
  static const EdgeInsets reviewPaddingWide = EdgeInsets.fromLTRB(28, 0, 34, 28);
  static const double topbarPadLeftWide = 50;
  static const double minTouchTarget = 44;
  static const double pillHeight = 46;
  static const double pillPaddingH = 22;

  /// [content] = area below the top bar and inside safe areas.
  static double boardSize(Size content) {
    if (isWide(content.width)) {
      return math.max(0, math.min(content.height - 64, content.width - 480));
    }
    return math.max(0, math.min(content.width - 24, content.height - 222));
  }
}

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------
abstract final class SrsText {
  static const String ui = 'InstrumentSans';
  static const String read = 'Newsreader';
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle _ui(
    double size,
    FontWeight w,
    Color c, {
    double em = 0,
    double? height,
    bool tab = false,
  }) => TextStyle(
    fontFamily: ui,
    fontSize: size,
    fontWeight: w,
    color: c,
    letterSpacing: size * em,
    height: height,
    fontFeatures: tab ? tabular : null,
  );

  static TextStyle scopeName(Color c) => _ui(17, FontWeight.w600, c, em: -0.015, height: 1.2);
  static TextStyle due(Color c) => _ui(14, FontWeight.w400, c, tab: true);
  static TextStyle dueNumber(Color c) => _ui(14, FontWeight.w600, c, tab: true);
  static TextStyle meta(Color c) => _ui(13.5, FontWeight.w400, c);
  static TextStyle button(Color c) => _ui(15, FontWeight.w600, c);
  static TextStyle textButton(Color c) => _ui(15, FontWeight.w500, c);
  static TextStyle kbd(Color c) => _ui(11, FontWeight.w500, c, height: 1);
  static TextStyle groupTitle(Color c) => _ui(12.5, FontWeight.w500, c);
  static TextStyle rowName(Color c) => _ui(15.5, FontWeight.w500, c, em: -0.005);
  static TextStyle rowSub(Color c) => _ui(12.5, FontWeight.w400, c, tab: true);
  static TextStyle rowDue(Color c) => _ui(17, FontWeight.w600, c, tab: true);
  static TextStyle seg(Color c) => _ui(13.5, FontWeight.w500, c);
  static TextStyle settingLabel(Color c) => _ui(16, FontWeight.w500, c);
  static TextStyle settingHelp(Color c) => _ui(14, FontWeight.w400, c, height: 1.4);

  /// Notation line size.
  static double lineSize({required bool wide, double wideWidth = 0}) =>
      wide ? (wideWidth * 0.024).clamp(23.0, 31.0) : 21;
  static TextStyle lineMove(double size, Color c) =>
      _ui(size, FontWeight.w600, c, em: -0.012, height: _wideLineHeight(size), tab: true);
  static TextStyle lineNumber(double size, Color c) =>
      _ui(size, FontWeight.w400, c, em: -0.012, height: _wideLineHeight(size), tab: true);
  static double _wideLineHeight(double size) => size > 21 ? 1.3 : 1.36;

  static TextStyle answerMove(bool wide, Color c) =>
      _ui(wide ? 52 : 38, FontWeight.w600, c, em: -0.02, height: 1.1);
  static TextStyle answerHelp(bool wide, Color c) => _ui(wide ? 16 : 15, FontWeight.w400, c);
  static TextStyle note(Color c) =>
      TextStyle(fontFamily: read, fontSize: 16.5, height: 19 / 16.5, color: c);
  static TextStyle noteSource(Color c) => _ui(13, FontWeight.w400, c);
  static TextStyle title(Color c) => _ui(32, FontWeight.w400, c, em: -0.02, height: 1.15);
  static TextStyle display(double size, Color c) =>
      _ui(size, FontWeight.w400, c, em: -0.045, height: 0.98);
  static TextStyle titleSmall(Color c) => _ui(24, FontWeight.w500, c, em: -0.015, height: 1.2);
  static TextStyle body(bool wide, Color c) =>
      _ui(wide ? 18 : 17, FontWeight.w400, c, height: 1.45);
  static TextStyle wordmark(Color c) => _ui(16, FontWeight.w600, c);
  static TextStyle toast(Color c) => _ui(14, FontWeight.w500, c);
}
