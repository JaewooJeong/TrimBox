import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../math/vector2d.dart';
import '../math/vector3d.dart';
import '../math/isometric_transform.dart';

/// 아이소메트릭 공간에서 렌더링 가능한 모든 객체의 기본 클래스
abstract class IsometricObject {
  /// 3D 공간에서의 위치
  Vector3D position;
  
  /// 객체의 크기 (폭, 높이, 깊이)
  Vector3D dimensions;
  
  /// 객체의 회전 (라디안, Y축 기준)
  double rotation;
  
  /// 기본 색상
  Color color;
  
  /// 그림자 색상
  Color? shadowColor;
  
  /// 객체의 불투명도 (0.0 - 1.0)
  double opacity;
  
  /// 객체가 렌더링될지 여부
  bool visible;
  
  /// 객체의 고유 식별자
  final String id;

  IsometricObject({
    required this.id,
    this.position = Vector3D.zero,
    this.dimensions = const Vector3D(1, 1, 1),
    this.rotation = 0.0,
    this.color = Colors.grey,
    this.shadowColor,
    this.opacity = 1.0,
    this.visible = true,
  }) {
    shadowColor ??= color.withOpacity(0.3);
  }

  /// 객체를 캔버스에 렌더링
  void render(Canvas canvas, IsometricTransform transform);

  /// 객체의 3D 경계 박스 반환
  IsometricBounds getBounds(IsometricTransform transform) {
    final min = position;
    final max = position + dimensions;
    return transform.transform3DBounds(min, max);
  }

  /// 객체의 모든 3D 꼭짓점 반환
  List<Vector3D> getVertices() {
    final pos = position;
    final size = dimensions;
    
    return [
      // 하단 면 (y = position.y)
      Vector3D(pos.x, pos.y, pos.z),              // 0: 좌전
      Vector3D(pos.x + size.x, pos.y, pos.z),     // 1: 우전
      Vector3D(pos.x + size.x, pos.y, pos.z + size.z), // 2: 우후
      Vector3D(pos.x, pos.y, pos.z + size.z),     // 3: 좌후
      
      // 상단 면 (y = position.y + dimensions.y)
      Vector3D(pos.x, pos.y + size.y, pos.z),     // 4: 좌전
      Vector3D(pos.x + size.x, pos.y + size.y, pos.z),     // 5: 우전
      Vector3D(pos.x + size.x, pos.y + size.y, pos.z + size.z), // 6: 우후
      Vector3D(pos.x, pos.y + size.y, pos.z + size.z),     // 7: 좌후
    ];
  }

  /// 2D 점이 이 객체와 교차하는지 확인 (클릭 감지용)
  bool hitTest(Vector2D point, IsometricTransform transform) {
    final bounds = getBounds(transform);
    return bounds.contains(point);
  }

  /// 객체를 이동
  void moveTo(Vector3D newPosition) {
    position = newPosition;
  }

  /// 객체를 회전
  void rotateTo(double newRotation) {
    rotation = newRotation;
  }

  /// 객체를 복제
  IsometricObject clone();

  /// 객체의 렌더링 우선순위 (작을수록 먼저 렌더링)
  /// 일반적으로 Z 좌표가 클수록 (뒤쪽일수록) 먼저 렌더링
  int get renderPriority {
    // Z-order: 뒤쪽 객체부터 렌더링 (화가 알고리즘)
    return (position.z * 1000).round();
  }

  /// 객체의 중심점
  Vector3D get center => position + (dimensions * 0.5);

  /// 객체의 볼륨
  double get volume => dimensions.x * dimensions.y * dimensions.z;

  /// 객체가 다른 객체와 겹치는지 확인
  bool intersects(IsometricObject other) {
    final myMin = position;
    final myMax = position + dimensions;
    final otherMin = other.position;
    final otherMax = other.position + other.dimensions;

    return myMin.x < otherMax.x &&
           myMax.x > otherMin.x &&
           myMin.y < otherMax.y &&
           myMax.y > otherMin.y &&
           myMin.z < otherMax.z &&
           myMax.z > otherMin.z;
  }

  /// 디버그 정보 출력
  String getDebugInfo() {
    return 'IsometricObject($id): pos=$position, size=$dimensions, rot=${rotation.toStringAsFixed(2)}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IsometricObject && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'IsometricObject($id)';
}

/// 렌더링 가능한 면을 나타내는 클래스
class IsometricFace {
  final List<Vector3D> vertices;
  final Color color;
  final Vector3D normal;

  const IsometricFace({
    required this.vertices,
    required this.color,
    required this.normal,
  });

  /// 면의 중심점
  Vector3D get center {
    var sum = Vector3D.zero;
    for (final vertex in vertices) {
      sum = sum + vertex;
    }
    return sum / vertices.length.toDouble();
  }

  /// 면의 평균 Z 좌표 (깊이 정렬용)
  double get averageZ {
    return vertices.map((v) => v.z).reduce((a, b) => a + b) / vertices.length;
  }
}

/// 렌더링용 메시 데이터
class IsometricMesh {
  final List<IsometricFace> faces;
  final List<Vector3D> vertices;

  const IsometricMesh({
    required this.faces,
    required this.vertices,
  });

  /// 메시를 변환하여 새로운 메시 생성
  IsometricMesh transform(Vector3D offset, double rotation) {
    // 회전 변환 (Y축 기준)
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    
    final transformedVertices = vertices.map((v) {
      final rotated = Vector3D(
        v.x * cos - v.z * sin,
        v.y,
        v.x * sin + v.z * cos,
      );
      return rotated + offset;
    }).toList();

    final transformedFaces = faces.map((face) {
      final transformedFaceVertices = face.vertices.map((v) {
        final rotated = Vector3D(
          v.x * cos - v.z * sin,
          v.y,
          v.x * sin + v.z * cos,
        );
        return rotated + offset;
      }).toList();
      
      return IsometricFace(
        vertices: transformedFaceVertices,
        color: face.color,
        normal: face.normal,
      );
    }).toList();

    return IsometricMesh(
      faces: transformedFaces,
      vertices: transformedVertices,
    );
  }
}