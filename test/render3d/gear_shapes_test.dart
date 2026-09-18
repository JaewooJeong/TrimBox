import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/render3d/gear_shapes.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/mesh.dart';
import 'package:trimbox/render3d/vec3.dart';

import 'mesh_checks.dart';

TrimBox _box(GearShape shape, math.Random rnd, int variant) {
  double dim() => 0.03 + rnd.nextDouble() * 1.2;
  final b = TrimBox(
    id: 'b',
    label: 'b',
    w: dim(),
    d: dim(),
    h: dim(),
    x: rnd.nextDouble() * 1.3 - 0.2,
    y: rnd.nextDouble() * 0.6,
    z: rnd.nextDouble() * 1.3 - 0.2,
    rotY: const [0, 90, 180, 270][rnd.nextInt(4)],
    color: const Color(0xFF556B2F),
    shape: shape,
    soft: true,
    compressibility: 0.45,
  );
  switch (variant) {
    case 1:
      b.squash = 0.30;
    case 2:
      b.squashW = 0.20;
    case 3:
      b.squashD = 0.45;
    default:
      break;
  }
  return b;
}

void main() {
  group('모든 모양 × 임의 치수 × 압축/회전', () {
    for (final shape in GearShape.values) {
      test('${shape.name}: AABB 안, 법선 바깥, 평면, NaN 없음', () {
        final rnd = math.Random(shape.index + 7);
        for (var i = 0; i < 60; i++) {
          final b = _box(shape, rnd, i % 4);
          final a = Aabb.fromBox(b);
          final mesh = gearMesh(b);
          final why = '${shape.name} #$i $a rot=${b.rotY}';

          expect(mesh.faces, isNotEmpty, reason: why);
          expect(mesh.faces.length, lessThanOrEqualTo(70), reason: why);
          expectNoNaN(mesh, why);
          expectInsideAabb(mesh, a, 1e-6, why);
          expectNormalsOutward(mesh, a.center, why);
          expectPlanarFaces(mesh, 1e-6, why);
          expectConvex(mesh, 1e-6, why);
          expectManifold(mesh, why);
        }
      });
    }

    test('gearFaces 는 메시와 같은 면을 Face 로 돌려준다', () {
      final b = _box(GearShape.cooler, math.Random(1), 0);
      final faces = gearFaces(b);
      final mesh = gearMesh(b);
      expect(faces.length, mesh.faces.length);
      final a = Aabb.fromBox(b);
      for (final f in faces) {
        expect(f.normal.dot(f.centroid - a.center), greaterThan(0));
      }
    });
  });

  group('원통 축', () {
    Aabb dims(double w, double h, double d) => Aabb(0, 0, 0, w, h, d);

    test('길쭉한 텐트 가방은 긴 축을 따라 눕는다', () {
      expect(cylinderAxis(dims(0.80, 0.35, 0.35)), 0);
      expect(cylinderAxis(dims(0.20, 0.15, 0.85)), 2);
      expect(cylinderAxis(dims(0.22, 1.02, 0.28)), 1); // 세워 실은 경우
    });

    test('코펠·워터저그는 세운 원통', () {
      expect(cylinderAxis(dims(0.20, 0.15, 0.20)), 1);
      expect(cylinderAxis(dims(0.18, 0.28, 0.18)), 1);
    });

    test('눕힌 원통은 바닥과 윗면에 닿는다 (공중에 뜨거나 묻히지 않음)', () {
      final a = Aabb(0.1, 0.0, 0.2, 0.9, 0.3, 0.55);
      final mesh = gearMeshFor(GearShape.cylinder, a);
      final ys = mesh.verts.map((v) => v.y);
      expect(ys.reduce(math.min), closeTo(a.y1, 1e-9));
      expect(ys.reduce(math.max), closeTo(a.y2, 1e-9));
      final zs = mesh.verts.map((v) => v.z);
      expect(zs.reduce(math.min), closeTo(a.z1, 1e-9));
      expect(zs.reduce(math.max), closeTo(a.z2, 1e-9));
    });
  });

  test('눌린 침낭은 유효 치수로 납작하게 그려진다', () {
    final b = TrimBox(
      id: 's',
      label: '침낭',
      w: 0.40,
      d: 0.26,
      h: 0.26,
      color: const Color(0xFF2E5090),
      shape: GearShape.softBag,
      soft: true,
      compressibility: 0.3,
      squash: 0.3,
    );
    final mesh = gearMesh(b);
    final top = mesh.verts.map((v) => v.y).reduce(math.max);
    expect(top, closeTo(0.26 * 0.7, 1e-9));
  });

  test('장식선은 면 위에 있다 (카메라를 향한 면에서만 그려도 떠 보이지 않게)', () {
    final rnd = math.Random(3);
    for (final shape in GearShape.values) {
      final mesh = gearMesh(_box(shape, rnd, 0));
      for (final f in mesh.faces) {
        final p0 = mesh.verts[f.idx[0]];
        for (final l in f.lines) {
          for (final p in l.pts) {
            expect(f.normal.dot(p - p0).abs(), lessThan(1e-6),
                reason: '${shape.name} 장식선이 면에서 벗어남');
          }
        }
      }
    }
  });

  test('sliceFace: 사각형을 가로지르는 선분', () {
    final quad = [
      const Vec3(0, 0, 0),
      const Vec3(2, 0, 0),
      const Vec3(2, 1, 0),
      const Vec3(0, 1, 0),
    ];
    final seg = sliceFace(quad, 0, 0.5)!;
    expect(seg.length, 2);
    expect(seg.every((p) => (p.x - 0.5).abs() < 1e-12), isTrue);
    expect(sliceFace(quad, 0, 3.0), isNull);
  });
}
