import 'package:chess_srs/src/styles/lichess_colors.dart';
import 'package:chess_srs/src/widgets/pgn.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('moveAnnotationChar', () {
    test('returns empty string for no nags', () {
      expect(moveAnnotationChar(const []), '');
      expect(moveAnnotationChar(const <int>[]), '');
    });

    test('maps standard nags to symbols', () {
      expect(moveAnnotationChar(const [1]), '!');
      expect(moveAnnotationChar(const [2]), '?');
      expect(moveAnnotationChar(const [3]), '!!');
      expect(moveAnnotationChar(const [4]), '??');
      expect(moveAnnotationChar(const [5]), '!?');
      expect(moveAnnotationChar(const [6]), '?!');
    });

    test('joins multiple nags in order', () {
      expect(moveAnnotationChar(const [1, 6]), '!?!');
      expect(moveAnnotationChar(const [3, 4]), '!!??');
    });

    test('maps extended nags and ignores unknown', () {
      expect(moveAnnotationChar(const [10]), '=');
      expect(moveAnnotationChar(const [13]), '∞');
      expect(moveAnnotationChar(const [18]), '+-');
      expect(moveAnnotationChar(const [146]), 'N');
      expect(moveAnnotationChar(const [999]), '');
      expect(moveAnnotationChar(const [1, 999, 3]), '!!!');
    });
  });

  group('makeAnnotation', () {
    test('returns null for null or empty nags', () {
      expect(makeAnnotation(null), isNull);
      expect(makeAnnotation(const []), isNull);
    });

    test('uses first nag for annotation', () {
      final annotation = makeAnnotation(const [1, 2]);
      expect(annotation, isNotNull);
      expect(annotation!.symbol, '!');
      expect(annotation.color.toARGB32(), Colors.lightGreen.toARGB32());
    });

    test('maps known nags to symbols and colors', () {
      expect(makeAnnotation(const [3])!.symbol, '!!');
      expect(makeAnnotation(const [3])!.color.toARGB32(), Colors.teal.toARGB32());
      expect(makeAnnotation(const [5])!.symbol, '!?');
      expect(makeAnnotation(const [5])!.color.toARGB32(), Colors.purple.toARGB32());
      expect(makeAnnotation(const [6])!.symbol, '?!');
      expect(makeAnnotation(const [6])!.color.toARGB32(), LichessColors.inaccuracy.toARGB32());
      expect(makeAnnotation(const [2])!.symbol, '?');
      expect(makeAnnotation(const [2])!.color.toARGB32(), LichessColors.mistake.toARGB32());
      expect(makeAnnotation(const [4])!.symbol, '??');
      expect(makeAnnotation(const [4])!.color.toARGB32(), LichessColors.blunder.toARGB32());
    });

    test('maps grey positional/other nags', () {
      for (final nag in const [
        8,
        10,
        11,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        22,
        32,
        36,
        44,
        132,
        138,
        140,
        146,
      ]) {
        final annotation = makeAnnotation([nag]);
        expect(annotation, isNotNull, reason: 'nag $nag should map');
        expect(
          annotation!.color.toARGB32(),
          Colors.grey.toARGB32(),
          reason: 'nag $nag should be grey',
        );
        expect(annotation.symbol, isNotEmpty, reason: 'nag $nag should have symbol');
      }
    });

    test('returns null for unknown nag', () {
      expect(makeAnnotation(const [999]), isNull);
      expect(makeAnnotation(const [0]), isNull);
    });
  });
}
