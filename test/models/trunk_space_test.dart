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
      // body profile (visual bodyWidth for proportional rendering)
      expect(s.bodyWidth, 1.40);
      expect(s.trunkLipHeight, 0.55);
      expect(s.bodyExtX, closeTo(0.18, 0.01));
    });

    test('쏘렌토 치수 검증 (실측 기반)', () {
      final s = TrunkSpace.sorento();
      expect(s.w, 1.38);
      expect(s.d, 1.07);
      expect(s.h, 0.82);
      expect(s.leftWheelhouse.w, 0.145);
      expect(s.leftWheelhouse.h, 0.30);
      expect(s.leftWheelhouse.d, 0.69); // 폭 138 구간은 테일게이트 쪽 38cm 뿐
      expect(s.rearCeilingDrop, 0.03);
      expect(s.aperture!.height, 0.79);
      // body profile
      expect(s.bodyWidth, 1.90);
      expect(s.trunkLipHeight, 0.78);
    });

    test('쏘렌토 뒤쪽 경계 프로필: 위로 갈수록 안쪽, 개구부 위는 프레임 두께 이상', () {
      final s = TrunkSpace.sorento();
      expect(s.rearInsetAt(0), 0);
      expect(s.rearDepthAt(0), s.d);
      var prev = 0.0;
      for (var y = 0.0; y <= s.h + 1e-9; y += 0.02) {
        final inset = s.rearInsetAt(y);
        expect(inset, greaterThanOrEqualTo(prev - 1e-12), reason: 'y=$y');
        prev = inset;
      }
      expect(s.rearInsetAt(0.48), closeTo(0.03, 1e-9));
      expect(s.rearInsetAt(0.79), closeTo(0.18, 1e-9));
      expect(s.rearInsetAt(s.h), greaterThanOrEqualTo(s.aperture!.frameDepth));
      // 역함수: 테일게이트 바닥선에서 18cm 앞이면 개구부 상단 높이까지
      expect(s.rearCeilingAt(s.d - 0.18), closeTo(0.79, 1e-6));
      expect(s.ceilingHeightAt(s.d - 0.18), lessThanOrEqualTo(0.79 + 1e-6));
      // 개구부 상단에 닿는 선 앞쪽은 실내 천장
      expect(s.ceilingHeightAt(0.3), closeTo(s.interiorCeilingAt(0.3), 1e-9));
      // 천장은 테일게이트 쪽으로 낮아진다
      expect(s.interiorCeilingAt(0), s.h);
      expect(s.interiorCeilingAt(s.d), closeTo(s.h - s.rearCeilingDrop, 1e-9));
    });

    test('쏘렌토 등받이 프로필: 위로 갈수록 뒤로, 헤드레스트 구간은 수직', () {
      final s = TrunkSpace.sorento();
      expect(s.frontInsetAt(0), 0);
      expect(s.frontInsetAt(0.30), closeTo(0.075, 1e-9));
      expect(s.frontInsetAt(0.60), closeTo(0.15, 1e-9));
      expect(s.frontInsetAt(0.80), closeTo(0.15, 1e-9));
    });

    test('개구부: 프레임 구간에서만 좁아진다', () {
      final s = TrunkSpace.sorento();
      final ap = s.aperture!;
      expect(s.xMinAt(0.5, 0.2), closeTo(0, 1e-9));
      expect(s.xMinAt(s.d, 0.0), closeTo((s.w - ap.bottomWidth) / 2, 1e-9));
      expect(s.xMinAt(s.d, ap.height), closeTo((s.w - ap.topWidth) / 2, 1e-9));
      expect(s.xMaxAt(s.d, 0.0) - s.xMinAt(s.d, 0.0), closeTo(ap.bottomWidth, 1e-9));
      // 천장 쪽 텀블홈: 프레임 밖에서도 높은 곳은 좁다
      expect(s.xMinAt(0.5, s.h), closeTo(s.ceilingNarrow, 1e-9));
    });

    test('실사용 부피는 형상 제약을 뺀 값이고 JSON 왕복 후에도 같다', () {
      final s = TrunkSpace.sorento();
      final boxVol = s.w * s.d * s.h;
      expect(s.usableVolume, lessThan(boxVol * 0.88));
      expect(s.usableVolume, greaterThan(boxVol * 0.7));
      final back = TrunkSpace.fromJson(s.toJson());
      expect(back.rearProfile!.points.length, s.rearProfile!.points.length);
      expect(back.frontProfile!.points.length, s.frontProfile!.points.length);
      expect(back.aperture!.bottomWidth, s.aperture!.bottomWidth);
      expect(back.rearCeilingDrop, s.rearCeilingDrop);
      expect(back.ceilingNarrow, s.ceilingNarrow);
      expect(back.officialVolumeLabel, s.officialVolumeLabel);
      expect(back.usableVolume, closeTo(s.usableVolume, 1e-9));
    });

    test('싼타페 치수 검증', () {
      final s = TrunkSpace.santafe();
      expect(s.w, 1.11);
      expect(s.d, 1.05);
      expect(s.h, 0.80);
      expect(s.leftWheelhouse.w, 0.13);
      // body profile
      expect(s.bodyWidth, 1.45);
      expect(s.trunkLipHeight, 0.56);
      expect(s.bodyExtX, closeTo(0.17, 0.01));
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
      expect(s.bodyWidth, 1.63);
      expect(s.trunkLipHeight, 0.50);
      expect(s.bodyExtX, closeTo(0.19, 0.01));
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
      expect(s.bodyWidth, 1.38);
      expect(s.trunkLipHeight, 0.55);
      expect(s.bodyExtX, closeTo(0.19, 0.01));
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
      expect(s.bodyWidth, 1.34);
      expect(s.trunkLipHeight, 0.45);
      expect(s.bodyExtX, closeTo(0.16, 0.01));
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
      expect(s.bodyWidth, 1.40);
      expect(s.trunkLipHeight, 0.55);
      expect(s.roofExtension, 0.12);
      expect(s.bumperDepth, 0.07);
      expect(s.bodyDepth, 0.55);
    });
  });

  group('TrunkPreset', () {
    test('label에 차종명과 치수 포함', () {
      expect(TrunkPreset.tucson.label, contains('투싼'));
      expect(TrunkPreset.tucson.label, contains('104'));
      expect(TrunkPreset.sorento.label, contains('쏘렌토'));
      expect(TrunkPreset.santafe.label, contains('싼타페'));
      expect(TrunkPreset.santafe.label, contains('111'));
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
