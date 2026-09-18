// 자동배치 엔진 불변식 스윕.
//
// 모든 검사는 "적용된 결과"(placement.applyTo 를 입력 사본에 적용)에 대해 한다.
// 불변식 목록은 test/validation/packing_test_kit.dart 의 expectPackingInvariants.
//
// 알려진 버그(맨 아래 그룹)는 skip 으로 남겨 두었다. 고치면 skip 을 지운다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/packing_advisor.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';

import '../validation/packing_test_kit.dart';

/// 스윕 한 번에 쓰는 세트 수 (트렁크마다). 세트마다 전략 3개를 모두 돌린다.
const int kSetsPerTrunk = 12;

void main() {
  final trunks = namedTrunks();

  group('불변식 스윕: 무작위 물리 박스 + 실제 장비 × 전 전략', () {
    for (final e in trunks.entries) {
      test('${e.key}: $kSetsPerTrunk 세트 × 3 전략', () {
        final trunk = e.value;
        final rnd = math.Random(e.key.hashCode & 0xffff ^ 0x5eed);
        var placed = 0, total = 0;
        for (var i = 0; i < kSetsPerTrunk; i++) {
          final n = 1 + rnd.nextInt(22);
          final input =
              i.isEven ? randomPhysicsBoxes(rnd, n) : randomGear(rnd, n);
          final before = input.map(snapshot).toList();
          for (final s in LayoutStrategy.values) {
            final r = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
            expect(r.strategy, s);
            expectPackingInvariants(trunk, input, r,
                ctx: '${e.key} set=$i n=$n ${s.name}',
                // BUG-1 (아래 '알려진 버그' 그룹): 틈에 밀어 넣은 연질 짐이 위쪽
                // 강체의 "지지자"로 잡힌다. 하중을 받는 경우만 여기서 실패로 본다.
                strictRigidOnSoft: false);
            // computeLayout 은 입력을 바꾸지 않는다
            expect(input.map(snapshot).toList(), before,
                reason: '${e.key} set=$i ${s.name}: 입력 박스가 변형됨');
            placed += r.placedCount;
            total += n;
          }
        }
        // 완전 실패 방지 (아반떼는 작은 세단 트렁크)
        expect(placed / total, greaterThan(e.key == 'avante' ? 0.2 : 0.5),
            reason: '${e.key}: $placed/$total');
      }, timeout: const Timeout(Duration(minutes: 3)));
    }
  });

  group('경계 입력', () {
    final sorento = TrunkSpace.sorento();

    test('빈 목록 · 박스 하나 · 전부 너무 큼', () {
      for (final s in LayoutStrategy.values) {
        final empty = AutoLayoutEngine.computeLayout(sorento, [], strategy: s);
        expectPackingInvariants(sorento, [], empty);
        expect(empty.allBoxesFit, isTrue);

        final one = [cmBox('a', 40, 30, 20)];
        expectPackingInvariants(
            sorento, one, AutoLayoutEngine.computeLayout(sorento, one, strategy: s));

        final huge = [cmBox('h1', 200, 50, 50), cmBox('h2', 150, 150, 10)];
        final r = AutoLayoutEngine.computeLayout(sorento, huge, strategy: s);
        expectPackingInvariants(sorento, huge, r);
        expect(r.placements, isEmpty);
        expect(r.utilizationPercent, 0);
        for (final reason in r.unfitReasons.values) {
          expect(reason, contains('트렁크보다 큼'));
        }
      }
    });

    test('같은 박스 30개 (id 만 다름): 회계가 맞고 물리적으로 유효', () {
      final input = [for (var i = 0; i < 30; i++) cmBox('same$i', 45, 35, 30, kg: 6)];
      final r = AutoLayoutEngine.computeLayout(sorento, input);
      expectPackingInvariants(sorento, input, r);
      expect(r.placedCount, greaterThanOrEqualTo(8)); // 실측 9개 (바닥 6 + 2층 3)
      expect(r.unfitBoxes, isNotEmpty, reason: '30 × 47L = 1.4m³ 은 다 들어갈 수 없다');
    });

    test('이미 위치·회전·압축이 들어 있는 입력도 결과는 rotY 0 · 유효', () {
      final input = [
        cmBox('a', 60, 30, 20, x: 0.5, y: 0.3, z: 0.4, rotY: 90),
        cmBox('b', 40, 40, 20, soft: true, compress: 0.4, x: 9, z: 9)
          ..squash = 0.4
          ..squashW = 0.2,
        cmBox('c', 30, 30, 30, rotY: 270, upright: true),
      ];
      final r = AutoLayoutEngine.computeLayout(sorento, input);
      expectPackingInvariants(sorento, input, r);
      expect(r.allBoxesFit, isTrue);
      // 자리가 넉넉하면 압축하지 않는다
      expect(r.squashedPlacements, isEmpty);
    });

    test('무게 0(모름)·음수가 아닌 극단 무게도 규칙을 깨지 않는다', () {
      final input = [
        cmBox('anvil', 30, 30, 20, kg: 200),
        cmBox('feather', 80, 60, 40, kg: 0.01, soft: true, compress: 0.5),
        cmBox('unknown', 50, 40, 30),
        cmBox('exact20', 40, 40, 40, kg: AutoLayoutEngine.floorOnlyKg),
        cmBox('just19', 40, 40, 40, kg: AutoLayoutEngine.floorOnlyKg - 0.1),
      ];
      for (final t in [sorento, plainTrunk(0.85, 0.65, 0.9)]) {
        final r = AutoLayoutEngine.computeLayout(t, input);
        expectPackingInvariants(t, input, r);
      }
    });
  });

  group('결정성', () {
    test('같은 입력 → 같은 배치 (시간 예산이 걸리지 않는 세트)', () {
      var asserted = 0, candidates = 0;
      for (final name in ['sorento', 'sorento7', 'tucson', 'custom']) {
        final trunk = trunks[name]!;
        final rnd = math.Random(name.length * 31 + 5);
        for (var i = 0; i < 6; i++) {
          final n = 3 + rnd.nextInt(12);
          final input = i.isEven ? randomGear(rnd, n) : randomPhysicsBoxes(rnd, n);
          final s = LayoutStrategy.values[i % 3];
          final sw = Stopwatch()..start();
          final r1 = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
          final ms = sw.elapsedMilliseconds;
          candidates++;
          // 보수(700ms)·전수 탐색(500ms) 예산에 걸릴 만큼 오래 걸린 세트는
          // 기계 속도에 따라 결과가 달라질 수 있어 단정하지 않는다 (보고서 참고)
          if (ms > 250) continue;
          final r2 = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
          expect(placementSignature(r2), placementSignature(r1),
              reason: '$name i=$i ${s.name}');
          asserted++;
        }
      }
      expect(asserted, greaterThanOrEqualTo(candidates ~/ 2),
          reason: '결정성 검사가 대부분 건너뛰어졌다 ($asserted/$candidates)');
    });

    test('같은 seed 의 무작위 재시도 → 같은 배치', () {
      // 전부는 못 넣는 작은 세트: 재시도가 실제로 돈다. 예산은 넉넉히.
      final trunk = trunks['custom']!;
      final rnd = math.Random(2024);
      final input = randomPhysicsBoxes(rnd, 9);
      AutoLayoutResult run(int seed) => AutoLayoutEngine.computeLayout(trunk, input,
          restarts: 6, seed: seed, budget: const Duration(seconds: 20));
      final a = run(77), b = run(77);
      expect(placementSignature(a), placementSignature(b));
      expectPackingInvariants(trunk, input, a, strictRigidOnSoft: false);
      // 다른 seed 도 유효하다 (같을 필요는 없다)
      expectPackingInvariants(trunk, input, run(78), strictRigidOnSoft: false);
    });

    test('입력 순서를 섞어도 배치 개수는 크게 달라지지 않는다 (±1)', () {
      final trunk = trunks['sorento']!;
      final rnd = math.Random(11);
      for (var i = 0; i < 3; i++) {
        final input = randomGear(rnd, 10 + i * 3);
        final shuffled = List<TrimBox>.from(input)..shuffle(math.Random(i));
        final a = AutoLayoutEngine.computeLayout(trunk, input);
        final b = AutoLayoutEngine.computeLayout(trunk, shuffled);
        expectPackingInvariants(trunk, shuffled, b, strictRigidOnSoft: false);
        expect((a.placedCount - b.placedCount).abs(), lessThanOrEqualTo(1),
            reason: 'i=$i ${a.placedCount} vs ${b.placedCount}');
      }
    });
  });

  group('재투입 (멱등 유사)', () {
    test('적용된 박스(새 w/d/h, 압축 0)를 다시 넣으면 이전 개수 − 1 이상', () {
      for (final name in ['sorento', 'sorento+13', 'carnival', 'custom']) {
        final trunk = trunks[name]!;
        final rnd = math.Random(name.hashCode & 0xfff);
        for (var i = 0; i < 4; i++) {
          final n = 6 + rnd.nextInt(12);
          final input = i.isEven ? randomGear(rnd, n) : randomPhysicsBoxes(rnd, n);
          final s = LayoutStrategy.values[i % 3];
          final r1 = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
          final again = <TrimBox>[
            for (final b in applied(r1))
              b.copyWith(x: 0, y: 0, z: 0, squash: 0, squashW: 0, squashD: 0)
                ..loadOrder = null,
          ];
          final r2 = AutoLayoutEngine.computeLayout(trunk, again, strategy: s);
          expectPackingInvariants(trunk, again, r2,
              ctx: '$name i=$i 재투입', strictRigidOnSoft: false);
          expect(r2.placedCount, greaterThanOrEqualTo(r1.placedCount - 1),
              reason: '$name i=$i ${s.name}: ${r1.placedCount} → ${r2.placedCount}');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('generateAlternatives', () {
    test('전략 3개, (배치 개수 ↓, 적재율 ↓) 정렬, 각 결과가 유효', () {
      final rnd = math.Random(3);
      for (final name in ['sorento', 'tucson']) {
        final trunk = trunks[name]!;
        final input = randomGear(rnd, 14);
        final alts = AutoLayoutEngine.generateAlternatives(trunk, input);
        expect(alts.length, LayoutStrategy.values.length);
        expect(alts.map((a) => a.strategy).toSet(), LayoutStrategy.values.toSet());
        for (var i = 1; i < alts.length; i++) {
          final a = alts[i - 1], b = alts[i];
          expect(a.placedCount, greaterThanOrEqualTo(b.placedCount));
          if (a.placedCount == b.placedCount) {
            expect(a.utilizationPercent + 1e-9,
                greaterThanOrEqualTo(b.utilizationPercent));
          }
        }
        for (final a in alts) {
          expectPackingInvariants(trunk, input, a,
              ctx: '$name ${a.strategy.name}', strictRigidOnSoft: false);
        }
      }
    });

    test('전략 라벨은 비어 있지 않고 서로 다르다', () {
      final labels = LayoutStrategy.values.map((s) => s.label).toSet();
      expect(labels.length, LayoutStrategy.values.length);
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
    });
  });

  group('알려진 버그 (고치면 skip 을 지운다)', () {
    test('BUG-1: 강체 아래 틈에 들어간 연질 짐 때문에 "단단한 짐이 연질 위" 가 된다', () {
      // 60×40 바닥. A(40×40×30) 위에 B(60×40×10, 6kg, 세움)가 67% 걸쳐 놓이고,
      // 연질 S(20×40×30)가 B 의 오버행 아래 틈에 들어가 윗면이 B 바닥과 맞닿는다.
      // SupportRule.supportersAt(B) 에 S 가 잡혀 PackingAdvisor 가 rigidOnSoft 를 낸다.
      final trunk = plainTrunk(0.6, 0.4, 0.8);
      final input = [
        cmBox('A', 40, 40, 30, kg: 3),
        cmBox('B', 60, 40, 10, kg: 6, upright: true),
        cmBox('S', 20, 40, 30, soft: true, compress: 0.3, kg: 1),
      ];
      final r = AutoLayoutEngine.computeLayout(trunk, input);
      expect(r.allBoxesFit, isTrue);
      final boxes = applied(r);
      final b = boxes.firstWhere((x) => x.id == 'B');
      // 연질 S 가 B 의 오버행 아래에 닿아 있는 것 자체는 괜찮다. B 가 연질 짐 없이도
      // 절반 이상 받쳐지면(하중을 연질이 지지 않으면) 조언이 나오면 안 된다.
      expect(
          SupportRule.supportRatio(b, b.y, boxes.where((o) => !o.soft), trunk),
          greaterThanOrEqualTo(SupportRule.minRatio - 1e-9),
          reason: 'B 는 단단한 짐만으로 지지돼야 한다');
      expect(
          PackingAdvisor.advise(boxes, trunk)
              .where((a) => a.kind == AdviceKind.rigidOnSoft),
          isEmpty);
    },);

    test('BUG-2: 무작위 재시도를 켜면 배치 개수가 줄어든다 (탐색을 더 했는데 더 나쁨)', () {
      final trunk = trunks['custom']!;
      final input = [
        cmBox('r0', 53, 23, 47, kg: 20.6),
        cmBox('r1', 71, 54, 11, upright: true),
        cmBox('r2', 39, 14, 52, kg: 3.3),
        cmBox('r3', 33, 11, 24, kg: 3.7),
        cmBox('r4', 55, 39, 54, kg: 6.0, soft: true, compress: 0.45),
        cmBox('r5', 26, 21, 23, kg: 1.5),
        cmBox('r6', 52, 39, 45, kg: 39.9),
        cmBox('r7', 38, 60, 13, kg: 8.8, upright: true, access: true),
        cmBox('r8', 28, 53, 31, kg: 3.4, soft: true),
        cmBox('r9', 64, 31, 30, kg: 21.9, upright: true),
        cmBox('r10', 27, 10, 45, kg: 1.3, upright: true),
        cmBox('r11', 65, 46, 10, kg: 17.3, upright: true),
      ];
      final r0 = AutoLayoutEngine.computeLayout(trunk, input);
      final r8 = AutoLayoutEngine.computeLayout(trunk, input,
          restarts: 8, budget: const Duration(seconds: 20));
      expect(r8.placedCount, greaterThanOrEqualTo(r0.placedCount),
          reason: 'restarts 0 → ${r0.placedCount}, restarts 8 → ${r8.placedCount}');
    },);
  });
}
