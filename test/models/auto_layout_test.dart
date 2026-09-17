import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

TrimBox box(String id, double wCm, double dCm, double hCm,
        {bool upright = false}) =>
    TrimBox(
      id: id,
      label: id,
      w: wCm / 100,
      d: dCm / 100,
      h: hCm / 100,
      color: const Color(0xFF888888),
      keepUpright: upright,
    );

/// 4인 가족 캠핑 번들 (add_box_dialog 의 프리셋 치수)
List<TrimBox> familyBundle() => [
      box('tent', 80, 35, 35),
      box('tarp', 80, 32, 32),
      box('table', 87, 19, 17),
      box('chair1', 85, 20, 15),
      box('chair2', 85, 20, 15),
      box('chair3', 85, 20, 15),
      box('chair4', 85, 20, 15),
      box('cooler', 60, 40, 42, upright: true),
      box('bag1', 43, 20, 20),
      box('bag2', 43, 20, 20),
      box('bag3', 43, 20, 20),
      box('bag4', 43, 20, 20),
      box('burner', 54, 34, 7, upright: true),
      box('cookset', 28, 23, 13, upright: true),
      box('container', 63, 41, 27, upright: true),
      box('firewood', 40, 25, 20),
    ];

/// 배치 결과를 실제 박스 사본에 적용해 돌려준다
List<TrimBox> applied(AutoLayoutResult r) {
  final out = <TrimBox>[];
  for (final p in r.placements) {
    final b = p.box.copyWith();
    p.applyTo(b);
    out.add(b);
  }
  return out;
}

/// 물리적으로 말이 되는 배치인지: 충돌 0, 부양 0, 회전은 rotY 0 으로 정규화
void expectPhysicallyValid(TrunkSpace trunk, AutoLayoutResult r) {
  final boxes = applied(r);
  final det = CollisionDetector(trunk);
  final coll = det.findAllCollisions(boxes);
  expect(coll, isEmpty, reason: '충돌: $coll');
  for (final b in boxes) {
    final others = boxes.where((o) => o.id != b.id);
    expect(SupportRule.isSupported(b, others, trunk), isTrue,
        reason: '${b.id} 부양 y=${b.y}');
    expect(b.rotY, 0);
    expect(b.x, greaterThanOrEqualTo(-1e-9));
    expect(b.z, greaterThanOrEqualTo(-1e-9));
  }
  // 적재 순서는 1..n 으로 빠짐없이
  final orders = r.placements.map((p) => p.loadOrder).toList()..sort();
  expect(orders, List.generate(orders.length, (i) => i + 1));
  // 미적재 사유는 미적재 박스마다 있다
  for (final u in r.unfitBoxes) {
    expect(r.unfitReasons[u.id], isNotNull);
  }
  expect(r.allBoxesFit, r.unfitBoxes.isEmpty);
}

void main() {
  final sorento = TrunkSpace.sorento();

  group('기본', () {
    test('빈 목록', () {
      final r = AutoLayoutEngine.computeLayout(sorento, []);
      expect(r.placements, isEmpty);
      expect(r.allBoxesFit, isTrue);
      expect(r.utilizationPercent, 0);
    });

    test('박스 하나는 바닥, 뒷좌석 쪽 구석에', () {
      final r = AutoLayoutEngine.computeLayout(sorento, [box('a', 40, 30, 20)]);
      expect(r.placements.length, 1);
      final p = r.placements.single;
      expect(p.y, 0);
      expect(p.z, lessThan(0.05));
      expectPhysicallyValid(sorento, r);
    });

    test('트렁크보다 큰 박스는 사유와 함께 미적재', () {
      final r = AutoLayoutEngine.computeLayout(sorento, [box('huge', 200, 50, 50)]);
      expect(r.placements, isEmpty);
      expect(r.unfitBoxes.length, 1);
      expect(r.unfitReasons['huge'], contains('트렁크보다 큼'));
    });

    test('세워서만 두는 박스는 눕히지 않는다', () {
      // 높이 90cm 는 천장(78cm)을 넘지만 눕히면 들어간다
      final upright = box('tall', 30, 30, 90, upright: true);
      final r1 = AutoLayoutEngine.computeLayout(sorento, [upright]);
      expect(r1.placements, isEmpty);
      expect(r1.unfitReasons['tall'], contains('천장'));

      final free = box('tall2', 30, 30, 90);
      final r2 = AutoLayoutEngine.computeLayout(sorento, [free]);
      expect(r2.placements.length, 1);
      expect(r2.placements.single.laidFlat, isTrue);
      expectPhysicallyValid(sorento, r2);
    });
  });

  group('감사에서 발견된 회귀', () {
    test('접이식 의자 4개 (85×20×15)는 모두 바닥에 놓인다 — 공중부양 없음', () {
      final chairs = List.generate(4, (i) => box('c$i', 85, 20, 15));
      final r = AutoLayoutEngine.computeLayout(sorento, chairs);
      expect(r.placements.length, 4);
      for (final p in r.placements) {
        expect(p.y, 0, reason: '${p.box.id} 는 바닥이어야 한다');
      }
      expectPhysicallyValid(sorento, r);
    });

    test('접이식 의자 8개도 전부 들어간다', () {
      final chairs = List.generate(8, (i) => box('c$i', 85, 20, 15));
      final r = AutoLayoutEngine.computeLayout(sorento, chairs);
      expect(r.allBoxesFit, isTrue);
      expectPhysicallyValid(sorento, r);
    });

    test('침낭 12개 (43×20×20)', () {
      final bags = List.generate(12, (i) => box('b$i', 43, 20, 20));
      final r = AutoLayoutEngine.computeLayout(sorento, bags);
      expect(r.allBoxesFit, isTrue);
      expectPhysicallyValid(sorento, r);
    });

    test('4인 가족 16개: 591L / 830L 이면 전부 들어가야 한다', () {
      for (final s in LayoutStrategy.values) {
        final r = AutoLayoutEngine.computeLayout(sorento, familyBundle(),
            strategy: s, restarts: 20);
        expectPhysicallyValid(sorento, r);
        expect(r.allBoxesFit, isTrue,
            reason: '$s 미적재: ${r.unfitBoxes.map((b) => b.id)} ${r.unfitReasons}');
        expect(r.utilizationPercent, greaterThan(60));
      }
    });

    test('적용 후 1cm 스냅을 해도 충돌이 생기지 않는다', () {
      final r = AutoLayoutEngine.computeLayout(sorento, familyBundle());
      final boxes = applied(r);
      for (final b in boxes) {
        b.snapToGrid(0.01);
      }
      expect(CollisionDetector(sorento).findAllCollisions(boxes), isEmpty);
    });

    test('무작위 재시도 없이도 15개 이상, 적재율 65% 이상', () {
      final r = AutoLayoutEngine.computeLayout(sorento, familyBundle());
      expectPhysicallyValid(sorento, r);
      expect(r.placedCount, greaterThanOrEqualTo(15));
      expect(r.utilizationPercent, greaterThan(65));
    });

    test('generateAlternatives 는 배치 개수·적재율 순', () {
      final alts = AutoLayoutEngine.generateAlternatives(sorento, familyBundle());
      expect(alts.length, 3);
      for (var i = 1; i < alts.length; i++) {
        final a = alts[i - 1], b = alts[i];
        expect(a.placedCount >= b.placedCount, isTrue);
        if (a.placedCount == b.placedCount) {
          expect(a.utilizationPercent + 1e-9 >= b.utilizationPercent, isTrue);
        }
      }
    });
  });

  group('프로퍼티 기반: 무작위 장비 셋', () {
    for (final preset in [
      TrunkPreset.sorento,
      TrunkPreset.tucson,
      TrunkPreset.avante,
      TrunkPreset.carnival,
    ]) {
      test('${preset.name}: 200회 × 최대 25개, 항상 물리적으로 유효', () {
        final trunk = preset.toTrunkSpace()!;
        final rnd = math.Random(preset.index * 1000 + 7);
        var totalPlaced = 0, totalBoxes = 0;
        final sw = Stopwatch()..start();
        for (var iter = 0; iter < 200; iter++) {
          final n = 1 + rnd.nextInt(25);
          final boxes = List.generate(n, (i) {
            final w = 10 + rnd.nextInt(80).toDouble();
            final d = 10 + rnd.nextInt(60).toDouble();
            final h = 5 + rnd.nextInt(50).toDouble();
            return box('r$i', w, d, h, upright: rnd.nextBool());
          });
          final s = LayoutStrategy.values[iter % 3];
          final r = AutoLayoutEngine.computeLayout(trunk, boxes, strategy: s);
          expectPhysicallyValid(trunk, r);
          totalPlaced += r.placedCount;
          totalBoxes += n;
        }
        sw.stop();
        // 성능 회귀 방지: 200회 합계가 20초를 넘으면 안 된다
        expect(sw.elapsedMilliseconds, lessThan(20000));
        // 완전 실패 방지 (아반떼는 작은 세단 트렁크라 큰 박스가 많이 탈락한다)
        expect(totalPlaced / totalBoxes,
            greaterThan(preset == TrunkPreset.avante ? 0.25 : 0.5));
      });
    }

    test('작은 박스만 있으면 항상 전부 들어간다', () {
      final rnd = math.Random(99);
      for (var iter = 0; iter < 50; iter++) {
        final boxes = List.generate(6, (i) {
          return box('s$i', 10 + rnd.nextInt(20).toDouble(),
              10 + rnd.nextInt(20).toDouble(), 5 + rnd.nextInt(15).toDouble());
        });
        final r = AutoLayoutEngine.computeLayout(sorento, boxes);
        expect(r.allBoxesFit, isTrue, reason: '$iter: ${r.unfitReasons}');
        expectPhysicallyValid(sorento, r);
      }
    });
  });

  group('적재 순서', () {
    test('깊은(z 작은) 박스가 먼저, 같은 구간이면 낮은 박스가 먼저', () {
      final r = AutoLayoutEngine.computeLayout(sorento, familyBundle());
      final ps = List<BoxPlacement>.from(r.placements)
        ..sort((a, b) => a.loadOrder.compareTo(b.loadOrder));
      for (var i = 1; i < ps.length; i++) {
        final a = ps[i - 1], b = ps[i];
        final za = (a.z / 0.25).floor(), zb = (b.z / 0.25).floor();
        expect(za <= zb, isTrue, reason: '${a.box.id} → ${b.box.id}');
        if (za == zb) expect(a.y <= b.y + 1e-9, isTrue);
      }
    });
  });

  group('적재율', () {
    test('실사용 부피는 직육면체보다 작다 (형상 반영)', () {
      final boxVol = sorento.w * sorento.d * sorento.h;
      expect(sorento.usableVolume, lessThan(boxVol));
      expect(sorento.usableVolume, greaterThan(boxVol * 0.7));
    });

    test('적재율은 배치된 박스 부피 / 실사용 부피', () {
      final r = AutoLayoutEngine.computeLayout(sorento, [box('a', 50, 50, 40)]);
      final expected = 0.5 * 0.5 * 0.4 / sorento.usableVolume * 100;
      expect(r.utilizationPercent, closeTo(expected, 1e-6));
    });
  });
}
