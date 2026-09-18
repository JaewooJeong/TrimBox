// 장비 카탈로그 전수 검증: 물리 속성의 상식 + "이 짐 하나가 쏘렌토에 들어가는가".
//
// 단품 미적재 목록은 명시적으로 고정한다. 카탈로그나 트렁크 모델을 바꿔서 이
// 목록이 달라지면 테스트가 깨지고, 그때 아래 근거를 다시 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/gear_physics.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'packing_test_kit.dart';

/// 쏘렌토(2열 최후방)에 단품으로도 안 들어가는 장비와 그 근거.
///
/// - 270도 어닝 (수납) 200×25×20: 가장 긴 변 200cm 가 트렁크의 어느 변보다도 길다
///   → "트렁크보다 큼". 루프 장착품이라 정상.
/// - 노르디스크 아스가르드 12.6 114×37×37: 가로로는 휠하우스 사이 폭보다 길어서
///   휠하우스 뒤에만 놓을 수 있는데 거기서 테일게이트까지 남는 깊이가 37cm 가 안
///   되고, 세로(깊이 방향 114cm)로는 등받이·테일게이트 기울기 때문에 깊이가
///   모자란다. 2열을 27cm 당기면 세로로 들어간다. 이 기하 근거는 아래
///   '아스가르드가 안 들어가는 이유' 테스트가 트렁크 객체에서 직접 확인한다.
const Map<String, String> kExpectedUnfitAlone = {
  '270도 어닝 (수납)': '트렁크보다 큼',
  '노르디스크 아스가르드 12.6': '빈 자리 없음',
};

/// 쿨러 서브카테고리지만 아이스박스가 아닌 것 (기어 박스) — access 예외
const Set<String> kCoolerCategoryNonCoolers = {'예티 로드아웃 GoBox 30'};

void main() {
  final catalog = gearCatalog();
  final sorento = TrunkSpace.sorento();

  group('카탈로그 기본', () {
    test('항목 수·라벨 유일·치수 양수', () {
      expect(catalog.length, greaterThanOrEqualTo(190));
      final labels = <String>{};
      for (final c in catalog) {
        expect(labels.add(c.label), isTrue, reason: '라벨 중복: ${c.label}');
        expect(c.label.trim(), isNotEmpty);
        expect(c.w > 0 && c.d > 0 && c.h > 0, isTrue, reason: c.label);
        expect(['camping', 'carrier', 'moving', 'custom'], contains(c.category));
        if (c.category == 'camping') {
          expect(c.subCategory, isNotNull, reason: '${c.label}: 캠핑 장비는 서브카테고리 필수');
        }
      }
    });

    test('추천 세트 3종의 모든 라벨이 카탈로그에 있다', () {
      final bundles = gearBundles();
      expect(bundles.length, 3);
      final labels = catalog.map((c) => c.label).toSet();
      for (final b in bundles) {
        expect(b.itemLabels, isNotEmpty);
        for (final l in b.itemLabels) {
          expect(labels, contains(l), reason: '${b.name}: $l');
        }
        expect(bundleBoxes(b).length, b.itemLabels.length);
      }
    });

    test('gearOverrides 의 모든 키가 카탈로그 라벨과 일치한다 (오타 = 조용한 추정치 폴백)', () {
      final labels = catalog.map((c) => c.label).toSet();
      final orphans = [
        for (final k in gearOverrides.keys)
          if (!labels.contains(k)) k
      ];
      expect(orphans, isEmpty, reason: '카탈로그에 없는 override: $orphans');
    });
  });

  group('물리 속성 (gearPhysicsFor) 전수', () {
    test('무게 > 0, 연질 ⇔ 압축률 > 0, 압축률 ≤ 0.5, 밀도 상식 범위', () {
      for (final c in catalog) {
        final ph = physicsOf(c);
        expect(ph.weightKg, greaterThan(0), reason: c.label);
        expect(ph.weightKg, lessThan(80), reason: '${c.label}: 혼자 못 드는 무게');
        expect(ph.compress, inInclusiveRange(0, 0.5), reason: c.label);
        if (ph.soft) {
          expect(ph.compress, greaterThan(0), reason: '${c.label}: 연질인데 압축률 0');
        } else {
          expect(ph.compress, 0, reason: '${c.label}: 강체인데 압축률 > 0');
        }
        // 물(1kg/L)보다 무거운 캠핑 짐은 철판류뿐이다. 3kg/L 은 어떤 경우에도 오류.
        final liters = c.w * c.d * c.h / 1000.0;
        expect(ph.weightKg / liters, lessThan(3.0), reason: '${c.label}: 밀도 과대');
      }
    });

    test('쿨러·냉장고는 세워서 + 자주 꺼냄', () {
      final coolers = catalog.where((c) =>
          (c.subCategory == 'cooler' && !kCoolerCategoryNonCoolers.contains(c.label)) ||
          c.label.contains('냉장고') ||
          c.label.contains('아이스박스'));
      expect(coolers.length, greaterThanOrEqualTo(15));
      for (final c in coolers) {
        final ph = physicsOf(c);
        expect(ph.upright, isTrue, reason: '${c.label}: 눕히면 안 된다');
        expect(ph.access, isTrue, reason: '${c.label}: 자주 꺼내는 짐');
      }
    });

    test('gearBox 는 앱(_addBoxes)과 같은 필드 매핑을 쓴다', () {
      for (final c in catalog.take(40)) {
        final ph = physicsOf(c);
        final b = gearBox('x', c);
        expect(b.keepUpright, ph.upright);
        expect(b.soft, ph.soft);
        expect(b.compressibility, ph.compress);
        expect(b.weightKg, ph.weightKg);
        expect(b.accessPriority, ph.access);
        expect(b.w, closeTo(c.w / 100, 1e-12));
        // toItemFields 가 물리 키를 모두 낸다 (표시용 키가 더 있어도 된다)
        final fields = ph.toItemFields();
        expect(fields.keys, containsAll(['weight', 'soft', 'compress', 'upright', 'access']));
        expect(fields['weight'], ph.weightKg);
        expect(fields['upright'], ph.upright);
      }
    });
  });

  group('단품 적재 판정', () {
    late Map<String, AutoLayoutResult> alone;
    late Map<String, TrimBox> boxes;

    setUpAll(() {
      alone = {};
      boxes = {};
      for (final c in catalog) {
        final b = gearBox('solo', c);
        boxes[c.label] = b;
        alone[c.label] = AutoLayoutEngine.computeLayout(sorento, [b]);
      }
    });

    test('모든 항목: 유효하게 놓이거나, 말이 되는 사유와 함께 미적재', () {
      for (final c in catalog) {
        final r = alone[c.label]!;
        expectPackingInvariants(sorento, [boxes[c.label]!], r, ctx: c.label);
        if (r.allBoxesFit) {
          final p = r.placements.single;
          expect(p.y, 0, reason: '${c.label}: 혼자면 바닥');
          expect(p.squashed, isFalse, reason: '${c.label}: 빈 트렁크에서 눌릴 이유가 없다');
        } else {
          final reason = r.unfitReasons['solo']!;
          expect(reason, isNot(contains('남은 부피 부족')),
              reason: '${c.label}: 빈 트렁크에서 부피 부족은 말이 안 된다');
        }
      }
    });

    test('단품 미적재 목록은 정확히 기대 목록과 같다', () {
      final unfit = {
        for (final c in catalog)
          if (!alone[c.label]!.allBoxesFit) c.label: alone[c.label]!.unfitReasons['solo']!
      };
      expect(unfit.keys.toSet(), kExpectedUnfitAlone.keys.toSet(),
          reason: '실제 미적재: $unfit');
      for (final e in kExpectedUnfitAlone.entries) {
        expect(unfit[e.key], contains(e.value), reason: e.key);
      }
      expect(unfit['270도 어닝 (수납)'], contains('200'), reason: '사유에 치수가 보여야 한다');
    });

    test('아스가르드가 안 들어가는 이유를 트렁크 형상에서 직접 확인한다', () {
      final c = catalog.firstWhere((c) => c.label == '노르디스크 아스가르드 12.6');
      final dims = [c.w, c.d, c.h].map((v) => v / 100).toList()..sort();
      final long = dims[2], thick = dims[1]; // 1.14, 0.37 (눕혀도 세워도 단면 37×37)
      final wh = sorento.leftWheelhouse;
      // 가로: 휠하우스 사이에는 안 들어가고 휠하우스 위(지지 50% 미만)에도 못 얹는다
      expect(long, greaterThan(sorento.floorWidthBetweenWheelhouses));
      expect(long, lessThan(sorento.w), reason: '폭 자체는 들어간다');
      expect((wh.w + sorento.rightWheelhouse.w) / long, lessThan(0.5));
      // 휠하우스 뒤 ~ 테일게이트 닫힘 한계 사이 깊이가 단면보다 얕다
      final behind = sorento.rearDepthAt(thick) - wh.zEnd;
      expect(behind, lessThan(thick - 0.005), reason: '휠하우스 뒤 깊이 $behind');
      // 세로: 등받이~테일게이트 깊이가 길이보다 짧다
      final lengthwise = sorento.rearDepthAt(thick) - sorento.frontDepthAt(thick);
      expect(lengthwise, lessThan(long - 0.01));
      // 2열을 끝까지 당기면 세로로 들어간다
      final s27 = TrunkSpace.sorento(seatSlide: sorentoSeatSlideMax);
      expect(s27.rearDepthAt(thick) - s27.frontDepthAt(thick), greaterThan(long));
    });

    test('7인승(3열 접음)은 5인승과 같은 판정', () {
      final s7 = TrunkSpace.sorento7();
      for (final c in catalog) {
        final r = AutoLayoutEngine.computeLayout(s7, [gearBox('solo', c)]);
        expect(r.allBoxesFit, alone[c.label]!.allBoxesFit, reason: c.label);
      }
    });

    test('2열을 27cm 당기면 어닝만 남는다 (당겨서 판정이 나빠지는 항목 없음)', () {
      final s27 = TrunkSpace.sorento(seatSlide: sorentoSeatSlideMax);
      final unfit = <String>[];
      for (final c in catalog) {
        final b = gearBox('solo', c);
        final r = AutoLayoutEngine.computeLayout(s27, [b]);
        expectPackingInvariants(s27, [b], r, ctx: '+27 ${c.label}');
        if (!r.allBoxesFit) unfit.add(c.label);
      }
      expect(unfit, ['270도 어닝 (수납)']);
    });

    test('개구부 통과 판정과 적재 가능성이 일치한다', () {
      final ap = sorento.aperture!;
      for (final c in catalog) {
        final b = boxes[c.label]!;
        final passes = CollisionDetector.fitsThroughAperture(b.w, b.d, b.h, ap,
            keepUpright: b.keepUpright);
        final r = alone[c.label]!;
        if (r.allBoxesFit) {
          expect(passes, isTrue, reason: '${c.label}: 놓였는데 개구부를 통과 못 한다');
          // 놓인 방향의 단면도 실제로 개구부 안에 들어온다 (높이 ≤ 개구부 높이)
          final p = r.placements.single;
          expect(p.h, lessThanOrEqualTo(ap.height + kBoundsEps), reason: c.label);
        }
        if (!passes) {
          expect(r.allBoxesFit, isFalse, reason: c.label);
          expect(r.unfitReasons['solo'], contains('개구부'), reason: c.label);
        }
      }
    });
  });

  group('개구부 통과 (fitsThroughAperture) 단위', () {
    final ap = sorento.aperture!;

    test('w·d 를 바꿔도 같은 결과, 세움 제약은 더 엄격하기만 하다', () {
      for (final (w, d, h) in [
        (1.0, 0.5, 0.3),
        (1.2, 0.3, 0.3),
        (0.3, 0.3, 1.2),
        (1.2, 1.2, 0.1),
        (0.9, 0.9, 0.85),
      ]) {
        final free = CollisionDetector.fitsThroughAperture(w, d, h, ap);
        expect(CollisionDetector.fitsThroughAperture(d, w, h, ap), free);
        final up = CollisionDetector.fitsThroughAperture(w, d, h, ap, keepUpright: true);
        if (up) expect(free, isTrue, reason: '세워서 되면 자유 방향도 된다');
      }
    });

    test('경계: 개구부 높이에 5mm 허용, 세워 싣는 짐은 기울임 여유만큼 더', () {
      // 눕혀도 되는 짐: 단면 높이 ≤ 개구부 높이 + 5mm. 40×40 단면이 안 되면 끝.
      double free(double over) => ap.height + over;
      expect(CollisionDetector.fitsThroughAperture(free(0.004), free(0.004), free(0.004), ap), isTrue);
      expect(CollisionDetector.fitsThroughAperture(free(0.006), free(0.006), free(0.006), ap), isFalse);
      // 세워서만 싣는 짐: 실내가 개구부보다 높아 윗부분을 기울여 넣는 여유가 있다
      const tilt = CollisionDetector.uprightTiltAllowance;
      expect(tilt, inInclusiveRange(0, 0.05), reason: '기울임 여유는 몇 cm 수준이어야 한다');
      expect(
          CollisionDetector.fitsThroughAperture(0.3, 0.3, ap.height + tilt + 0.004, ap,
              keepUpright: true),
          isTrue);
      expect(
          CollisionDetector.fitsThroughAperture(0.3, 0.3, ap.height + tilt + 0.006, ap,
              keepUpright: true),
          isFalse);
      // 개구부 폭보다 넓은 정사각 판은 어느 단면으로도 못 지난다
      final side = ap.bottomWidth + 0.1;
      expect(CollisionDetector.fitsThroughAperture(side, side, 0.1, ap), isFalse);
      final plate = cmBox('plate', side * 100, side * 100, 10);
      final r = AutoLayoutEngine.computeLayout(sorento, [plate]);
      expect(r.allBoxesFit, isFalse);
      expect(CollisionDetector(sorento).exceedsAperture(plate), isTrue);
    });

    test('개구부가 없는 트렁크는 통과 검사를 하지 않는다', () {
      final plain = plainTrunk(1.5, 1.5, 0.5);
      expect(CollisionDetector(plain).exceedsAperture(cmBox('p', 140, 140, 10)), isFalse);
    });
  });

  group('개구부 프레임 경계 (회귀)', () {
    test('프레임 시작면에 딱 닿은 박스는 프레임 구간이 아니다', () {
      // 폭 140 트렁크, 개구부 폭 110·프레임 두께 12cm. 폭 120 박스의 뒤 면이 프레임
      // 시작면(z = d − 0.12)에 닿기만 하고 들어가지는 않는다 → 경계 밖이 아니어야 한다.
      // (2026-09-18 오전까지는 닿는 순간 '트렁크 경계 밖' 이 됐다.)
      const ap = Aperture(bottomWidth: 1.10, topWidth: 1.05, height: 0.79, frameDepth: 0.12);
      const t = TrunkSpace(
        w: 1.40,
        d: 1.00,
        h: 0.80,
        leftWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        rightWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        aperture: ap,
      );
      const det = CollisionDetector(t);
      final frameStart = t.d - ap.frameDepth;
      final b = cmBox('wide', 120, 30, 30, x: 0.10, z: frameStart - 0.30);
      expect(det.violations(b, []), isEmpty,
          reason: '${det.describe(b, [])} — z2=${b.z + b.effectiveD} frame=$frameStart');
      expect(det.violations(b.copyWith(z: b.z - 0.01), []), isEmpty);
      // 1cm 들어가면 개구부 폭 제한을 받는다
      expect(det.violations(b.copyWith(z: b.z + 0.01), []), [CollisionKind.bounds]);
      // 자동배치도 그 자리를 찾는다 (깊이 30 슬롯이 프레임 앞에만 있다)
      final r = AutoLayoutEngine.computeLayout(t, [cmBox('wide', 120, 30, 30)]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      expectPackingInvariants(t, [r.placements.single.box], r);
    });
  });
}
