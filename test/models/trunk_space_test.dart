import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';

void main() {
  group('TrunkSpace', () {
    test('defaultSUV 치수 검증', () {
      final s = TrunkSpace.defaultSUV();
      expect(s.w, 1.08);
      expect(s.d, 1.07);
      expect(s.h, 0.80);
      expect(s.leftWheelhouse.w, 0.18);
      expect(s.rightWheelhouse.d, 0.36);
      expect(s.gridUnit, 0.10);
    });

    test('sedan 치수 검증', () {
      final s = TrunkSpace.sedan();
      expect(s.w, 0.90);
      expect(s.d, 0.85);
      expect(s.h, 0.65);
      expect(s.leftWheelhouse.w, 0.15);
    });

    test('van 치수 검증', () {
      final s = TrunkSpace.van();
      expect(s.w, 1.30);
      expect(s.d, 1.20);
      expect(s.h, 0.90);
      expect(s.leftWheelhouse.w, 0.20);
    });

    test('custom 생성', () {
      final s = TrunkSpace.custom(
        w: 2.0,
        d: 1.5,
        h: 1.0,
        leftWheelhouse: const Wheelhouse(w: 0.1, d: 0.2, h: 0.1),
        rightWheelhouse: const Wheelhouse(w: 0.1, d: 0.2, h: 0.1),
      );
      expect(s.w, 2.0);
      expect(s.d, 1.5);
      expect(s.leftWheelhouse.w, 0.1);
    });

    test('custom 기본 휠하우스 0', () {
      final s = TrunkSpace.custom(w: 1.0, d: 1.0, h: 0.5);
      expect(s.leftWheelhouse.w, 0);
      expect(s.leftWheelhouse.d, 0);
      expect(s.rightWheelhouse.w, 0);
    });

    test('toJson/fromJson 라운드트립', () {
      final s = TrunkSpace.defaultSUV();
      final json = s.toJson();
      final restored = TrunkSpace.fromJson(json);

      expect(restored.w, s.w);
      expect(restored.d, s.d);
      expect(restored.h, s.h);
      expect(restored.leftWheelhouse.w, s.leftWheelhouse.w);
      expect(restored.rightWheelhouse.d, s.rightWheelhouse.d);
    });
  });

  group('TrunkPreset', () {
    test('label에 치수 포함', () {
      expect(TrunkPreset.suv.label, contains('108'));
      expect(TrunkPreset.sedan.label, contains('90'));
      expect(TrunkPreset.van.label, contains('130'));
      expect(TrunkPreset.custom.label, '커스텀');
    });

    test('toTrunkSpace 반환값 검증', () {
      final suv = TrunkPreset.suv.toTrunkSpace();
      expect(suv, isNotNull);
      expect(suv!.w, 1.08);

      final sedan = TrunkPreset.sedan.toTrunkSpace();
      expect(sedan, isNotNull);
      expect(sedan!.w, 0.90);

      final van = TrunkPreset.van.toTrunkSpace();
      expect(van, isNotNull);
      expect(van!.w, 1.30);
    });

    test('custom은 null 반환', () {
      expect(TrunkPreset.custom.toTrunkSpace(), isNull);
    });
  });
}
