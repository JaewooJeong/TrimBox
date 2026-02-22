import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';

void main() {
  group('TrunkSpace 차종 팩토리', () {
    test('투싼 치수 검증', () {
      final s = TrunkSpace.tucson();
      expect(s.w, 1.04);
      expect(s.d, 0.91);
      expect(s.h, 0.73);
      expect(s.leftWheelhouse.w, 0.14);
      expect(s.leftWheelhouse.d, 0.40);
      expect(s.leftWheelhouse.h, 0.35);
      expect(s.rightWheelhouse.w, 0.14);
      expect(s.gridUnit, 0.01);
    });

    test('쏘렌토 치수 검증', () {
      final s = TrunkSpace.sorento();
      expect(s.w, 1.05);
      expect(s.d, 1.00);
      expect(s.h, 0.77);
      expect(s.leftWheelhouse.w, 0.15);
      expect(s.leftWheelhouse.h, 0.35);
    });

    test('싼타페 치수 검증', () {
      final s = TrunkSpace.santafe();
      expect(s.w, 1.28);
      expect(s.d, 1.05);
      expect(s.h, 0.80);
      expect(s.leftWheelhouse.w, 0.10);
    });

    test('카니발 치수 검증', () {
      final s = TrunkSpace.carnival();
      expect(s.w, 1.25);
      expect(s.d, 0.85);
      expect(s.h, 0.88);
      expect(s.leftWheelhouse.w, 0.10);
      expect(s.leftWheelhouse.d, 0.30);
      expect(s.leftWheelhouse.h, 0.25);
    });

    test('아이오닉5 치수 검증', () {
      final s = TrunkSpace.ioniq5();
      expect(s.w, 1.00);
      expect(s.d, 0.95);
      expect(s.h, 0.73);
      expect(s.leftWheelhouse.w, 0.15);
      expect(s.leftWheelhouse.d, 0.35);
      expect(s.leftWheelhouse.h, 0.30);
    });

    test('아반떼 치수 검증', () {
      final s = TrunkSpace.avante();
      expect(s.w, 1.02);
      expect(s.d, 0.71);
      expect(s.h, 0.43);
      expect(s.leftWheelhouse.w, 0.05);
      expect(s.leftWheelhouse.d, 0.30);
      expect(s.leftWheelhouse.h, 0.25);
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
      final s = TrunkSpace.tucson();
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
    test('label에 차종명과 치수 포함', () {
      expect(TrunkPreset.tucson.label, contains('투싼'));
      expect(TrunkPreset.tucson.label, contains('104'));
      expect(TrunkPreset.sorento.label, contains('쏘렌토'));
      expect(TrunkPreset.santafe.label, contains('싼타페'));
      expect(TrunkPreset.carnival.label, contains('카니발'));
      expect(TrunkPreset.ioniq5.label, contains('아이오닉5'));
      expect(TrunkPreset.avante.label, contains('아반떼'));
      expect(TrunkPreset.custom.label, '커스텀');
    });

    test('카테고리 매핑', () {
      expect(TrunkPreset.tucson.category, VehicleCategory.suv);
      expect(TrunkPreset.sorento.category, VehicleCategory.suv);
      expect(TrunkPreset.santafe.category, VehicleCategory.suv);
      expect(TrunkPreset.carnival.category, VehicleCategory.minivan);
      expect(TrunkPreset.ioniq5.category, VehicleCategory.suv);
      expect(TrunkPreset.avante.category, VehicleCategory.sedan);
      expect(TrunkPreset.custom.category, isNull);
    });

    test('toTrunkSpace 반환값 검증', () {
      for (final p in TrunkPreset.values) {
        if (p == TrunkPreset.custom) {
          expect(p.toTrunkSpace(), isNull);
        } else {
          expect(p.toTrunkSpace(), isNotNull);
        }
      }
    });

    test('volumeLiters 양수', () {
      for (final p in TrunkPreset.values) {
        if (p == TrunkPreset.custom) continue;
        expect(p.volumeLiters, isNotNull);
        expect(p.volumeLiters!, greaterThan(0));
      }
    });
  });
}
