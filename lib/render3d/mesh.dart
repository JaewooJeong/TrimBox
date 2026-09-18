import 'dart:ui' show Color;

import 'geometry.dart';
import 'vec3.dart';

/// 면 위에 그리는 장식선 (끈·이음선·리브). 면이 카메라를 향할 때만 그린다.
class DecoLine {
  final List<Vec3> pts;

  /// 밑색 대비 밝기: 음수 = 어둡게(검정 쪽), 양수 = 밝게(흰색 쪽). 크기는 섞는 비율.
  final double tone;
  final double width; // 화면 px
  final bool closed;

  const DecoLine(this.pts, {this.tone = -0.45, this.width = 1.2, this.closed = false});
}

/// 꼭짓점 인덱스로 정의된 면. [normal] 은 바깥(보이는 쪽)을 향한다.
class MeshFace {
  final List<int> idx;
  final Vec3 normal;

  /// 밑색 보정: 양수 = 밝게, 음수 = 어둡게 (−1..1)
  final double tint;

  /// true 면 모서리를 긋지 않는다 (원통 옆면·모따기처럼 이어지는 면)
  final bool smooth;

  /// 물체 밑색 대신 쓸 색 (고정물의 램프 등)
  final Color? color;

  final List<DecoLine> lines;

  const MeshFace(
    this.idx,
    this.normal, {
    this.tint = 0,
    this.smooth = false,
    this.color,
    this.lines = const [],
  });
}

/// 볼록 다면체(또는 면 묶음). 꼭짓점을 공유하므로 투영은 꼭짓점당 한 번,
/// 닫힌 메시는 공유 모서리로 실루엣을 구할 수 있다.
class Mesh {
  final List<Vec3> verts;
  final List<MeshFace> faces;

  /// 닫힌 볼록 다면체인가 (실루엣 외곽선을 그릴 수 있다)
  final bool closed;

  const Mesh(this.verts, this.faces, {this.closed = true});

  List<Vec3> facePoints(MeshFace f) => [for (final i in f.idx) verts[i]];

  /// 테스트·도구용: 독립된 [Face] 목록
  List<Face> toFaces() => [for (final f in faces) Face(facePoints(f), f.normal)];

  /// 장식선까지 포함한 모든 점 (경계 검사용)
  Iterable<Vec3> get allPoints sync* {
    yield* verts;
    for (final f in faces) {
      for (final l in f.lines) {
        yield* l.pts;
      }
    }
  }
}

/// 메시 조립 도우미. 법선은 Newell 방법으로 구하고 [center] 기준 바깥으로 맞춘다.
class MeshBuilder {
  final Vec3 center;
  final List<Vec3> verts = [];
  final List<MeshFace> faces = [];

  MeshBuilder(this.center);

  int v(double x, double y, double z) {
    verts.add(Vec3(x, y, z));
    return verts.length - 1;
  }

  int add(Vec3 p) {
    verts.add(p);
    return verts.length - 1;
  }

  List<Vec3> pts(List<int> idx) => [for (final i in idx) verts[i]];

  /// 면을 추가한다. [normal] 을 주지 않으면 계산해서 바깥을 향하게 한다.
  void face(
    List<int> idx, {
    Vec3? normal,
    double tint = 0,
    bool smooth = false,
    Color? color,
    List<DecoLine> Function(List<Vec3> pts, Vec3 normal)? deco,
  }) {
    final p = pts(idx);
    var n = normal ?? newellNormal(p);
    if (normal == null) {
      var c = Vec3.zero;
      for (final q in p) {
        c = c + q;
      }
      c = c * (1.0 / p.length);
      if (n.dot(c - center) < 0) n = -n;
    }
    faces.add(MeshFace(idx, n,
        tint: tint,
        smooth: smooth,
        color: color,
        lines: deco == null ? const [] : deco(p, n)));
  }

  Mesh build({bool closed = true}) => Mesh(verts, faces, closed: closed);
}

/// Newell 방법의 다각형 법선
Vec3 newellNormal(List<Vec3> p) => newellPolygonNormal(p);

/// 다각형을 평면 (축 [axis] 좌표 = [value]) 으로 잘랐을 때의 선분.
/// 교차가 없으면 null. 장식선을 면 위에 정확히 얹는 데 쓴다.
List<Vec3>? sliceFace(List<Vec3> p, int axis, double value) {
  final out = <Vec3>[];
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    final da = a[axis] - value, db = b[axis] - value;
    if ((da < 0 && db >= 0) || (da >= 0 && db < 0)) {
      final t = da / (da - db);
      out.add(a + (b - a) * t);
    }
  }
  if (out.length != 2) return null;
  return out;
}

/// 사각형 [q] (q0→q1 이 u, q0→q3 이 v) 위의 점. 평면 사다리꼴이면 면 위에 있다.
Vec3 quadPoint(List<Vec3> q, double u, double v) {
  final a = q[0] + (q[1] - q[0]) * u;
  final b = q[3] + (q[2] - q[3]) * u;
  return a + (b - a) * v;
}
