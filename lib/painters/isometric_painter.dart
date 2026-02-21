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
    canvas.save();
    final center = computeCenter(size, space, scale);
    canvas.translate(center.dx, center.dy);

    // 1. 뒷벽 (가장 뒤, 모든 오브젝트 뒤에)
    _drawTrunkWalls(canvas);
    // 2. 바닥 + 그리드
    _drawTrunkFloor(canvas);
    _drawGrid(canvas);
    // 3. 휠하우스 + 박스 통합 depth sort 렌더링
    _drawObjects(canvas);
    // 4. 트렁크 림/엣지 (맨 앞에 그려서 프레임 역할)
    _drawTrunkRim(canvas);
    // 5. 치수 라벨
    _drawDimensionLabels(canvas);

    canvas.restore();
  }

  /// 트렁크 뒷벽 2개: x=0 면(왼쪽 뒤), z=0 면(오른쪽 뒤)
  void _drawTrunkWalls(Canvas canvas) {
    final w = space.w;
    final d = space.d;
    final h = space.h;

    final wallStroke = Paint()
      ..color = const Color(0xFF505050)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 왼쪽 뒷벽 (x=0 면, z 방향으로 연장) — 어두운 면 (그림자 쪽)
    final leftWall = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(0, 0, d).dx, toIso(0, 0, d).dy)
      ..lineTo(toIso(0, h, d).dx, toIso(0, h, d).dy)
      ..lineTo(toIso(0, h, 0).dx, toIso(0, h, 0).dy)
      ..close();

    canvas.drawPath(
      leftWall,
      Paint()
        ..color = const Color(0xFF252530) // 차분한 차가운 회색 (그림자 쪽)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(leftWall, wallStroke);

    // 오른쪽 뒷벽 (z=0 면, x 방향으로 연장) — 밝은 면 (빛 받는 쪽)
    final rightWall = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(w, 0, 0).dx, toIso(w, 0, 0).dy)
      ..lineTo(toIso(w, h, 0).dx, toIso(w, h, 0).dy)
      ..lineTo(toIso(0, h, 0).dx, toIso(0, h, 0).dy)
      ..close();

    canvas.drawPath(
      rightWall,
      Paint()
        ..color = const Color(0xFF353540) // 중간 밝기 회색 (빛 받는 면)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(rightWall, wallStroke);

    // 벽면 높이 가이드선 (10cm 간격)
    final wallMinorPaint = Paint()
      ..color = const Color(0x15FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final wallMajorPaint = Paint()
      ..color = const Color(0x30FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final wallUnit = space.gridUnit; // 10cm
    final wallMajorUnit = wallUnit * 5; // 50cm

    for (double py = wallUnit; py < h - 0.001; py += wallUnit) {
      final isMajor = (py / wallMajorUnit - (py / wallMajorUnit).round()).abs() < 0.001;
      final paint = isMajor ? wallMajorPaint : wallMinorPaint;
      // 왼쪽 벽 수평선
      canvas.drawLine(toIso(0, py, 0), toIso(0, py, d), paint);
      // 오른쪽 벽 수평선
      canvas.drawLine(toIso(0, py, 0), toIso(w, py, 0), paint);
    }
  }

  /// 트렁크 상단 림과 수직 엣지
  void _drawTrunkRim(Canvas canvas) {
    final w = space.w;
    final d = space.d;
    final h = space.h;

    // 밝은 림 (상단 벽 엣지)
    final rimPaint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // 왼쪽 벽 상단 엣지
    canvas.drawLine(toIso(0, h, 0), toIso(0, h, d), rimPaint);
    // 오른쪽 벽 상단 엣지
    canvas.drawLine(toIso(0, h, 0), toIso(w, h, 0), rimPaint);

    // 수직 코너 엣지 (프레임 느낌)
    final edgePaint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // 뒤쪽 코너 (x=0, z=0)
    canvas.drawLine(toIso(0, 0, 0), toIso(0, h, 0), edgePaint);
    // 앞왼쪽 코너 (x=0, z=d)
    canvas.drawLine(toIso(0, 0, d), toIso(0, h, d), edgePaint);
    // 앞오른쪽 코너 (x=w, z=0)
    canvas.drawLine(toIso(w, 0, 0), toIso(w, h, 0), edgePaint);
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

    // 바닥 면 채우기 (벽보다 밝게 → 바닥/벽 구분으로 입체감)
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF28282E) // 밝은 바닥 (벽과 확실한 대비)
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

    // 벽-바닥 접합선 (어두운 선으로 깊이감)
    final junctionPaint = Paint()
      ..color = const Color(0xFF0A0A0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(toIso(0, 0, 0), toIso(0, 0, d), junctionPaint);
    canvas.drawLine(toIso(0, 0, 0), toIso(w, 0, 0), junctionPaint);

    // 앰비언트 오클루전: 벽-바닥 코너에 어두운 삼각 스트립
    final aoDepth = 0.06; // 바닥 위 AO 범위 (6cm)
    final aoPaint = Paint()
      ..color = const Color(0x50000000)
      ..style = PaintingStyle.fill;

    // 왼쪽 벽 AO (x=0 쪽 바닥)
    final leftAo = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(0, 0, d).dx, toIso(0, 0, d).dy)
      ..lineTo(toIso(aoDepth, 0, d).dx, toIso(aoDepth, 0, d).dy)
      ..lineTo(toIso(aoDepth, 0, 0).dx, toIso(aoDepth, 0, 0).dy)
      ..close();
    canvas.drawPath(leftAo, aoPaint);

    // 오른쪽 벽 AO (z=0 쪽 바닥)
    final rightAo = Path()
      ..moveTo(toIso(0, 0, 0).dx, toIso(0, 0, 0).dy)
      ..lineTo(toIso(w, 0, 0).dx, toIso(w, 0, 0).dy)
      ..lineTo(toIso(w, 0, aoDepth).dx, toIso(w, 0, aoDepth).dy)
      ..lineTo(toIso(0, 0, aoDepth).dx, toIso(0, 0, aoDepth).dy)
      ..close();
    canvas.drawPath(rightAo, aoPaint);
  }

  void _drawGrid(Canvas canvas) {
    final w = space.w;
    final d = space.d;
    final unit = space.gridUnit; // 0.10m = 10cm
    final majorUnit = unit * 5;  // 0.50m = 50cm

    // 10cm 소격자 (가느다란 선)
    final minorPaint = Paint()
      ..color = const Color(0x40999999)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 50cm 대격자 (굵고 밝은 선)
    final majorPaint = Paint()
      ..color = const Color(0x80AAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // X축 방향 그리드
    for (double x = 0; x <= w + 0.001; x += unit) {
      final p1 = toIso(x, 0, 0);
      final p2 = toIso(x, 0, d);
      final isMajor = (x / majorUnit - (x / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(p1, p2, isMajor ? majorPaint : minorPaint);
    }

    // Z축 방향 그리드
    for (double z = 0; z <= d + 0.001; z += unit) {
      final p1 = toIso(0, 0, z);
      final p2 = toIso(w, 0, z);
      final isMajor = (z / majorUnit - (z / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(p1, p2, isMajor ? majorPaint : minorPaint);
    }
  }

  /// 휠하우스 + 박스를 통합 depth sort하여 렌더링
  void _drawObjects(Canvas canvas) {
    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;

    // 모든 렌더 대상을 (depth, drawCallback) 쌍으로 수집
    final List<({double depth, VoidCallback draw})> objects = [];

    // 휠하우스 추가
    final lwX = 0.0;
    final lwZ = space.d - lw.d;
    objects.add((
      depth: (lwX + lw.w / 2) + (lwZ + lw.d / 2),
      draw: () => _drawIsometricBox(
        canvas,
        x: lwX, y: 0, z: lwZ,
        w: lw.w, h: lw.h, d: lw.d,
        fillColor: const Color(0xFFB0B0B0),
        strokeColor: const Color(0xFF777777),
      ),
    ));

    final rwX = space.w - rw.w;
    final rwZ = space.d - rw.d;
    objects.add((
      depth: (rwX + rw.w / 2) + (rwZ + rw.d / 2),
      draw: () => _drawIsometricBox(
        canvas,
        x: rwX, y: 0, z: rwZ,
        w: rw.w, h: rw.h, d: rw.d,
        fillColor: const Color(0xFFB0B0B0),
        strokeColor: const Color(0xFF777777),
      ),
    ));

    // 박스 추가
    for (final box in boxes) {
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
        depth: (box.x + box.effectiveW / 2) + (box.z + box.effectiveD / 2),
        draw: () {
          _drawIsometricBox(
            canvas,
            x: box.x, y: box.y, z: box.z,
            w: box.effectiveW, h: box.h, d: box.effectiveD,
            fillColor: box.color,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
          );
          if (isSelected) {
            _drawBoxLabel(canvas, box);
          } else {
            _drawBoxNameLabel(canvas, box);
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

  /// 씬 중심점 계산 (히트테스트에서도 동일한 좌표계를 사용하기 위해 public static)
  static Offset computeCenter(
      Size size, TrunkSpace space, double scale) {
    final sceneTop = space.h * scale;
    final sceneBottom = (space.w + space.d) * _sinA * scale;
    final sceneHeight = sceneTop + sceneBottom;
    final centerY = (size.height - sceneHeight) / 2 + sceneTop;
    final leftExtent = space.d * _cosA * scale;
    final rightExtent = space.w * _cosA * scale;
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
    // 보이는 7개 꼭짓점 (뷰어 방향: +x, +z → 앞면 표시)
    final p1 = toIso(x + w, y, z);         // 바닥-오른쪽
    final p2 = toIso(x + w, y, z + d);     // 바닥-앞 (정면 꼭짓점)
    final p3 = toIso(x, y, z + d);         // 바닥-왼쪽
    final p4 = toIso(x, y + h, z);         // 윗면-뒤
    final p5 = toIso(x + w, y + h, z);     // 윗면-오른쪽
    final p6 = toIso(x + w, y + h, z + d); // 윗면-앞
    final p7 = toIso(x, y + h, z + d);     // 윗면-왼쪽

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

    // 면 셰이딩 (높은 대비 → 강한 입체감)
    final topColor = fillColor;
    final rightColor = Color.lerp(fillColor, Colors.black, 0.35)!;
    final leftColor = Color.lerp(fillColor, Colors.black, 0.58)!;

    // ── 3개 면 채우기 (fill only, 스트로크 없음) ──
    // 1. 왼쪽 면 = z+d 면 (가장 어둡게, 뷰어에게 보이는 면)
    fill.color = leftColor;
    canvas.drawPath(
      Path()
        ..moveTo(p3.dx, p3.dy)..lineTo(p7.dx, p7.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    // 2. 오른쪽 면 = x+w 면 (중간 밝기, 뷰어에게 보이는 면)
    fill.color = rightColor;
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p2.dx, p2.dy)..close(),
      fill,
    );
    // 3. 윗면 (원색)
    fill.color = topColor;
    canvas.drawPath(
      Path()
        ..moveTo(p4.dx, p4.dy)..lineTo(p5.dx, p5.dy)
        ..lineTo(p6.dx, p6.dy)..lineTo(p7.dx, p7.dy)..close(),
      fill,
    );

    // ── 외곽 헥사곤 (p2가 아래쪽 정면 꼭짓점) ──
    final edgeColor = Color.lerp(fillColor, Colors.black, 0.65)!;
    final hexOutline = Path()
      ..moveTo(p4.dx, p4.dy)..lineTo(p5.dx, p5.dy)
      ..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)..lineTo(p7.dx, p7.dy)..close();

    // 바깥쪽 밝은 테두리 (어두운 배경과 분리) → 안쪽은 면 fill이 덮음
    canvas.drawPath(
      hexOutline,
      Paint()
        ..color = Color.lerp(fillColor, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );
    // 3개 면 다시 채우기 (바깥 테두리의 안쪽 절반을 덮음)
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

    // 어두운 엣지 (면 위에 그려서 면 경계선 역할)
    canvas.drawPath(
      hexOutline,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round,
    );

    // ── 내부 분리선: 앞 기둥 p2→p6 (왼면/오른면 경계) ──
    canvas.drawLine(
      p2, p6,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // ── 윗면 뒤쪽 엣지 (뷰어에서 먼 쪽) ──
    final backEdgePaint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(p5, p4, backEdgePaint);
    canvas.drawLine(p4, p7, backEdgePaint);

    // ── 충돌/선택 외곽선 ──
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

  void _drawBoxLabel(Canvas canvas, TrimBox box) {
    final center = toIso(
      box.x + box.effectiveW / 2,
      box.y + box.h,
      box.z + box.effectiveD / 2,
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

  /// 비선택 박스 위에 짧은 이름 라벨 (배경 포함)
  void _drawBoxNameLabel(Canvas canvas, TrimBox box) {
    final center = toIso(
      box.x + box.effectiveW / 2,
      box.y + box.h,
      box.z + box.effectiveD / 2,
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

  /// 트렁크 치수 라벨 (폭, 깊이)
  void _drawDimensionLabels(Canvas canvas) {
    final w = space.w;
    final d = space.d;

    // 폭 라벨 (바닥 앞쪽 Z=d 엣지, x 방향)
    final wMid = toIso(w / 2, 0, d);
    _paintDimLabel(
      canvas,
      '${(w * 100).round()}cm',
      Offset(wMid.dx, wMid.dy + 16),
    );

    // 깊이 라벨 (바닥 앞쪽 X=w 엣지, z 방향)
    final dMid = toIso(w, 0, d / 2);
    _paintDimLabel(
      canvas,
      '${(d * 100).round()}cm',
      Offset(dMid.dx + 10, dMid.dy + 8),
    );

    // 높이 라벨 (뒤쪽 코너 수직선)
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
