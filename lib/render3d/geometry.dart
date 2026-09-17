import 'dart:math' as math;
import 'dart:ui';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import 'vec3.dart';

/// 축 정렬 경계 상자 (월드 좌표, m)
class Aabb {
  final double x1, y1, z1; // min
  final double x2, y2, z2; // max

  const Aabb(this.x1, this.y1, this.z1, this.x2, this.y2, this.z2);

  factory Aabb.fromBox(TrimBox b) => Aabb(
        b.x,
        b.y,
        b.z,
        b.x + b.effectiveW,
        b.y + b.h,
        b.z + b.effectiveD,
      );

  /// 왼쪽 휠하우스: x=[0, w], z=[0, d]
  factory Aabb.leftWheelhouse(TrunkSpace s) => Aabb(
      0, 0, 0, s.leftWheelhouse.w, s.leftWheelhouse.h, s.leftWheelhouse.d);

  /// 오른쪽 휠하우스: x=[W-w, W], z=[0, d]
  factory Aabb.rightWheelhouse(TrunkSpace s) => Aabb(
      s.w - s.rightWheelhouse.w,
      0,
      0,
      s.w,
      s.rightWheelhouse.h,
      s.rightWheelhouse.d);

  Vec3 get min => Vec3(x1, y1, z1);
  Vec3 get max => Vec3(x2, y2, z2);
  Vec3 get center => Vec3((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2);
  double get w => x2 - x1;
  double get h => y2 - y1;
  double get d => z2 - z1;
  bool get isEmpty => w <= 0 || h <= 0 || d <= 0;

  double minOn(int axis) => axis == 0 ? x1 : (axis == 1 ? y1 : z1);
  double maxOn(int axis) => axis == 0 ? x2 : (axis == 1 ? y2 : z2);

  bool overlaps(Aabb o, {double eps = 1e-6}) =>
      x1 < o.x2 - eps &&
      x2 > o.x1 + eps &&
      y1 < o.y2 - eps &&
      y2 > o.y1 + eps &&
      z1 < o.z2 - eps &&
      z2 > o.z1 + eps;

  /// 8개 꼭짓점
  List<Vec3> get corners => [
        for (final x in [x1, x2])
          for (final y in [y1, y2])
            for (final z in [z1, z2]) Vec3(x, y, z),
      ];

  @override
  String toString() =>
      'Aabb([$x1,$y1,$z1]-[$x2,$y2,$z2])';
}

/// 평면 다각형 면. [normal]은 면이 보이는 쪽(카메라 쪽)을 가리키는 단위 벡터.
class Face {
  final List<Vec3> pts;
  final Vec3 normal;

  const Face(this.pts, this.normal);

  Vec3 get centroid {
    var sx = 0.0, sy = 0.0, sz = 0.0;
    for (final p in pts) {
      sx += p.x;
      sy += p.y;
      sz += p.z;
    }
    final n = pts.length.toDouble();
    return Vec3(sx / n, sy / n, sz / n);
  }

  /// 카메라 위치에서 이 면의 앞면이 보이는가
  bool facesCamera(Vec3 camPos) => normal.dot(camPos - centroid) > 0;
}

/// 트렁크 껍데기의 부위
enum ShellPart { floor, ceiling, leftWall, rightWall, seatBack, frame, tailgate }

class ShellFace {
  final Face face;
  final ShellPart part;

  const ShellFace(this.face, this.part);
}

/// 세 점으로 정의된 다각형의 법선 (오른손 좌표계, 반시계 순서 기준)
Vec3 polygonNormal(List<Vec3> pts) {
  final a = pts[1] - pts[0];
  final b = pts[2] - pts[0];
  return a.cross(b).normalized;
}

/// 트렁크 내부 형상을 z 방향 [stations]개 구간으로 나눈 면 목록.
///
/// 모든 법선은 트렁크 안쪽(내부 중심)을 향한다. 카메라가 트렁크 밖에서
/// 볼 때 카메라를 향하는 면 = 먼 쪽 벽이므로, 법선 컬링만으로
/// "열린 상자" 뷰가 만들어진다.
///
/// 테일게이트 모델이 있으면 천장·벽은 뒤쪽 경계가 내려오기 시작하는
/// z(= d − rearInsetAt(h)) 까지만 만들고, 그 뒤는 프로필을 따라 마감한다.
/// 개구부 프레임(D필러·헤더)은 [frameFaces], 닫힌 테일게이트 면은
/// [tailgateFaces] 로 따로 만든다.
List<ShellFace> buildTrunkShell(TrunkSpace s, {int stations = 8}) {
  final n = math.max(2, stations);
  final zStart = s.frontInsetAt(s.h);
  final zEnd = s.hasTailgateModel ? s.rearDepthAt(s.h) : s.d;
  final zs = List<double>.generate(
      n + 1, (i) => zStart + (zEnd - zStart) * i / n);
  final interior = Vec3(s.w / 2, s.h / 2, s.d / 2);

  double xl(double z) => s.xMinAt(z, 0);
  double xr(double z) => s.xMaxAt(z, 0);
  double ceil(double z) => s.interiorCeilingAt(z);
  double xtl(double z) => s.xMinAt(z, ceil(z));
  double xtr(double z) => s.xMaxAt(z, ceil(z));

  ShellFace make(List<Vec3> pts, ShellPart part) {
    var normal = polygonNormal(pts);
    // 내부를 향하도록 보정
    final c = Face(pts, normal).centroid;
    if (normal.dot(interior - c) < 0) normal = -normal;
    return ShellFace(Face(pts, normal), part);
  }

  final faces = <ShellFace>[];
  for (var i = 0; i < n; i++) {
    final z0 = zs[i], z1 = zs[i + 1];
    // 바닥
    faces.add(make([
      Vec3(xl(z0), 0, z0),
      Vec3(xr(z0), 0, z0),
      Vec3(xr(z1), 0, z1),
      Vec3(xl(z1), 0, z1),
    ], ShellPart.floor));
    // 천장
    faces.add(make([
      Vec3(xtl(z0), ceil(z0), z0),
      Vec3(xtr(z0), ceil(z0), z0),
      Vec3(xtr(z1), ceil(z1), z1),
      Vec3(xtl(z1), ceil(z1), z1),
    ], ShellPart.ceiling));
    // 왼쪽 벽
    faces.add(make([
      Vec3(xl(z0), 0, z0),
      Vec3(xl(z1), 0, z1),
      Vec3(xtl(z1), ceil(z1), z1),
      Vec3(xtl(z0), ceil(z0), z0),
    ], ShellPart.leftWall));
    // 오른쪽 벽
    faces.add(make([
      Vec3(xr(z0), 0, z0),
      Vec3(xr(z1), 0, z1),
      Vec3(xtr(z1), ceil(z1), z1),
      Vec3(xtr(z0), ceil(z0), z0),
    ], ShellPart.rightWall));
  }

  // 앞쪽 마감: 뒷좌석 등받이 (기울기가 있으면 프로필을 따라 여러 면)
  final front = frontProfilePolyline(s);
  if (zStart > 1e-6) {
    faces.add(make([
      Vec3(xl(0), 0, 0),
      Vec3(xr(0), 0, 0),
      Vec3(xr(zStart), 0, zStart),
      Vec3(xl(zStart), 0, zStart),
    ], ShellPart.floor));
    // 벽: 바닥 zStart → 천장 zStart → 프로필을 따라 내려와 바닥 0
    faces.add(make([
      Vec3(xl(zStart), 0, zStart),
      Vec3(xtl(zStart), ceil(zStart), zStart),
      for (final p in front.reversed) Vec3(s.xMinAt(p.z, p.y), p.y, p.z),
    ], ShellPart.leftWall));
    faces.add(make([
      Vec3(xr(zStart), 0, zStart),
      Vec3(xtr(zStart), ceil(zStart), zStart),
      for (final p in front.reversed) Vec3(s.xMaxAt(p.z, p.y), p.y, p.z),
    ], ShellPart.rightWall));
  }
  for (var i = 0; i + 1 < front.length; i++) {
    final a = front[i], b = front[i + 1];
    if ((b.y - a.y).abs() < 1e-9) continue;
    faces.add(make([
      Vec3(s.xMinAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(b.z, b.y), b.y, b.z),
      Vec3(s.xMinAt(b.z, b.y), b.y, b.z),
    ], ShellPart.seatBack));
  }

  // 뒤쪽 마감: 바닥은 테일게이트 바닥선(z = d)까지, 벽은 프로필을 따라
  if (zEnd < s.d - 1e-6) {
    faces.add(make([
      Vec3(xl(zEnd), 0, zEnd),
      Vec3(xr(zEnd), 0, zEnd),
      Vec3(xr(s.d), 0, s.d),
      Vec3(xl(s.d), 0, s.d),
    ], ShellPart.floor));
    final prof = rearProfilePolyline(s);
    // 왼쪽 벽: 바닥 zEnd → 바닥 d → 프로필 위로 → 천장 zEnd
    faces.add(make([
      Vec3(xl(zEnd), 0, zEnd),
      for (final p in prof) Vec3(s.xMinAt(p.z, p.y), p.y, p.z),
      Vec3(xtl(zEnd), ceil(zEnd), zEnd),
    ], ShellPart.leftWall));
    faces.add(make([
      Vec3(xr(zEnd), 0, zEnd),
      for (final p in prof) Vec3(s.xMaxAt(p.z, p.y), p.y, p.z),
      Vec3(xtr(zEnd), ceil(zEnd), zEnd),
    ], ShellPart.rightWall));
  }
  return faces;
}

/// 2열 등받이 프로필을 (z, y) 점열로 — 바닥 (0, 0) 에서 천장까지 y 오름차순.
List<Vec3> frontProfilePolyline(TrunkSpace s) {
  final ys = <double>{0.0, s.interiorCeilingAt(s.frontInsetAt(s.h))};
  final fp = s.frontProfile;
  if (fp != null) {
    for (final p in fp.points) {
      if (p.y > 0 && p.y < s.h) ys.add(p.y);
    }
  }
  final sorted = ys.toList()..sort();
  return [for (final y in sorted) Vec3(0, y, s.frontInsetAt(y))];
}

/// 뒤쪽 경계 프로필을 (z, y) 점열로 — 바닥 (d, 0) 에서 천장까지 y 오름차순.
/// 개구부 상단에서 헤더로 꺾이는 점을 포함한다.
List<Vec3> rearProfilePolyline(TrunkSpace s) {
  final ys = <double>{0.0, s.h};
  final rp = s.rearProfile;
  if (rp != null) {
    for (final p in rp.points) {
      if (p.y > 0 && p.y < s.h) ys.add(p.y);
    }
  }
  final ap = s.aperture;
  if (ap != null && ap.height > 0 && ap.height < s.h) {
    ys.add(ap.height - 1e-6);
    ys.add(ap.height);
  }
  final sorted = ys.toList()..sort();
  return [for (final y in sorted) Vec3(0, y, s.rearDepthAt(y))];
}

/// 개구부 프레임(D필러 트림 + 헤더)의 면. z = d − frameDepth .. d 구간을
/// 채우는 고체로 보고, 카메라 쪽(뒤)에서 보이는 뒷면과 개구부 안쪽 면을 만든다.
/// 법선은 바깥(카메라)쪽/개구부 중심쪽을 향한다.
List<ShellFace> frameFaces(TrunkSpace s) {
  final ap = s.aperture;
  if (ap == null) return const [];
  final zf = s.d - ap.frameDepth;
  final zb = s.d;
  final top = math.min(ap.height, s.interiorCeilingAt(zf));
  final ceil = s.interiorCeilingAt(zf);
  double al(double y) => (s.w - ap.widthAt(y)) / 2;
  double ar(double y) => s.w - al(y);
  final xl = s.xMinAt(zf - 1e-6, 0), xr = s.xMaxAt(zf - 1e-6, 0);
  final out = <ShellFace>[];
  // 뒷면 (z = d) — 왼쪽 기둥, 오른쪽 기둥, 헤더
  out.add(ShellFace(
      Face([
        Vec3(xl, 0, zb),
        Vec3(al(0), 0, zb),
        Vec3(al(top), top, zb),
        Vec3(xl, top, zb),
      ], const Vec3(0, 0, 1)),
      ShellPart.frame));
  out.add(ShellFace(
      Face([
        Vec3(ar(0), 0, zb),
        Vec3(xr, 0, zb),
        Vec3(xr, top, zb),
        Vec3(ar(top), top, zb),
      ], const Vec3(0, 0, 1)),
      ShellPart.frame));
  if (ceil > top + 1e-6) {
    out.add(ShellFace(
        Face([
          Vec3(xl, top, zb),
          Vec3(xr, top, zb),
          Vec3(xr, ceil, zb),
          Vec3(xl, ceil, zb),
        ], const Vec3(0, 0, 1)),
        ShellPart.frame));
    // 헤더 아랫면 (y = top)
    out.add(ShellFace(
        Face([
          Vec3(al(top), top, zf),
          Vec3(ar(top), top, zf),
          Vec3(ar(top), top, zb),
          Vec3(al(top), top, zb),
        ], const Vec3(0, -1, 0)),
        ShellPart.frame));
  }
  // 기둥 안쪽 면 (개구부 중심을 향함)
  out.add(ShellFace(
      Face([
        Vec3(al(0), 0, zf),
        Vec3(al(0), 0, zb),
        Vec3(al(top), top, zb),
        Vec3(al(top), top, zf),
      ], const Vec3(1, 0, 0)),
      ShellPart.frame));
  out.add(ShellFace(
      Face([
        Vec3(ar(0), 0, zf),
        Vec3(ar(top), top, zf),
        Vec3(ar(top), top, zb),
        Vec3(ar(0), 0, zb),
      ], const Vec3(-1, 0, 0)),
      ShellPart.frame));
  return out;
}

/// 닫힌 테일게이트 안쪽 면 (프로필을 폭 방향으로 늘린 띠). 법선은 안쪽(−z).
List<Face> tailgateFaces(TrunkSpace s) {
  if (!s.hasTailgateModel) return const [];
  final prof = rearProfilePolyline(s);
  final out = <Face>[];
  for (var i = 0; i + 1 < prof.length; i++) {
    final a = prof[i], b = prof[i + 1];
    if ((b.y - a.y).abs() < 1e-9) continue;
    final pts = [
      Vec3(s.xMinAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(b.z, b.y), b.y, b.z),
      Vec3(s.xMinAt(b.z, b.y), b.y, b.z),
    ];
    var normal = polygonNormal(pts);
    if (normal.z > 0) normal = -normal;
    out.add(Face(pts, normal));
  }
  return out;
}

/// 바닥 외곽선 (z 오름차순 왼쪽 → z 내림차순 오른쪽)
List<Vec3> floorOutline(TrunkSpace s, {int stations = 8}) {
  final n = math.max(2, stations);
  final left = <Vec3>[];
  final right = <Vec3>[];
  for (var i = 0; i <= n; i++) {
    final z = s.d * i / n;
    left.add(Vec3(s.xMinAt(z, 0), 0, z));
    right.add(Vec3(s.xMaxAt(z, 0), 0, z));
  }
  return [...left, ...right.reversed];
}

/// 테일게이트 개구부 외곽선 (z = d). 개구부 모델이 있으면 그 사다리꼴.
List<Vec3> openingOutline(TrunkSpace s) {
  final z = s.d;
  final ap = s.aperture;
  if (ap != null) {
    final top = math.min(ap.height, s.interiorCeilingAt(z));
    final al = (s.w - ap.widthAt(0)) / 2;
    final at = (s.w - ap.widthAt(top)) / 2;
    return [
      Vec3(al, 0, z),
      Vec3(s.w - al, 0, z),
      Vec3(s.w - at, top, z),
      Vec3(at, top, z),
    ];
  }
  final c = s.ceilingHeightAt(z);
  return [
    Vec3(s.xMinAt(z, 0), 0, z),
    Vec3(s.xMaxAt(z, 0), 0, z),
    Vec3(s.xMaxAt(z, c), c, z),
    Vec3(s.xMinAt(z, c), c, z),
  ];
}

/// AABB의 6면 (법선은 바깥쪽)
List<Face> aabbFaces(Aabb b) {
  final x1 = b.x1, y1 = b.y1, z1 = b.z1, x2 = b.x2, y2 = b.y2, z2 = b.z2;
  return [
    // -x (왼쪽)
    Face([Vec3(x1, y1, z1), Vec3(x1, y1, z2), Vec3(x1, y2, z2), Vec3(x1, y2, z1)],
        const Vec3(-1, 0, 0)),
    // +x (오른쪽)
    Face([Vec3(x2, y1, z1), Vec3(x2, y2, z1), Vec3(x2, y2, z2), Vec3(x2, y1, z2)],
        const Vec3(1, 0, 0)),
    // -y (바닥면)
    Face([Vec3(x1, y1, z1), Vec3(x2, y1, z1), Vec3(x2, y1, z2), Vec3(x1, y1, z2)],
        const Vec3(0, -1, 0)),
    // +y (윗면)
    Face([Vec3(x1, y2, z1), Vec3(x1, y2, z2), Vec3(x2, y2, z2), Vec3(x2, y2, z1)],
        const Vec3(0, 1, 0)),
    // -z (뒷좌석 쪽)
    Face([Vec3(x1, y1, z1), Vec3(x1, y2, z1), Vec3(x2, y2, z1), Vec3(x2, y1, z1)],
        const Vec3(0, 0, -1)),
    // +z (테일게이트 쪽)
    Face([Vec3(x1, y1, z2), Vec3(x2, y1, z2), Vec3(x2, y2, z2), Vec3(x1, y2, z2)],
        const Vec3(0, 0, 1)),
  ];
}

// ── 조명 ──

/// 고정 광원 방향 (위, 약간 테일게이트 쪽·오른쪽에서)
final Vec3 lightDir = const Vec3(0.35, 1.0, 0.55).normalized;

/// 램버트 음영. [ambient] + [diffuse] * max(0, n·L)
Color shadeColor(Color base, Vec3 normal,
    {double ambient = 0.52, double diffuse = 0.48}) {
  final k = ambient + diffuse * math.max(0.0, normal.dot(lightDir));
  return Color.fromARGB(
    (base.a * 255).round(),
    (base.r * 255 * k).round().clamp(0, 255),
    (base.g * 255 * k).round().clamp(0, 255),
    (base.b * 255 * k).round().clamp(0, 255),
  );
}
