import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Unicode private use area (basic multilingual plane) the disambiguated
/// ids live in.
const _privateUseStart = 0xE000;
const _privateUseEnd = 0xF8FF;

/// The number of duplicate indices the encoding has to cover. It mirrors
/// `UciCharPair.maxDuplicateIndex`: every index from 1 to it must get its own
/// id, and every one of those ids must stay inside the private use area.
const _duplicateIndices = 2500;

bool _isSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDFFF;

void main() {
  group('UciCharPair.disambiguated', () {
    const base = UciCharPair('T', 'd');

    test('keeps every duplicate index inside the private use area', () {
      // SPEC INV-010. Two variations of the same move must never end up with
      // the same id, so every index the encoding accepts has to land inside
      // the private use area - the area the id format is documented to use.
      for (var index = 1; index <= _duplicateIndices; index++) {
        final id = UciCharPair.disambiguated(base, index);
        for (final codeUnit in id.toString().codeUnits) {
          expect(
            codeUnit,
            inInclusiveRange(_privateUseStart, _privateUseEnd),
            reason: 'duplicate index $index',
          );
        }
      }
    });

    test('gives every duplicate index its own id', () {
      // SPEC INV-010. The id is what tells two variations of the same move
      // apart, so two different indices may never produce the same id.
      final ids = <UciCharPair>{};
      for (var index = 1; index <= _duplicateIndices; index++) {
        expect(ids.add(UciCharPair.disambiguated(base, index)), isTrue,
            reason: 'duplicate index $index reused an id');
      }
    });

    test('recovers the base pair from every duplicate index', () {
      // SPEC INV-010. A disambiguated id is the base pair plus its duplicate
      // index, so the base pair has to come back out of it.
      for (var index = 1; index <= _duplicateIndices; index++) {
        expect(UciCharPair.disambiguated(base, index).basePair, base,
            reason: 'duplicate index $index');
      }
    });

    test('round-trips every duplicate index through its id', () {
      // SPEC INV-010. An id is stored as a string and read back, so the id
      // has to survive the trip through its own text.
      for (var index = 1; index <= _duplicateIndices; index++) {
        final id = UciCharPair.disambiguated(base, index);
        expect(UciCharPair.fromStringId(id.toString()), id,
            reason: 'duplicate index $index');
      }
    });

    test('keeps every id two code units long and free of surrogates', () {
      // SPEC INV-010. A path is a concatenation of two-code-unit ids, and the
      // app reads a path back two code units at a time, so an id may never be
      // longer than that and may never hold half of a surrogate pair.
      for (var index = 1; index <= _duplicateIndices; index++) {
        final id = UciCharPair.disambiguated(base, index).toString();
        expect(id.length, 2, reason: 'duplicate index $index');
        for (final codeUnit in id.codeUnits) {
          expect(_isSurrogate(codeUnit), isFalse, reason: 'duplicate index $index');
        }
      }
    });

    test('still decodes an id minted by the previous encoding', () {
      // The previous encoding put the duplicate index in the high byte of the
      // second character and left the first character alone. Those ids stay
      // readable, so an id written before the encoding changed still names
      // the same move.
      expect(
        UciCharPair.fromStringId('T\uE164').basePair,
        const UciCharPair('T', 'd'),
      );
    });

    test('refuses a duplicate index it cannot encode', () {
      // SPEC INV-011. Past the last index the encoding has, the only way to
      // answer would be to mint an id another duplicate already has. The
      // refusal is deliberate (an ArgumentError), not an overflow.
      expect(
        () => UciCharPair.disambiguated(base, _duplicateIndices + 1),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.runtimeType, 'runtimeType', ArgumentError),
        ),
      );
      expect(
        () => UciCharPair.disambiguated(base, 1000000000),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.runtimeType, 'runtimeType', ArgumentError),
        ),
      );
    });
  });

  group('Node.addChild', () {
    test('gives every sibling that repeats a move its own id', () {
      // SPEC INV-010. The id of a branch is what keeps two variations of the
      // same move apart, so a run of identical siblings must stay
      // distinguishable - past the point where the encoding used to run out.
      const siblingCount = 30;
      final root = Root(position: Chess.initial);
      final move = Move.parse('e2e4')!;
      final position = Chess.initial.playUnchecked(move);
      for (var i = 0; i < siblingCount; i++) {
        root.addChild(Branch(sanMove: SanMove('e4', move), position: position));
      }

      expect(root.children.length, siblingCount);
      final ids = root.children.map((child) => child.id).toList();
      expect(ids.toSet().length, siblingCount);
      for (final id in ids) {
        expect(root.childById(id)?.id, id);
        expect(id.basePair, UciCharPair.fromMove(move));
      }
    });

    test('imports a game whose variations repeat the same move', () {
      // SPEC INV-010. The duplicate variations of a real game are the case
      // the disambiguation exists for, so they have to survive the import
      // with distinct ids.
      const siblingCount = 30;
      final variations = List.filled(siblingCount, '(1. e4)').join(' ');
      final root = Root.fromPgnGame(PgnGame.parsePgn('1. e4 $variations *'));

      expect(root.children.length, siblingCount + 1);
      final ids = root.children.map((child) => child.id).toSet();
      expect(ids.length, siblingCount + 1);
    });
  });
}
