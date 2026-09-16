import 'dart:math' as math;

/// 불변 3D 벡터 (미터 단위 월드 좌표).
///
/// 월드 좌표계: x = 트렁크 폭(0..w, 테일게이트에서 봤을 때 왼쪽→오른쪽),
/// y = 높이(0 = 바닥), z = 깊이(0 = 뒷좌석 등받이, d = 테일게이트 개구부).
class Vec3 {
  final double x;
  final double y;
  final double z;

  const Vec3(this.x, this.y, this.z);

  static const Vec3 zero = Vec3(0, 0, 0);
  static const Vec3 unitY = Vec3(0, 1, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator -() => Vec3(-x, -y, -z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final len = length;
    if (len < 1e-12) return Vec3.zero;
    return Vec3(x / len, y / len, z / len);
  }

  /// 축 인덱스로 성분 접근 (0=x, 1=y, 2=z)
  double operator [](int axis) => switch (axis) {
        0 => x,
        1 => y,
        _ => z,
      };

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// 반직선: origin + dir * t (dir는 단위 벡터)
class Ray {
  final Vec3 origin;
  final Vec3 dir;

  const Ray(this.origin, this.dir);

  Vec3 at(double t) => origin + dir * t;
}
