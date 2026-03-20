import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/painters/isometric_painter.dart';

void main() {
  IsometricPainter makePainter({
    double scale = 100.0,
  }) =>
      IsometricPainter(
        space: TrunkSpace.tucson(),
        boxes: [],
        scale: scale,
      );

  group('toScreen 1-point perspective 투영', () {
    test('vanishing point: (camX, camY, 0) → Offset(0, 0)', () {
      // At z=0, camZ - z = camZ = d + focalLen = 2*d
      // f = focalLen / (2*d) * scale = d / (2*d) * scale = 0.5 * scale
      // sx = (camX - camX) * f = 0, sy = -(camY - camY) * f = 0
      final p = makePainter();
      final o = p.toScreen(p.camX, p.camY, 0);
      expect(o.dx, closeTo(0, 0.001));
      expect(o.dy, closeTo(0, 0.001));
    });

    test('opening center: (camX, camY, d) → Offset(0, 0)', () {
      // At z=d, camZ - z = focalLen, f = focalLen/focalLen * scale = scale
      // sx = (camX - camX) * scale = 0
      final p = makePainter();
      final o = p.toScreen(p.camX, p.camY, p.space.d);
      expect(o.dx, closeTo(0, 0.001));
      expect(o.dy, closeTo(0, 0.001));
    });

    test('opening edge: objects at z=d have f=scale', () {
      final p = makePainter();
      final d = p.space.d;
      // At opening: f = focalLen / (camZ - d) * scale = focalLen / focalLen * scale = scale
      final o = p.toScreen(p.camX + 1.0, p.camY, d);
      // sx = 1.0 * scale = 100
      expect(o.dx, closeTo(100.0, 0.01));
      expect(o.dy, closeTo(0, 0.001));
    });

    test('back wall: objects at z=0 appear smaller (f < scale)', () {
      final p = makePainter();
      // At z=0: f = focalLen / camZ * scale = focalLen / (d + focalLen) * scale
      final oFront = p.toScreen(p.camX + 1.0, p.camY, p.space.d);
      final oBack = p.toScreen(p.camX + 1.0, p.camY, 0);
      // Front should be larger (farther from vanishing pt in screen)
      expect(oFront.dx.abs(), greaterThan(oBack.dx.abs()));
      // Ratio = (d + focalLen) / focalLen (front_f/back_f)
      final expectedRatio = (p.space.d + p.focalLen) / p.focalLen;
      expect(oFront.dx / oBack.dx, closeTo(expectedRatio, 0.01));
    });

    test('y축: 위로 갈수록 sy 음수', () {
      final p = makePainter();
      // Point above camY at opening
      final o = p.toScreen(p.camX, p.camY + 0.5, p.space.d);
      // sy = -(0.5) * scale = -50
      expect(o.dy, closeTo(-50.0, 0.01));
    });

    test('y축: 아래로 갈수록 sy 양수', () {
      final p = makePainter();
      final o = p.toScreen(p.camX, p.camY - 0.3, p.space.d);
      // sy = -(-0.3) * scale = 30
      expect(o.dy, closeTo(30.0, 0.01));
    });

    test('스케일 변경 시 비례 확인', () {
      final p1 = makePainter(scale: 100);
      final p2 = makePainter(scale: 200);
      final o1 = p1.toScreen(1, 0.2, 0.5);
      final o2 = p2.toScreen(1, 0.2, 0.5);
      expect(o2.dx, closeTo(o1.dx * 2, 0.01));
      expect(o2.dy, closeTo(o1.dy * 2, 0.01));
    });
  });

  group('isFaceVisible 면 가시성', () {
    test('fixed perspective: all faces visible', () {
      final p = makePainter();
      // In 1-point perspective from fixed camera, all interior faces are visible
      expect(p.isFaceVisible(-1, 0), true);
      expect(p.isFaceVisible(1, 0), true);
      expect(p.isFaceVisible(0, 1), true);
      expect(p.isFaceVisible(0, -1), true);
    });
  });

  group('computeCenter 중심점', () {
    final size = const Size(800, 600);

    test('returns canvas center', () {
      final center = IsometricPainter.computeCenter(
          size, TrunkSpace.tucson(), 280.0, 0.0);
      expect(center.dx, closeTo(400.0, 0.001));
      expect(center.dy, closeTo(300.0, 0.001));
    });

    test('cameraYaw has no effect (perspective ignores yaw)', () {
      final c0 = IsometricPainter.computeCenter(
          size, TrunkSpace.tucson(), 280.0, 0.0);
      final c45 = IsometricPainter.computeCenter(
          size, TrunkSpace.tucson(), 280.0, 0.785);
      expect(c0.dx, closeTo(c45.dx, 0.001));
      expect(c0.dy, closeTo(c45.dy, 0.001));
    });

    test('스케일 변경 시에도 중심 동일', () {
      final c1 = IsometricPainter.computeCenter(
          size, TrunkSpace.tucson(), 150.0, 0.0);
      final c2 = IsometricPainter.computeCenter(
          size, TrunkSpace.tucson(), 280.0, 0.0);
      expect(c1.dx, closeTo(c2.dx, 0.001));
      expect(c1.dy, closeTo(c2.dy, 0.001));
    });
  });

  group('toIso alias', () {
    test('toIso returns same result as toScreen', () {
      final p = makePainter();
      final a = p.toScreen(0.5, 0.3, 0.7);
      final b = p.toIso(0.5, 0.3, 0.7);
      expect(a.dx, closeTo(b.dx, 0.001));
      expect(a.dy, closeTo(b.dy, 0.001));
    });
  });
}
