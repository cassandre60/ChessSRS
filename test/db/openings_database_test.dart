import 'dart:io';

import 'package:chess_srs/src/db/openings_database.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  TestWidgetsFlutterBinding.ensureInitialized();

  // The ffi factory resolves getDatabasesPath() against the cwd of the FIRST
  // resolution and then pins it, so the cwd redirect happens once here, not
  // per test. Each test wipes the databases tree instead, which keeps the
  // tests independent of each other.
  final previousCwd = Directory.current;
  // Resolved before the redirect: the index test below opens the asset from
  // the filesystem, and a relative path would land in the temp tree.
  final assetDbPath = File('assets/chess_openings.db').absolute.path;
  final tempRoot = Directory.systemTemp.createTempSync('openings_db_test');
  Directory.current = tempRoot;

  tearDownAll(() async {
    Directory.current = previousCwd;
    await tempRoot.delete(recursive: true);
  });

  /// The directory the service's provider will place its database in.
  final databasesDir = Directory(p.join('.dart_tool', 'sqflite_common_ffi', 'databases'));

  /// Removes the whole .dart_tool tree, as on a fresh install.
  Future<void> wipeDatabasesTree() async {
    final dotTool = Directory(p.join(tempRoot.path, '.dart_tool'));
    if (await dotTool.exists()) await dotTool.delete(recursive: true);
  }

  Future<Database> openThroughProvider() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final db = await container.read(openingsDatabaseProvider.future);
    addTearDown(db.close);
    return db;
  }

  group('Openings database', () {
    test('openings table has index on epd covering fetchFromFen', () async {
      final db = await databaseFactoryFfi.openDatabase(
        assetDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      addTearDown(db.close);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'openings'",
      );
      expect(indexes.map((row) => row['name']), contains('idx_openings_epd'));

      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM openings WHERE epd = ? LIMIT 1',
        ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'],
      );
      final detail = plan.map((row) => row['detail']! as String).join(' ');
      expect(detail, contains('idx_openings_epd'));
      expect(detail, isNot(contains('SCAN')));
    });
  });

  group('openingsDatabaseProvider', () {
    test(
      'a first run creates the databases directory, copies the asset and opens it read-only',
      () async {
        // The whole .dart_tool/... chain is missing, as on a fresh install: the
        // directory creation must build every ancestor or the copy never happens.
        await wipeDatabasesTree();

        final db = await openThroughProvider();

        final file = File(p.join(databasesDir.path, 'chess_openings5.db'));
        expect(await file.exists(), isTrue, reason: 'the asset must be copied into place');
        final asset = await rootBundle.load('assets/chess_openings.db');
        expect((await file.readAsBytes()).length, asset.lengthInBytes);

        // The openings dataset is a static shared asset; a writable handle is
        // how it gets corrupted, so the connection must refuse writes.
        await expectLater(
          db.execute('CREATE TABLE mutant_probe (x)'),
          throwsA(isA<DatabaseException>()),
        );
      },
    );

    test('a first run deletes stale openings databases and leaves other files alone', () async {
      await wipeDatabasesTree();
      await databasesDir.create(recursive: true);
      final stale = File(p.join(databasesDir.path, 'chess_openings4.db'));
      await stale.writeAsBytes([1, 2, 3]);
      final unrelated = File(p.join(databasesDir.path, 'unrelated.db'));
      await unrelated.writeAsBytes([4, 5, 6]);

      await openThroughProvider();

      expect(await stale.exists(), isFalse, reason: 'old dataset versions must be cleaned up');
      expect(await unrelated.exists(), isTrue, reason: 'the cleanup must match name, not sweep');
    });

    test('an existing database is opened without being rewritten from the asset', () async {
      await wipeDatabasesTree();
      await databasesDir.create(recursive: true);
      // A valid database that is NOT the asset: if the provider copied the
      // asset over it, the probe table would vanish. The path is resolved via
      // getDatabasesPath() because the ffi factory treats a relative path as
      // relative to the databases directory, not the cwd.
      final probePath = p.join(await getDatabasesPath(), 'chess_openings5.db');
      final probe = await databaseFactoryFfiNoIsolate.openDatabase(probePath);
      await probe.execute('CREATE TABLE probe (x)');
      await probe.close();

      final db = await openThroughProvider();

      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'probe'",
      );
      expect(rows, isNotEmpty, reason: 'the existing database must not be replaced');
    });
  });
}
