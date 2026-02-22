import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

/// _resolveStackingY 로직 재현 (simulator_screen.dart와 동일)
void resolveStackingY(TrimBox box, List<TrimBox> allBoxes) {
  double supportY = 0;
  final boxArea = box.effectiveW * box.effectiveD;

  for (final other in allBoxes) {
    if (other.id == box.id) continue;
    final overlapX =
        math.min(box.x + box.effectiveW, other.x + other.effectiveW) -
            math.max(box.x, other.x);
    final overlapZ =
        math.min(box.z + box.effectiveD, other.z + other.effectiveD) -
            math.max(box.z, other.z);

    if (overlapX > 0 && overlapZ > 0) {
      final overlapArea = overlapX * overlapZ;
      if (overlapArea >= boxArea * 0.5) {
        final candidateY = other.y + other.h;
        if (candidateY > supportY) supportY = candidateY;
      }
    }
  }

  box.y = supportY;
}

TrimBox makeBox({
  String id = 'a',
  double w = 0.4,
  double d = 0.3,
  double h = 0.3,
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

void main() {
  group('Y-axis stacking (resolveStackingY)', () {
    test('박스가 없으면 바닥(y=0)에 배치', () {
      final box = makeBox(id: 'a', x: 0.1, z: 0.1);
      resolveStackingY(box, [box]);
      expect(box.y, 0.0);
    });

    test('완전히 겹치는 박스 위에 스태킹', () {
      final bottom = makeBox(id: 'bottom', x: 0.1, z: 0.1, h: 0.3);
      bottom.y = 0;
      final top = makeBox(id: 'top', x: 0.1, z: 0.1, h: 0.2);

      resolveStackingY(top, [bottom, top]);
      expect(top.y, closeTo(0.3, 0.001)); // bottom.y + bottom.h
    });

    test('50% 이상 XZ 겹침 시 스태킹', () {
      // bottom: x=[0, 0.4], z=[0, 0.3] → area = 0.12
      final bottom = makeBox(id: 'bottom', x: 0, z: 0, w: 0.4, d: 0.3, h: 0.3);
      bottom.y = 0;
      // top: x=[0.1, 0.5], z=[0, 0.3] → area = 0.12
      // overlap: x=[0.1, 0.4]=0.3, z=[0,0.3]=0.3 → overlapArea=0.09
      // 0.09 / 0.12 = 75% >= 50% → stacks
      final top = makeBox(id: 'top', x: 0.1, z: 0, w: 0.4, d: 0.3, h: 0.2);

      resolveStackingY(top, [bottom, top]);
      expect(top.y, closeTo(0.3, 0.001));
    });

    test('50% 미만 XZ 겹침 시 바닥에 배치', () {
      // bottom: x=[0, 0.4], z=[0, 0.3] → area = 0.12
      final bottom = makeBox(id: 'bottom', x: 0, z: 0, w: 0.4, d: 0.3, h: 0.3);
      bottom.y = 0;
      // top: x=[0.3, 0.7], z=[0, 0.3] → area = 0.12
      // overlap: x=[0.3, 0.4]=0.1, z=[0,0.3]=0.3 → overlapArea=0.03
      // 0.03 / 0.12 = 25% < 50% → floor
      final top = makeBox(id: 'top', x: 0.3, z: 0, w: 0.4, d: 0.3, h: 0.2);

      resolveStackingY(top, [bottom, top]);
      expect(top.y, 0.0);
    });

    test('겹치지 않으면 바닥에 배치', () {
      final bottom = makeBox(id: 'bottom', x: 0, z: 0, h: 0.3);
      bottom.y = 0;
      final separate = makeBox(id: 'sep', x: 0.5, z: 0.5, h: 0.2);

      resolveStackingY(separate, [bottom, separate]);
      expect(separate.y, 0.0);
    });

    test('3단 스태킹 (A 위에 B 위에 C)', () {
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, h: 0.2);
      a.y = 0;
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, h: 0.15);
      b.y = 0.2; // A 위에

      final c = makeBox(id: 'c', x: 0.1, z: 0.1, h: 0.1);
      resolveStackingY(c, [a, b, c]);
      expect(c.y, closeTo(0.35, 0.001)); // b.y + b.h = 0.2 + 0.15
    });

    test('가장 높은 지지면 선택', () {
      final low = makeBox(id: 'low', x: 0.1, z: 0.1, h: 0.1);
      low.y = 0;
      final high = makeBox(id: 'high', x: 0.1, z: 0.1, h: 0.3);
      high.y = 0;

      final top = makeBox(id: 'top', x: 0.1, z: 0.1, h: 0.1);
      resolveStackingY(top, [low, high, top]);
      expect(top.y, closeTo(0.3, 0.001)); // high.y + high.h
    });
  });

  group('Height overflow collision', () {
    late CollisionDetector detector;

    setUp(() {
      detector = CollisionDetector(TrunkSpace.tucson());
    });

    test('스태킹 후 높이 초과 시 충돌 감지', () {
      final bottom = makeBox(id: 'bottom', x: 0.1, z: 0.1, h: 0.5);
      bottom.y = 0;
      final top = makeBox(id: 'top', x: 0.1, z: 0.1, h: 0.5);
      top.y = 0.5; // total = 1.0 > space.h (0.73 투싼)

      expect(detector.isOverHeight(top), true);
      expect(detector.isOverHeight(bottom), false);
    });

    test('스태킹 후 높이 내 정상', () {
      final bottom = makeBox(id: 'bottom', x: 0.1, z: 0.1, h: 0.3);
      bottom.y = 0;
      final top = makeBox(id: 'top', x: 0.1, z: 0.1, h: 0.3);
      top.y = 0.3; // total = 0.6 < 0.73 (투싼)

      expect(detector.isOverHeight(top), false);
    });

    test('Y축 분리된 같은 XZ 위치 박스 충돌 없음', () {
      final bottom = makeBox(id: 'bottom', x: 0.1, z: 0.1, h: 0.2);
      bottom.y = 0;
      final top = makeBox(id: 'top', x: 0.1, z: 0.1, h: 0.2);
      top.y = 0.2; // exactly on top, no overlap

      expect(detector.boxesOverlap(bottom, top), false);
    });
  });

  group('Gravity (resolveGravity)', () {
    /// _resolveGravity 로직 재현
    void resolveGravity(List<TrimBox> boxes) {
      final sorted = List<TrimBox>.from(boxes)
        ..sort((a, b) => a.y.compareTo(b.y));
      for (int i = 0; i < sorted.length; i++) {
        final box = sorted[i];
        double supportY = 0;
        final boxArea = box.effectiveW * box.effectiveD;
        for (int j = 0; j < i; j++) {
          final other = sorted[j];
          final overlapX =
              math.min(box.x + box.effectiveW, other.x + other.effectiveW) -
                  math.max(box.x, other.x);
          final overlapZ =
              math.min(box.z + box.effectiveD, other.z + other.effectiveD) -
                  math.max(box.z, other.z);
          if (overlapX > 0 && overlapZ > 0) {
            final overlapArea = overlapX * overlapZ;
            if (overlapArea >= boxArea * 0.5) {
              final candidateY = other.y + other.h;
              if (candidateY > supportY) supportY = candidateY;
            }
          }
        }
        box.y = supportY;
      }
    }

    test('지지 박스 제거 후 위 박스 바닥으로 낙하', () {
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, h: 0.2);
      a.y = 0;
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, h: 0.15);
      b.y = 0.2; // A 위에

      final boxes = [a, b];
      // A 제거
      boxes.removeWhere((box) => box.id == 'a');
      resolveGravity(boxes);

      expect(b.y, 0.0); // 바닥으로 떨어짐
    });

    test('지지 박스 이동 후 위 박스 낙하', () {
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, h: 0.2);
      a.y = 0;
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, h: 0.15);
      b.y = 0.2;

      final boxes = [a, b];
      // A를 멀리 이동 (겹침 없어짐)
      a.x = 0.8;
      resolveGravity(boxes);

      expect(b.y, 0.0); // 바닥으로 떨어짐
    });

    test('3단 스택에서 중간 제거 시 위 박스 낙하', () {
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, h: 0.2);
      a.y = 0;
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, h: 0.15);
      b.y = 0.2;
      final c = makeBox(id: 'c', x: 0.1, z: 0.1, h: 0.1);
      c.y = 0.35;

      final boxes = [a, b, c];
      // B 제거
      boxes.removeWhere((box) => box.id == 'b');
      resolveGravity(boxes);

      // C는 A 위에 안착해야 함
      expect(c.y, closeTo(0.2, 0.001)); // a.y + a.h
    });

    test('지지 박스가 아직 있으면 Y 유지', () {
      final a = makeBox(id: 'a', x: 0.1, z: 0.1, h: 0.2);
      a.y = 0;
      final b = makeBox(id: 'b', x: 0.1, z: 0.1, h: 0.15);
      b.y = 0.2;

      final boxes = [a, b];
      resolveGravity(boxes);

      expect(b.y, closeTo(0.2, 0.001)); // 변화 없음
    });
  });
}
