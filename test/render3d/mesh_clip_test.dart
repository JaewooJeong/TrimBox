import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/depth_sort.dart';
import 'package:trimbox/render3d/fixtures.dart';
import 'package:trimbox/render3d/gear_shapes.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/mesh.dart';
import 'package:trimbox/render3d/scene.dart';
import 'package:trimbox/render3d/vec3.dart';

import 'mesh_checks.dart';

double _volume(Mesh m) {
  // 발산 정리: 면마다 부채꼴 삼각형의 부호 있는 부피 (법선 방향으로 부호를 맞춘다)
  var v = 0.0;
  for (final f in m.faces) {
    final p = m.facePoints(f);
    var fv = 0.0;
    for (var i = 1; i + 1 < p.length; i++) {
      fv += p[0].dot(p[i].cross(p[i + 1])) / 6;
    }
    final n = newellNormal(p);
    v += n.dot(f.normal) >= 0 ? fv : -fv;
  }
  return v;
}

void main() {
  group('clipMesh', () {
    for (final shape in GearShape.values) {
      test('${shape.name}: 두 조각 모두 닫힌 볼록체, 부피 합 = 원래 부피', () {
        final rnd = math.Random(shape.index + 11);
        for (var i = 0; i < 30; i++) {
          final a = Aabb(0.1, 0.0, 0.2, 0.1 + 0.1 + rnd.nextDouble(),
              0.05 + rnd.nextDouble() * 0.6, 0.2 + 0.1 + rnd.nextDouble());
          final mesh = gearMeshFor(shape, a);
          final axis = rnd.nextInt(3);
          final value = a.minOn(axis) +
              (a.maxOn(axis) - a.minOn(axis)) * (0.1 + 0.8 * rnd.nextDouble());
          final lo = clipMesh(mesh, axis, value, keepBelow: true);
          final hi = clipMesh(mesh, axis, value, keepBelow: false);
          final why = '${shape.name} #$i axis $axis @ $value';

          for (final (part, below) in [(lo, true), (hi, false)]) {
            expectNoNaN(part, why);
            expectInsideAabb(part, a, 1e-9, why);
            for (final p in part.allPoints) {
              if (below) {
                expect(p[axis], lessThanOrEqualTo(value + 1e-9), reason: why);
              } else {
                expect(p[axis], greaterThanOrEqualTo(value - 1e-9), reason: why);
              }
            }
            expectPlanarFaces(part, 1e-6, why);
            expectConvex(part, 1e-6, why);
            expectManifold(part, why);
            // 단면은 하나, 절단선은 단면의 변과 정확히 같다
            final caps = part.faces.where((f) => f.isCap).toList();
            expect(caps.length, 1, reason: why);
            expect(caps.single.cutEdges.length, caps.single.idx.length);
            expect(part.cutEdgeKeys.length, caps.single.idx.length, reason: why);
          }
          expect(_volume(lo) + _volume(hi), closeTo(_volume(mesh), 1e-9),
              reason: why);
        }
      });
    }

    test('두 번 잘라도 절단선 표시가 유지된다', () {
      final a = const Aabb(0, 0, 0, 1, 0.4, 0.5);
      final once = clipMesh(gearMeshFor(GearShape.cooler, a), 0, 0.6,
          keepBelow: true);
      final twice = clipMesh(once, 2, 0.2, keepBelow: false);
      expectManifold(twice, 'twice');
      expectConvex(twice, 1e-9, 'twice');
      expect(twice.faces.where((f) => f.isCap).length, 2);
      // x = 0.6 단면의 변은 여전히 절단선
      for (final f in twice.faces) {
        for (var k = 0; k < f.idx.length; k++) {
          final p = twice.verts[f.idx[k]];
          final q = twice.verts[f.idx[(k + 1) % f.idx.length]];
          final onCut = ((p.x - 0.6).abs() < 1e-9 && (q.x - 0.6).abs() < 1e-9) ||
              ((p.z - 0.2).abs() < 1e-9 && (q.z - 0.2).abs() < 1e-9);
          expect(f.cutEdges.contains(k), onCut, reason: '$p → $q');
        }
      }
    });

    test('평면이 메시 밖이면 한쪽은 그대로, 다른 쪽은 빈 메시', () {
      final a = const Aabb(0, 0, 0, 1, 1, 1);
      final mesh = gearMeshFor(GearShape.box, a);
      final all = clipMesh(mesh, 1, 2.0, keepBelow: true);
      expect(all.faces.length, mesh.faces.length);
      expect(all.cutEdgeKeys, isEmpty);
      expect(clipMesh(mesh, 1, 2.0, keepBelow: false).faces, isEmpty);
    });

    test('휠하우스 아치도 자를 수 있다', () {
      final s = TrunkSpace.sorento();
      final arch = wheelhouseMesh(s, left: true)!;
      final lo = clipMesh(arch, 2, 0.44, keepBelow: true);
      final hi = clipMesh(arch, 2, 0.44, keepBelow: false);
      expectManifold(lo, 'arch lo');
      expectManifold(hi, 'arch hi');
      expect(_volume(lo) + _volume(hi), closeTo(_volume(arch), 1e-9));
    });
  });

  group('순환 가림 풀기', () {
    // 휠하우스(W) 위에 걸친 짐(S), 그 앞에 세운 판(T): 왼쪽 위에서 보면
    // S 가 W 를, T 가 S 를, W 가 T 를 가린다 → 어떤 순서로도 못 그린다.
    final space = TrunkSpace.sorento();
    TrimBox box(String id, Aabb a, GearShape shape) => TrimBox(
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
    final boxes = [
      box('under', const Aabb(0.15, 0, 0.15, 0.73, 0.35, 0.40), GearShape.crate),
      box('S', const Aabb(0.03, 0.35, 0.15, 0.73, 0.60, 0.40), GearShape.softBag),
      box('T', const Aabb(0.15, 0, 0.44, 0.75, 0.60, 0.51), GearShape.flat),
    ];
    final cam = OrbitCamera.fitTrunk(space, const Size(960, 640),
        yaw: -0.99, pitch: 0.40);

    test('자르지 않으면 순환이 있다', () {
      final objs = sceneObjects(space, boxes);
      final graph = DepthGraph([for (final o in objs) o.aabb], cam.position);
      expect(graph.findCycle(), isNotNull);
    });

    test('sceneDrawOrder 는 물체를 잘라 순환 없이 정렬한다', () {
      final order = sceneDrawOrder(space, boxes, cam);
      expect(order.any((o) => o.isSplit), isTrue);
      final graph = DepthGraph([for (final o in order) o.aabb], cam.position);
      expect(graph.findCycle(), isNull);
      // 순서가 모든 제약을 지킨다
      for (var i = 0; i < order.length; i++) {
        for (var j = i + 1; j < order.length; j++) {
          expect(depthOrder(order[i].aabb, order[j].aabb, cam.position),
              lessThanOrEqualTo(0),
              reason: '${order[j].aabb} 가 ${order[i].aabb} 보다 먼저여야 함');
        }
      }
      // 조각의 상자들은 원래 상자를 빈틈없이 나눈다
      final byOrigin = <int, List<SceneObject>>{};
      for (final o in order) {
        byOrigin.putIfAbsent(o.origin, () => []).add(o);
      }
      for (final parts in byOrigin.values) {
        final full = parts.first.fullAabb;
        final vol = parts.fold<double>(
            0, (v, p) => v + p.aabb.w * p.aabb.h * p.aabb.d);
        expect(vol, closeTo(full.w * full.h * full.d, 1e-9));
        expect(parts.where((p) => p.isFirstPart).length, 1);
        expect(parts.where((p) => p.isLastPart).length, 1);
      }
    });

    test('순환이 없는 장면은 아무것도 자르지 않는다', () {
      final order = sceneDrawOrder(space, [boxes[0]], cam);
      expect(order.any((o) => o.isSplit), isFalse);
      expect(order.every((o) => o.isFirstPart && o.isLastPart), isTrue);
    });
  });

  test('Vec3 인덱스 접근 (절단 축)', () {
    const v = Vec3(1, 2, 3);
    expect([v[0], v[1], v[2]], [1, 2, 3]);
  });
}
