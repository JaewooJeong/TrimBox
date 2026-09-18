import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/gear_shapes.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/picking.dart';
import 'package:trimbox/render3d/vec3.dart';

import 'scene_fixtures.dart';

double _area(List<Offset> pts) {
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s.abs() / 2;
}

/// 라벨이 놓이는 자리와 같은 점: 가장 크게 보이는 AABB 면의 투영 중심
Offset? _largestFaceCentre(TrimBox b, OrbitCamera cam, Size size) {
  Offset? best;
  var bestArea = 0.0;
  for (final f in aabbFaces(Aabb.fromBox(b))) {
    if (!f.facesCamera(cam.position)) continue;
    final c = cam.project(f.centroid, size);
    final pts = [for (final p in f.pts) cam.project(p, size)?.screen];
    if (c == null || pts.any((p) => p == null)) continue;
    final area = _area(pts.cast<Offset>());
    if (area > bestArea) {
      bestArea = area;
      best = c.screen;
    }
  }
  return best;
}

TrimBox _box(String id, GearShape shape, Aabb a) => TrimBox(
      id: id,
      label: id,
      w: a.w,
      d: a.d,
      h: a.h,
      x: a.x1,
      y: a.y1,
      z: a.z1,
      color: const Color(0xFF556B2F),
      shape: shape,
    );

void main() {
  const size = Size(960, 640);

  group('rayConvexMeshHit', () {
    final a = const Aabb(0, 0, 0, 1, 0.4, 0.4);
    final cyl = gearMeshFor(GearShape.cylinder, a); // x 축으로 누운 원통

    test('가운데를 지나면 맞고, 진입 거리는 AABB 진입 이후', () {
      final r = Ray(const Vec3(0.5, 0.2, 3), const Vec3(0, 0, -1));
      final t = rayConvexMeshHit(r, cyl)!;
      expect(t, closeTo(2.6, 1e-6));
      expect(t, greaterThanOrEqualTo(rayAabbHit(r, a)! - 1e-9));
    });

    test('AABB 의 빈 귀퉁이를 지나면 AABB 는 맞지만 원통은 빗나간다', () {
      // 원통 축(x)과 나란히 단면의 귀퉁이 (y, z) = (0.38, 0.38) 를 지난다
      final corner = Ray(const Vec3(-1, 0.38, 0.38), const Vec3(1, 0, 0));
      expect(rayAabbHit(corner, a), closeTo(1.0, 1e-9));
      expect(rayConvexMeshHit(corner, cyl), isNull);
      // 같은 방향으로 단면 가운데를 지나면 끝면에 맞는다
      final centre = Ray(const Vec3(-1, 0.2, 0.2), const Vec3(1, 0, 0));
      expect(rayConvexMeshHit(centre, cyl), closeTo(1.0, 1e-9));
    });

    test('안에서 쏘면 0', () {
      final r = Ray(const Vec3(0.5, 0.2, 0.2), const Vec3(1, 0, 0));
      expect(rayConvexMeshHit(r, cyl), 0);
    });

    test('모든 모양: 메시에 맞으면 AABB 에도 맞는다 (메시 ⊂ AABB)', () {
      final rnd = math.Random(4);
      for (final shape in GearShape.values) {
        final mesh = gearMeshFor(shape, a);
        var meshHits = 0;
        for (var i = 0; i < 300; i++) {
          final o = Vec3(rnd.nextDouble() * 3 - 1, rnd.nextDouble() * 2,
              rnd.nextDouble() * 3 - 1);
          final target = Vec3(rnd.nextDouble() * 1.4 - 0.2,
              rnd.nextDouble() * 0.6 - 0.1, rnd.nextDouble() * 0.6 - 0.1);
          final r = Ray(o, (target - o).normalized);
          final tm = rayConvexMeshHit(r, mesh);
          if (tm == null) continue;
          meshHits++;
          final ta = rayAabbHit(r, a);
          expect(ta, isNotNull, reason: shape.name);
          expect(tm, greaterThanOrEqualTo(ta! - 1e-9));
        }
        expect(meshHits, greaterThan(50));
      }
    });
  });

  group('pickBox', () {
    test('빈 곳은 null, 하나만 걸리면 그 박스 (빈 귀퉁이여도 — 터치에 넉넉하게)', () {
      final cyl = _box('cyl', GearShape.cylinder, const Aabb(0, 0, 0, 1, 0.4, 0.4));
      expect(pickBox(Ray(const Vec3(5, 5, 5), const Vec3(0, 1, 0)), [cyl]),
          isNull);
      final corner = Ray(const Vec3(-1, 0.38, 0.38), const Vec3(1, 0, 0));
      expect(rayConvexMeshHit(corner, gearMesh(cyl)), isNull);
      expect(pickBox(corner, [cyl])?.id, 'cyl');
    });

    test('원통 AABB 의 빈 귀퉁이 너머로 보이는 쿨러를 누르면 쿨러가 잡힌다', () {
      // 쿨러(뒤) 앞에 누운 원통. 위에서 비스듬히 원통의 위쪽 앞 귀퉁이를 지나 쿨러를 본다.
      final cooler =
          _box('cooler', GearShape.cooler, const Aabb(0.2, 0, 0.0, 0.8, 0.42, 0.40));
      final cyl =
          _box('cyl', GearShape.cylinder, const Aabb(0.1, 0, 0.45, 0.9, 0.30, 0.75));
      // 원통 AABB 의 위·뒤 귀퉁이 (y 0.28, z 0.47: 타원 밖) 를 스쳐 쿨러 앞면으로
      final from = const Vec3(0.5, 0.90, 1.60);
      final to = const Vec3(0.5, 0.28, 0.47);
      final ray = Ray(from, (to - from).normalized);
      // 전제: 두 AABB 모두 걸리고 원통 AABB 가 더 가깝지만, 원통 모양에는 닿지 않는다
      final tCyl = rayAabbHit(ray, Aabb.fromBox(cyl));
      final tCooler = rayAabbHit(ray, Aabb.fromBox(cooler));
      expect(tCyl, isNotNull);
      expect(tCooler, isNotNull);
      expect(tCyl!, lessThan(tCooler!));
      expect(rayConvexMeshHit(ray, gearMesh(cyl)), isNull);

      expect(pickBox(ray, [cyl, cooler])?.id, 'cooler');
      expect(pickBox(ray, [cooler, cyl])?.id, 'cooler');
      // 원통 몸통을 누르면 원통
      final body = Ray(from, (const Vec3(0.5, 0.15, 0.60) - from).normalized);
      expect(rayConvexMeshHit(body, gearMesh(cyl)), isNotNull);
      expect(pickBox(body, [cyl, cooler])?.id, 'cyl');
    });

    test('둘 다 모양은 빗나가면 가까운 AABB', () {
      final a = _box('a', GearShape.cylinder, const Aabb(0, 0, 0.5, 1, 0.4, 0.9));
      final b = _box('b', GearShape.cylinder, const Aabb(0, 0, 0.0, 1, 0.4, 0.4));
      // 두 원통의 위쪽 귀퉁이만 스치는 수평에 가까운 반직선
      final ray = Ray(const Vec3(0.5, 0.398, 3), const Vec3(0, 0, -1));
      // y = 0.398 은 타원 꼭대기(0.4) 바로 아래라 원통에 닿는다 → a 가 앞
      expect(pickBox(ray, [a, b])?.id, 'a');
    });

    for (final entry in {
      'sorento 가족 세트': () => (TrunkSpace.sorento(), familyBundle),
      'sorento 슬라이드 미니멀': () =>
          (TrunkSpace.sorento(seatSlide: 0.27), '2인 미니멀 캠핑'),
      'tucson 미니멀': () => (TrunkSpace.tucson(), '2인 미니멀 캠핑'),
    }.entries) {
      test('${entry.key}: 가장 크게 보이는 면의 중심을 누르면 그 박스(또는 그 앞의 박스)', () {
        final (space, bundle) = entry.value();
        final boxes = packedBundle(space, bundle);
        expect(boxes.length, greaterThan(4));
        var exact = 0, total = 0;
        for (final yaw in [-1.2, -0.6, 0.0, 0.35, 0.6, 1.2]) {
          for (final pitch in [0.1, 0.38, 1.0]) {
            final cam = OrbitCamera.fitTrunk(space, size, yaw: yaw, pitch: pitch);
            for (final b in boxes) {
              final centre = _largestFaceCentre(b, cam, size);
              if (centre == null) continue;
              final ray = cam.ray(centre, size);
              final tTarget = rayAabbHit(ray, Aabb.fromBox(b));
              expect(tTarget, isNotNull, reason: '${b.label} 자기 면 중심');
              final picked = pickBox(ray, boxes);
              expect(picked, isNotNull);
              total++;
              if (picked!.id == b.id) {
                exact++;
                continue;
              }
              // 다른 박스라면 반드시 더 앞에 있어야 한다 (가려서 안 보이는 경우)
              final tPicked = rayAabbHit(ray, Aabb.fromBox(picked))!;
              expect(tPicked, lessThanOrEqualTo(tTarget! + 1e-9),
                  reason: '${b.label} 을 눌렀는데 뒤에 있는 ${picked.label} 이 잡힘 '
                      '(yaw $yaw pitch $pitch)');
            }
          }
        }
        // 가려지지 않은 박스는 자기 자신이 잡힌다 (꽉 찬 트렁크는 가려진 박스가 더 많다)
        expect(total, greaterThan(50));
        expect(exact / total, greaterThan(0.3), reason: '$exact / $total');
      });
    }
  });
}
