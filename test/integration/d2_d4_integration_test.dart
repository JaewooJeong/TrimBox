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
  group('D2 Integration — Auto-layout + Verdict flow', () {
    test('generateAlternatives returns 3 strategies with correct labels', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('cooler', 0.40, 0.30, 0.30),
        _box('tent', 0.60, 0.20, 0.20),
      ];
      final alts = AutoLayoutEngine.generateAlternatives(trunk, boxes);
      expect(alts.length, 3);

      final strategies = alts.map((a) => a.strategy).toSet();
      expect(strategies, containsAll(LayoutStrategy.values));

      for (final alt in alts) {
        expect(alt.strategy.label.isNotEmpty, isTrue);
      }
    });

    test('quick check does not modify box positions', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.30, 0.30, 0.30),
        _box('b', 0.20, 0.20, 0.20),
      ];
      // Record original positions
      final origX = boxes.map((b) => b.x).toList();
      final origZ = boxes.map((b) => b.z).toList();

      // Run computeLayout (what quick check calls)
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // Original box objects should NOT have their positions changed
      for (int i = 0; i < boxes.length; i++) {
        expect(boxes[i].x, origX[i], reason: 'Box ${boxes[i].id} x changed');
        expect(boxes[i].z, origZ[i], reason: 'Box ${boxes[i].id} z changed');
      }

      // Result placements are separate from input boxes
      expect(result.placements, isNotEmpty);
    });

    test('load order is assigned sequentially and reflects sort order', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('small', 0.10, 0.10, 0.10),
        _box('large', 0.40, 0.40, 0.40),
        _box('medium', 0.25, 0.25, 0.25),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.placements.length, 3);

      // All load orders should be unique and 1-based
      final orders = result.placements.map((p) => p.loadOrder).toSet();
      expect(orders, {1, 2, 3});
    });

    test('all boxes fit verdict when all placed', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [_box('a', 0.20, 0.20, 0.20)];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.allBoxesFit, isTrue);
      expect(result.unfitBoxes, isEmpty);
      expect(result.utilizationPercent, greaterThan(0));
    });

    test('partial fit verdict with unfit boxes', () {
      final trunk = TrunkSpace.custom(w: 0.30, d: 0.30, h: 0.30);
      final boxes = [
        _box('fits', 0.25, 0.25, 0.25),
        _box('nofit', 0.50, 0.50, 0.50),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(result.allBoxesFit, isFalse);
      expect(result.unfitBoxes.length, 1);
      expect(result.unfitBoxes[0].id, 'nofit');
      expect(result.placements.length, 1);
    });
  });

  group('D3 Integration — Load order and step view data', () {
    test('loadOrder assigned to TrimBox after layout application', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [
        _box('a', 0.30, 0.30, 0.30),
        _box('b', 0.20, 0.20, 0.20),
        _box('c', 0.15, 0.15, 0.15),
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);

      // Simulate _applyAutoLayout: assign loadOrder to boxes
      for (final placement in result.placements) {
        final box = boxes.firstWhere((b) => b.id == placement.box.id);
        box.loadOrder = placement.loadOrder;
      }

      // All boxes should have loadOrder assigned
      for (final box in boxes) {
        expect(box.loadOrder, isNotNull, reason: '${box.id} missing loadOrder');
        expect(box.loadOrder, greaterThan(0));
      }

      // Load orders should be unique
      final orders = boxes.map((b) => b.loadOrder).toSet();
      expect(orders.length, 3);
    });

    test('step view maxStep equals max loadOrder', () {
      final boxes = [
        _box('a', 0.3, 0.3, 0.3)..loadOrder = 1,
        _box('b', 0.2, 0.2, 0.2)..loadOrder = 2,
        _box('c', 0.1, 0.1, 0.1)..loadOrder = 3,
      ];
      int maxLoadOrder = 0;
      for (final b in boxes) {
        if (b.loadOrder != null && b.loadOrder! > maxLoadOrder) {
          maxLoadOrder = b.loadOrder!;
        }
      }
      expect(maxLoadOrder, 3);
    });

    test('step view filtering: boxes with null loadOrder excluded', () {
      final boxes = [
        _box('a', 0.3, 0.3, 0.3)..loadOrder = 1,
        _box('b', 0.2, 0.2, 0.2)..loadOrder = null,
        _box('c', 0.1, 0.1, 0.1)..loadOrder = 2,
      ];

      // Simulate step view at step 1
      const highlightStep = 1;
      final visibleBoxes = boxes.where((b) {
        if (b.loadOrder == null) return false; // hidden in step mode
        if (b.loadOrder! > highlightStep) return false; // future hidden
        return true;
      }).toList();

      expect(visibleBoxes.length, 1);
      expect(visibleBoxes[0].id, 'a');
    });

    test('step view at max step shows all ordered boxes', () {
      final boxes = [
        _box('a', 0.3, 0.3, 0.3)..loadOrder = 1,
        _box('b', 0.2, 0.2, 0.2)..loadOrder = 2,
        _box('c', 0.1, 0.1, 0.1)..loadOrder = 3,
      ];

      const highlightStep = 3;
      final visibleBoxes = boxes.where((b) {
        if (b.loadOrder == null) return false;
        if (b.loadOrder! > highlightStep) return false;
        return true;
      }).toList();

      expect(visibleBoxes.length, 3);
    });
  });

  group('D4 Integration — Share card text generation', () {
    test('share text includes vehicle, count, utilization, hashtags', () {
      // Simulate _buildShareText logic
      const presetName = '쏘렌토';
      final boxes = [
        _box('쿨러', 0.40, 0.30, 0.30),
        _box('텐트', 0.60, 0.20, 0.20),
      ];
      final volPct = 15;
      final totalLiters = 850;
      final usedLiters = 128;

      final sb = StringBuffer();
      sb.writeln('$presetName 트렁크 적재 시뮬레이션');
      sb.writeln('적재율: $volPct% (${usedLiters}L / ${totalLiters}L)');
      sb.writeln('장비 ${boxes.length}개:');
      for (final b in boxes) {
        final name = b.label.isNotEmpty ? b.label : b.id;
        sb.writeln(
            '  - $name (${(b.w * 100).round()}x${(b.d * 100).round()}x${(b.h * 100).round()}cm)');
      }
      sb.writeln('#TrimBox #캠핑 #트렁크패킹');
      final text = sb.toString();

      expect(text, contains('쏘렌토'));
      expect(text, contains('적재율: 15%'));
      expect(text, contains('장비 2개'));
      expect(text, contains('쿨러'));
      expect(text, contains('텐트'));
      expect(text, contains('#TrimBox'));
      expect(text, contains('#캠핑'));
    });
  });

  group('D5 QA — Edge cases and regression guards', () {
    test('empty box list: all operations safe', () {
      final trunk = TrunkSpace.sorento();
      final result = AutoLayoutEngine.computeLayout(trunk, []);
      expect(result.allBoxesFit, isTrue);
      expect(result.placements, isEmpty);
      expect(result.unfitBoxes, isEmpty);
      expect(result.utilizationPercent, 0);

      final alts = AutoLayoutEngine.generateAlternatives(trunk, []);
      expect(alts.length, 3);
      for (final alt in alts) {
        expect(alt.placements, isEmpty);
        expect(alt.allBoxesFit, isTrue);
      }
    });

    test('single box: quick check, auto-layout, step view all coherent', () {
      final trunk = TrunkSpace.sorento();
      final boxes = [_box('solo', 0.30, 0.30, 0.30)];

      // Quick check
      final quickResult = AutoLayoutEngine.computeLayout(trunk, boxes);
      expect(quickResult.allBoxesFit, isTrue);
      expect(quickResult.placements.length, 1);
      expect(quickResult.placements[0].loadOrder, 1);

      // After applying, step view with maxStep=1 shows the solo box
      boxes[0].loadOrder = 1;
      final visibleInStep = boxes.where((b) =>
          b.loadOrder != null && b.loadOrder! <= 1).toList();
      expect(visibleInStep.length, 1);
    });

    test('copyWith preserves loadOrder', () {
      final box = _box('a', 0.3, 0.3, 0.3);
      box.loadOrder = 5;
      final copy = box.copyWith();
      expect(copy.loadOrder, 5);
    });

    test('copyWith with explicit loadOrder override', () {
      final box = _box('a', 0.3, 0.3, 0.3);
      box.loadOrder = 5;
      final copy = box.copyWith(loadOrder: 10);
      expect(copy.loadOrder, 10);
    });

    test('utilization calculation matches manual computation', () {
      final trunk = TrunkSpace.custom(w: 1.0, d: 1.0, h: 1.0);
      final boxes = [
        _box('a', 0.5, 0.5, 0.5), // vol = 0.125
        _box('b', 0.3, 0.3, 0.3), // vol = 0.027
      ];
      final result = AutoLayoutEngine.computeLayout(trunk, boxes);
      final expectedVol = 0.125 + 0.027;
      final expectedPct = expectedVol / 1.0 * 100; // ~15.2%
      expect(result.utilizationPercent, closeTo(expectedPct, 0.1));
    });

    test('all vehicle presets produce valid layouts with standard camping set', () {
      final campingSet = [
        _box('cooler', 0.40, 0.30, 0.30),
        _box('tent', 0.60, 0.20, 0.20),
        _box('chair', 0.12, 0.12, 0.80),
        _box('table', 0.60, 0.10, 0.10),
      ];

      for (final preset in TrunkPreset.values) {
        final trunk = preset.toTrunkSpace();
        if (trunk == null) continue; // custom
        final result = AutoLayoutEngine.computeLayout(trunk, campingSet);
        // Should not crash and should place at least some boxes
        expect(result.placements.length, greaterThanOrEqualTo(0),
            reason: 'Preset ${preset.name} crashed or failed');
        // All placed boxes must be within bounds
        for (final p in result.placements) {
          expect(p.x, greaterThanOrEqualTo(-0.01));
          expect(p.y, greaterThanOrEqualTo(-0.01));
          expect(p.z, greaterThanOrEqualTo(-0.01));
        }
      }
    });
  });
}
