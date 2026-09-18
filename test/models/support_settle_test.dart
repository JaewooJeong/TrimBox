// SupportRule.settle (중력 정착) 프로퍼티 테스트.
//
// 생성 방법: 유효한 무작위 적층(S0)을 만든 뒤, 쌓은 순서대로 누적되는 양만큼
// 위로 띄운다(S1). 나중에 쌓은 짐일수록 더 많이 띄우므로 서로 겹치지 않는다.
// settle 후(S2): 종료, y 증가 없음, 부양 없음, 멱등, x·z·치수 불변.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

import '../validation/packing_test_kit.dart';

/// 유효한 무작위 적층 (충돌 0, 부양 0). 쌓은 순서대로 돌려준다.
///
/// 높이는 5cm 단위로만 만든다: 윗면이 1.5cm(heightTol) 이내로 "거의 같은" 받침은
/// 묶음 규칙에 따라 결과가 달라지므로 '거의 같은 높이의 받침' 그룹에서 따로 다룬다.
List<TrimBox> buildStack(math.Random rnd, TrunkSpace t, int n) {
  final det = CollisionDetector(t);
  final placed = <TrimBox>[];
  for (var i = 0; i < n * 4 && placed.length < n; i++) {
    final w = (10 + rnd.nextInt(45)).toDouble();
    final d = (10 + rnd.nextInt(35)).toDouble();
    final h = (5 + rnd.nextInt(6) * 5).toDouble();
    final b = cmBox('s$i', w, d, h,
        x: rnd.nextInt(((t.w - w / 100) * 100).floor().clamp(1, 1000)) / 100,
        z: rnd.nextInt(((t.d - d / 100) * 100).floor().clamp(1, 1000)) / 100);
    final levels = SupportRule.validLevels(b, placed, t)..shuffle(rnd);
    for (final level in levels) {
      b.y = level;
      // validLevels 는 바닥이 무효(2열 슬라이드 빈틈 위)여도 0 을 돌려줄 수 있으므로
      // 지지 여부를 따로 확인한다
      if (!det.hasCollision(b, placed) && SupportRule.isSupported(b, placed, t)) {
        placed.add(b);
        break;
      }
    }
  }
  return placed;
}

bool anyOverlap(CollisionDetector det, List<TrimBox> boxes) {
  for (final a in boxes) {
    for (final b in boxes) {
      if (det.boxesOverlap(a, b)) return true;
    }
  }
  return false;
}

void expectAllSupported(List<TrimBox> boxes, TrunkSpace t, String ctx) {
  for (final b in boxes) {
    expect(SupportRule.isSupported(b, boxes.where((o) => o.id != b.id), t), isTrue,
        reason: '$ctx: ${b.id} 부양 y=${b.y}');
  }
}

void main() {
  final trunks = {
    'plain': plainTrunk(1.2, 1.0, 1.5),
    'sorento': TrunkSpace.sorento(),
    'sorento+27': TrunkSpace.sorento(seatSlide: 0.27),
    'tucson': TrunkSpace.tucson(),
  };

  group('띄운 적층을 정착', () {
    for (final e in trunks.entries) {
      test('${e.key}: 종료 · y 증가 없음 · 부양 없음 · 멱등 · 겹침 없음', () {
        final t = e.value;
        final det = CollisionDetector(t);
        final rnd = math.Random(e.key.hashCode & 0xffff);
        var checked = 0, stacked = 0;
        for (var iter = 0; iter < 120; iter++) {
          final s0 = buildStack(rnd, t, 3 + rnd.nextInt(12));
          expectAllSupported(s0, t, '${e.key} iter=$iter S0');
          stacked += s0.where((b) => b.y > 0).length;

          // S1: 누적 띄우기
          final s1 = [for (final b in s0) b.copyWith()];
          var lift = 0.0;
          for (final b in s1) {
            lift += rnd.nextInt(4) == 0 ? 0 : rnd.nextInt(6) * 0.05;
            b.y += lift;
          }
          if (anyOverlap(det, s1)) continue; // 오버행 아래 있던 짐이 위 짐을 뚫은 경우
          checked++;

          final before = {for (final b in s1) b.id: b.copyWith()};
          final sw = Stopwatch()..start();
          final changed = SupportRule.settle(s1, t);
          expect(sw.elapsedMilliseconds, lessThan(2000), reason: '정착이 끝나지 않는다');

          var moved = false;
          for (final b in s1) {
            final o = before[b.id]!;
            expect(b.y, lessThanOrEqualTo(o.y + 1e-9),
                reason: '${e.key} iter=$iter ${b.id}: y 가 올라감 ${o.y} → ${b.y}');
            expect(b.y, greaterThanOrEqualTo(0));
            expect([b.x, b.z, b.w, b.d, b.h, b.rotY], [o.x, o.z, o.w, o.d, o.h, o.rotY]);
            if ((b.y - o.y).abs() > 1e-6) moved = true;
          }
          expect(changed, moved, reason: '반환값은 "하나라도 움직였는가"');
          expectAllSupported(s1, t, '${e.key} iter=$iter S2');
          expect(anyOverlap(det, s1), isFalse, reason: '${e.key} iter=$iter: 정착 후 겹침');
          for (final b in s1) {
            expect(det.overlapsLeftWheelhouse(b) || det.overlapsRightWheelhouse(b), isFalse,
                reason: '${e.key} iter=$iter ${b.id}: 휠하우스를 뚫고 내려감');
          }

          // 멱등
          final ys = [for (final b in s1) b.y];
          expect(SupportRule.settle(s1, t), isFalse);
          expect([for (final b in s1) b.y], ys);
        }
        expect(checked, greaterThan(60), reason: '겹침 없는 S1 이 너무 적다');
        expect(stacked, greaterThan(30), reason: '2층 이상이 거의 없다 (공허한 통과)');
      });
    }

    test('입력 순서와 무관하다', () {
      final t = trunks['sorento']!;
      final rnd = math.Random(5);
      for (var iter = 0; iter < 40; iter++) {
        final s0 = buildStack(rnd, t, 10);
        final a = [for (final b in s0) b.copyWith(y: b.y + 0.4)];
        final b = [for (final x in a) x.copyWith()]..shuffle(rnd);
        SupportRule.settle(a, t);
        SupportRule.settle(b, t);
        final ya = {for (final x in a) x.id: x.y};
        final yb = {for (final x in b) x.id: x.y};
        expect(yb, ya, reason: 'iter=$iter');
      }
    });

    test('빈 목록 · 한 개 · maxIterations 0', () {
      final t = trunks['plain']!;
      expect(SupportRule.settle([], t), isFalse);
      final one = cmBox('a', 30, 30, 30, y: 0.7);
      expect(SupportRule.settle([one], t, maxIterations: 0), isFalse);
      expect(one.y, 0.7);
      expect(SupportRule.settle([one], t), isTrue);
      expect(one.y, 0);
    });

    test('20단 탑도 기본 반복 횟수 안에 전부 내려온다', () {
      final t = plainTrunk(1, 1, 10);
      final tower = [
        for (var i = 0; i < 20; i++) cmBox('t$i', 40, 40, 10, x: 0.3, z: 0.3, y: i * 0.1 + 1.0 + i * 0.05),
      ];
      SupportRule.settle(tower, t);
      for (var i = 0; i < 20; i++) {
        expect(tower[i].y, closeTo(i * 0.1, 1e-9), reason: 't$i');
      }
      expectAllSupported(tower, t, 'tower');
    });
  });

  group('휠하우스 윗면 (2열 슬라이드로 zStart 이동)', () {
    for (final slide in [0.0, 0.13, 0.27]) {
      test('slide=$slide: 휠하우스 위에 절반 이상 걸치면 0.35 에, 아니면 바닥으로', () {
        final t = TrunkSpace.sorento(seatSlide: slide);
        final wh = t.leftWheelhouse;
        expect(wh.zStart, closeTo(slide, 1e-12));
        // 휠하우스 위 (폭 14cm, 휠하우스 구간 안)
        final on = cmBox('on', 14, 30, 10, x: 0.0, z: wh.zStart + 0.1, y: 0.6);
        // 오른쪽도
        final onR = cmBox('onR', 14, 30, 10, x: t.w - 0.14, z: wh.zStart + 0.1, y: 0.6);
        // 휠하우스 뒤 (zEnd 이후) 벽 쪽: 바닥까지
        final behind = cmBox('behind', 14, 20, 10, x: 0.0, z: wh.zEnd, y: 0.6);
        // 깊이의 40% 만 휠하우스 위: 지지 부족 → 바닥 (휠하우스 밖으로 비켜난 x)
        final partial = cmBox('partial', 30, 30, 10, x: 0.3, z: wh.zStart + 0.1, y: 0.6);
        final list = [on, onR, behind, partial];
        SupportRule.settle(list, t);
        expect(on.y, closeTo(wh.h, 1e-9));
        expect(onR.y, closeTo(wh.h, 1e-9));
        expect(behind.y, 0);
        expect(partial.y, 0);
        expectAllSupported(list, t, 'slide=$slide');
        if (slide > 0.1) {
          // 등받이와 휠하우스 사이(z < slide)는 2열을 당겨 생긴 빈틈이다: 휠하우스가
          // 더는 받치지 않으므로 바닥 높이까지 내려가지만, 받칠 바닥이 없어 "지지 안 됨".
          expect(t.floorStartZ, closeTo(slide, 1e-12));
          final front = cmBox('front', 14, (slide * 100).floorToDouble(), 10, x: 0.0, z: 0.0, y: 0.6);
          SupportRule.settle([front], t);
          expect(front.y, 0, reason: '슬라이드 전 휠하우스 자리(z < $slide)에는 이제 휠하우스가 없다');
          expect(SupportRule.floorSupportRatio(front, t), 0);
          expect(SupportRule.isSupported(front, [], t), isFalse, reason: '빈틈 위는 지지되지 않는다');
          // 깊이의 절반 이상이 실제 바닥(z ≥ slide)에 걸치면 지지된다
          final bridge = cmBox('bridge', 30, 60, 10, x: 0.5, z: slide - 0.2, y: 0.6);
          SupportRule.settle([bridge], t);
          expect(bridge.y, 0);
          expect(SupportRule.isSupported(bridge, [], t), isTrue);
          // 같은 짐이 슬라이드 전 트렁크에서는 휠하우스 위에 얹힌다
          final old = front.copyWith(y: 0.6);
          SupportRule.settle([old], TrunkSpace.sorento());
          expect(old.y, closeTo(wh.h, 1e-9));
        }
      });
    }

    test('휠하우스 + 같은 높이(±1.5cm) 박스가 합쳐서 50% 를 받치면 유효', () {
      final t = TrunkSpace.sorento();
      final wh = t.leftWheelhouse;
      final whW = (wh.w * 100).ceilToDouble(); // cm, 휠하우스 바로 옆 x
      // 휠하우스보다 1cm 낮은 상자를 바로 옆에 둔다
      final crate = cmBox('crate', 30, 30, wh.h * 100 - 1, x: whW / 100, z: 0.2);
      // 폭 60 판자: 휠하우스(약 14.5) + crate 30 ≈ 74% — 어느 한쪽만으로는 50% 미만
      final plank = cmBox('plank', 60, 30, 5, x: 0.0, z: 0.2, y: 0.8);
      expect(wh.w / 0.6, lessThan(0.5));
      SupportRule.settle([crate, plank], t);
      expect(plank.y, closeTo(wh.h, SupportRule.heightTol + 1e-9));
      expect(plank.y, greaterThan(0));
      expect(SupportRule.isSupported(plank, [crate], t), isTrue);
    });
  });

  group('거의 같은 높이의 받침 (heightTol 묶음)', () {
    test('윗면이 1cm 다른 두 받침 위 — 목록 순서와 무관하게 높은 쪽에 얹힌다 (회귀)', () {
      // 2026-09-18 오전까지는 층의 대표 높이가 "처음 본" 받침이라 [A, B] 순서면
      // K 가 30 에 놓여 31 짜리 B 를 1cm 파고들었다.
      final t = plainTrunk(2, 2, 1);
      TrimBox a() => cmBox('A', 50, 50, 30, x: 0.0); // 윗면 30
      TrimBox b() => cmBox('B', 50, 50, 31, x: 0.5); // 윗면 31
      TrimBox k() => cmBox('K', 100, 50, 10, x: 0.0, y: 0.8);
      final det = CollisionDetector(t);
      for (final order in [
        [a(), b(), k()],
        [b(), a(), k()],
      ]) {
        SupportRule.settle(order, t);
        final top = order.firstWhere((x) => x.id == 'K');
        expect(top.y, closeTo(0.31, 1e-9),
            reason: '${order.map((x) => x.id).join()}: K.y=${top.y}');
        expect(det.findAllCollisions(order), isEmpty,
            reason: '${order.map((x) => x.id).join()}: K 가 B 를 1cm 파고든다');
        expect(SupportRule.validLevels(k(), [order[0], order[1]], t), [0.0, closeTo(0.31, 1e-9)]);
      }
    });
  });

  group('알려진 버그 (고치면 skip 을 지운다)', () {
    test('BUG-6: 받침을 지우면 위 짐이 옆 짐을 뚫고 내려간다', () {
      // C(윗면 40) | D(윗면 20) + E(D 위, 윗면 40). 판자 K 는 C 30% + E 60% 로 40 에 있다.
      // E 를 지우면 40 층은 30% 뿐이라 무효, 20 층(D 60%)이 유효 → K 가 20 으로
      // 내려가면서 C(0~40)와 겹친다.
      final t = plainTrunk(2, 2, 1);
      final c = cmBox('C', 30, 50, 40, x: 0.0);
      final d = cmBox('D', 60, 50, 20, x: 0.4);
      final k = cmBox('K', 100, 50, 20, x: 0.0, y: 0.4);
      final list = [c, d, k]; // E 는 이미 지워진 상태
      SupportRule.settle(list, t);
      final det = CollisionDetector(t);
      expect(det.findAllCollisions(list), isEmpty,
          reason: 'K.y=${k.y}: K 와 C 가 겹친다');
    },);
  });
}
