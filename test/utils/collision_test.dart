import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

void main() {
  late CollisionDetector detector;

  setUp(() {
    detector = CollisionDetector(TrunkSpace.tucson());
  });

  TrimBox makeBox({
    String id = 'a',
    double w = 0.2,
    double d = 0.2,
    double h = 0.2,
    double x = 0,
    double y = 0,
    double z = 0,
  }) =>
      TrimBox(
        id: id,
        label: id,
        w: w,
        d: d,
        h: h,
        x: x,
        y: y,
        z: z,
        color: const Color(0xFFFF0000),
      );

  group('CollisionDetector', () {
    test('겹치지 않는 두 박스', () {
      final a = makeBox(id: 'a', x: 0, z: 0);
      final b = makeBox(id: 'b', x: 0.5, z: 0.5);
      expect(detector.boxesOverlap(a, b), false);
    });

    test('겹치는 두 박스', () {
      final a = makeBox(id: 'a', x: 0, z: 0);
      final b = makeBox(id: 'b', x: 0.1, z: 0.1);
      expect(detector.boxesOverlap(a, b), true);
    });

    test('같은 ID는 겹침 아님', () {
      final a = makeBox(id: 'a', x: 0, z: 0);
      final b = makeBox(id: 'a', x: 0, z: 0);
      expect(detector.boxesOverlap(a, b), false);
    });

    test('경계 밖 박스 감지', () {
      final box = makeBox(x: 1.0, z: 1.0, w: 0.2, d: 0.2);
      // x + w = 1.2 > 1.04 (투싼)
      expect(detector.isOutOfBounds(box), true);
    });

    test('경계 내 박스 정상', () {
      final box = makeBox(x: 0.1, z: 0.1, w: 0.2, d: 0.2);
      expect(detector.isOutOfBounds(box), false);
    });

    test('왼쪽 휠하우스 겹침', () {
      // 투싼 왼쪽 휠하우스: x=[0, 0.14], z=[0, 0.40], h=0.35 (뒷축 쪽)
      final box = makeBox(x: 0, z: 0.1, w: 0.1, d: 0.1, h: 0.1);
      expect(detector.overlapsLeftWheelhouse(box), true);
    });

    test('오른쪽 휠하우스 겹침', () {
      // 투싼 오른쪽 휠하우스: x=[0.90, 1.04], z=[0, 0.40] (뒷축 쪽)
      final box = makeBox(x: 0.91, z: 0.1, w: 0.1, d: 0.1, h: 0.1);
      expect(detector.overlapsRightWheelhouse(box), true);
    });

    test('휠하우스 위 박스 (y > 휠하우스 높이) 정상', () {
      // 투싼 휠하우스 h=0.35, 박스 y=0.40 → 위에 있으므로 충돌 없음
      final box = makeBox(x: 0, z: 0.1, w: 0.1, d: 0.1, h: 0.1, y: 0.40);
      expect(detector.overlapsLeftWheelhouse(box), false);
    });

    test('findAllCollisions 경계 밖 감지', () {
      final boxes = [
        makeBox(id: 'ok1', x: 0.3, z: 0.0, w: 0.2, d: 0.2),
        makeBox(id: 'ok2', x: 0.3, z: 0.3, w: 0.2, d: 0.2),
        makeBox(id: 'oob', x: 1.0, z: 1.0, w: 0.2, d: 0.2), // 경계 밖
      ];
      final result = detector.findAllCollisions(boxes);
      expect(result.contains('oob'), true);
      expect(result.contains('ok1'), false);
      expect(result.contains('ok2'), false);
    });

    test('findAllCollisions 겹치는 두 박스 모두 감지', () {
      final boxes = [
        makeBox(id: 'a', x: 0.3, z: 0.3, w: 0.2, d: 0.2),
        makeBox(id: 'b', x: 0.4, z: 0.4, w: 0.2, d: 0.2), // a와 겹침
      ];
      final result = detector.findAllCollisions(boxes);
      expect(result.contains('a'), true);
      expect(result.contains('b'), true);
    });

    test('isOverHeight 높이 초과 감지', () {
      final box = makeBox(x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.5, y: 0.4);
      // y + h = 0.9 > space.h (0.73 투싼)
      expect(detector.isOverHeight(box), true);
    });

    test('isOverHeight 높이 내 박스 정상', () {
      final box = makeBox(x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.3, y: 0.2);
      // y + h = 0.5 <= space.h (0.73 투싼)
      expect(detector.isOverHeight(box), false);
    });

    test('hasCollision 높이 초과 시 충돌', () {
      final box = makeBox(x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.5, y: 0.5);
      expect(detector.hasCollision(box, []), true);
    });

    test('findAllCollisions 높이 초과 박스 감지', () {
      final boxes = [
        makeBox(id: 'ok', x: 0.3, z: 0.3, w: 0.2, d: 0.2, h: 0.2, y: 0),
        makeBox(id: 'tall', x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.5, y: 0.5),
      ];
      final result = detector.findAllCollisions(boxes);
      expect(result.contains('tall'), true);
      expect(result.contains('ok'), false);
    });

    test('Y축으로 분리된 박스는 충돌 아님', () {
      // 같은 XZ 위치지만 Y축으로 분리
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.2, y: 0);
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.2, y: 0.3);
      expect(detector.boxesOverlap(a, b), false);
    });

    test('Y축 겹치는 박스는 충돌', () {
      // 같은 XZ 위치, Y축 겹침
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.2, y: 0);
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, w: 0.2, d: 0.2, h: 0.2, y: 0.1);
      expect(detector.boxesOverlap(a, b), true);
    });

    test('높이 경계값: y+h == 천장높이 (정확히 동일 시 초과 아님)', () {
      // 투싼 h=0.73, ceilingDrop=0.08
      // z=0.91(개구부)에서 천장높이 = 0.73 (drop 없음)
      final box = makeBox(x: 0.1, z: 0.91, w: 0.2, d: 0.0, h: 0.73, y: 0);
      expect(detector.isOverHeight(box), false);
    });

    test('높이 경계값: 천장 낮은 곳에서 초과 감지', () {
      // z=0(깊은 곳)에서 천장높이 = 0.73 - 0.08 = 0.65
      final box = makeBox(x: 0.1, z: 0.0, w: 0.2, d: 0.1, h: 0.66, y: 0);
      expect(detector.isOverHeight(box), true);
    });

    test('3D AABB 경계 접촉 (touching but not overlapping)', () {
      // a: x=[0, 0.2], b: x=[0.2, 0.4] → touching at x=0.2, not overlapping
      final a = makeBox(id: 'a', x: 0, z: 0, w: 0.2, d: 0.2, h: 0.2);
      final b = makeBox(id: 'b', x: 0.2, z: 0, w: 0.2, d: 0.2, h: 0.2);
      expect(detector.boxesOverlap(a, b), false);
    });

    test('빈 휠하우스(w=0, d=0, h=0) 시 충돌 없음', () {
      final emptySpace = TrunkSpace.custom(w: 1.0, d: 1.0, h: 0.5);
      final emptyDetector = CollisionDetector(emptySpace);
      final box = makeBox(x: 0, z: 0.8, w: 0.1, d: 0.1, h: 0.1);
      expect(emptyDetector.overlapsLeftWheelhouse(box), false);
      expect(emptyDetector.overlapsRightWheelhouse(box), false);
    });
  });

  group('쏘렌토 실측 형상: 테일게이트·등받이·개구부', () {
    final sorento = TrunkSpace.sorento();
    final det = CollisionDetector(sorento);

    TrimBox at({double x = 0.3, double y = 0, double z = 0, double w = 0.4,
            double d = 0.3, double h = 0.3, bool upright = false}) =>
        TrimBox(
            id: 't', label: 't', w: w, d: d, h: h, x: x, y: y, z: z,
            color: const Color(0xFF00FF00), keepUpright: upright);

    test('짐 윗면 높이의 닫힘 한계까지 붙이면 닫힌다', () {
      final b = at(z: sorento.rearDepthAt(0.30) - 0.30, d: 0.30, h: 0.30);
      expect(det.blocksTailgate(b), isFalse);
      expect(det.violations(b, []), isEmpty);
      // 바닥선까지 밀어붙이면 하부 트림 기울기(약 3cm)만큼 걸린다
      final flush = at(z: sorento.d - 0.30, d: 0.30, h: 0.30);
      expect(det.blocksTailgate(flush), isTrue);
      expect(det.tailgateOverhang(flush), closeTo(sorento.rearInsetAt(0.30), 1e-9));
    });

    test('허리선 위로 올라온 짐이 테일게이트 바닥선에 붙으면 문이 안 닫힌다', () {
      final b = at(z: sorento.d - 0.30, d: 0.30, h: 0.70);
      expect(det.blocksTailgate(b), isTrue);
      expect(det.tailgateOverhang(b), closeTo(sorento.rearInsetAt(0.70), 1e-9));
      expect(det.violations(b, []), contains(CollisionKind.tailgate));
      expect(det.describe(b, []).join(), contains('테일게이트 닫힘 불가'));
      // 프로필만큼 앞으로 당기면 닫힌다
      final ok = at(z: sorento.rearDepthAt(0.70) - 0.30, d: 0.30, h: 0.70);
      expect(det.blocksTailgate(ok), isFalse);
    });

    test('tailgateBlockers 는 걸리는 박스만 돌려준다', () {
      final a = at(z: sorento.d - 0.30, d: 0.30, h: 0.70)..label = 'a';
      final b = at(z: 0.3, d: 0.30, h: 0.70);
      final blockers = det.tailgateBlockers([a, b.copyWith(id: 'b')]);
      expect(blockers, {'t'});
    });

    test('키 큰 짐을 등받이에 바짝 붙이면 등받이 기울기에 걸린다', () {
      final b = at(z: 0, h: 0.60);
      expect(det.hitsSeatBack(b), isTrue);
      expect(det.violations(b, []), contains(CollisionKind.seatBack));
      final ok = at(z: sorento.frontInsetAt(0.60), h: 0.60);
      expect(det.hitsSeatBack(ok), isFalse);
      // 낮은 짐은 거의 붙일 수 있다
      final low = at(z: 0.02, h: 0.05);
      expect(det.hitsSeatBack(low), isFalse);
    });

    test('개구부: 어떤 방향으로도 못 지나가는 짐만 걸린다', () {
      final ap = sorento.aperture!;
      // 120×90×85 — 두 작은 변(85, 90)도 개구부 폭×높이(110×79)를 못 지남
      expect(det.exceedsAperture(at(w: 1.20, d: 0.90, h: 0.85)), isTrue);
      // 세워야 하는 쿨러: 높이 0.85 는 개구부 높이 초과 → 못 넣음
      expect(det.exceedsAperture(at(w: 0.6, d: 0.4, h: 0.85, upright: true)), isTrue);
      // 같은 치수라도 눕힐 수 있으면 통과
      expect(det.exceedsAperture(at(w: 0.6, d: 0.4, h: 0.85)), isFalse);
      // 긴 테이블(120×60×5)은 길이 방향으로 들어간다
      expect(det.exceedsAperture(at(w: 1.20, d: 0.60, h: 0.05)), isFalse);
      expect(CollisionDetector.fitsThroughAperture(1.09, 0.5, 0.5, ap), isTrue);
    });

    test('개구부 프레임 구간에서는 폭이 개구부로 제한된다', () {
      // 프레임 밖(z 작음)에서는 최대 폭 1.38 까지 놓을 수 있다
      final wide = at(x: 0.0, z: 0.6, w: 1.36, d: 0.2, h: 0.2);
      expect(det.isOutOfBounds(wide), isFalse);
      // 프레임 구간(z ≥ d − 0.12)에서는 1.10 을 넘으면 경계 밖
      final wideRear = at(x: 0.0, z: sorento.d - 0.2, w: 1.36, d: 0.2, h: 0.2);
      expect(det.isOutOfBounds(wideRear), isTrue);
      final fitsRear = at(x: (sorento.w - 1.08) / 2, z: sorento.d - 0.2, w: 1.08, d: 0.2, h: 0.2);
      expect(det.isOutOfBounds(fitsRear), isFalse);
    });

    test('천장 초과는 실내 천장 기준, 테일게이트 쪽 제한은 tailgate 로 보고', () {
      final tall = at(z: 0.3, h: 0.85);
      expect(det.isOverHeight(tall), isTrue);
      final rear = at(z: sorento.d - 0.30, d: 0.30, h: 0.60);
      final v = det.violations(rear, []);
      expect(v, contains(CollisionKind.tailgate));
      expect(v, isNot(contains(CollisionKind.ceiling)));
    });
  });
}
