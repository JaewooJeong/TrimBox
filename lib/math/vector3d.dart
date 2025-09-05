import 'dart:math' as math;

/// 3D 벡터 클래스
/// 3차원 공간에서의 점, 방향, 위치를 표현
class Vector3D {
  final double x;
  final double y;
  final double z;

  const Vector3D(this.x, this.y, this.z);

  /// 원점
  static const Vector3D zero = Vector3D(0, 0, 0);
  
  /// 단위 벡터들
  static const Vector3D unitX = Vector3D(1, 0, 0);
  static const Vector3D unitY = Vector3D(0, 1, 0);
  static const Vector3D unitZ = Vector3D(0, 0, 1);

  /// 벡터 덧셈
  Vector3D operator +(Vector3D other) {
    return Vector3D(x + other.x, y + other.y, z + other.z);
  }

  /// 벡터 뺄셈
  Vector3D operator -(Vector3D other) {
    return Vector3D(x - other.x, y - other.y, z - other.z);
  }

  /// 스칼라 곱셈
  Vector3D operator *(double scalar) {
    return Vector3D(x * scalar, y * scalar, z * scalar);
  }

  /// 스칼라 나눗셈
  Vector3D operator /(double scalar) {
    return Vector3D(x / scalar, y / scalar, z / scalar);
  }

  /// 벡터의 크기
  double get magnitude => sqrt(x * x + y * y + z * z);

  /// 단위 벡터로 정규화
  Vector3D get normalized {
    final mag = magnitude;
    if (mag == 0) return Vector3D.zero;
    return Vector3D(x / mag, y / mag, z / mag);
  }

  /// 내적 (Dot Product)
  double dot(Vector3D other) {
    return x * other.x + y * other.y + z * other.z;
  }

  /// 외적 (Cross Product)
  Vector3D cross(Vector3D other) {
    return Vector3D(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x,
    );
  }

  /// 두 벡터 사이의 거리
  double distanceTo(Vector3D other) {
    return (this - other).magnitude;
  }

  /// 선형 보간 (Linear Interpolation)
  Vector3D lerp(Vector3D target, double t) {
    return Vector3D(
      x + (target.x - x) * t,
      y + (target.y - y) * t,
      z + (target.z - z) * t,
    );
  }

  /// 벡터 회전 (Y축 기준)
  Vector3D rotateY(double angleRadians) {
    final cos = cosine(angleRadians);
    final sin = sine(angleRadians);
    
    return Vector3D(
      x * cos + z * sin,
      y,
      -x * sin + z * cos,
    );
  }

  /// 벡터 회전 (X축 기준)
  Vector3D rotateX(double angleRadians) {
    final cos = cosine(angleRadians);
    final sin = sine(angleRadians);
    
    return Vector3D(
      x,
      y * cos - z * sin,
      y * sin + z * cos,
    );
  }

  /// 벡터 회전 (Z축 기준)
  Vector3D rotateZ(double angleRadians) {
    final cos = cosine(angleRadians);
    final sin = sine(angleRadians);
    
    return Vector3D(
      x * cos - y * sin,
      x * sin + y * cos,
      z,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Vector3D &&
        x == other.x &&
        y == other.y &&
        z == other.z;
  }

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vector3D($x, $y, $z)';
}

/// 수학 헬퍼 함수들
double sqrt(double value) => math.sqrt(value);
double cosine(double radians) => math.cos(radians);
double sine(double radians) => math.sin(radians);
double tan(double radians) => math.tan(radians);
double atan2(double y, double x) => math.atan2(y, x);

