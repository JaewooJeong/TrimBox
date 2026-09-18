import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/gear_physics.dart';
import 'package:trimbox/models/packing_advisor.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';

TrimBox box(
  String id,
  double wCm,
  double dCm,
  double hCm, {
  bool soft = false,
  double compress = 0,
  double kg = 0,
  bool access = false,
  bool upright = false,
  double x = 0,
  double y = 0,
  double z = 0,
}) =>
    TrimBox(
      id: id,
      label: id,
      w: wCm / 100,
      d: dCm / 100,
      h: hCm / 100,
      x: x,
      y: y,
      z: z,
      color: const Color(0xFF888888),
      soft: soft,
      compressibility: compress,
      weightKg: kg,
      accessPriority: access,
      keepUpright: upright,
    );

TrunkSpace plain(double w, double d, double h) => TrunkSpace(
      w: w,
      d: d,
      h: h,
      leftWheelhouse: const Wheelhouse(w: 0, d: 0, h: 0),
      rightWheelhouse: const Wheelhouse(w: 0, d: 0, h: 0),
    );

List<TrimBox> applied(AutoLayoutResult r) => [
      for (final p in r.placements) (p.box.copyWith()..loadOrder = null)..also(p),
    ];

extension on TrimBox {
  TrimBox also(BoxPlacement p) {
    p.applyTo(this);
    return this;
  }
}

void main() {
  group('TrimBox 물리 속성', () {
    test('압축은 실제 높이·폭·깊이에만 반영되고 공칭 치수는 유지된다', () {
      final b = box('a', 40, 30, 20, soft: true, compress: 0.4)..squash = 0.4;
      expect(b.h, closeTo(0.20, 1e-9));
      expect(b.effectiveH, closeTo(0.12, 1e-9));
      expect(b.top, closeTo(0.12, 1e-9));
      expect(b.volume, closeTo(0.024, 1e-9));
      b.squash = 0;
      b.squashD = 0.25;
      expect(b.effectiveD, closeTo(0.225, 1e-9));
      expect(b.effectiveW, closeTo(0.40, 1e-9));
      b.rotY = 90; // 회전하면 눌린 축도 같이 돈다
      expect(b.effectiveW, closeTo(0.225, 1e-9));
      expect(b.effectiveD, closeTo(0.40, 1e-9));
      expect(b.squashAmount, closeTo(0.25, 1e-9));
    });

    test('JSON 왕복에 무게·연질·압축·접근성이 남는다', () {
      final b = box('a', 40, 30, 20, soft: true, compress: 0.4, kg: 12.5, access: true)
        ..squash = 0.2
        ..squashW = 0.1;
      final back = TrimBox.fromJson(b.toJson());
      expect(back.soft, isTrue);
      expect(back.compressibility, 0.4);
      expect(back.weightKg, 12.5);
      expect(back.accessPriority, isTrue);
      expect(back.squash, 0.2);
      expect(back.squashW, 0.1);
      // 없던 필드는 기본값
      final legacy = TrimBox.fromJson({
        'id': 'x', 'label': 'x', 'size': {'w': 0.1, 'd': 0.1, 'h': 0.1},
        'pos': {'x': 0, 'y': 0, 'z': 0}, 'color': 0xFF000000,
      });
      expect(legacy.soft, isFalse);
      expect(legacy.weightKg, 0);
      expect(legacy.effectiveH, closeTo(0.1, 1e-9));
    });
  });

  group('연질 짐 눌러 넣기', () {
    test('천장보다 높은 침낭은 눌러서 들어가고, 눌린 비율은 최소한으로', () {
      final trunk = plain(0.5, 0.5, 0.17);
      final bag = box('bag', 40, 40, 20, soft: true, compress: 0.4);
      final r = AutoLayoutEngine.computeLayout(trunk, [bag]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      final p = r.placements.single;
      expect(p.squashed, isTrue);
      expect(p.squash, closeTo(0.2, 1e-9)); // 절반 단계로 충분 (0.20 → 0.16 ≤ 0.17)
      final b = applied(r).single;
      expect(b.top, lessThanOrEqualTo(0.17 + 0.005));
      expect(CollisionDetector(trunk).findAllCollisions([b]), isEmpty);
      // 더 낮은 천장이면 최대 단계까지 누른다
      final r2 = AutoLayoutEngine.computeLayout(plain(0.5, 0.5, 0.13), [bag]);
      expect(r2.allBoxesFit, isTrue);
      expect(r2.placements.single.squash, closeTo(0.4, 1e-9));
    });

    test('같은 침낭도 단단하면 안 들어간다', () {
      final trunk = plain(0.5, 0.5, 0.15);
      final r = AutoLayoutEngine.computeLayout(trunk, [box('rigid', 40, 40, 20)]);
      expect(r.allBoxesFit, isFalse);
    });

    test('어느 방향으로도 강체로는 안 들어가는 자리에 눌러 넣는다', () {
      // 바닥 50×35, 높이 25. 40×40×20 은 어떤 방향으로도 강체로는 안 들어간다
      final trunk = plain(0.5, 0.35, 0.25);
      expect(AutoLayoutEngine.computeLayout(trunk, [box('r', 40, 40, 20)]).allBoxesFit, isFalse);
      final bag = box('bag', 40, 40, 20, soft: true, compress: 0.4);
      final r = AutoLayoutEngine.computeLayout(trunk, [bag]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      final p = r.placements.single;
      expect(p.squashed, isTrue);
      final b = applied(r).single;
      expect(b.z + b.effectiveD, lessThanOrEqualTo(0.35 + 0.005));
      expect(b.top, lessThanOrEqualTo(0.25 + 0.005));
      expect(CollisionDetector(trunk).findAllCollisions([b]), isEmpty);
    });

    test('한 번에 한 축만 누른다: 세워서 폭을 누르면 들어가고, 두 축을 눌러야 하면 미적재', () {
      // 바닥 30×30, 높이 60 에 40×40×10 침낭: 세워서(40 높이) 폭 40→28 로 누르면 들어간다
      final trunk = plain(0.3, 0.3, 0.6);
      final bag = box('bag', 40, 40, 10, soft: true, compress: 0.3);
      final r = AutoLayoutEngine.computeLayout(trunk, [bag]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      final p = r.placements.single;
      expect(p.squashed, isTrue);
      expect(p.squashW > 0 || p.squashD > 0, isTrue);
      final b = applied(r).single;
      expect(CollisionDetector(trunk).findAllCollisions([b]), isEmpty);
      // 높이 35 면 세울 수 없고(40) 눕히면 두 축을 다 눌러야 하므로 미적재
      final r2 = AutoLayoutEngine.computeLayout(plain(0.3, 0.3, 0.35), [bag]);
      expect(r2.allBoxesFit, isFalse);
    });

    test('압축률 0 인 연질 짐은 눌리지 않는다', () {
      final trunk = plain(0.5, 0.5, 0.15);
      final r = AutoLayoutEngine.computeLayout(trunk, [box('bag', 40, 40, 20, soft: true)]);
      expect(r.allBoxesFit, isFalse);
    });

    test('연질 짐은 단단한 짐을 다 놓은 뒤에 (적재 순서에서 뒤)', () {
      final trunk = plain(1.0, 1.0, 0.8);
      final r = AutoLayoutEngine.computeLayout(trunk, [
        box('bag', 40, 30, 20, soft: true, compress: 0.4),
        box('crate', 40, 30, 30, kg: 8),
        box('cooler', 50, 40, 40, kg: 20),
      ]);
      expect(r.allBoxesFit, isTrue);
      final order = {for (final p in r.placements) p.box.id: p.loadOrder};
      expect(order['bag']! > order['crate']!, isTrue);
      expect(order['bag']! > order['cooler']!, isTrue);
    });
  });

  group('무게 규칙', () {
    test('20kg 이상은 바닥에만: 바닥이 차면 위에 올리지 않고 미적재', () {
      final trunk = plain(0.5, 0.5, 0.8);
      final base = box('base', 50, 50, 20, kg: 3);
      final heavy = box('heavy', 40, 40, 30, kg: 25);
      final r = AutoLayoutEngine.computeLayout(trunk, [base, heavy]);
      // 무거운 것이 먼저 바닥을 차지하고, 가벼운 base 가 그 위로 간다
      final placed = {for (final p in r.placements) p.box.id: p};
      expect(placed['heavy']!.y, 0);
      if (placed.containsKey('base')) {
        expect(placed['base']!.y, greaterThan(0));
      }
    });

    test('단단한 5kg 이상 짐은 연질 짐 위에 놓지 않는다', () {
      final trunk = plain(0.4, 0.4, 0.8);
      final bag = box('bag', 40, 40, 20, soft: true, compress: 0.3, kg: 1.5);
      final pot = box('pot', 30, 30, 15, kg: 6);
      final r = AutoLayoutEngine.computeLayout(trunk, [bag, pot]);
      expect(r.allBoxesFit, isTrue, reason: '${r.unfitReasons}');
      final placed = {for (final p in r.placements) p.box.id: p};
      expect(placed['pot']!.y, 0, reason: '냄비가 바닥, 침낭이 위');
      expect(placed['bag']!.y, greaterThan(0));
    });

    test('자주 꺼내는 짐은 테일게이트 쪽', () {
      final trunk = plain(1.0, 1.0, 0.8);
      final r = AutoLayoutEngine.computeLayout(trunk, [
        box('cooler', 40, 30, 30, kg: 15, access: true, upright: true),
        box('tent', 60, 30, 30, kg: 10),
      ]);
      final placed = {for (final p in r.placements) p.box.id: p};
      final coolerRear = placed['cooler']!.z + placed['cooler']!.d;
      final tentRear = placed['tent']!.z + placed['tent']!.d;
      expect(coolerRear, greaterThan(tentRear));
    });
  });

  group('PackingAdvisor', () {
    final trunk = plain(1.0, 1.0, 0.8);

    test('무거운 짐이 위에 있으면 조언', () {
      final base = box('base', 50, 50, 30, kg: 4);
      final heavy = box('heavy', 40, 40, 30, kg: 20, y: 0.30);
      final advice = PackingAdvisor.advise([base, heavy], trunk);
      expect(advice.map((a) => a.kind), containsAll([AdviceKind.heavyHigh, AdviceKind.heavyOnLight]));
    });

    test('단단한 짐이 연질 짐 위에 있으면 조언, 가벼우면 괜찮다', () {
      final bag = box('bag', 50, 50, 20, soft: true, kg: 1.5);
      final pot = box('pot', 30, 30, 15, kg: 6, y: 0.20);
      expect(PackingAdvisor.advise([bag, pot], trunk).map((a) => a.kind),
          contains(AdviceKind.rigidOnSoft));
      final light = box('cup', 30, 30, 15, kg: 0.5, y: 0.20);
      expect(PackingAdvisor.advise([bag, light], trunk), isEmpty);
    });

    test('자주 꺼내는 짐이 안쪽에서 막혀 있으면 조언', () {
      final cooler = box('cooler', 40, 30, 30, kg: 15, access: true, z: 0.0);
      final blocker = box('tent', 60, 30, 30, kg: 10, z: 0.30);
      expect(PackingAdvisor.advise([cooler, blocker], trunk).map((a) => a.kind),
          contains(AdviceKind.accessBuried));
      // 트렁크 밖 (미적재) 짐은 조언 대상이 아니다
      final parked = box('p', 40, 40, 40, kg: 30, y: 0.3, z: 1.06);
      expect(PackingAdvisor.advise([parked], trunk), isEmpty);
    });

    test('가족 세트: 무거운 쿨러는 바닥, 무거운 짐 위 조언 없음, 2열 +13cm 면 전부 적재', () {
      final sorento = TrunkSpace.sorento();
      final gear = [
        for (final (id, label, sub, w, d, h) in [
          ('tent', '코베아 네스트W (4인 거실형)', 'tent', 80, 35, 35),
          ('tarp', '렉타타프 (대형/폴대 포함)', 'tarp', 80, 22, 22),
          ('table', '롤테이블 (4인/120cm)', 'tableChair', 87, 19, 17),
          ('chair1', '일반 캠핑의자 (접이식)', 'tableChair', 85, 20, 15),
          ('chair2', '일반 캠핑의자 (접이식)', 'tableChair', 85, 20, 15),
          ('chair3', '일반 캠핑의자 (접이식)', 'tableChair', 85, 20, 15),
          ('chair4', '일반 캠핑의자 (접이식)', 'tableChair', 85, 20, 15),
          ('cooler', '대형 아이스박스 (50L)', 'cooler', 60, 40, 42),
          ('bag1', '일반 침낭 (3계절)', 'sleepingGear', 40, 26, 26),
          ('bag2', '일반 침낭 (3계절)', 'sleepingGear', 40, 26, 26),
          ('bag3', '일반 침낭 (3계절)', 'sleepingGear', 40, 26, 26),
          ('bag4', '일반 침낭 (3계절)', 'sleepingGear', 40, 26, 26),
          ('burner', '코베아 슬림트윈 투버너', 'cooking', 54, 34, 7),
          ('cookset', '코펠세트 (4-5인)', 'cooking', 28, 23, 13),
          ('container', '스노우피크 쉘프컨테이너 50', 'storage', 63, 41, 27),
          ('firewood', '장작 한 묶음', 'misc', 40, 25, 20),
        ])
          () {
            final ph = gearPhysicsFor(label: label, category: 'camping', subCategory: sub, wCm: w, dCm: d, hCm: h);
            return box(id, w.toDouble(), d.toDouble(), h.toDouble(),
                soft: ph.soft, compress: ph.compress, kg: ph.weightKg, access: ph.access, upright: ph.upright);
          }(),
      ];
      // 2열 최후방: 실측 치수로는 강체 기준 15개 이상 (테이블 하나가 남을 수 있다)
      final r = AutoLayoutEngine.computeLayout(sorento, gear, restarts: 24);
      expect(r.placedCount, greaterThanOrEqualTo(15), reason: '${r.unfitReasons}');
      // 2열을 13cm 당기면 전부 들어간다
      final slid = AutoLayoutEngine.computeLayout(
          TrunkSpace.sorento(seatSlide: 0.13), gear, restarts: 24);
      expect(slid.allBoxesFit, isTrue, reason: '${slid.unfitReasons}');
      final boxes = applied(r);
      expect(CollisionDetector(sorento).findAllCollisions(boxes), isEmpty);
      for (final b in boxes) {
        expect(SupportRule.isSupported(b, boxes.where((o) => o.id != b.id), sorento), isTrue);
      }
      final advice = PackingAdvisor.advise(boxes, sorento);
      expect(advice.where((a) => a.kind == AdviceKind.heavyHigh), isEmpty,
          reason: advice.map((a) => a.message).join('; '));
      final cooler = boxes.firstWhere((b) => b.id == 'cooler');
      expect(cooler.y, 0);
    });
  });

  group('2열 슬라이드', () {
    test('앞으로 당기면 바닥이 길어지고 휠하우스는 등받이에서 멀어진다', () {
      final s0 = TrunkSpace.sorento();
      final s27 = TrunkSpace.sorento(seatSlide: 0.27);
      expect(s27.d, closeTo(s0.d + 0.27, 1e-9));
      expect(s27.leftWheelhouse.zStart, closeTo(0.27, 1e-9));
      expect(s27.leftWheelhouse.zEnd, closeTo(0.27 + s0.leftWheelhouse.d, 1e-9));
      expect(s27.floorStartZ, closeTo(0.27, 1e-9));
      expect(s27.usableVolume, greaterThan(s0.usableVolume + 0.15));
      expect(s27.officialVolumeLabel, contains('910'));
      expect(TrunkSpace.sorento7(seatSlide: 0.27).officialVolumeLabel, contains('821'));
      // JSON 왕복
      final back = TrunkSpace.fromJson(s27.toJson());
      expect(back.seatSlide, 0.27);
      expect(back.leftWheelhouse.zStart, 0.27);
    });

    test('등받이와 휠하우스 사이 새 공간에 짐을 놓을 수 있다', () {
      final s = TrunkSpace.sorento(seatSlide: 0.27);
      final det = CollisionDetector(s);
      // 왼쪽 벽에 붙여 z 0.08~0.26: 슬라이드 전에는 휠하우스 자리
      final b = box('b', 30, 18, 20, x: 0.0, z: 0.08);
      expect(det.hasCollision(b, []), isFalse);
      expect(CollisionDetector(TrunkSpace.sorento()).overlapsLeftWheelhouse(b), isTrue);
      // 휠하우스 위 지지면도 이동
      final onWheel = box('w', 14, 20, 10, x: 0.0, z: 0.30);
      expect(SupportRule.highestLevel(onWheel, [], s),
          closeTo(s.leftWheelhouse.h, 1e-9));
    });

    test('슬라이드 후에도 자동배치는 물리적으로 유효하고 더 많이 들어간다', () {
      final s0 = TrunkSpace.sorento();
      final s27 = TrunkSpace.sorento(seatSlide: 0.27);
      final gear = [for (var i = 0; i < 14; i++) box('c$i', 60, 40, 30, kg: 8)];
      final r0 = AutoLayoutEngine.computeLayout(s0, gear);
      final r27 = AutoLayoutEngine.computeLayout(s27, gear);
      expect(r27.placedCount, greaterThan(r0.placedCount));
      final boxes = applied(r27);
      expect(CollisionDetector(s27).findAllCollisions(boxes), isEmpty);
      for (final b in boxes) {
        expect(SupportRule.isSupported(b, boxes.where((o) => o.id != b.id), s27), isTrue);
      }
    });
  });
}
