// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/user/search_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The opening explorer's database settings, as a sheet of Diagram rows.
///
/// Every control here was a `ListTile` whose subtitle was a `Wrap` of Material choice and filter
/// chips. They are now [SrsSettingsRow]s carrying an [SrsSegmented] -- the plain form where the
/// choice is exclusive, `.multi` where it is not.
class OpeningExplorerSettings extends ConsumerWidget {
  const OpeningExplorerSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(openingExplorerPreferencesProvider);
    final notifier = ref.read(openingExplorerPreferencesProvider.notifier);

    /// A row whose control picks one of [options]. [onChanged] may be async; the row does not
    /// care, and the notifier's futures are fire-and-forget.
    Widget single<T>({
      required String label,
      required Map<T, String> options,
      required T selected,
      required void Function(T) onChanged,
    }) => SrsSettingsRow(
      label: label,
      control: SrsSegmented<T>(options: options, value: selected, onChanged: onChanged),
    );

    /// A row where any number of [options] may be on at once. The preference's own `toggle`
    /// already flips the key, so the control's "is it on now" flag is not needed here.
    Widget multiple<T>({
      required String label,
      required Map<T, String> options,
      required Iterable<T> selected,
      required void Function(T) onToggle,
    }) => SrsSettingsRow(
      label: label,
      control: SrsSegmented<T>.multi(
        options: options,
        values: selected,
        onToggled: (key, _) => onToggle(key),
      ),
    );

    /// `datesMap` is label -> value; the segmented control wants value -> label.
    Map<T, String> byValue<T>(Map<String, T> dates) => {
      for (final e in dates.entries) e.value: e.key,
    };

    /// The speed control, labelled the way the Lichess client labels a time control.
    Map<Speed, String> speedLabels(Iterable<Speed> speeds) => {
      for (final s in speeds) s: Perf.fromVariantAndSpeed(Variant.standard, s).label(context.l10n),
    };

    final rows = <Widget>[
      SrsSettingsRow(
        label: context.l10n.database,
        control: SrsSegmented<OpeningDatabase>(
          options: const {
            OpeningDatabase.master: 'Masters',
            OpeningDatabase.lichess: 'Lichess',
            OpeningDatabase.player: 'Player',
            OpeningDatabase.chessdb: 'ChessDB',
          },
          value: prefs.db,
          onChanged: notifier.setDatabase,
        ),
      ),
    ];

    switch (prefs.db) {
      case OpeningDatabase.master:
        rows.add(
          single<int>(
            label: 'Timespan',
            options: byValue(MasterDb.datesMap),
            selected: prefs.masterDb.sinceYear,
            onChanged: notifier.setMasterDbSince,
          ),
        );
      case OpeningDatabase.lichess:
        rows
          ..add(
            multiple<Speed>(
              label: context.l10n.timeControl,
              options: speedLabels(LichessDb.kAvailableSpeeds),
              selected: prefs.lichessDb.speeds,
              onToggle: notifier.toggleLichessDbSpeed,
            ),
          )
          ..add(
            multiple<int>(
              label: context.l10n.rating,
              options: {for (final r in LichessDb.kAvailableRatings) r: '$r'},
              selected: prefs.lichessDb.ratings,
              onToggle: notifier.toggleLichessDbRating,
            ),
          )
          ..add(
            single<DateTime>(
              label: 'Timespan',
              options: byValue(LichessDb.datesMap),
              selected: prefs.lichessDb.since,
              onChanged: notifier.setLichessDbSince,
            ),
          );
      case OpeningDatabase.player:
        rows
          ..add(
            SrsSettingsRow(
              label: context.l10n.player,
              value: prefs.playerDb.username ?? 'Select a Lichess player',
              onTap: () => Navigator.of(context).push(
                SearchScreen.buildRoute(
                  onUserTap: (user) {
                    notifier.setPlayerDbUsernameOrId(user.name);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ),
          )
          ..add(
            single<Side>(
              label: context.l10n.side,
              options: const {Side.white: 'White', Side.black: 'Black'},
              selected: prefs.playerDb.side,
              onChanged: notifier.setPlayerDbSide,
            ),
          )
          ..add(
            multiple<Speed>(
              label: context.l10n.timeControl,
              options: speedLabels(PlayerDb.kAvailableSpeeds),
              selected: prefs.playerDb.speeds,
              onToggle: notifier.togglePlayerDbSpeed,
            ),
          )
          ..add(
            multiple<GameMode>(
              label: context.l10n.mode,
              options: const {GameMode.casual: 'Casual', GameMode.rated: 'Rated'},
              selected: prefs.playerDb.gameModes,
              onToggle: notifier.togglePlayerDbGameMode,
            ),
          )
          ..add(
            single<DateTime>(
              label: 'Timespan',
              options: byValue(PlayerDb.datesMap),
              selected: prefs.playerDb.since,
              onChanged: notifier.setPlayerDbSince,
            ),
          );
      case OpeningDatabase.chessdb:
        rows.add(
          const SrsSettingsRow(
            label: 'ChessDB Cloud Book',
            help:
                'Open cloud database queries with move evaluation scores, win rates, and candidate lines.',
          ),
        );
    }

    return SrsSheetSurface(
      radius: 22,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SrsSheetGrabber(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
