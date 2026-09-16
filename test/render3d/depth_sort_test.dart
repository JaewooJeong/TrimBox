import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/render3d/depth_sort.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/vec3.dart';

void main() {
  group('sortBackToFront', () {
    test('앞뒤로 놓인 두 상자: 카메라에 가까운 것이 나중', () {
      final back = const Aabb(0, 0, 0.0, 0.5, 0.3, 0.3);
      final front = const Aabb(0, 0, 0.5, 0.5, 0.3, 0.8);
      final order = sortBackToFront([front, back], const Vec3(0.25, 0.5, 3));
      expect(order, [1, 0]);
    });

    test('카메라가 반대편(-z)이면 순서가 뒤집힌다', () {
      final back = const Aabb(0, 0, 0.0, 0.5, 0.3, 0.3);
      final front = const Aabb(0, 0, 0.5, 0.5, 0.3, 0.8);
      final order = sortBackToFront([front, back], const Vec3(0.25, 0.5, -3));
      expect(order, [0, 1]);
    });

    test('적층: 위에서 보면 아래 상자를 먼저 그린다', () {
      final lower = const Aabb(0, 0, 0, 0.5, 0.3, 0.5);
      final upper = const Aabb(0.1, 0.3, 0.1, 0.4, 0.6, 0.4);
      final order = sortBackToFront([upper, lower], const Vec3(0.25, 2.0, 2.0));
      expect(order, [1, 0]);
    });

    test('휠하우스 옆 상자: 상자가 카메라 쪽이면 휠하우스를 먼저 그린다', () {
      // 감사에서 확인된 버그 재현: 예전 정렬 키는 휠하우스(z 0.4)를 상자 위에 덮었다
      final wheelhouse = const Aabb(0, 0, 0, 0.08, 0.30, 0.40);
      final box = const Aabb(0.08, 0, 0, 0.5, 0.35, 0.35);
      // 카메라: 뒤쪽 중앙 (x = 0.54)
      final order = sortBackToFront([wheelhouse, box], const Vec3(0.54, 0.7, 2.5));
      expect(order, [0, 1]);
    });

    test('겹치는 상자(충돌)도 순열을 반환한다', () {
      final a = const Aabb(0, 0, 0, 1, 1, 1);
      final b = const Aabb(0.5, 0.5, 0.5, 1.5, 1.5, 1.5);
      final order = sortBackToFront([a, b], const Vec3(0, 3, 3));
      expect(order.toSet(), {0, 1});
    });

    test('무작위 비겹침 상자 30개: 순열이며 분리 평면 관계를 지킨다', () {
      final rnd = math.Random(42);
      final boxes = <Aabb>[];
      // 격자에 무작위 크기로 배치해 겹치지 않게
      for (var i = 0; i < 30; i++) {
        final gx = i % 5, gz = (i ~/ 5) % 3, gy = i ~/ 15;
        final w = 0.1 + rnd.nextDouble() * 0.15;
        final d = 0.1 + rnd.nextDouble() * 0.15;
        final h = 0.1 + rnd.nextDouble() * 0.15;
        final x = gx * 0.3, z = gz * 0.3, y = gy * 0.3;
        boxes.add(Aabb(x, y, z, x + w, y + h, z + d));
      }
      final cam = const Vec3(0.7, 1.2, 2.2);
      final order = sortBackToFront(boxes, cam);
      expect(order.length, 30);
      expect(order.toSet().length, 30);

      // 검증: i가 j보다 먼저 그려졌다면, j가 i를 가리는 것이 가능해야 하고
      // 그 반대(i가 j를 가림)는 분리 평면 기준으로 불가능해야 한다.
      final pos = List<int>.filled(30, 0);
      for (var k = 0; k < order.length; k++) {
        pos[order[k]] = k;
      }
      var violations = 0;
      for (var i = 0; i < 30; i++) {
        for (var j = i + 1; j < 30; j++) {
          final r = _separatingOrder(boxes[i], boxes[j], cam);
          if (r == 0) continue;
          final iFirst = pos[i] < pos[j];
          if ((r < 0) != iFirst) violations++;
        }
      }
      expect(violations, 0);
    });
  });
}

/// 테스트용 독립 구현: -1 = i 먼저, 1 = j 먼저, 0 = 제약 없음
/// (모든 분리축이 같은 답을 줄 때만 제약)
int _separatingOrder(Aabb a, Aabb b, Vec3 cam) {
  var verdict = 0;
  for (var axis = 0; axis < 3; axis++) {
    int r;
    if (a.maxOn(axis) <= b.minOn(axis) + 1e-9) {
      r = cam[axis] >= (a.maxOn(axis) + b.minOn(axis)) / 2 ? -1 : 1;
    } else if (b.maxOn(axis) <= a.minOn(axis) + 1e-9) {
      r = cam[axis] >= (b.maxOn(axis) + a.minOn(axis)) / 2 ? 1 : -1;
    } else {
      continue;
    }
    if (verdict == 0) {
      verdict = r;
    } else if (verdict != r) {
      return 0;
    }
  }
  return verdict;
}
