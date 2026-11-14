import 'package:chess_srs/src/model/engine/engine_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EngineSlot', () {
    test('contains expected native engine slots', () {
      expect(EngineSlot.values, const <EngineSlot>[
        EngineSlot.sfLight,
        EngineSlot.sfLatest,
        EngineSlot.fairy,
        EngineSlot.lc0,
      ]);
    });

    test('exposes stable names', () {
      expect(EngineSlot.sfLight.name, 'sfLight');
      expect(EngineSlot.sfLatest.name, 'sfLatest');
      expect(EngineSlot.fairy.name, 'fairy');
      expect(EngineSlot.lc0.name, 'lc0');
    });
  });
}
