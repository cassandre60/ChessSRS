// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/persistence/sqlite_study_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  group('schema v17 remote study linkage', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_upgrade_test_');
      dbPath = p.join(tempDir.path, 'upgrade.db');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
    });

    test('a v16 database gains the linkage columns with rows intact', () async {
      // A real pre-v17 library: srs_study without remoteStudyId/remoteUpdatedAt.
      final oldDb = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 16,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE srs_study (id TEXT PRIMARY KEY, title TEXT NOT NULL, '
              'createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL, '
              'isActive INTEGER NOT NULL DEFAULT 1, pgnHash TEXT)',
            );
            await db.insert('srs_study', {
              'id': 's1',
              'title': 'Old repertoire',
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-02T00:00:00.000',
              'isActive': 1,
              'pgnHash': 'abc123',
            });
          },
        ),
      );
      await oldDb.close();

      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(() async {
        try {
          await db.close();
        } catch (_) {}
      });

      final columns = await db.rawQuery('PRAGMA table_info(srs_study)');
      final names = columns.map((c) => c['name']! as String).toSet();
      expect(names, containsAll(['remoteStudyId', 'remoteUpdatedAt']));

      final rows = await db.query('srs_study');
      expect(rows.length, 1);
      expect(rows.first['title'], 'Old repertoire');
      expect(rows.first['pgnHash'], 'abc123');

      // The repository reads the upgraded row with empty linkage.
      final repo = SqliteStudyRepository(db);
      final study = await repo.getStudy('s1');
      expect(study?.remoteStudyId, isNull);
      expect(study?.remoteUpdatedAt, isNull);

      // And the new columns round-trip.
      await repo.updateStudyRemoteRef(
        studyId: 's1',
        remoteStudyId: 'aaaaaaaa',
        remoteUpdatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect((await repo.getStudy('s1'))?.remoteStudyId, 'aaaaaaaa');
      expect(await repo.getStudyByRemoteId('aaaaaaaa'), isNotNull);
    });
  });
}
