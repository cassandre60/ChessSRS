import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UciCharPair', () {
    // regular moves
    expect(UciCharPair.fromMove(Move.parse('a1b1')!).toString(), '#\$');
    expect(UciCharPair.fromMove(Move.parse('a1a2')!).toString(), '#+');
    expect(UciCharPair.fromMove(Move.parse('h7h8')!).toString(), 'Zb');

    // promotions
    expect(UciCharPair.fromMove(Move.parse('b7b8q')!).toString(), 'Td');
    expect(UciCharPair.fromMove(Move.parse('b7c8q')!).toString(), 'Te');
    expect(UciCharPair.fromMove(Move.parse('b7c8n')!).toString(), 'T}');

    // drops
    expect(UciCharPair.fromMove(Move.parse('P@a1')!).toString(), '#\x8f');
    expect(UciCharPair.fromMove(Move.parse('Q@h8')!).toString(), 'b\x8b');

    // disambiguation for duplicate variations
    const base = UciCharPair('T', 'd');
    expect(UciCharPair.disambiguated(base, 0), base);
    final disambiguated1 = UciCharPair.disambiguated(base, 1);
    final disambiguated2 = UciCharPair.disambiguated(base, 2);
    expect(disambiguated1 != base, true);
    expect(disambiguated2 != disambiguated1, true);
    expect(disambiguated1.basePair, base);
    expect(disambiguated2.basePair, base);
    expect(base.basePair, base);
    expect(disambiguated1.toString().length, 2);
    expect(disambiguated2.toString().length, 2);
  });

  group('UciCharPair.fromStringId', () {
    test('keeps the two characters in order', () {
      // SPEC INV-010. The id of a branch is what tells two branches apart, so
      // the two characters of a stored id have to decode back the way they
      // were written.
      expect(UciCharPair.fromStringId('Td'), const UciCharPair('T', 'd'));
      expect(UciCharPair.fromStringId('Td').a, 'T');
      expect(UciCharPair.fromStringId('Td').b, 'd');
      expect(UciCharPair.fromStringId('Td').toString(), 'Td');
    });

    test('rejects an id that is not two characters', () {
      // SPEC INV-010. The length is checked before the characters are read, so
      // a malformed id is refused by the validation and not by an accidental
      // read past the end of the string.
      final rejection = throwsA(
        isA<ArgumentError>().having((e) => e.runtimeType, 'runtimeType', ArgumentError),
      );
      expect(() => UciCharPair.fromStringId(''), rejection);
      expect(() => UciCharPair.fromStringId('T'), rejection);
      expect(() => UciCharPair.fromStringId('Tdd'), rejection);
    });

    test('names the offending id in the error', () {
      // SPEC INV-010.
      expect(
        () => UciCharPair.fromStringId('Tdd'),
        throwsA(isA<ArgumentError>().having((e) => e.toString(), 'message', contains('Tdd'))),
      );
    });
  });

  group('UciCharPair.fromUci', () {
    test('encodes a move exactly like fromMove does', () {
      // SPEC INV-010.
      for (final uci in ['e2e4', 'b7b8q', 'g1f3', 'P@a1']) {
        expect(UciCharPair.fromUci(uci), UciCharPair.fromMove(Move.parse(uci)!));
      }
    });

    test('rejects a move it cannot parse', () {
      // SPEC INV-011. A move that cannot be parsed is refused outright rather
      // than half-encoded into an id that points at some other branch.
      expect(() => UciCharPair.fromUci('e2e9'), throwsA(isA<ArgumentError>()));
      expect(() => UciCharPair.fromUci('not-a-move'), throwsA(isA<ArgumentError>()));
      expect(() => UciCharPair.fromUci('e2'), throwsA(isA<ArgumentError>()));
    });

    test('names the offending move in the error', () {
      // SPEC INV-011.
      expect(
        () => UciCharPair.fromUci('e2e9'),
        throwsA(isA<ArgumentError>().having((e) => e.toString(), 'message', contains('e2e9'))),
      );
    });
  });

  group('UciCharPair.fromMove', () {
    test('gives every promotion role its own character', () {
      // SPEC INV-010. A promotion is identified by its role, so two roles may
      // never share a character: the id of a promoting branch would then be
      // indistinguishable from the id of the same move promoting differently.
      expect(UciCharPair.fromMove(Move.parse('b7b8q')!).toString(), 'Td');
      expect(UciCharPair.fromMove(Move.parse('b7b8r')!).toString(), 'Tl');
      expect(UciCharPair.fromMove(Move.parse('b7b8b')!).toString(), 'Tt');
      expect(UciCharPair.fromMove(Move.parse('b7b8n')!).toString(), 'T|');
    });

    test('gives every drop role its own character', () {
      // SPEC INV-010.
      expect(UciCharPair.fromMove(Move.parse('P@a1')!).toString(), '#\x8f');
      expect(UciCharPair.fromMove(Move.parse('Q@a1')!).toString(), '#\x8b');
      expect(UciCharPair.fromMove(Move.parse('R@a1')!).toString(), '#\x8c');
      expect(UciCharPair.fromMove(Move.parse('B@a1')!).toString(), '#\x8d');
      expect(UciCharPair.fromMove(Move.parse('N@a1')!).toString(), '#\x8e');
    });

    test('encodes distinct moves to distinct pairs', () {
      // SPEC INV-010. The id of a branch is the only thing that tells two
      // branches apart, so two different moves may never share an id.
      final moves = <String>[
        'e2e4',
        'd2d4',
        'g1f3',
        'b1c3',
        'a2a3',
        'h7h6',
        'c2c4',
        'b7b8q',
        'b7b8r',
        'b7b8b',
        'b7b8n',
        'b7c8q',
        'b7c8r',
        'b7c8b',
        'b7c8n',
        'P@a1',
        'Q@a1',
        'R@a1',
        'B@a1',
        'N@a1',
        'P@h8',
        'Q@h8',
        'R@h8',
        'B@h8',
        'N@h8',
      ];
      final pairs = moves.map((uci) => UciCharPair.fromMove(Move.parse(uci)!)).toList();
      expect(pairs.toSet().length, pairs.length);
    });
  });

  group('UciCharPair disambiguation', () {
    test('gives each duplicate index its own id', () {
      // SPEC INV-010. The duplicate index has to be recoverable from the id, so
      // two different indices may never produce the same id.
      final base = UciCharPair.fromMove(Move.parse('e2e4')!);
      final ids = [for (var i = 1; i <= 9; i++) UciCharPair.disambiguated(base, i)];
      expect(ids.toSet().length, ids.length);
    });

    test('keeps the base character recoverable for every index it can hold', () {
      // SPEC INV-010. The private use area holds 24 disambiguation indices
      // (0xE000..0xF8FF is 6400 code points, one index per 256 of them), and
      // every one of those indices still has to decode back to the base pair.
      final base = UciCharPair.fromMove(Move.parse('Q@h8')!);
      for (var i = 1; i <= 24; i++) {
        expect(UciCharPair.disambiguated(base, i).basePair, base);
      }
    });

    test('rewrites exactly the characters in the private use area', () {
      // No invariant names the private use range this encoding uses; the
      // contract is the one the code documents: `basePair` undoes the
      // disambiguation encoding and leaves every other character alone.
      expect(UciCharPair.fromStringId('T\uE000').basePair, const UciCharPair('T', '\x00'));
      expect(UciCharPair.fromStringId('T\uF8FF').basePair, const UciCharPair('T', '\xff'));
    });

    test('leaves a character outside the private use area alone', () {
      // No invariant names the private use range this encoding uses.
      expect(UciCharPair.fromStringId('T\uF900').basePair, UciCharPair.fromStringId('T\uF900'));
      expect(UciCharPair.fromStringId('T\u0100').basePair, UciCharPair.fromStringId('T\u0100'));
    });
  });

  group('UciPath', () {
    test('UciPath.size', () {
      expect(UciPath.empty.size, 0);
      expect(const UciPath('Td').size, 1);
      expect(const UciPath('TdTe').size, 2);
    });

    test('UciPath.head', () {
      expect(UciPath.empty.head, null);
      expect(const UciPath('Td').head, const UciCharPair('T', 'd'));
      expect(const UciPath('TdTe').head, const UciCharPair('T', 'd'));
    });

    test('UciPath.tail', () {
      expect(UciPath.empty.tail, UciPath.empty);
      expect(const UciPath('Td').tail, UciPath.empty);
      expect(const UciPath('TdTe').tail, const UciPath('Te'));
      expect(const UciPath('TdTeTf').tail, const UciPath('TeTf'));
    });

    test('UciPath.penultimate', () {
      expect(UciPath.empty.penultimate, UciPath.empty);
      expect(const UciPath('Td').penultimate, UciPath.empty);
      expect(const UciPath('TdTe').penultimate, const UciPath('Td'));
    });

    test('UciPath.last', () {
      expect(UciPath.empty.last, null);
      expect(const UciPath('Td').last, const UciCharPair('T', 'd'));
      expect(const UciPath('TdTe').last, const UciCharPair('T', 'e'));
    });

    test('UciPath.operator []', () {
      expect(const UciPath('Td')[0], const UciCharPair('T', 'd'));
      expect(const UciPath('TdTe')[0], const UciCharPair('T', 'd'));
      expect(const UciPath('TdTe')[1], const UciCharPair('T', 'e'));

      expect(() => UciPath.empty[0], throwsAssertionError);
      expect(() => const UciPath('TdTe')[2], throwsAssertionError);
      expect(() => const UciPath('TdTe')[-1], throwsAssertionError);
    });

    test('UciPath.stripPrefix', () {
      const path = UciPath('AaBbCcDdEe');
      expect(path.stripPrefix(UciPath.empty), path);
      expect(path.stripPrefix(const UciPath('Aa')), const UciPath('BbCcDdEe'));
      expect(path.stripPrefix(path), UciPath.empty);

      expect(path.stripPrefix(const UciPath('Nope')), path);
      expect(path.stripPrefix(const UciPath('Bb')), path);
    });

    test('UciPath.truncate', () {
      expect(UciPath.empty.truncate(0), UciPath.empty);
      expect(UciPath.empty.truncate(123), UciPath.empty);

      expect(const UciPath('Td').truncate(1), const UciPath('Td'));
      expect(const UciPath('TdTe').truncate(1), const UciPath('Td'));
      expect(const UciPath('TdTe').truncate(2), const UciPath('TdTe'));
      expect(const UciPath('TdTeTf').truncate(2), const UciPath('TdTe'));
      expect(const UciPath('TdTeTf').truncate(3), const UciPath('TdTeTf'));
      expect(const UciPath('TdTeTf').truncate(4), const UciPath('TdTeTf'));
    });

    test('UciPath.contains', () {
      expect(UciPath.empty.contains(UciPath.empty), true);
      expect(const UciPath('Td').contains(UciPath.empty), true);
      expect(const UciPath('Td').contains(const UciPath('Td')), true);
      expect(const UciPath('Td').contains(const UciPath('Te')), false);
      expect(const UciPath('TdTe').contains(const UciPath('Td')), true);
      expect(const UciPath('TdTe').contains(const UciPath('Te')), false);
      expect(const UciPath('TdTe').contains(const UciPath('Tf')), false);
    });

    test('UciPath.isEmpty', () {
      expect(UciPath.empty.isEmpty, true);
      expect(const UciPath('Td').isEmpty, false);
      expect(const UciPath('TdTe').isEmpty, false);
    });

    test('UciPath.join concatenates in order', () {
      expect(UciPath.join(const UciPath('Td'), const UciPath('Te')), const UciPath('TdTe'));
      expect(UciPath.join(const UciPath('Td'), UciPath.empty), const UciPath('Td'));
      expect(UciPath.join(UciPath.empty, const UciPath('Te')), const UciPath('Te'));
    });

    test('UciPath.fromId wraps a single pair', () {
      expect(UciPath.fromId(const UciCharPair('T', 'd')), const UciPath('Td'));
    });

    test('UciPath.fromIds concatenates the ids', () {
      expect(
        UciPath.fromIds([const UciCharPair('T', 'd'), const UciCharPair('T', 'e')]),
        const UciPath('TdTe'),
      );
      expect(UciPath.fromIds(const []), UciPath.empty);
    });

    test('UciPath.fromUciMoves encodes every move of the line', () {
      expect(
        UciPath.fromUciMoves(['e2e4', 'e7e5']),
        UciPath.fromIds([
          UciCharPair.fromMove(Move.parse('e2e4')!),
          UciCharPair.fromMove(Move.parse('e7e5')!),
        ]),
      );
    });

    test('UciPath.fromUciMoves refuses a move it cannot parse', () {
      // SPEC INV-011. A line that contains a move nobody can parse is refused
      // outright rather than turned into a path that addresses the wrong node.
      expect(() => UciPath.fromUciMoves(['e2e4', 'not-a-move']), throwsA(isA<ArgumentError>()));
    });

    test('UciPath.operator + appends the pair at the end', () {
      expect(const UciPath('Td') + const UciCharPair('T', 'e'), const UciPath('TdTe'));
      expect(UciPath.empty + const UciCharPair('T', 'd'), const UciPath('Td'));
    });

    test('UciPath.fromNodeList writes the id of every node', () {
      // SPEC INV-010. A path is the address of a node in the tree, so it has
      // to carry the id of each node on the way.
      final root = Root.fromPgnMoves('e4 e5');
      expect(root.mainlinePath, const UciPath('/?WG'));
      expect(UciPath.fromNodeList(root.mainline), root.mainlinePath);
    });

    test('UciPath.fromNodeList keeps the disambiguated id of a duplicate', () {
      // SPEC INV-010. Two variations of the same move share a base id and
      // differ only in their disambiguated one; a path that dropped the
      // disambiguation could no longer address the second of them.
      final base = UciCharPair.fromMove(Move.parse('e2e4')!);
      final first = Branch(
        sanMove: SanMove('e4', Move.parse('e2e4')!),
        position: Chess.initial,
        id: base,
      );
      final second = Branch(
        sanMove: SanMove('e4', Move.parse('e2e4')!),
        position: Chess.initial,
        id: UciCharPair.disambiguated(base, 1),
      );
      expect(
        UciPath.fromNodeList([first, second]),
        UciPath.fromIds([base, UciCharPair.disambiguated(base, 1)]),
      );
    });
  });
}
