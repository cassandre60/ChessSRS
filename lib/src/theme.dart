// The Lichess `CustomTheme` extension: the alternating row colours the table views and the
// list widgets read through `context.lichessTheme`.
//
// The rest of the legacy Lichess theme lived here too and is gone. `makeAppTheme` had no
// callers -- `app.dart` builds the Diagram theme through `srsThemeData` -- and with it went
// `_makeDefaultTheme` and `_makeBackgroundImageTheme`, the latter being the translucent-surface
// theme that existed so a user-chosen background image could show through. The background
// setting that fed it was cut with them: the Diagram palette specifies a fixed `ground`, and the
// accent table in `design/docs/02-tokens.md` is chosen against that `ground` for 4.5:1
// contrast. `kSliderTheme` went the same way: nothing referenced it, and it only carried a
// deprecated `SliderThemeData.year2023` flag.
import 'package:material_ui/material_ui.dart';

/// A custom theme extension that adds lichess custom properties to the theme.
@immutable
class CustomTheme extends ThemeExtension<CustomTheme> {
  const CustomTheme({required this.rowEven, required this.rowOdd});

  final Color rowEven;
  final Color rowOdd;

  @override
  CustomTheme copyWith({Color? rowEven, Color? rowOdd}) {
    return CustomTheme(rowEven: rowEven ?? this.rowEven, rowOdd: rowOdd ?? this.rowOdd);
  }

  @override
  CustomTheme lerp(ThemeExtension<CustomTheme>? other, double t) {
    if (other is! CustomTheme) {
      return this;
    }
    return CustomTheme(
      rowEven: Color.lerp(rowEven, other.rowEven, t) ?? rowEven,
      rowOdd: Color.lerp(rowOdd, other.rowOdd, t) ?? rowOdd,
    );
  }
}

/// A [BuildContext] extension that provides the [lichessTheme] property.
extension CustomThemeBuildContext on BuildContext {
  CustomTheme get _defaultLichessTheme => CustomTheme(
    rowEven: ColorScheme.of(this).surfaceContainer,
    rowOdd: ColorScheme.of(this).surfaceContainerLow,
  );

  CustomTheme get lichessTheme => Theme.of(this).extension<CustomTheme>() ?? _defaultLichessTheme;
}

// --
