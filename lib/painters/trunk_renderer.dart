part of 'isometric_painter.dart';

/// 트렁크 구조물 렌더링 (벽, 바닥, 림, 등받이, 실루엣, 립, 단차, 로고)
extension TrunkRendering on IsometricPainter {
  /// 테이퍼 인셋 (뒷벽이 좁아지는 양, 각 측면)
  double get _taperInset => projW * space.taperRatio / 2;

  /// 트렁크 뒷벽 2개 (view-space) — 테이퍼링 적용
  void drawTrunkWalls(Canvas canvas) {
    final pw = projW;
    final pd = projD;
    final h = space.h;
    final inset = _taperInset;

    final wallStroke = Paint()
      ..color = const Color(0xFF505050)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 왼쪽 뒷벽 (viewX=0, z방향) — 어두운 면
    final leftWall = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..lineTo(toIso(0, h, pd).dx, toIso(0, h, pd).dy)
      ..lineTo(toIso(inset, h, 0).dx, toIso(inset, h, 0).dy)
      ..close();

    canvas.drawPath(
      leftWall,
      Paint()
        ..color = const Color(0xFF2A2825)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(leftWall, wallStroke);

    // S9: 왼쪽 벽 높이 그라데이션 (상단 밝음 → 하단 어두움)
    canvas.drawPath(
      leftWall,
      Paint()
        ..shader = ui.Gradient.linear(
          toIso(inset / 2, h, pd / 2),
          toIso(inset / 2, 0, pd / 2),
          [const Color(0x00000000), const Color(0x18000000)],
        )
        ..style = PaintingStyle.fill,
    );

    // 오른쪽 뒷벽 (viewZ=0, x방향) — 밝은 면
    final rightWall = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(toIso(pw - inset, 0, 0).dx, toIso(pw - inset, 0, 0).dy)
      ..lineTo(toIso(pw - inset, h, 0).dx, toIso(pw - inset, h, 0).dy)
      ..lineTo(toIso(inset, h, 0).dx, toIso(inset, h, 0).dy)
      ..close();

    canvas.drawPath(
      rightWall,
      Paint()
        ..color = const Color(0xFF3A3835)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(rightWall, wallStroke);

    // S9: 오른쪽 벽 높이 그라데이션
    canvas.drawPath(
      rightWall,
      Paint()
        ..shader = ui.Gradient.linear(
          toIso(pw / 2, h, 0),
          toIso(pw / 2, 0, 0),
          [const Color(0x00000000), const Color(0x18000000)],
        )
        ..style = PaintingStyle.fill,
    );

    // S8: 벽면 직물/트림 질감 — 가는 수평 패턴
    final wallMinorPaint = Paint()
      ..color = const Color(0x12FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final wallMajorPaint = Paint()
      ..color = const Color(0x28FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    const wallUnit = 0.10;
    const wallMajorUnit = 0.50;

    for (double py = wallUnit; py < h - 0.001; py += wallUnit) {
      final isMajor =
          (py / wallMajorUnit - (py / wallMajorUnit).round()).abs() < 0.001;
      final paint = isMajor ? wallMajorPaint : wallMinorPaint;
      canvas.drawLine(toIso(inset, py, 0), toIso(0, py, pd), paint);
      canvas.drawLine(
          toIso(inset, py, 0), toIso(pw - inset, py, 0), paint);
    }

    // S8: 벽면 미세 직물 패턴 (2cm 간격 세밀 수평선)
    final fabricPaint = Paint()
      ..color = const Color(0x08FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    for (double py = 0.02; py < h - 0.001; py += 0.02) {
      // 10cm 단위와 겹치지 않을 때만
      if ((py * 10).round() % 1 == 0 && (py * 100).round() % 10 != 0) {
        canvas.drawLine(toIso(inset, py, 0), toIso(0, py, pd), fabricPaint);
        canvas.drawLine(
            toIso(inset, py, 0), toIso(pw - inset, py, 0), fabricPaint);
      }
    }

    // 벽면 수직 패딩 라인
    final vertPaint = Paint()
      ..color = const Color(0x10FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    const vertUnit = 0.10;
    for (double pz = vertUnit; pz < pd - 0.001; pz += vertUnit) {
      final t = pz / pd;
      final xAtZ = inset * (1 - t);
      canvas.drawLine(
          toIso(xAtZ, 0, pz), toIso(xAtZ, h, pz), vertPaint);
    }
    for (double px = vertUnit; px < (pw - 2 * inset) - 0.001; px += vertUnit) {
      canvas.drawLine(
          toIso(inset + px, 0, 0), toIso(inset + px, h, 0), vertPaint);
    }
  }

  /// 뒷좌석 등받이 — 뒷벽(viewZ=0)에 오버레이, 테이퍼 반영
  void drawSeatBackrest(Canvas canvas) {
    final pw = projW;
    final h = space.h;
    final inset = _taperInset;
    final tilt = h * 0.04;

    final backrestFill = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(
          toIso(pw - inset, 0, 0).dx, toIso(pw - inset, 0, 0).dy)
      ..lineTo(toIso(pw - inset, h, tilt).dx,
          toIso(pw - inset, h, tilt).dy)
      ..lineTo(toIso(inset, h, tilt).dx, toIso(inset, h, tilt).dy)
      ..close();

    canvas.drawPath(
      backrestFill,
      Paint()
        ..color = const Color(0xFF434038)
        ..style = PaintingStyle.fill,
    );

    // S8: 등받이 직물 질감 (시트 패브릭) — 더 거친 패딩 격자
    final fabricPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const padUnit = 0.10;
    for (double py = padUnit; py < h - 0.001; py += padUnit) {
      final t = py / h;
      final z = tilt * t;
      canvas.drawLine(
          toIso(inset, py, z), toIso(pw - inset, py, z), fabricPaint);
    }
    final backrestW = pw - 2 * inset;
    for (double px = padUnit; px < backrestW - 0.001; px += padUnit) {
      canvas.drawLine(
          toIso(inset + px, 0, 0), toIso(inset + px, h, tilt), fabricPaint);
    }

    // S8: 등받이 퀼팅 패턴 (대각선) — 시트 직물 차별화
    final quiltPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    for (double offset = 0.05; offset < backrestW + h; offset += 0.08) {
      // 좌하 → 우상 대각선
      final startX = math.min(offset, backrestW);
      final startY = math.max(0.0, offset - backrestW);
      final endY = math.min(offset, h);
      final endX = math.max(0.0, offset - h);
      if (startX > endX && endY > startY) {
        final startZ = tilt * (startY / h);
        final endZ = tilt * (endY / h);
        canvas.drawLine(
          toIso(inset + startX, startY, startZ),
          toIso(inset + endX, endY, endZ),
          quiltPaint,
        );
      }
    }

    // 분할선 렌더링
    final splitRatio = space.seatSplitRatio;
    if (splitRatio != null && splitRatio.length >= 2) {
      final splitPaint = Paint()
        ..color = const Color(0xFF1A1816)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      final splitGlowPaint = Paint()
        ..color = const Color(0x30000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round;

      double cumulative = 0;
      for (int i = 0; i < splitRatio.length - 1; i++) {
        cumulative += splitRatio[i];
        final splitX = inset + backrestW * cumulative;
        canvas.drawLine(
          toIso(splitX, 0.01, 0),
          toIso(splitX, h - 0.01, tilt),
          splitGlowPaint,
        );
        canvas.drawLine(
          toIso(splitX, 0.01, 0),
          toIso(splitX, h - 0.01, tilt),
          splitPaint,
        );
      }
    }

    // 등받이 상단 모서리
    canvas.drawLine(
      toIso(inset, h, tilt),
      toIso(pw - inset, h, tilt),
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  /// 트렁크 리드(뚜껑) 실루엣
  void drawTrunkLidSilhouette(Canvas canvas) {
    final opacity = ((1.5 - zoomLevel) / 0.5).clamp(0.0, 1.0) * 0.12;
    if (opacity < 0.01) return;

    final pw = projW;
    final pd = projD;
    final h = space.h;

    final alpha = (opacity * 255).round();
    final silhouetteColor = Color.fromARGB(alpha, 0x88, 0x88, 0x88);

    final archHeight = h * 0.5;
    final archDepth = pd * 0.3;

    final rightTop = toIso(pw, h, 0);
    final leftTop = toIso(0, h, pd);
    final frontCorner = toIso(pw, h, pd);

    final archApex = toIso(pw * 0.5, h + archHeight, pd + archDepth);

    final lidPath = Path()
      ..moveTo(leftTop.dx, leftTop.dy)
      ..cubicTo(
        toIso(0, h + archHeight * 0.6, pd + archDepth * 0.5).dx,
        toIso(0, h + archHeight * 0.6, pd + archDepth * 0.5).dy,
        toIso(pw * 0.3, h + archHeight, pd + archDepth).dx,
        toIso(pw * 0.3, h + archHeight, pd + archDepth).dy,
        archApex.dx,
        archApex.dy,
      )
      ..cubicTo(
        toIso(pw * 0.7, h + archHeight, pd + archDepth).dx,
        toIso(pw * 0.7, h + archHeight, pd + archDepth).dy,
        toIso(pw, h + archHeight * 0.6, pd + archDepth * 0.5).dx,
        toIso(pw, h + archHeight * 0.6, pd + archDepth * 0.5).dy,
        rightTop.dx,
        rightTop.dy,
      );

    canvas.drawPath(
      lidPath,
      Paint()
        ..color = silhouetteColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    final pillarPaint = Paint()
      ..color = silhouetteColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      toIso(0, h, pd),
      toIso(0, h + archHeight * 0.15, pd + archDepth * 0.08),
      pillarPaint,
    );
    canvas.drawLine(
      toIso(pw, h, 0),
      toIso(pw, h + archHeight * 0.15, archDepth * 0.08),
      pillarPaint,
    );
    canvas.drawLine(
      frontCorner,
      toIso(pw, h + archHeight * 0.2, pd + archDepth * 0.1),
      pillarPaint,
    );
  }

  /// S3: 트렁크 3D 립 + 상단 림 + 수직 엣지 — 테이퍼 반영
  void drawTrunkRim(Canvas canvas) {
    final pw = projW;
    final pd = projD;
    final h = space.h;
    final inset = _taperInset;
    const lipT = 0.025; // 2.5cm lip thickness

    // 메탈릭 립 색상
    const lipTopColor = Color(0xFFA0A0A0);
    const lipFrontColor = Color(0xFF808080);
    const lipSideColor = Color(0xFF606060);

    final lipStroke = Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // === Front lip bar (z=pd edge, x=0 to x=pw) ===
    // Front face (facing viewer, at z=pd+lipT)
    _drawQuadFace(canvas, [
      toIso(0, 0, pd + lipT),
      toIso(pw, 0, pd + lipT),
      toIso(pw, h, pd + lipT),
      toIso(0, h, pd + lipT),
    ], lipFrontColor, lipStroke);

    // Top face of front lip
    _drawQuadFace(canvas, [
      toIso(0, h, pd),
      toIso(pw, h, pd),
      toIso(pw, h, pd + lipT),
      toIso(0, h, pd + lipT),
    ], lipTopColor, lipStroke);

    // S10: Front lip top highlight gradient
    final frontLipTopPath = Path()
      ..moveTo(toIso(0, h, pd).dx, toIso(0, h, pd).dy)
      ..lineTo(toIso(pw, h, pd).dx, toIso(pw, h, pd).dy)
      ..lineTo(toIso(pw, h, pd + lipT).dx, toIso(pw, h, pd + lipT).dy)
      ..lineTo(toIso(0, h, pd + lipT).dx, toIso(0, h, pd + lipT).dy)
      ..close();
    canvas.drawPath(
      frontLipTopPath,
      Paint()
        ..shader = ui.Gradient.linear(
          toIso(pw / 2, h, pd),
          toIso(pw / 2, h, pd + lipT),
          [const Color(0x50FFFFFF), const Color(0x10FFFFFF)],
        )
        ..style = PaintingStyle.fill,
    );

    // === Right lip bar (right edge, from back to front) ===
    // Outer face
    _drawQuadFace(canvas, [
      toIso(pw - inset + lipT, 0, 0),
      toIso(pw + lipT, 0, pd),
      toIso(pw + lipT, h, pd),
      toIso(pw - inset + lipT, h, 0),
    ], lipSideColor, lipStroke);

    // Top face of right lip
    _drawQuadFace(canvas, [
      toIso(pw - inset, h, 0),
      toIso(pw, h, pd),
      toIso(pw + lipT, h, pd),
      toIso(pw - inset + lipT, h, 0),
    ], lipTopColor, lipStroke);

    // S10: Right lip top highlight gradient
    final rightLipTopPath = Path()
      ..moveTo(toIso(pw - inset, h, 0).dx, toIso(pw - inset, h, 0).dy)
      ..lineTo(toIso(pw, h, pd).dx, toIso(pw, h, pd).dy)
      ..lineTo(toIso(pw + lipT, h, pd).dx, toIso(pw + lipT, h, pd).dy)
      ..lineTo(
          toIso(pw - inset + lipT, h, 0).dx, toIso(pw - inset + lipT, h, 0).dy)
      ..close();
    canvas.drawPath(
      rightLipTopPath,
      Paint()
        ..shader = ui.Gradient.linear(
          toIso(pw / 2, h, pd / 2),
          toIso(pw / 2 + lipT, h, pd / 2),
          [const Color(0x50FFFFFF), const Color(0x10FFFFFF)],
        )
        ..style = PaintingStyle.fill,
    );

    // === 뒷벽 상단 림 (기존) ===
    final rimPaint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(toIso(inset, h, 0), toIso(0, h, pd), rimPaint);
    canvas.drawLine(
        toIso(inset, h, 0), toIso(pw - inset, h, 0), rimPaint);

    // S10: 뒷벽 상단 하이라이트 스트립
    final highlightPaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(toIso(inset, h, 0), toIso(0, h, pd), highlightPaint);
    canvas.drawLine(
        toIso(inset, h, 0), toIso(pw - inset, h, 0), highlightPaint);

    // 수직 엣지
    final edgePaint = Paint()
      ..color = const Color(0xFF888888)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        toIso(inset, 0, 0), toIso(inset, h, 0), edgePaint);
    canvas.drawLine(toIso(0, 0, pd), toIso(0, h, pd), edgePaint);
    canvas.drawLine(
        toIso(pw - inset, 0, 0), toIso(pw - inset, h, 0), edgePaint);
  }

  /// 트렁크 바닥 — 테이퍼링 + 앰비언트 라이팅 + 질감 + 로고
  void drawTrunkFloor(Canvas canvas) {
    final pw = projW;
    final pd = projD;
    final inset = _taperInset;

    // 사다리꼴 바닥
    final path = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(
          toIso(pw - inset, 0, 0).dx, toIso(pw - inset, 0, 0).dy)
      ..lineTo(toIso(pw, 0, pd).dx, toIso(pw, 0, pd).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2D2A27)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF5A5550)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 벽-바닥 접합선
    final junctionPaint = Paint()
      ..color = const Color(0xFF0E0C0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(toIso(inset, 0, 0), toIso(0, 0, pd), junctionPaint);
    canvas.drawLine(toIso(inset, 0, 0),
        toIso(pw - inset, 0, 0), junctionPaint);

    // 바닥 앞쪽 림 하이라이트
    final rimHighlight = Paint()
      ..color = const Color(0xFF666666)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawLine(
        toIso(pw - inset, 0, 0), toIso(pw, 0, pd), rimHighlight);
    canvas.drawLine(toIso(0, 0, pd), toIso(pw, 0, pd), rimHighlight);

    // 앰비언트 오클루전 스트립
    final aoDepth = 0.06;
    final aoPaint = Paint()
      ..color = const Color(0x50000000)
      ..style = PaintingStyle.fill;

    final leftAo = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(toIso(0, 0, pd).dx, toIso(0, 0, pd).dy)
      ..lineTo(toIso(aoDepth, 0, pd).dx, toIso(aoDepth, 0, pd).dy)
      ..lineTo(toIso(inset + aoDepth, 0, 0).dx,
          toIso(inset + aoDepth, 0, 0).dy)
      ..close();
    canvas.drawPath(leftAo, aoPaint);

    final rightAo = Path()
      ..moveTo(toIso(inset, 0, 0).dx, toIso(inset, 0, 0).dy)
      ..lineTo(toIso(pw - inset, 0, 0).dx,
          toIso(pw - inset, 0, 0).dy)
      ..lineTo(toIso(pw - inset, 0, aoDepth).dx,
          toIso(pw - inset, 0, aoDepth).dy)
      ..lineTo(
          toIso(inset, 0, aoDepth).dx, toIso(inset, 0, aoDepth).dy)
      ..close();
    canvas.drawPath(rightAo, aoPaint);

    // S8: 바닥 고무 매트 홈 패턴 (세로 방향 홈)
    final groovePaint = Paint()
      ..color = const Color(0x0A000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double gz = 0.03; gz < pd; gz += 0.03) {
      final t = gz / pd;
      final xStart = inset * (1 - t);
      final xEnd = pw - inset * (1 - t);
      canvas.drawLine(toIso(xStart, 0, gz), toIso(xEnd, 0, gz), groovePaint);
    }

    // S8: 바닥 카페트/고무 매트 점 패턴 (다양한 크기)
    final dotPaint = Paint()
      ..color = const Color(0x12000000)
      ..style = PaintingStyle.fill;
    final dotPaintSmall = Paint()
      ..color = const Color(0x08000000)
      ..style = PaintingStyle.fill;
    const dotStep = 0.05;
    for (double dx = dotStep; dx < pw; dx += dotStep) {
      for (double dz = dotStep; dz < pd; dz += dotStep) {
        final p = toIso(dx, 0, dz);
        canvas.drawCircle(p, 1.2, dotPaint);
      }
    }
    // 오프셋된 작은 점 패턴
    for (double dx = dotStep / 2; dx < pw; dx += dotStep) {
      for (double dz = dotStep / 2; dz < pd; dz += dotStep) {
        final p = toIso(dx, 0, dz);
        canvas.drawCircle(p, 0.6, dotPaintSmall);
      }
    }

    // S9: 바닥 앰비언트 라이팅 그라데이션 (앞쪽 밝음 → 뒤쪽 어두움)
    final gradPath = Path()
      ..moveTo(toIso(inset, 0.001, 0).dx, toIso(inset, 0.001, 0).dy)
      ..lineTo(
          toIso(pw - inset, 0.001, 0).dx, toIso(pw - inset, 0.001, 0).dy)
      ..lineTo(toIso(pw, 0.001, pd).dx, toIso(pw, 0.001, pd).dy)
      ..lineTo(toIso(0, 0.001, pd).dx, toIso(0, 0.001, pd).dy)
      ..close();
    canvas.drawPath(
      gradPath,
      Paint()
        ..shader = ui.Gradient.linear(
          toIso(pw / 2, 0.001, pd),
          toIso(pw / 2, 0.001, 0),
          [const Color(0x00000000), const Color(0x14000000)],
        )
        ..style = PaintingStyle.fill,
    );
  }

  /// S4: 바닥 단차 (문턱 근처 threshold strip)
  void drawFloorStep(Canvas canvas) {
    final pw = projW;
    final pd = projD;
    const stepH = 0.015; // 1.5cm step height
    const stepD = 0.04; // 4cm step depth
    final stepStart = pd - stepD;

    final stepStroke = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // 단차 윗면 (밝은 톤)
    _drawQuadFace(
      canvas,
      [
        toIso(0, stepH, stepStart),
        toIso(pw, stepH, stepStart),
        toIso(pw, stepH, pd),
        toIso(0, stepH, pd),
      ],
      const Color(0xFF3A3836),
      stepStroke,
    );

    // 단차 앞면 (어두운 톤)
    _drawQuadFace(
      canvas,
      [
        toIso(0, 0, stepStart),
        toIso(pw, 0, stepStart),
        toIso(pw, stepH, stepStart),
        toIso(0, stepH, stepStart),
      ],
      const Color(0xFF302E2B),
      stepStroke,
    );

    // 단차 상단 하이라이트
    canvas.drawLine(
      toIso(0, stepH, stepStart),
      toIso(pw, stepH, stepStart),
      Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  /// S11: 바닥 차종 로고 (미세 양각 텍스트)
  void drawFloorLogo(Canvas canvas) {
    final name = space.vehicleName;
    if (name == null) return;

    final pw = projW;
    final pd = projD;
    final center = toIso(pw / 2, 0.002, pd / 2);

    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0x0FFFFFFF), // ~6% opacity
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 3.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  /// Helper: draw a filled quad face with stroke
  void _drawQuadFace(
      Canvas canvas, List<Offset> pts, Color fill, Paint stroke) {
    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill);
    canvas.drawPath(path, stroke);
  }
}
