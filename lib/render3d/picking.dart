import 'geometry.dart';
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
