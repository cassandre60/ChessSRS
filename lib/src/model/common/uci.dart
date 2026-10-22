import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:dartchess/dartchess.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'uci.freezed.dart';
part 'uci.g.dart';

/// UciCharPair from scalachess
@Freezed(fromJson: true, toJson: true, toStringOverride: false)
sealed class UciCharPair with _$UciCharPair {
  const UciCharPair._();

  const factory UciCharPair(String a, String b) = _UciCharPair;

  factory UciCharPair.fromStringId(String id) {
    if (id.length != 2) {
      throw ArgumentError('Invalid id $id');
    }
    return UciCharPair(id[0], id[1]);
  }

  /// Creates a UciCharPair from a UCI move.
  ///
  /// Throws an [ArgumentError] if the move is invalid.
  factory UciCharPair.fromUci(String uci) {
    final move = Move.parse(uci);
    if (move == null) {
      throw ArgumentError('Invalid uci $uci');
    }
    return UciCharPair.fromMove(move);
  }

  factory UciCharPair.fromMove(Move move) => switch (move) {
    NormalMove(from: final f, to: final t, promotion: final p) => UciCharPair(
      String.fromCharCode(35 + f),
      String.fromCharCode(p != null ? 35 + 64 + 8 * _promotionRoles.indexOf(p) + t.file : 35 + t),
    ),
    DropMove(to: final t, role: final r) => UciCharPair(
      String.fromCharCode(35 + t),
      String.fromCharCode(35 + 64 + 8 * 5 + _dropRoles.indexOf(r)),
    ),
  };

  /// The largest duplicate index [disambiguated] can encode.
  ///
  /// Every index from 1 to it gets its own id. Past it the private use area
  /// has no room left, and the duplicate is refused instead of being given an
  /// id another duplicate already has.
  static const maxDuplicateIndex = _firstCharacterIndexSteps * _secondCharacterIndexSteps;

  /// Creates a disambiguated [UciCharPair] for duplicate variations of the same move.
  ///
  /// For [duplicateIndex] <= 0, returns [base] unchanged.
  /// For [duplicateIndex] > 0, both characters move into the Unicode private
  /// use area (0xE000..0xF8FF):
  ///
  /// * the first character keeps the base pair's first character in its six
  ///   low bits and holds the high part of the duplicate index above them;
  /// * the second character keeps the base pair's second character in its low
  ///   byte - as the previous encoding did - and holds the low part of the
  ///   duplicate index in its high byte.
  ///
  /// Both characters stay in the basic multilingual plane, so an id is always
  /// two code units long and never holds half of a surrogate pair.
  ///
  /// Throws an [ArgumentError] if [duplicateIndex] is greater than
  /// [maxDuplicateIndex], or if [base] is not a plain id.
  factory UciCharPair.disambiguated(UciCharPair base, int duplicateIndex) {
    final cleanBase = base.basePair;
    if (duplicateIndex <= 0) return cleanBase;
    if (duplicateIndex > maxDuplicateIndex) {
      throw ArgumentError(
        'Cannot disambiguate $duplicateIndex duplicates of $cleanBase: '
        'the maximum is $maxDuplicateIndex',
      );
    }
    final baseA = cleanBase.a.codeUnitAt(0);
    final baseB = cleanBase.b.codeUnitAt(0);
    if (baseA < _charShift ||
        baseA > _charShift + _firstCharacterValues - 1 ||
        baseB < _charShift ||
        baseB > _charShift + _secondCharacterValues - 1) {
      throw ArgumentError('Not a plain id: $cleanBase');
    }
    final index = duplicateIndex - 1;
    return UciCharPair(
      String.fromCharCode(
        _privateUseStart +
            (index ~/ _secondCharacterIndexSteps) * _firstCharacterValues +
            (baseA - _charShift),
      ),
      String.fromCharCode(_privateUseStart + (index % _secondCharacterIndexSteps) * 256 + baseB),
    );
  }

  /// Returns the base [UciCharPair] without any disambiguation encoding.
  ///
  /// A character inside the private use area carries part of the encoding and
  /// is decoded; a character outside it is left alone.
  UciCharPair get basePair {
    final aCode = a.codeUnitAt(0);
    final bCode = b.codeUnitAt(0);
    final baseA = aCode >= _privateUseStart && aCode <= _privateUseEnd
        ? String.fromCharCode(_charShift + (aCode - _privateUseStart) % _firstCharacterValues)
        : a;
    final baseB = bCode >= _privateUseStart && bCode <= _privateUseEnd
        ? String.fromCharCode(bCode & 0xFF)
        : b;
    return UciCharPair(baseA, baseB);
  }

  factory UciCharPair.fromJson(Map<String, dynamic> json) => _$UciCharPairFromJson(json);

  @override
  String toString() => '$a$b';
}

const _promotionRoles = [Role.queen, Role.rook, Role.bishop, Role.knight, Role.king];

const _dropRoles = [Role.queen, Role.rook, Role.bishop, Role.knight, Role.pawn];

/// The first code unit a plain id character can hold: a plain id encodes a
/// square, a promotion or a drop role, all counted from 35 ('#').
const _charShift = 35;

/// The first code point of the Unicode private use area (basic multilingual
/// plane). A disambiguated id lives entirely inside it.
const _privateUseStart = 0xE000;

/// The last code point of the Unicode private use area (basic multilingual
/// plane).
const _privateUseEnd = 0xF8FF;

/// The number of code points in the private use area.
const _privateUseSize = _privateUseEnd - _privateUseStart + 1;

/// The number of values the first character of a plain id can take: a square,
/// counted from [_charShift].
const _firstCharacterValues = 64;

/// The number of values the second character of a plain id can take: a square
/// (35 + square), a promotion (35 + 64 + role * 8 + file) or a drop role
/// (35 + 64 + 40 + role), counted from [_charShift].
const _secondCharacterValues = 109;

/// The number of duplicate index steps the first character of a disambiguated
/// id can carry: the private use area holds [_privateUseSize] code points and
/// the base pair's first character spends [_firstCharacterValues] of them.
const _firstCharacterIndexSteps = _privateUseSize ~/ _firstCharacterValues;

/// The number of duplicate index steps the second character of a disambiguated
/// id can carry: it holds the step in its high byte, and the private use area
/// ends 25 code points after it starts.
const _secondCharacterIndexSteps = (_privateUseEnd - _privateUseStart) ~/ 256 + 1;

/// Compact representation of a path to a game node made from concatenated
/// UciCharPair strings.
@Freezed(fromJson: true, toJson: true)
sealed class UciPath with _$UciPath {
  const UciPath._();

  const factory UciPath(String value) = _UciPath;

  factory UciPath.fromId(UciCharPair id) => UciPath(id.toString());
  factory UciPath.fromIds(Iterable<UciCharPair> ids) =>
      UciPath(ids.map((id) => id.toString()).join(''));

  factory UciPath.fromNodeList(Iterable<Branch> nodeList) {
    final path = StringBuffer();
    for (final node in nodeList) {
      path.write(node.id);
    }
    return UciPath(path.toString());
  }

  factory UciPath.join(UciPath a, UciPath b) => UciPath(a.value + b.value);

  /// Creates a UciPath from a list of UCI moves.
  ///
  /// Throws an [ArgumentError] if any of the moves is invalid.
  factory UciPath.fromUciMoves(Iterable<UCIMove> moves) {
    final path = StringBuffer();
    for (final move in moves) {
      path.write(UciCharPair.fromUci(move));
    }
    return UciPath(path.toString());
  }

  static const empty = UciPath('');

  UciPath operator +(UciCharPair id) => UciPath(value + id.toString());

  UciCharPair operator [](int index) {
    assert(index >= 0 && index < size);
    return UciCharPair(value[index * 2], value[index * 2 + 1]);
  }

  bool contains(UciPath other) => value.startsWith(other.value);

  UciPath stripPrefix(UciPath prefix) =>
      contains(prefix) ? UciPath(value.substring(prefix.value.length)) : this;

  UciPath truncate(int maxSize) =>
      size <= maxSize ? this : UciPath(value.substring(0, maxSize * 2));

  int get size => value.length ~/ 2;

  UciCharPair? get head => value.isEmpty ? null : UciCharPair(value[0], value[1]);

  UciCharPair? get last =>
      value.isEmpty ? null : UciCharPair(value[value.length - 2], value[value.length - 1]);

  UciPath get tail => value.isEmpty ? UciPath.empty : UciPath(value.substring(2));

  UciPath get penultimate =>
      value.isEmpty ? UciPath.empty : UciPath(value.substring(0, value.length - 2));

  bool get isEmpty => value.isEmpty;

  factory UciPath.fromJson(Map<String, dynamic> json) => _$UciPathFromJson(json);
}
