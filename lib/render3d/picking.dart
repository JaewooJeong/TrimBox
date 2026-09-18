import '../models/trim_box.dart';
import 'gear_shapes.dart';
import 'geometry.dart';
import 'mesh.dart';
import 'vec3.dart';

/// 반직선과 AABB의 교차 (slab 법). 진입 거리 t (>= 0) 또는 null.
double? rayAabbHit(Ray r, Aabb b) {
  var tMin = 0.0;
  var tMax = double.infinity;
  for (var axis = 0; axis < 3; axis++) {
    final o = r.origin[axis];
    final d = r.dir[axis];
    final lo = b.minOn(axis);
    final hi = b.maxOn(axis);
    if (d.abs() < 1e-12) {
      if (o < lo || o > hi) return null;
      continue;
    }
    var t1 = (lo - o) / d;
    var t2 = (hi - o) / d;
    if (t1 > t2) {
      final tmp = t1;
      t1 = t2;
      t2 = tmp;
    }
    if (t1 > tMin) tMin = t1;
    if (t2 < tMax) tMax = t2;
    if (tMin > tMax) return null;
  }
  return tMin;
}

/// 반직선과 수평 평면 y = [planeY]의 교점. 평행하거나 뒤쪽이면 null.
Vec3? rayPlaneY(Ray r, double planeY) {
  final dy = r.dir.y;
  if (dy.abs() < 1e-9) return null;
  final t = (planeY - r.origin.y) / dy;
  if (t < 0) return null;
  return r.at(t);
}

/// 반직선과 닫힌 볼록 메시의 교차 (면 평면으로 구간을 좁혀 간다). 진입 거리 또는 null.
double? rayConvexMeshHit(Ray r, Mesh m) {
  var tNear = 0.0;
  var tFar = double.infinity;
  for (final f in m.faces) {
    final p0 = m.verts[f.idx[0]];
    final denom = f.normal.dot(r.dir);
    final dist = f.normal.dot(p0 - r.origin); // > 0 이면 원점이 면 안쪽
    if (denom.abs() < 1e-12) {
      if (dist < 0) return null; // 면과 나란하고 바깥
      continue;
    }
    final t = dist / denom;
    if (denom < 0) {
      if (t > tNear) tNear = t; // 들어가는 면
    } else {
      if (t < tFar) tFar = t; // 나가는 면
    }
    if (tNear > tFar) return null;
  }
  return tNear;
}

/// 화면에서 고른 반직선에 걸리는 박스.
///
/// 판정은 넉넉한 AABB 가 기본이다 (터치에서는 모양의 빈 귀퉁이를 눌러도 잡혀야 한다).
/// 다만 AABB 가 둘 이상 걸리면 **실제로 그려진 모양**에 반직선이 닿는 박스 중 가장
/// 가까운 것을 고른다 — 원통 AABB 의 빈 귀퉁이 너머로 보이는 쿨러를 누르면 쿨러가 잡힌다.
/// 그려진 모양에 닿는 박스가 없으면 가장 가까운 AABB.
TrimBox? pickBox(Ray ray, Iterable<TrimBox> boxes) {
  TrimBox? nearest;
  var nearestT = double.infinity;
  final hits = <TrimBox>[];
  for (final b in boxes) {
    final t = rayAabbHit(ray, Aabb.fromBox(b));
    if (t == null) continue;
    hits.add(b);
    if (t < nearestT) {
      nearestT = t;
      nearest = b;
    }
  }
  if (hits.length <= 1) return nearest;

  TrimBox? best;
  var bestT = double.infinity;
  for (final b in hits) {
    final t = b.shape == GearShape.box
        ? rayAabbHit(ray, Aabb.fromBox(b))
        : rayConvexMeshHit(ray, gearMesh(b));
    if (t != null && t < bestT) {
      bestT = t;
      best = b;
    }
  }
  return best ?? nearest;
}
