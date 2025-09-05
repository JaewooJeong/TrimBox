import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../math/vector2d.dart';
import '../math/vector3d.dart';
import '../math/isometric_transform.dart';
import 'isometric_object.dart';

/// 기본적인 아이소메트릭 박스/큐브 객체
class IsometricBox extends IsometricObject {
  /// 측면 색상 (기본 색상보다 어둡게)
  Color? sideColor;
  
  /// 윗면 색상 (기본 색상보다 밝게)  
  Color? topColor;
  
  /// 테두리 색상
  Color? borderColor;
  
  /// 테두리 두께
  double borderWidth;

  IsometricBox({
    required super.id,
    super.position,
    super.dimensions,
    super.rotation,
    super.color,
    super.shadowColor,
    super.opacity,
    super.visible,
    this.sideColor,
    this.topColor,
    this.borderColor,
    this.borderWidth = 1.0,
  }) {
    // 자동으로 면별 색상 계산
    sideColor ??= Color.lerp(color, Colors.black, 0.3) ?? Colors.grey.shade700;
    topColor ??= Color.lerp(color, Colors.white, 0.2) ?? Colors.grey.shade300;
    borderColor ??= Colors.black54;
  }

  @override
  void render(Canvas canvas, IsometricTransform transform) {
    if (!visible || opacity <= 0) return;
    
    // 박스의 8개 꼭짓점을 2D로 변환
    final vertices3d = getVertices();
    final vertices2d = vertices3d.map(transform.to2D).toList();
    
    // 면들을 그리기 (뒤에서 앞으로, 화가 알고리즘)
    _drawFaces(canvas, vertices2d);
    
    // 테두리 그리기
    if (borderWidth > 0 && borderColor != null) {
      _drawEdges(canvas, vertices2d);
    }
  }

  /// 박스의 면들을 그리기
  void _drawFaces(Canvas canvas, List<Vector2D> vertices2d) {
    final paint = Paint()..style = PaintingStyle.fill;
    
    // 좌측면 (더 어두운 색)
    paint.color = sideColor!.withOpacity(opacity);
    final leftFace = Path()
      ..moveTo(vertices2d[0].x, vertices2d[0].y) // 0: 좌전하
      ..lineTo(vertices2d[3].x, vertices2d[3].y) // 3: 좌후하
      ..lineTo(vertices2d[7].x, vertices2d[7].y) // 7: 좌후상
      ..lineTo(vertices2d[4].x, vertices2d[4].y) // 4: 좌전상
      ..close();
    canvas.drawPath(leftFace, paint);

    // 우측면 (중간 명도)
    paint.color = Color.lerp(color, sideColor!, 0.5)!.withOpacity(opacity);
    final rightFace = Path()
      ..moveTo(vertices2d[1].x, vertices2d[1].y) // 1: 우전하
      ..lineTo(vertices2d[5].x, vertices2d[5].y) // 5: 우전상
      ..lineTo(vertices2d[6].x, vertices2d[6].y) // 6: 우후상
      ..lineTo(vertices2d[2].x, vertices2d[2].y) // 2: 우후하
      ..close();
    canvas.drawPath(rightFace, paint);

    // 윗면 (가장 밝은 색)
    paint.color = topColor!.withOpacity(opacity);
    final topFace = Path()
      ..moveTo(vertices2d[4].x, vertices2d[4].y) // 4: 좌전상
      ..lineTo(vertices2d[7].x, vertices2d[7].y) // 7: 좌후상
      ..lineTo(vertices2d[6].x, vertices2d[6].y) // 6: 우후상
      ..lineTo(vertices2d[5].x, vertices2d[5].y) // 5: 우전상
      ..close();
    canvas.drawPath(topFace, paint);
  }

  /// 박스의 테두리 그리기
  void _drawEdges(Canvas canvas, List<Vector2D> vertices2d) {
    final paint = Paint()
      ..color = borderColor!.withOpacity(opacity)
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    // 보이는 모서리들만 그리기
    final edges = [
      // 앞면 모서리들
      [0, 1], [1, 5], [5, 4], [4, 0], // 앞면 사각형
      
      // 뒷면으로 가는 모서리들  
      [0, 3], [1, 2], [4, 7], [5, 6],
      
      // 뒷면 보이는 모서리들
      [3, 7], [7, 6], [6, 2],
    ];

    for (final edge in edges) {
      final start = vertices2d[edge[0]];
      final end = vertices2d[edge[1]];
      
      canvas.drawLine(
        Offset(start.x, start.y),
        Offset(end.x, end.y),
        paint,
      );
    }
  }

  @override
  IsometricBox clone() {
    return IsometricBox(
      id: '${id}_clone',
      position: position,
      dimensions: dimensions,
      rotation: rotation,
      color: color,
      shadowColor: shadowColor,
      opacity: opacity,
      visible: visible,
      sideColor: sideColor,
      topColor: topColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
    );
  }

  /// 박스를 새로운 색상으로 변경
  IsometricBox withColor(Color newColor) {
    return IsometricBox(
      id: id,
      position: position,
      dimensions: dimensions,
      rotation: rotation,
      color: newColor,
      shadowColor: shadowColor,
      opacity: opacity,
      visible: visible,
      borderColor: borderColor,
      borderWidth: borderWidth,
    );
  }

  /// 박스를 새로운 크기로 변경
  IsometricBox withDimensions(Vector3D newDimensions) {
    return IsometricBox(
      id: id,
      position: position,
      dimensions: newDimensions,
      rotation: rotation,
      color: color,
      shadowColor: shadowColor,
      opacity: opacity,
      visible: visible,
      sideColor: sideColor,
      topColor: topColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
    );
  }

  /// 박스에 그라디언트 효과 적용
  void applyGradient({
    required Color lightColor,
    required Color darkColor,
  }) {
    topColor = lightColor;
    color = Color.lerp(lightColor, darkColor, 0.5)!;
    sideColor = darkColor;
  }

  /// 박스의 재질감 설정
  void setMaterial({
    double roughness = 0.5,
    double metallic = 0.0,
  }) {
    final brightness = 1.0 - roughness * 0.5;
    final saturation = 1.0 - metallic * 0.3;
    
    final hsl = HSLColor.fromColor(color);
    final adjustedColor = hsl
        .withLightness((hsl.lightness * brightness).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * saturation).clamp(0.0, 1.0))
        .toColor();
    
    color = adjustedColor;
    topColor = Color.lerp(adjustedColor, Colors.white, 0.2);
    sideColor = Color.lerp(adjustedColor, Colors.black, 0.3);
  }

  @override
  String getDebugInfo() {
    return 'IsometricBox($id): pos=$position, size=$dimensions, color=$color';
  }
}