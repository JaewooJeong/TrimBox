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

  /// 각도·거리 제한을 적용한 사본
  OrbitCamera clamped({required double minDistance, required double maxDistance}) =>
      copyWith(
        yaw: yaw.clamp(-maxYawAbs, maxYawAbs),
        pitch: pitch.clamp(minPitch, maxPitch),
        distance: distance.clamp(minDistance, maxDistance),
      );

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

    for (var i = 0; i < 5; i++) {
      double maxNorm = 0;
      final c = cam._center(size);
      for (final p in corners) {
        final pp = cam.project(p, size);
        if (pp == null) {
          maxNorm = 2;
          break;
        }
        final nx = (pp.screen.dx - c.dx).abs() / (size.width / 2 * margin);
        final ny = (pp.screen.dy - c.dy).abs() / (size.height / 2 * margin);
        maxNorm = math.max(maxNorm, math.max(nx, ny));
      }
      if (maxNorm <= 0) break;
      cam = cam.copyWith(distance: cam.distance * maxNorm);
      if ((maxNorm - 1).abs() < 0.01) break;
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
