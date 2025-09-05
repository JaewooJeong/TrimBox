import 'dart:math' as math;
import 'vector2d.dart';
import 'vector3d.dart';

/// 아이소메트릭 변환을 위한 핵심 클래스
/// 3D 좌표를 2D 아이소메트릭 투영으로 변환하고 역변환을 수행
class IsometricTransform {
  /// 아이소메트릭 표준 각도 (30도)
  static const double standardAngle = math.pi / 6; // 30도 in radians
  
  /// 아이소메트릭 표준 각도의 코사인값 (√3/2)
  static const double cosStandardAngle = 0.8660254037844387;
  
  /// 아이소메트릭 표준 각도의 사인값 (1/2)
  static const double sinStandardAngle = 0.5;

  /// 스케일 팩터
  final double scale;
  
  /// 카메라 각도 (기본값: 아이소메트릭 표준)
  final double cameraAngleX;
  final double cameraAngleY;
  
  /// 오프셋 (화면 중심점 이동)
  final Vector2D offset;

  const IsometricTransform({
    this.scale = 1.0,
    this.cameraAngleX = standardAngle,
    this.cameraAngleY = standardAngle,
    this.offset = Vector2D.zero,
  });

  /// 표준 아이소메트릭 변환
  factory IsometricTransform.standard({
    double scale = 1.0,
    Vector2D offset = Vector2D.zero,
  }) {
    return IsometricTransform(
      scale: scale,
      offset: offset,
    );
  }

  /// 3D 점을 2D 아이소메트릭 좌표로 변환
  /// 
  /// 변환 공식:
  /// x_iso = (x - z) * cos(30°) * scale + offset.x
  /// y_iso = (x + z) * sin(30°) - y * scale + offset.y
  Vector2D to2D(Vector3D point3d) {
    final x = point3d.x;
    final y = point3d.y;
    final z = point3d.z;

    // 아이소메트릭 변환 적용
    final isoX = (x - z) * cosStandardAngle * scale + offset.x;
    final isoY = (x + z) * sinStandardAngle - y * scale + offset.y;

    return Vector2D(isoX, isoY);
  }

  /// 2D 아이소메트릭 좌표를 3D 점으로 역변환
  /// 
  /// 주의: Y축 높이 정보는 별도로 제공되어야 함
  Vector3D to3D(Vector2D point2d, {double height = 0.0}) {
    final adjustedX = (point2d.x - offset.x) / scale;
    final adjustedY = (point2d.y - offset.y + height * scale) / scale;

    // 역변환 공식 적용
    final x = (adjustedX / cosStandardAngle + adjustedY / sinStandardAngle) / 2;
    final z = (adjustedY / sinStandardAngle - adjustedX / cosStandardAngle) / 2;
    
    return Vector3D(x, height, z);
  }

  /// 3D 벡터를 2D 벡터로 변환 (위치가 아닌 방향/크기)
  Vector2D transformDirection(Vector3D direction) {
    final x = direction.x;
    final y = direction.y;
    final z = direction.z;

    final isoX = (x - z) * cosStandardAngle * scale;
    final isoY = (x + z) * sinStandardAngle - y * scale;

    return Vector2D(isoX, isoY);
  }

  /// 3D 경계 박스를 2D로 변환
  IsometricBounds transform3DBounds(Vector3D min, Vector3D max) {
    // 3D 박스의 8개 꼭짓점을 계산
    final vertices = [
      Vector3D(min.x, min.y, min.z),
      Vector3D(max.x, min.y, min.z),
      Vector3D(min.x, max.y, min.z),
      Vector3D(max.x, max.y, min.z),
      Vector3D(min.x, min.y, max.z),
      Vector3D(max.x, min.y, max.z),
      Vector3D(min.x, max.y, max.z),
      Vector3D(max.x, max.y, max.z),
    ];

    // 모든 꼭짓점을 2D로 변환
    final transformed2D = vertices.map(to2D).toList();

    // 2D 경계 계산
    double minX = transformed2D.first.x;
    double maxX = transformed2D.first.x;
    double minY = transformed2D.first.y;
    double maxY = transformed2D.first.y;

    for (final point in transformed2D) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }

    return IsometricBounds(
      min: Vector2D(minX, minY),
      max: Vector2D(maxX, maxY),
    );
  }

  /// 거리 스케일 계산 (3D 거리 → 2D 거리)
  double transformDistance(double distance3d) {
    return distance3d * scale;
  }

  /// 각도 변환 (3D 각도 → 2D 각도)
  double transformAngle(double angle3d) {
    // 간단한 근사치 (정확한 각도 변환은 더 복잡함)
    return angle3d;
  }

  /// 변환 매트릭스 생성 (고급 사용자용)
  List<List<double>> get transformMatrix {
    return [
      [cosStandardAngle * scale, 0, -cosStandardAngle * scale, offset.x],
      [sinStandardAngle * scale, -scale, sinStandardAngle * scale, offset.y],
      [0, 0, 0, 1],
    ];
  }

  /// 새로운 스케일로 변환 생성
  IsometricTransform withScale(double newScale) {
    return IsometricTransform(
      scale: newScale,
      cameraAngleX: cameraAngleX,
      cameraAngleY: cameraAngleY,
      offset: offset,
    );
  }

  /// 새로운 오프셋으로 변환 생성
  IsometricTransform withOffset(Vector2D newOffset) {
    return IsometricTransform(
      scale: scale,
      cameraAngleX: cameraAngleX,
      cameraAngleY: cameraAngleY,
      offset: newOffset,
    );
  }

  /// 변환 결합 (다른 변환과 합성)
  IsometricTransform combine(IsometricTransform other) {
    return IsometricTransform(
      scale: scale * other.scale,
      cameraAngleX: cameraAngleX + other.cameraAngleX,
      cameraAngleY: cameraAngleY + other.cameraAngleY,
      offset: offset + other.offset,
    );
  }

  @override
  String toString() {
    return 'IsometricTransform(scale: $scale, offset: $offset)';
  }
}

/// 2D 아이소메트릭 공간에서의 경계 박스
class IsometricBounds {
  final Vector2D min;
  final Vector2D max;

  const IsometricBounds({
    required this.min,
    required this.max,
  });

  /// 경계의 너비
  double get width => max.x - min.x;

  /// 경계의 높이
  double get height => max.y - min.y;

  /// 경계의 중심점
  Vector2D get center => Vector2D(
    (min.x + max.x) / 2,
    (min.y + max.y) / 2,
  );

  /// 경계의 크기
  Vector2D get size => Vector2D(width, height);

  /// 점이 경계 내부에 있는지 확인
  bool contains(Vector2D point) {
    return point.x >= min.x &&
           point.x <= max.x &&
           point.y >= min.y &&
           point.y <= max.y;
  }

  /// 다른 경계와 겹치는지 확인
  bool intersects(IsometricBounds other) {
    return min.x <= other.max.x &&
           max.x >= other.min.x &&
           min.y <= other.max.y &&
           max.y >= other.min.y;
  }

  /// 경계 확장
  IsometricBounds expand(double amount) {
    return IsometricBounds(
      min: Vector2D(min.x - amount, min.y - amount),
      max: Vector2D(max.x + amount, max.y + amount),
    );
  }

  @override
  String toString() {
    return 'IsometricBounds(min: $min, max: $max)';
  }
}