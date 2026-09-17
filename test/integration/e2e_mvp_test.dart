import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/models/scene.dart';
import 'package:trimbox/utils/collision.dart';

TrimBox _box(String id, double w, double d, double h,
    {BoxCategory category = BoxCategory.camping}) =>
    TrimBox(
      id: id,
      label: id,
      w: w,
      d: d,
      h: h,
      color: const Color(0xFFFF0000),
      category: category,
    );

void main() {
  // ─────────────────────────────────────────────
  // E2E-1: Full MVP user journey
  // 차 선택 → 장비 선택 → 자동 배치 → 결과 확인
  // ─────────────────────────────────────────────
  group('E2E-1: Full MVP user journey (3-second promise)', () {
    test('Sorento + 4인 캠핑세트 → 자동배치 → 결과 확인', () {
      // Step 1: 차량 선택 (쏘렌토)
      final trunk = TrunkSpace.sorento();
      expect(trunk.w, 1.08);
      expect(trunk.d, 1.10);
      expect(trunk.h, 0.78);
      expect(trunk.vehicleName, contains('SORENTO'));

      // Step 2: 캠핑 장비 선택 (4인 기본세트)
      final boxes = [
        _box('쿨러 50L', 0.58, 0.38, 0.38),
        _box('텐트 4인용', 0.65, 0.22, 0.22),
        _box('캠핑의자 x2', 0.13, 0.13, 0.90),
        _box('캠핑테이블', 0.60, 0.12, 0.08),
        _box('침낭 x2', 0.42, 0.25, 0.25),
        _box('버너+코펠', 0.35, 0.25, 0.15),
        _box('랜턴', 0.12, 0.12, 0.25),
      ];

      // Step 3: 자동배치 (3초 이내)
      final stopwatch = Stopwatch()..start();
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      stopwatch.stop();

      // AC: 3초 이내 결과
      expect(stopwatch.elapsedMilliseconds, lessThan(3000),
          reason: 'Auto-layout must complete within 3 seconds');

      // Step 4: 결과 확인
      expect(result.placements, isNotEmpty);
      expect(result.utilizationPercent, greaterThan(0));

      // 모든 배치된 박스가 트렁크 안에 있는지 검증
      final cd = CollisionDetector(trunk);
      for (final p in result.placements) {
        final placed = p.box.copyWith();
        p.applyTo(placed);
        expect(cd.isOutOfBounds(placed), isFalse,
            reason: '${p.box.label} is out of bounds');
      }

      // 배치된 박스끼리 겹치지 않는지 검증
      final placedBoxes = result.placements.map((p) {
        final b = p.box.copyWith();
        p.applyTo(b);
        return b;
      }).toList();

      for (int i = 0; i < placedBoxes.length; i++) {
        for (int j = i + 1; j < placedBoxes.length; j++) {
          expect(cd.boxesOverlap(placedBoxes[i], placedBoxes[j]), isFalse,
              reason:
                  '${placedBoxes[i].label} overlaps ${placedBoxes[j].label}');
        }
      }
    });

    test('모든 차종 × 기본 캠핑세트 → 자동배치 정상 완료', () {
      final campingSet = [
        _box('쿨러', 0.40, 0.30, 0.30),
        _box('텐트', 0.60, 0.20, 0.20),
        _box('의자', 0.12, 0.12, 0.80),
        _box('테이블', 0.60, 0.10, 0.10),
        _box('침낭', 0.42, 0.25, 0.25),
      ];

      for (final preset in TrunkPreset.values) {
        final trunk = preset.toTrunkSpace();
        if (trunk == null) continue;

        final result = AutoLayoutEngine.computeLayout(trunk, campingSet);

        // 크래시 없이 완료
        expect(result.placements, isNotNull,
            reason: '${preset.name} layout crashed');
        expect(result.utilizationPercent, greaterThanOrEqualTo(0),
            reason: '${preset.name} utilization negative');

        // 모든 배치가 경계 내
        for (final p in result.placements) {
          expect(p.x, greaterThanOrEqualTo(-0.01),
              reason: '${preset.name}: ${p.box.label} x<0');
          expect(p.z, greaterThanOrEqualTo(-0.01),
              reason: '${preset.name}: ${p.box.label} z<0');
          expect(p.y, greaterThanOrEqualTo(-0.01),
              reason: '${preset.name}: ${p.box.label} y<0');
        }
      }
    });
  });

  // ─────────────────────────────────────────────
  // E2E-2: 3 전략 비교 (generateAlternatives)
  // ─────────────────────────────────────────────
  group('E2E-2: Strategy comparison flow', () {
    test('3 전략 모두 유효한 결과 반환 + 추천 배지 존재', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('쿨러', 0.40, 0.30, 0.30),
        _box('텐트', 0.60, 0.20, 0.20),
        _box('의자', 0.12, 0.12, 0.80),
      ];

      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      expect(alts.length, 3);

      // 각 전략이 고유
      final strategies = alts.map((a) => a.strategy).toSet();
      expect(strategies.length, 3);

      // 모든 전략이 라벨 보유
      for (final alt in alts) {
        expect(alt.strategy.label.isNotEmpty, isTrue);
        expect(alt.utilizationPercent, greaterThanOrEqualTo(0));
      }

      // 최소 하나의 전략이 박스를 배치
      expect(alts.any((a) => a.placements.isNotEmpty), isTrue);
    });

    test('전략별 적재율 차이 검증 (maxUtilization >= balanced)', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.35, 0.25, 0.25),
        _box('c', 0.30, 0.20, 0.20),
        _box('d', 0.25, 0.25, 0.25),
        _box('e', 0.20, 0.15, 0.15),
      ];

      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      final maxUtil = alts.firstWhere(
          (a) => a.strategy == LayoutStrategy.maxUtilization);
      final balanced = alts.firstWhere(
          (a) => a.strategy == LayoutStrategy.balanced);

      // maxUtilization은 balanced 이상의 적재율
      expect(maxUtil.utilizationPercent,
          greaterThanOrEqualTo(balanced.utilizationPercent - 1),
          reason: 'maxUtilization should pack at least as well as balanced');
    });
  });

  // ─────────────────────────────────────────────
  // E2E-3: 적재 순서 가이드 + 스텝 뷰
  // ─────────────────────────────────────────────
  group('E2E-3: Load order and step view', () {
    test('적재 순서: 깊은 곳(z 작은) 먼저 → 입구(z 큰) 나중', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('입구쪽', 0.30, 0.30, 0.30),
        _box('깊숙이', 0.30, 0.30, 0.30),
        _box('중간', 0.30, 0.30, 0.30),
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      if (result.placements.length >= 2) {
        // loadOrder 1 (먼저 적재) = z가 작은 쪽 (깊숙이)
        final sorted = List.of(result.placements)
          ..sort((a, b) => a.loadOrder.compareTo(b.loadOrder));

        // 먼저 적재하는 박스가 더 깊숙이 있어야 함
        for (int i = 0; i < sorted.length - 1; i++) {
          expect(sorted[i].z, lessThanOrEqualTo(sorted[i + 1].z + 0.01),
              reason: 'Load order ${sorted[i].loadOrder} should be deeper '
                  'than ${sorted[i + 1].loadOrder}');
        }
      }
    });

    test('스텝 뷰 필터링: step N까지의 박스만 표시', () {
      final trunk = TrunkSpace.sorento();
      final boxes = List.generate(5, (i) =>
          _box('box_$i', 0.20, 0.20, 0.20));

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // loadOrder를 박스에 적용
      for (final p in result.placements) {
        final box = boxes.firstWhere((b) => b.id == p.box.id);
        box.loadOrder = p.loadOrder;
      }

      // 각 스텝에서 올바른 수의 박스가 보여야 함
      for (int step = 1; step <= result.placements.length; step++) {
        final visible = boxes.where((b) =>
            b.loadOrder != null && b.loadOrder! <= step).toList();
        expect(visible.length, step,
            reason: 'Step $step should show $step boxes');
      }
    });
  });

  // ─────────────────────────────────────────────
  // E2E-4: 충돌 감지 통합
  // ─────────────────────────────────────────────
  group('E2E-4: Collision detection integration', () {
    test('자동배치 결과는 충돌 0개', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.35, 0.25, 0.25),
        _box('c', 0.30, 0.20, 0.20),
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      final cd = CollisionDetector(trunk);

      // 배치 결과로 박스 위치 설정
      final placed = <TrimBox>[];
      for (final p in result.placements) {
        final b = p.box.copyWith();
        p.applyTo(b);
        placed.add(b);
      }

      // 충돌 감지
      final collisions = cd.findAllCollisions(placed);
      expect(collisions, isEmpty,
          reason: 'Auto-layout should produce zero collisions');
    });

    test('휠하우스 회피 검증', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('big', 0.50, 0.50, 0.25), // 휠하우스 근처에 놓일 수 있는 크기
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      final cd = CollisionDetector(trunk);

      for (final p in result.placements) {
        final b = p.box.copyWith();
        p.applyTo(b);
        expect(cd.overlapsLeftWheelhouse(b), isFalse,
            reason: '${b.label} overlaps left wheelhouse');
        expect(cd.overlapsRightWheelhouse(b), isFalse,
            reason: '${b.label} overlaps right wheelhouse');
      }
    });

    test('수동 배치: 겹침 감지', () {
      final trunk = TrunkSpace.sorento();
      final cd = CollisionDetector(trunk);

      final a = _box('a', 0.30, 0.30, 0.30)..x = 0.1..z = 0.1;
      final b = _box('b', 0.30, 0.30, 0.30)..x = 0.2..z = 0.2; // 겹침

      expect(cd.boxesOverlap(a, b), isTrue);

      // 멀리 이동하면 겹침 해소
      b.x = 0.5;
      b.z = 0.5;
      expect(cd.boxesOverlap(a, b), isFalse);
    });

    test('경계 초과 감지', () {
      final trunk = TrunkSpace.sorento();
      final cd = CollisionDetector(trunk);

      final box = _box('overflow', 0.30, 0.30, 0.30);
      box.x = trunk.w; // 오른쪽 경계 밖
      expect(cd.isOutOfBounds(box), isTrue);

      box.x = -0.1; // 왼쪽 경계 밖
      expect(cd.isOutOfBounds(box), isTrue);

      box.x = 0.1; // 정상
      box.z = 0.1;
      expect(cd.isOutOfBounds(box), isFalse);
    });

    test('높이 초과 감지', () {
      final trunk = TrunkSpace.sorento();
      final cd = CollisionDetector(trunk);

      // z=0(깊은 곳)에서 천장높이 = h - ceilingDrop = 0.66m
      final box = _box('tall', 0.20, 0.20, trunk.h + 0.1);
      expect(cd.isOverHeight(box), isTrue);

      // 개구부(z=d) 근처에서는 천장높이가 h와 동일
      final normalBox = _box('normal', 0.20, 0.20, trunk.h - 0.1);
      normalBox.z = trunk.d - 0.20; // 개구부 근처에 배치
      expect(cd.isOverHeight(normalBox), isFalse);
    });
  });

  // ─────────────────────────────────────────────
  // E2E-5: Scene JSON 직렬화 왕복 (save/load)
  // ─────────────────────────────────────────────
  group('E2E-5: Scene serialization roundtrip', () {
    test('Scene → JSON → Scene 완전 복원', () {
      final original = Scene(
        space: TrunkSpace.sorento(),
        boxes: [
          _box('쿨러', 0.40, 0.30, 0.30)..x = 0.1..z = 0.2,
          _box('텐트', 0.60, 0.20, 0.20)..x = 0.5..z = 0.1..rotY = 90,
        ],
      );

      final jsonStr = original.toJsonString();
      final restored = Scene.fromJsonString(jsonStr);

      expect(restored.space.w, original.space.w);
      expect(restored.space.d, original.space.d);
      expect(restored.space.h, original.space.h);
      expect(restored.space.vehicleName, original.space.vehicleName);
      expect(restored.boxes.length, original.boxes.length);

      for (int i = 0; i < original.boxes.length; i++) {
        expect(restored.boxes[i].id, original.boxes[i].id);
        expect(restored.boxes[i].label, original.boxes[i].label);
        expect(restored.boxes[i].w, original.boxes[i].w);
        expect(restored.boxes[i].d, original.boxes[i].d);
        expect(restored.boxes[i].h, original.boxes[i].h);
        expect(restored.boxes[i].x, original.boxes[i].x);
        expect(restored.boxes[i].z, original.boxes[i].z);
        expect(restored.boxes[i].rotY, original.boxes[i].rotY);
      }
    });

    test('모든 차종 프리셋 JSON 왕복', () {
      for (final preset in TrunkPreset.values) {
        final trunk = preset.toTrunkSpace();
        if (trunk == null) continue;

        final scene = Scene(space: trunk, boxes: []);
        final restored = Scene.fromJsonString(scene.toJsonString());

        expect(restored.space.w, trunk.w,
            reason: '${preset.name} w mismatch');
        expect(restored.space.d, trunk.d,
            reason: '${preset.name} d mismatch');
        expect(restored.space.h, trunk.h,
            reason: '${preset.name} h mismatch');
        expect(restored.space.taperRatio, trunk.taperRatio,
            reason: '${preset.name} taperRatio mismatch');
        expect(restored.space.ceilingDrop, trunk.ceilingDrop,
            reason: '${preset.name} ceilingDrop mismatch');
        expect(restored.space.bodyColor, trunk.bodyColor,
            reason: '${preset.name} bodyColor mismatch');
      }
    });

    test('회전된 박스 직렬화 보존', () {
      final box = _box('rotated', 0.40, 0.20, 0.30);
      box.rotY = 90;
      box.x = 0.15;
      box.z = 0.25;

      expect(box.effectiveW, 0.20); // rotated: d becomes effectiveW
      expect(box.effectiveD, 0.40);

      final scene = Scene(space: TrunkSpace.sorento(), boxes: [box]);
      final restored = Scene.fromJsonString(scene.toJsonString());

      expect(restored.boxes[0].rotY, 90);
      expect(restored.boxes[0].effectiveW, 0.20);
      expect(restored.boxes[0].effectiveD, 0.40);
    });
  });

  // ─────────────────────────────────────────────
  // E2E-6: 프리셋 치수 정확도 (P0-2 regression guard)
  // ─────────────────────────────────────────────
  group('E2E-6: Vehicle preset dimension accuracy', () {
    test('쏘렌토 치수 정확 (h=0.78, wh.w=0.08)', () {
      final s = TrunkSpace.sorento();
      expect(s.w, 1.08);
      expect(s.d, 1.10);
      expect(s.h, 0.78);
      expect(s.leftWheelhouse.w, 0.08);
      expect(s.rightWheelhouse.w, 0.08);
    });

    test('싼타페 치수 정확 (w=1.11, wh.w=0.13)', () {
      final s = TrunkSpace.santafe();
      expect(s.w, 1.11);
      expect(s.d, 1.05);
      expect(s.h, 0.80);
      expect(s.leftWheelhouse.w, 0.13);
      expect(s.rightWheelhouse.w, 0.13);
    });

    test('모든 프리셋 적재량(L) 양수', () {
      for (final preset in TrunkPreset.values) {
        final vol = preset.volumeLiters;
        if (vol == null) continue; // custom
        expect(vol, greaterThan(0),
            reason: '${preset.name} volume should be positive');
      }
    });

    test('트렁크 형상 함수 일관성', () {
      for (final preset in TrunkPreset.values) {
        final trunk = preset.toTrunkSpace();
        if (trunk == null) continue;

        // z=d (입구)에서 천장 높이 = h (드롭 없음)
        expect(trunk.ceilingHeightAt(trunk.d), closeTo(trunk.h, 0.001),
            reason: '${preset.name} ceiling at opening should equal h');

        // z=0 (뒤)에서 천장 높이 <= h
        expect(trunk.ceilingHeightAt(0), lessThanOrEqualTo(trunk.h),
            reason: '${preset.name} ceiling at rear should be <= h');

        // 테이퍼: z=d (입구) = 0
        expect(trunk.taperAt(trunk.d), closeTo(0, 0.001),
            reason: '${preset.name} taper at opening should be 0');

        // 상단 좁아짐: z=d = 0
        expect(trunk.topNarrowAt(trunk.d), closeTo(0, 0.001),
            reason: '${preset.name} topNarrow at opening should be 0');
      }
    });
  });

  // ─────────────────────────────────────────────
  // E2E-7: 공유 카드 텍스트 생성
  // ─────────────────────────────────────────────
  group('E2E-7: Share card generation', () {
    test('공유 텍스트 포맷 완전성', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('쿨러', 0.40, 0.30, 0.30),
        _box('텐트', 0.60, 0.20, 0.20),
        _box('의자', 0.12, 0.12, 0.80),
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      final volPct = result.utilizationPercent.round();

      // 공유 텍스트 생성 (simulator_screen 로직 재현)
      final sb = StringBuffer();
      sb.writeln('${trunk.vehicleName} 트렁크 적재 시뮬레이션');
      sb.writeln('적재율: $volPct%');
      sb.writeln('장비 ${boxes.length}개:');
      for (final b in boxes) {
        sb.writeln('  - ${b.label} '
            '(${(b.w * 100).round()}x${(b.d * 100).round()}x${(b.h * 100).round()}cm)');
      }
      sb.writeln('#TrimBox #캠핑 #트렁크패킹');
      final text = sb.toString();

      expect(text, contains('SORENTO'));
      expect(text, contains('적재율:'));
      expect(text, contains('장비 3개'));
      expect(text, contains('쿨러'));
      expect(text, contains('텐트'));
      expect(text, contains('의자'));
      expect(text, contains('#TrimBox'));
      expect(text, contains('#캠핑'));
      expect(text, contains('40x30x30cm'));
    });
  });

  // ─────────────────────────────────────────────
  // E2E-8: TrimBox 모델 무결성
  // ─────────────────────────────────────────────
  group('E2E-8: TrimBox model integrity', () {
    test('회전 + 그리드 스냅 + 클램핑 통합', () {
      final trunk = TrunkSpace.sorento();
      final box = _box('test', 0.40, 0.20, 0.30);

      // 초기 상태
      expect(box.effectiveW, 0.40);
      expect(box.effectiveD, 0.20);

      // 90도 회전
      box.rotate90();
      expect(box.rotY, 90);
      expect(box.effectiveW, 0.20); // swapped
      expect(box.effectiveD, 0.40);

      // 경계 밖으로 이동 후 클램핑
      box.x = 2.0;
      box.z = 2.0;
      box.clampTo(trunk.w, trunk.d);
      expect(box.x, lessThanOrEqualTo(trunk.w - box.effectiveW));
      expect(box.z, lessThanOrEqualTo(trunk.d - box.effectiveD));

      // 그리드 스냅
      box.x = 0.123;
      box.z = 0.456;
      box.snapToGrid(0.01);
      expect(box.x, closeTo(0.12, 0.005));
      expect(box.z, closeTo(0.46, 0.005));
    });

    test('copyWith 모든 필드 보존', () {
      final box = _box('orig', 0.30, 0.25, 0.20);
      box.x = 0.1;
      box.y = 0.05;
      box.z = 0.2;
      box.rotY = 90;
      box.loadOrder = 3;

      final copy = box.copyWith();
      expect(copy.id, box.id);
      expect(copy.label, box.label);
      expect(copy.w, box.w);
      expect(copy.d, box.d);
      expect(copy.h, box.h);
      expect(copy.x, box.x);
      expect(copy.y, box.y);
      expect(copy.z, box.z);
      expect(copy.rotY, box.rotY);
      expect(copy.loadOrder, box.loadOrder);
    });

    test('copyWith 필드 오버라이드', () {
      final box = _box('orig', 0.30, 0.25, 0.20);
      final copy = box.copyWith(x: 0.5, z: 0.6, loadOrder: 7);
      expect(copy.x, 0.5);
      expect(copy.z, 0.6);
      expect(copy.loadOrder, 7);
      expect(copy.w, box.w); // 변경 안 된 필드 유지
    });
  });

  // ─────────────────────────────────────────────
  // E2E-9: 대량 박스 스트레스 테스트
  // ─────────────────────────────────────────────
  group('E2E-9: Stress test — many boxes', () {
    test('20개 박스 자동배치 3초 이내', () {
      final trunk = TrunkSpace.sorento();
      final boxes = List.generate(20, (i) =>
          _box('box_$i', 0.15 + (i % 5) * 0.05, 0.10 + (i % 3) * 0.05, 0.10 + (i % 4) * 0.05));

      final stopwatch = Stopwatch()..start();
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(3000),
          reason: '20 boxes × 3 strategies must complete in 3 seconds');
      expect(alts.length, 3);
    });

    test('30개 박스 자동배치 크래시 없음', () {
      final trunk = TrunkSpace.carnival(); // 가장 큰 트렁크
      final boxes = List.generate(30, (i) =>
          _box('box_$i', 0.10 + (i % 4) * 0.03, 0.08 + (i % 3) * 0.03, 0.08 + (i % 5) * 0.02));

      // 크래시 없이 완료되면 성공
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements, isNotNull);
      expect(result.utilizationPercent, greaterThanOrEqualTo(0));
    });

    test('아반떼(세단) 트렁크에 큰 짐 → 적재 불가 정확 판정', () {
      final trunk = TrunkSpace.avante(); // 가장 작은 트렁크
      final boxes = [
        _box('거대쿨러', 0.70, 0.50, 0.50), // 트렁크보다 큰 깊이
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.allBoxesFit, isFalse);
      expect(result.unfitBoxes, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────
  // E2E-10: 스태킹 (y축 적재)
  // ─────────────────────────────────────────────
  group('E2E-10: Stacking behavior', () {
    test('자동배치 스태킹: 바닥 위에 쌓기', () {
      final trunk = TrunkSpace.sorento();
      // 의도적으로 바닥 면적보다 많은 짐
      final boxes = [
        _box('big1', 0.50, 0.50, 0.20),
        _box('big2', 0.50, 0.50, 0.20),
        _box('big3', 0.50, 0.50, 0.20),
        _box('big4', 0.50, 0.50, 0.20),
        _box('big5', 0.50, 0.50, 0.20),
        _box('small_top', 0.30, 0.30, 0.15),
      ];

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // 일부 박스가 y > 0에 배치되어야 함 (스태킹)
      final stackedCount = result.placements.where((p) => p.y > 0.01).length;
      // 바닥 면적이 부족하므로 스태킹 발생
      if (result.placements.length > 4) {
        expect(stackedCount, greaterThan(0),
            reason: 'Should stack boxes when floor area is insufficient');
      }
    });

    test('스태킹된 박스 높이 초과 불가', () {
      final trunk = TrunkSpace.sorento();
      final boxes = List.generate(10, (i) =>
          _box('box_$i', 0.30, 0.30, 0.25));

      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      for (final p in result.placements) {
        expect(p.y + p.box.h, lessThanOrEqualTo(trunk.h + 0.01),
            reason: '${p.box.label} exceeds trunk height');
      }
    });
  });
}
