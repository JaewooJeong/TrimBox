// PackingAdvisor 와 자동배치의 일관성: 엔진이 "절대 안 함"으로 막는 규칙
// (20kg 이상은 바닥, 5kg 이상 강체는 연질 위에 안 올림, 2열 슬라이드 바닥 빈틈 위에
// 안 놓음)에 대해 조언이 뜨면 안 된다.
// heavyOnLight·accessBuried 는 엔진이 점수로만 다루므로 떠도 된다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/packing_advisor.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import '../validation/packing_test_kit.dart';

final _hangul = RegExp('[가-힣]');

void expectWellFormed(List<Advice> advice, List<TrimBox> boxes) {
  for (final a in advice) {
    expect(a.message.trim(), isNotEmpty);
    expect(_hangul.hasMatch(a.message), isTrue, reason: '한국어 문장이어야: ${a.message}');
    expect(a.message, isNot(contains('null')));
    expect(a.message, isNot(contains('Instance of')));
    expect(boxes.any((b) => identical(b, a.box)), isTrue, reason: '조언 대상은 입력 박스');
    final name = a.box.label.isNotEmpty ? a.box.label : a.box.id;
    expect(a.message, contains(name), reason: '누구에 대한 조언인지 보여야 한다');
  }
}

void main() {
  final trunks = namedTrunks();

  group('자동배치 결과에 대한 조언', () {
    test('무작위 장비: heavyHigh 없음, rigidOnSoft 는 하중을 받는 경우 없음', () {
      var packs = 0, adviceSeen = 0;
      for (final name in ['sorento', 'sorento7', 'sorento+13', 'sorento+27', 'tucson', 'carnival']) {
        final trunk = trunks[name]!;
        final rnd = math.Random(name.hashCode & 0xfff ^ 0xad);
        for (var i = 0; i < 4; i++) {
          final input = i.isEven
              ? randomGear(rnd, 8 + rnd.nextInt(12))
              : randomPhysicsBoxes(rnd, 8 + rnd.nextInt(12));
          final s = LayoutStrategy.values[(i + name.length) % 3];
          final r = AutoLayoutEngine.computeLayout(trunk, input, strategy: s);
          final boxes = applied(r);
          final snap = boxes.map(snapshot).toList();
          final advice = PackingAdvisor.advise(boxes, trunk);
          packs++;
          adviceSeen += advice.length;
          expectWellFormed(advice, boxes);
          expect(boxes.map(snapshot).toList(), snap, reason: 'advise 는 박스를 바꾸지 않는다');
          // 같은 입력 → 같은 조언
          final again = PackingAdvisor.advise(boxes, trunk);
          expect(again.map((a) => '${a.kind}|${a.box.id}|${a.message}').toList(),
              advice.map((a) => '${a.kind}|${a.box.id}|${a.message}').toList());

          expect(advice.where((a) => a.kind == AdviceKind.heavyHigh), isEmpty,
              reason: '$name i=$i ${s.name}: ${advice.map((a) => a.message)}');
          // 바닥 빈틈(2열 슬라이드) 위에는 엔진이 놓지 않는다
          expect(advice.where((a) => a.kind == AdviceKind.overSeatGap), isEmpty,
              reason: '$name i=$i ${s.name}: ${advice.map((a) => a.message)}');
          // BUG-1 (packer_invariants_test): 틈에 낀 연질 짐 때문에 뜨는 rigidOnSoft 는
          // 여기서 실패로 보지 않는다. 연질 짐이 실제로 하중을 받는 경우만 실패.
          for (final a in advice.where((a) => a.kind == AdviceKind.rigidOnSoft)) {
            final rigidOthers = boxes.where((o) => o.id != a.box.id && !o.soft);
            expect(SupportRule.isSupported(a.box, rigidOthers, trunk), isTrue,
                reason: '$name i=$i: ${a.message} — 연질 짐 없이는 지지되지 않는다');
          }
        }
      }
      expect(packs, 24);
      // 공허한 통과 방지: 스윕 어딘가에서는 조언(heavyOnLight 등)이 실제로 나온다
      expect(adviceSeen, greaterThan(0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('추천 세트 3종 (쏘렌토, 앱 설정): heavyHigh 없음, 쿨러가 묻혔다는 조언 없음', () {
      for (final bundle in gearBundles()) {
        for (final slide in [0.0, 0.13]) {
          final trunk = TrunkSpace.sorento(seatSlide: slide);
          final input = bundleBoxes(bundle);
          final r = AutoLayoutEngine.computeLayout(trunk, input,
              restarts: 24, budget: const Duration(seconds: 30));
          final boxes = applied(r);
          final advice = PackingAdvisor.advise(boxes, trunk);
          expectWellFormed(advice, boxes);
          expect(advice.where((a) => a.kind == AdviceKind.heavyHigh), isEmpty);
          expect(advice.where((a) => a.kind == AdviceKind.accessBuried), isEmpty,
              reason: '${bundle.name} slide=$slide: ${advice.map((a) => a.message)}');
        }
      }
    });
  });

  group('트렁크 밖에 세워 둔 짐은 무시한다', () {
    test('미적재로 주차된 짐(앱: z = d + 6cm)은 조언 대상도, 다른 짐의 받침·가림막도 아니다', () {
      final trunk = TrunkSpace.sorento();
      final cooler = cmBox('cooler', 40, 30, 30, kg: 15, access: true, upright: true,
          x: 0.5, z: trunk.frontDepthAt(0.30));
      final base = [cooler];
      expect(PackingAdvisor.advise(base, trunk), isEmpty);
      // 주차된 짐: 무겁고 떠 있고, 연질 위에 있고, 쿨러 뒤를 가리는 x 범위
      final parkedSoft = cmBox('pSoft', 60, 40, 30, soft: true, kg: 2, x: 0.4, z: trunk.d + 0.06);
      final parkedHeavy = cmBox('pHeavy', 50, 40, 30, kg: 35, x: 0.45, y: 0.30, z: trunk.d + 0.06);
      final parkedAccess = cmBox('pAccess', 40, 30, 30, kg: 9, access: true, x: 0.0, z: trunk.d);
      final all = [cooler, parkedSoft, parkedHeavy, parkedAccess];
      final advice = PackingAdvisor.advise(all, trunk);
      expect(advice.where((a) => a.box.id.startsWith('p')), isEmpty,
          reason: advice.map((a) => a.message).join('; '));
    });

    test('바닥 빈틈 위에 통째로 놓인 짐은 overSeatGap, 절반 이상 걸치면 조언 없음', () {
      final trunk = TrunkSpace.sorento(seatSlide: sorentoSeatSlideMax);
      final gap = trunk.floorStartZ;
      expect(gap, greaterThan(0));
      final inGap = cmBox('inGap', 30, 20, 5, x: 0.5, z: gap - 0.2);
      final bridging = cmBox('bridging', 30, 60, 5, x: 0.9, z: gap - 0.2);
      final advice = PackingAdvisor.advise([inGap, bridging], trunk);
      expectWellFormed(advice, [inGap, bridging]);
      expect(advice.map((a) => (a.kind, a.box.id)).toList(), [(AdviceKind.overSeatGap, 'inGap')]);
      // 슬라이드가 없으면 빈틈도 없다
      expect(PackingAdvisor.advise([inGap.copyWith(z: 0.0)], TrunkSpace.sorento()), isEmpty);
    });

    test('같은 짐을 트렁크 안으로 옮기면 조언이 뜬다 (위 테스트가 공허하지 않음)', () {
      final trunk = plainTrunk(1.2, 1.2, 0.9);
      final soft = cmBox('soft', 60, 40, 30, soft: true, kg: 2, x: 0.4, z: 0.4);
      final heavy = cmBox('heavy', 50, 40, 30, kg: 35, x: 0.45, y: 0.30, z: 0.4);
      final kinds = PackingAdvisor.advise([soft, heavy], trunk).map((a) => a.kind).toSet();
      expect(kinds, containsAll([AdviceKind.heavyHigh, AdviceKind.rigidOnSoft]));
    });

    test('경계: z = d − 5mm 부터 밖으로 본다 (CollisionDetector 와 같은 기준)', () {
      final trunk = plainTrunk(1.0, 1.0, 0.9);
      final inside = cmBox('in', 30, 30, 30, kg: 25, y: 0.3, z: trunk.d - 0.006);
      final outside = cmBox('out', 30, 30, 30, kg: 25, y: 0.3, z: trunk.d - 0.005);
      expect(PackingAdvisor.advise([inside], trunk).map((a) => a.kind),
          contains(AdviceKind.heavyHigh));
      expect(PackingAdvisor.advise([outside], trunk), isEmpty);
    });
  });

  group('문턱값', () {
    final trunk = plainTrunk(1.2, 1.2, 0.9);

    test('heavyHigh: 정확히 20kg·바닥에서 1.5cm 초과부터', () {
      final base = cmBox('base', 60, 60, 30, kg: 30);
      Set<AdviceKind> kinds(double kg, double y) => PackingAdvisor.advise(
              [base, cmBox('b', 40, 40, 20, kg: kg, x: 0.1, z: 0.1, y: y)], trunk)
          .where((a) => a.box.id == 'b')
          .map((a) => a.kind)
          .toSet();
      expect(kinds(AutoLayoutEngine.floorOnlyKg, 0.30), contains(AdviceKind.heavyHigh));
      expect(kinds(AutoLayoutEngine.floorOnlyKg - 0.1, 0.30), isNot(contains(AdviceKind.heavyHigh)));
      expect(PackingAdvisor.advise([cmBox('f', 40, 40, 20, kg: 40, y: SupportRule.heightTol)], trunk),
          isEmpty);
    });

    test('heavyOnLight: 8kg 이상이 자기 무게 40% 미만 짐 위, 무게 모름(0)은 제외', () {
      Set<AdviceKind> kinds(double topKg, double baseKg) => PackingAdvisor.advise([
            cmBox('base', 60, 60, 30, kg: baseKg),
            cmBox('top', 40, 40, 20, kg: topKg, x: 0.1, z: 0.1, y: 0.30),
          ], trunk).map((a) => a.kind).toSet();
      expect(kinds(10, 3.9), {AdviceKind.heavyOnLight});
      expect(kinds(10, 4.0), isEmpty);
      expect(kinds(7.9, 1.0), isEmpty);
      expect(kinds(10, 0), isEmpty);
    });

    test('rigidOnSoft: 5kg 이상 강체만, 연질끼리·가벼운 강체는 제외, heavyOnLight 보다 우선', () {
      List<Advice> run(TrimBox top) => PackingAdvisor.advise(
          [cmBox('bag', 60, 60, 30, soft: true, kg: 1), top], trunk);
      expect(run(cmBox('pot', 40, 40, 20, kg: 5, x: 0.1, z: 0.1, y: 0.30)).map((a) => a.kind),
          [AdviceKind.rigidOnSoft]);
      expect(run(cmBox('cup', 40, 40, 20, kg: 4.9, x: 0.1, z: 0.1, y: 0.30)), isEmpty);
      expect(run(cmBox('bag2', 40, 40, 20, kg: 6, soft: true, x: 0.1, z: 0.1, y: 0.30)), isEmpty);
      // 10kg 강체가 1kg 연질 위: 두 규칙 모두 해당하지만 문장은 하나 (rigidOnSoft)
      expect(run(cmBox('crate', 40, 40, 20, kg: 10, x: 0.1, z: 0.1, y: 0.30)).map((a) => a.kind),
          [AdviceKind.rigidOnSoft]);
    });

    test('무게 표기: 정수는 "20kg", 소수는 "20.5kg", 라벨이 비면 id', () {
      final base = cmBox('base', 60, 60, 30, kg: 30);
      final a = PackingAdvisor.advise(
          [base, cmBox('b', 40, 40, 20, kg: 20, x: 0.1, z: 0.1, y: 0.30)], trunk);
      expect(a.single.message, contains('(20kg)'));
      final nameless = cmBox('id-42', 40, 40, 20, kg: 20.5, x: 0.1, z: 0.1, y: 0.30)..label = '';
      final b = PackingAdvisor.advise([base, nameless], trunk);
      expect(b.single.message, contains('id-42 (20.5kg)'));
    });
  });

  group('알려진 버그 (고치면 skip 을 지운다)', () {
    test('BUG-1: 자동배치 직후인데 rigidOnSoft 조언이 뜬다 (최소 재현)', () {
      // packer_invariants_test 의 BUG-1 과 같은 입력. 연질 S 는 강체 B 의 오버행 아래
      // 틈에 들어갔을 뿐이고, B 는 A 만으로 67% 지지된다.
      final trunk = plainTrunk(0.6, 0.4, 0.8);
      final r = AutoLayoutEngine.computeLayout(trunk, [
        cmBox('A', 40, 40, 30, kg: 3),
        cmBox('B', 60, 40, 10, kg: 6, upright: true),
        cmBox('S', 20, 40, 30, soft: true, compress: 0.3, kg: 1),
      ]);
      expect(r.allBoxesFit, isTrue);
      final advice = PackingAdvisor.advise(applied(r), trunk);
      expect(advice.where((a) => a.kind == AdviceKind.rigidOnSoft), isEmpty,
          reason: advice.map((a) => a.message).join('; '));
    },);
  });
}
