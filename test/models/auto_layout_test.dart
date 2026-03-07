import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';

TrimBox _box(String id, double w, double d, double h) => TrimBox(
      id: id,
      label: id,
      w: w,
      d: d,
      h: h,
      color: const Color(0xFFFF0000),
    );

void main() {
  group('AutoLayoutEngine', () {
    late TrunkSpace trunk;

    setUp(() {
      // Simple rectangular trunk for testing: 1.0 x 1.0 x 1.0m, no wheelhousees
      trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
    });

    test('empty box list returns empty result', () {
      final result = AutoLayoutEngine.computeLayout(trunk, []);
      expect(result.placements, isEmpty);
      expect(result.allBoxesFit, isTrue);
      expect(result.unfitBoxes, isEmpty);
      expect(result.utilizationPercent, 0);
    });

    test('single box is placed at origin', () {
      final boxes = [_box('a', 0.3, 0.3, 0.3)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 1);
      expect(result.allBoxesFit, isTrue);
      expect(result.placements[0].x, closeTo(0, 0.01));
      expect(result.placements[0].y, closeTo(0, 0.01));
      expect(result.placements[0].z, closeTo(0, 0.01));
    });

    test('two non-overlapping boxes are both placed', () {
      final boxes = [_box('a', 0.4, 0.4, 0.4), _box('b', 0.4, 0.4, 0.4)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 2);
      expect(result.allBoxesFit, isTrue);

      // Verify no overlap
      final p1 = result.placements[0];
      final p2 = result.placements[1];
      final w1 = p1.rotated ? p1.box.d : p1.box.w;
      final d1 = p1.rotated ? p1.box.w : p1.box.d;
      final w2 = p2.rotated ? p2.box.d : p2.box.w;
      final d2 = p2.rotated ? p2.box.w : p2.box.d;

      // At least one axis must be non-overlapping
      final sepX = p1.x + w1 <= p2.x + 0.01 || p2.x + w2 <= p1.x + 0.01;
      final sepY = p1.y + p1.box.h <= p2.y + 0.01 || p2.y + p2.box.h <= p1.y + 0.01;
      final sepZ = p1.z + d1 <= p2.z + 0.01 || p2.z + d2 <= p1.z + 0.01;
      expect(sepX || sepY || sepZ, isTrue);
    });

    test('box too large for trunk is reported as unfit', () {
      final boxes = [_box('big', 1.5, 1.5, 1.5)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements, isEmpty);
      expect(result.allBoxesFit, isFalse);
      expect(result.unfitBoxes.length, 1);
      expect(result.unfitBoxes[0].id, 'big');
    });

    test('stacking: small box placed on top of large box', () {
      final boxes = [
        _box('large', 0.8, 0.8, 0.3),
        _box('small', 0.3, 0.3, 0.3),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 2);
      expect(result.allBoxesFit, isTrue);
    });

    test('utilization percent is calculated correctly', () {
      // Box that fills exactly 50% of the volume
      final boxes = [_box('half', 1.0, 1.0, 0.5)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.utilizationPercent, closeTo(50, 1));
    });

    test('BFD sorts largest volume first', () {
      final boxes = [
        _box('small', 0.1, 0.1, 0.1),
        _box('large', 0.5, 0.5, 0.5),
        _box('medium', 0.3, 0.3, 0.3),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      // Large box should be placed first (loadOrder 1)
      final largePlacement = result.placements.firstWhere((p) => p.box.id == 'large');
      expect(largePlacement.loadOrder, 1);
    });

    test('wheelhouse avoidance works', () {
      final trunkWithWH = TrunkSpace(
        w: 1.0,
        d: 1.0,
        h: 1.0,
        leftWheelhouse: const Wheelhouse(w: 0.3, d: 0.4, h: 0.3),
        rightWheelhouse: const Wheelhouse(w: 0.3, d: 0.4, h: 0.3),
      );
      // Box that would overlap with wheelhousees if placed at corners
      final boxes = [_box('a', 0.5, 0.5, 0.2)];
      final result = AutoLayoutEngine.computeLayout(trunkWithWH, boxes);
      expect(result.placements.length, 1);

      // Verify not overlapping with left wheelhouse
      final p = result.placements[0];
      final pw = p.rotated ? p.box.d : p.box.w;
      final pd = p.rotated ? p.box.w : p.box.d;

      // Left WH: x=[0, 0.3], z=[0.6, 1.0], y=[0, 0.3]
      final overlapsLeft = p.x < 0.3 && p.x + pw > 0 &&
          p.z < 1.0 && p.z + pd > 0.6 &&
          p.y < 0.3 && p.y + p.box.h > 0;
      // Right WH: x=[0.7, 1.0], z=[0.6, 1.0], y=[0, 0.3]
      final overlapsRight = p.x < 1.0 && p.x + pw > 0.7 &&
          p.z < 1.0 && p.z + pd > 0.6 &&
          p.y < 0.3 && p.y + p.box.h > 0;
      expect(overlapsLeft, isFalse);
      expect(overlapsRight, isFalse);
    });

    test('ceiling height constraint respected', () {
      final lowCeilingTrunk = const TrunkSpace(
        w: 1.0,
        d: 1.0,
        h: 0.8,
        leftWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        rightWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        ceilingDrop: 0.3, // significant ceiling drop at the back
      );
      // Tall box that only fits near the opening
      final boxes = [_box('tall', 0.3, 0.3, 0.7)];
      final result = AutoLayoutEngine.computeLayout(lowCeilingTrunk, boxes);
      if (result.placements.isNotEmpty) {
        final p = result.placements[0];
        // Must be placed where ceiling is high enough
        final ceilAtZ = lowCeilingTrunk.ceilingHeightAt(p.z);
        expect(p.y + p.box.h, lessThanOrEqualTo(ceilAtZ + 0.01));
      }
    });

    test('rotation is used when needed', () {
      // Narrow trunk, box only fits when rotated
      final narrowTrunk = TrunkSpace.custom(w: 0.3, d: 1.0, h: 1.0);
      final boxes = [_box('wide', 0.5, 0.2, 0.2)]; // w=0.5 > 0.3, but d=0.2 fits
      final result = AutoLayoutEngine.computeLayout(narrowTrunk, boxes);
      expect(result.placements.length, 1);
      expect(result.placements[0].rotated, isTrue);
    });

    test('load order is sequential', () {
      final boxes = [
        _box('a', 0.3, 0.3, 0.3),
        _box('b', 0.2, 0.2, 0.2),
        _box('c', 0.1, 0.1, 0.1),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 3);
      for (int i = 0; i < result.placements.length; i++) {
        expect(result.placements[i].loadOrder, i + 1);
      }
    });
  });

  group('AutoLayoutEngine.generateAlternatives', () {
    test('returns 3 alternatives (one per strategy)', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = [
        _box('a', 0.3, 0.3, 0.3),
        _box('b', 0.2, 0.2, 0.2),
      ];
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      expect(alts.length, 3);
      // Each should have a different strategy
      final strategies = alts.map((a) => a.strategy).toSet();
      expect(strategies.length, 3);
    });

    test('alternatives are sorted by utilization descending', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = [
        _box('a', 0.4, 0.4, 0.4),
        _box('b', 0.3, 0.3, 0.3),
        _box('c', 0.2, 0.2, 0.2),
      ];
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      for (int i = 1; i < alts.length; i++) {
        expect(alts[i - 1].utilizationPercent,
            greaterThanOrEqualTo(alts[i].utilizationPercent));
      }
    });
  });

  group('AutoLayoutEngine with real vehicle presets', () {
    test('Sorento trunk fits multiple boxes', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('cooler', 0.40, 0.30, 0.30),
        _box('tent', 0.60, 0.20, 0.20),
        _box('bag', 0.30, 0.30, 0.25),
        _box('snack', 0.20, 0.20, 0.15),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, greaterThanOrEqualTo(3));
      expect(result.utilizationPercent, greaterThan(0));
    });

    test('easyAccess strategy places near opening (high z)', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.3, 0.3, 0.3),
        _box('b', 0.2, 0.2, 0.2),
      ];
      final balanced = AutoLayoutEngine.computeLayout(
          trunk, boxes, strategy: LayoutStrategy.balanced);
      final easy = AutoLayoutEngine.computeLayout(
          trunk, boxes, strategy: LayoutStrategy.easyAccess);

      // easyAccess should have higher average z (closer to opening)
      if (balanced.placements.isNotEmpty && easy.placements.isNotEmpty) {
        final avgZBalanced = balanced.placements
            .map((p) => p.z).reduce((a, b) => a + b) / balanced.placements.length;
        final avgZEasy = easy.placements
            .map((p) => p.z).reduce((a, b) => a + b) / easy.placements.length;
        expect(avgZEasy, greaterThanOrEqualTo(avgZBalanced - 0.01));
      }
    });
  });

  group('LayoutStrategy', () {
    test('label returns Korean text', () {
      expect(LayoutStrategy.balanced.label, isNotEmpty);
      expect(LayoutStrategy.maxUtilization.label, isNotEmpty);
      expect(LayoutStrategy.easyAccess.label, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Stress & Edge-Case Tests (Murat — Test Architect)
  // ═══════════════════════════════════════════════════════════════════

  group('Edge Cases', () {
    test('10 identical boxes — no overlaps', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = List.generate(10, (i) => _box('id_$i', 0.2, 0.2, 0.2));
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // All should fit (10 * 0.008 = 0.08 m³ vs 1.0 m³ trunk)
      expect(result.allBoxesFit, isTrue);
      expect(result.placements.length, 10);

      // Verify no pairwise AABB overlap
      for (int i = 0; i < result.placements.length; i++) {
        final pi = result.placements[i];
        final wi = pi.rotated ? pi.box.d : pi.box.w;
        final di = pi.rotated ? pi.box.w : pi.box.d;
        for (int j = i + 1; j < result.placements.length; j++) {
          final pj = result.placements[j];
          final wj = pj.rotated ? pj.box.d : pj.box.w;
          final dj = pj.rotated ? pj.box.w : pj.box.d;

          final overlapX = pi.x < pj.x + wj && pi.x + wi > pj.x;
          final overlapY = pi.y < pj.y + pj.box.h && pi.y + pi.box.h > pj.y;
          final overlapZ = pi.z < pj.z + dj && pi.z + di > pj.z;
          final overlaps = overlapX && overlapY && overlapZ;
          expect(overlaps, isFalse,
              reason: 'Box ${pi.box.id} overlaps ${pj.box.id}');
        }
      }
    });

    test('one huge box fills entire trunk — utilization near 100%', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = [_box('huge', 1.0, 1.0, 1.0)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 1);
      expect(result.allBoxesFit, isTrue);
      expect(result.utilizationPercent, closeTo(100, 1));
    });

    test('30 tiny boxes (10x10x10cm) all fit in standard trunk', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes =
          List.generate(30, (i) => _box('tiny_$i', 0.10, 0.10, 0.10));
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      // 30 * 0.001 = 0.03 m³ — should easily fit in 1.0 m³
      expect(result.allBoxesFit, isTrue);
      expect(result.placements.length, 30);
    });

    test('box exactly matching trunk dimensions', () {
      final trunk = TrunkSpace.custom(w: 0.80, d: 0.60, h: 0.50);
      final boxes = [_box('exact', 0.80, 0.60, 0.50)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 1);
      expect(result.allBoxesFit, isTrue);
      expect(result.utilizationPercent, closeTo(100, 1));
    });

    test('box height equals ceiling at back (z=0) with ceilingDrop', () {
      // At z=0 ceiling = h - ceilingDrop*(1-0)^2 = 0.8 - 0.2 = 0.6
      final trunk = const TrunkSpace(
        w: 1.0,
        d: 1.0,
        h: 0.8,
        leftWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        rightWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        ceilingDrop: 0.2,
      );
      // Box that is exactly 0.6 tall — can fit at z=0
      final boxes = [_box('tall_back', 0.3, 0.3, 0.60)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 1);
      // If placed at z=0, verify height respects ceiling
      final p = result.placements[0];
      final ceilAtZ = trunk.ceilingHeightAt(p.z);
      final ceilAtZEnd =
          trunk.ceilingHeightAt(p.z + (p.rotated ? p.box.w : p.box.d));
      final minCeiling = ceilAtZ < ceilAtZEnd ? ceilAtZ : ceilAtZEnd;
      expect(p.y + p.box.h, lessThanOrEqualTo(minCeiling + 0.01));
    });
  });

  group('Property-Based Validation', () {
    // Helper to run property checks on any result
    void verifyNoOverlaps(AutoLayoutResult result) {
      final placements = result.placements;
      for (int i = 0; i < placements.length; i++) {
        final pi = placements[i];
        final wi = pi.rotated ? pi.box.d : pi.box.w;
        final di = pi.rotated ? pi.box.w : pi.box.d;
        for (int j = i + 1; j < placements.length; j++) {
          final pj = placements[j];
          final wj = pj.rotated ? pj.box.d : pj.box.w;
          final dj = pj.rotated ? pj.box.w : pj.box.d;

          final overlapX = pi.x < pj.x + wj + -0.001 && pi.x + wi > pj.x + 0.001;
          final overlapY =
              pi.y < pj.y + pj.box.h - 0.001 && pi.y + pi.box.h > pj.y + 0.001;
          final overlapZ =
              pi.z < pj.z + dj - 0.001 && pi.z + di > pj.z + 0.001;
          expect(overlapX && overlapY && overlapZ, isFalse,
              reason:
                  'Overlap: ${pi.box.id}@(${pi.x},${pi.y},${pi.z}) vs ${pj.box.id}@(${pj.x},${pj.y},${pj.z})');
        }
      }
    }

    test('no placement overlaps — mixed box sizes on Sorento', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.30, 0.30, 0.25),
        _box('c', 0.20, 0.20, 0.20),
        _box('d', 0.50, 0.25, 0.20),
        _box('e', 0.15, 0.15, 0.15),
        _box('f', 0.35, 0.20, 0.25),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      verifyNoOverlaps(result);
    });

    test('all placements within bounds', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.25, 0.25, 0.20),
        _box('c', 0.30, 0.20, 0.35),
        _box('d', 0.20, 0.20, 0.15),
        _box('e', 0.35, 0.30, 0.25),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      for (final p in result.placements) {
        final pw = p.rotated ? p.box.d : p.box.w;
        final pd = p.rotated ? p.box.w : p.box.d;
        expect(p.x, greaterThanOrEqualTo(-0.01),
            reason: '${p.box.id} x=${p.x} out of bounds');
        expect(p.y, greaterThanOrEqualTo(-0.01),
            reason: '${p.box.id} y=${p.y} out of bounds');
        expect(p.z, greaterThanOrEqualTo(-0.01),
            reason: '${p.box.id} z=${p.z} out of bounds');
        expect(p.x + pw, lessThanOrEqualTo(trunk.w + 0.01),
            reason: '${p.box.id} x+w=${p.x + pw} exceeds trunk.w=${trunk.w}');
        expect(p.z + pd, lessThanOrEqualTo(trunk.d + 0.01),
            reason: '${p.box.id} z+d=${p.z + pd} exceeds trunk.d=${trunk.d}');
      }
    });

    test('all placements respect ceiling height', () {
      final trunk = TrunkSpace.sorento(); // has ceilingDrop=0.12
      final boxes = [
        _box('a', 0.30, 0.30, 0.60),
        _box('b', 0.25, 0.25, 0.50),
        _box('c', 0.20, 0.40, 0.40),
        _box('d', 0.35, 0.20, 0.30),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      for (final p in result.placements) {
        final pd = p.rotated ? p.box.w : p.box.d;
        final ceilStart = trunk.ceilingHeightAt(p.z);
        final ceilEnd = trunk.ceilingHeightAt(p.z + pd);
        final minCeiling = ceilStart < ceilEnd ? ceilStart : ceilEnd;
        expect(p.y + p.box.h, lessThanOrEqualTo(minCeiling + 0.01),
            reason:
                '${p.box.id} top=${p.y + p.box.h} exceeds ceiling=$minCeiling at z=${p.z}');
      }
    });

    test('no placement inside wheelhouse', () {
      final trunk = TrunkSpace.sorento();
      final lw = trunk.leftWheelhouse;
      final rw = trunk.rightWheelhouse;
      final boxes = [
        _box('a', 0.30, 0.30, 0.25),
        _box('b', 0.25, 0.25, 0.20),
        _box('c', 0.20, 0.20, 0.20),
        _box('d', 0.40, 0.30, 0.25),
        _box('e', 0.15, 0.35, 0.15),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      for (final p in result.placements) {
        final pw = p.rotated ? p.box.d : p.box.w;
        final pd = p.rotated ? p.box.w : p.box.d;

        // Left wheelhouse: x=[0, lw.w], z=[trunk.d-lw.d, trunk.d], y=[0, lw.h]
        if (lw.w > 0 && lw.d > 0 && lw.h > 0) {
          final olX = p.x < lw.w && p.x + pw > 0;
          final olZ = p.z < trunk.d && p.z + pd > trunk.d - lw.d;
          final olY = p.y < lw.h && p.y + p.box.h > 0;
          expect(olX && olY && olZ, isFalse,
              reason: '${p.box.id} overlaps left wheelhouse');
        }

        // Right wheelhouse: x=[trunk.w-rw.w, trunk.w], z=[trunk.d-rw.d, trunk.d], y=[0, rw.h]
        if (rw.w > 0 && rw.d > 0 && rw.h > 0) {
          final orX = p.x < trunk.w && p.x + pw > trunk.w - rw.w;
          final orZ = p.z < trunk.d && p.z + pd > trunk.d - rw.d;
          final orY = p.y < rw.h && p.y + p.box.h > 0;
          expect(orX && orY && orZ, isFalse,
              reason: '${p.box.id} overlaps right wheelhouse');
        }
      }
    });

    test('utilization math is correct — sum of volumes / trunk volume', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.25, 0.25, 0.20),
        _box('c', 0.30, 0.20, 0.25),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // Manually calculate expected utilization
      final lhVol = trunk.leftWheelhouse.w *
          trunk.leftWheelhouse.d *
          trunk.leftWheelhouse.h;
      final rhVol = trunk.rightWheelhouse.w *
          trunk.rightWheelhouse.d *
          trunk.rightWheelhouse.h;
      final trunkVol = trunk.w * trunk.d * trunk.h - lhVol - rhVol;

      double boxVol = 0;
      for (final p in result.placements) {
        boxVol += p.box.w * p.box.d * p.box.h;
      }
      final expectedUtil = (boxVol / trunkVol * 100).clamp(0, 100);
      expect(result.utilizationPercent, closeTo(expectedUtil, 0.01));
    });
  });

  group('Vehicle-Specific Tests', () {
    test('Sorento with typical family camping gear', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('tent', 0.60, 0.20, 0.20),       // rolled tent bag
        _box('cooler', 0.40, 0.30, 0.30),      // cooler box
        _box('chair1', 0.12, 0.12, 0.80),      // folded chair (tall)
        _box('chair2', 0.12, 0.12, 0.80),
        _box('chair3', 0.12, 0.12, 0.80),
        _box('chair4', 0.12, 0.12, 0.80),
        _box('table', 0.60, 0.10, 0.10),       // folded table
        _box('sleepbag1', 0.25, 0.25, 0.50),   // sleeping bag
        _box('sleepbag2', 0.25, 0.25, 0.50),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      // At least most items should fit in Sorento's decent trunk
      expect(result.placements.length, greaterThanOrEqualTo(5),
          reason: 'Sorento should fit at least 5 of 9 camping items');
      expect(result.utilizationPercent, greaterThan(0));
    });

    test('Avante (smallest trunk) handles tight space gracefully', () {
      final trunk = TrunkSpace.avante(); // 1.02 x 0.71 x 0.43
      final boxes = [
        _box('suitcase', 0.50, 0.35, 0.25),
        _box('bag1', 0.30, 0.25, 0.20),
        _box('bag2', 0.30, 0.25, 0.20),
        _box('laptop', 0.40, 0.30, 0.05),
        _box('grocery', 0.35, 0.25, 0.25),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      // Should place some boxes without crashing
      expect(result.placements.length, greaterThanOrEqualTo(1));
      // All placed boxes must respect the low ceiling
      for (final p in result.placements) {
        expect(p.y + p.box.h, lessThanOrEqualTo(trunk.h + 0.01),
            reason: '${p.box.id} exceeds Avante trunk height');
      }
    });

    test('Carnival (widest trunk) distributes boxes properly', () {
      final trunk = TrunkSpace.carnival(); // 1.25 x 0.85 x 0.88
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.40, 0.30, 0.30),
        _box('c', 0.40, 0.30, 0.30),
        _box('d', 0.40, 0.30, 0.30),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.allBoxesFit, isTrue);
      expect(result.placements.length, 4);

      // Verify spread: not all boxes at same x
      final xPositions = result.placements.map((p) => p.x).toSet();
      expect(xPositions.length, greaterThan(1),
          reason: 'Boxes should spread across the wide Carnival trunk');
    });
  });

  group('Strategy Comparison', () {
    test('maxUtilization packs at least as much as easyAccess', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.40, 0.30, 0.30),
        _box('b', 0.30, 0.30, 0.25),
        _box('c', 0.25, 0.20, 0.20),
        _box('d', 0.35, 0.25, 0.30),
        _box('e', 0.20, 0.20, 0.15),
        _box('f', 0.30, 0.25, 0.20),
      ];
      final maxUtil = AutoLayoutEngine.computeLayout(
        trunk, boxes,
        strategy: LayoutStrategy.maxUtilization,
      );
      final easyAccess = AutoLayoutEngine.computeLayout(
        trunk, boxes,
        strategy: LayoutStrategy.easyAccess,
      );
      expect(maxUtil.utilizationPercent,
          greaterThanOrEqualTo(easyAccess.utilizationPercent - 0.01),
          reason:
              'maxUtilization (${maxUtil.utilizationPercent}%) should pack >= easyAccess (${easyAccess.utilizationPercent}%)');
    });

    test('easyAccess puts items closer to opening (higher avg z)', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = [
        _box('a', 0.3, 0.3, 0.3),
        _box('b', 0.25, 0.25, 0.25),
        _box('c', 0.2, 0.2, 0.2),
        _box('d', 0.15, 0.15, 0.15),
      ];
      final balanced = AutoLayoutEngine.computeLayout(
        trunk, boxes,
        strategy: LayoutStrategy.balanced,
      );
      final easy = AutoLayoutEngine.computeLayout(
        trunk, boxes,
        strategy: LayoutStrategy.easyAccess,
      );

      if (balanced.placements.isNotEmpty && easy.placements.isNotEmpty) {
        double avgZ(AutoLayoutResult r) =>
            r.placements.map((p) => p.z).reduce((a, b) => a + b) /
            r.placements.length;
        expect(avgZ(easy), greaterThanOrEqualTo(avgZ(balanced) - 0.01),
            reason:
                'easyAccess avgZ=${avgZ(easy)} should be >= balanced avgZ=${avgZ(balanced)}');
      }
    });
  });

  group('Performance — 3초 내 결과', () {
    test('20 boxes on Sorento completes under 3 seconds', () {
      final trunk = TrunkSpace.sorento();
      final boxes = List.generate(20, (i) => _box('box_$i', 0.15 + (i % 5) * 0.05, 0.15 + (i % 3) * 0.05, 0.10 + (i % 4) * 0.05));
      final sw = Stopwatch()..start();
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(3000),
          reason: '20 boxes x 3 strategies took ${sw.elapsedMilliseconds}ms');
      expect(alts.length, 3);
    });

    test('30 boxes on Carnival completes under 3 seconds', () {
      final trunk = TrunkSpace.carnival();
      final boxes = List.generate(30, (i) => _box('box_$i', 0.10 + (i % 4) * 0.05, 0.10 + (i % 3) * 0.05, 0.10 + (i % 5) * 0.03));
      final sw = Stopwatch()..start();
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(3000),
          reason: '30 boxes x 3 strategies took ${sw.elapsedMilliseconds}ms');
      expect(alts.length, 3);
    });
  });

  group('Regression Guards', () {
    test('empty trunk with auto-layout — 0 boxes, no crash', () {
      final trunk = TrunkSpace.sorento();
      final result = AutoLayoutEngine.computeLayout(trunk, []);
      expect(result.placements, isEmpty);
      expect(result.allBoxesFit, isTrue);
      expect(result.unfitBoxes, isEmpty);
      expect(result.utilizationPercent, 0);
      expect(result.strategy, LayoutStrategy.balanced);
    });

    test('single oversized box — too tall for ceiling, in unfitBoxes', () {
      // Trunk with ceiling drop: at z=0, ceiling = 0.8 - 0.3 = 0.5
      // At z=d, ceiling = 0.8 (full height)
      // A box that is 0.85 tall won't fit anywhere since max ceiling = 0.8
      final trunk = const TrunkSpace(
        w: 1.0,
        d: 1.0,
        h: 0.8,
        leftWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        rightWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        ceilingDrop: 0.3,
      );
      final boxes = [_box('tooTall', 0.3, 0.3, 0.85)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements, isEmpty);
      expect(result.allBoxesFit, isFalse);
      expect(result.unfitBoxes.length, 1);
      expect(result.unfitBoxes[0].id, 'tooTall');
    });
  });
}
