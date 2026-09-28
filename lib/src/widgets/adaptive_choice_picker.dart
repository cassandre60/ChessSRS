import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// Shows the choice picker.
///
/// One appearance on every platform. It used to branch on `TargetPlatform`: a
/// `CupertinoActionSheet` on iOS, and past ten choices a `CupertinoPicker` wheel that selected by
/// scrolling and stopping. Every other platform already got the Diagram dialog below, so the same
/// settings row opened two different things depending on the device.
///
/// `00-agent-brief.md` open decision 4, resolved 2026-09-28: keep platform *behaviours*, not
/// platform-specific *looks*. The wheel was a behaviour difference too, and it made long lists
/// unreachable by tapping.
Future<void> showChoicePicker<T>(
  BuildContext context, {
  Widget? title,
  required List<T> choices,
  required T selectedItem,
  required Widget Function(T choice) labelBuilder,
  void Function(T choice)? onSelectedItemChanged,
}) {
  final deviceHeight = MediaQuery.heightOf(context);
  // SrsDialog rather than a Material AlertDialog: this picker is opened from a settings row
  // everywhere in the app, so converting it once reskins every caller instead of leaving
  // each screen tapping into a Material dialog.
  return showDialog<void>(
    context: context,
    builder: (context) {
      final choiceWidgets = choices
          .map(
            (value) => SrsSettingsRow(
              // Pass the caller's widget through rather than flattening it to a string: some
              // labels are rich text with a swatch in them, and reading `.data` off a
              // Text.rich yields null, which rendered the row blank.
              label: '',
              labelWidget: labelBuilder(value),
              selected: value == selectedItem,
              enabled: onSelectedItemChanged != null,
              onTap: () {
                onSelectedItemChanged?.call(value);
                Navigator.of(context).pop();
              },
            ),
          )
          .toList(growable: false);

      return SrsDialog(
        title: title == null ? null : _labelOf(context, title),
        // Capped and scrollable for every list, not just long ones. The old code only
        // constrained the >= 10 case, and a short list of tall labels -- the nine chess
        // variants, each a name plus a description -- grew the card to the full screen
        // height with no way to reach the last option.
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: deviceHeight * 0.6),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: choiceWidgets),
          ),
        ),
        actions: [
          SrsTextButton(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        ],
      );
    },
  );
}

/// The picker's own title is caller-supplied and may be rich text; fall back to an empty title
/// rather than flattening it, since only the rows above use [SrsSettingsRow.labelWidget].
String _labelOf(BuildContext context, Widget? label) {
  if (label is Text) return label.data ?? '';
  return '';
}

/// Shows a multi-select over [choices], returning the chosen subset.
///
/// Was `showAdaptiveDialog` + `AlertDialog.adaptive` + `CheckboxListTile.adaptive`, with
/// `CupertinoDialogAction` buttons on iOS. It backs the board settings "submit move" row, so it is
/// a preference a user can actually reach, and it was the one remaining place where the same
/// question looked like a different thing depending on the device.
///
/// `selected` on [SrsSettingsRow] draws a filled accent dot. On a multi-select that reads as
/// "included", which is the only marker the design system has, and it is what a checkbox was
/// standing in for anyway.
Future<Set<T>?> showMultipleChoicesPicker<T extends Enum>(
  BuildContext context, {
  required Iterable<T> choices,
  required Iterable<T> selectedItems,
  required Widget Function(T choice) labelBuilder,
}) {
  final deviceHeight = MediaQuery.heightOf(context);
  return showDialog<Set<T>>(
    context: context,
    builder: (context) {
      var items = {...selectedItems};
      return StatefulBuilder(
        builder: (context, setState) {
          final rows = choices
              .map(
                (choice) => SrsSettingsRow(
                  label: '',
                  labelWidget: labelBuilder(choice),
                  selected: items.contains(choice),
                  onTap: () => setState(() {
                    items = items.contains(choice)
                        ? items.difference({choice})
                        : items.union({choice});
                  }),
                ),
              )
              .toList(growable: false);

          return SrsDialog(
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: deviceHeight * 0.6),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: rows),
              ),
            ),
            // Right-aligned text button then pill, per the dialog spec in 03-components.md §11.
            actions: [
              SrsTextButton(
                label: context.l10n.cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
              SrsPillButton(
                label: context.l10n.mobileOkButton,
                onPressed: () => Navigator.of(context).pop(items),
              ),
            ],
          );
        },
      );
    },
  );
}
