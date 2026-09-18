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
        b.top,
        b.z + b.effectiveD,
      );

  /// 왼쪽 휠하우스: x=[0, w], z=[zStart, zEnd]
  factory Aabb.leftWheelhouse(TrunkSpace s) => Aabb(0, 0, s.leftWheelhouse.zStart,
      s.leftWheelhouse.w, s.leftWheelhouse.h, s.leftWheelhouse.zEnd);

  /// 오른쪽 휠하우스: x=[W-w, W], z=[zStart, zEnd]
  factory Aabb.rightWheelhouse(TrunkSpace s) => Aabb(
      s.w - s.rightWheelhouse.w,
      0,
      s.rightWheelhouse.zStart,
      s.w,
      s.rightWheelhouse.h,
      s.rightWheelhouse.zEnd);

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
enum ShellPart {
  floor,
  ceiling,
  leftWall,
  rightWall,
  seatBack,

  /// 헤드레스트 구간 뒤로 파인 곳 (실내 쪽 — 짐이 못 가는 어두운 공간)
  seatRecess,
  frame,
  tailgate,
}

class ShellFace {
  final Face face;
  final ShellPart part;

  /// 등받이 프로필 평면 뒤(실내 쪽)의 장식 면 — 짐칸의 경계가 아니다.
  /// 헤드레스트 구간의 실제 적재 한계는 `seatLimitFace` 다.
  final bool behindSeatPlane;

  const ShellFace(this.face, this.part, {this.behindSeatPlane = false});
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
/// 옆벽은 [TrunkSpace.xMinAt] 과 같은 꺾임(천장 높이의 60% 위에서 안쪽으로
/// 기욺)을 그대로 따른다 — 벽에 붙인 짐이 그림의 벽을 뚫고 보이지 않게.
///
/// 테일게이트 모델이 있으면 천장·벽은 뒤쪽 경계가 내려오기 시작하는
/// z(= d − rearInsetAt(h)) 까지만 만들고, 그 뒤는 프로필을 따라 마감한다.
/// 개구부 프레임(D필러·헤더)은 `fixtures.dart`, 닫힌 테일게이트 면은
/// [tailgateFaces] 로 따로 만든다.
///
/// [headrestZoneY], [headrestRecess] 를 주면 등받이의 그 높이 위 구간을 평면으로
/// 막지 않고 [headrestRecess] 만큼 실내 쪽으로 파인 공간으로 만든다 (헤드레스트가
/// 들어갈 자리). 파인 곳은 프로필 평면 뒤라서 짐이 닿을 수 있는 공간이 아니다.
List<ShellFace> buildTrunkShell(
  TrunkSpace s, {
  int stations = 8,
  double? headrestZoneY,
  double headrestRecess = 0,
}) {
  final n = math.max(2, stations);
  final zStart = s.frontInsetAt(s.h);
  final zEnd = s.hasTailgateModel ? s.rearDepthAt(s.h) : s.d;
  final zs = List<double>.generate(
      n + 1, (i) => zStart + (zEnd - zStart) * i / n);
  final interior = Vec3(s.w / 2, s.h / 2, s.d / 2);
  // 프레임 구간의 개구부 좁아짐은 벽이 아니라 기둥(고정물)이 그린다
  final zWallMax = s.aperture == null
      ? s.d
      : s.d - s.aperture!.frameDepth - 1e-6;

  double xl(double z) => s.xMinAt(z, 0);
  double xr(double z) => s.xMaxAt(z, 0);
  double ceil(double z) => s.interiorCeilingAt(z);
  double xtl(double z) => s.xMinAt(z, ceil(z));
  double xtr(double z) => s.xMaxAt(z, ceil(z));
  double knee(double z) => ceil(z) * 0.6;
  double xkl(double z) => s.xMinAt(z, knee(z));
  double xkr(double z) => s.xMaxAt(z, knee(z));
  final hasKnee = s.rearTopNarrow + s.ceilingNarrow > 0.001;

  ShellFace make(List<Vec3> pts, ShellPart part, {bool behind = false}) {
    var normal = newellPolygonNormal(pts);
    // 내부를 향하도록 보정
    final c = Face(pts, normal).centroid;
    if (normal.dot(interior - c) < 0) normal = -normal;
    return ShellFace(Face(pts, normal), part, behindSeatPlane: behind);
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
    if (hasKnee) {
      // 벽 아래쪽(수직) + 위쪽(안으로 기욺)
      faces.add(make([
        Vec3(xl(z0), 0, z0),
        Vec3(xl(z1), 0, z1),
        Vec3(xkl(z1), knee(z1), z1),
        Vec3(xkl(z0), knee(z0), z0),
      ], ShellPart.leftWall));
      faces.add(make([
        Vec3(xkl(z0), knee(z0), z0),
        Vec3(xkl(z1), knee(z1), z1),
        Vec3(xtl(z1), ceil(z1), z1),
        Vec3(xtl(z0), ceil(z0), z0),
      ], ShellPart.leftWall));
      faces.add(make([
        Vec3(xr(z0), 0, z0),
        Vec3(xr(z1), 0, z1),
        Vec3(xkr(z1), knee(z1), z1),
        Vec3(xkr(z0), knee(z0), z0),
      ], ShellPart.rightWall));
      faces.add(make([
        Vec3(xkr(z0), knee(z0), z0),
        Vec3(xkr(z1), knee(z1), z1),
        Vec3(xtr(z1), ceil(z1), z1),
        Vec3(xtr(z0), ceil(z0), z0),
      ], ShellPart.rightWall));
    } else {
      faces.add(make([
        Vec3(xl(z0), 0, z0),
        Vec3(xl(z1), 0, z1),
        Vec3(xtl(z1), ceil(z1), z1),
        Vec3(xtl(z0), ceil(z0), z0),
      ], ShellPart.leftWall));
      faces.add(make([
        Vec3(xr(z0), 0, z0),
        Vec3(xr(z1), 0, z1),
        Vec3(xtr(z1), ceil(z1), z1),
        Vec3(xtr(z0), ceil(z0), z0),
      ], ShellPart.rightWall));
    }
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
    // 벽: zStart 단면과 등받이 프로필 사이. 꺾임이 있으면 아래(수직)·위(기욺)로 나눈다 —
    // 한 장의 비평면 다각형으로 그리면 면이 물리 벽보다 안쪽으로 들어온다.
    final yk = _kneeOnProfile(s, s.frontInsetAt);
    for (final left in [true, false]) {
      double wx(double z, double y) => left ? s.xMinAt(z, y) : s.xMaxAt(z, y);
      final part = left ? ShellPart.leftWall : ShellPart.rightWall;
      Vec3 at(Vec3 p) => Vec3(wx(p.z, p.y), p.y, p.z);
      if (hasKnee && yk != null) {
        faces.add(make([
          Vec3(wx(zStart, 0), 0, zStart),
          Vec3(wx(zStart, knee(zStart)), knee(zStart), zStart),
          for (final p in front.reversed)
            if (p.y <= yk + 1e-9) at(p),
        ], part));
        faces.add(make([
          Vec3(wx(zStart, knee(zStart)), knee(zStart), zStart),
          Vec3(wx(zStart, ceil(zStart)), ceil(zStart), zStart),
          for (final p in front.reversed)
            if (p.y >= yk - 1e-9) at(p),
        ], part));
      } else {
        faces.add(make([
          Vec3(wx(zStart, 0), 0, zStart),
          Vec3(wx(zStart, ceil(zStart)), ceil(zStart), zStart),
          for (final p in front.reversed) at(p),
        ], part));
      }
    }
  }
  final recessed = headrestZoneY != null && headrestRecess > 1e-6;
  for (var i = 0; i + 1 < front.length; i++) {
    final a = front[i], b = front[i + 1];
    if ((b.y - a.y).abs() < 1e-9) continue;
    if (recessed && a.y >= headrestZoneY - 1e-6) continue; // 아래에서 파인 공간으로
    faces.add(make([
      Vec3(s.xMinAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(a.z, a.y), a.y, a.z),
      Vec3(s.xMaxAt(b.z, b.y), b.y, b.z),
      Vec3(s.xMinAt(b.z, b.y), b.y, b.z),
    ], ShellPart.seatBack));
  }
  if (recessed) {
    final y0 = headrestZoneY, y1 = ceil(zStart);
    final zp = zStart, zr = zStart - headrestRecess;
    final l0 = s.xMinAt(zp, y0), l1 = s.xMinAt(zp, y1);
    final r0 = s.xMaxAt(zp, y0), r1 = s.xMaxAt(zp, y1);
    // 안쪽 벽(어두운 실내), 등받이 윗면, 양옆, 천장
    faces.add(make([
      Vec3(l0, y0, zr), Vec3(r0, y0, zr), Vec3(r1, y1, zr), Vec3(l1, y1, zr), //
    ], ShellPart.seatRecess, behind: true));
    faces.add(make([
      Vec3(l0, y0, zr), Vec3(r0, y0, zr), Vec3(r0, y0, zp), Vec3(l0, y0, zp), //
    ], ShellPart.seatBack, behind: true));
    faces.add(make([
      Vec3(l0, y0, zr), Vec3(l0, y0, zp), Vec3(l1, y1, zp), Vec3(l1, y1, zr), //
    ], ShellPart.leftWall, behind: true));
    faces.add(make([
      Vec3(r0, y0, zr), Vec3(r0, y0, zp), Vec3(r1, y1, zp), Vec3(r1, y1, zr), //
    ], ShellPart.rightWall, behind: true));
    faces.add(make([
      Vec3(l1, y1, zr), Vec3(r1, y1, zr), Vec3(r1, y1, zp), Vec3(l1, y1, zp), //
    ], ShellPart.ceiling, behind: true));
  }

  // 뒤쪽 마감: 바닥은 테일게이트 바닥선(z = d)까지, 벽은 프로필을 따라
  if (zEnd < s.d - 1e-6) {
    faces.add(make([
      Vec3(xl(zEnd), 0, zEnd),
      Vec3(xr(zEnd), 0, zEnd),
      Vec3(xr(zWallMax), 0, s.d),
      Vec3(xl(zWallMax), 0, s.d),
    ], ShellPart.floor));
    final prof = rearProfilePolyline(s);
    final yk = _kneeOnProfile(s, s.rearDepthAt);
    for (final left in [true, false]) {
      // 프레임 구간에서도 벽은 벽 평면에 둔다 (좁아짐은 기둥이 그린다). 천장 위로는 안 올라간다.
      double wx(double z, double y) => left
          ? s.xMinAt(math.min(z, zWallMax), y)
          : s.xMaxAt(math.min(z, zWallMax), y);
      final part = left ? ShellPart.leftWall : ShellPart.rightWall;
      Vec3 at(Vec3 p) {
        final y = math.min(p.y, ceil(p.z));
        return Vec3(wx(p.z, y), y, p.z);
      }

      if (hasKnee && yk != null) {
        faces.add(make([
          Vec3(wx(zEnd, 0), 0, zEnd),
          for (final p in prof)
            if (p.y <= yk + 1e-9) at(p),
          Vec3(wx(zEnd, knee(zEnd)), knee(zEnd), zEnd),
        ], part));
        faces.add(make([
          Vec3(wx(zEnd, knee(zEnd)), knee(zEnd), zEnd),
          for (final p in prof)
            if (p.y >= yk - 1e-9) at(p),
          Vec3(wx(zEnd, ceil(zEnd)), ceil(zEnd), zEnd),
        ], part));
      } else {
        faces.add(make([
          Vec3(wx(zEnd, 0), 0, zEnd),
          for (final p in prof) at(p),
          Vec3(wx(zEnd, ceil(zEnd)), ceil(zEnd), zEnd),
        ], part));
      }
    }
  }
  return faces;
}

/// Newell 방법의 다각형 법선 (오목·약간 비평면 다각형에도 안정적)
Vec3 newellPolygonNormal(List<Vec3> p) {
  var nx = 0.0, ny = 0.0, nz = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    nx += (a.y - b.y) * (a.z + b.z);
    ny += (a.z - b.z) * (a.x + b.x);
    nz += (a.x - b.x) * (a.y + b.y);
  }
  return Vec3(nx, ny, nz).normalized;
}

/// 벽이 안쪽으로 꺾이는 높이(천장 높이의 60%)가 프로필 위에서 어디인지.
/// 꺾임 높이는 z 에 따라(천장 높이에 따라) 달라지므로 고정점 반복으로 구한다.
/// 벽이 꺾이지 않는 차는 null.
double? _kneeOnProfile(TrunkSpace s, double Function(double y) zAt) {
  if (s.rearTopNarrow + s.ceilingNarrow <= 0.001) return null;
  var y = s.h * 0.6;
  for (var i = 0; i < 4; i++) {
    y = s.interiorCeilingAt(zAt(y)) * 0.6;
  }
  return y;
}

/// 2열 등받이 프로필을 (z, y) 점열로 — 바닥 (0, 0) 에서 천장까지 y 오름차순.
/// [withKnee]: 옆벽이 꺾이는 높이에도 점을 둔다 (벽·등받이 면이 `xMinAt` 을 따르도록).
List<Vec3> frontProfilePolyline(TrunkSpace s, {bool withKnee = true}) {
  final top = s.interiorCeilingAt(s.frontInsetAt(s.h));
  final ys = <double>{0.0, top};
  final fp = s.frontProfile;
  if (fp != null) {
    for (final p in fp.points) {
      if (p.y > 0 && p.y < s.h) ys.add(p.y);
    }
  }
  if (withKnee) {
    final k = _kneeOnProfile(s, s.frontInsetAt);
    if (k != null && k > 0 && k < top) ys.add(k);
  }
  final sorted = ys.toList()..sort();
  return [for (final y in sorted) Vec3(0, y, s.frontInsetAt(y))];
}

/// 뒤쪽 경계 프로필을 (z, y) 점열로 — 바닥 (d, 0) 에서 천장까지 y 오름차순.
/// 개구부 상단에서 헤더로 꺾이는 점과 옆벽이 꺾이는 높이의 점을 포함한다.
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
  final k = _kneeOnProfile(s, s.rearDepthAt);
  if (k != null && k > 0 && k < s.h) ys.add(k);
  final sorted = ys.toList()..sort();
  return [for (final y in sorted) Vec3(0, y, s.rearDepthAt(y))];
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
  // 프레임 구간의 개구부 좁아짐은 바닥이 아니라 기둥이 차지한다
  final zWallMax =
      s.aperture == null ? s.d : s.d - s.aperture!.frameDepth - 1e-6;
  for (var i = 0; i <= n; i++) {
    final z = s.d * i / n;
    final zx = math.min(z, zWallMax);
    left.add(Vec3(s.xMinAt(zx, 0), 0, z));
    right.add(Vec3(s.xMaxAt(zx, 0), 0, z));
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
