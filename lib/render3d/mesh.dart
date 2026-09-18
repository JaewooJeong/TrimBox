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

  /// 물체를 정렬용으로 잘랐을 때 생긴 단면인가 (불투명할 때만 그린다)
  final bool isCap;

  /// 잘린 자리의 변: k 가 들어 있으면 변 (idx[k] → idx[k+1]) 은 실제 모서리가 아니라
  /// 절단선이므로 긋지 않는다.
  final List<int> cutEdges;

  const MeshFace(
    this.idx,
    this.normal, {
    this.tint = 0,
    this.smooth = false,
    this.color,
    this.lines = const [],
    this.isCap = false,
    this.cutEdges = const [],
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

  /// 절단선인 변의 키 집합 (작은 인덱스 × 꼭짓점 수 + 큰 인덱스). 실루엣에서 뺀다.
  Set<int> get cutEdgeKeys {
    final n = verts.length;
    final out = <int>{};
    for (final f in faces) {
      for (final k in f.cutEdges) {
        final a = f.idx[k], b = f.idx[(k + 1) % f.idx.length];
        out.add(a < b ? a * n + b : b * n + a);
      }
    }
    return out;
  }

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

/// 메시를 축 정렬 평면 (축 [axis] 좌표 = [value]) 으로 잘라 한쪽만 남긴다.
/// [keepBelow] 면 좌표 ≤ value 쪽. 볼록 메시면 결과도 볼록이고, 닫힌 메시면 단면을
/// 막아 닫힌 메시로 돌려준다. 절단선은 [MeshFace.cutEdges] 로 표시해 모서리선·실루엣에서
/// 빠지게 한다 — 두 조각을 이어 그리면 원래 물체와 같아 보인다.
///
/// 그리기 순서가 순환할 때(서로 돌아가며 가리는 세 물체) 물체를 나눠 순환을 끊는 데 쓴다.
Mesh clipMesh(Mesh m, int axis, double value, {required bool keepBelow}) {
  const eps = 1e-9;
  bool inside(Vec3 p) => keepBelow ? p[axis] <= value + eps : p[axis] >= value - eps;

  final verts = <Vec3>[];
  final remap = <int, int>{}; // 원래 꼭짓점 → 새 인덱스
  final onEdge = <int, int>{}; // 잘린 변(키) → 교점의 새 인덱스
  final n = m.verts.length;

  int keep(int i) => remap.putIfAbsent(i, () {
        verts.add(m.verts[i]);
        return verts.length - 1;
      });
  int cut(int a, int b) {
    final key = a < b ? a * n + b : b * n + a;
    return onEdge.putIfAbsent(key, () {
      final pa = m.verts[a], pb = m.verts[b];
      final t = (value - pa[axis]) / (pb[axis] - pa[axis]);
      final p = pa + (pb - pa) * t;
      // 부동소수점 오차 없이 정확히 평면 위에
      verts.add(switch (axis) {
        0 => Vec3(value, p.y, p.z),
        1 => Vec3(p.x, value, p.z),
        _ => Vec3(p.x, p.y, value),
      });
      return verts.length - 1;
    });
  }

  final faces = <MeshFace>[];
  // 단면 고리: 교점 ↔ 이웃 교점 (면마다 감는 방향이 달라서 무방향으로 잇는다)
  final capAdj = <int, List<int>>{};
  for (final f in m.faces) {
    final k = f.idx.length;
    final outIdx = <int>[];
    final outCut = <bool>[];
    for (var e = 0; e < k; e++) {
      final a = f.idx[e], b = f.idx[(e + 1) % k];
      final wasCut = f.cutEdges.contains(e);
      final ia = inside(m.verts[a]), ib = inside(m.verts[b]);
      if (ia && ib) {
        outIdx.add(keep(a));
        outCut.add(wasCut);
      } else if (ia && !ib) {
        outIdx.add(keep(a));
        outCut.add(wasCut);
        outIdx.add(cut(a, b));
        outCut.add(true); // 여기서 다음 교점까지가 절단선
      } else if (!ia && ib) {
        outIdx.add(cut(a, b));
        outCut.add(wasCut);
      }
    }
    // 같은 점이 연달아 나오면(꼭짓점이 평면 위) 하나로
    final idx = <int>[];
    final cuts = <bool>[];
    for (var i = 0; i < outIdx.length; i++) {
      final next = outIdx[(i + 1) % outIdx.length];
      if (outIdx[i] == next) continue;
      idx.add(outIdx[i]);
      cuts.add(outCut[i]);
    }
    if (idx.length < 3) continue;
    for (var i = 0; i < idx.length; i++) {
      if (cuts[i]) {
        final a = idx[i], b = idx[(i + 1) % idx.length];
        if ((verts[a][axis] - value).abs() < 1e-7 &&
            (verts[b][axis] - value).abs() < 1e-7) {
          capAdj.putIfAbsent(a, () => []).add(b);
          capAdj.putIfAbsent(b, () => []).add(a);
        }
      }
    }
    faces.add(MeshFace(
      idx,
      f.normal,
      tint: f.tint,
      smooth: f.smooth,
      color: f.color,
      isCap: f.isCap,
      cutEdges: [
        for (var i = 0; i < cuts.length; i++)
          if (cuts[i]) i
      ],
      lines: [
        for (final l in f.lines) ..._clipLine(l, axis, value, keepBelow),
      ],
    ));
  }

  // 단면 막기: 절단선을 이어 고리 하나가 되면 뚜껑 면을 단다
  var closed = m.closed;
  if (m.closed && capAdj.length >= 3) {
    final start = capAdj.keys.first;
    final loop = <int>[start];
    int? prev;
    var cur = start;
    var ok = capAdj.values.every((v) => v.length == 2);
    while (ok) {
      final nb = capAdj[cur]!;
      final next = nb[0] != prev ? nb[0] : nb[1];
      if (next == start) break;
      if (loop.length > capAdj.length) {
        ok = false;
        break;
      }
      loop.add(next);
      prev = cur;
      cur = next;
    }
    if (ok && loop.length == capAdj.length) {
      final normal = switch (axis) {
        0 => Vec3(keepBelow ? 1 : -1, 0, 0),
        1 => Vec3(0, keepBelow ? 1 : -1, 0),
        _ => Vec3(0, 0, keepBelow ? 1 : -1),
      };
      faces.add(MeshFace(loop, normal,
          smooth: true,
          isCap: true,
          cutEdges: [for (var i = 0; i < loop.length; i++) i]));
    } else {
      closed = false;
    }
  }
  return Mesh(verts, faces, closed: closed);
}

List<DecoLine> _clipLine(DecoLine l, int axis, double value, bool keepBelow) {
  bool inside(Vec3 p) => keepBelow ? p[axis] <= value : p[axis] >= value;
  if (l.pts.every(inside)) return [l];
  final out = <DecoLine>[];
  final count = l.closed ? l.pts.length : l.pts.length - 1;
  for (var i = 0; i < count; i++) {
    var a = l.pts[i], b = l.pts[(i + 1) % l.pts.length];
    final ia = inside(a), ib = inside(b);
    if (!ia && !ib) continue;
    if (ia != ib) {
      final t = (value - a[axis]) / (b[axis] - a[axis]);
      final c = a + (b - a) * t;
      if (ia) {
        b = c;
      } else {
        a = c;
      }
    }
    out.add(DecoLine([a, b], tone: l.tone, width: l.width));
  }
  return out;
}
