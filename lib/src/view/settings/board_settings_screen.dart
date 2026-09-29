import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/utils/system.dart';
import 'package:chess_srs/src/view/settings/board_choice_screen.dart';
import 'package:chess_srs/src/view/settings/piece_set_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class BoardSettingsScreen extends ConsumerStatefulWidget {
  const BoardSettingsScreen({super.key});

  static Route<dynamic> buildRoute({bool fullscreenDialog = false}) {
    return buildScreenRoute(
      fullscreenDialog: fullscreenDialog,
      screen: const BoardSettingsScreen(),
    );
  }

  @override
  ConsumerState<BoardSettingsScreen> createState() => _BoardSettingsScreenState();
}

class _BoardSettingsScreenState extends ConsumerState<BoardSettingsScreen> {
  bool isLoading = false;

  Future<void> _setAccountPref(Future<void> Function(AccountPreferences preferences) save) async {
    setState(() {
      isLoading = true;
    });
    try {
      final authUser = ref.read(authControllerProvider);
      await save(ref.read(accountPreferencesProvider.notifier));
      if (authUser != null && mounted) {
        showSnackBar(
          context,
          context.l10n.settingsAccountPrefsSaved,
          type: SnackBarType.success,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final accountPrefsAsync = ref.watch(accountPreferencesProvider);
    final accountPrefs = accountPrefsAsync.value ?? defaultAccountPreferences;
    final authUser = ref.watch(authControllerProvider);
    final isOnline = ref.watch(isDeviceOnlineProvider);
    // We only allow changing account preferences if the user is logged out (prefs are local in that
    // case) or if the user is logged in and online (prefs are stored on the server in that case).
    final accountPrefsEnabled =
        accountPrefsAsync.hasValue && !isLoading && (authUser == null || isOnline);
    final androidVersionAsync = ref.watch(androidVersionProvider);

    // Correspondence and unlimited time controls require an account, so anonymous
    // players cannot enable move confirmation for them.
    final submitMoveChoices = authUser == null
        ? SubmitMoveChoice.values
              .where((c) => c != SubmitMoveChoice.correspondence && c != SubmitMoveChoice.unlimited)
              .toList()
        : SubmitMoveChoice.values;
    final submitMove = authUser == null
        ? SubmitMove(accountPrefs.submitMove.choices.where(submitMoveChoices.contains))
        : accountPrefs.submitMove;
    final c = context.srs;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.mobileBoardSettings,
              onBack: () => Navigator.of(context).maybePop(),
              // Every account preference on this screen round-trips to the server, so the
              // progress belongs on the head rather than on one row.
              trailing: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  const SrsGroupHeader('Display'),
                  SrsSettingsRow(
                    label: context.l10n.board,
                    value: boardPrefs.boardTheme.label,
                    onTap: () {
                      Navigator.of(context).push(BoardChoiceScreen.buildRoute());
                    },
                  ),
                  SrsSettingsRow(
                    label: context.l10n.pieceSet,
                    value: boardPrefs.pieceSet.label,
                    onTap: () {
                      Navigator.of(context).push(PieceSetScreen.buildRoute());
                    },
                  ),
                  SrsSettingsRow(
                    enabled: accountPrefsEnabled,
                    label: context.l10n.preferencesZenMode,
                    value: accountPrefs.zenMode.label(context.l10n),
                    onTap: accountPrefsEnabled
                        ? () {
                            showChoicePicker(
                              context,
                              choices: Zen.values,
                              selectedItem: accountPrefs.zenMode,
                              labelBuilder: (t) => Text(t.label(context.l10n)),
                              onSelectedItemChanged: (Zen? value) {
                                _setAccountPref(
                                  (prefs) => prefs.setZen(value ?? accountPrefs.zenMode),
                                );
                              },
                            );
                          }
                        : null,
                  ),
                  SrsSettingsRow(
                    enabled: accountPrefsEnabled,
                    label: context.l10n.preferencesPgnPieceNotation,
                    value: accountPrefs.pieceNotation.label(context.l10n),
                    onTap: accountPrefsEnabled
                        ? () {
                            showChoicePicker(
                              context,
                              choices: PieceNotation.values,
                              selectedItem: accountPrefs.pieceNotation,
                              labelBuilder: (t) => Text(t.label(context.l10n)),
                              onSelectedItemChanged: (PieceNotation? value) {
                                _setAccountPref(
                                  (prefs) =>
                                      prefs.setPieceNotation(value ?? accountPrefs.pieceNotation),
                                );
                              },
                            );
                          }
                        : null,
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesBoardCoordinates,
                    control: SrsSwitch(
                      value: boardPrefs.coordinates,
                      semanticLabel: context.l10n.preferencesBoardCoordinates,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleCoordinates();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.mobilePrefMagnifyDraggedPiece,
                    control: SrsSwitch(
                      value: boardPrefs.magnifyDraggedPiece,
                      semanticLabel: context.l10n.mobilePrefMagnifyDraggedPiece,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleMagnifyDraggedPiece();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.mobileSettingsDraggedPieceTarget,
                    value: dragTargetKindLabel(context.l10n, boardPrefs.dragTargetKind),
                    onTap: () {
                      showChoicePicker(
                        context,
                        choices: DragTargetKind.values,
                        selectedItem: boardPrefs.dragTargetKind,
                        labelBuilder: (t) => Text(dragTargetKindLabel(context.l10n, t)),
                        onSelectedItemChanged: (DragTargetKind? value) {
                          ref
                              .read(boardPreferencesProvider.notifier)
                              .setDragTargetKind(value ?? DragTargetKind.circle);
                        },
                      );
                    },
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesPieceAnimation,
                    control: SrsSwitch(
                      value: boardPrefs.pieceAnimation,
                      semanticLabel: context.l10n.preferencesPieceAnimation,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).togglePieceAnimation();
                      },
                    ),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.android &&
                      !isTabletOrLarger(context))
                    androidVersionAsync.maybeWhen(
                      data: (version) => version != null && version.sdkInt >= 29
                          ? SrsSettingsRow(
                              label: context.l10n.mobileSettingsImmersiveMode,
                              help: context.l10n.mobileSettingsImmersiveModeSubtitle,
                              control: SrsSwitch(
                                value: boardPrefs.immersiveModeWhilePlaying ?? false,
                                semanticLabel: context.l10n.mobileSettingsImmersiveMode,
                                onChanged: (value) {
                                  ref
                                      .read(boardPreferencesProvider.notifier)
                                      .toggleImmersiveModeWhilePlaying();
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesPieceDestinations,
                    control: SrsSwitch(
                      value: boardPrefs.showLegalMoves,
                      semanticLabel: context.l10n.preferencesPieceDestinations,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleShowLegalMoves();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesBoardHighlights,
                    control: SrsSwitch(
                      value: boardPrefs.boardHighlights,
                      semanticLabel: context.l10n.preferencesBoardHighlights,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleBoardHighlights();
                      },
                    ),
                  ),
                  if (!isShortVerticalScreen(context))
                    SrsSettingsRow(
                      label: context.l10n.preferencesMoveListWhilePlaying,
                      control: SrsSwitch(
                        value: boardPrefs.moveListDisplay,
                        semanticLabel: context.l10n.preferencesMoveListWhilePlaying,
                        onChanged: (value) {
                          ref.read(boardPreferencesProvider.notifier).toggleMoveListDisplay();
                        },
                      ),
                    ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesMaterialDifference,
                    value: boardPrefs.materialDifferenceFormat.l10n(AppLocalizations.of(context)),
                    onTap: () {
                      showChoicePicker(
                        context,
                        choices: MaterialDifferenceFormat.values,
                        selectedItem: boardPrefs.materialDifferenceFormat,
                        labelBuilder: (t) => Text(t.l10n(context.l10n)),
                        onSelectedItemChanged: (MaterialDifferenceFormat? value) => ref
                            .read(boardPreferencesProvider.notifier)
                            .setMaterialDifferenceFormat(
                              value ?? MaterialDifferenceFormat.materialDifference,
                            ),
                      );
                    },
                  ),
                  SrsSettingsRow(
                    label: context.l10n.mobileSettingsClockPosition,
                    value: boardPrefs.clockPosition.label(context.l10n),
                    onTap: () {
                      showChoicePicker(
                        context,
                        choices: ClockPosition.values,
                        selectedItem: boardPrefs.clockPosition,
                        labelBuilder: (t) => Text(t.label(context.l10n)),
                        onSelectedItemChanged: (ClockPosition? value) => ref
                            .read(boardPreferencesProvider.notifier)
                            .setClockPosition(value ?? ClockPosition.right),
                      );
                    },
                  ),
                  if (isTabletOrLarger(context))
                    SrsSettingsRow(
                      label: context.l10n.settingsBoardLandscapePosition,
                      value: boardPrefs.landscapeBoardPosition.label(context.l10n),
                      onTap: () {
                        showChoicePicker(
                          context,
                          choices: LandscapeBoardPosition.values,
                          selectedItem: boardPrefs.landscapeBoardPosition,
                          labelBuilder: (t) => Text(t.label(context.l10n)),
                          onSelectedItemChanged: (LandscapeBoardPosition? value) => ref
                              .read(boardPreferencesProvider.notifier)
                              .setLandscapeBoardPosition(value ?? LandscapeBoardPosition.left),
                        );
                      },
                    ),
                  const SrsGroupHeader('Game behaviour'),
                  SrsSettingsRow(
                    label: context.l10n.preferencesPremovesPlayingDuringOpponentTurn,
                    control: SrsSwitch(
                      value: boardPrefs.premoves,
                      semanticLabel: context.l10n.preferencesPremovesPlayingDuringOpponentTurn,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).togglePremoves();
                      },
                    ),
                  ),
                  // takebacks are always enabled for anonymous players, so hide the setting.
                  if (authUser != null)
                    SrsSettingsRow(
                      enabled: accountPrefsEnabled,
                      label: context.l10n.preferencesTakebacksWithOpponentApproval,
                      value: accountPrefs.takeback.label(context.l10n),
                      onTap: accountPrefsEnabled
                          ? () {
                              showChoicePicker(
                                context,
                                choices: Takeback.values,
                                selectedItem: accountPrefs.takeback,
                                labelBuilder: (t) => Text(t.label(context.l10n)),
                                onSelectedItemChanged: (Takeback? value) {
                                  _setAccountPref(
                                    (prefs) => prefs.setTakeback(value ?? accountPrefs.takeback),
                                  );
                                },
                              );
                            }
                          : null,
                    ),
                  SrsSettingsRow(
                    enabled: accountPrefsEnabled,
                    label: context.l10n.preferencesPromoteToQueenAutomatically,
                    value: accountPrefs.autoQueen.label(context.l10n),
                    onTap: accountPrefsEnabled
                        ? () {
                            showChoicePicker(
                              context,
                              choices: AutoQueen.values,
                              selectedItem: accountPrefs.autoQueen,
                              labelBuilder: (t) => Text(t.label(context.l10n)),
                              onSelectedItemChanged: (AutoQueen? value) {
                                _setAccountPref(
                                  (prefs) => prefs.setAutoQueen(value ?? accountPrefs.autoQueen),
                                );
                              },
                            );
                          }
                        : null,
                  ),
                  // Auto threefold is decided server side, so hide the setting for anonymous players.
                  if (authUser != null)
                    SrsSettingsRow(
                      enabled: accountPrefsEnabled,
                      label: context.l10n.preferencesClaimDrawOnThreefoldRepetitionAutomatically,
                      value: accountPrefs.autoThreefold.label(context.l10n),
                      onTap: accountPrefsEnabled
                          ? () {
                              showChoicePicker(
                                context,
                                choices: AutoThreefold.values,
                                selectedItem: accountPrefs.autoThreefold,
                                labelBuilder: (t) => Text(t.label(context.l10n)),
                                onSelectedItemChanged: (AutoThreefold? value) {
                                  _setAccountPref(
                                    (prefs) =>
                                        prefs.setAutoThreefold(value ?? accountPrefs.autoThreefold),
                                  );
                                },
                              );
                            }
                          : null,
                    ),
                  SrsSettingsRow(
                    enabled: accountPrefsEnabled,
                    label: context.l10n.preferencesMoveConfirmation,
                    value: submitMove.label(context.l10n),
                    onTap: accountPrefsEnabled
                        ? () {
                            showMultipleChoicesPicker(
                              context,
                              choices: submitMoveChoices,
                              selectedItems: submitMove.choices,
                              labelBuilder: (t) => Text(t.label(context.l10n)),
                            ).then((value) {
                              if (value != null) {
                                _setAccountPref((prefs) => prefs.setSubmitMove(SubmitMove(value)));
                              }
                            });
                          }
                        : null,
                    help: context.l10n.preferencesExplainCanThenBeTemporarilyDisabled,
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesConfirmResignationAndDrawOffers,
                    control: SrsSwitch(
                      value: boardPrefs.confirmResignAndDraw,
                      semanticLabel: context.l10n.preferencesConfirmResignationAndDrawOffers,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleConfirmResignAndDraw();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.mobileSettingsTouchFeedback,
                    help: context.l10n.mobileSettingsTouchFeedbackSubtitle,
                    control: SrsSwitch(
                      value: boardPrefs.hapticFeedback,
                      semanticLabel: context.l10n.mobileSettingsTouchFeedback,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleHapticFeedback();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesHowDoYouMovePieces,
                    value: pieceShiftMethodl10n(context, boardPrefs.pieceShiftMethod),
                    onTap: () {
                      showChoicePicker(
                        context,
                        choices: PieceShiftMethod.values,
                        selectedItem: boardPrefs.pieceShiftMethod,
                        labelBuilder: (t) => Text(pieceShiftMethodl10n(context, t)),
                        onSelectedItemChanged: (PieceShiftMethod? value) {
                          ref
                              .read(boardPreferencesProvider.notifier)
                              .setPieceShiftMethod(value ?? PieceShiftMethod.either);
                        },
                      );
                    },
                  ),
                  SrsSettingsRow(
                    label: context.l10n.settingsBoardMoveOnRelease,
                    help: context.l10n.settingsBoardMoveOnReleaseHelp,
                    control: SrsSwitch(
                      value: boardPrefs.moveOnRelease,
                      semanticLabel: context.l10n.settingsBoardMoveOnRelease,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleMoveOnRelease();
                      },
                    ),
                  ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesCastleByMovingTheKingTwoSquaresOrOntoTheRook,
                    value: boardPrefs.castlingMethod.l10n(context.l10n),
                    onTap: () {
                      showChoicePicker(
                        context,
                        choices: CastlingMethod.values,
                        selectedItem: boardPrefs.castlingMethod,
                        labelBuilder: (t) => Text(t.l10n(context.l10n)),
                        onSelectedItemChanged: (CastlingMethod? value) {
                          ref
                              .read(boardPreferencesProvider.notifier)
                              .setCastlingMethod(value ?? CastlingMethod.kingOverRook);
                        },
                      );
                    },
                  ),
                  SrsSettingsRow(
                    label: context.l10n.mobileSettingsShapeDrawing,
                    help: context.l10n.mobileSettingsShapeDrawingSubtitle,
                    control: SrsSwitch(
                      value: boardPrefs.enableShapeDrawings,
                      semanticLabel: context.l10n.mobileSettingsShapeDrawing,
                      onChanged: (value) {
                        ref.read(boardPreferencesProvider.notifier).toggleEnableShapeDrawings();
                      },
                    ),
                  ),
                  const SrsGroupHeader('Chess clock'),
                  // Give more time is always enabled for anonymous players, so hide the setting.
                  if (authUser != null)
                    SrsSettingsRow(
                      enabled: accountPrefsEnabled,
                      label: context.l10n.preferencesGiveMoreTime,
                      value: accountPrefs.moretime.label(context.l10n),
                      onTap: accountPrefsEnabled
                          ? () {
                              showChoicePicker(
                                context,
                                choices: Moretime.values,
                                selectedItem: accountPrefs.moretime,
                                labelBuilder: (t) => Text(t.label(context.l10n)),
                                onSelectedItemChanged: (Moretime? value) {
                                  _setAccountPref(
                                    (prefs) => prefs.setMoretime(value ?? accountPrefs.moretime),
                                  );
                                },
                              );
                            }
                          : null,
                    ),
                  SrsSettingsRow(
                    label: context.l10n.preferencesSoundWhenTimeGetsCritical,
                    control: SrsSwitch(
                      value: accountPrefs.clockSound.value,
                      semanticLabel: context.l10n.preferencesSoundWhenTimeGetsCritical,
                      onChanged: accountPrefsEnabled
                          ? (value) {
                              _setAccountPref((prefs) => prefs.setClockSound(BooleanPref(value)));
                            }
                          : null,
                    ),
                  ),
                  SrsSettingsRow(
                    enabled: accountPrefsEnabled,
                    label: context.l10n.preferencesTenthsOfSeconds,
                    value: accountPrefs.clockTenths.label(context.l10n),
                    onTap: accountPrefsEnabled
                        ? () {
                            showChoicePicker(
                              context,
                              choices: ClockTenths.values,
                              selectedItem: accountPrefs.clockTenths,
                              labelBuilder: (t) => Text(t.label(context.l10n)),
                              onSelectedItemChanged: (ClockTenths? value) {
                                _setAccountPref(
                                  (prefs) =>
                                      prefs.setClockTenths(value ?? accountPrefs.clockTenths),
                                );
                              },
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String pieceShiftMethodl10n(BuildContext context, PieceShiftMethod pieceShiftMethod) =>
    switch (pieceShiftMethod) {
      PieceShiftMethod.either => context.l10n.mobileSettingsPieceShiftMethodEither,
      PieceShiftMethod.drag => context.l10n.preferencesDragPiece,
      PieceShiftMethod.tapTwoSquares => context.l10n.mobileSettingsPieceShiftMethodTapTwoSquares,
    };
