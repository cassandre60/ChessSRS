import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Shows a platform adaptive choice picker dialog
///
/// On Android, it shows a dialog with radio buttons.
/// On iOS, it shows a modal action sheet if the number of choices is less than or equal to 10.
/// Otherwise, it shows a [CupertinoPicker].
Future<void> showChoicePicker<T>(
  BuildContext context, {
  Widget? title,
  required List<T> choices,
  required T selectedItem,
  required Widget Function(T choice) labelBuilder,
  void Function(T choice)? onSelectedItemChanged,
}) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.iOS:
      if (choices.length <= 10) {
        return showCupertinoModalPopup<void>(
          context: context,
          builder: (context) {
            return CupertinoActionSheet(
              title: title,
              actions: choices.map((value) {
                return CupertinoActionSheetAction(
                  onPressed: () {
                    if (onSelectedItemChanged != null) {
                      onSelectedItemChanged(value);
                    }
                    Navigator.of(context).pop();
                  },
                  child: labelBuilder(value),
                );
              }).toList(),
              cancelButton: CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel),
              ),
            );
          },
        );
      } else {
        return showCupertinoModalPopup<void>(
          context: context,
          builder: (context) {
            return NotificationListener(
              onNotification: (ScrollEndNotification notification) {
                if (onSelectedItemChanged != null) {
                  final index = (notification.metrics as FixedExtentMetrics).itemIndex;
                  onSelectedItemChanged(choices[index]);
                }
                return false;
              },
              child: SizedBox(
                height: 250,
                child: CupertinoPicker(
                  backgroundColor: Theme.of(context).canvasColor,
                  useMagnifier: true,
                  magnification: 1.1,
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(
                    initialItem: choices.indexWhere((t) => t == selectedItem),
                  ),
                  children: choices.map((value) {
                    return Center(child: labelBuilder(value));
                  }).toList(),
                  onSelectedItemChanged: (_) {},
                ),
              ),
            );
          },
        );
      }
    case TargetPlatform.android:
    default:
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
              SrsTextButton(
                label: context.l10n.cancel,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
  }
}

/// The picker's own title is caller-supplied and may be rich text; fall back to an empty title
/// rather than flattening it, since only the rows above use [SrsSettingsRow.labelWidget].
String _labelOf(BuildContext context, Widget? label) {
  if (label is Text) return label.data ?? '';
  return '';
}

Future<Set<T>?> showMultipleChoicesPicker<T extends Enum>(
  BuildContext context, {
  required Iterable<T> choices,
  required Iterable<T> selectedItems,
  required Widget Function(T choice) labelBuilder,
}) {
  return showAdaptiveDialog<Set<T>>(
    context: context,
    builder: (context) {
      Set<T> items = {...selectedItems};
      return AlertDialog.adaptive(
        contentPadding: const EdgeInsets.only(top: 12),
        scrollable: true,
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            // Material ancestor is needed for CheckboxListTile.adaptive to work on iOS
            return Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: choices
                    .map((choice) {
                      return CheckboxListTile.adaptive(
                        title: labelBuilder(choice),
                        value: items.contains(choice),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              items = value ? items.union({choice}) : items.difference({choice});
                            });
                          }
                        },
                      );
                    })
                    .toList(growable: false),
              ),
            );
          },
        ),
        actions: Theme.of(context).platform == TargetPlatform.iOS
            ? [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  child: Text(context.l10n.mobileOkButton),
                  onPressed: () => Navigator.of(context).pop(items),
                ),
              ]
            : [
                TextButton(
                  child: Text(context.l10n.cancel),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: Text(context.l10n.mobileOkButton),
                  onPressed: () => Navigator.of(context).pop(items),
                ),
              ],
      );
    },
  );
}
