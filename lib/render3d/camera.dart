import 'dart:math' as math;
import 'dart:ui';

import '../models/trunk_space.dart';
import 'vec3.dart';

/// 화면에 투영된 점: 픽셀 위치 + 카메라 기준 깊이(m)
class ProjectedPoint {
  final Offset screen;
  final double depth;

  const ProjectedPoint(this.screen, this.depth);
}

/// 타깃을 중심으로 공전하는 원근 카메라 (불변 값 객체).
///
/// yaw = 0 이면 카메라가 +z 쪽(테일게이트 뒤)에서 트렁크 안을 바라본다.
/// yaw > 0 이면 카메라가 +x(오른쪽)으로 돌아간다. pitch > 0 이면 위에서 내려다본다.
class OrbitCamera {
  final Vec3 target;
  final double yaw; // 라디안
  final double pitch; // 라디안
  final double distance; // m
  final double fovY; // 라디안 (수직 시야각)
  final Offset pan; // 화면 픽셀 오프셋

  const OrbitCamera({
    required this.target,
    required this.yaw,
    required this.pitch,
    required this.distance,
    this.fovY = defaultFovY,
    this.pan = Offset.zero,
  });

  static const double defaultFovY = 42 * math.pi / 180;
  static const double minPitch = 3 * math.pi / 180;
  static const double maxPitch = 75 * math.pi / 180;
  static const double maxYawAbs = 85 * math.pi / 180;
  static const double nearPlane = 0.02;

  /// 카메라 위치 (월드)
  Vec3 get position => target +
      Vec3(
        math.sin(yaw) * math.cos(pitch),
        math.sin(pitch),
        math.cos(yaw) * math.cos(pitch),
      ) *
          distance;

  Vec3 get forward => (target - position).normalized;

  Vec3 get right {
    final f = forward;
    final r = f.cross(Vec3.unitY);
    // 정면으로 바로 내려다보는 극단적 경우 방어
    if (r.length < 1e-6) return const Vec3(1, 0, 0);
    return r.normalized;
  }

  Vec3 get up => right.cross(forward).normalized;

  /// 초점 거리(픽셀): 수직 시야각을 화면 높이에 맞춘다.
  double focalPx(Size size) => (size.height / 2) / math.tan(fovY / 2);

  Offset _center(Size size) =>
      Offset(size.width / 2 + pan.dx, size.height / 2 + pan.dy);

  /// 월드 → 화면. 카메라 뒤(near plane 앞)면 null.
  ProjectedPoint? project(Vec3 p, Size size) {
    final v = p - position;
    final f = forward;
    final zc = v.dot(f);
    if (zc < nearPlane) return null;
    final xc = v.dot(right);
    final yc = v.dot(up);
    final fp = focalPx(size);
    final c = _center(size);
    return ProjectedPoint(
      Offset(c.dx + xc / zc * fp, c.dy - yc / zc * fp),
      zc,
    );
  }

  /// 화면 픽셀 → 월드 반직선
  Ray ray(Offset screen, Size size) {
    final fp = focalPx(size);
    final c = _center(size);
    final nx = (screen.dx - c.dx) / fp;
    final ny = -(screen.dy - c.dy) / fp;
    final dir = (right * nx + up * ny + forward).normalized;
    return Ray(position, dir);
  }

  OrbitCamera copyWith({
    Vec3? target,
    double? yaw,
    double? pitch,
    double? distance,
    double? fovY,
    Offset? pan,
  }) =>
      OrbitCamera(
        target: target ?? this.target,
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        distance: distance ?? this.distance,
        fovY: fovY ?? this.fovY,
        pan: pan ?? this.pan,
      );

  /// 각도·거리 제한을 적용한 사본.
  ///
  /// [keepOutside] 를 주면 카메라가 그 트렁크 상자 안으로 들어가지 않게 최소 거리를
  /// 올린다. 가로로 긴 캔버스(844×300 등)는 맞춤 거리가 짧아서, 최대로 확대하면
  /// (맞춤 거리 × 0.45) 카메라가 트렁크 안에 들어가 면이 near plane 에 잘린다.
  OrbitCamera clamped({
    required double minDistance,
    required double maxDistance,
    TrunkSpace? keepOutside,
  }) {
    final y = _finiteOr(yaw, 0).clamp(-maxYawAbs, maxYawAbs).toDouble();
    final p = _finiteOr(pitch, minPitch).clamp(minPitch, maxPitch).toDouble();
    var dist = _finiteOr(distance, maxDistance)
        .clamp(minDistance, math.max(minDistance, maxDistance))
        .toDouble();
    if (keepOutside != null) {
      final out = copyWith(yaw: y, pitch: p)._exitDistance(keepOutside);
      dist = math.max(dist, out + outsideMargin);
    }
    return copyWith(yaw: y, pitch: p, distance: dist);
  }

  /// [clamped] 의 keepOutside 여유 (m)
  static const double outsideMargin = 0.10;

  static double _finiteOr(double v, double fallback) => v.isFinite ? v : fallback;

  /// 타깃에서 카메라 방향으로 나아가 트렁크 상자 [0,w]×[0,h]×[0,d] 를 벗어나는 거리.
  /// 타깃이 상자 밖이면 0.
  double _exitDistance(TrunkSpace s) {
    final dir = Vec3(
      math.sin(yaw) * math.cos(pitch),
      math.sin(pitch),
      math.cos(yaw) * math.cos(pitch),
    );
    final lo = [0.0, 0.0, 0.0], hi = [s.w, s.h, s.d];
    var t = double.infinity;
    for (var axis = 0; axis < 3; axis++) {
      final o = target[axis], d = dir[axis];
      if (o < lo[axis] || o > hi[axis]) return 0;
      if (d.abs() < 1e-12) continue;
      final exit = d > 0 ? (hi[axis] - o) / d : (lo[axis] - o) / d;
      if (exit < t) t = exit;
    }
    return t.isFinite ? t : 0;
  }

  /// 트렁크 전체가 화면의 [margin] 비율 안에 들어오는 거리로 맞춘 카메라.
  /// 원근 투영은 거리에 정확히 비례하지 않으므로 몇 번 반복해 수렴시킨다.
  static OrbitCamera fitTrunk(
    TrunkSpace space,
    Size size, {
    double yaw = 0.0,
    double pitch = 22 * math.pi / 180,
    double margin = 0.88,
  }) {
    final target = Vec3(space.w / 2, space.h * 0.42, space.d / 2);
    final corners = [
      for (final x in [0.0, space.w])
        for (final y in [0.0, space.h])
          for (final z in [0.0, space.d]) Vec3(x, y, z),
    ];
    var cam = OrbitCamera(
      target: target,
      yaw: yaw,
      pitch: pitch,
      distance: Vec3(space.w, space.h, space.d).length * 1.5,
    );
    if (size.width <= 0 || size.height <= 0) return cam;

    // 화면 여백 기준으로 가장 많이 벗어난 꼭짓점의 비율 (1 = 딱 맞음, 2 = 카메라 뒤)
    double overflow(OrbitCamera c) {
      double maxNorm = 0;
      final ctr = c._center(size);
      for (final p in corners) {
        final pp = c.project(p, size);
        if (pp == null) return 2;
        final nx = (pp.screen.dx - ctr.dx).abs() / (size.width / 2 * margin);
        final ny = (pp.screen.dy - ctr.dy).abs() / (size.height / 2 * margin);
        maxNorm = math.max(maxNorm, math.max(nx, ny));
      }
      return maxNorm;
    }

    // 고정점 반복. 가까운 꼭짓점은 거리에 비례하지 않게 움직이므로(원근) 가로로 긴
    // 캔버스·극단 각도에서는 몇 번 더 돌아야 수렴한다.
    for (var i = 0; i < 24; i++) {
      final m = overflow(cam);
      if (m <= 0) break;
      cam = cam.copyWith(distance: cam.distance * m);
      if ((m - 1).abs() < 0.002) break;
    }
    // 보증: 아직 넘치면 들어올 때까지 물러난다
    for (var i = 0; i < 60 && overflow(cam) > 1.0; i++) {
      cam = cam.copyWith(distance: cam.distance * 1.03);
    }
    return cam;
  }

  @override
  bool operator ==(Object other) =>
      other is OrbitCamera &&
      other.target == target &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.distance == distance &&
      other.fovY == fovY &&
      other.pan == pan;

  @override
  int get hashCode => Object.hash(target, yaw, pitch, distance, fovY, pan);
}
