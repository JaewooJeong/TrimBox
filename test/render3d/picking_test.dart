import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/picking.dart';
import 'package:trimbox/render3d/vec3.dart';

void main() {
  group('rayAabbHit', () {
    const box = Aabb(0, 0, 0, 1, 1, 1);

    test('정면에서 쏘면 진입 거리를 돌려준다', () {
      final r = Ray(const Vec3(0.5, 0.5, 3), const Vec3(0, 0, -1));
      expect(rayAabbHit(r, box), closeTo(2.0, 1e-9));
    });

    test('빗나가면 null', () {
      final r = Ray(const Vec3(2, 0.5, 3), const Vec3(0, 0, -1));
      expect(rayAabbHit(r, box), isNull);
    });

    test('반대 방향이면 null', () {
      final r = Ray(const Vec3(0.5, 0.5, 3), const Vec3(0, 0, 1));
      expect(rayAabbHit(r, box), isNull);
    });

    test('대각선 반직선', () {
      final dir = const Vec3(-1, -1, -1).normalized;
      final r = Ray(const Vec3(2, 2, 2), dir);
      final t = rayAabbHit(r, box)!;
      final hit = r.at(t);
      expect(hit.x, closeTo(1, 1e-9));
      expect(hit.y, closeTo(1, 1e-9));
      expect(hit.z, closeTo(1, 1e-9));
    });

    test('가까운 상자가 먼저 잡힌다', () {
      const near = Aabb(0, 0, 1.5, 1, 1, 2.5);
      final r = Ray(const Vec3(0.5, 0.5, 5), const Vec3(0, 0, -1));
      expect(rayAabbHit(r, near)!, lessThan(rayAabbHit(r, box)!));
    });
  });

  group('rayPlaneY', () {
    test('평면 교점', () {
      final r = Ray(const Vec3(0, 2, 0), const Vec3(0, -1, 1).normalized);
      final p = rayPlaneY(r, 0)!;
      expect(p.y, closeTo(0, 1e-9));
      expect(p.z, closeTo(2, 1e-9));
    });

    test('평행하면 null', () {
      final r = Ray(const Vec3(0, 2, 0), const Vec3(1, 0, 0));
      expect(rayPlaneY(r, 0), isNull);
    });

    test('뒤쪽 교점은 null', () {
      final r = Ray(const Vec3(0, 2, 0), const Vec3(0, 1, 0));
      expect(rayPlaneY(r, 0), isNull);
    });
  });
}
