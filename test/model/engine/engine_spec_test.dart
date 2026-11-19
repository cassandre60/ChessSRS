import 'package:chess_srs/src/model/engine/engine_slot.dart';
import 'package:chess_srs/src/model/engine/engine_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multistockfish/multistockfish.dart';

void main() {
  group('StockfishSpec', () {
    test('light constructor sets slot, flavor, and null nnuePath', () {
      const spec = StockfishSpec.light();
      expect(spec.slot, EngineSlot.sfLight);
      expect(spec.flavor, StockfishFlavor.light);
      expect(spec.nnuePath, isNull);
      expect(spec.label, StockfishFlavor.light.name);
      expect(spec.toString(), 'StockfishSpec(${StockfishFlavor.light.name})');
    });

    test('latest constructor sets slot, flavor, and nnuePath', () {
      const spec = StockfishSpec.latest(nnuePath: '/tmp/nn-abc.nnue');
      expect(spec.slot, EngineSlot.sfLatest);
      expect(spec.flavor, StockfishFlavor.latestNoNNUE);
      expect(spec.nnuePath, '/tmp/nn-abc.nnue');
      expect(spec.label, StockfishFlavor.latestNoNNUE.name);
    });

    test('fairy constructor sets slot, flavor, and null nnuePath', () {
      const spec = StockfishSpec.fairy();
      expect(spec.slot, EngineSlot.fairy);
      expect(spec.flavor, StockfishFlavor.variant);
      expect(spec.nnuePath, isNull);
      expect(spec.label, StockfishFlavor.variant.name);
    });

    test('equality and hashCode depend on slot and nnuePath', () {
      const a = StockfishSpec.latest(nnuePath: '/a.nnue');
      const b = StockfishSpec.latest(nnuePath: '/a.nnue');
      const c = StockfishSpec.latest(nnuePath: '/b.nnue');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));

      expect(const StockfishSpec.light(), equals(const StockfishSpec.light()));
      expect(const StockfishSpec.fairy(), equals(const StockfishSpec.fairy()));
      expect(const StockfishSpec.light(), isNot(equals(const StockfishSpec.fairy())));
    });
  });

  group('Lc0Spec', () {
    test('has lc0 slot and label', () {
      const spec = Lc0Spec();
      expect(spec.slot, EngineSlot.lc0);
      expect(spec.label, 'lc0');
      expect(spec.toString(), 'Lc0Spec()');
    });

    test('all instances are equal and share hashCode', () {
      const a = Lc0Spec();
      const b = Lc0Spec();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, (Lc0Spec).hashCode);
    });
  });

  test('different spec types are not equal', () {
    expect(const Lc0Spec(), isNot(equals(const StockfishSpec.light())));
  });
}
