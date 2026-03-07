part of 'isometric_painter.dart';

/// Trunk interior rendering — walls, floor, ceiling, seat backrest
/// Supports curved ceiling (ceilingDrop), C-pillar narrowing (rearTopNarrow),
/// and bottom taper (taperRatio) for realistic car trunk shapes.
extension TrunkRendering on IsometricPainter {
  static const int _shapeSegs = 10;

  // ── Shape helpers ──

  /// Left wall X at bottom for depth z
  double _wallLeftBot(double z) => space.taperAt(z);

  /// Right wall X at bottom for depth z
  double _wallRightBot(double z) => space.w - space.taperAt(z);

  /// Left wall X at ceiling for depth z
  double _wallLeftTop(double z) =>
      space.taperAt(z) + space.topNarrowAt(z);

  /// Right wall X at ceiling for depth z
  double _wallRightTop(double z) =>
      space.w - space.taperAt(z) - space.topNarrowAt(z);

  /// Ceiling height at depth z
  double _ceilH(double z) => space.ceilingHeightAt(z);

  // ── Ceiling ──
  void drawTrunkCeiling(Canvas canvas) {
    final d = space.d;
    final hasCurve =
        space.ceilingDrop > 0 || space.rearTopNarrow > 0;

    if (!hasCurve) {
      // Legacy flat ceiling
      final inset = space.w * space.taperRatio / 2;
      _drawQuadFace(canvas, [
        toScreen(inset, space.h, 0),
        toScreen(space.w - inset, space.h, 0),
        toScreen(space.w, space.h, d),
        toScreen(0, space.h, d),
      ], const Color(0xFF222020));
      return;
    }

    for (int i = 0; i < _shapeSegs; i++) {
      final t0 = i / _shapeSegs;
      final t1 = (i + 1) / _shapeSegs;
      final z0 = d * t0, z1 = d * t1;

      final ch0 = _ceilH(z0), ch1 = _ceilH(z1);
      final lt0 = _wallLeftTop(z0), lt1 = _wallLeftTop(z1);
      final rt0 = _wallRightTop(z0), rt1 = _wallRightTop(z1);

      // Slight color variation: darker toward back
      // Warmer/brighter near opening (high t = near opening)
      final warmShift = t0 * 0.12; // brighter toward opening
      final shade = Color.lerp(
          const Color(0xFF222020), const Color(0xFF3A3530), warmShift)!;

      _drawQuadFace(canvas, [
        toScreen(lt0, ch0, z0),
        toScreen(rt0, ch0, z0),
        toScreen(rt1, ch1, z1),
        toScreen(lt1, ch1, z1),
      ], shade);
    }
  }

  // ── Side walls ──
  void drawTrunkWalls(Canvas canvas) {
    final d = space.d;
    final hasCurve =
        space.ceilingDrop > 0 || space.rearTopNarrow > 0;

    if (!hasCurve) {
      _drawLegacyWalls(canvas);
      return;
    }

    for (int i = 0; i < _shapeSegs; i++) {
      final t0 = i / _shapeSegs;
      final t1 = (i + 1) / _shapeSegs;
      final z0 = d * t0, z1 = d * t1;

      final ch0 = _ceilH(z0), ch1 = _ceilH(z1);
      final lb0 = _wallLeftBot(z0), lb1 = _wallLeftBot(z1);
      final lt0 = _wallLeftTop(z0), lt1 = _wallLeftTop(z1);
      final rb0 = _wallRightBot(z0), rb1 = _wallRightBot(z1);
      final rt0 = _wallRightTop(z0), rt1 = _wallRightTop(z1);

      final shade = Color.lerp(
          const Color(0xFF2A2825), const Color(0xFF1E1C1A), (1 - t0) * 0.4)!;

      // Left wall segment
      _drawQuadFace(canvas, [
        toScreen(lb0, 0, z0),
        toScreen(lb1, 0, z1),
        toScreen(lt1, ch1, z1),
        toScreen(lt0, ch0, z0),
      ], shade);

      // Left wall plastic grain lines
      _drawWallGrainLines(canvas, lb0, lb1, lt0, lt1, ch0, ch1, z0, z1);

      // Right wall segment
      _drawQuadFace(canvas, [
        toScreen(rb1, 0, z1),
        toScreen(rb0, 0, z0),
        toScreen(rt0, ch0, z0),
        toScreen(rt1, ch1, z1),
      ], shade);

      // Right wall plastic grain lines
      _drawWallGrainLines(canvas, rb0, rb1, rt0, rt1, ch0, ch1, z0, z1);
    }

    // Ceiling-wall junction lines (ambient occlusion)
    _drawCeilingWallJunctions(canvas);

    // Depth gradient overlay on entire wall area
    _drawWallGradientOverlay(canvas);
  }

  void _drawLegacyWalls(Canvas canvas) {
    final w = space.w, d = space.d, h = space.h;
    final inset = space.w * space.taperRatio / 2;

    final leftPts = [
      toScreen(inset, 0, 0),
      toScreen(0, 0, d),
      toScreen(0, h, d),
      toScreen(inset, h, 0),
    ];
    _drawQuadFace(canvas, leftPts, const Color(0xFF2A2825));
    _drawDepthGradient(canvas, leftPts);

    final rightPts = [
      toScreen(w - inset, 0, 0),
      toScreen(w, 0, d),
      toScreen(w, h, d),
      toScreen(w - inset, h, 0),
    ];
    _drawQuadFace(canvas, rightPts, const Color(0xFF2A2825));
    _drawDepthGradient(canvas, rightPts);
  }

  void _drawCeilingWallJunctions(Canvas canvas) {
    final d = space.d;
    final junctionPaint = Paint()
      ..color = const Color(0xFF0E0C0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Left ceiling-wall junction
    final leftJunction = Path();
    var pt = toScreen(_wallLeftTop(0), _ceilH(0), 0);
    leftJunction.moveTo(pt.dx, pt.dy);
    for (int i = 1; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      pt = toScreen(_wallLeftTop(z), _ceilH(z), z);
      leftJunction.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(leftJunction, junctionPaint);

    // Right ceiling-wall junction
    final rightJunction = Path();
    pt = toScreen(_wallRightTop(0), _ceilH(0), 0);
    rightJunction.moveTo(pt.dx, pt.dy);
    for (int i = 1; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      pt = toScreen(_wallRightTop(z), _ceilH(z), z);
      rightJunction.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(rightJunction, junctionPaint);
  }

  void _drawWallGradientOverlay(Canvas canvas) {
    final d = space.d;
    // Left wall gradient
    final leftOutline = <Offset>[];
    // Bottom edge: front -> back
    for (int i = _shapeSegs; i >= 0; i--) {
      final z = d * i / _shapeSegs;
      leftOutline.add(toScreen(_wallLeftBot(z), 0, z));
    }
    // Top edge: back -> front
    for (int i = 0; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      leftOutline.add(toScreen(_wallLeftTop(z), _ceilH(z), z));
    }
    final leftPath = buildPath(leftOutline);
    canvas.drawPath(
      leftPath,
      Paint()
        ..shader = ui.Gradient.linear(
          toScreen(_wallLeftBot(0), 0, 0),
          toScreen(0, 0, d),
          [
            const Color(0x38000000), // dark deep interior
            const Color(0x18000000), // mid
            const Color(0x00000000), // transition
            const Color(0x30FFFAED), // warm ambient from opening (was 0x10)
          ],
          [0.0, 0.25, 0.6, 1.0],
        )
        ..style = PaintingStyle.fill,
    );

    // Right wall gradient
    final rightOutline = <Offset>[];
    for (int i = _shapeSegs; i >= 0; i--) {
      final z = d * i / _shapeSegs;
      rightOutline.add(toScreen(_wallRightBot(z), 0, z));
    }
    for (int i = 0; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      rightOutline.add(toScreen(_wallRightTop(z), _ceilH(z), z));
    }
    final rightPath = buildPath(rightOutline);
    canvas.drawPath(
      rightPath,
      Paint()
        ..shader = ui.Gradient.linear(
          toScreen(_wallRightBot(0), 0, 0),
          toScreen(space.w, 0, d),
          [
            const Color(0x38000000),
            const Color(0x18000000),
            const Color(0x00000000),
            const Color(0x30FFFAED), // warm ambient from opening (was 0x10)
          ],
          [0.0, 0.25, 0.6, 1.0],
        )
        ..style = PaintingStyle.fill,
    );
  }

  /// Plastic trim grain lines + gloss highlight on a wall segment
  void _drawWallGrainLines(Canvas canvas, double xBot0, double xBot1,
      double xTop0, double xTop1, double h0, double h1, double z0, double z1) {
    final grainPaint = Paint()
      ..color = const Color(0x0CFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.4;

    // 4 horizontal grain lines at 20%, 40%, 60%, 80% height
    for (final frac in [0.2, 0.4, 0.6, 0.8]) {
      final y0 = h0 * frac;
      final y1 = h1 * frac;
      final x0 = xBot0 + (xTop0 - xBot0) * frac;
      final x1 = xBot1 + (xTop1 - xBot1) * frac;
      canvas.drawLine(
        toScreen(x0, y0, z0),
        toScreen(x1, y1, z1),
        grainPaint,
      );
    }

    // Gloss highlight near top (~85% height) -- brighter specular band
    final glossPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const glossFrac = 0.85;
    final gy0 = h0 * glossFrac;
    final gy1 = h1 * glossFrac;
    final gx0 = xBot0 + (xTop0 - xBot0) * glossFrac;
    final gx1 = xBot1 + (xTop1 - xBot1) * glossFrac;
    canvas.drawLine(
      toScreen(gx0, gy0, z0),
      toScreen(gx1, gy1, z1),
      glossPaint,
    );
  }

  void _drawDepthGradient(Canvas canvas, List<Offset> pts) {
    final path = buildPath(pts);
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          pts[1], pts[0],
          [const Color(0x00000000), const Color(0x30000000)],
        )
        ..style = PaintingStyle.fill,
    );
  }

  // ── Seat backrest (z = 0) with diamond quilting ──
  void drawSeatBackrest(Canvas canvas) {
    final w = space.w;
    final seatH = _ceilH(0); // ceiling height at rear
    final insetBot = _wallLeftBot(0); // bottom taper at z=0
    final insetTop = _wallLeftTop(0); // top taper at z=0
    final tilt = seatH * 0.12;

    // Main surface (trapezoidal for realism)
    final facePath = buildPath([
      toScreen(insetBot, 0, 0),
      toScreen(w - insetBot, 0, 0),
      toScreen(w - insetTop, seatH, tilt),
      toScreen(insetTop, seatH, tilt),
    ]);

    canvas.drawPath(
        facePath,
        Paint()
          ..color = const Color(0xFF3D3A35)
          ..style = PaintingStyle.fill);

    // Diamond quilting -- clip to face shape
    canvas.save();
    canvas.clipPath(facePath);

    final backW = w - insetBot - insetTop; // average width
    const quiltUnit = 0.08;
    final quiltPaint = Paint()
      ..color = const Color(0x20967B5D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Family A: u + v = c (lines going down-right)
    for (double c = quiltUnit; c < backW + seatH; c += quiltUnit) {
      final u0 = math.max(0.0, c - seatH);
      final u1 = math.min(backW, c);
      if (u1 <= u0) continue;
      final v0 = c - u0;
      final v1 = c - u1;
      canvas.drawLine(
        toScreen(insetBot + u0, v0, tilt * v0 / seatH),
        toScreen(insetBot + u1, v1, tilt * v1 / seatH),
        quiltPaint,
      );
    }

    // Family B: u - v = c (lines going up-right)
    for (double c = -seatH + quiltUnit; c < backW; c += quiltUnit) {
      final u0 = math.max(0.0, c);
      final u1 = math.min(backW, c + seatH);
      if (u1 <= u0) continue;
      final v0 = u0 - c;
      final v1 = u1 - c;
      if (v0 < -0.001 || v1 > seatH + 0.001) continue;
      canvas.drawLine(
        toScreen(insetBot + u0, v0, tilt * v0 / seatH),
        toScreen(insetBot + u1, v1, tilt * v1 / seatH),
        quiltPaint,
      );
    }

    canvas.restore();

    // Seat split lines
    final splitRatio = space.seatSplitRatio;
    if (splitRatio != null && splitRatio.length >= 2) {
      final splitPaint = Paint()
        ..color = const Color(0xFF1A1816)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      double cum = 0;
      final seatWidthBot = w - 2 * insetBot;
      final seatWidthTop = w - 2 * insetTop;
      for (int i = 0; i < splitRatio.length - 1; i++) {
        cum += splitRatio[i];
        final sxBot = insetBot + seatWidthBot * cum;
        final sxTop = insetTop + seatWidthTop * cum;
        canvas.drawLine(
          toScreen(sxBot, 0.01, 0),
          toScreen(sxTop, seatH - 0.01, tilt),
          splitPaint,
        );
      }
    }

    // Top edge highlight
    canvas.drawLine(
      toScreen(insetTop, seatH, tilt),
      toScreen(w - insetTop, seatH, tilt),
      Paint()
        ..color = const Color(0x30FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Headrest stubs (protruding above seat top)
    _drawHeadrests(canvas, w, seatH, tilt, insetBot, insetTop);

    // Seat fold lever indicators (red pull handles near split lines)
    _drawSeatFoldLevers(canvas, w, seatH, tilt, insetBot, insetTop);
  }

  void _drawHeadrests(Canvas canvas, double w, double seatH, double tilt,
      double insetBot, double insetTop) {
    final splitRatio = space.seatSplitRatio;
    if (splitRatio == null) return; // sedan -- no visible headrests

    const headrestH = 0.10; // 10cm tall
    const headrestW = 0.12; // 12cm wide
    const headrestD = 0.04; // 4cm deep (thickness)

    // Place headrests at center of each seat section
    final seatWidth = w - 2 * insetTop;
    double cum = 0;
    for (int i = 0; i < splitRatio.length; i++) {
      final sectionCenter = cum + splitRatio[i] / 2;
      cum += splitRatio[i];

      final cx = insetTop + seatWidth * sectionCenter;
      final hx = cx - headrestW / 2;
      final by = seatH;
      final ty = seatH + headrestH;
      final hz = tilt - headrestD;

      // Headrest: slightly rounded dark rectangle
      const headColor = Color(0xFF2A2826);
      const headDark = Color(0xFF1E1C1A);

      // Front face
      _drawQuadFace(canvas, [
        toScreen(hx, by, tilt),
        toScreen(hx + headrestW, by, tilt),
        toScreen(hx + headrestW, ty, tilt),
        toScreen(hx, ty, tilt),
      ], headColor);

      // Top face
      _drawQuadFace(canvas, [
        toScreen(hx, ty, hz),
        toScreen(hx + headrestW, ty, hz),
        toScreen(hx + headrestW, ty, tilt),
        toScreen(hx, ty, tilt),
      ], headDark);

      // Metal post hints (two thin lines)
      final postPaint = Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final postLeft = cx - 0.025;
      final postRight = cx + 0.025;
      canvas.drawLine(
          toScreen(postLeft, by, tilt),
          toScreen(postLeft, by - 0.01, tilt),
          postPaint);
      canvas.drawLine(
          toScreen(postRight, by, tilt),
          toScreen(postRight, by - 0.01, tilt),
          postPaint);
    }
  }

  // ── Seat Fold Lever Indicators ──
  void _drawSeatFoldLevers(Canvas canvas, double w, double seatH, double tilt,
      double insetBot, double insetTop) {
    final splitRatio = space.seatSplitRatio;
    if (splitRatio == null || splitRatio.length < 2) return;

    const leverW = 0.02; // 2cm wide
    const leverH = 0.01; // 1cm tall

    final leverPaint = Paint()
      ..color = const Color(0xFFCC3333) // red pull handle
      ..style = PaintingStyle.fill;

    // Place a lever near each split line, on the top edge
    final seatWidthTop = w - 2 * insetTop;
    double cum = 0;
    for (int i = 0; i < splitRatio.length - 1; i++) {
      cum += splitRatio[i];
      final sx = insetTop + seatWidthTop * cum;
      // Offset slightly into the wider section
      final lx = sx + 0.01;
      final ly = seatH - leverH;

      // Small colored rectangle on the seat top
      final pts = [
        toScreen(lx, ly, tilt),
        toScreen(lx + leverW, ly, tilt),
        toScreen(lx + leverW, seatH, tilt),
        toScreen(lx, seatH, tilt),
      ];
      canvas.drawPath(buildPath(pts), leverPaint);

      // Tiny highlight
      canvas.drawPath(
        buildPath(pts),
        Paint()
          ..color = const Color(0x30FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  // ── Trunk floor ──
  void drawTrunkFloor(Canvas canvas) {
    final w = space.w, d = space.d;

    // Main floor -- follows bottom taper
    final floorPts = [
      toScreen(_wallLeftBot(0), 0, 0),
      toScreen(_wallRightBot(0), 0, 0),
      toScreen(_wallRightBot(d), 0, d),
      toScreen(_wallLeftBot(d), 0, d),
    ];
    _drawQuadFace(canvas, floorPts, const Color(0xFF4A4540));

    // Depth lighting gradient -- strong warm light near opening
    canvas.drawPath(
      buildPath(floorPts),
      Paint()
        ..shader = ui.Gradient.linear(
          floorPts[0], floorPts[3],
          [
            const Color(0x40000000), // dark deep interior
            const Color(0x18000000), // mid
            const Color(0x00000000), // transition
            const Color(0x50FFFAED), // warm light near opening (was 0x18)
          ],
          [0.0, 0.25, 0.55, 1.0],
        )
        ..style = PaintingStyle.fill,
    );

    // Carpet texture -- fine stipple pattern
    _drawCarpetTexture(canvas, d);

    // Floor-wall corner ambient occlusion strips
    _drawFloorWallCornerAO(canvas, d);

    // Wall-floor junction lines (ambient occlusion)
    final junctionPaint = Paint()
      ..color = const Color(0xFF0E0C0A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Left junction: curved path following wall bottom
    final leftJunction = Path()
      ..moveTo(toScreen(_wallLeftBot(0), 0, 0).dx,
          toScreen(_wallLeftBot(0), 0, 0).dy);
    for (int i = 1; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      final pt = toScreen(_wallLeftBot(z), 0, z);
      leftJunction.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(leftJunction, junctionPaint);

    // Right junction
    final rightJunction = Path()
      ..moveTo(toScreen(_wallRightBot(0), 0, 0).dx,
          toScreen(_wallRightBot(0), 0, 0).dy);
    for (int i = 1; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      final pt = toScreen(_wallRightBot(z), 0, z);
      rightJunction.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(rightJunction, junctionPaint);

    // Back junction
    canvas.drawLine(
        toScreen(_wallLeftBot(0), 0, 0),
        toScreen(_wallRightBot(0), 0, 0),
        junctionPaint);

    // Opening edge highlight
    canvas.drawLine(
      toScreen(0, 0, d),
      toScreen(w, 0, d),
      Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Floor mat edge -- subtle raised perimeter line
    _drawFloorMatEdge(canvas, d);

    _drawFloorStep(canvas);
  }

  /// Carpet texture -- subtle stipple dots across the floor
  void _drawCarpetTexture(Canvas canvas, double d) {
    final w = space.w;
    // Fixed seed based on trunk dimensions for stable pattern
    final rng = math.Random((w * 1000 + d * 1000).toInt());
    const dotCount = 260;

    final lighterPaint = Paint()
      ..color = const Color(0x18403C38)
      ..style = PaintingStyle.fill;
    final darkerPaint = Paint()
      ..color = const Color(0x1A0A0806)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < dotCount; i++) {
      final t = rng.nextDouble(); // 0..1 along depth
      final z = t * d;
      final leftX = _wallLeftBot(z);
      final rightX = _wallRightBot(z);
      final x = leftX + rng.nextDouble() * (rightX - leftX);
      final pt = toScreen(x, 0, z);

      // Perspective-aware dot size: smaller when deeper
      final dz = camZ - z;
      final dotR = (focalLen / dz) * scale * 0.002 + 0.3;

      final paint = rng.nextBool() ? lighterPaint : darkerPaint;
      canvas.drawCircle(pt, dotR, paint);
    }

    // Add a few short fiber-like lines for variety
    final fiberPaint = Paint()
      ..color = const Color(0x12504A44)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i < 60; i++) {
      final t = rng.nextDouble();
      final z = t * d;
      final leftX = _wallLeftBot(z);
      final rightX = _wallRightBot(z);
      final x = leftX + rng.nextDouble() * (rightX - leftX);
      final pt = toScreen(x, 0, z);
      final dz = camZ - z;
      final len = (focalLen / dz) * scale * 0.004;
      final angle = rng.nextDouble() * math.pi;
      final dx = math.cos(angle) * len;
      final dy = math.sin(angle) * len;
      canvas.drawLine(pt, pt + Offset(dx, dy), fiberPaint);
    }
  }

  /// Darken floor near wall edges (ambient occlusion in corners)
  void _drawFloorWallCornerAO(Canvas canvas, double d) {
    const aoWidth = 0.04; // 4cm strip

    // Left edge AO strip
    final leftAO = <Offset>[];
    for (int i = 0; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      leftAO.add(toScreen(_wallLeftBot(z), 0, z));
    }
    for (int i = _shapeSegs; i >= 0; i--) {
      final z = d * i / _shapeSegs;
      leftAO.add(toScreen(_wallLeftBot(z) + aoWidth, 0, z));
    }
    canvas.drawPath(
      buildPath(leftAO),
      Paint()
        ..color = const Color(0x1A000000)
        ..style = PaintingStyle.fill,
    );

    // Right edge AO strip
    final rightAO = <Offset>[];
    for (int i = 0; i <= _shapeSegs; i++) {
      final z = d * i / _shapeSegs;
      rightAO.add(toScreen(_wallRightBot(z), 0, z));
    }
    for (int i = _shapeSegs; i >= 0; i--) {
      final z = d * i / _shapeSegs;
      rightAO.add(toScreen(_wallRightBot(z) - aoWidth, 0, z));
    }
    canvas.drawPath(
      buildPath(rightAO),
      Paint()
        ..color = const Color(0x1A000000)
        ..style = PaintingStyle.fill,
    );

    // Back edge AO strip (along seat)
    final backAO = [
      toScreen(_wallLeftBot(0), 0, 0),
      toScreen(_wallRightBot(0), 0, 0),
      toScreen(_wallRightBot(0), 0, aoWidth),
      toScreen(_wallLeftBot(0), 0, aoWidth),
    ];
    canvas.drawPath(
      buildPath(backAO),
      Paint()
        ..color = const Color(0x1A000000)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawFloorStep(Canvas canvas) {
    final w = space.w, d = space.d;
    const stepH = 0.015;
    const stepD = 0.04;
    final stepStart = d - stepD;

    final stepStroke = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Top face
    _drawQuadFace(canvas, [
      toScreen(0, stepH, stepStart),
      toScreen(w, stepH, stepStart),
      toScreen(w, stepH, d),
      toScreen(0, stepH, d),
    ], const Color(0xFF3A3836), stroke: stepStroke);

    // Front face
    _drawQuadFace(canvas, [
      toScreen(0, 0, stepStart),
      toScreen(w, 0, stepStart),
      toScreen(w, stepH, stepStart),
      toScreen(0, stepH, stepStart),
    ], const Color(0xFF302E2B), stroke: stepStroke);
  }

  // ── Floor Mat Edge ──
  void _drawFloorMatEdge(Canvas canvas, double d) {
    const inset = 0.02; // 2cm inset from perimeter

    final matEdgePaint = Paint()
      ..color = const Color(0xFF3A3836)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Build inset perimeter path following floor shape
    final matPath = Path();

    // Start at back-left (near seat)
    var pt = toScreen(_wallLeftBot(inset) + inset, 0, inset);
    matPath.moveTo(pt.dx, pt.dy);

    // Back edge (near seat)
    pt = toScreen(_wallRightBot(inset) - inset, 0, inset);
    matPath.lineTo(pt.dx, pt.dy);

    // Right edge -- follow wall with inset
    for (int i = 1; i <= _shapeSegs; i++) {
      final t = i / _shapeSegs;
      final z = inset + (d - 2 * inset) * t;
      final x = _wallRightBot(z) - inset;
      pt = toScreen(x, 0, z);
      matPath.lineTo(pt.dx, pt.dy);
    }

    // Front edge (near opening)
    pt = toScreen(_wallLeftBot(d - inset) + inset, 0, d - inset);
    matPath.lineTo(pt.dx, pt.dy);

    // Left edge -- follow wall with inset (back toward seat)
    for (int i = _shapeSegs; i >= 0; i--) {
      final t = i / _shapeSegs;
      final z = inset + (d - 2 * inset) * t;
      final x = _wallLeftBot(z) + inset;
      pt = toScreen(x, 0, z);
      matPath.lineTo(pt.dx, pt.dy);
    }

    matPath.close();
    canvas.drawPath(matPath, matEdgePaint);
  }

  // ── Cargo Hooks / Tie-Down Points ──
  void drawCargoHooks(Canvas canvas) {
    final w = space.w, d = space.d;
    const hookRadius = 0.01; // 2cm diameter = 1cm radius

    // 4 hooks: 2 near front (z ~ d*0.85), 2 near back (z ~ 0.15)
    final hookPositions = [
      (x: 0.08, z: d * 0.85),
      (x: w - 0.08, z: d * 0.85),
      (x: 0.08, z: d * 0.15),
      (x: w - 0.08, z: d * 0.15),
    ];

    final ringPaint = Paint()
      ..color = const Color(0xFF777777)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final basePaint = Paint()
      ..color = const Color(0xFF555555)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final hook in hookPositions) {
      final center = toScreen(hook.x, 0, hook.z);
      // Perspective-aware radius
      final dz = camZ - hook.z;
      final pxRadius = (focalLen / dz) * scale * hookRadius;

      // D-ring: circle
      canvas.drawCircle(center, pxRadius, ringPaint);
      // Base line through bottom (embedded in floor)
      canvas.drawLine(
        center + Offset(-pxRadius * 0.7, pxRadius * 0.3),
        center + Offset(pxRadius * 0.7, pxRadius * 0.3),
        basePaint,
      );
    }
  }

  // ── Cargo Net Attachment Points ──
  void drawCargoNetPoints(Canvas canvas) {
    final d = space.d, h = space.h;
    const studRadius = 0.005; // 1cm diameter = 0.5cm radius

    // 2 on each wall, at z ~ d*0.3 and z ~ d*0.7, height ~ h*0.4
    final studs = [
      // Left wall
      (x: _wallLeftBot(d * 0.3) + 0.005, y: h * 0.4, z: d * 0.3),
      (x: _wallLeftBot(d * 0.7) + 0.005, y: h * 0.4, z: d * 0.7),
      // Right wall
      (x: _wallRightBot(d * 0.3) - 0.005, y: h * 0.4, z: d * 0.3),
      (x: _wallRightBot(d * 0.7) - 0.005, y: h * 0.4, z: d * 0.7),
    ];

    final studPaint = Paint()
      ..color = const Color(0xFF666666)
      ..style = PaintingStyle.fill;

    for (final stud in studs) {
      final pt = toScreen(stud.x, stud.y, stud.z);
      final dz = camZ - stud.z;
      final pxR = (focalLen / dz) * scale * studRadius;
      canvas.drawCircle(pt, pxR.clamp(0.8, 3.0), studPaint);
      // Highlight ring
      canvas.drawCircle(
        pt,
        pxR.clamp(0.8, 3.0),
        Paint()
          ..color = const Color(0x30FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  // ── Rear Wall 12V Outlet ──
  void drawTwelveVOutlet(Canvas canvas) {
    final d = space.d;
    const outletRadius = 0.0125; // 2.5cm diameter = 1.25cm radius

    final z = d * 0.2;
    final x = _wallLeftBot(z) + 0.005; // on left wall, slightly inside
    const y = 0.08; // near floor

    final pt = toScreen(x, y, z);
    final dz = camZ - z;
    final pxR = (focalLen / dz) * scale * outletRadius;

    // Dark circle (outlet body)
    canvas.drawCircle(
      pt,
      pxR,
      Paint()
        ..color = const Color(0xFF1A1A1A)
        ..style = PaintingStyle.fill,
    );

    // Lighter ring (chrome surround)
    canvas.drawCircle(
      pt,
      pxR,
      Paint()
        ..color = const Color(0xFF555555)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Inner detail -- two small vertical slots
    final slotPaint = Paint()
      ..color = const Color(0xFF444444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawLine(
      pt + Offset(-pxR * 0.3, -pxR * 0.25),
      pt + Offset(-pxR * 0.3, pxR * 0.25),
      slotPaint,
    );
    canvas.drawLine(
      pt + Offset(pxR * 0.3, -pxR * 0.25),
      pt + Offset(pxR * 0.3, pxR * 0.25),
      slotPaint,
    );
  }

  /// Small LED trunk light in upper-left corner near the opening
  void drawTrunkLight(Canvas canvas) {
    final h = space.h;
    final d = space.d;

    // Light position: upper-left, near the opening
    final lightX = 0.05;
    final lightY = h * 0.85;
    final lightZ = d * 0.9;
    final lightCenter = toScreen(lightX, lightY, lightZ);

    // Perspective-aware radius
    final dz = camZ - lightZ;
    final pScale = focalLen / dz * scale;

    // Radial glow (~15cm radius in world space)
    final glowRadius = 0.15 * pScale;
    canvas.drawCircle(
      lightCenter,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          lightCenter,
          glowRadius,
          [
            const Color(0x30FFFAF0), // warm white center
            const Color(0x18FFF5E0), // warm mid
            const Color(0x00FFF5E0), // fade out
          ],
          [0.0, 0.4, 1.0],
        ),
    );

    // Warm wash on nearby wall/ceiling (larger, dimmer)
    final washRadius = 0.30 * pScale;
    canvas.drawCircle(
      lightCenter,
      washRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          lightCenter,
          washRadius,
          [
            const Color(0x10FFF5E0),
            const Color(0x00FFF5E0),
          ],
          [0.0, 1.0],
        ),
    );

    // The LED itself -- small bright circle
    final ledRadius = 0.012 * pScale;
    canvas.drawCircle(
      lightCenter,
      ledRadius,
      Paint()..color = const Color(0xDDFFFAF0),
    );
    // Tiny bright core
    canvas.drawCircle(
      lightCenter,
      ledRadius * 0.4,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  /// Helper: filled quad with optional stroke
  void _drawQuadFace(Canvas canvas, List<Offset> pts, Color fill,
      {Paint? stroke}) {
    final path = buildPath(pts);
    canvas.drawPath(
        path,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill);
    if (stroke != null) canvas.drawPath(path, stroke);
  }
}
