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
      // 투싼 왼쪽 휠하우스: x=[0, 0.14], z=[0.91-0.40, 0.91] = [0.51, 0.91], h=0.35
      final box = makeBox(x: 0, z: 0.6, w: 0.1, d: 0.1, h: 0.1);
      expect(detector.overlapsLeftWheelhouse(box), true);
    });

    test('오른쪽 휠하우스 겹침', () {
      // 투싼 오른쪽 휠하우스: x=[1.04-0.14, 1.04] = [0.90, 1.04], z=[0.51, 0.91]
      final box = makeBox(x: 0.91, z: 0.6, w: 0.1, d: 0.1, h: 0.1);
      expect(detector.overlapsRightWheelhouse(box), true);
    });

    test('휠하우스 위 박스 (y > 휠하우스 높이) 정상', () {
      // 투싼 휠하우스 h=0.35, 박스 y=0.40 → 위에 있으므로 충돌 없음
      final box = makeBox(x: 0, z: 0.6, w: 0.1, d: 0.1, h: 0.1, y: 0.40);
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
  });
}
