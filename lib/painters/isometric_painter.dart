import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../models/trunk_space.dart';
import '../models/trim_box.dart';

// Extension renderers
part 'trunk_renderer.dart';
part 'box_renderer.dart';
part 'guide_renderer.dart';

/// 카메라 방향 (0°, 90°, 180°, 270°)
enum CameraDirection { dir0, dir1, dir2, dir3 }

/// 3D 좌표 → 2D 아이소메트릭 변환 및 전체 씬 페인팅
class IsometricPainter extends CustomPainter {
  final TrunkSpace space;
  final List<TrimBox> boxes;
  final String? selectedBoxId;
  final Set<String> collidingBoxIds;
  final double scale;
  final Offset panOffset;
  final CameraDirection direction;

  /// 드래그 중인 박스 ID (null이면 드래그 중 아님)
  final String? draggingBoxId;

  /// 줌 레벨 (실루엣 페이드 계산용)
  final double zoomLevel;

  IsometricPainter({
    required this.space,
    required this.boxes,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    this.scale = 280.0,
    this.panOffset = Offset.zero,
    this.direction = CameraDirection.dir0,
    this.draggingBoxId,
    this.zoomLevel = 1.0,
  });

  // 아이소메트릭 각도 (30도)
  static const double _angle = 30.0 * math.pi / 180.0;
  static final double _cosA = math.cos(_angle);
  static final double _sinA = math.sin(_angle);

  /// View-space projected dimensions
  double get projW =>
      (direction == CameraDirection.dir1 || direction == CameraDirection.dir3)
          ? space.d
          : space.w;
  double get projD =>
      (direction == CameraDirection.dir1 || direction == CameraDirection.dir3)
          ? space.w
          : space.d;

  /// Pure isometric projection (view-space coords → 2D screen)
  Offset toIso(double x, double y, double z) {
    final sx = (x - z) * _cosA * scale;
    final sy = (x + z) * _sinA * scale - y * scale;
    return Offset(sx, sy);
  }

  /// World-space box → view-space box
  ({double vx, double vz, double vw, double vd}) boxToView(
      double x, double z, double w, double d) {
    switch (direction) {
      case CameraDirection.dir0:
        return (vx: x, vz: z, vw: w, vd: d);
      case CameraDirection.dir1:
        return (vx: z, vz: space.w - x - w, vw: d, vd: w);
      case CameraDirection.dir2:
        return (vx: space.w - x - w, vz: space.d - z - d, vw: w, vd: d);
      case CameraDirection.dir3:
        return (vx: space.d - z - d, vz: x, vw: d, vd: w);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final center = computeCenter(size, space, scale, direction);
    canvas.translate(center.dx + panOffset.dx, center.dy + panOffset.dy);

    drawTrunkWalls(canvas);
    drawSeatBackrest(canvas);
    drawTrunkFloor(canvas);
    drawFloorStep(canvas);
    drawFloorLogo(canvas);
    drawGrid(canvas);
    drawObjects(canvas);
    if (draggingBoxId != null) drawStackingGuides(canvas);
    drawTrunkRim(canvas);
    drawTrunkLidSilhouette(canvas);
    drawDimensionLabels(canvas);

    canvas.restore();
  }

  /// 씬 중심점 계산 (direction-aware)
  static Offset computeCenter(
      Size size, TrunkSpace space, double scale, CameraDirection direction) {
    final projW =
        (direction == CameraDirection.dir1 || direction == CameraDirection.dir3)
            ? space.d
            : space.w;
    final projD =
        (direction == CameraDirection.dir1 || direction == CameraDirection.dir3)
            ? space.w
            : space.d;

    final sceneTop = space.h * scale;
    final sceneBottom = (projW + projD) * _sinA * scale;
    final sceneHeight = sceneTop + sceneBottom;
    final centerY = (size.height - sceneHeight) / 2 + sceneTop;
    final leftExtent = projD * _cosA * scale;
    final rightExtent = projW * _cosA * scale;
    final centerX = (size.width + leftExtent - rightExtent) / 2;
    return Offset(centerX, centerY);
  }

  /// 꼭짓점에 미세 라운딩을 적용한 Path 생성
  Path roundedPath(List<Offset> points) {
    final r = scale * 0.005;
    final path = Path();
    final n = points.length;
    for (int i = 0; i < n; i++) {
      final prev = points[(i - 1 + n) % n];
      final curr = points[i];
      final next = points[(i + 1) % n];

      final dx1 = prev.dx - curr.dx;
      final dy1 = prev.dy - curr.dy;
      final len1 = math.sqrt(dx1 * dx1 + dy1 * dy1);
      final dx2 = next.dx - curr.dx;
      final dy2 = next.dy - curr.dy;
      final len2 = math.sqrt(dx2 * dx2 + dy2 * dy2);

      if (len1 < 0.001 || len2 < 0.001) {
        if (i == 0) {
          path.moveTo(curr.dx, curr.dy);
        } else {
          path.lineTo(curr.dx, curr.dy);
        }
        continue;
      }

      final clampR = math.min(r, math.min(len1 / 3, len2 / 3));
      final startX = curr.dx + (dx1 / len1) * clampR;
      final startY = curr.dy + (dy1 / len1) * clampR;
      final endX = curr.dx + (dx2 / len2) * clampR;
      final endY = curr.dy + (dy2 / len2) * clampR;

      if (i == 0) {
        path.moveTo(startX, startY);
      } else {
        path.lineTo(startX, startY);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, endX, endY);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant IsometricPainter oldDelegate) => true;
}
