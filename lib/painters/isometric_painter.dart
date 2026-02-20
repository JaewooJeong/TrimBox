import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/trunk_space.dart';
import '../models/trim_box.dart';

/// 3D 좌표 → 2D 아이소메트릭 변환 및 전체 씬 페인팅
class IsometricPainter extends CustomPainter {
  final TrunkSpace space;
  final List<TrimBox> boxes;
  final String? selectedBoxId;
  final Set<String> collidingBoxIds;
  final double scale;

  IsometricPainter({
    required this.space,
    required this.boxes,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    this.scale = 280.0,
  });

  // 아이소메트릭 각도 (30도)
  static const double _angle = 30.0 * math.pi / 180.0;
  static final double _cosA = math.cos(_angle);
  static final double _sinA = math.sin(_angle);

  /// 3D (x, y, z) → 2D 아이소메트릭 좌표
  Offset toIso(double x, double y, double z) {
    final sx = (x - z) * _cosA * scale;
    final sy = (x + z) * _sinA * scale - y * scale;
    return Offset(sx, sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 캔버스 중앙으로 이동
    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.55);

    _drawTrunkFloor(canvas);
    _drawGrid(canvas);
    _drawWheelhouses(canvas);
    _drawBoxes(canvas);

    canvas.restore();
  }

  void _drawTrunkFloor(Canvas canvas) {
    final w = space.w;
    final d = space.d;

    final path = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(w, 0, 0).dx, toIso(w, 0, 0).dy)
      ..lineTo(toIso(w, 0, d).dx, toIso(w, 0, d).dy)
      ..lineTo(toIso(0, 0, d).dx, toIso(0, 0, d).dy)
      ..close();

    // 바닥 면 채우기
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2E2E2E)
        ..style = PaintingStyle.fill,
    );

    // 바닥 테두리
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawGrid(Canvas canvas) {
    final gridPaint = Paint()
      ..color = const Color(0x40CCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final w = space.w;
    final d = space.d;
    final unit = space.gridUnit;

    // X축 방향 그리드
    for (double x = 0; x <= w + 0.001; x += unit) {
      final p1 = toIso(x, 0, 0);
      final p2 = toIso(x, 0, d);
      canvas.drawLine(p1, p2, gridPaint);
    }

    // Z축 방향 그리드
    for (double z = 0; z <= d + 0.001; z += unit) {
      final p1 = toIso(0, 0, z);
      final p2 = toIso(w, 0, z);
      canvas.drawLine(p1, p2, gridPaint);
    }
  }

  void _drawWheelhouses(Canvas canvas) {
    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;

    // 왼쪽 휠하우스 (x=0 쪽, z 뒤쪽)
    _drawIsometricBox(
      canvas,
      x: 0,
      y: 0,
      z: space.d - lw.d,
      w: lw.w,
      h: lw.h,
      d: lw.d,
      fillColor: const Color(0xFFA9A9A9),
      strokeColor: const Color(0xFF888888),
    );

    // 오른쪽 휠하우스 (x=space.w-rw.w 쪽, z 뒤쪽)
    _drawIsometricBox(
      canvas,
      x: space.w - rw.w,
      y: 0,
      z: space.d - rw.d,
      w: rw.w,
      h: rw.h,
      d: rw.d,
      fillColor: const Color(0xFFA9A9A9),
      strokeColor: const Color(0xFF888888),
    );
  }

  void _drawBoxes(Canvas canvas) {
    // Z가 작은 것(앞쪽)부터 → 뒤의 박스가 앞에 그려지지 않도록
    final sorted = List<TrimBox>.from(boxes)
      ..sort((a, b) {
        final zA = a.z + a.effectiveD;
        final zB = b.z + b.effectiveD;
        if (zA != zB) return zA.compareTo(zB);
        return (a.x + a.effectiveW).compareTo(b.x + b.effectiveW);
      });

    for (final box in sorted) {
      final isSelected = box.id == selectedBoxId;
      final isColliding = collidingBoxIds.contains(box.id);

      Color strokeColor;
      double strokeWidth;
      if (isColliding) {
        strokeColor = const Color(0xFFFF4D4D);
        strokeWidth = 2.5;
      } else if (isSelected) {
        strokeColor = const Color(0xFF4DA3FF);
        strokeWidth = 2.5;
      } else {
        strokeColor = box.color.withValues(alpha: 0.8);
        strokeWidth = 1.0;
      }

      _drawIsometricBox(
        canvas,
        x: box.x,
        y: box.y,
        z: box.z,
        w: box.effectiveW,
        h: box.h,
        d: box.effectiveD,
        fillColor: box.color.withValues(alpha: 0.7),
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
      );

      // 선택된 박스에 크기 라벨 표시
      if (isSelected) {
        _drawBoxLabel(canvas, box);
      }
    }
  }

  void _drawIsometricBox(
    Canvas canvas, {
    required double x,
    required double y,
    required double z,
    required double w,
    required double h,
    required double d,
    required Color fillColor,
    required Color strokeColor,
    double strokeWidth = 1.0,
  }) {
    // 보이는 면에 필요한 꼭짓점만 계산
    final p0 = toIso(x, y, z);         // 바닥-앞왼
    final p2 = toIso(x + w, y, z + d); // 바닥-뒤오른
    final p3 = toIso(x, y, z + d);     // 바닥-뒤왼
    final p4 = toIso(x, y + h, z);     // 윗면-앞왼
    final p5 = toIso(x + w, y + h, z); // 윗면-앞오른
    final p6 = toIso(x + w, y + h, z + d); // 윗면-뒤오른
    final p7 = toIso(x, y + h, z + d); // 윗면-뒤왼

    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // 윗면 (가장 밝게)
    final top = Path()
      ..moveTo(p4.dx, p4.dy)
      ..lineTo(p5.dx, p5.dy)
      ..lineTo(p6.dx, p6.dy)
      ..lineTo(p7.dx, p7.dy)
      ..close();
    fill.color = _brighten(fillColor, 0.2);
    canvas.drawPath(top, fill);
    canvas.drawPath(top, stroke);

    // 왼쪽 면
    final left = Path()
      ..moveTo(p3.dx, p3.dy)
      ..lineTo(p7.dx, p7.dy)
      ..lineTo(p6.dx, p6.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    fill.color = _darken(fillColor, 0.1);
    canvas.drawPath(left, fill);
    canvas.drawPath(left, stroke);

    // 오른쪽 면
    final right = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p4.dx, p4.dy)
      ..lineTo(p7.dx, p7.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    fill.color = _darken(fillColor, 0.2);
    canvas.drawPath(right, fill);
    canvas.drawPath(right, stroke);
  }

  void _drawBoxLabel(Canvas canvas, TrimBox box) {
    final center = toIso(
      box.x + box.effectiveW / 2,
      box.y + box.h,
      box.z + box.effectiveD / 2,
    );

    final text =
        '${(box.w * 100).round()}×${(box.d * 100).round()}×${(box.h * 100).round()}cm';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bg = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 14),
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(4)),
      Paint()..color = const Color(0xCC000000),
    );
    tp.paint(canvas, Offset(bg.left + 4, bg.top + 2));
  }

  Color _brighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: c.a);
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor()
        .withValues(alpha: c.a);
  }

  @override
  bool shouldRepaint(covariant IsometricPainter oldDelegate) => true;
}
