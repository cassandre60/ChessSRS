import 'package:chess_srs/src/db/openings_database.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

const kOpeningAllowedVariants = ISetConst({
  Variant.standard,
  Variant.kingOfTheHill,
  Variant.threeCheck,
  Variant.crazyhouse,
});

/// A provider for [OpeningService].
final openingServiceProvider = Provider<OpeningService>((Ref ref) {
  return OpeningService(ref);
}, name: 'OpeningServiceProvider');

class OpeningService {
  OpeningService(this._ref);

  final Ref _ref;

  Future<Database> get _db => _ref.read(openingsDatabaseProvider.future);

  Future<FullOpening?> fetchFromFen(String fen) async {
    final db = await _db;
    // The openings table is keyed by the position's EPD (first four FEN fields),
    // en-passant target included when a legal capture exists. Splitting on
    // " - " instead mangles any position whose castling field is "-" (it
    // swallows the ep field) or whose ep field is a square, so use the shared
    // helper.
    final epd = fenToEpd(fen);
    final list = await db.query('openings', where: 'epd = ?', whereArgs: [epd], limit: 1);
    final first = list.firstOrNull;

    if (first != null) {
      return FullOpening(
        eco: first['eco']! as String,
        name: first['name']! as String,
        fen: first['epd']! as String,
        pgnMoves: first['pgn']! as String,
        uciMoves: first['uci']! as String,
      );
    } else {
      return null;
    }
  }
}
