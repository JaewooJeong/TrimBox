import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';

TrimBox box(String id, double w, double d, double h,
        {double x = 0, double y = 0, double z = 0, int rotY = 0}) =>
    TrimBox(
      id: id,
      label: id,
      w: w,
      d: d,
      h: h,
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      color: const Color(0xFF888888),
    );

void main() {
  final noWheel = TrunkSpace.custom(w: 2, d: 2, h: 1);
  final sorento = TrunkSpace.sorento();

  group('validLevels / highestLevel', () {
    test('아무것도 없으면 바닥만', () {
      final b = box('a', 0.3, 0.3, 0.2);
      expect(SupportRule.validLevels(b, [], noWheel), [0.0]);
      expect(SupportRule.highestLevel(b, [], noWheel), 0.0);
    });

    test('완전히 위에 얹으면 아래 상자 윗면이 유효 층', () {
      final base = box('base', 0.5, 0.5, 0.3);
      final top = box('top', 0.3, 0.3, 0.2, x: 0.1, z: 0.1);
      expect(SupportRule.highestLevel(top, [base], noWheel), closeTo(0.3, 1e-9));
    });

    test('절반(50%) 걸치면 유효, 그보다 적으면 무효', () {
      final base = box('base', 0.5, 0.5, 0.3);
      final half = box('h', 0.4, 0.5, 0.2, x: 0.3); // x 0.3~0.7, 겹침 0.2/0.4 = 50%
      expect(SupportRule.highestLevel(half, [base], noWheel), closeTo(0.3, 1e-9));
      final less = box('l', 0.4, 0.5, 0.2, x: 0.31); // 47.5%
      expect(SupportRule.highestLevel(less, [base], noWheel), 0.0);
    });

    test('두 상자가 합쳐서 지지하면 유효 (같은 높이 그룹)', () {
      final a = box('a', 0.3, 0.5, 0.3, x: 0.0);
      final b = box('b', 0.3, 0.5, 0.3, x: 0.7);
      // 폭 1.0 상자: a 30% + b 30% = 60%
      final top = box('t', 1.0, 0.5, 0.2);
      expect(SupportRule.highestLevel(top, [a, b], noWheel), closeTo(0.3, 1e-9));
    });

    test('높이가 다른 상자들은 합산하지 않는다', () {
      final a = box('a', 0.3, 0.5, 0.3, x: 0.0);
      final b = box('b', 0.3, 0.5, 0.2, x: 0.7);
      final top = box('t', 1.0, 0.5, 0.2);
      expect(SupportRule.highestLevel(top, [a, b], noWheel), 0.0);
    });

    test('휠하우스 윗면도 지지면이다', () {
      // 쏘렌토 왼쪽 휠하우스 윗면 높이 = leftWheelhouse.h
      final lw = sorento.leftWheelhouse;
      final small = box('s', lw.w, 0.3, 0.1, x: 0, z: 0.05);
      expect(SupportRule.highestLevel(small, [], sorento), closeTo(lw.h, 1e-9));
    });

    test('회전한 상자는 회전된 footprint 로 계산한다', () {
      final base = box('base', 0.5, 0.2, 0.3);
      final top = box('t', 0.2, 0.5, 0.2, rotY: 90); // 실제 footprint 0.5 × 0.2
      expect(SupportRule.highestLevel(top, [base], noWheel), closeTo(0.3, 1e-9));
    });
  });

  group('nearestLevel', () {
    test('현재 높이에 가장 가까운 유효 층을 고른다', () {
      final base = box('base', 0.5, 0.5, 0.3);
      final t = box('t', 0.3, 0.3, 0.2, x: 0.1, z: 0.1, y: 0.05);
      expect(SupportRule.nearestLevel(t, [base], noWheel), 0.0);
      t.y = 0.25;
      expect(SupportRule.nearestLevel(t, [base], noWheel), closeTo(0.3, 1e-9));
    });
  });

  group('supportRatio / isSupported', () {
    test('바닥은 항상 1.0', () {
      final b = box('a', 0.3, 0.3, 0.2);
      expect(SupportRule.supportRatio(b, 0, [], noWheel), 1.0);
      expect(SupportRule.isSupported(b, [], noWheel), isTrue);
    });

    test('공중에 떠 있으면 0', () {
      final b = box('a', 0.3, 0.3, 0.2, y: 0.3);
      expect(SupportRule.supportRatio(b, 0.3, [], noWheel), 0.0);
      expect(SupportRule.isSupported(b, [], noWheel), isFalse);
    });

    test('감사에서 발견된 케이스: 휠하우스 모서리에만 닿은 의자는 미지지', () {
      // 의자 x 0.08~0.93 (휠하우스 x 0~0.08과 폭 방향 겹침 0)
      final chair = box('c', 0.85, 0.20, 0.15, x: 0.08, y: 0.30, z: 0);
      expect(SupportRule.isSupported(chair, [], sorento), isFalse);
    });
  });

  group('settle (중력)', () {
    test('떠 있는 상자는 바닥으로 떨어진다', () {
      final b = box('a', 0.3, 0.3, 0.2, y: 0.5);
      final changed = SupportRule.settle([b], noWheel);
      expect(changed, isTrue);
      expect(b.y, 0.0);
    });

    test('지지 상자가 사라지면 다단 적층이 순서대로 내려온다', () {
      final base = box('base', 0.5, 0.5, 0.3);
      final mid = box('mid', 0.4, 0.4, 0.2, y: 0.3);
      final top = box('top', 0.3, 0.3, 0.2, y: 0.5);
      final list = [base, mid, top];
      SupportRule.settle(list, noWheel);
      expect(mid.y, closeTo(0.3, 1e-9));
      expect(top.y, closeTo(0.5, 1e-9));

      list.remove(base);
      SupportRule.settle(list, noWheel);
      expect(mid.y, 0.0);
      expect(top.y, closeTo(0.2, 1e-9));
    });

    test('아래 상자 위로 올라가지 않은 상자는 그대로 (바닥 유지)', () {
      final a = box('a', 0.5, 0.5, 0.3);
      final b = box('b', 0.5, 0.5, 0.3, x: 1.0);
      SupportRule.settle([a, b], noWheel);
      expect(a.y, 0.0);
      expect(b.y, 0.0);
    });

    test('정착 후 모든 상자는 isSupported', () {
      final base = box('base', 0.6, 0.6, 0.3);
      final t1 = box('t1', 0.3, 0.3, 0.2, x: 0.0, z: 0.0, y: 0.9);
      final t2 = box('t2', 0.3, 0.3, 0.2, x: 0.3, z: 0.3, y: 0.9);
      final t3 = box('t3', 0.6, 0.6, 0.2, y: 1.5);
      final list = [base, t1, t2, t3];
      SupportRule.settle(list, noWheel);
      for (final b in list) {
        final others = list.where((o) => o.id != b.id);
        expect(SupportRule.isSupported(b, others, noWheel), isTrue,
            reason: '${b.id} y=${b.y}');
      }
      expect(t3.y, closeTo(0.5, 1e-9));
    });
  });
}
