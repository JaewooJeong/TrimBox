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
enum ShellPart { floor, ceiling, leftWall, rightWall, seatBack }

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
List<ShellFace> buildTrunkShell(TrunkSpace s, {int stations = 8}) {
  final n = math.max(2, stations);
  final zs = List<double>.generate(n + 1, (i) => s.d * i / n);
  final interior = Vec3(s.w / 2, s.h / 2, s.d / 2);

  double xl(double z) => s.taperAt(z);
  double xr(double z) => s.w - s.taperAt(z);
  double xtl(double z) => s.taperAt(z) + s.topNarrowAt(z);
  double xtr(double z) => s.w - s.taperAt(z) - s.topNarrowAt(z);
  double ceil(double z) => s.ceilingHeightAt(z);

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
  // 뒷좌석 등받이 (z = 0)
  faces.add(make([
    Vec3(xl(0), 0, 0),
    Vec3(xr(0), 0, 0),
    Vec3(xtr(0), ceil(0), 0),
    Vec3(xtl(0), ceil(0), 0),
  ], ShellPart.seatBack));
  return faces;
}

/// 바닥 외곽선 (z 오름차순 왼쪽 → z 내림차순 오른쪽)
List<Vec3> floorOutline(TrunkSpace s, {int stations = 8}) {
  final n = math.max(2, stations);
  final left = <Vec3>[];
  final right = <Vec3>[];
  for (var i = 0; i <= n; i++) {
    final z = s.d * i / n;
    left.add(Vec3(s.taperAt(z), 0, z));
    right.add(Vec3(s.w - s.taperAt(z), 0, z));
  }
  return [...left, ...right.reversed];
}

/// 테일게이트 개구부 외곽선 (z = d)
List<Vec3> openingOutline(TrunkSpace s) {
  final z = s.d;
  final t = s.taperAt(z);
  final nrw = s.topNarrowAt(z);
  final c = s.ceilingHeightAt(z);
  return [
    Vec3(t, 0, z),
    Vec3(s.w - t, 0, z),
    Vec3(s.w - t - nrw, c, z),
    Vec3(t + nrw, c, z),
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
