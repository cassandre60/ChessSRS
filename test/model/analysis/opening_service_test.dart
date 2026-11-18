// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/openings_database.dart';
import 'package:chess_srs/src/model/analysis/opening_service.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE openings (eco TEXT, name TEXT, pgn TEXT, uci TEXT, epd TEXT)');
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertOpening({
    required String epd,
    String eco = 'C20',
    String name = "King's Pawn Game",
    String pgn = 'e4',
    String uci = 'e2e4',
  }) {
    return db.insert('openings', {'eco': eco, 'name': name, 'pgn': pgn, 'uci': uci, 'epd': epd});
  }

  /// Runs [OpeningService.fetchFromFen] against the in-memory database above.
  Future<FullOpening?> fetch(String fen) {
    final container = ProviderContainer(
      overrides: [openingsDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    return container.read(openingServiceProvider).fetchFromFen(fen);
  }

  // The EPD stored in the asset database is the position's first four FEN
  // fields, exactly as the dataset publishes it (en-passant target included
  // only when a legal en-passant capture exists).
  group('OpeningService.fetchFromFen', () {
    test('maps the stored row and ignores the halfmove clock and fullmove number', () async {
      const epd = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
      await insertOpening(
        epd: epd,
        eco: 'B00',
        name: "King's Pawn Game",
        pgn: '1. e4',
        uci: 'e2e4',
      );

      final opening = await fetch('$epd 0 1');

      expect(opening, isNotNull);
      expect(opening!.eco, 'B00');
      expect(opening.name, "King's Pawn Game");
      expect(opening.fen, epd);
      expect(opening.pgnMoves, '1. e4');
      expect(opening.uciMoves, 'e2e4');
    });

    test('finds a position whose castling field is "-"', () async {
      // Both sides have lost castling rights. The castling field itself is
      // "-", so a naive split on " - " swallows the ep field too.
      const epd = '2kr3r/ppp2ppp/1bn1bPq1/6N1/2ppNPP1/8/PPP4P/R1BQR1K1 w - -';
      await insertOpening(epd: epd, eco: 'B01', name: 'Scandinavian Defense');

      final opening = await fetch('$epd 3 17');

      expect(opening, isNotNull);
      expect(opening!.name, 'Scandinavian Defense');
      expect(opening.fen, epd);
    });

    test('finds a position with an en-passant target square', () async {
      const epd = 'rnbqkbnr/pp1ppppp/8/8/1pP1P3/8/P2P1PPP/RNBQKBNR b KQkq c3';
      await insertOpening(epd: epd, eco: 'A10', name: 'English Opening');

      final opening = await fetch('$epd 0 3');

      expect(opening, isNotNull);
      expect(opening!.name, 'English Opening');
      expect(opening.fen, epd);
    });

    test('returns null when the position is not in the database', () async {
      const epd = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
      await insertOpening(epd: epd);

      final opening = await fetch('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');

      expect(opening, isNull);
    });
  });
}
