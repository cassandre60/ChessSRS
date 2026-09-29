// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// The surface a bottom sheet or popover is painted on.
///
/// design/docs/03-components.md gives every sheet the same shell: background `surface`, the sheet
/// shadow from `02` §4, and clipped corners — radius 22 inset by 8 on a narrow screen, radius 16
/// for a popover. The Library sheet, the scope list and the study actions each grew their own copy
/// of this box, so a change to the shadow or the corner radius had three places to land. They now
/// share it.
///
/// Deliberately not in `primitives.dart`: that file imports only `flutter/widgets.dart`, and this
/// needs `Material` for the rows inside it.
class SrsSheetSurface extends StatelessWidget {
  const SrsSheetSurface({
    super.key,
    required this.child,
    this.radius = 22,
    this.maxHeight,
    this.width,
  });

  final Widget child;
  final double radius;

  /// Caps the sheet's height. Callers pass the spec's figure for their layout.
  final double? maxHeight;

  /// Defaults to whatever width the parent allows. A sheet anchored with only a left and a top
  /// gets loose constraints, and something that stretches to its parent's width inside it will
  /// lay out against an unbounded width — so a popover anchored that way has to say how wide it is.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final shape = BorderRadius.circular(radius);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: shape,
          boxShadow: [BoxShadow(color: c.scrim, blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: shape,
          child: Material(
            // A Material rather than a coloured box: Text and any Material descendant need a
            // Material ancestor inside the closest LookupBoundary, and the sheet is a route.
            key: surfaceKey,
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Addresses the painted surface, for tests that need its rect.
  static const surfaceKey = ValueKey('srs-sheet-surface');
}

/// The 36x4 grabber a narrow sheet carries at its top, with the spec's 8px gap above and below.
class SrsSheetGrabber extends StatelessWidget {
  const SrsSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: c.hairline, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}

/// A single-line text input in the style the dialogs use.
///
/// design/docs/03-components.md §12: "Text inputs: 16px, 1px `hairline` bottom border (2px `ink`
/// when focused), no filled/outlined boxes" — which is also the demo's `.field`. The rename dialog
/// is the only thing that needs one today, but the style belongs to the dialog family rather than
/// to that one call site.
class SrsTextInput extends StatelessWidget {
  const SrsTextInput({
    super.key,
    required this.controller,
    this.hintText,
    this.semanticLabel,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;

  /// The field's accessible name, which a bare underline input does not otherwise have.
  final String? semanticLabel;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final textStyle = TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink);
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      style: textStyle,
      cursorColor: c.accent,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        hintText: hintText,
        hintStyle: textStyle.copyWith(color: c.ink3),
        border: UnderlineInputBorder(borderSide: BorderSide(color: c.hairline)),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hairline)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ink, width: 2)),
      ),
    );
    if (semanticLabel == null) return field;
    return Semantics(label: semanticLabel, textField: true, child: field);
  }
}

/// Presents [child] — which should already be an [SrsSheetSurface] — as a bottom sheet.
///
/// The route's own background is transparent because the surface supplies the colour, radius and
/// shadow; leaving the route's chrome on as well is what produces a grey sheet inside a Diagram one.
/// The grabber belongs to the surface too, so `showDragHandle` stays off.
Future<T?> showSrsSheet<T>(BuildContext context, Widget child, {bool isDismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    backgroundColor: const Color(0x00000000),
    elevation: 0,
    builder: (_) => child,
  );
}

/// Finger-tracking drag-to-dismiss for the custom dialog sheets.
///
/// The Library, scope, study-actions and import sheets are plain routes over
/// `showGeneralDialog`, so unlike `showModalBottomSheet` they get no drag
/// handling from the framework: a swipe down previously did nothing until
/// release, then the sheet vanished in one frame (owner report 2026-09-29).
/// A downward [Dismissible] around the sheet content makes it follow the
/// finger, snap back under the threshold, and fling away past it — and only
/// then pops the route.
class SrsSheetDismissible extends StatelessWidget {
  const SrsSheetDismissible({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: const ValueKey('srs-sheet-dismissible'),
      direction: DismissDirection.down,
      dismissThresholds: const {DismissDirection.down: 0.25},
      movementDuration: const Duration(milliseconds: 200),
      // Translucent, like the drag-end detector this replaces: taps outside
      // the sheet must keep reaching the barrier behind it (barrier-tap
      // dismissal broke under the default opaque, which claims taps across
      // the whole route area). Drags starting on the sheet still track.
      behavior: HitTestBehavior.translucent,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: child,
    );
  }
}
