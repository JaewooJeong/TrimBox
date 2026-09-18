// 실제 쏘렌토 MQ4 적재 사례로 모델을 검증한다 (출처: backlog/sorento-mq4-measurements.md 6절).
// 패커의 탐색 운에 기대지 않도록, 가능한 곳은 "증인 배치"(손으로 만든 배치가 규칙을
// 통과하는지)로 검증하고, 패커 검사는 보조로 둔다.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

TrimBox box(
  String id,
  double wCm,
  double dCm,
  double hCm, {
  double x = 0,
  double y = 0,
  double z = 0,
  bool soft = false,
  double compress = 0,
  double kg = 0,
  bool upright = false,
}) =>
    TrimBox(
      id: id,
      label: id,
      w: wCm / 100,
      d: dCm / 100,
      h: hCm / 100,
      x: x,
      y: y,
      z: z,
      color: const Color(0xFF888888),
      soft: soft,
      compressibility: compress,
      weightKg: kg,
      keepUpright: upright,
    );

void expectValid(TrunkSpace trunk, List<TrimBox> boxes) {
  final det = CollisionDetector(trunk);
  for (final b in boxes) {
    expect(det.violations(b, boxes), isEmpty,
        reason: '${b.id}: ${det.describe(b, boxes)}');
    expect(SupportRule.isSupported(b, boxes.where((o) => o.id != b.id), trunk), isTrue,
        reason: '${b.id} 부양');
  }
  expect(det.tailgateBlockers(boxes), isEmpty);
}

List<TrimBox> applied(AutoLayoutResult r) {
  final out = <TrimBox>[];
  for (final p in r.placements) {
    final b = p.box.copyWith();
    p.applyTo(b);
    out.add(b);
  }
  return out;
}

void main() {
  final sorento = TrunkSpace.sorento();

  group('ADAC 실측 용량', () {
    test('2열 뒤 천장까지 980 L ↔ 모델 실사용 부피 900~1,020 L', () {
      expect(sorento.usableVolume, inInclusiveRange(0.90, 1.02));
    });

    test('음료 상자 15개: ADAC 상자 치수 미공개 — 40×30×27 이면 15개, 29 면 12개 이상', () {
      // 높이 27 이면 3단(81cm)이 되고 29 면 2단뿐이다. ADAC 는 치수를 밝히지 않았다.
      for (final (h, atLeast) in [(27.0, 15), (29.0, 12)]) {
        final crates = [for (var i = 0; i < 15; i++) box('crate$i', 40, 30, h, kg: 8)];
        final r = AutoLayoutEngine.computeLayout(sorento, crates,
            restarts: 24, budget: const Duration(seconds: 4));
        expect(r.placedCount, greaterThanOrEqualTo(atLeast),
            reason: 'h=$h: ${r.placedCount}/15 ${r.unfitReasons}');
        expectValid(sorento, applied(r));
      }
    });
  });

  group('What Car?: 기내용 캐리어 10개가 러기지 커버 아래 들어간다', () {
    test('증인 배치: 56×35×23 을 2단 × 5개, 윗면 46cm 이하', () {
      final cases = <TrimBox>[];
      for (var layer = 0; layer < 2; layer++) {
        final y = layer * 0.23;
        final zFront = layer == 0 ? 0.06 : 0.12; // 등받이 기울기만큼 뒤로
        for (var i = 0; i < 3; i++) {
          cases.add(box('f$layer$i', 35, 56, 23, x: 0.15 + i * 0.35, y: y, z: zFront));
        }
        cases.add(box('r${layer}0', 56, 35, 23, x: 0.13, y: y, z: 0.69));
        cases.add(box('r${layer}1', 56, 35, 23, x: 0.69, y: y, z: 0.69));
      }
      expect(cases.length, 10);
      expectValid(sorento, cases);
      expect(cases.map((b) => b.top).reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(0.46 + 1e-9));
    });
  });

  group('골프백 (캐디백 약 127×35×30) — MQ4 멤버스 카페 사진 후기', () {
    test('세로로는 2열을 10cm 당겨도 안 들어간다', () {
      final slid = TrunkSpace.sorento(seatSlide: 0.10);
      final det = CollisionDetector(slid);
      for (var z = 0.0; z <= slid.d - 1.27 + 0.2; z += 0.02) {
        expect(det.isOutOfBounds(box('bag', 35, 127, 30, x: 0.5, z: z)), isTrue);
      }
    });

    test('휠하우스 사이 바닥에는 가로로 안 놓인다', () {
      final det = CollisionDetector(sorento);
      for (var z = 0.1; z + 0.35 <= sorento.leftWheelhouse.zEnd; z += 0.05) {
        final b = box('bag', 127, 35, 30, x: 0.055, z: z);
        expect(det.hasCollision(b, []), isTrue, reason: 'z=$z');
      }
    });

    test('테일게이트 쪽 넓은 구간 바닥에는 가로로 놓이고, 하나 더 얹어도 문이 닫힌다', () {
      final a = box('a', 127, 35, 30, x: 0.055, z: sorento.leftWheelhouse.zEnd);
      final b = box('b', 127, 35, 30, x: 0.055, y: 0.30, z: 0.62);
      expectValid(sorento, [a, b]);
    });

    test('패커도 캐디백 하나를 놓을 자리를 찾는다 (가로, 뒤쪽)', () {
      final r = AutoLayoutEngine.computeLayout(sorento, [box('bag', 127, 35, 30, kg: 12)]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      final b = applied(r).single;
      expect(b.effectiveW, closeTo(1.27, 1e-9), reason: '가로로 놓여야 한다');
      expect(b.z, greaterThanOrEqualTo(sorento.leftWheelhouse.zEnd - 1e-9));
      expectValid(sorento, [b]);
    });

    // 실제로는 캐디백 4개가 다 실렸다 (2열 최후방, 등받이 눕힘, 문 닫힘). 모델에서는
    // 위층 깊이 예산이 1~2cm 모자라 3개까지다: 가방은 모든 축으로 조금씩 눌리고 끝이
    // 가늘지만 모델은 한 축 압축의 직육면체다. 보수적인 쪽의 오차로 기록해 둔다.
    test('캐디백 4 + 보스턴백 4 + 백팩 3: 캐디백 3개 이상·전체 10개 이상 실리고 문이 닫힌다', () {
      final gear = [
        for (var i = 0; i < 4; i++) box('caddie$i', 127, 33, 28, soft: true, compress: 0.15, kg: 12),
        for (var i = 0; i < 4; i++) box('boston$i', 48, 30, 28, soft: true, compress: 0.3, kg: 4),
        for (var i = 0; i < 3; i++) box('pack$i', 45, 30, 20, soft: true, compress: 0.3, kg: 3),
      ];
      final r = AutoLayoutEngine.computeLayout(sorento, gear,
          restarts: 24, budget: const Duration(seconds: 4));
      final placed = r.placements.map((p) => p.box.id).toSet();
      expect(placed.where((id) => id.startsWith('caddie')).length,
          greaterThanOrEqualTo(3),
          reason: '${r.placedCount}/11 미적재: ${r.unfitReasons}');
      expect(r.placedCount, greaterThanOrEqualTo(10), reason: '${r.unfitReasons}');
      expectValid(sorento, applied(r));
    });
  });

  group('캐리어·긴 짐·키 큰 짐', () {
    test('28인치 4개 + 20인치 2개가 천장까지 실린다 (7인승 3열 접음 후기)', () {
      final gear = [
        for (var i = 0; i < 4; i++) box('l$i', 52, 31, 78, kg: 20),
        for (var i = 0; i < 2; i++) box('s$i', 40, 23, 55, kg: 9),
      ];
      final r = AutoLayoutEngine.computeLayout(TrunkSpace.sorento7(), gear,
          restarts: 24, budget: const Duration(seconds: 4));
      expect(r.allBoxesFit, isTrue, reason: '${r.placedCount}/6 ${r.unfitReasons}');
      expectValid(TrunkSpace.sorento7(), applied(r));
    });

    test('134cm 캐노피 가방은 가로로 빠듯하게 들어간다', () {
      final r = AutoLayoutEngine.computeLayout(sorento, [box('canopy', 134, 25, 25, kg: 15)]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      expectValid(sorento, applied(r));
      // 140cm 는 최대 폭 138 을 넘는다
      final r2 = AutoLayoutEngine.computeLayout(sorento, [box('long', 140, 25, 25)]);
      expect(r2.allBoxesFit, isFalse);
    });

    test('80cm 난로는 입구에서 기울여 넣을 수 있고 세워 실린다, 84cm 는 안 된다', () {
      final heater = box('heater', 45, 45, 80, kg: 8, upright: true);
      final det = CollisionDetector(sorento);
      expect(det.exceedsAperture(heater), isFalse);
      final r = AutoLayoutEngine.computeLayout(sorento, [heater]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      expect(applied(r).single.h, closeTo(0.80, 1e-9));
      expectValid(sorento, applied(r));
      final tall = box('tall', 45, 45, 84, upright: true);
      expect(AutoLayoutEngine.computeLayout(sorento, [tall]).allBoxesFit, isFalse);
    });
  });

  group('2열 슬라이드 빈틈', () {
    test('당긴 만큼 생긴 빈틈 위에 통째로 놓인 작은 짐은 지지되지 않는다', () {
      final slid = TrunkSpace.sorento(seatSlide: 0.27);
      final small = box('small', 30, 18, 10, x: 0.3, z: 0.05);
      expect(SupportRule.floorSupportRatio(small, slid), 0);
      expect(SupportRule.isSupported(small, [], slid), isFalse);
      // 절반 이상 실제 바닥에 걸치면 된다
      final bridge = box('bridge', 30, 60, 10, x: 0.3, z: 0.05);
      expect(SupportRule.isSupported(bridge, [], slid), isTrue);
      // 슬라이드가 없으면 예전과 같다
      expect(SupportRule.isSupported(small, [], sorento), isTrue);
    });

    test('자동배치는 빈틈 위에 뜬 짐을 만들지 않는다', () {
      final slid = TrunkSpace.sorento(seatSlide: 0.27);
      final gear = [for (var i = 0; i < 12; i++) box('b$i', 30, 20, 15, kg: 2)];
      final r = AutoLayoutEngine.computeLayout(slid, gear);
      expect(r.allBoxesFit, isTrue);
      expectValid(slid, applied(r));
    });
  });
}
