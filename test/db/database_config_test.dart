// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// SPEC INV-001. An acknowledged review answer survives process restart.
// Database memory-mapping and page cache configuration preserve durability.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  group('database connection configuration', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_db_config_test_');
      dbPath = p.join(tempDir.path, 'config_test.db');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });
    });

    test('openAppDatabase configures foreign keys, mmap, cache size, and temp store', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      addTearDown(db.close);

      final fkResult = await db.rawQuery('PRAGMA foreign_keys');
      expect(fkResult.first.values.first, equals(1));

      final cacheResult = await db.rawQuery('PRAGMA cache_size');
      expect(cacheResult.first.values.first, equals(-64000));

      final tempStoreResult = await db.rawQuery('PRAGMA temp_store');
      expect(tempStoreResult.first.values.first, equals(2));

      final mmapResult = await db.rawQuery('PRAGMA mmap_size');
      final mmapValue = mmapResult.first.values.first! as int;
      expect(mmapValue, greaterThanOrEqualTo(0));
      // The exact pin the loose check above cannot provide: 0 is SQLite's
      // default, so `>= 0` passes when the pragma is never applied (#168).
      // The loose line stays until its removal is signed off (G08).
      expect(mmapValue, equals(268435456));
    });
  });
}
