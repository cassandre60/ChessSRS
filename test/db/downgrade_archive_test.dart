// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The downgrade policy: an older build opening a newer database snapshots it
// and refuses, instead of deleting the file. When the archive mechanism was
// `onDatabaseDowngradeDelete` (the pre-fix code), the same open returned a
// fresh empty database and every study, decision and review row was gone.
//
// The scenario is not hypothetical: a build of any kind stamped user_version
// higher than the binary in hand — an installed older APK, a rollback across
// branches — and the file on disk is the only copy of three months of review
// memory.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_downgrade_test_');
    dbPath = p.join(tempDir.path, 'app.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  test('an older build refuses a newer database, archives it, and leaves it untouched', () async {
    // A database a newer build wrote: schema v24 with one repertoire row in it.
    final newer = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 24,
        onCreate: (db, version) async {
          await db.execute('CREATE TABLE srs_study (id TEXT PRIMARY KEY, title TEXT NOT NULL)');
          await db.insert('srs_study', {'id': 'st-1', 'title': 'Owner repertoire'});
        },
      ),
    );
    await newer.close();

    Database? opened;
    try {
      opened = await openAppDatabase(databaseFactoryFfi, dbPath);
      fail(
        'opening a v24 database from a v23 build must fail rather than '
        'recreate it empty (the pre-fix code deleted the file)',
      );
    } on DatabaseNewerVersionException catch (e) {
      expect(e.oldVersion, 24);
      expect(e.newVersion, 23, reason: 'the repo schema version that exists today');
      expect(
        e.toString(),
        contains('Nothing was deleted'),
        reason: 'the message must tell the user why the open refuses instead of wipe',
      );
    } finally {
      await opened?.close();
    }

    // The archive slot holds a standalone (no WAL strangers) snapshot the
    // recovery recipe can open read-only.
    final archive = File('$dbPath.pre-downgrade.bak');
    expect(archive.existsSync(), isTrue, reason: 'refusal must not discard the only copy');

    final snapshot = await databaseFactoryFfi.openDatabase(
      archive.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final saved = await snapshot.rawQuery('SELECT count(*) FROM srs_study');
    expect(saved.single['count(*)'], 1, reason: 'the archive holds the repertoire rows');
    await snapshot.close();

    // The live file itself survives the refused open, byte for byte in
    // shape: still v24, still carrying the row.
    final live = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    expect((await live.rawQuery('PRAGMA user_version')).single['user_version'], 24);
    final liveRows = await live.rawQuery('SELECT count(*) FROM srs_study');
    expect(liveRows.single['count(*)'], 1);
    await live.close();
  });

  test('a repeated refused open refreshes the archive instead of growing', () async {
    await databaseFactoryFfi
        .openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 24,
            onCreate: (db, version) async {
              await db.execute('CREATE TABLE srs_study (id TEXT PRIMARY KEY, title TEXT NOT NULL)');
              await db.insert('srs_study', {'id': 'st-1', 'title': 'Owner repertoire'});
            },
          ),
        )
        .then((db) => db.close());

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await openAppDatabase(databaseFactoryFfi, dbPath);
        fail('each open while the build is older must still refuse');
      } on DatabaseNewerVersionException {
        // expected on both attempts
      }
    }

    final slot = Directory(
      tempDir.path,
    ).listSync().whereType<File>().any((f) => f.path.endsWith('app.db.pre-downgrade.bak'));
    expect(slot, isTrue, reason: 'one archive slot, refreshed in place');

    final archives = Directory(
      tempDir.path,
    ).listSync().whereType<File>().where((f) => f.path.contains('pre-downgrade.bak')).length;
    expect(archives, 1, reason: 'refusing twice must not snowball archive copies');
  });
}
