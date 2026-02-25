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
      // body profile
      expect(s.bodyWidth, 1.82);
      expect(s.trunkLipHeight, 0.55);
      expect(s.bodyExtX, closeTo(0.39, 0.01));
    });

    test('쏘렌토 치수 검증', () {
      final s = TrunkSpace.sorento();
      expect(s.w, 1.05);
      expect(s.d, 1.00);
      expect(s.h, 0.77);
      expect(s.leftWheelhouse.w, 0.15);
      expect(s.leftWheelhouse.h, 0.35);
      // body profile
      expect(s.bodyWidth, 1.90);
      expect(s.trunkLipHeight, 0.58);
      expect(s.bodyExtX, closeTo(0.425, 0.01));
    });

    test('싼타페 치수 검증', () {
      final s = TrunkSpace.santafe();
      expect(s.w, 1.09);
      expect(s.d, 1.05);
      expect(s.h, 0.80);
      expect(s.leftWheelhouse.w, 0.10);
      // body profile
      expect(s.bodyWidth, 1.88);
      expect(s.trunkLipHeight, 0.56);
      expect(s.bodyExtX, closeTo(0.395, 0.01));
    });

    test('카니발 치수 검증', () {
      final s = TrunkSpace.carnival();
      expect(s.w, 1.25);
      expect(s.d, 0.85);
      expect(s.h, 0.88);
      expect(s.leftWheelhouse.w, 0.10);
      expect(s.leftWheelhouse.d, 0.30);
      expect(s.leftWheelhouse.h, 0.25);
      // body profile
      expect(s.bodyWidth, 1.95);
      expect(s.trunkLipHeight, 0.50);
      expect(s.bodyExtX, closeTo(0.35, 0.01));
    });

    test('아이오닉5 치수 검증', () {
      final s = TrunkSpace.ioniq5();
      expect(s.w, 1.00);
      expect(s.d, 0.95);
      expect(s.h, 0.73);
      expect(s.leftWheelhouse.w, 0.15);
      expect(s.leftWheelhouse.d, 0.35);
      expect(s.leftWheelhouse.h, 0.30);
      // body profile
      expect(s.bodyWidth, 1.89);
      expect(s.trunkLipHeight, 0.55);
      expect(s.bodyExtX, closeTo(0.445, 0.01));
    });

    test('아반떼 치수 검증', () {
      final s = TrunkSpace.avante();
      expect(s.w, 1.02);
      expect(s.d, 0.71);
      expect(s.h, 0.43);
      expect(s.leftWheelhouse.w, 0.05);
      expect(s.leftWheelhouse.d, 0.30);
      expect(s.leftWheelhouse.h, 0.25);
      // body profile
      expect(s.bodyWidth, 1.82);
      expect(s.trunkLipHeight, 0.45);
      expect(s.bodyExtX, closeTo(0.40, 0.01));
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
      // body profile 라운드트립
      expect(restored.bodyWidth, s.bodyWidth);
      expect(restored.trunkLipHeight, s.trunkLipHeight);
      expect(restored.roofExtension, s.roofExtension);
      expect(restored.bumperDepth, s.bumperDepth);
      expect(restored.bodyDepth, s.bodyDepth);
    });

    test('이전 포맷 JSON 역호환성', () {
      final oldJson = {
        'w': 1.0,
        'd': 0.8,
        'h': 0.7,
        'wheelhouse': {
          'left': {'w': 0.0, 'd': 0.0, 'h': 0.0},
          'right': {'w': 0.0, 'd': 0.0, 'h': 0.0},
        },
      };
      final s = TrunkSpace.fromJson(oldJson);
      expect(s.w, 1.0);
      expect(s.d, 0.8);
      expect(s.h, 0.7);
      // body profile 필드 없으면 기본값
      expect(s.bodyWidth, 1.90);
      expect(s.trunkLipHeight, 0.55);
      expect(s.roofExtension, 0.12);
      expect(s.bumperDepth, 0.07);
      expect(s.bodyDepth, 0.30);
    });
  });

  group('TrunkPreset', () {
    test('label에 차종명과 치수 포함', () {
      expect(TrunkPreset.tucson.label, contains('투싼'));
      expect(TrunkPreset.tucson.label, contains('104'));
      expect(TrunkPreset.sorento.label, contains('쏘렌토'));
      expect(TrunkPreset.santafe.label, contains('싼타페'));
      expect(TrunkPreset.santafe.label, contains('109'));
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
