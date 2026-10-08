// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-005, INV-067.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/import/opening_name.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/opening_name_repair_migration.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('spurious opening names', () {
    test('a title that merely mentions an opening is not a family', () {
      // The exact name the owner reported appearing as a hub (P-OPENNAME
      // follow-up): a study title, not an opening.
      expect(isLikelyOpeningFamily('White vs French'), isFalse);
      expect(mentionsOpeningButIsNotFamily('White vs French'), isTrue);
      expect(mentionsOpeningButIsNotFamily('My French Repertoire'), isTrue);
    });

    test('a real family is kept, including one the ECO table produces', () {
      for (final name in const [
        'French Defense',
        'Sicilian Defense',
        'Caro-Kann Defense',
        "Queen's Gambit",
        'Petrov Defense',
      ]) {
        expect(isLikelyOpeningFamily(name), isTrue, reason: name);
        expect(mentionsOpeningButIsNotFamily(name), isFalse, reason: name);
      }
    });

    test('every family the ECO fallback can produce is one the repair keeps', () {
      // The repair and the ECO table are separate producers of names; if the
      // repair rejected one of them it would erase a correct label on upgrade.
      for (final code in const [
        'B20',
        'B12',
        'B05',
        'C00',
        'C30',
        'C60',
        'D10',
        'D30',
        'D80',
        'E40',
        'E60',
        'E00',
        'A20',
        'A40',
        'A80',
      ]) {
        final family = ecoToOpeningFamily(code);
        expect(family, isNotNull, reason: code);
        expect(mentionsOpeningButIsNotFamily(family!), isFalse, reason: '$code → $family');
      }
    });

    test('an unrecognised name is left alone rather than erased', () {
      // Not a family this build knows, and not a mention of one either: the
      // repair must not treat "I do not recognise it" as "it is wrong".
      expect(mentionsOpeningButIsNotFamily('QGD Exchange Variation'), isFalse);
      expect(mentionsOpeningButIsNotFamily('My Repertoire'), isFalse);
    });
  });

  group('repairSpuriousOpeningNames', () {
    late Directory tempDir;
    late String dbPath;
    late Database db;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_opening_repair_');
      dbPath = p.join(tempDir.path, 'repair.db');
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
      await db.insert(kTableSrsStudy, {
        'id': 'study-1',
        'title': 'Study',
        'createdAt': '2026-09-16T12:00:00.000Z',
        'updatedAt': '2026-09-16T12:00:00.000Z',
        'isActive': 1,
      });
    });

    tearDown(() async {
      await db.close();
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> seedChapter(String id, {String? opening}) {
      return db.insert(kTableSrsChapter, {
        'id': id,
        'studyId': 'study-1',
        'sourceOrder': 0,
        'startingFen': 'start',
        'createdAt': '2026-09-16T12:00:00.000Z',
        'opening': opening,
        'treeJson': jsonEncode(
          repertoireNodeToJson(const RepertoireNode(id: 'n1', fen: 'start', fenKey: 'start')),
        ),
      });
    }

    Future<String?> openingOf(String chapterId) async {
      final rows = await db.query(
        kTableSrsChapter,
        columns: ['opening'],
        where: 'id = ?',
        whereArgs: [chapterId],
      );
      return rows.single['opening'] as String?;
    }

    test('clears a stored title-as-opening and keeps a real family', () async {
      await seedChapter('c-bogus', opening: 'White vs French');
      await seedChapter('c-real', opening: 'French Defense');
      await seedChapter('c-unknown', opening: 'QGD Exchange Variation');
      await seedChapter('c-none');

      final result = await repairSpuriousOpeningNames(db);

      expect(result.cleared, 1);
      expect(result.kept, 2);
      expect(await openingOf('c-bogus'), isNull);
      expect(await openingOf('c-real'), 'French Defense');
      expect(await openingOf('c-unknown'), 'QGD Exchange Variation');
      expect(await openingOf('c-none'), isNull);
    });

    test('is idempotent: a second run clears nothing', () async {
      await seedChapter('c-bogus', opening: 'White vs French');
      await seedChapter('c-real', opening: 'Sicilian Defense');

      final first = await repairSpuriousOpeningNames(db);
      final second = await repairSpuriousOpeningNames(db);

      expect(first.cleared, 1);
      expect(second.cleared, 0);
      expect(second.kept, 1);
    });

    test('clears across more chapters than one SQL statement can bind', () async {
      // 400 is the chunk size, so 500 chapters needs two statements; a single
      // unbound IN(...) would throw on the second batch instead of repairing it.
      for (var i = 0; i < 500; i++) {
        await seedChapter('c-$i', opening: i.isEven ? 'White vs French' : 'French Defense');
      }

      final result = await repairSpuriousOpeningNames(db);

      expect(result.cleared, 250);
      final remaining = await db.query(
        kTableSrsChapter,
        columns: ['opening'],
        where: 'opening IS NOT NULL',
      );
      expect(remaining.length, 250);
    });

    test('the chapter keeps its title and its tree', () async {
      await seedChapter('c-bogus', opening: 'White vs French');

      await repairSpuriousOpeningNames(db);

      final rows = await db.query(kTableSrsChapter, where: 'id = ?', whereArgs: ['c-bogus']);
      expect(rows.single['treeJson'], isNotNull);
      expect(rows.single['studyId'], 'study-1');
    });
  });
}
