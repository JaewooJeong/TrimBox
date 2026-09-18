// 앱의 추천 세트 3종 × 쏘렌토 5/7인승 × 2열 슬라이드 3단계의 적재 판정.
//
// 앱과 같은 restarts: 24 를 쓰되 시간 예산은 넉넉히 줘서(모든 재시도가 돈다)
// 기계 속도와 무관하게 같은 결과가 나오게 한다. 하한은 실측값
// (2026-09-18, "실사례 보정" 이후의 쏘렌토 형상 + 세워 놓기 편향이 들어간 엔진):
//
//   세트              | 5인승 0 / +13 / +27 | 7인승 0 / +13 / +27
//   2인 미니멀 (9개)  |   9  /  9  /  9     |   9  /  9  /  9
//   4인 가족 (16개)   |  16  / 16  / 16     |  16  / 16  / 16
//   솔로 백패킹 (6개) |   6  /  6  /  6     |   6  /  6  /  6
//
// (보정 전 형상에서는 4인 가족이 2열 최후방에서 15/16 이었다.)
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/packing_advisor.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'packing_test_kit.dart';

const Duration kGenerous = Duration(seconds: 30);
const List<double> kSlides = [0.0, 0.13, sorentoSeatSlideMax];

/// 세트 이름 → 슬라이드별 배치 개수 하한 (5인승·7인승 공통)
const Map<String, List<int>> kLowerBounds = {
  '2인 미니멀 캠핑': [9, 9, 9],
  '4인 가족 캠핑': [16, 16, 16],
  '솔로 백패킹': [6, 6, 6],
};

TrunkSpace sorentoOf(bool sevenSeat, double slide) => sevenSeat
    ? TrunkSpace.sorento7(seatSlide: slide)
    : TrunkSpace.sorento(seatSlide: slide);

void main() {
  final bundles = {for (final b in gearBundles()) b.name: b};

  test('세트 이름이 기대와 같다 (하한 표와 1:1)', () {
    expect(bundles.keys.toSet(), kLowerBounds.keys.toSet());
  });

  group('판정 매트릭스', () {
    for (final name in kLowerBounds.keys) {
      for (final seven in [false, true]) {
        test('$name · ${seven ? '7인승(3열 접음)' : '5인승'}: 슬라이드별 하한, 당길수록 나빠지지 않음', () {
          final counts = <int>[];
          for (var i = 0; i < kSlides.length; i++) {
            final trunk = sorentoOf(seven, kSlides[i]);
            final input = bundleBoxes(bundles[name]!);
            final r = AutoLayoutEngine.computeLayout(trunk, input,
                restarts: 24, budget: kGenerous);
            expectPackingInvariants(trunk, input, r,
                ctx: '$name slide=${kSlides[i]}',
                strictRigidOnSoft: false); // BUG-1, packer_invariants_test 참고
            expect(r.placedCount, greaterThanOrEqualTo(kLowerBounds[name]![i]),
                reason: 'slide=${kSlides[i]} 미적재 ${r.unfitBoxes.map((b) => b.label)} '
                    '${r.unfitReasons.values}');
            // 20kg 이상은 조언 대상이 아니어야 (바닥에만 놓았으므로)
            expect(
                PackingAdvisor.advise(applied(r), trunk)
                    .where((a) => a.kind == AdviceKind.heavyHigh),
                isEmpty);
            counts.add(r.placedCount);
          }
          for (var i = 1; i < counts.length; i++) {
            expect(counts[i], greaterThanOrEqualTo(counts[i - 1] - 1),
                reason: '2열을 더 당겼는데 2개 이상 덜 들어감: $counts');
          }
          // 가장 많이 당긴 상태는 최후방보다 나쁘지 않다
          expect(counts.last, greaterThanOrEqualTo(counts.first), reason: '$counts');
        }, timeout: const Timeout(Duration(minutes: 2)));
      }
    }
  });

  group('4인 가족 캠핑', () {
    final family = bundles['4인 가족 캠핑']!;

    test('세트 구성: 16개, 약 0.5m³, 20kg 이상은 텐트·쿨러', () {
      final input = bundleBoxes(family);
      expect(input.length, 16);
      final liters = input.fold<double>(0, (s, b) => s + b.volume) * 1000;
      expect(liters, inInclusiveRange(450, 600));
      final heavy = input.where((b) => b.weightKg >= AutoLayoutEngine.floorOnlyKg);
      expect(heavy.map((b) => b.label).toSet(),
          {'코베아 네스트W (4인 거실형)', '대형 아이스박스 (50L)'});
      // 공칭 부피는 어느 구성에서도 실사용 부피보다 작다 → "부피 부족" 은 사유가 될 수 없다
      expect(liters / 1000, lessThan(TrunkSpace.sorento().usableVolume));
    });

    test('2열 +13cm: 5·7인승 모두 전부 적재 (앱의 슬라이드 제안 설정 restarts 12 로도)', () {
      for (final seven in [false, true]) {
        final trunk = sorentoOf(seven, 0.13);
        for (final restarts in [12, 24]) {
          final input = bundleBoxes(family);
          final r = AutoLayoutEngine.computeLayout(trunk, input,
              restarts: restarts, budget: kGenerous);
          expect(r.allBoxesFit, isTrue, reason: 'seven=$seven ${r.unfitReasons}');
          expectPackingInvariants(trunk, input, r, strictRigidOnSoft: false);
        }
      }
    });

    test('2열 최후방: 쿨러는 실리고 바닥에 있다, 미적재가 있어도 1개이고 사유는 "빈 자리 없음"', () {
      for (final seven in [false, true]) {
        final trunk = sorentoOf(seven, 0);
        final input = bundleBoxes(family);
        final r = AutoLayoutEngine.computeLayout(trunk, input,
            restarts: 24, budget: kGenerous);
        final cooler =
            r.placements.where((p) => p.box.label == '대형 아이스박스 (50L)').toList();
        expect(cooler.length, 1, reason: '쿨러가 미적재: ${r.unfitReasons}');
        expect(cooler.single.y, 0);
        expect(cooler.single.h, closeTo(0.42, 1e-9), reason: '쿨러는 눕히지 않는다');
        expect(r.unfitBoxes.length, lessThanOrEqualTo(1));
        for (final reason in r.unfitReasons.values) {
          expect(reason, contains('빈 자리 없음'));
        }
      }
    });

    test('전략 3개 모두: +13cm·+27cm 전부 적재, 최후방은 재시도 없이도 13개 이상', () {
      for (final s in LayoutStrategy.values) {
        final input = bundleBoxes(family);
        for (final slide in [0.13, sorentoSeatSlideMax]) {
          final trunk = TrunkSpace.sorento(seatSlide: slide);
          final r = AutoLayoutEngine.computeLayout(trunk, input,
              strategy: s, restarts: 24, budget: kGenerous);
          expect(r.allBoxesFit, isTrue, reason: '${s.name} +$slide ${r.unfitReasons}');
          // 연질 짐이 강체의 하중을 받는 배치는 없다 (접촉만 하는 경우는 BUG-1)
          expectPackingInvariants(trunk, input, r,
              ctx: '가족 ${s.name} +$slide', strictRigidOnSoft: false);
        }
      }
      for (final s in LayoutStrategy.values) {
        final trunk = TrunkSpace.sorento();
        final input = bundleBoxes(family);
        final r0 = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
        expectPackingInvariants(trunk, input, r0,
            ctx: '가족 ${s.name}', strictRigidOnSoft: false);
        expect(r0.placedCount, greaterThanOrEqualTo(13), reason: s.name);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
