part of 'isometric_painter.dart';

/// Vehicle body exterior rendering — painted panels, tail lights,
/// license plate, bumper contour, and panel gap lines around the trunk opening.
extension VehicleBodyRendering on IsometricPainter {
  void drawOpeningFrame(Canvas canvas) {
    final w = space.w, d = space.d, h = space.h;
    final bodyBaseColor = Color(space.bodyColor);

    // Opening shape: wider at bottom, curved/narrower at top
    final bl = toScreen(0, 0, d);
    final br = toScreen(w, 0, d);

    final topH = space.ceilingHeightAt(d);
    final topNarrow = space.topNarrowAt(d);
    final topTaper = space.taperAt(d);

    // Build curved top edge with multiple points
    const topSegs = 12;
    final topPoints = <Offset>[];
    for (int i = 0; i <= topSegs; i++) {
      final t = i / topSegs;
      final x = (topTaper + topNarrow) + (w - 2 * (topTaper + topNarrow)) * t;
      final archBoost = 0.03 * math.sin(t * math.pi);
      final y = topH + archBoost;
      topPoints.add(toScreen(x, y, d));
    }

    // Build the opening outline path
    final openingPath = Path()..moveTo(bl.dx, bl.dy);
    openingPath.lineTo(br.dx, br.dy);
    final rightMid = toScreen(w, h * 0.5, d);
    openingPath.lineTo(rightMid.dx, rightMid.dy);
    openingPath.lineTo(topPoints.last.dx, topPoints.last.dy);
    for (int i = topSegs - 1; i >= 0; i--) {
      openingPath.lineTo(topPoints[i].dx, topPoints[i].dy);
    }
    final leftMid = toScreen(0, h * 0.5, d);
    openingPath.lineTo(leftMid.dx, leftMid.dy);
    openingPath.close();

    // ── 1. Painted body panel (replaces flat black) ──
    _drawBodyPanel(canvas, openingPath, bodyBaseColor);

    // ── 5. Panel gap lines (tailgate outline) ──
    _drawPanelGapLines(canvas, w, d, h, topH, topNarrow, topTaper);

    // ── 2. Tail lights ──
    _drawTailLights(canvas, w, d, h);

    // ── 3. License plate area ──
    _drawLicensePlate(canvas, w, d);

    // ── 4. Bumper contour ──
    _drawBumperContour(canvas, w, d, bodyBaseColor);

    // ── Rubber seal (thick dark border following the opening shape) ──
    canvas.drawPath(
        openingPath,
        Paint()
          ..color = const Color(0xFF0A0A0A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7.0
          ..strokeJoin = StrokeJoin.round);

    // Metal trim highlight
    canvas.drawPath(
        openingPath,
        Paint()
          ..color = const Color(0xFF666666)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Inner light edge
    canvas.drawPath(
        openingPath,
        Paint()
          ..color = const Color(0x18FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    // Loading sill / bumper lip
    _drawLoadingSill(canvas);
  }

  /// Painted body panel with metallic sheen and radial gradient
  void _drawBodyPanel(Canvas canvas, Path openingPath, Color bodyBaseColor) {
    final screenRect = Rect.fromLTWH(-3000, -3000, 6000, 6000);
    final framePath = Path()
      ..addRect(screenRect)
      ..addPath(openingPath, Offset.zero);
    framePath.fillType = PathFillType.evenOdd;

    // Base body color fill
    canvas.drawPath(
        framePath,
        Paint()
          ..color = bodyBaseColor
          ..style = PaintingStyle.fill);

    // Radial gradient for curvature simulation — lighter at center, darker at edges
    final center = toScreen(space.w / 2, space.h * 0.5, space.d);
    final gradientPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        800.0,
        [
          _lighten(bodyBaseColor, 0.15),
          bodyBaseColor,
          _darken(bodyBaseColor, 0.25),
        ],
        [0.0, 0.4, 1.0],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(framePath, gradientPaint);

    // Subtle horizontal metallic sheen band across the middle
    final sheenRect = Rect.fromCenter(center: center, width: 3000, height: 120);
    canvas.save();
    canvas.clipPath(framePath);
    canvas.drawRect(
        sheenRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(sheenRect.left, sheenRect.top),
            Offset(sheenRect.left, sheenRect.bottom),
            [
              const Color(0x00FFFFFF),
              const Color(0x0AFFFFFF),
              const Color(0x00FFFFFF),
            ],
          )
          ..style = PaintingStyle.fill);
    canvas.restore();
  }

  /// Panel gap lines — thin dark line offset from the opening, suggesting tailgate boundary
  void _drawPanelGapLines(Canvas canvas, double w, double d, double h,
      double topH, double topNarrow, double topTaper) {
    const gap = 0.02; // 2cm offset from opening edge

    // Build offset path around the opening
    final gapBl = toScreen(-gap, -gap, d);
    final gapBr = toScreen(w + gap, -gap, d);
    final gapRightMid = toScreen(w + gap, h * 0.5, d);
    final gapLeftMid = toScreen(-gap, h * 0.5, d);

    const gapSegs = 12;
    final gapTopPoints = <Offset>[];
    for (int i = 0; i <= gapSegs; i++) {
      final t = i / gapSegs;
      final x = (topTaper + topNarrow - gap) +
          (w - 2 * (topTaper + topNarrow - gap)) * t;
      final archBoost = 0.03 * math.sin(t * math.pi);
      final y = topH + archBoost + gap;
      gapTopPoints.add(toScreen(x, y, d));
    }

    final gapPath = Path()..moveTo(gapBl.dx, gapBl.dy);
    gapPath.lineTo(gapBr.dx, gapBr.dy);
    gapPath.lineTo(gapRightMid.dx, gapRightMid.dy);
    gapPath.lineTo(gapTopPoints.last.dx, gapTopPoints.last.dy);
    for (int i = gapSegs - 1; i >= 0; i--) {
      gapPath.lineTo(gapTopPoints[i].dx, gapTopPoints[i].dy);
    }
    gapPath.lineTo(gapLeftMid.dx, gapLeftMid.dy);
    gapPath.close();

    canvas.drawPath(
        gapPath,
        Paint()
          ..color = const Color(0xFF0D0D0D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  /// Tail lights — vertical rounded rectangles on each side
  void _drawTailLights(Canvas canvas, double w, double d, double h) {
    final bodyExtX = space.bodyExtX;
    // Tail light dimensions in world coords
    const lightW = 0.08; // 8cm wide
    const lightH = 0.20; // 20cm tall
    // Position: at outer body edge, 60-80% height (center at 70%)
    final lightCenterY = h * 0.70;
    final lightTop = lightCenterY + lightH / 2;
    final lightBot = lightCenterY - lightH / 2;

    // Left tail light
    final leftX = -bodyExtX + 0.01; // 1cm inset from body edge
    _drawSingleTailLight(canvas, leftX, leftX + lightW, lightBot, lightTop, d);

    // Right tail light
    final rightX = w + bodyExtX - 0.01 - lightW;
    _drawSingleTailLight(
        canvas, rightX, rightX + lightW, lightBot, lightTop, d);
  }

  void _drawSingleTailLight(Canvas canvas, double x0, double x1, double yBot,
      double yTop, double d) {
    final tl = toScreen(x0, yTop, d);
    final tr = toScreen(x1, yTop, d);
    final br = toScreen(x1, yBot, d);
    final bl = toScreen(x0, yBot, d);

    // Glow halo (semi-transparent red, slightly larger)
    final glowPath = buildPath([tl, tr, br, bl]);
    canvas.drawPath(
        glowPath,
        Paint()
          ..color = const Color(0x30FF0000)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Main tail light body — dark red
    canvas.drawPath(
        glowPath,
        Paint()
          ..color = const Color(0xFF8B0000)
          ..style = PaintingStyle.fill);

    // Inner bright accent strip (vertical center line)
    final midX = (x0 + x1) / 2;
    final stripW = (x1 - x0) * 0.3;
    final innerTl = toScreen(midX - stripW / 2, yTop - 0.01, d);
    final innerTr = toScreen(midX + stripW / 2, yTop - 0.01, d);
    final innerBr = toScreen(midX + stripW / 2, yBot + 0.01, d);
    final innerBl = toScreen(midX - stripW / 2, yBot + 0.01, d);
    final innerPath = buildPath([innerTl, innerTr, innerBr, innerBl]);
    canvas.drawPath(
        innerPath,
        Paint()
          ..color = const Color(0xFFAA2222)
          ..style = PaintingStyle.fill);

    // Outline
    canvas.drawPath(
        glowPath,
        Paint()
          ..color = const Color(0xFF440000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
  }

  /// License plate recessed area below the trunk opening
  void _drawLicensePlate(Canvas canvas, double w, double d) {
    // Plate dimensions: 52cm × 11cm, centered horizontally
    const plateW = 0.52;
    const plateH = 0.11;
    // Position: below trunk floor (y < 0), centered
    final plateCX = w / 2;
    const plateTopY = -0.04; // 4cm below trunk floor
    const plateBotY = plateTopY - plateH;

    final tl = toScreen(plateCX - plateW / 2, plateTopY, d);
    final tr = toScreen(plateCX + plateW / 2, plateTopY, d);
    final br = toScreen(plateCX + plateW / 2, plateBotY, d);
    final bl = toScreen(plateCX - plateW / 2, plateBotY, d);

    final platePath = buildPath([tl, tr, br, bl]);

    // Recessed background (darker than body)
    canvas.drawPath(
        platePath,
        Paint()
          ..color = _darken(Color(space.bodyColor), 0.35)
          ..style = PaintingStyle.fill);

    // Plate white area (slightly inset)
    const inset = 0.005;
    final iTl = toScreen(plateCX - plateW / 2 + inset, plateTopY - inset, d);
    final iTr = toScreen(plateCX + plateW / 2 - inset, plateTopY - inset, d);
    final iBr = toScreen(plateCX + plateW / 2 - inset, plateBotY + inset, d);
    final iBl = toScreen(plateCX - plateW / 2 + inset, plateBotY + inset, d);
    final innerPlatePath = buildPath([iTl, iTr, iBr, iBl]);
    canvas.drawPath(
        innerPlatePath,
        Paint()
          ..color = const Color(0xFFE8E8E0)
          ..style = PaintingStyle.fill);

    // Border line
    canvas.drawPath(
        platePath,
        Paint()
          ..color = const Color(0xFF333333)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  /// Bumper contour — horizontal bands with gradually darker color
  void _drawBumperContour(
      Canvas canvas, double w, double d, Color bodyBaseColor) {
    final bodyExtX = space.bodyExtX;
    // Bumper area: below license plate area to the bottom of visibility
    const bumperTop = -0.18; // below trunk floor
    const bandHeight = 0.06; // each band is 6cm
    const numBands = 3;

    for (int i = 0; i < numBands; i++) {
      final bandTopY = bumperTop - i * bandHeight;
      final bandBotY = bandTopY - bandHeight;
      final darkenAmount = 0.10 + i * 0.12;

      final bTl = toScreen(-bodyExtX, bandTopY, d);
      final bTr = toScreen(w + bodyExtX, bandTopY, d);
      final bBr = toScreen(w + bodyExtX, bandBotY, d);
      final bBl = toScreen(-bodyExtX, bandBotY, d);

      final bandPath = buildPath([bTl, bTr, bBr, bBl]);
      canvas.drawPath(
          bandPath,
          Paint()
            ..color = _darken(bodyBaseColor, darkenAmount)
            ..style = PaintingStyle.fill);
    }

    // Reflective highlight line at bottom edge of bumper
    final hlY = bumperTop - numBands * bandHeight;
    final hlLeft = toScreen(-bodyExtX + 0.05, hlY, d);
    final hlRight = toScreen(w + bodyExtX - 0.05, hlY, d);
    canvas.drawLine(
        hlLeft,
        hlRight,
        Paint()
          ..color = const Color(0x30FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Thin separator line between bumper bands for texture
    for (int i = 1; i < numBands; i++) {
      final lineY = bumperTop - i * bandHeight;
      final lLeft = toScreen(-bodyExtX + 0.02, lineY, d);
      final lRight = toScreen(w + bodyExtX - 0.02, lineY, d);
      canvas.drawLine(
          lLeft,
          lRight,
          Paint()
            ..color = const Color(0x18000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }
  }

  /// Loading sill / bumper lip — the horizontal ledge at the bottom of the trunk opening
  void _drawLoadingSill(Canvas canvas) {
    final w = space.w, d = space.d;
    const sillH = 0.04; // 4cm tall sill
    const sillD = 0.06; // 6cm deep

    // Top face of sill
    _drawSillFace(canvas, [
      toScreen(0, sillH, d - sillD),
      toScreen(w, sillH, d - sillD),
      toScreen(w, sillH, d),
      toScreen(0, sillH, d),
    ], const Color(0xFF4A4845));

    // Front face of sill (faces camera)
    _drawSillFace(canvas, [
      toScreen(0, 0, d),
      toScreen(w, 0, d),
      toScreen(w, sillH, d),
      toScreen(0, sillH, d),
    ], const Color(0xFF3A3836));

    // Inner face of sill (faces into trunk)
    _drawSillFace(canvas, [
      toScreen(0, 0, d - sillD),
      toScreen(w, 0, d - sillD),
      toScreen(w, sillH, d - sillD),
      toScreen(0, sillH, d - sillD),
    ], const Color(0xFF333130));

    // Chrome/metal strip highlight on top edge
    canvas.drawLine(
      toScreen(0, sillH, d),
      toScreen(w, sillH, d),
      Paint()
        ..color = const Color(0xFF888888)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawSillFace(Canvas canvas, List<Offset> pts, Color color) {
    final path = buildPath(pts);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  // ── Color utility helpers ──

  Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }
}
