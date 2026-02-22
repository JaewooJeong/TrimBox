import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/trunk_space.dart';
import '../models/trim_box.dart';

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

  IsometricPainter({
    required this.space,
    required this.boxes,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    this.scale = 280.0,
    this.panOffset = Offset.zero,
    this.direction = CameraDirection.dir0,
    this.draggingBoxId,
  });

  // 아이소메트릭 각도 (30도)
  static const double _angle = 30.0 * math.pi / 180.0;
  static final double _cosA = math.cos(_angle);
  static final double _sinA = math.sin(_angle);

  /// View-space projected dimensions
  double get _projW =>
      (direction == CameraDirection.dir1 || direction == CameraDirection.dir3)
          ? space.d
          : space.w;
  double get _projD =>
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
  ({double vx, double vz, double vw, double vd}) _boxToView(
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

    _drawTrunkWalls(canvas);
    _drawTrunkFloor(canvas);
    _drawGrid(canvas);
    _drawObjects(canvas);
    if (draggingBoxId != null) _drawStackingGuides(canvas);
    _drawTrunkRim(canvas);
    _drawDimensionLabels(canvas);

    canvas.restore();
  }

  /// 트렁크 뒷벽 2개 (view-space)
  void _drawTrunkWalls(Canvas canvas) {
    final pw = _projW;
    final pd = _projD;
    final h = space.h;

    final wallStroke = Paint()
      ..color = const Color(0xFF505050)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 왼쪽 뒷벽 (viewX=0, z방향) — 어두운 면
    final leftWall = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..lineTo(toIso(0, h, pd).dx, toIso(0, h, pd).dy)
      ..lineTo(toIso(0, h, 0).dx, toIso(0, h, 0).dy)
      ..close();

    canvas.drawPath(
      leftWall,
      Paint()
        ..color = const Color(0xFF252530)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(leftWall, wallStroke);

    // 오른쪽 뒷벽 (viewZ=0, x방향) — 밝은 면
    final rightWall = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(pw, 0, 0).dx, toIso(pw, 0, 0).dy)
      ..lineTo(toIso(pw, h, 0).dx, toIso(pw, h, 0).dy)
      ..lineTo(toIso(0, h, 0).dx, toIso(0, h, 0).dy)
      ..close();

    canvas.drawPath(
      rightWall,
      Paint()
        ..color = const Color(0xFF353540)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(rightWall, wallStroke);

    // 벽면 높이 가이드선
    final wallMinorPaint = Paint()
      ..color = const Color(0x15FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final wallMajorPaint = Paint()
      ..color = const Color(0x30FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const wallUnit = 0.10;
    const wallMajorUnit = 0.50;

    for (double py = wallUnit; py < h - 0.001; py += wallUnit) {
      final isMajor =
          (py / wallMajorUnit - (py / wallMajorUnit).round()).abs() < 0.001;
      final paint = isMajor ? wallMajorPaint : wallMinorPaint;
      canvas.drawLine(toIso(0, py, 0), toIso(0, py, pd), paint);
      canvas.drawLine(toIso(0, py, 0), toIso(pw, py, 0), paint);
    }
  }

  /// 트렁크 상단 림과 수직 엣지
  void _drawTrunkRim(Canvas canvas) {
    final pw = _projW;
    final pd = _projD;
    final h = space.h;

    final rimPaint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(toIso(0, h, 0), toIso(0, h, pd), rimPaint);
    canvas.drawLine(toIso(0, h, 0), toIso(pw, h, 0), rimPaint);

    final edgePaint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(toIso(0, 0, 0), toIso(0, h, 0), edgePaint);
    canvas.drawLine(toIso(0, 0, pd), toIso(0, h, pd), edgePaint);
    canvas.drawLine(toIso(pw, 0, 0), toIso(pw, h, 0), edgePaint);
  }

  void _drawTrunkFloor(Canvas canvas) {
    final pw = _projW;
    final pd = _projD;

    final path = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(pw, 0, 0).dx, toIso(pw, 0, 0).dy)
      ..lineTo(toIso(pw, 0, pd).dx, toIso(pw, 0, pd).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF28282E)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 벽-바닥 접합선
    final junctionPaint = Paint()
      ..color = const Color(0xFF0A0A0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(toIso(0, 0, 0), toIso(0, 0, pd), junctionPaint);
    canvas.drawLine(toIso(0, 0, 0), toIso(pw, 0, 0), junctionPaint);

    // 앰비언트 오클루전 스트립
    final aoDepth = 0.06;
    final aoPaint = Paint()
      ..color = const Color(0x50000000)
      ..style = PaintingStyle.fill;

    final leftAo = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..lineTo(toIso(aoDepth, 0, pd).dx, toIso(aoDepth, 0, pd).dy)
      ..lineTo(toIso(aoDepth, 0, 0).dx, toIso(aoDepth, 0, 0).dy)
      ..close();
    canvas.drawPath(leftAo, aoPaint);

    final rightAo = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(pw, 0, 0).dx, toIso(pw, 0, 0).dy)
      ..lineTo(toIso(pw, 0, aoDepth).dx, toIso(pw, 0, aoDepth).dy)
      ..lineTo(toIso(0, 0, aoDepth).dx, toIso(0, 0, aoDepth).dy)
      ..close();
    canvas.drawPath(rightAo, aoPaint);
  }

  void _drawGrid(Canvas canvas) {
    final pw = _projW;
    final pd = _projD;
    const unit = 0.10;
    const majorUnit = 0.50;

    final minorPaint = Paint()
      ..color = const Color(0x40999999)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final majorPaint = Paint()
      ..color = const Color(0x80AAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (double x = 0; x <= pw + 0.001; x += unit) {
      final p1 = toIso(x, 0, 0);
      final p2 = toIso(x, 0, pd);
      final isMajor =
          (x / majorUnit - (x / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(p1, p2, isMajor ? majorPaint : minorPaint);
    }

    for (double z = 0; z <= pd + 0.001; z += unit) {
      final p1 = toIso(0, 0, z);
      final p2 = toIso(pw, 0, z);
      final isMajor =
          (z / majorUnit - (z / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(p1, p2, isMajor ? majorPaint : minorPaint);
    }
  }

  /// 휠하우스 + 박스를 통합 depth sort하여 렌더링
  void _drawObjects(Canvas canvas) {
    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;

    final List<({double depth, VoidCallback draw})> objects = [];

    // 휠하우스 → view-space 변환 (카페트 톤 색상)
    const whFill = Color(0xFF8A8A8A);
    const whStroke = Color(0xFF666666);

    final lvw = _boxToView(0, space.d - lw.d, lw.w, lw.d);
    objects.add((
      depth: (lvw.vx + lvw.vw / 2) + (lvw.vz + lvw.vd / 2),
      draw: () {
        _drawIsometricBox(
          canvas,
          x: lvw.vx, y: 0, z: lvw.vz,
          w: lvw.vw, h: lw.h, d: lvw.vd,
          fillColor: whFill,
          strokeColor: whStroke,
        );
        _drawWheelhouseTexture(canvas, lvw.vx, lw.h, lvw.vz, lvw.vw, lvw.vd);
      },
    ));

    final rvw = _boxToView(space.w - rw.w, space.d - rw.d, rw.w, rw.d);
    objects.add((
      depth: (rvw.vx + rvw.vw / 2) + (rvw.vz + rvw.vd / 2),
      draw: () {
        _drawIsometricBox(
          canvas,
          x: rvw.vx, y: 0, z: rvw.vz,
          w: rvw.vw, h: rw.h, d: rvw.vd,
          fillColor: whFill,
          strokeColor: whStroke,
        );
        _drawWheelhouseTexture(canvas, rvw.vx, rw.h, rvw.vz, rvw.vw, rvw.vd);
      },
    ));

    // 박스 → view-space 변환
    for (final box in boxes) {
      final vb = _boxToView(box.x, box.z, box.effectiveW, box.effectiveD);
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
        strokeColor = Color.lerp(box.color, Colors.black, 0.35)!;
        strokeWidth = 1.2;
      }

      objects.add((
        depth: (vb.vx + vb.vw / 2) + (vb.vz + vb.vd / 2),
        draw: () {
          _drawIsometricBox(
            canvas,
            x: vb.vx, y: box.y, z: vb.vz,
            w: vb.vw, h: box.h, d: vb.vd,
            fillColor: box.color,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
          );
          if (isSelected) {
            _drawBoxLabelAt(canvas, box, vb);
          } else {
            _drawBoxNameLabelAt(canvas, box, vb);
          }
        },
      ));
    }

    // Painter's algorithm: depth 작은 것(뒤쪽)부터 그리기
    objects.sort((a, b) => a.depth.compareTo(b.depth));
    for (final obj in objects) {
      obj.draw();
    }
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
    final p1 = toIso(x + w, y, z);
    final p2 = toIso(x + w, y, z + d);
    final p3 = toIso(x, y, z + d);
    final p4 = toIso(x, y + h, z);
    final p5 = toIso(x + w, y + h, z);
    final p6 = toIso(x + w, y + h, z + d);
    final p7 = toIso(x, y + h, z + d);

    final fill = Paint()..style = PaintingStyle.fill;

    // 바닥 그림자
    if (y < 0.001) {
      final so = 0.015;
      final shadow = Path()
        ..moveTo(toIso(x - so, -0.002, z - so).dx,
            toIso(x - so, -0.002, z - so).dy)
        ..lineTo(toIso(x + w + so, -0.002, z - so).dx,
            toIso(x + w + so, -0.002, z - so).dy)
        ..lineTo(toIso(x + w + so * 2, -0.002, z + d + so * 2).dx,
            toIso(x + w + so * 2, -0.002, z + d + so * 2).dy)
        ..lineTo(toIso(x - so, -0.002, z + d + so * 2).dx,
            toIso(x - so, -0.002, z + d + so * 2).dy)
        ..close();
      canvas.drawPath(
        shadow,
        Paint()
          ..color = const Color(0x55000000)
          ..style = PaintingStyle.fill,
      );
    }

    final topColor = fillColor;
    final rightColor = Color.lerp(fillColor, Colors.black, 0.35)!;
    final leftColor = Color.lerp(fillColor, Colors.black, 0.58)!;

    // 1. 왼쪽 면 (z+d)
    fill.color = leftColor;
    canvas.drawPath(
      Path()
        ..moveTo(p3.dx, p3.dy)..lineTo(p7.dx, p7.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    // 2. 오른쪽 면 (x+w)
    fill.color = rightColor;
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    // 3. 윗면
    fill.color = topColor;
    canvas.drawPath(
      Path()
        ..moveTo(p4.dx, p4.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p7.dx, p7.dy)..close(),
      fill,
    );

    // 외곽 헥사곤
    final edgeColor = Color.lerp(fillColor, Colors.black, 0.65)!;
    final hexOutline = Path()
      ..moveTo(p4.dx, p4.dy)..lineTo(p5.dx, p5.dy)
      ..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)..lineTo(p7.dx, p7.dy)..close();

    canvas.drawPath(
      hexOutline,
      Paint()
        ..color = Color.lerp(fillColor, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );
    // 3개 면 다시 채우기
    fill.color = leftColor;
    canvas.drawPath(
      Path()..moveTo(p3.dx, p3.dy)..lineTo(p7.dx, p7.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    fill.color = rightColor;
    canvas.drawPath(
      Path()..moveTo(p1.dx, p1.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    fill.color = topColor;
    canvas.drawPath(
      Path()..moveTo(p4.dx, p4.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p7.dx, p7.dy)..close(),
      fill,
    );

    canvas.drawPath(
      hexOutline,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round,
    );

    // 내부 분리선: p2→p6
    canvas.drawLine(
      p2, p6,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // 윗면 뒤쪽 엣지
    final backEdgePaint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(p5, p4, backEdgePaint);
    canvas.drawLine(p4, p7, backEdgePaint);

    // 충돌/선택 외곽선
    if (strokeWidth > 1.5) {
      canvas.drawPath(
        hexOutline,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  /// 휠하우스 상단면에 미세한 카페트 텍스처 (점선 격자)
  void _drawWheelhouseTexture(
      Canvas canvas, double vx, double y, double vz, double vw, double vd) {
    final texPaint = Paint()
      ..color = const Color(0x20000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const step = 0.03; // 3cm 간격
    for (double x = step; x < vw; x += step) {
      canvas.drawLine(toIso(vx + x, y, vz), toIso(vx + x, y, vz + vd), texPaint);
    }
    for (double z = step; z < vd; z += step) {
      canvas.drawLine(toIso(vx, y, vz + z), toIso(vx + vw, y, vz + z), texPaint);
    }
  }

  /// 선택된 박스 치수 라벨 (view-space 좌표 사용)
  void _drawBoxLabelAt(Canvas canvas, TrimBox box,
      ({double vx, double vz, double vw, double vd}) vb) {
    final center = toIso(
      vb.vx + vb.vw / 2,
      box.y + box.h,
      vb.vz + vb.vd / 2,
    );

    final text =
        '${(box.effectiveW * 100).round()}×${(box.effectiveD * 100).round()}×${(box.h * 100).round()}cm';
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

  /// 비선택 박스 이름 라벨 (view-space 좌표 사용)
  void _drawBoxNameLabelAt(Canvas canvas, TrimBox box,
      ({double vx, double vz, double vw, double vd}) vb) {
    final center = toIso(
      vb.vx + vb.vw / 2,
      box.y + box.h,
      vb.vz + vb.vd / 2,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: box.label,
        style: const TextStyle(
          color: Color(0xEEFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelCenter = Offset(center.dx, center.dy - 12);
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: labelCenter,
        width: tp.width + 10,
        height: tp.height + 6,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0x99000000));
    tp.paint(
      canvas,
      Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2),
    );
  }

  /// 드래그 중 스태킹 가이드 렌더링
  void _drawStackingGuides(Canvas canvas) {
    final dragBox = boxes.where((b) => b.id == draggingBoxId).firstOrNull;
    if (dragBox == null) return;

    final dragArea = dragBox.effectiveW * dragBox.effectiveD;

    for (final other in boxes) {
      if (other.id == dragBox.id) continue;

      // XZ 겹침 계산
      final overlapX =
          math.min(dragBox.x + dragBox.effectiveW, other.x + other.effectiveW) -
              math.max(dragBox.x, other.x);
      final overlapZ =
          math.min(dragBox.z + dragBox.effectiveD, other.z + other.effectiveD) -
              math.max(dragBox.z, other.z);

      if (overlapX <= 0 || overlapZ <= 0) continue;

      final overlapArea = overlapX * overlapZ;
      final isStackable = overlapArea >= dragArea * 0.5;
      final topY = other.y + other.h;

      // 높이 초과 확인
      final wouldExceed = topY + dragBox.h > space.h + 0.001;
      final guideColor = (isStackable && !wouldExceed)
          ? const Color(0x6600CC66) // 초록 (적재 가능)
          : const Color(0x55FF4444); // 빨강 (불가)

      // 아래 박스 상단면 하이라이트 (view-space)
      final vb =
          _boxToView(other.x, other.z, other.effectiveW, other.effectiveD);
      final p4 = toIso(vb.vx, topY, vb.vz);
      final p5 = toIso(vb.vx + vb.vw, topY, vb.vz);
      final p6 = toIso(vb.vx + vb.vw, topY, vb.vz + vb.vd);
      final p7 = toIso(vb.vx, topY, vb.vz + vb.vd);

      final topFace = Path()
        ..moveTo(p4.dx, p4.dy)
        ..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)
        ..lineTo(p7.dx, p7.dy)
        ..close();

      canvas.drawPath(
        topFace,
        Paint()
          ..color = guideColor
          ..style = PaintingStyle.fill,
      );

      // 테두리
      canvas.drawPath(
        topFace,
        Paint()
          ..color = (isStackable && !wouldExceed)
              ? const Color(0xAA00CC66)
              : const Color(0xAAFF4444)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  /// 트렁크 치수 라벨
  void _drawDimensionLabels(Canvas canvas) {
    final pw = _projW;
    final pd = _projD;

    // 폭 라벨 (front-left edge, viewZ=pd)
    final wMid = toIso(pw / 2, 0, pd);
    _paintDimLabel(
      canvas,
      '${(pw * 100).round()}cm',
      Offset(wMid.dx, wMid.dy + 16),
    );

    // 깊이 라벨 (front-right edge, viewX=pw)
    final dMid = toIso(pw, 0, pd / 2);
    _paintDimLabel(
      canvas,
      '${(pd * 100).round()}cm',
      Offset(dMid.dx + 10, dMid.dy + 8),
    );

    // 높이 라벨
    final hMid = toIso(0, space.h / 2, 0);
    _paintDimLabel(
      canvas,
      '↕${(space.h * 100).round()}cm',
      Offset(hMid.dx + 8, hMid.dy - 6),
    );
  }

  void _paintDimLabel(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0x99FFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  @override
  bool shouldRepaint(covariant IsometricPainter oldDelegate) => true;
}
