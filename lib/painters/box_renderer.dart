part of 'isometric_painter.dart';

/// 박스 및 휠하우스 렌더링
extension BoxRendering on IsometricPainter {
  void drawIsometricBox(
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
    bool isSelected = false,
    BoxCategory category = BoxCategory.custom,
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
    final topColorBright = Color.lerp(fillColor, Colors.white, 0.05)!;
    final rightColor = Color.lerp(fillColor, Colors.black, 0.35)!;
    final rightColorBright = Color.lerp(fillColor, Colors.black, 0.30)!;
    final leftColor = Color.lerp(fillColor, Colors.black, 0.58)!;
    final leftColorBright = Color.lerp(fillColor, Colors.black, 0.53)!;

    final leftPath = roundedPath([p3, p7, p6, p2]);
    final rightPath = roundedPath([p1, p5, p6, p2]);
    final topPath = roundedPath([p4, p5, p6, p7]);

    // 1. 왼쪽 면 (z+d)
    final leftMidTop = Offset((p7.dx + p6.dx) / 2, (p7.dy + p6.dy) / 2);
    final leftMidBot = Offset((p3.dx + p2.dx) / 2, (p3.dy + p2.dy) / 2);
    fill.shader = ui.Gradient.linear(
        leftMidTop, leftMidBot, [leftColorBright, leftColor]);
    canvas.drawPath(leftPath, fill);
    // 2. 오른쪽 면 (x+w)
    final rightMidTop = Offset((p5.dx + p6.dx) / 2, (p5.dy + p6.dy) / 2);
    final rightMidBot = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    fill.shader = ui.Gradient.linear(
        rightMidTop, rightMidBot, [rightColorBright, rightColor]);
    canvas.drawPath(rightPath, fill);
    // 3. 윗면
    final topMidBack = Offset((p4.dx + p5.dx) / 2, (p4.dy + p5.dy) / 2);
    final topMidFront = Offset((p7.dx + p6.dx) / 2, (p7.dy + p6.dy) / 2);
    fill.shader = ui.Gradient.linear(
        topMidBack, topMidFront, [topColor, topColorBright]);
    canvas.drawPath(topPath, fill);

    fill.shader = null;

    // 외곽 헥사곤
    final edgeColor = Color.lerp(fillColor, Colors.black, 0.65)!;
    final hexOutline = roundedPath([p4, p5, p1, p2, p3, p7]);

    canvas.drawPath(
      hexOutline,
      Paint()
        ..color = Color.lerp(fillColor, Colors.black, 0.35)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeJoin = StrokeJoin.round,
    );
    // 3개 면 다시 채우기 (그라데이션)
    fill.shader = ui.Gradient.linear(
        leftMidTop, leftMidBot, [leftColorBright, leftColor]);
    canvas.drawPath(leftPath, fill);
    fill.shader = ui.Gradient.linear(
        rightMidTop, rightMidBot, [rightColorBright, rightColor]);
    canvas.drawPath(rightPath, fill);
    fill.shader = ui.Gradient.linear(
        topMidBack, topMidFront, [topColor, topColorBright]);
    canvas.drawPath(topPath, fill);

    fill.shader = null;

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

    // 선택 글로우 효과
    if (isSelected) {
      canvas.drawPath(
        hexOutline,
        Paint()
          ..color = const Color(0x664DA3FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 6
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6),
      );
    }

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

    // 카테고리별 텍스처
    if (category != BoxCategory.custom) {
      drawBoxTexture(canvas, category, x, y + h, z, w, d, fillColor);
    }
  }

  /// 휠하우스 상단면에 미세한 카페트 텍스처
  void drawWheelhouseTexture(
      Canvas canvas, double vx, double y, double vz, double vw, double vd) {
    final texPaint = Paint()
      ..color = const Color(0x20000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    const step = 0.03;
    for (double x = step; x < vw; x += step) {
      canvas.drawLine(
          toIso(vx + x, y, vz), toIso(vx + x, y, vz + vd), texPaint);
    }
    for (double z = step; z < vd; z += step) {
      canvas.drawLine(
          toIso(vx, y, vz + z), toIso(vx + vw, y, vz + z), texPaint);
    }
  }

  /// 카테고리별 텍스처 렌더링 (윗면 + 오른쪽면)
  void drawBoxTexture(Canvas canvas, BoxCategory category, double x,
      double topY, double z, double w, double d, Color baseColor) {
    // 윗면 아이소 투영 폭이 30px 미만이면 텍스처 생략
    final isoWidth = (toIso(x + w, topY, z).dx - toIso(x, topY, z + d).dx).abs();
    if (isoWidth < 30) return;

    switch (category) {
      case BoxCategory.carrier:
        _drawCarrierTexture(canvas, x, topY, z, w, d, baseColor);
      case BoxCategory.moving:
        _drawMovingTexture(canvas, x, topY, z, w, d, baseColor);
      case BoxCategory.camping:
        _drawCampingTexture(canvas, x, topY, z, w, d, baseColor);
      case BoxCategory.custom:
        break;
    }
  }

  /// 캐리어: 윗면 4코너 원(바퀴), 오른쪽면 상단 수평선+사각(손잡이)
  void _drawCarrierTexture(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final wheelColor = Color.lerp(baseColor, Colors.black, 0.45)!;
    final wheelPaint = Paint()
      ..color = wheelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 윗면 4코너 바퀴 (코너에서 안쪽 15%)
    final inW = w * 0.15;
    final inD = d * 0.15;
    final wheelR = math.min(w, d) * 0.08 * scale;

    final corners = [
      toIso(x + inW, topY, z + inD),
      toIso(x + w - inW, topY, z + inD),
      toIso(x + w - inW, topY, z + d - inD),
      toIso(x + inW, topY, z + d - inD),
    ];
    for (final c in corners) {
      canvas.drawCircle(c, wheelR, wheelPaint);
      canvas.drawCircle(
        c,
        wheelR * 0.4,
        Paint()
          ..color = wheelColor
          ..style = PaintingStyle.fill,
      );
    }

    // 오른쪽면 (x+w) 상단 손잡이: 수평선 + 작은 사각
    final handleColor = Color.lerp(baseColor, Colors.black, 0.30)!;
    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final handleY = topY - (topY > 0 ? math.min(0.05, topY * 0.2) : 0);
    canvas.drawLine(
      toIso(x + w, handleY, z + d * 0.3),
      toIso(x + w, handleY, z + d * 0.7),
      handlePaint,
    );
  }

  /// 이사박스: 윗면 십자 라인(테이프), 20% 밝은 톤
  void _drawMovingTexture(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final tapeColor = Color.lerp(baseColor, Colors.white, 0.20)!;
    final tapePaint = Paint()
      ..color = tapeColor.withAlpha(0xAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // 십자: 가로 + 세로 중앙선
    canvas.drawLine(
      toIso(x, topY, z + d / 2),
      toIso(x + w, topY, z + d / 2),
      tapePaint,
    );
    canvas.drawLine(
      toIso(x + w / 2, topY, z),
      toIso(x + w / 2, topY, z + d),
      tapePaint,
    );
  }

  /// 캠핑: 윗면 X자 대각선(스트랩), 25% 어두운 톤
  void _drawCampingTexture(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final strapColor = Color.lerp(baseColor, Colors.black, 0.25)!;
    final strapPaint = Paint()
      ..color = strapColor.withAlpha(0xAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // X자 대각선
    canvas.drawLine(
      toIso(x, topY, z),
      toIso(x + w, topY, z + d),
      strapPaint,
    );
    canvas.drawLine(
      toIso(x + w, topY, z),
      toIso(x, topY, z + d),
      strapPaint,
    );
  }

  /// 선택된 박스 치수 라벨
  void drawBoxLabelAt(Canvas canvas, TrimBox box,
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

  /// 비선택 박스 이름 라벨
  void drawBoxNameLabelAt(Canvas canvas, TrimBox box,
      ({double vx, double vz, double vw, double vd}) vb) {
    final center = toIso(
      vb.vx + vb.vw / 2,
      box.y + box.h,
      vb.vz + vb.vd / 2,
    );

    final topArea = vb.vw * vb.vd;
    final double fontSize;
    if (topArea < 0.04) {
      fontSize = 9;
    } else if (topArea > 0.16) {
      fontSize = 13;
    } else {
      fontSize = 11;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: box.label,
        style: TextStyle(
          color: const Color(0xEEFFFFFF),
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final isoTopWidth = (toIso(vb.vx + vb.vw, box.y + box.h, vb.vz).dx -
            toIso(vb.vx, box.y + box.h, vb.vz + vb.vd).dx)
        .abs();
    if (tp.width > isoTopWidth) return;

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

  /// 휠하우스 전용 렌더링 — 둥근 모서리 + 약간의 역사다리꼴
  void drawWheelhouse(
    Canvas canvas, {
    required double x,
    required double z,
    required double w,
    required double h,
    required double d,
    required Color fillColor,
    required Color strokeColor,
  }) {
    // 역사다리꼴: 상단이 약간 안쪽 (~1cm)
    final topInset = 0.01;

    // 바닥 꼭짓점 (y=0)
    final b1 = toIso(x + w, 0, z);
    final b2 = toIso(x + w, 0, z + d);
    final b3 = toIso(x, 0, z + d);

    // 상단 꼭짓점 (y=h, 약간 안쪽)
    final t0 = toIso(x + topInset, h, z + topInset);
    final t1 = toIso(x + w - topInset, h, z + topInset);
    final t2 = toIso(x + w - topInset, h, z + d - topInset);
    final t3 = toIso(x + topInset, h, z + d - topInset);

    final fill = Paint()..style = PaintingStyle.fill;

    // 바닥 그림자
    final so = 0.01;
    final shadow = Path()
      ..moveTo(toIso(x - so, -0.002, z - so).dx,
          toIso(x - so, -0.002, z - so).dy)
      ..lineTo(toIso(x + w + so, -0.002, z - so).dx,
          toIso(x + w + so, -0.002, z - so).dy)
      ..lineTo(toIso(x + w + so, -0.002, z + d + so).dx,
          toIso(x + w + so, -0.002, z + d + so).dy)
      ..lineTo(toIso(x - so, -0.002, z + d + so).dx,
          toIso(x - so, -0.002, z + d + so).dy)
      ..close();
    canvas.drawPath(
      shadow,
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.fill,
    );

    final topColor = Color.lerp(fillColor, Colors.white, 0.05)!;
    final rightColor = Color.lerp(fillColor, Colors.black, 0.20)!;
    final leftColor = Color.lerp(fillColor, Colors.black, 0.40)!;

    // 왼쪽 면 (z+d 쪽) — 역사다리꼴
    final leftPath = Path()
      ..moveTo(b3.dx, b3.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(t3.dx, t3.dy)
      ..close();
    fill.color = leftColor;
    canvas.drawPath(leftPath, fill);

    // 오른쪽 면 (x+w 쪽) — 역사다리꼴
    final rightPath = Path()
      ..moveTo(b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(t2.dx, t2.dy)
      ..lineTo(t1.dx, t1.dy)
      ..close();
    fill.color = rightColor;
    canvas.drawPath(rightPath, fill);

    // 상단면 (둥근 모서리) — quadraticBezierTo로 라운딩
    final r = 0.03 * scale; // 화면 기준 라운딩 반경
    final topPath = _roundedTopFace(t0, t1, t2, t3, r);
    fill.color = topColor;
    canvas.drawPath(topPath, fill);

    // 외곽선
    final outlinePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round;

    // 헥사곤 외곽
    final hex = Path()
      ..moveTo(t0.dx, t0.dy)
      ..lineTo(t1.dx, t1.dy)
      ..lineTo(b1.dx, b1.dy)
      ..lineTo(b2.dx, b2.dy)
      ..lineTo(b3.dx, b3.dy)
      ..lineTo(t3.dx, t3.dy)
      ..close();
    canvas.drawPath(hex, outlinePaint);

    // 내부 분리선: b2→t2
    canvas.drawLine(b2, t2, outlinePaint);

    // 상단 뒤쪽 엣지
    canvas.drawLine(t0, t1, outlinePaint);
    canvas.drawLine(t0, t3, outlinePaint);

    // S10: 휠하우스 상단 엣지 하이라이트
    final highlightPaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(t0, t1, highlightPaint);
    canvas.drawLine(t1, t2, highlightPaint);
  }

  /// 상단면 4 코너에 둥근 모서리 적용
  Path _roundedTopFace(Offset p0, Offset p1, Offset p2, Offset p3, double r) {
    final points = [p0, p1, p2, p3];
    final n = points.length;
    final path = Path();

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
}
