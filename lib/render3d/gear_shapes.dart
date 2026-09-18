import 'dart:math' as math;

import '../models/trim_box.dart';
import 'geometry.dart';
import 'mesh.dart';
import 'vec3.dart';

/// 짐의 모양별 메시. **모든 꼭짓점과 장식선은 박스의 AABB 안에 있다** —
/// 충돌·지지 판정은 AABB 그대로이므로 그림이 물리보다 커 보이면 안 된다.
/// 모든 모양은 볼록 다면체라서 법선 컬링만으로 면 순서 문제가 없다.
Mesh gearMesh(TrimBox b) {
  final rotated = b.rotY == 90 || b.rotY == 270;
  return gearMeshFor(
    b.shape,
    Aabb.fromBox(b),
    squashY: b.squash,
    squashX: rotated ? b.squashD : b.squashW,
    squashZ: rotated ? b.squashW : b.squashD,
  );
}

/// 테스트·도구용: 독립된 면 목록
List<Face> gearFaces(TrimBox b) => gearMesh(b).toFaces();

/// [squashX]/[squashY]/[squashZ]: 월드 축별로 눌린 비율 (천 가방의 주름 표시에만 쓴다).
Mesh gearMeshFor(
  GearShape shape,
  Aabb a, {
  double squashX = 0,
  double squashY = 0,
  double squashZ = 0,
}) =>
    switch (shape) {
      GearShape.box => _box(a),
      GearShape.cylinder => _cylinder(a),
      GearShape.softBag => _softBag(a, [squashX, squashY, squashZ]),
      GearShape.cooler => _cooler(a),
      GearShape.crate => _crate(a),
      GearShape.flat => _flat(a),
      GearShape.hardCase => _hardCase(a),
    };

/// 원통이 눕는 축 (0=x, 1=y, 2=z): 단면이 가장 둥근 축, 비슷하면 긴 축.
int cylinderAxis(Aabb a) {
  final dims = [a.w, a.h, a.d];
  final maxDim = dims.reduce(math.max);
  var best = 0;
  var bestScore = -1.0;
  for (var k = 0; k < 3; k++) {
    final p = dims[(k + 1) % 3], q = dims[(k + 2) % 3];
    final hi = math.max(p, q);
    final round = hi <= 0 ? 0.0 : math.min(p, q) / hi;
    final score = round +
        (maxDim <= 0 ? 0.0 : 0.05 * dims[k] / maxDim) +
        (k == 1 ? 0.001 : 0.0);
    if (score > bestScore) {
      bestScore = score;
      best = k;
    }
  }
  return best;
}

// ── 공용 ──

const double _dark = -0.5;
const double _light = 0.35;

/// y 높이에 네 꼭짓점 고리 (안쪽으로 [inset] 만큼 들여서). 순서: (x1,z1) (x2,z1) (x2,z2) (x1,z2)
List<int> _ring(MeshBuilder m, Aabb a, double y, double inset) => [
      m.v(a.x1 + inset, y, a.z1 + inset),
      m.v(a.x2 - inset, y, a.z1 + inset),
      m.v(a.x2 - inset, y, a.z2 - inset),
      m.v(a.x1 + inset, y, a.z2 - inset),
    ];

/// 면 위의 사각 고리 장식선 (u, v 는 0..1)
DecoLine _loopOn(List<Vec3> quad, double u0, double u1, double v0, double v1,
        {double tone = _dark, double width = 1.2}) =>
    DecoLine([
      quadPoint(quad, u0, v0),
      quadPoint(quad, u1, v0),
      quadPoint(quad, u1, v1),
      quadPoint(quad, u0, v1),
    ], tone: tone, width: width, closed: true);

List<DecoLine> _slices(List<Vec3> pts, int axis, List<double> values,
    {double tone = _dark, double width = 1.2}) {
  final out = <DecoLine>[];
  for (final v in values) {
    final seg = sliceFace(pts, axis, v);
    if (seg != null) out.add(DecoLine(seg, tone: tone, width: width));
  }
  return out;
}

// ── 상자 ──

Mesh _box(Aabb a) {
  final m = MeshBuilder(a.center);
  final lo = _ring(m, a, a.y1, 0), hi = _ring(m, a, a.y2, 0);
  for (var k = 0; k < 4; k++) {
    m.face([lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]]);
  }
  m.face(hi);
  m.face(lo);
  return m.build();
}

// ── 납작한 판 (접이식 테이블·그리들·매트) ──

Mesh _flat(Aabb a) {
  final m = MeshBuilder(a.center);
  final lo = _ring(m, a, a.y1, 0), hi = _ring(m, a, a.y2, 0);
  final yLine = a.y2 - a.h * 0.22;
  for (var k = 0; k < 4; k++) {
    m.face([lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]],
        deco: (p, n) => _slices(p, 1, [yLine], tone: _light, width: 1.0));
  }
  m.face(hi,
      tint: 0.06,
      deco: (p, n) => [
            _loopOn(p, 0.04, 0.96, 0.04, 0.96, tone: _light, width: 1.0),
          ]);
  m.face(lo);
  return m.build();
}

// ── 원통 (텐트·타프·의자 수납 가방, 말아 둔 매트, 워터저그·코펠) ──

const int cylinderSides = 14;

Mesh _cylinder(Aabb a) {
  final axis = cylinderAxis(a);
  // 단면의 두 방향: v 는 위/아래에 평평한 면이 오는 방향 (눕힌 원통이 바닥에 닿게 y)
  final int uAxis, vAxis;
  switch (axis) {
    case 0:
      uAxis = 2;
      vAxis = 1;
    case 2:
      uAxis = 0;
      vAxis = 1;
    default:
      uAxis = 0;
      vAxis = 2;
  }
  final dims = [a.w, a.h, a.d];
  final c = a.center;
  final ru = dims[uAxis] / 2, rv = dims[vAxis] / 2, half = dims[axis] / 2;

  const n = cylinderSides;
  // 꼭짓점이 v 방향 끝에 정확히 닿도록 보정 (n 이 4의 배수가 아니라서)
  var maxSin = 0.0;
  for (var i = 0; i < n; i++) {
    maxSin = math.max(maxSin, math.sin(2 * math.pi * i / n).abs());
  }
  final sv = 1 / maxSin;

  Vec3 at(double along, double u, double v) {
    final p = [c.x, c.y, c.z];
    p[axis] += along;
    p[uAxis] += u;
    p[vAxis] += v;
    return Vec3(p[0], p[1], p[2]);
  }

  final m = MeshBuilder(c);
  final r0 = <int>[], r1 = <int>[];
  for (var i = 0; i < n; i++) {
    final t = 2 * math.pi * i / n;
    final u = math.cos(t) * ru;
    final v = (math.sin(t) * sv).clamp(-1.0, 1.0) * rv;
    r0.add(m.add(at(-half, u, v)));
    r1.add(m.add(at(half, u, v)));
  }
  // 조임끈 고리: +축 끝에서 14%
  final ringAt = c[axis] + half - dims[axis] * 0.14;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    m.face([r0[i], r0[j], r1[j], r1[i]],
        smooth: true,
        deco: (p, nrm) => _slices(p, axis, [ringAt], width: 1.4));
  }
  m.face(r0, tint: -0.08);
  m.face(r1, tint: -0.08, deco: (p, nrm) {
    // 조임끈 매듭: 끝면 가운데 작은 고리
    const k = 8;
    return [
      DecoLine([
        for (var i = 0; i < k; i++)
          at(half, math.cos(2 * math.pi * i / k) * ru * 0.24,
              math.sin(2 * math.pi * i / k) * rv * 0.24),
      ], tone: _dark, width: 1.2, closed: true),
    ];
  });
  return m.build();
}

// ── 천 가방 (침낭·더플백·배낭·소프트 쿨러): 모서리를 깎은 상자 ──

/// 눌린 천의 주름: 눌린 축에 수직인 짧고 살짝 비뚠 선 2~3개. [quad] 위의 점만 쓴다.
/// [acrossU]: true 면 주름이 u 방향으로 달린다 (v 가 눌린 축).
List<DecoLine> _creases(List<Vec3> quad, bool acrossU, double amount) {
  // (눌린 축 위치, 시작, 끝, 기울기)
  const marks = [
    [0.30, 0.10, 0.64, 0.035],
    [0.55, 0.30, 0.92, -0.030],
    [0.76, 0.14, 0.78, 0.025],
  ];
  final count = amount >= 0.2 ? 3 : 2;
  return [
    for (var i = 0; i < count; i++)
      DecoLine([
        for (final t in const [0.0, 0.45, 1.0])
          () {
            final along = marks[i][1] + (marks[i][2] - marks[i][1]) * t;
            // 가운데가 살짝 처진 꺾은선
            final level =
                marks[i][0] + marks[i][3] * (t == 0.45 ? 1.0 : (t == 0 ? 0 : 0.4));
            return acrossU
                ? quadPoint(quad, along, level)
                : quadPoint(quad, level, along);
          }(),
      ], tone: -0.30, width: 1.0),
  ];
}

Mesh _softBag(Aabb a, [List<double> squash = const [0, 0, 0]]) {
  final minDim = math.min(a.w, math.min(a.h, a.d));
  final c = minDim * 0.16;
  final m = MeshBuilder(a.center);
  final lo = [a.x1, a.y1, a.z1], hi = [a.x2, a.y2, a.z2];

  // 꼭짓점: 모서리(sx,sy,sz)마다 3개 — 면 축 k 에 속한 점은 나머지 두 축을 c 만큼 당긴다
  final ids = List<int>.filled(24, 0);
  for (var corner = 0; corner < 8; corner++) {
    final s = [(corner & 4) != 0, (corner & 2) != 0, (corner & 1) != 0];
    for (var k = 0; k < 3; k++) {
      final p = List<double>.filled(3, 0);
      for (var ax = 0; ax < 3; ax++) {
        final edge = s[ax] ? hi[ax] : lo[ax];
        p[ax] = ax == k ? edge : (s[ax] ? edge - c : edge + c);
      }
      ids[corner * 3 + k] = m.v(p[0], p[1], p[2]);
    }
  }
  int vid(bool sx, bool sy, bool sz, int k) =>
      ((sx ? 4 : 0) + (sy ? 2 : 0) + (sz ? 1 : 0)) * 3 + k;
  int at(List<bool> s, int k) => ids[vid(s[0], s[1], s[2], k)];

  // 끈: 긴 수평축을 가로지르는 띠 (길면 두 줄)
  final long = a.w >= a.d ? 0 : 2;
  final len = long == 0 ? a.w : a.d;
  final start = long == 0 ? a.x1 : a.z1;
  final straps = len >= 0.45
      ? [start + len * 0.3, start + len * 0.7]
      : [start + len * 0.5];
  List<DecoLine> strap(List<Vec3> p, Vec3 n) {
    if (n[long].abs() > 0.5 || n.y < -0.5) return <DecoLine>[];
    return _slices(p, long, straps, tone: _dark, width: 1.6);
  }

  // 주면 6개
  for (var k = 0; k < 3; k++) {
    final a1 = (k + 1) % 3, a2 = (k + 2) % 3;
    for (final sign in [false, true]) {
      final quad = <int>[];
      for (final pr in const [
        [false, false],
        [true, false],
        [true, true],
        [false, true]
      ]) {
        final s = List<bool>.filled(3, false);
        s[k] = sign;
        s[a1] = pr[0];
        s[a2] = pr[1];
        quad.add(at(s, k));
      }
      // 이 면의 (u, v) = (축 a1, 축 a2). 눌린 축이 면 안에 있으면 그 축에 수직인 주름.
      final face = k, uAxis = a1, vAxis = a2;
      m.face(quad, smooth: true, deco: (p, n) {
        final lines = strap(p, n);
        if (face == 1 && !sign) return lines; // 바닥면
        for (var ax = 0; ax < 3; ax++) {
          if (squash[ax] <= 0.02 || ax == face) continue;
          // 높이로 눌렸으면 옆면에, 옆으로 눌렸으면 윗면에 (눈에 잘 띄는 면 하나씩만)
          if (ax == 1 ? face == 1 : face != 1) continue;
          if (ax == vAxis) {
            lines.addAll(_creases(p, true, squash[ax]));
          } else if (ax == uAxis) {
            lines.addAll(_creases(p, false, squash[ax]));
          }
        }
        return lines;
      });
    }
  }
  // 모서리 모따기 12개: 축 e 를 따라가는 모서리, 나머지 두 축의 부호 (sa, sb)
  for (var e = 0; e < 3; e++) {
    final ax = (e + 1) % 3, bx = (e + 2) % 3;
    for (final sa in [false, true]) {
      for (final sb in [false, true]) {
        List<bool> s(bool se) {
          final r = List<bool>.filled(3, false);
          r[e] = se;
          r[ax] = sa;
          r[bx] = sb;
          return r;
        }

        m.face([
          at(s(false), ax),
          at(s(true), ax),
          at(s(true), bx),
          at(s(false), bx),
        ], smooth: true, tint: -0.04, deco: strap);
      }
    }
  }
  // 꼭짓점 삼각형 8개
  for (var corner = 0; corner < 8; corner++) {
    m.face([ids[corner * 3], ids[corner * 3 + 1], ids[corner * 3 + 2]],
        smooth: true, tint: -0.06);
  }
  return m.build();
}

// ── 하드 쿨러·차량용 냉장고: 아래로 살짝 좁아지는 몸통 + 밝은 뚜껑 ──

Mesh _cooler(Aabb a) {
  final foot = math.min(a.w, a.d);
  final m = MeshBuilder(a.center);
  final seamY = a.y1 + a.h * 0.78;
  final lidEdgeY = a.y2 - a.h * 0.05;
  final bottom = _ring(m, a, a.y1, foot * 0.035);
  final seam = _ring(m, a, seamY, 0);
  final lidEdge = _ring(m, a, lidEdgeY, 0);
  final top = _ring(m, a, a.y2, foot * 0.04);

  // 짧은 옆면(긴 수평축에 수직)에 손잡이 홈, 긴 앞뒷면에 걸쇠
  final longIsX = a.w >= a.d;
  for (var k = 0; k < 4; k++) {
    final j = (k + 1) % 4;
    final shortSide = longIsX ? (k == 1 || k == 3) : (k == 0 || k == 2);
    m.face([bottom[k], bottom[j], seam[j], seam[k]], deco: (p, n) {
      return shortSide
          ? [
              _loopOn(p, 0.24, 0.76, 0.62, 0.84),
              DecoLine([quadPoint(p, 0.30, 0.73), quadPoint(p, 0.70, 0.73)],
                  tone: _light, width: 1.6),
            ]
          : [_loopOn(p, 0.46, 0.54, 0.84, 1.0, width: 1.4)];
    });
    m.face([seam[k], seam[j], lidEdge[j], lidEdge[k]],
        tint: 0.24,
        deco: (p, n) => [
              // 뚜껑 이음선을 또렷하게
              DecoLine([p[0], p[1]], tone: _dark, width: 1.8),
            ]);
    m.face([lidEdge[k], lidEdge[j], top[j], top[k]], tint: 0.30, smooth: true);
  }
  m.face(top, tint: 0.24);
  m.face(bottom);
  return m.build();
}

// ── 수납 컨테이너·폴딩박스: 테두리 + 아래로 좁아지는 몸통 + 리브 ──

Mesh _crate(Aabb a) {
  final foot = math.min(a.w, a.d);
  final m = MeshBuilder(a.center);
  final rimY = a.y2 - a.h * 0.13;
  final bottom = _ring(m, a, a.y1, foot * 0.05);
  final rim = _ring(m, a, rimY, 0);
  final top = _ring(m, a, a.y2, 0);
  final bodyH = rimY - a.y1;
  final ribs = [a.y1 + bodyH * 0.36, a.y1 + bodyH * 0.70];

  for (var k = 0; k < 4; k++) {
    final j = (k + 1) % 4;
    m.face([bottom[k], bottom[j], rim[j], rim[k]],
        deco: (p, n) => _slices(p, 1, ribs, tone: _dark, width: 1.2));
    // 테두리 띠 (볼록 형상을 유지하려고 턱 없이 색으로만 구분)
    m.face([rim[k], rim[j], top[j], top[k]], tint: 0.14);
  }
  m.face(top,
      tint: 0.08,
      deco: (p, n) => [
            _loopOn(p, 0.06, 0.94, 0.06, 0.94, tone: _light, width: 1.2),
          ]);
  m.face(bottom);
  return m.build();
}

// ── 캐리어·파워스테이션: 세로 모서리를 깎은 하드 케이스 + 손잡이 ──

Mesh _hardCase(Aabb a) {
  final c = math.min(a.w, a.d) * 0.13;
  final m = MeshBuilder(a.center);
  List<int> oct(double y) => [
        m.v(a.x1 + c, y, a.z1),
        m.v(a.x2 - c, y, a.z1),
        m.v(a.x2, y, a.z1 + c),
        m.v(a.x2, y, a.z2 - c),
        m.v(a.x2 - c, y, a.z2),
        m.v(a.x1 + c, y, a.z2),
        m.v(a.x1, y, a.z2 - c),
        m.v(a.x1, y, a.z1 + c),
      ];
  final lo = oct(a.y1), hi = oct(a.y2);

  final longIsX = a.w >= a.d;
  final shortAxis = longIsX ? 2 : 0;
  final seamAt = longIsX ? (a.z1 + a.z2) / 2 : (a.x1 + a.x2) / 2;
  List<DecoLine> seam(List<Vec3> p, Vec3 n) => n[shortAxis].abs() > 0.5
      ? const []
      : _slices(p, shortAxis, [seamAt], tone: -0.4, width: 1.2);

  for (var k = 0; k < 8; k++) {
    final j = (k + 1) % 8;
    final bevel = k.isOdd;
    m.face([lo[k], lo[j], hi[j], hi[k]],
        smooth: bevel, tint: bevel ? 0.10 : 0, deco: seam);
  }
  m.face(hi, tint: 0.04, deco: (p, n) {
    final ctr = a.center;
    final l = (longIsX ? a.w : a.d) * 0.17;
    final off = (longIsX ? a.d : a.w) * 0.18;
    Vec3 pt(double along, double across) => longIsX
        ? Vec3(ctr.x + along, a.y2, ctr.z + across)
        : Vec3(ctr.x + across, a.y2, ctr.z + along);
    return [
      ...seam(p, n),
      // 손잡이
      DecoLine([pt(-l, off), pt(l, off)], tone: -0.6, width: 3.0),
    ];
  });
  m.face(lo);
  return m.build();
}

// ── 바닥에 닿는 모양 (접촉 그림자) ──

/// 짐이 놓인 면에 드리우는 그림자의 외곽 (y = AABB 밑면). 모양의 바닥 윤곽을 [pad] 만큼
/// 키운 것으로, AABB 밑면을 [pad] 만큼 키운 사각형을 벗어나지 않는다.
List<Vec3> gearFootprint(GearShape shape, Aabb a, {double pad = 0.015}) {
  final y = a.y1;
  final cx = (a.x1 + a.x2) / 2, cz = (a.z1 + a.z2) / 2;
  final hx = a.w / 2 + pad, hz = a.d / 2 + pad;

  List<Vec3> chamfered(double c) => [
        Vec3(cx - hx + c, y, cz - hz), Vec3(cx + hx - c, y, cz - hz), //
        Vec3(cx + hx, y, cz - hz + c), Vec3(cx + hx, y, cz + hz - c),
        Vec3(cx + hx - c, y, cz + hz), Vec3(cx - hx + c, y, cz + hz),
        Vec3(cx - hx, y, cz + hz - c), Vec3(cx - hx, y, cz - hz + c),
      ];
  List<Vec3> rect(double sx, double sz) => [
        Vec3(cx - hx * sx, y, cz - hz * sz), Vec3(cx + hx * sx, y, cz - hz * sz), //
        Vec3(cx + hx * sx, y, cz + hz * sz), Vec3(cx - hx * sx, y, cz + hz * sz),
      ];

  switch (shape) {
    case GearShape.cylinder:
      final axis = cylinderAxis(a);
      if (axis == 1) {
        // 세운 통: 타원
        return [
          for (var i = 0; i < cylinderSides; i++)
            Vec3(cx + hx * math.cos(2 * math.pi * i / cylinderSides), y,
                cz + hz * math.sin(2 * math.pi * i / cylinderSides)),
        ];
      }
      // 눕힌 원통: 바닥에 닿는 띠는 폭의 일부뿐
      return axis == 0 ? rect(1, 0.72) : rect(0.72, 1);
    case GearShape.softBag:
      return chamfered(math.min(a.w, math.min(a.h, a.d)) * 0.16 + pad);
    case GearShape.hardCase:
      return chamfered(math.min(a.w, a.d) * 0.13);
    case GearShape.cooler:
    case GearShape.crate:
      // 아래로 좁아지는 몸통
      final inset = math.min(a.w, a.d) * 0.03;
      return rect(1 - inset / hx, 1 - inset / hz);
    case GearShape.box:
    case GearShape.flat:
      return rect(1, 1);
  }
}
