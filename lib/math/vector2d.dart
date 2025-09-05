import 'dart:math' as math;

/// 2D 벡터 클래스
/// 2차원 평면에서의 점, 방향, 위치를 표현
class Vector2D {
  final double x;
  final double y;

  const Vector2D(this.x, this.y);

  /// 원점
  static const Vector2D zero = Vector2D(0, 0);
  
  /// 단위 벡터들
  static const Vector2D unitX = Vector2D(1, 0);
  static const Vector2D unitY = Vector2D(0, 1);

  /// 벡터 덧셈
  Vector2D operator +(Vector2D other) {
    return Vector2D(x + other.x, y + other.y);
  }

  /// 벡터 뺄셈
  Vector2D operator -(Vector2D other) {
    return Vector2D(x - other.x, y - other.y);
  }

  /// 스칼라 곱셈
  Vector2D operator *(double scalar) {
    return Vector2D(x * scalar, y * scalar);
  }

  /// 스칼라 나눗셈
  Vector2D operator /(double scalar) {
    return Vector2D(x / scalar, y / scalar);
  }

  /// 벡터의 크기
  double get magnitude => math.sqrt(x * x + y * y);

  /// 벡터의 크기의 제곱 (성능 최적화용)
  double get magnitudeSquared => x * x + y * y;

  /// 단위 벡터로 정규화
  Vector2D get normalized {
    final mag = magnitude;
    if (mag == 0) return Vector2D.zero;
    return Vector2D(x / mag, y / mag);
  }

  /// 내적 (Dot Product)
  double dot(Vector2D other) {
    return x * other.x + y * other.y;
  }

  /// 외적의 크기 (2D에서는 스칼라값)
  double cross(Vector2D other) {
    return x * other.y - y * other.x;
  }

  /// 두 벡터 사이의 거리
  double distanceTo(Vector2D other) {
    return (this - other).magnitude;
  }

  /// 두 벡터 사이의 거리의 제곱 (성능 최적화용)
  double distanceSquaredTo(Vector2D other) {
    return (this - other).magnitudeSquared;
  }

  /// 선형 보간 (Linear Interpolation)
  Vector2D lerp(Vector2D target, double t) {
    return Vector2D(
      x + (target.x - x) * t,
      y + (target.y - y) * t,
    );
  }

  /// 벡터 회전 (원점 기준)
  Vector2D rotate(double angleRadians) {
    final cos = math.cos(angleRadians);
    final sin = math.sin(angleRadians);
    
    return Vector2D(
      x * cos - y * sin,
      x * sin + y * cos,
    );
  }

  /// 벡터의 각도 (라디안)
  double get angle => math.atan2(y, x);

  /// 벡터를 각도로 생성 (단위 벡터)
  static Vector2D fromAngle(double angleRadians) {
    return Vector2D(math.cos(angleRadians), math.sin(angleRadians));
  }

  /// 두 점 사이의 각도
  double angleTo(Vector2D other) {
    return math.atan2(cross(other), dot(other));
  }

  /// 벡터 반사 (법선 벡터를 기준으로)
  Vector2D reflect(Vector2D normal) {
    return this - normal * (2 * dot(normal));
  }

  /// 벡터를 다른 벡터 위에 투영
  Vector2D project(Vector2D onto) {
    final dotProduct = dot(onto);
    final ontoMagnitudeSquared = onto.magnitudeSquared;
    
    if (ontoMagnitudeSquared == 0) return Vector2D.zero;
    
    return onto * (dotProduct / ontoMagnitudeSquared);
  }

  /// 벡터의 수직 벡터 (시계방향 90도 회전)
  Vector2D get perpendicular => Vector2D(-y, x);

  /// 벡터를 정수 좌표로 반올림
  Vector2D get rounded => Vector2D(x.roundToDouble(), y.roundToDouble());

  /// 벡터를 정수 좌표로 버림
  Vector2D get floor => Vector2D(x.floorToDouble(), y.floorToDouble());

  /// 벡터를 정수 좌표로 올림
  Vector2D get ceil => Vector2D(x.ceilToDouble(), y.ceilToDouble());

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vector2D &&
        x == other.x &&
        y == other.y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vector2D($x, $y)';
}