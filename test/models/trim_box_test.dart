import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';

void main() {
  group('TrimBox', () {
    TrimBox makeBox({
      double w = 0.4,
      double d = 0.3,
      double h = 0.3,
      double x = 0,
      double z = 0,
      int rotY = 0,
    }) =>
        TrimBox(
          id: 'test-box',
          label: 'Test',
          w: w,
          d: d,
          h: h,
          x: x,
          z: z,
          rotY: rotY,
          color: const Color(0xFFFF0000),
        );

    test('생성 및 기본값 검증', () {
      final box = makeBox();
      expect(box.id, 'test-box');
      expect(box.label, 'Test');
      expect(box.w, 0.4);
      expect(box.d, 0.3);
      expect(box.h, 0.3);
      expect(box.x, 0);
      expect(box.y, 0);
      expect(box.z, 0);
      expect(box.rotY, 0);
    });

    test('90도 회전 시 effectiveW/D 스왑', () {
      final box = makeBox(w: 0.4, d: 0.3);
      expect(box.effectiveW, 0.4);
      expect(box.effectiveD, 0.3);

      box.rotate90();
      expect(box.rotY, 90);
      expect(box.effectiveW, 0.3);
      expect(box.effectiveD, 0.4);
    });

    test('360도 회전 시 원래 방향 복귀', () {
      final box = makeBox(w: 0.4, d: 0.3);
      box.rotate90();
      box.rotate90();
      box.rotate90();
      box.rotate90();
      expect(box.rotY, 0);
      expect(box.effectiveW, 0.4);
      expect(box.effectiveD, 0.3);
    });

    test('snapToGrid 10cm 단위', () {
      final box = makeBox(x: 0.13, z: 0.27);
      box.x = 0.13;
      box.z = 0.27;
      box.snapToGrid(0.10);
      expect(box.x, closeTo(0.1, 0.001));
      expect(box.z, closeTo(0.3, 0.001));
    });

    test('clampTo 경계 내 유지', () {
      final box = makeBox(w: 0.4, d: 0.3, x: 1.0, z: 0.9);
      box.clampTo(1.08, 1.07);
      expect(box.x, closeTo(0.68, 0.001)); // 1.08 - 0.4 = 0.68
      expect(box.z, closeTo(0.77, 0.001)); // 1.07 - 0.3 = 0.77
    });

    test('clampTo 회전 상태 반영', () {
      final box = makeBox(w: 0.4, d: 0.3, x: 1.0, z: 0.9);
      box.rotate90(); // effectiveW=0.3, effectiveD=0.4
      box.clampTo(1.08, 1.07);
      expect(box.x, closeTo(0.78, 0.001)); // 1.08 - 0.3 = 0.78
      expect(box.z, closeTo(0.67, 0.001)); // 1.07 - 0.4 = 0.67
    });

    test('clampTo 음수 위치 보정', () {
      final box = makeBox(w: 0.4, d: 0.3, x: -0.5, z: -0.2);
      box.clampTo(1.08, 1.07);
      expect(box.x, 0);
      expect(box.z, 0);
    });

    test('toJson/fromJson 라운드트립', () {
      final box = makeBox(x: 0.2, z: 0.3);
      box.rotY = 90;
      final json = box.toJson();
      final restored = TrimBox.fromJson(json);

      expect(restored.id, box.id);
      expect(restored.label, box.label);
      expect(restored.w, box.w);
      expect(restored.d, box.d);
      expect(restored.h, box.h);
      expect(restored.x, box.x);
      expect(restored.z, box.z);
      expect(restored.rotY, 90);
    });

    test('copyWith 동작', () {
      final box = makeBox();
      final copy = box.copyWith(label: 'Copy', x: 0.5);
      expect(copy.label, 'Copy');
      expect(copy.x, 0.5);
      expect(copy.w, box.w);
      expect(copy.id, box.id);
    });
  });
}
