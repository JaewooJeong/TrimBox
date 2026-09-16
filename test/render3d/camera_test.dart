import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/vec3.dart';

void main() {
  const size = Size(800, 600);
  final space = TrunkSpace.sorento();

  group('OrbitCamera 위치', () {
    test('yaw=0 이면 카메라는 +z(테일게이트 뒤)에 있다', () {
      final cam = OrbitCamera.fitTrunk(space, size);
      expect(cam.position.z, greaterThan(space.d));
      expect((cam.position.x - space.w / 2).abs(), lessThan(1e-9));
      expect(cam.position.y, greaterThan(cam.target.y));
    });

    test('yaw > 0 이면 카메라가 +x 쪽으로 돈다', () {
      final cam = OrbitCamera.fitTrunk(space, size, yaw: 0.5);
      expect(cam.position.x, greaterThan(space.w / 2));
    });

    test('forward 는 타깃을 향한다', () {
      final cam = OrbitCamera.fitTrunk(space, size, yaw: 0.3, pitch: 0.4);
      final toTarget = (cam.target - cam.position).normalized;
      expect((toTarget - cam.forward).length, lessThan(1e-9));
    });

    test('right/up/forward 는 정규 직교 기저', () {
      final cam = OrbitCamera.fitTrunk(space, size, yaw: -0.7, pitch: 0.6);
      expect(cam.right.dot(cam.forward).abs(), lessThan(1e-9));
      expect(cam.up.dot(cam.forward).abs(), lessThan(1e-9));
      expect(cam.right.dot(cam.up).abs(), lessThan(1e-9));
      expect((cam.up.length - 1).abs(), lessThan(1e-9));
    });
  });

  group('fitTrunk', () {
    test('트렁크 8개 꼭짓점이 모두 화면 여백 안에 들어온다', () {
      final cam = OrbitCamera.fitTrunk(space, size);
      for (final x in [0.0, space.w]) {
        for (final y in [0.0, space.h]) {
          for (final z in [0.0, space.d]) {
            final p = cam.project(Vec3(x, y, z), size);
            expect(p, isNotNull);
            expect(p!.screen.dx, inInclusiveRange(0, size.width));
            expect(p.screen.dy, inInclusiveRange(0, size.height));
          }
        }
      }
    });

    test('세로로 긴 캔버스(모바일)에서도 들어온다', () {
      const mobile = Size(390, 700);
      final cam = OrbitCamera.fitTrunk(space, mobile);
      for (final c in [
        Vec3(0, 0, space.d),
        Vec3(space.w, space.h, 0),
        Vec3(space.w, 0, space.d),
      ]) {
        final p = cam.project(c, mobile)!;
        expect(p.screen.dx, inInclusiveRange(0, mobile.width));
        expect(p.screen.dy, inInclusiveRange(0, mobile.height));
      }
    });

    test('가까운 점이 먼 점보다 화면에서 더 크게 투영된다 (원근)', () {
      final cam = OrbitCamera.fitTrunk(space, size);
      final near1 = cam.project(Vec3(0, 0, space.d), size)!.screen;
      final near2 = cam.project(Vec3(space.w, 0, space.d), size)!.screen;
      final far1 = cam.project(Vec3(0, 0, 0), size)!.screen;
      final far2 = cam.project(Vec3(space.w, 0, 0), size)!.screen;
      expect((near2 - near1).distance, greaterThan((far2 - far1).distance));
    });
  });

  group('project ↔ ray 일관성', () {
    test('투영한 픽셀로 쏜 반직선은 원래 점을 지난다', () {
      final cam = OrbitCamera.fitTrunk(space, size, yaw: 0.4, pitch: 0.5);
      final pts = [
        Vec3(0.2, 0.0, 0.3),
        Vec3(1.0, 0.5, 1.0),
        Vec3(0.5, 0.78, 0.0),
      ];
      for (final p in pts) {
        final proj = cam.project(p, size)!;
        final ray = cam.ray(proj.screen, size);
        // 점과 반직선 사이 거리
        final v = p - ray.origin;
        final t = v.dot(ray.dir);
        final closest = ray.at(t);
        expect((closest - p).length, lessThan(1e-6));
        expect(t, greaterThan(0));
      }
    });

    test('카메라 뒤의 점은 투영되지 않는다', () {
      final cam = OrbitCamera.fitTrunk(space, size);
      final behind = cam.position + (cam.position - cam.target);
      expect(cam.project(behind, size), isNull);
    });
  });

  group('clamped', () {
    test('각도와 거리를 제한한다', () {
      final cam = OrbitCamera(
        target: Vec3.zero,
        yaw: math.pi,
        pitch: -1.0,
        distance: 100,
      ).clamped(minDistance: 1, maxDistance: 5);
      expect(cam.yaw, OrbitCamera.maxYawAbs);
      expect(cam.pitch, OrbitCamera.minPitch);
      expect(cam.distance, 5);
    });
  });
}
