import 'dart:math' as math;
import 'dart:ui' show Color;

import '../models/trunk_space.dart';
import 'geometry.dart';
import 'mesh.dart';
import 'vec3.dart';

/// 트렁크의 고정물(휠하우스 아치, 개구부 프레임, 차체 윤곽, 헤드레스트)을 메시로 만든다.
///
/// 원칙: 그림이 물리보다 커 보이면 안 된다.
///  - 휠하우스 아치의 모든 꼭짓점은 충돌 판정에 쓰는 휠하우스 AABB 안에 있다.
///  - 프레임(D필러·헤더·모서리 R)은 z ≥ d − frameDepth 구간에만 있다.
///  - 헤드레스트는 등받이 프로필 평면보다 짐칸 쪽(+z)으로 나오지 않는다.
///  - 차체 윤곽·범퍼·테일램프는 차 밖(z > d)에만 있다.
class FixtureObject {
  final Aabb aabb; // 뒤→앞 정렬용
  final Mesh mesh;
  final Color color;
  final double alpha;
  final bool outline; // 어두운 모서리선을 긋는가

  /// −1 = 왼쪽, +1 = 오른쪽에 붙은 고정물. 카메라가 그쪽으로 돌아가 짐칸을 가리게
  /// 되면 페인터가 반투명하게 만든다 (단면도처럼). 0 = 항상 그대로.
  final int fadeSide;

  const FixtureObject(this.aabb, this.mesh, this.color,
      {this.alpha = 1.0, this.outline = true, this.fadeSide = 0});
}

const Color wheelhouseColor = Color(0xFF615E5A);
const Color frameColor = Color(0xFF3A3D43);
const Color bodyGhostColor = Color(0xFF9AA3AD);
const Color lampColor = Color(0xD9C8283C);

// ── 휠하우스 아치 ──

/// 아치 어깨 한쪽의 분할 수 (전체 윤곽 = 수직 2 + 어깨 2×3 + 윗면 1 = 9 구간)
const int wheelhouseShoulderSegments = 3;

/// z–y 평면의 아치 윤곽 (앞뒤 어깨가 둥근 평평한 윗면)을 x 방향으로 밀어낸 볼록체.
/// 위로 갈수록 벽 쪽으로 살짝 기운다. 전부 휠하우스 AABB 안.
Mesh? wheelhouseMesh(TrunkSpace s, {required bool left}) {
  final a = left ? Aabb.leftWheelhouse(s) : Aabb.rightWheelhouse(s);
  if (a.isEmpty) return null;
  final r = math.min(a.h * 0.55, a.d * 0.30);

  // 윤곽 (z, y): 앞(z1) 바닥 → 앞 어깨 → 윗면 → 뒤 어깨 → 뒤(z2) 바닥
  final prof = <List<double>>[
    [a.z1, 0],
  ];
  const n = wheelhouseShoulderSegments;
  for (var i = 0; i <= n; i++) {
    final t = math.pi - (math.pi / 2) * i / n; // 180° → 90°
    prof.add([a.z1 + r + r * math.cos(t), a.y2 - r + r * math.sin(t)]);
  }
  for (var i = 0; i <= n; i++) {
    final t = math.pi / 2 - (math.pi / 2) * i / n; // 90° → 0°
    prof.add([a.z2 - r + r * math.cos(t), a.y2 - r + r * math.sin(t)]);
  }
  prof.add([a.z2, 0]);

  final wallX = left ? a.x1 : a.x2;
  double innerX(double y) {
    final inset = a.w * 0.22 * (a.h <= 0 ? 0 : (y - a.y1) / a.h);
    return left ? a.x2 - inset : a.x1 + inset;
  }

  final m = MeshBuilder(a.center);
  final wall = <int>[], inner = <int>[];
  for (final p in prof) {
    final y = p[1].clamp(a.y1, a.y2).toDouble();
    final z = p[0].clamp(a.z1, a.z2).toDouble();
    wall.add(m.v(wallX, y, z));
    inner.add(m.v(innerX(y), y, z));
  }
  final last = prof.length - 1;
  for (var i = 0; i < last; i++) {
    final vertical = i == 0 || i == last - 1;
    m.face([wall[i], wall[i + 1], inner[i + 1], inner[i]], smooth: !vertical);
  }
  m.face(inner, tint: 0.04); // 짐칸 쪽 면
  m.face(wall); // 벽 쪽 (보통 가려짐)
  m.face([wall[0], inner[0], inner[last], wall[last]]); // 바닥
  return m.build();
}

// ── 개구부 프레임 ──

/// 개구부 위쪽 모서리의 둥근 반지름 (m)
double apertureCornerRadius(TrunkSpace s) {
  final ap = s.aperture;
  if (ap == null) return 0;
  final top = math.min(ap.height, s.interiorCeilingAt(s.d - ap.frameDepth));
  return math.max(0.0, math.min(0.08, math.min(top * 0.3, ap.topWidth * 0.2)));
}

/// D필러 트림 2개 + 헤더 + 둥근 모서리 2개. 모두 z ∈ [d − frameDepth, d].
List<FixtureObject> frameFixtures(TrunkSpace s) {
  final ap = s.aperture;
  if (ap == null) return const [];
  final zf = s.d - ap.frameDepth, zb = s.d;
  final ceil = s.interiorCeilingAt(zf);
  final top = math.min(ap.height, ceil);
  double al(double y) => math.max(0.0, (s.w - ap.widthAt(y)) / 2);
  final xl = s.xMinAt(zf - 1e-6, 0), xr = s.xMaxAt(zf - 1e-6, 0);
  final r = apertureCornerRadius(s);
  final out = <FixtureObject>[];
  const seal = -0.7; // 고무 몰딩
  const sealW = 2.0;

  // 기둥: x–y 단면 사다리꼴을 z 로 밀어낸 볼록체
  for (final leftSide in [true, false]) {
    double mx(double x) => leftSide ? x : s.w - x;
    final outer = leftSide ? xl : s.w - xr; // 벽에서의 거리
    if (al(0) <= outer + 1e-6) continue;
    final m = MeshBuilder(Vec3(mx((outer + al(0)) / 2), top / 2, (zf + zb) / 2));
    final sect = [
      [outer, 0.0],
      [al(0), 0.0],
      [al(top), top],
      [outer, top],
    ];
    final f = [for (final p in sect) m.v(mx(p[0]), p[1], zf)];
    final b = [for (final p in sect) m.v(mx(p[0]), p[1], zb)];
    m.face(b,
        deco: (p, n) => [
              DecoLine([
                Vec3(mx(al(0)), 0, zb),
                Vec3(mx(al(top - r)), top - r, zb),
              ], tone: seal, width: sealW),
              // 트림 패널 경계선
              if (al(0) - outer > 0.07)
                DecoLine([
                  Vec3(mx(al(0) - 0.035), 0.02, zb),
                  Vec3(mx(al(top) - 0.035), top - 0.02, zb),
                ], tone: 0.16, width: 1.0),
            ]);
    m.face(f);
    // 개구부 안쪽 면. 바깥면·윗면·밑면은 단면도처럼 생략한다 (벽을 바깥에서 볼 때와 같다)
    m.face([f[1], f[2], b[2], b[1]], tint: 0.10);
    final x1 = leftSide ? xl : s.w - al(0), x2 = leftSide ? al(0) : xr;
    out.add(FixtureObject(
        Aabb(x1, 0, zf, x2, top, zb), m.build(closed: false), frameColor,
        fadeSide: leftSide ? -1 : 1));
  }

  // 헤더
  if (ceil > top + 1e-6) {
    final box = Aabb(xl, top, zf, xr, ceil, zb);
    final m = MeshBuilder(box.center);
    final lo = [
      m.v(xl, top, zf), m.v(xr, top, zf), m.v(xr, top, zb), m.v(xl, top, zb), //
    ];
    final hi = [
      m.v(xl, ceil, zf), m.v(xr, ceil, zf), m.v(xr, ceil, zb), m.v(xl, ceil, zb),
    ];
    // 앞·뒷면과 밑면만 (윗면·옆면은 천장처럼 생략 — 위에서 내려다볼 때 짐을 가리지 않게)
    m.face([lo[0], lo[1], hi[1], hi[0]]);
    m.face([lo[2], lo[3], hi[3], hi[2]],
        deco: (p, n) => [
              DecoLine([
                Vec3(al(top) + r, top, zb),
                Vec3(s.w - al(top) - r, top, zb),
              ], tone: seal, width: sealW),
            ]);
    m.face(lo, tint: -0.1);
    out.add(FixtureObject(box, m.build(closed: false), frameColor));
  }

  // 기둥·모서리 위만 덮는 윗면 조각 (가운데는 열어 둔다). 없으면 위에서 볼 때
  // 헤더 속으로 기둥 안쪽 면이 들여다보인다. 기둥과 같이 흐려지도록 따로 둔다.
  final capY = math.max(ceil, top);
  final capW = al(top) + r - xl;
  if (capW > 0.01) {
    for (final leftSide in [true, false]) {
      double mx(double x) => leftSide ? x : s.w - x;
      final m = MeshBuilder(Vec3(mx(xl + capW / 2), capY - 1, (zf + zb) / 2));
      m.face([
        m.v(mx(xl), capY, zf),
        m.v(mx(xl + capW), capY, zf),
        m.v(mx(xl + capW), capY, zb),
        m.v(mx(xl), capY, zb),
      ], normal: const Vec3(0, 1, 0), tint: -0.05);
      final x1 = leftSide ? xl : s.w - xl - capW;
      out.add(FixtureObject(
          Aabb(x1, capY, zf, x1 + capW, capY + 0.001, zb),
          m.build(closed: false),
          frameColor,
          fadeSide: leftSide ? -1 : 1));
    }
  }

  // 둥근 모서리 (기둥과 헤더 사이를 메우는 조각)
  if (r > 0.005) {
    const seg = 4;
    for (final leftSide in [true, false]) {
      double mx(double x) => leftSide ? x : s.w - x;
      final cx = al(top); // 모서리 점 C 의 x (왼쪽 기준)
      final ox = cx + r, oy = top - r; // 호의 중심
      // 윤곽: C → A(기둥 모서리) → 호(180°→90°) → B
      final outline = <List<double>>[
        [cx, top],
        [al(top - r), top - r],
        for (var i = 0; i <= seg; i++)
          [
            ox + r * math.cos(math.pi - (math.pi / 2) * i / seg),
            oy + r * math.sin(math.pi - (math.pi / 2) * i / seg),
          ],
      ];
      final m = MeshBuilder(Vec3(mx(cx), top, (zf + zb) / 2));
      final f = [for (final p in outline) m.v(mx(p[0]), p[1], zf)];
      final b = [for (final p in outline) m.v(mx(p[0]), p[1], zb)];
      // 호 안쪽 면 (개구부 중심을 향함)
      for (var i = 2; i + 1 < outline.length; i++) {
        final mid = [
          (outline[i][0] + outline[i + 1][0]) / 2,
          (outline[i][1] + outline[i + 1][1]) / 2,
        ];
        var nx = ox - mid[0];
        final ny = oy - mid[1];
        if (!leftSide) nx = -nx;
        m.face([f[i], f[i + 1], b[i + 1], b[i]],
            normal: Vec3(nx, ny, 0).normalized, smooth: true, tint: 0.10);
      }
      m.face(b,
          normal: const Vec3(0, 0, 1),
          smooth: true,
          deco: (p, n) => [
                DecoLine([for (var i = 1; i < b.length; i++) m.verts[b[i]]],
                    tone: seal, width: sealW),
              ]);
      m.face(f, normal: const Vec3(0, 0, -1), smooth: true);
      final x1 = leftSide ? cx : s.w - cx - r;
      out.add(FixtureObject(
          Aabb(x1, top - r, zf, x1 + r, top, zb), m.build(closed: false),
          frameColor,
          outline: false,
          fadeSide: leftSide ? -1 : 1));
    }
  }
  return out;
}

// ── 차 밖: 차체 윤곽·테일램프 (반투명) ──

double bodyOverhang(TrunkSpace s) => s.bodyExtX.clamp(0.06, 0.30).toDouble();

/// 개구부 양옆 차체를 좁은 반투명 띠와 세로형 테일램프로 암시한다. 모두 z > d.
List<FixtureObject> bodyFixtures(TrunkSpace s) {
  final ext = math.min(bodyOverhang(s), 0.15);
  final z = s.d + 0.004, zl = s.d + 0.007;
  final ceil = s.interiorCeilingAt(s.d);
  const sillY = -0.025;
  final rc = ext * 0.7; // 어깨 둥글기
  final out = <FixtureObject>[];

  for (final leftSide in [true, false]) {
    double mx(double x) => leftSide ? x : s.w - x;
    // 옆 패널: 바깥 위 모서리를 둥글게
    final pts = <Vec3>[
      Vec3(mx(0), sillY, z),
      Vec3(mx(0), ceil, z),
      Vec3(mx(-ext + rc), ceil, z),
      for (var i = 1; i <= 3; i++)
        Vec3(
          mx(-ext + rc - rc * math.sin(math.pi / 2 * i / 3)),
          ceil - rc + rc * math.cos(math.pi / 2 * i / 3),
          z,
        ),
      Vec3(mx(-ext), sillY, z),
    ];
    final m = MeshBuilder(Vec3(mx(-ext / 2), ceil / 2, z - 1));
    m.face([for (final p in pts) m.add(p)],
        normal: const Vec3(0, 0, 1),
        deco: (p, n) => [DecoLine(p, tone: 0.5, width: 1.0, closed: true)]);
    // 세로형 테일램프 (차체 쪽에 남는 바깥 절반)
    final lx0 = -ext * 0.30, lx1 = -ext * 0.62;
    final ly0 = ceil * 0.46, ly1 = ceil * 0.80;
    m.face([
      m.v(mx(lx0), ly0, zl),
      m.v(mx(lx1), ly0 + 0.015, zl),
      m.v(mx(lx1), ly1 - 0.03, zl),
      m.v(mx(lx0), ly1, zl),
    ], normal: const Vec3(0, 0, 1), color: lampColor);
    final x1 = leftSide ? -ext : s.w, x2 = leftSide ? 0.0 : s.w + ext;
    out.add(FixtureObject(
        Aabb(x1, sillY, s.d + 0.001, x2, ceil, s.d + 0.01),
        m.build(closed: false),
        bodyGhostColor,
        alpha: 0.20,
        outline: false,
        fadeSide: leftSide ? -1 : 1));
  }
  return out;
}

// ── 2열 등받이·헤드레스트 ──

class HeadrestSpec {
  final double cx; // 중심 x
  final double w, h; // 폭·높이
  final double y0; // 아랫면 높이
  const HeadrestSpec(this.cx, this.w, this.h, this.y0);
}

/// 등받이를 어떻게 그릴지: 쿠션 구획, 헤드레스트 구간.
class SeatLayout {
  /// 쿠션 윗선 = 헤드레스트 구간 시작 높이
  final double topY;

  /// 헤드레스트 구간의 프로필 평면 z (짐이 닿을 수 있는 한계)
  final double planeZ;

  /// 헤드레스트 구간 천장 높이
  final double ceilY;

  /// 평면 뒤로 파 들어가는 깊이 (실내 쪽, 짐이 못 가는 곳)
  final double recess;

  /// 쿠션 구획 [x0, x1]
  final List<List<double>> sections;
  final List<HeadrestSpec> headrests;

  const SeatLayout({
    required this.topY,
    required this.planeZ,
    required this.ceilY,
    required this.recess,
    required this.sections,
    required this.headrests,
  });

  bool get hasHeadrests => headrests.isNotEmpty;
}

/// 분할 시트가 아니면(세단 고정 등받이) null.
SeatLayout? seatLayout(TrunkSpace s) {
  final ratios = s.seatSplitRatio;
  if (ratios == null || ratios.isEmpty) return null;
  final total = ratios.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return null;

  final planeZ = s.frontInsetAt(s.h);
  final ceilY = s.interiorCeilingAt(planeZ);

  // 헤드레스트 구간: 프로필 꼭대기의 수직 구간. 프로필이 없으면 높이의 74% 위.
  double topY;
  final fp = s.frontProfile;
  if (fp != null && fp.points.length >= 2) {
    final pts = fp.points;
    final a = pts[pts.length - 2], b = pts.last;
    topY = (b.inset - a.inset).abs() < 1e-6 ? a.y : ceilY;
  } else {
    topY = math.min(0.60, s.h * 0.74);
  }

  final xl = s.xMinAt(planeZ, 0), xr = s.xMaxAt(planeZ, 0);
  final sections = <List<double>>[];
  var cum = 0.0;
  for (final r in ratios) {
    final x0 = xl + (xr - xl) * cum / total;
    cum += r;
    sections.add([x0, xl + (xr - xl) * cum / total]);
  }

  final zone = ceilY - topY;
  final hh = math.min(0.17, zone - 0.04);
  final headrests = <HeadrestSpec>[];
  if (hh >= 0.06) {
    // 좌석 중심: 6:4 처럼 한쪽이 넓으면 3인승(1/6, 1/2, 5/6), 아니면 구획마다 하나
    final wide = ratios.any((r) => r / total >= 0.55);
    final centers = wide
        ? [1 / 6, 1 / 2, 5 / 6]
        : [for (final sec in sections) ((sec[0] + sec[1]) / 2 - xl) / (xr - xl)];
    final topXl = s.xMinAt(planeZ, ceilY), topXr = s.xMaxAt(planeZ, ceilY);
    for (var i = 0; i < centers.length; i++) {
      final middle = wide && i == 1;
      final hw = math.min(middle ? 0.20 : 0.25, (xr - xl) / centers.length * 0.7);
      var cx = xl + (xr - xl) * centers[i];
      // 천장 쪽이 좁아지는 차는 벽 안으로
      cx = cx.clamp(topXl + hw / 2 + 0.01, topXr - hw / 2 - 0.01).toDouble();
      headrests.add(HeadrestSpec(
          cx, hw, middle ? hh * 0.85 : hh, topY + math.min(0.035, zone - hh)));
    }
  }
  return SeatLayout(
    topY: headrests.isEmpty ? ceilY : topY,
    planeZ: planeZ,
    ceilY: ceilY,
    recess: headrests.isEmpty ? 0 : 0.09,
    sections: sections,
    headrests: headrests,
  );
}

/// 헤드레스트: x–y 에서 모서리를 깎은 덩어리. 짐칸 쪽 면이 정확히 프로필 평면(z = planeZ).
List<Mesh> headrestMeshes(SeatLayout seat) {
  final out = <Mesh>[];
  for (final hr in seat.headrests) {
    final x1 = hr.cx - hr.w / 2, x2 = hr.cx + hr.w / 2;
    final y1 = hr.y0, y2 = hr.y0 + hr.h;
    final zb = seat.planeZ, zf = seat.planeZ - seat.recess * 0.8;
    final c = math.min(hr.w, hr.h) * 0.22;
    final outline = [
      [x1 + c, y1], [x2 - c, y1], [x2, y1 + c], [x2, y2 - c], //
      [x2 - c, y2], [x1 + c, y2], [x1, y2 - c], [x1, y1 + c],
    ];
    final m = MeshBuilder(Vec3(hr.cx, (y1 + y2) / 2, (zf + zb) / 2));
    final f = [for (final p in outline) m.v(p[0], p[1], zf)];
    final b = [for (final p in outline) m.v(p[0], p[1], zb)];
    for (var i = 0; i < 8; i++) {
      final j = (i + 1) % 8;
      m.face([f[i], f[j], b[j], b[i]], smooth: true);
    }
    m.face(b, tint: 0.05, deco: (p, n) {
      // 가운데 박음질
      final y = (y1 + y2) / 2;
      return [
        DecoLine([Vec3(x1 + c * 0.6, y, zb), Vec3(x2 - c * 0.6, y, zb)],
            tone: -0.4, width: 1.0),
      ];
    });
    m.face(f);
    out.add(m.build());
  }
  return out;
}
