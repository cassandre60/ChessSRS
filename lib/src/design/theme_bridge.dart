// Bridge between SrsColors and Material ThemeData.
// The app still uses MaterialApp, so we generate a ThemeData that is
// visually consistent with the design tokens. This lets un-migrated
// screens (analysis, editor) look reasonable while migrated screens
// read tokens from SrsTheme.of(context) directly.
import 'dart:async';

import 'package:chess_srs/src/design/tokens.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The accent the design system's colours are built from.
///
/// A view over the stored preference rather than a value of its own. It used to be a plain
/// notifier that always rebuilt to the default and never wrote anything down, so the settings
/// screen let the user pick an accent and the app forgot it on the next launch.
class SrsAccentNotifier extends Notifier<SrsAccent> {
  @override
  SrsAccent build() => ref.watch(generalPreferencesProvider.select((prefs) => prefs.accent));

  SrsAccent get accent => state;

  set accent(SrsAccent value) {
    state = value;
    // The preference is the value of record; this assignment is the immediate repaint, and the
    // save is what makes it survive a restart.
    unawaited(ref.read(generalPreferencesProvider.notifier).setAccent(value));
  }
}

final srsAccentProvider = NotifierProvider<SrsAccentNotifier, SrsAccent>(SrsAccentNotifier.new);

ThemeData srsThemeData(SrsColors c) {
  final brightness = c.brightness;
  final cs = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.ground,
    secondary: c.accent,
    onSecondary: c.ground,
    error: const Color(0xFFB3261E),
    onError: const Color(0xFFFFFFFF),
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerLowest: c.ground,
    surfaceContainerLow: c.ground,
    surfaceContainer: c.ground,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surface,
    surfaceDim: c.page,
    onSurfaceVariant: c.ink2,
    outline: c.hairline,
    outlineVariant: c.hairlineSoft,
    inverseSurface: c.ink,
    onInverseSurface: c.ground,
    shadow: c.scrim,
    scrim: c.scrim,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: cs,
    scaffoldBackgroundColor: c.ground,
    fontFamily: SrsText.ui,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.ground,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(color: c.ground, elevation: 0),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.ink2),
    listTileTheme: ListTileThemeData(textColor: c.ink, iconColor: c.ink2),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.ink,
      unselectedLabelColor: c.ink3,
      indicatorColor: c.accent,
      dividerColor: c.hairline,
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: const TextStyle(
        fontFamily: SrsText.ui,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: SrsText.ui,
        fontWeight: FontWeight.normal,
        fontSize: 14,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink3, fontSize: 14),
      labelStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink2, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.ground;
        return c.ink3;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        // Ink, not the accent: the Folio switch is on-ink/off-hairline (SrsSwitch), and the
        // bridge exists to make un-migrated screens read as the same system.
        if (states.contains(WidgetState.selected)) return c.ink;
        return c.surface;
      }),
      trackOutlineColor: WidgetStateProperty.all(c.hairline),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          // Ink, not the accent, for the same reason: SrsSegmented marks the chosen
          // item ink-on-ground.
          if (states.contains(WidgetState.selected)) return c.ink;
          return c.surface;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return c.ground;
          return c.ink;
        }),
        side: WidgetStateProperty.all(BorderSide(color: c.hairline)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Ink, not the accent: the only filled button in the system is the ink pill
        // (SrsPillButton), and the bridge exists to make un-migrated screens — auth,
        // import, offline setup — read as the same system instead of Material purple.
        backgroundColor: c.ink,
        foregroundColor: c.ground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        side: BorderSide(color: c.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.ink,
        textStyle: const TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface,
      contentTextStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink, fontSize: 14),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    sliderTheme: const SliderThemeData(
      // ignore: deprecated_member_use
      year2023: false,
    ),
  );
}
