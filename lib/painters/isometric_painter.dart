import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../models/trunk_space.dart';
import '../models/trim_box.dart';

part 'trunk_renderer.dart';
part 'box_renderer.dart';
part 'guide_renderer.dart';
part 'vehicle_body_renderer.dart';

/// 1-Point Perspective trunk interior painter
/// (class name retained for API compatibility)
class IsometricPainter extends CustomPainter {
  final TrunkSpace space;
  final List<TrimBox> boxes;
  final String? selectedBoxId;
  final Set<String> collidingBoxIds;
  final double scale;
  final Offset panOffset;
  final double cameraYaw; // retained for API compat (unused in projection)
  final String? draggingBoxId;
  final double zoomLevel;
  /// When non-null, only boxes with this loadOrder are fully visible;
  /// boxes with lower loadOrder are dimmed, higher are hidden.
  final int? highlightLoadOrder;

  IsometricPainter({
    required this.space,
    required this.boxes,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    this.scale = 280.0,
    this.panOffset = Offset.zero,
    this.cameraYaw = 0.0,
    this.draggingBoxId,
    this.zoomLevel = 1.0,
    this.highlightLoadOrder,
  });

  // ── Camera parameters ──
  late final double camX = space.w / 2;
  late final double camY = space.h * 1.05;
  late final double focalLen = space.d * 1.0;
  late final double camZ = space.d + focalLen;

  /// 1-point perspective projection: world → screen
  Offset toScreen(double x, double y, double z) {
    final dz = camZ - z;
    if (dz < 0.001) return Offset.zero;
    final f = focalLen / dz * scale;
    return Offset((x - camX) * f, -(y - camY) * f);
  }

  /// Alias for backward compatibility
  Offset toIso(double x, double y, double z) => toScreen(x, y, z);

  /// Face visibility — fixed perspective, all interior faces visible
  bool isFaceVisible(double nx, double nz) => true;

  /// Build a closed path from screen-space points
  Path buildPath(List<Offset> pts) {
    final p = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(
      size.width / 2 + panOffset.dx,
      size.height / 2 + panOffset.dy,
    );

    // Draw order: back -> front
    drawSeatBackrest(canvas);
    drawTrunkCeiling(canvas);
    drawTrunkWalls(canvas);
    drawCargoNetPoints(canvas);
    drawTwelveVOutlet(canvas);
    drawTrunkFloor(canvas);
    drawCargoHooks(canvas);
    drawTrunkLight(canvas);
    drawGrid(canvas);
    drawObjects(canvas);
    if (draggingBoxId != null) drawStackingGuides(canvas);
    drawOpeningFrame(canvas);
    drawDimensionLabels(canvas);

    canvas.restore();
  }

  /// Scene center (for simulator_screen compat)
  static Offset computeCenter(
      Size size, TrunkSpace space, double scale, double cameraYaw) {
    return Offset(size.width / 2, size.height / 2);
  }

  @override
  bool shouldRepaint(covariant IsometricPainter oldDelegate) =>
      space != oldDelegate.space ||
      boxes != oldDelegate.boxes ||
      selectedBoxId != oldDelegate.selectedBoxId ||
      collidingBoxIds != oldDelegate.collidingBoxIds ||
      scale != oldDelegate.scale ||
      panOffset != oldDelegate.panOffset ||
      draggingBoxId != oldDelegate.draggingBoxId ||
      zoomLevel != oldDelegate.zoomLevel ||
      highlightLoadOrder != oldDelegate.highlightLoadOrder;
}
