// 메시 불변식 검사 (모양·고정물 테스트 공용)
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/mesh.dart';
import 'package:trimbox/render3d/vec3.dart';

void expectNoNaN(Mesh mesh, String why) {
  for (final p in mesh.allPoints) {
    expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue,
        reason: '$why: 점 $p');
  }
  for (final f in mesh.faces) {
    final n = f.normal;
    expect(n.x.isFinite && n.y.isFinite && n.z.isFinite, isTrue, reason: why);
    expect(n.length, closeTo(1.0, 1e-9), reason: '$why: 법선 길이');
  }
}

/// 꼭짓점과 장식선 전부가 AABB ± eps 안
void expectInsideAabb(Mesh mesh, Aabb a, double eps, String why) {
  for (final p in mesh.allPoints) {
    expect(p.x, inInclusiveRange(a.x1 - eps, a.x2 + eps), reason: '$why x $p');
    expect(p.y, inInclusiveRange(a.y1 - eps, a.y2 + eps), reason: '$why y $p');
    expect(p.z, inInclusiveRange(a.z1 - eps, a.z2 + eps), reason: '$why z $p');
  }
}

Vec3 faceCentroid(Mesh mesh, MeshFace f) {
  var c = Vec3.zero;
  for (final i in f.idx) {
    c = c + mesh.verts[i];
  }
  return c * (1.0 / f.idx.length);
}

void expectNormalsOutward(Mesh mesh, Vec3 center, String why) {
  for (final f in mesh.faces) {
    expect(f.normal.dot(faceCentroid(mesh, f) - center), greaterThan(0),
        reason: '$why: 법선이 안쪽을 향함 ${f.normal}');
  }
}

void expectPlanarFaces(Mesh mesh, double eps, String why) {
  for (final f in mesh.faces) {
    final p0 = mesh.verts[f.idx[0]];
    for (final i in f.idx) {
      expect(f.normal.dot(mesh.verts[i] - p0).abs(), lessThan(eps),
          reason: '$why: 면이 평면이 아님');
    }
  }
}

/// 볼록: 모든 꼭짓점이 모든 면의 안쪽
void expectConvex(Mesh mesh, double eps, String why) {
  for (final f in mesh.faces) {
    final p0 = mesh.verts[f.idx[0]];
    for (final v in mesh.verts) {
      expect(f.normal.dot(v - p0), lessThan(eps), reason: '$why: 볼록 아님');
    }
  }
}

/// 닫힌 다면체: 모든 모서리를 정확히 두 면이 공유 (실루엣 계산의 전제)
void expectManifold(Mesh mesh, String why) {
  expect(mesh.closed, isTrue, reason: why);
  final n = mesh.verts.length;
  final count = <int, int>{};
  for (final f in mesh.faces) {
    for (var k = 0; k < f.idx.length; k++) {
      final a = f.idx[k], b = f.idx[(k + 1) % f.idx.length];
      final key = a < b ? a * n + b : b * n + a;
      count[key] = (count[key] ?? 0) + 1;
    }
  }
  for (final c in count.values) {
    expect(c, 2, reason: '$why: 모서리를 공유하는 면 수');
  }
}
