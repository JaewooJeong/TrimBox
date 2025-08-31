import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/trunk_space.dart';
import '../models/box.dart';
import '../utils/isometric_utils.dart';
import '../utils/collision_utils.dart';

class TrunkPainter extends CustomPainter {
  final TrunkSpace trunkSpace;
  final List<Box> boxes;
  final double scale;
  final Offset centerOffset;
  final String? selectedBoxId;
  final Box? draggedBox;
  
  const TrunkPainter({
    required this.trunkSpace,
    required this.boxes,
    this.scale = 100.0,
    this.centerOffset = Offset.zero,
    this.selectedBoxId,
    this.draggedBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Center the view
    final center = Offset(size.width / 2, size.height / 2) + centerOffset;
    canvas.translate(center.dx, center.dy);
    
    _drawTrunkFloor(canvas);
    _drawGrid(canvas);
    _drawWheelhouses(canvas);
    _drawBoxes(canvas);
  }
  
  void _drawTrunkFloor(Canvas canvas) {
    final floorPaint = Paint()
      ..color = const Color(0xFF2E2E2E)
      ..style = PaintingStyle.fill;
    
    // Get floor corners
    final corners = [
      IsometricUtils.projectToScreen(0, 0, 0, scale: scale),
      IsometricUtils.projectToScreen(trunkSpace.width, 0, 0, scale: scale),
      IsometricUtils.projectToScreen(trunkSpace.width, 0, trunkSpace.depth, scale: scale),
      IsometricUtils.projectToScreen(0, 0, trunkSpace.depth, scale: scale),
    ];
    
    final path = Path();
    path.moveTo(corners[0].dx, corners[0].dy);
    for (int i = 1; i < corners.length; i++) {
      path.lineTo(corners[i].dx, corners[i].dy);
    }
    path.close();
    
    canvas.drawPath(path, floorPaint);
    
    // Draw floor outline
    final outlinePaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, outlinePaint);
  }
  
  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Draw grid lines parallel to X-axis
    for (double z = trunkSpace.gridSize; z < trunkSpace.depth; z += trunkSpace.gridSize) {
      final start = IsometricUtils.projectToScreen(0, 0, z, scale: scale);
      final end = IsometricUtils.projectToScreen(trunkSpace.width, 0, z, scale: scale);
      canvas.drawLine(start, end, gridPaint);
    }
    
    // Draw grid lines parallel to Z-axis
    for (double x = trunkSpace.gridSize; x < trunkSpace.width; x += trunkSpace.gridSize) {
      final start = IsometricUtils.projectToScreen(x, 0, 0, scale: scale);
      final end = IsometricUtils.projectToScreen(x, 0, trunkSpace.depth, scale: scale);
      canvas.drawLine(start, end, gridPaint);
    }
  }
  
  void _drawWheelhouses(Canvas canvas) {
    final wheelhousePaint = Paint()
      ..color = const Color(0xFFA9A9A9)
      ..style = PaintingStyle.fill;
    
    final wheelhouseOutlinePaint = Paint()
      ..color = Colors.white38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    for (final wheelhouse in trunkSpace.wheelhouses) {
      _drawBox(
        canvas,
        wheelhouse.x,
        0,
        wheelhouse.z,
        wheelhouse.width,
        wheelhouse.height,
        wheelhouse.depth,
        wheelhousePaint,
        wheelhouseOutlinePaint,
      );
    }
  }
  
  void _drawBoxes(Canvas canvas) {
    // Draw all regular boxes first
    for (final box in boxes) {
      if (draggedBox?.id == box.id) continue; // Skip dragged box, draw it last
      
      _drawSingleBox(canvas, box);
    }
    
    // Draw dragged box last (on top)
    if (draggedBox != null) {
      _drawSingleBox(canvas, draggedBox!);
    }
  }
  
  void _drawSingleBox(Canvas canvas, Box box) {
    final isSelected = selectedBoxId == box.id;
    final isDragged = draggedBox?.id == box.id;
    final hasCollision = CollisionUtils.hasAnyCollision(
      box, 
      boxes.where((b) => b.id != box.id).toList(), 
      trunkSpace,
    );
    
    // Determine box colors based on state
    Color fillColor = _getBoxColor(box).withOpacity(0.7);
    Color outlineColor = _getBoxColor(box);
    double strokeWidth = 2.0;
    
    if (hasCollision) {
      // Red for collisions
      outlineColor = const Color(0xFFFF4D4D);
      fillColor = const Color(0xFFFF4D4D).withOpacity(0.3);
      strokeWidth = 3.0;
    } else if (isSelected) {
      // Blue for selected
      outlineColor = const Color(0xFF4DA3FF);
      strokeWidth = 3.0;
    }
    
    final boxPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    
    final boxOutlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    
    // Apply rotation by swapping dimensions if needed
    double width = box.width;
    double depth = box.depth;
    if (box.rotationY == 90 || box.rotationY == 270) {
      width = box.depth;
      depth = box.width;
    }
    
    _drawBox(
      canvas,
      box.x,
      box.y,
      box.z,
      width,
      box.height,
      depth,
      boxPaint,
      boxOutlinePaint,
    );
    
    // Draw size label for selected box
    if (isSelected) {
      _drawBoxLabel(canvas, box, width, depth);
    }
  }
  
  void _drawBoxLabel(Canvas canvas, Box box, double width, double depth) {
    final centerPos = IsometricUtils.projectToScreen(
      box.x + width / 2, 
      box.y + box.height + 0.1, 
      box.z + depth / 2, 
      scale: scale,
    );
    
    final text = '${(box.width * 100).toInt()}×${(box.depth * 100).toInt()}×${(box.height * 100).toInt()}cm';
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas, 
      centerPos - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
  
  void _drawBox(
    Canvas canvas,
    double x, double y, double z,
    double width, double height, double depth,
    Paint fillPaint,
    Paint outlinePaint,
  ) {
    final corners = IsometricUtils.getBoxCorners(
      x, y, z, width, height, depth,
      scale: scale,
    );
    
    // Draw faces in correct order for proper depth
    // Bottom face
    _drawQuad(canvas, [corners[0], corners[1], corners[2], corners[3]], fillPaint, outlinePaint);
    
    // Left face
    _drawQuad(canvas, [corners[0], corners[3], corners[7], corners[4]], fillPaint, outlinePaint);
    
    // Right face
    _drawQuad(canvas, [corners[1], corners[5], corners[6], corners[2]], fillPaint, outlinePaint);
    
    // Top face
    _drawQuad(canvas, [corners[4], corners[5], corners[6], corners[7]], fillPaint, outlinePaint);
  }
  
  void _drawQuad(Canvas canvas, List<Offset> points, Paint fillPaint, Paint outlinePaint) {
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
  }
  
  Color _getBoxColor(Box box) {
    // Generate color based on box ID for consistency
    final hash = box.id.hashCode;
    final colors = [
      const Color(0xFFFFB3BA), // Light pink
      const Color(0xFFBAE1FF), // Light blue
      const Color(0xFFBAFFC9), // Light green
      const Color(0xFFFFFFBA), // Light yellow
      const Color(0xFFFFDBBA), // Light orange
      const Color(0xFFE1BAFF), // Light purple
    ];
    return colors[hash.abs() % colors.length];
  }

  /// Get the box at a given screen position (for hit testing)
  Box? getBoxAtPosition(Offset screenPos, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2) + centerOffset;
    final adjustedPos = screenPos - center;
    
    // Convert screen position to world coordinates
    final worldPos = IsometricUtils.screenToWorld(adjustedPos, scale: scale);
    
    // Check boxes in reverse order (top to bottom)
    for (int i = boxes.length - 1; i >= 0; i--) {
      final box = boxes[i];
      final dims = CollisionUtils.hasAnyCollision(box, [], trunkSpace) 
          ? (width: box.depth, depth: box.width) // Consider rotation
          : (width: box.width, depth: box.depth);
      
      if (worldPos.dx >= box.x && 
          worldPos.dx <= box.x + dims.width &&
          worldPos.dy >= box.z && 
          worldPos.dy <= box.z + dims.depth) {
        return box;
      }
    }
    
    return null;
  }

  @override
  bool shouldRepaint(TrunkPainter oldDelegate) {
    return oldDelegate.trunkSpace != trunkSpace ||
           oldDelegate.boxes != boxes ||
           oldDelegate.scale != scale ||
           oldDelegate.centerOffset != centerOffset ||
           oldDelegate.selectedBoxId != selectedBoxId ||
           oldDelegate.draggedBox != draggedBox;
  }
}