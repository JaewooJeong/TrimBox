// CollisionDetector 내부 일관성: 같은 규칙을 세 군데(hasCollision / violations /
// findAllCollisions)에서 각각 구현하고 있으므로 서로 어긋나지 않는지 무작위로 본다.
// + 허용 오차 경계(5mm boundsTol, 0.5mm overlapTol) + 트렁크 밖에 세워 둔 짐.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

import 'packing_test_kit.dart';

/// 1mm 격자 난수 (경계값과 우연히 1e-6 이내로 겹치지 않게)
double mm(math.Random rnd, double lo, double hi) {
  final a = (lo * 1000).round(), b = (hi * 1000).round();
  if (b <= a) return a / 1000;
  return (a + rnd.nextInt(b - a + 1)) / 1000;
}

/// 구역별 무작위 박스: 안쪽 / 밖 / 겹침 / 테일게이트 쐐기 / 등받이 쐐기 /
/// 개구부 프레임 / 트렁크 밖 주차 / 천장 / 휠하우스
List<TrimBox> zoneBoxes(math.Random rnd, TrunkSpace t, int n) {
  final out = <TrimBox>[];
  for (var i = 0; i < n; i++) {
    final w = mm(rnd, 0.05, 0.5), d = mm(rnd, 0.05, 0.4), h = mm(rnd, 0.03, 0.4);
    var x = mm(rnd, 0, math.max(0, t.w - w));
    var y = rnd.nextBool() ? 0.0 : mm(rnd, 0, math.max(0, t.h - h));
    var z = mm(rnd, 0, math.max(0, t.d - d));
    final frame = t.aperture?.frameDepth ?? 0.1;
    switch (i % 9) {
      case 0: // 안쪽 (그대로)
        break;
      case 1: // 밖
        x = rnd.nextBool() ? -mm(rnd, 0.001, 0.2) : t.w - w + mm(rnd, 0.001, 0.2);
        if (rnd.nextBool()) z = -mm(rnd, 0.001, 0.2);
      case 2: // 앞 박스와 겹침·맞닿음
        if (out.isNotEmpty) {
          final o = out[rnd.nextInt(out.length)];
          x = o.x + mm(rnd, -0.05, 0.05);
          y = o.y + (rnd.nextBool() ? 0 : o.effectiveH);
          z = o.z + mm(rnd, -0.05, 0.05);
        }
      case 3: // 테일게이트 쐐기: 높고 뒤쪽
        y = mm(rnd, 0.3, math.max(0.3, t.h - h));
        z = t.d - d - mm(rnd, 0, 0.3);
      case 4: // 등받이 쐐기: 높고 앞쪽
        y = mm(rnd, 0.2, math.max(0.2, t.h - h));
        z = mm(rnd, 0, 0.25);
      case 5: // 개구부 프레임 구간, 벽 가까이
        z = t.d - d - mm(rnd, 0, frame);
        x = rnd.nextBool() ? mm(rnd, 0, 0.2) : t.w - w - mm(rnd, 0, 0.2);
      case 6: // 트렁크 밖 주차 (앱은 d + 0.06)
        z = t.d + [0.06, 0.0, -0.004, 0.5][rnd.nextInt(4)];
        y = rnd.nextBool() ? 0.0 : mm(rnd, 0, 0.5);
      case 7: // 천장 근처·초과
        y = t.h - h + mm(rnd, -0.02, 0.05);
      case 8: // 휠하우스 근처
        x = rnd.nextBool() ? mm(rnd, 0, 0.2) : t.w - w - mm(rnd, 0, 0.2);
        z = t.leftWheelhouse.zStart + mm(rnd, -0.1, 0.3);
        y = rnd.nextBool() ? 0.0 : t.leftWheelhouse.h + mm(rnd, -0.01, 0.01);
    }
    final soft = rnd.nextInt(5) == 0;
    final b = cmBox('z$i', w * 100, d * 100, h * 100,
        x: x, y: y, z: z, rotY: [0, 90, 180, 270][rnd.nextInt(4)],
        soft: soft, compress: soft ? 0.4 : 0, upright: rnd.nextInt(4) == 0);
    if (soft) {
      switch (rnd.nextInt(4)) {
        case 0:
          b.squash = 0.3;
        case 1:
          b.squashW = 0.2;
        case 2:
          b.squashD = 0.4;
      }
    }
    out.add(b);
  }
  return out;
}

const _spaceKinds = {
  CollisionKind.bounds,
  CollisionKind.ceiling,
  CollisionKind.wheelhouse,
  CollisionKind.tailgate,
  CollisionKind.seatBack,
};

void main() {
  final trunks = namedTrunks();

  group('무작위 일관성', () {
    for (final e in trunks.entries) {
      test('${e.key}: hasCollision ⇔ violations, findAllCollisions = 합집합, describe 1:1', () {
        final t = e.value;
        final det = CollisionDetector(t);
        final rnd = math.Random(e.key.hashCode & 0xffff);
        final seenKinds = <CollisionKind>{};
        var clean = 0;
        for (var iter = 0; iter < 60; iter++) {
          final all = zoneBoxes(rnd, t, 3 + rnd.nextInt(16));
          final expectedColliding = <String>{};
          for (final b in all) {
            final v = det.violations(b, all);
            seenKinds.addAll(v);
            // 다른 짐이 없을 때의 판정 (트렁크 자체와의 충돌만)
            final alone = det.violations(b, const []);
            expect(det.hasCollision(b, const []), alone.isNotEmpty);
            expect(alone, [for (final k in v) if (k != CollisionKind.overlap) k]);
            if (alone.isEmpty) clean++;
            expect(det.hasCollision(b, all), v.isNotEmpty,
                reason: '${e.key} iter=$iter ${snapshot(b)} → $v');
            if (v.isNotEmpty) expectedColliding.add(b.id);
            expect(v.toSet().length, v.length, reason: '사유 중복: $v');

            // describe: 사유 하나당 문장 하나, 예외 없음, 비어 있지 않음
            final msgs = det.describe(b, all);
            expect(msgs.length, v.length, reason: '$v vs $msgs');
            for (final m in msgs) {
              expect(m.trim(), isNotEmpty);
              expect(m, isNot(contains('NaN')));
              expect(m, isNot(contains('Infinity')));
            }
            for (final k in v) {
              expect(k.label.trim(), isNotEmpty);
            }

            // 개별 술어와 사유의 대응
            expect(v.contains(CollisionKind.bounds), det.isOutOfBounds(b));
            expect(v.contains(CollisionKind.ceiling), det.isOverHeight(b));
            expect(v.contains(CollisionKind.wheelhouse),
                det.overlapsLeftWheelhouse(b) || det.overlapsRightWheelhouse(b));
            expect(v.contains(CollisionKind.tailgate), det.blocksTailgate(b));
            expect(v.contains(CollisionKind.seatBack), det.hitsSeatBack(b));
            expect(v.contains(CollisionKind.aperture), det.exceedsAperture(b));
            expect(v.contains(CollisionKind.overlap),
                all.any((o) => det.boxesOverlap(b, o)));

            // 모델이 없는 트렁크는 그 사유를 내지 않는다
            if (!t.hasTailgateModel) {
              expect(v, isNot(contains(CollisionKind.tailgate)));
              expect(det.tailgateOverhang(b), 0);
            }
            if (t.frontProfile == null) {
              expect(v, isNot(contains(CollisionKind.seatBack)));
              expect(det.seatBackIntrusion(b), 0);
            }
            if (t.aperture == null) expect(v, isNot(contains(CollisionKind.aperture)));

            // 트렁크 밖(z ≥ d − 5mm)에 세워 둔 짐: 문을 막지도, 등받이에 걸리지도 않는다
            if (b.z >= t.d - CollisionDetector.boundsTol) {
              expect(det.blocksTailgate(b), isFalse);
              expect(det.hitsSeatBack(b), isFalse);
              expect(det.tailgateOverhang(b), 0);
              expect(det.seatBackIntrusion(b), 0);
            }

            // 독립 오라클과의 대조 (공간 사유만)
            final oracle = pointOracleViolations(t, b);
            if (v.toSet().intersection(_spaceKinds).isEmpty) {
              expect(oracle, isEmpty,
                  reason: '${e.key} iter=$iter 판정기는 통과, 오라클은 위반: ${snapshot(b)}');
            }
            final nonWheel = oracle.where((m) => !m.contains('휠하우스'));
            if (nonWheel.isNotEmpty) {
              expect(v.toSet().intersection(_spaceKinds), isNotEmpty,
                  reason: '${e.key} iter=$iter 오라클은 위반($nonWheel), 판정기는 통과: ${snapshot(b)}');
            }
          }
          // 겹침은 대칭
          for (final a in all) {
            for (final b in all) {
              expect(det.boxesOverlap(a, b), det.boxesOverlap(b, a));
            }
            expect(det.boxesOverlap(a, a), isFalse);
          }
          expect(det.findAllCollisions(all), expectedColliding,
              reason: '${e.key} iter=$iter');
          final blockers = det.tailgateBlockers(all);
          expect(expectedColliding.containsAll(blockers), isTrue);
          expect(blockers, {for (final b in all) if (det.blocksTailgate(b)) b.id});
        }
        // 생성기가 실제로 여러 사유와 "깨끗한" 박스를 모두 만들었는지 (공허한 통과 방지)
        expect(clean, greaterThan(20), reason: '${e.key}: 유효한 박스가 너무 적다');
        expect(seenKinds, containsAll([
          CollisionKind.bounds,
          CollisionKind.ceiling,
          CollisionKind.wheelhouse,
          CollisionKind.overlap,
          if (t.hasTailgateModel) CollisionKind.tailgate,
          if (t.frontProfile != null) CollisionKind.seatBack,
        ]));
      });
    }
  });

  group('허용 오차 경계 — 직육면체 트렁크', () {
    final t = plainTrunk(1.0, 1.0, 0.8);
    final det = CollisionDetector(t);
    List<CollisionKind> v(TrimBox b) => det.violations(b, []);

    test('벽·앞뒤: 맞닿음 OK, +4mm OK, +6mm 는 경계 밖', () {
      expect(v(cmBox('r0', 40, 30, 20, x: 0.6)), isEmpty);
      expect(v(cmBox('r4', 40, 30, 20, x: 0.604)), isEmpty);
      expect(v(cmBox('r6', 40, 30, 20, x: 0.606)), [CollisionKind.bounds]);
      expect(v(cmBox('l4', 40, 30, 20, x: -0.004)), isEmpty);
      expect(v(cmBox('l6', 40, 30, 20, x: -0.006)), [CollisionKind.bounds]);
      expect(v(cmBox('f4', 40, 30, 20, z: -0.004)), isEmpty);
      expect(v(cmBox('f6', 40, 30, 20, z: -0.006)), [CollisionKind.bounds]);
      expect(v(cmBox('b0', 40, 30, 20, z: 0.7)), isEmpty);
      expect(v(cmBox('b4', 40, 30, 20, z: 0.704)), isEmpty);
      expect(v(cmBox('b6', 40, 30, 20, z: 0.706)), [CollisionKind.bounds]);
    });

    test('천장: 맞닿음 OK, +4mm OK, +6mm 는 천장 초과', () {
      expect(v(cmBox('c0', 40, 30, 20, y: 0.6)), isEmpty);
      expect(v(cmBox('c4', 40, 30, 20, y: 0.604)), isEmpty);
      expect(v(cmBox('c6', 40, 30, 20, y: 0.606)), [CollisionKind.ceiling]);
      // 눌린 연질 짐은 실제 높이로 본다
      final bag = cmBox('bag', 40, 30, 100, soft: true, compress: 0.4)..squash = 0.25;
      expect(bag.effectiveH, closeTo(0.75, 1e-12));
      expect(v(bag), isEmpty);
    });

    test('박스끼리: 맞닿음·0.4mm 겹침은 OK, 0.6mm 겹침은 충돌 (세 축 모두)', () {
      final a = cmBox('a', 40, 30, 20);
      for (final (dx, dy, dz) in [(1, 0, 0), (0, 1, 0), (0, 0, 1)]) {
        TrimBox next(double overlapM) => cmBox('b', 40, 30, 20,
            x: dx * (0.4 - overlapM), y: dy * (0.2 - overlapM), z: dz * (0.3 - overlapM));
        expect(det.boxesOverlap(a, next(0)), isFalse, reason: '맞닿음 축 $dx$dy$dz');
        expect(det.boxesOverlap(a, next(0.0004)), isFalse, reason: '0.4mm 축 $dx$dy$dz');
        expect(det.boxesOverlap(a, next(0.0006)), isTrue, reason: '0.6mm 축 $dx$dy$dz');
        expect(det.findAllCollisions([a, next(0.0006)]), {'a', 'b'});
        expect(det.findAllCollisions([a, next(0.0004)]), isEmpty);
      }
      // 같은 id 는 자기 자신으로 본다
      expect(det.boxesOverlap(a, cmBox('a', 40, 30, 20)), isFalse);
    });

    test('회전(90/270)한 박스는 폭·깊이를 바꿔서 판정한다', () {
      final b = cmBox('rot', 90, 20, 20, x: 0.75, rotY: 90); // 실제 폭 20, 깊이 90
      expect(b.effectiveW, closeTo(0.2, 1e-12));
      expect(v(b), isEmpty);
      b.rotY = 0;
      expect(v(b), [CollisionKind.bounds]);
      b.rotY = 270;
      expect(v(b), isEmpty);
      b
        ..rotY = 90
        ..z = 0.2;
      expect(v(b), [CollisionKind.bounds], reason: '깊이 90 이 뒤로 나간다');
    });
  });

  group('허용 오차 경계 — 쏘렌토 형상', () {
    final t = TrunkSpace.sorento();
    final det = CollisionDetector(t);

    test('테일게이트: 윗면 높이의 닫힘 한계 +4mm OK, +6mm 는 닫힘 불가', () {
      for (final hCm in [20.0, 44.0, 60.0, 75.0]) {
        final limit = t.rearDepthAt(hCm / 100);
        TrimBox at(double over) =>
            cmBox('t', 30, 30, hCm, x: 0.5, z: limit - 0.3 + over);
        expect(det.blocksTailgate(at(0)), isFalse, reason: 'h=$hCm 맞닿음');
        expect(det.blocksTailgate(at(0.004)), isFalse, reason: 'h=$hCm +4mm');
        expect(det.blocksTailgate(at(0.006)), isTrue, reason: 'h=$hCm +6mm');
        expect(det.violations(at(0.006), []), contains(CollisionKind.tailgate));
        expect(det.tailgateOverhang(at(0.006)), closeTo(0.006, 1e-9));
        expect(det.describe(at(0.03), []).join(), contains('테일게이트 닫힘 불가 (+3cm'));
      }
      // 위로 갈수록 한계가 앞으로 온다 (단조)
      var prev = double.infinity;
      for (var y = 0.0; y <= t.h; y += 0.01) {
        expect(t.rearDepthAt(y), lessThanOrEqualTo(prev + 1e-12));
        prev = t.rearDepthAt(y);
      }
    });

    test('2열 등받이: 윗면 높이의 한계 −4mm OK, −6mm 는 걸림', () {
      for (final hCm in [20.0, 40.0, 60.0, 78.0]) {
        final limit = t.frontDepthAt(hCm / 100);
        TrimBox at(double into) => cmBox('s', 30, 30, hCm, x: 0.5, z: limit - into);
        expect(det.hitsSeatBack(at(0)), isFalse);
        expect(det.hitsSeatBack(at(0.004)), isFalse);
        expect(det.hitsSeatBack(at(0.006)), isTrue, reason: 'h=$hCm');
        expect(det.violations(at(0.006), []), contains(CollisionKind.seatBack));
      }
    });

    test('개구부 프레임 구간: 개구부 폭 안쪽이면 OK, 6mm 나가면 경계 밖', () {
      final ap = t.aperture!;
      const hM = 0.3;
      final left = (t.w - ap.widthAt(hM)) / 2;
      final zIn = t.rearDepthAt(hM) - 0.3; // 뒤 면이 프레임 구간 안
      expect(zIn + 0.3, greaterThan(t.d - ap.frameDepth));
      TrimBox at(double x) => cmBox('f', 30, 30, 30, x: x, z: zIn);
      expect(det.violations(at(left), []), isEmpty);
      expect(det.violations(at(left - 0.004), []), isEmpty);
      expect(det.violations(at(left - 0.006), []), [CollisionKind.bounds]);
      // 같은 x 라도 프레임 구간 앞이면 벽까지 쓸 수 있다
      final zFree = t.d - ap.frameDepth - 0.3 - 0.01;
      expect(det.violations(cmBox('g', 30, 30, 30, x: 0.0, z: zFree), []), isEmpty);
    });

    test('천장: 테일게이트 쪽으로 3cm 내려온다', () {
      final zMid = 0.4;
      final ceil = math.min(t.interiorCeilingAt(zMid), t.interiorCeilingAt(zMid + 0.2));
      TrimBox at(double over) => cmBox('c', 30, 20, 20, x: 0.5, z: zMid, y: ceil - 0.2 + over);
      expect(det.isOverHeight(at(0.004)), isFalse);
      expect(det.isOverHeight(at(0.006)), isTrue);
    });

    test('rearCeilingAt 은 rearDepthAt 의 역함수다 (프로필이 기울어진 모든 높이)', () {
      // 상수를 박지 않고 프로필에서 직접: 높이 y 의 닫힘 한계 z 에서 허용 높이는 다시 y
      final ap = t.aperture!;
      var checked = 0;
      for (var y = 0.02; y < ap.height - 0.01; y += 0.01) {
        final slope = t.rearInsetAt(y + 0.005) - t.rearInsetAt(y - 0.005);
        if (slope < 1e-6) continue; // 수직 구간은 역함수가 유일하지 않다
        final z = t.rearDepthAt(y);
        expect(t.rearCeilingAt(z), closeTo(y, 1e-6), reason: 'y=$y z=$z');
        // 그 높이·깊이에 딱 맞춘 박스는 문을 막지 않는다
        final b = cmBox('fit', 30, 30, y * 100, x: 0.5, z: z - 0.3);
        expect(det.blocksTailgate(b), isFalse, reason: 'y=$y');
        checked++;
      }
      expect(checked, greaterThan(20));
      // 어떤 깊이에서도 허용 높이는 0..h
      for (var z = 0.0; z <= t.d; z += 0.01) {
        expect(t.rearCeilingAt(z), inInclusiveRange(0, t.h));
        expect(t.ceilingHeightAt(z), lessThanOrEqualTo(t.interiorCeilingAt(z) + 1e-12));
      }
    });

    test('휠하우스: 옆·뒤·위에 맞닿으면 OK, 6mm 파고들면 충돌', () {
      final wh = t.leftWheelhouse;
      final x0 = (wh.w * 100).ceil() / 100; // 0.15 (휠하우스 폭 14.5cm)
      expect(det.violations(cmBox('side', 30, 30, 20, x: x0, z: 0.2), []), isEmpty);
      expect(det.violations(cmBox('in', 30, 30, 20, x: wh.w - 0.006, z: 0.2), []),
          contains(CollisionKind.wheelhouse));
      expect(det.violations(cmBox('behind', 30, 30, 20, x: 0.0, z: wh.zEnd), []), isEmpty);
      expect(det.violations(cmBox('behindIn', 30, 30, 20, x: 0.0, z: wh.zEnd - 0.006), []),
          contains(CollisionKind.wheelhouse));
      // 위: 등받이 기울기(높이 45cm 에서 16.5cm)를 피해 z 0.2 에
      final onTop = cmBox('top', 14, 30, 10, x: 0.0, y: wh.h, z: 0.2);
      expect(det.violations(onTop, []), isEmpty, reason: '${det.describe(onTop, [])}');
      // 오른쪽도 대칭
      final right = cmBox('r', 30, 30, 20, x: t.w - x0 - 0.3, z: 0.2);
      expect(det.violations(right, []), isEmpty);
      expect(det.violations(right..x = right.x + 0.012, []),
          contains(CollisionKind.wheelhouse));
    });
  });

  group('트렁크 밖에 세워 둔 짐 (앱의 _parkUnfitBoxes: z = d + 6cm)', () {
    for (final name in ['sorento', 'sorento+27', 'tucson']) {
      test('$name: 경계 밖으로만 표시되고, 문 닫힘·등받이·실린 짐과의 겹침에 영향 없음', () {
        final t = trunks[name]!;
        final det = CollisionDetector(t);
        final loaded = cmBox('in', 60, 40, 30, x: 0.3, z: 0.3);
        expect(det.violations(loaded, []), isEmpty);
        var x = 0.0;
        final parked = <TrimBox>[];
        for (var i = 0; i < 4; i++) {
          final p = cmBox('p$i', 40, 40, 70, x: x, z: t.d + 0.06, y: i.isEven ? 0 : 0.3);
          x += 0.45;
          parked.add(p);
        }
        final all = [loaded, ...parked];
        expect(det.tailgateBlockers(all), isEmpty);
        for (final p in parked) {
          final v = det.violations(p, all);
          expect(v, contains(CollisionKind.bounds));
          expect(v, isNot(contains(CollisionKind.tailgate)));
          expect(v, isNot(contains(CollisionKind.seatBack)));
          expect(v, isNot(contains(CollisionKind.overlap)));
        }
        expect(det.findAllCollisions(all), parked.map((p) => p.id).toSet());
        expect(det.hasCollision(loaded, all), isFalse);
      });
    }

    test('경계: z = d − 5mm 부터 "밖" 으로 본다, d − 6mm 는 아직 안 (문을 막는다)', () {
      final t = TrunkSpace.sorento();
      final det = CollisionDetector(t);
      final outside = cmBox('o', 30, 30, 30, x: 0.5, z: t.d - 0.005);
      final inside = cmBox('i', 30, 30, 30, x: 0.5, z: t.d - 0.006);
      expect(det.blocksTailgate(outside), isFalse);
      expect(det.blocksTailgate(inside), isTrue);
      // 어느 쪽이든 유효한 배치는 아니다
      expect(det.hasCollision(outside, []), isTrue);
      expect(det.hasCollision(inside, []), isTrue);
    });
  });

  group('알려진 버그 (고치면 skip 을 지운다)', () {
    test('BUG-4: 바닥 아래(y < 0)로 내려간 박스는 유효하지 않다', () {
      final t = plainTrunk(1.0, 1.0, 0.8);
      final det = CollisionDetector(t);
      final sunk = cmBox('sunk', 40, 30, 20, x: 0.3, z: 0.3, y: -0.10);
      expect(det.hasCollision(sunk, []), isTrue);
      expect(det.violations(sunk, []), isNotEmpty);
    },);

    test('BUG-5: 휠하우스 앞면에 맞닿은 박스 — 모든 cm 단위 2열 슬라이드에서 충돌 아님', () {
      final bad = <String>[];
      for (var cm = 1; cm <= 27; cm++) {
        final t = TrunkSpace.sorento(seatSlide: cm / 100);
        final det = CollisionDetector(t);
        for (var dCm = 1; dCm <= cm; dCm++) {
          // 뒤 면이 휠하우스 시작면(z = slide)에 정확히 닿는 깊이 dCm 박스
          final b = cmBox('b', 10, dCm.toDouble(), 5, x: 0.0, z: (cm - dCm) / 100);
          if (det.overlapsLeftWheelhouse(b)) bad.add('slide=${cm}cm d=${dCm}cm');
        }
      }
      expect(bad, isEmpty);
    },);
  });
}
