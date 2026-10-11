// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Application-layer access to the database-file facts that settings displays.
///
/// `QUALITY.md` §1.1 keeps `view/` off `db/`. The storage-size readout in
/// `SrsSettingsScreen` is the one thing presentation still wanted from that layer, so
/// it is re-exported here rather than reached for directly: the screen imports this
/// file, and `db/database.dart` stays an implementation detail of the application
/// layer.
///
/// This is a re-export, not a wrapper, and deliberately so. `getDbSizeInBytesProvider`
/// measures a file through `_databasePath`, which is private to `db/database.dart`;
/// duplicating the lookup here would mean exporting that path or reimplementing it,
/// creating a second source of truth for where the database lives. There is exactly one
/// provider and one implementation, and presentation depends on the name through the
/// application layer instead of through `db/`.
library;

export 'package:chess_srs/src/db/database.dart' show getDbSizeInBytesProvider;
