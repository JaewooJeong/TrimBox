part of 'isometric_painter.dart';

/// Inferred camping sub-type for texture differentiation
enum _CampingSubType {
  tentBag,
  cooler,
  chairBag,
  container,
  defaultCamping,
}

/// Box and wheelhouse rendering — perspective view
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
    String label = '',
    double origWcm = 0,
    double origDcm = 0,
    double origHcm = 0,
  }) {
    // 8 vertices
    final p0 = toScreen(x, y, z); // back-left-bottom
    final p1 = toScreen(x + w, y, z); // back-right-bottom
    final p2 = toScreen(x + w, y, z + d); // front-right-bottom
    final p3 = toScreen(x, y, z + d); // front-left-bottom
    final p4 = toScreen(x, y + h, z); // back-left-top
    final p5 = toScreen(x + w, y + h, z); // back-right-top
    final p6 = toScreen(x + w, y + h, z + d); // front-right-top
    final p7 = toScreen(x, y + h, z + d); // front-left-top

    // Quadratic depth darkening with ambient floor
    // z=0 is deepest (darkest), z=d is opening (brightest)
    final depthFactor = space.d > 0 ? (z / space.d).clamp(0.0, 1.0) : 0.5;
    final depthDarken = math.pow(1.0 - depthFactor, 1.4) * 0.65;
    final ambientFloor = 0.20; // never fully black
    final effectiveDepthDarken = depthDarken * (1.0 - ambientFloor);
    // Color temperature shift: warm near opening, cool deep inside
    final warmShift = Color.lerp(fillColor, const Color(0xFFFFF8E7), depthFactor * 0.08)!;
    final coolShift = Color.lerp(warmShift, const Color(0xFFD8E8F0), (1.0 - depthFactor) * 0.06)!;
    final baseColor = Color.lerp(coolShift, Colors.black, effectiveDepthDarken)!;

    final fill = Paint()..style = PaintingStyle.fill;

    // Ground shadow — multi-layer with light-from-opening offset
    {
      // Shadow softness grows with height (stacked boxes have softer shadow)
      final heightFactor = y.clamp(0.0, 1.0);
      final baseSo = 0.015;
      // Light comes from opening (high z), so shadow offsets toward back (lower z)
      final lightOffsetZ = -0.01 - heightFactor * 0.02;
      // Higher boxes = more transparent + larger shadow
      final layers = [
        (spread: baseSo + heightFactor * 0.02, alpha: (0x44 * (1.0 - heightFactor * 0.4)).round()),
        (spread: baseSo * 2.0 + heightFactor * 0.03, alpha: (0x22 * (1.0 - heightFactor * 0.3)).round()),
        (spread: baseSo * 3.5 + heightFactor * 0.04, alpha: (0x11 * (1.0 - heightFactor * 0.2)).round()),
      ];
      for (int li = 0; li < layers.length; li++) {
        final layer = layers[li];
        final so = layer.spread;
        final shadowPath = buildPath([
          toScreen(x - so, -0.001, z - so + lightOffsetZ),
          toScreen(x + w + so, -0.001, z - so + lightOffsetZ),
          toScreen(x + w + so, -0.001, z + d + so + lightOffsetZ),
          toScreen(x - so, -0.001, z + d + so + lightOffsetZ),
        ]);
        // Blur increases per layer for soft shadow falloff
        final blurSigma = 2.0 + li * 3.0 + heightFactor * 4.0;
        canvas.drawPath(
            shadowPath,
            Paint()
              ..color = Color.fromARGB(layer.alpha, 0, 0, 0)
              ..style = PaintingStyle.fill
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma));
      }
    }

    // Inter-box ambient occlusion: darken bottom edge where box meets surface
    if (y > 0.005) {
      // Box is stacked — draw thin dark strip at contact line (front + sides)
      final aoAlpha = 0x33;
      final aoWidth = 0.006; // 6mm dark strip
      final aoPaint = Paint()
        ..color = Color.fromARGB(aoAlpha, 0, 0, 0)
        ..style = PaintingStyle.fill;
      // Front AO strip
      canvas.drawPath(buildPath([
        toScreen(x, y, z + d),
        toScreen(x + w, y, z + d),
        toScreen(x + w, y - aoWidth, z + d),
        toScreen(x, y - aoWidth, z + d),
      ]), aoPaint);
      // Left AO strip
      if (camX > x) {
        canvas.drawPath(buildPath([
          toScreen(x, y, z),
          toScreen(x, y, z + d),
          toScreen(x, y - aoWidth, z + d),
          toScreen(x, y - aoWidth, z),
        ]), aoPaint);
      }
      // Right AO strip
      if (camX < x + w) {
        canvas.drawPath(buildPath([
          toScreen(x + w, y, z),
          toScreen(x + w, y, z + d),
          toScreen(x + w, y - aoWidth, z + d),
          toScreen(x + w, y - aoWidth, z),
        ]), aoPaint);
      }
    }

    // Face visibility from fixed camera
    final showLeft = camX > x;
    final showRight = camX < x + w;
    final showTop = camY > y + h;

    // Draw faces back-to-front with strong value separation
    // Research: top = brightest, front = medium, side = darkest

    // Left face (darkest side — away from opening light)
    if (showLeft) {
      fill.color = Color.lerp(baseColor, Colors.black, 0.50)!;
      canvas.drawPath(buildPath([p0, p3, p7, p4]), fill);
    }

    // Right face (dark side)
    if (showRight) {
      fill.color = Color.lerp(baseColor, Colors.black, 0.45)!;
      canvas.drawPath(buildPath([p1, p2, p6, p5]), fill);
    }

    // Top face (brightest — catches ambient light from above)
    if (showTop) {
      fill.color = Color.lerp(baseColor, Colors.white, 0.18)!;
      canvas.drawPath(buildPath([p4, p5, p6, p7]), fill);
    }

    // Front face (medium — faces viewer and opening light)
    fill.color = Color.lerp(baseColor, Colors.black, 0.08)!;
    canvas.drawPath(buildPath([p3, p2, p6, p7]), fill);

    // Edge lines — front edges bold, receding edges thinner for depth
    final edgeColor = Color.lerp(baseColor, Colors.black, 0.50)!;
    final frontEdgePaint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final recedingEdgePaint = Paint()
      ..color = Color.lerp(edgeColor, Colors.black, 0.15)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Front face edges (bold — closest to camera)
    canvas.drawLine(p3, p2, frontEdgePaint);
    canvas.drawLine(p2, p6, frontEdgePaint);
    canvas.drawLine(p6, p7, frontEdgePaint);
    canvas.drawLine(p7, p3, frontEdgePaint);

    // Top face edges (receding toward back)
    if (showTop) {
      canvas.drawLine(p4, p5, recedingEdgePaint);
      if (showLeft) canvas.drawLine(p4, p7, recedingEdgePaint);
      if (showRight) canvas.drawLine(p5, p6, recedingEdgePaint);
    }

    // Vertical back edges (receding)
    if (showLeft) {
      canvas.drawLine(p0, p4, recedingEdgePaint);
      canvas.drawLine(p0, p3, recedingEdgePaint);
    }
    if (showRight) {
      canvas.drawLine(p1, p5, recedingEdgePaint);
      canvas.drawLine(p1, p2, recedingEdgePaint);
    }

    // Selection glow
    if (isSelected) {
      final frontOutline = buildPath([p3, p2, p6, p7]);
      canvas.drawPath(
          frontOutline,
          Paint()
            ..color = const Color(0x664DA3FF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6));
    }

    // Collision/selection stroke
    if (strokeWidth > 1.5) {
      canvas.drawPath(
          buildPath([p3, p2, p6, p7]),
          Paint()
            ..color = strokeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round);
    }

    // Category texture on top face
    if (category != BoxCategory.custom && showTop) {
      _drawBoxTexture(canvas, category, x, y + h, z, w, d, baseColor,
          label, origWcm, origDcm, origHcm);
    }

    // Category texture on front face
    if (category != BoxCategory.custom) {
      _drawFrontFaceTexture(canvas, category, x, y, z + d, w, h, baseColor,
          label, origWcm, origDcm, origHcm);
    }

    // Front-face label (render label text on the front face)
    if (label.isNotEmpty) {
      _drawFrontFaceLabel(canvas, label, x, y, z + d, w, h, baseColor);
    }
  }

  // ── Wheelhouse (rounded arch) ──
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
    // Rounded arch profile: vertical sides + semicircular top
    const arcSegs = 12;
    final radius = math.min(w, h) * 0.7;
    final straightH = h - radius; // height of straight part
    final cx = x + w / 2;

    // Build arch cross-section (left profile → right profile)
    List<Offset> archProfile(double atZ) {
      final pts = <Offset>[];
      pts.add(toScreen(x, 0, atZ));
      if (straightH > 0) pts.add(toScreen(x, straightH, atZ));
      // Arc from left to right
      for (int i = 0; i <= arcSegs; i++) {
        final angle = math.pi - (math.pi * i / arcSegs);
        final ax = cx + radius * math.cos(angle);
        final ay = straightH + radius * math.sin(angle);
        pts.add(toScreen(ax, math.min(ay, h), atZ));
      }
      if (straightH > 0) pts.add(toScreen(x + w, straightH, atZ));
      pts.add(toScreen(x + w, 0, atZ));
      return pts;
    }

    final depthFactor = space.d > 0 ? (z + d / 2) / space.d : 0.5;
    final depthDarken = (1.0 - depthFactor) * 0.15;
    final baseColor = Color.lerp(fillColor, Colors.black, depthDarken)!;

    // Determine which side this wheelhouse is on
    final isLeft = x < space.w / 2;
    final sideX = isLeft ? x + w : x; // inner face facing cargo area

    // Inner side face: arch-shaped (not simple rectangle)
    final sideFrontPts = <Offset>[];
    sideFrontPts.add(toScreen(sideX, 0, z));
    sideFrontPts.add(toScreen(sideX, 0, z + d));
    sideFrontPts.add(toScreen(sideX, h, z + d));
    sideFrontPts.add(toScreen(sideX, h, z));
    final sideColor = Color.lerp(baseColor, Colors.black, 0.12)!;
    _drawWheelhouseFace(canvas, sideFrontPts, sideColor);

    // Top surface: curved arch, drawn as quad strips along depth
    const depthSegs = 6;
    for (int di = 0; di < depthSegs; di++) {
      final zt0 = z + d * di / depthSegs;
      final zt1 = z + d * (di + 1) / depthSegs;
      for (int ai = 0; ai < arcSegs; ai++) {
        final a0 = math.pi - (math.pi * ai / arcSegs);
        final a1 = math.pi - (math.pi * (ai + 1) / arcSegs);

        final ax0 = cx + radius * math.cos(a0);
        final ay0 = math.min(straightH + radius * math.sin(a0), h);
        final ax1 = cx + radius * math.cos(a1);
        final ay1 = math.min(straightH + radius * math.sin(a1), h);

        // Shade varies by arc position: darker at sides, lighter at apex
        final arcFrac = ai / arcSegs;
        final arcShade = 0.05 + 0.12 * (0.5 - (arcFrac - 0.5).abs());
        final shade = Color.lerp(baseColor, Colors.white, arcShade)!;
        final quad = buildPath([
          toScreen(ax0, ay0, zt0),
          toScreen(ax1, ay1, zt0),
          toScreen(ax1, ay1, zt1),
          toScreen(ax0, ay0, zt1),
        ]);
        canvas.drawPath(quad,
            Paint()..color = shade..style = PaintingStyle.fill);
      }
    }

    // Front face (z = z + d, toward camera) — the most visible face
    final frontProfile = archProfile(z + d);
    final frontColor = Color.lerp(baseColor, Colors.black, 0.05)!;
    _drawWheelhouseFace(canvas, frontProfile, frontColor);

    // Subtle inner shadow gradient on front face (concave depth cue)
    final frontPath = buildPath(frontProfile);
    final archCenter = toScreen(cx, h * 0.5, z + d);
    canvas.drawPath(
        frontPath,
        Paint()
          ..shader = ui.Gradient.radial(
            archCenter,
            (w * scale * focalLen / (camZ - z - d)).abs().clamp(10.0, 200.0),
            [
              Color.lerp(frontColor, Colors.black, 0.15)!,
              frontColor,
            ],
            [0.0, 1.0],
          )
          ..style = PaintingStyle.fill);

    // Strong edge outline on front face for clear arch silhouette
    final edgePaint = Paint()
      ..color = Color.lerp(baseColor, Colors.black, 0.50)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(frontPath, edgePaint);

    // Inner highlight along the arch (plastic specular edge)
    final highlightPaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(frontPath, highlightPaint);

    // Depth edge lines connecting front arch to back (visible ribs)
    for (final frac in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final angle = math.pi - (math.pi * frac);
      final ex = cx + radius * math.cos(angle);
      final ey = math.min(straightH + radius * math.sin(angle), h);
      if (ey > 0.01) {
        canvas.drawLine(
          toScreen(ex, ey, z),
          toScreen(ex, ey, z + d),
          Paint()
            ..color = Color.lerp(baseColor, Colors.black, 0.30)!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6,
        );
      }
    }

    // Floor-to-wheelhouse junction: AO shadow strip (8mm) + line
    final aoStripW = 0.008;
    final aoStripPaint = Paint()
      ..color = const Color(0x44000000)
      ..style = PaintingStyle.fill;
    // Left side AO strip
    canvas.drawPath(buildPath([
      toScreen(x - aoStripW, -0.001, z),
      toScreen(x, -0.001, z),
      toScreen(x, -0.001, z + d),
      toScreen(x - aoStripW, -0.001, z + d),
    ]), aoStripPaint);
    // Right side AO strip
    canvas.drawPath(buildPath([
      toScreen(x + w, -0.001, z),
      toScreen(x + w + aoStripW, -0.001, z),
      toScreen(x + w + aoStripW, -0.001, z + d),
      toScreen(x + w, -0.001, z + d),
    ]), aoStripPaint);
    // Front AO strip
    canvas.drawPath(buildPath([
      toScreen(x, -0.001, z + d),
      toScreen(x + w, -0.001, z + d),
      toScreen(x + w, -0.001, z + d + aoStripW),
      toScreen(x, -0.001, z + d + aoStripW),
    ]), aoStripPaint);
    // Junction lines on top of AO
    final junctionPaint = Paint()
      ..color = const Color(0xFF1A1816)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(toScreen(x, 0, z), toScreen(x, 0, z + d), junctionPaint);
    canvas.drawLine(toScreen(x + w, 0, z), toScreen(x + w, 0, z + d), junctionPaint);
  }

  void _drawWheelhouseFace(Canvas canvas, List<Offset> pts, Color color) {
    canvas.drawPath(
        buildPath(pts),
        Paint()
          ..color = color
          ..style = PaintingStyle.fill);
  }

  // ── Camping sub-type inference from dimensions (cm) and label ──
  _CampingSubType _inferCampingSubType(
      String label, double wcm, double dcm, double hcm) {
    // Coolers / ice boxes
    if (label.contains('쿨러') || label.contains('아이스')) {
      return _CampingSubType.cooler;
    }
    // Folding boxes / containers / shelves
    if (label.contains('컨테이너') ||
        label.contains('폴딩박스') ||
        label.contains('쉘프') ||
        label.contains('정리함')) {
      return _CampingSubType.container;
    }
    // Tent bags (long, cylindrical — w > 50 and (d < 25 or h < 25))
    final maxDim = math.max(wcm, math.max(dcm, hcm));
    final minDim = math.min(wcm, math.min(dcm, hcm));
    if (maxDim > 50 && minDim < 25 &&
        (label.contains('텐트') || label.contains('타프') ||
         label.contains('침낭') || label.contains('매트'))) {
      return _CampingSubType.tentBag;
    }
    // Chairs (long and thin — one dim > 70, another < 20)
    if (maxDim > 70 && minDim < 20 &&
        (label.contains('의자') || label.contains('체어'))) {
      return _CampingSubType.chairBag;
    }
    // Tent bags by pure dimension (long, thin, not matched above)
    if (maxDim > 50 && minDim < 25) {
      return _CampingSubType.tentBag;
    }
    // Chairs by pure dimension
    if (maxDim > 70 && minDim < 20) {
      return _CampingSubType.chairBag;
    }
    return _CampingSubType.defaultCamping;
  }

  // ── Category textures on TOP face ──
  void _drawBoxTexture(
      Canvas canvas,
      BoxCategory category,
      double x,
      double topY,
      double z,
      double w,
      double d,
      Color baseColor,
      String label,
      double origWcm,
      double origDcm,
      double origHcm) {
    switch (category) {
      case BoxCategory.carrier:
        _drawCarrierTopTexture(canvas, x, topY, z, w, d, baseColor);
      case BoxCategory.moving:
        _drawMovingTopTexture(canvas, x, topY, z, w, d, baseColor);
      case BoxCategory.camping:
        _drawCampingTopTexture(canvas, x, topY, z, w, d, baseColor,
            label, origWcm, origDcm, origHcm);
      case BoxCategory.custom:
        break;
    }
  }

  void _drawCarrierTopTexture(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final wheelColor = Color.lerp(baseColor, Colors.black, 0.45)!;
    final wheelPaint = Paint()
      ..color = wheelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final inW = w * 0.15, inD = d * 0.15;
    final wheelR = math.min(w, d) * 0.08 * scale * focalLen / (camZ - z);
    final corners = [
      toScreen(x + inW, topY, z + inD),
      toScreen(x + w - inW, topY, z + inD),
      toScreen(x + w - inW, topY, z + d - inD),
      toScreen(x + inW, topY, z + d - inD),
    ];
    for (final c in corners) {
      canvas.drawCircle(c, wheelR, wheelPaint);
      canvas.drawCircle(
          c,
          wheelR * 0.4,
          Paint()
            ..color = wheelColor
            ..style = PaintingStyle.fill);
    }
  }

  void _drawMovingTopTexture(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final tapeColor = Color.lerp(baseColor, Colors.white, 0.20)!;
    final tapePaint = Paint()
      ..color = tapeColor.withAlpha(0xAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(toScreen(x, topY, z + d / 2),
        toScreen(x + w, topY, z + d / 2), tapePaint);
    canvas.drawLine(toScreen(x + w / 2, topY, z),
        toScreen(x + w / 2, topY, z + d), tapePaint);
  }

  void _drawCampingTopTexture(
      Canvas canvas,
      double x,
      double topY,
      double z,
      double w,
      double d,
      Color baseColor,
      String label,
      double origWcm,
      double origDcm,
      double origHcm) {
    final subType = _inferCampingSubType(label, origWcm, origDcm, origHcm);
    final strapColor = Color.lerp(baseColor, Colors.black, 0.25)!;
    final strapPaint = Paint()
      ..color = strapColor.withAlpha(0xAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    switch (subType) {
      case _CampingSubType.tentBag:
        // Oval shape on top + horizontal compression straps
        _drawOvalTopFace(canvas, x, topY, z, w, d, baseColor);
        // 2-3 compression straps across length
        final strapCount = w > d ? 3 : 2;
        for (int i = 1; i <= strapCount; i++) {
          final frac = i / (strapCount + 1);
          if (w > d) {
            // Straps perpendicular to the long axis
            final sx = x + w * frac;
            canvas.drawLine(
                toScreen(sx, topY, z + d * 0.1),
                toScreen(sx, topY, z + d * 0.9),
                strapPaint);
          } else {
            final sz = z + d * frac;
            canvas.drawLine(
                toScreen(x + w * 0.1, topY, sz),
                toScreen(x + w * 0.9, topY, sz),
                strapPaint);
          }
        }

      case _CampingSubType.cooler:
        // Lid line at 80% depth
        final lidZ = z + d * 0.80;
        final lidPaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.30)!.withAlpha(0xCC)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            toScreen(x + w * 0.05, topY, lidZ),
            toScreen(x + w * 0.95, topY, lidZ),
            lidPaint);
        // Slightly glossy top: lighter overlay stripe
        final glossPaint = Paint()
          ..color = const Color(0x18FFFFFF)
          ..style = PaintingStyle.fill;
        canvas.drawPath(
            buildPath([
              toScreen(x + w * 0.1, topY, z + d * 0.2),
              toScreen(x + w * 0.9, topY, z + d * 0.2),
              toScreen(x + w * 0.9, topY, z + d * 0.5),
              toScreen(x + w * 0.1, topY, z + d * 0.5),
            ]),
            glossPaint);

      case _CampingSubType.chairBag:
        // Fabric bag: diagonal cross-hatching on top
        final hatchPaint = Paint()
          ..color = strapColor.withAlpha(0x55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round;
        final count = 5;
        for (int i = 0; i <= count; i++) {
          final frac = i / count;
          canvas.drawLine(
              toScreen(x, topY, z + d * frac),
              toScreen(x + w * frac, topY, z),
              hatchPaint);
          canvas.drawLine(
              toScreen(x + w * frac, topY, z + d),
              toScreen(x + w, topY, z + d * frac),
              hatchPaint);
        }

      case _CampingSubType.container:
        // Cross tape like moving box but thinner
        canvas.drawLine(
            toScreen(x, topY, z + d / 2),
            toScreen(x + w, topY, z + d / 2),
            strapPaint);

      case _CampingSubType.defaultCamping:
        // X-strap pattern + buckle indicator
        canvas.drawLine(toScreen(x, topY, z),
            toScreen(x + w, topY, z + d), strapPaint);
        canvas.drawLine(toScreen(x + w, topY, z),
            toScreen(x, topY, z + d), strapPaint);
        // Buckle indicator at center
        final cx = x + w / 2, cz = z + d / 2;
        final bucklePaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.40)!
          ..style = PaintingStyle.fill;
        final bw2 = w * 0.08, bd2 = d * 0.08;
        canvas.drawPath(
            buildPath([
              toScreen(cx - bw2, topY, cz - bd2),
              toScreen(cx + bw2, topY, cz - bd2),
              toScreen(cx + bw2, topY, cz + bd2),
              toScreen(cx - bw2, topY, cz + bd2),
            ]),
            bucklePaint);
    }
  }

  /// Draw an oval/ellipse on the top face to suggest a cylindrical bag
  void _drawOvalTopFace(Canvas canvas, double x, double topY, double z,
      double w, double d, Color baseColor) {
    final cx = x + w / 2, cz = z + d / 2;
    final rx = w * 0.42, rz = d * 0.42;
    const segs = 16;
    final ovalPts = <Offset>[];
    for (int i = 0; i < segs; i++) {
      final angle = 2 * math.pi * i / segs;
      ovalPts.add(toScreen(
          cx + rx * math.cos(angle), topY, cz + rz * math.sin(angle)));
    }
    final ovalPaint = Paint()
      ..color = Color.lerp(baseColor, Colors.black, 0.12)!
      ..style = PaintingStyle.fill;
    canvas.drawPath(buildPath(ovalPts), ovalPaint);
    final ovalStroke = Paint()
      ..color = Color.lerp(baseColor, Colors.black, 0.30)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(buildPath(ovalPts), ovalStroke);
  }

  // ── Category textures on FRONT face (z = frontZ) ──
  void _drawFrontFaceTexture(
      Canvas canvas,
      BoxCategory category,
      double x,
      double botY,
      double frontZ,
      double w,
      double h,
      Color baseColor,
      String label,
      double origWcm,
      double origDcm,
      double origHcm) {
    switch (category) {
      case BoxCategory.carrier:
        _drawCarrierFrontTexture(canvas, x, botY, frontZ, w, h, baseColor);
      case BoxCategory.moving:
        _drawMovingFrontTexture(canvas, x, botY, frontZ, w, h, baseColor);
      case BoxCategory.camping:
        _drawCampingFrontTexture(canvas, x, botY, frontZ, w, h, baseColor,
            label, origWcm, origDcm, origHcm);
      case BoxCategory.custom:
        break;
    }
  }

  void _drawCarrierFrontTexture(Canvas canvas, double x, double botY,
      double frontZ, double w, double h, Color baseColor) {
    // Handle on top of front face
    final handleColor = Color.lerp(baseColor, Colors.black, 0.35)!;
    final handlePaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final hw = w * 0.3;
    final hx = x + w / 2 - hw / 2;
    final hy = botY + h * 0.85;
    // U-shape handle
    canvas.drawLine(
        toScreen(hx, hy, frontZ),
        toScreen(hx, botY + h * 0.92, frontZ),
        handlePaint);
    canvas.drawLine(
        toScreen(hx, botY + h * 0.92, frontZ),
        toScreen(hx + hw, botY + h * 0.92, frontZ),
        handlePaint);
    canvas.drawLine(
        toScreen(hx + hw, botY + h * 0.92, frontZ),
        toScreen(hx + hw, hy, frontZ),
        handlePaint);
    // Zipper line across middle
    final zipPaint = Paint()
      ..color = Color.lerp(baseColor, Colors.black, 0.18)!.withAlpha(0x88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        toScreen(x + w * 0.05, botY + h * 0.5, frontZ),
        toScreen(x + w * 0.95, botY + h * 0.5, frontZ),
        zipPaint);
  }

  void _drawMovingFrontTexture(Canvas canvas, double x, double botY,
      double frontZ, double w, double h, Color baseColor) {
    // Cross tape on front face (vertical + horizontal)
    final tapeColor = Color.lerp(baseColor, Colors.white, 0.20)!;
    final tapePaint = Paint()
      ..color = tapeColor.withAlpha(0x88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    // Vertical center tape
    canvas.drawLine(
        toScreen(x + w / 2, botY, frontZ),
        toScreen(x + w / 2, botY + h, frontZ),
        tapePaint);
    // Horizontal center tape
    canvas.drawLine(
        toScreen(x, botY + h / 2, frontZ),
        toScreen(x + w, botY + h / 2, frontZ),
        tapePaint);
  }

  void _drawCampingFrontTexture(
      Canvas canvas,
      double x,
      double botY,
      double frontZ,
      double w,
      double h,
      Color baseColor,
      String label,
      double origWcm,
      double origDcm,
      double origHcm) {
    final subType = _inferCampingSubType(label, origWcm, origDcm, origHcm);

    switch (subType) {
      case _CampingSubType.tentBag:
        // Slightly darker ends — already handled by face shading
        // Draw end cap circle on front face (cylindrical look)
        final cx = x + w / 2, cy = botY + h / 2;
        final r = math.min(w, h) * 0.35;
        final circleSegs = 12;
        final circlePts = <Offset>[];
        for (int i = 0; i < circleSegs; i++) {
          final a = 2 * math.pi * i / circleSegs;
          circlePts.add(toScreen(
              cx + r * math.cos(a), cy + r * math.sin(a), frontZ));
        }
        final circlePaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.15)!.withAlpha(0x66)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(buildPath(circlePts), circlePaint);

      case _CampingSubType.cooler:
        // Handle U-shapes on front face (two handles)
        final handlePaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.30)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        final hw = w * 0.12;
        final hh = h * 0.08;
        // Left handle
        final lx = x + w * 0.2;
        final hy = botY + h * 0.88;
        canvas.drawLine(
            toScreen(lx, hy, frontZ),
            toScreen(lx, hy + hh, frontZ), handlePaint);
        canvas.drawLine(
            toScreen(lx, hy + hh, frontZ),
            toScreen(lx + hw, hy + hh, frontZ), handlePaint);
        canvas.drawLine(
            toScreen(lx + hw, hy + hh, frontZ),
            toScreen(lx + hw, hy, frontZ), handlePaint);
        // Right handle
        final rx = x + w * 0.68;
        canvas.drawLine(
            toScreen(rx, hy, frontZ),
            toScreen(rx, hy + hh, frontZ), handlePaint);
        canvas.drawLine(
            toScreen(rx, hy + hh, frontZ),
            toScreen(rx + hw, hy + hh, frontZ), handlePaint);
        canvas.drawLine(
            toScreen(rx + hw, hy + hh, frontZ),
            toScreen(rx + hw, hy, frontZ), handlePaint);
        // Lid line
        final lidPaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.22)!.withAlpha(0xAA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawLine(
            toScreen(x + w * 0.05, botY + h * 0.78, frontZ),
            toScreen(x + w * 0.95, botY + h * 0.78, frontZ),
            lidPaint);

      case _CampingSubType.chairBag:
        // Fabric bag cross-hatch on front face
        final hatchPaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.15)!.withAlpha(0x55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round;
        final count = 4;
        for (int i = 0; i <= count; i++) {
          final frac = i / count;
          canvas.drawLine(
              toScreen(x, botY + h * frac, frontZ),
              toScreen(x + w * frac, botY, frontZ),
              hatchPaint);
          canvas.drawLine(
              toScreen(x + w * frac, botY + h, frontZ),
              toScreen(x + w, botY + h * frac, frontZ),
              hatchPaint);
        }
        // Drawstring circle at top-center
        final dsCx = x + w / 2, dsCy = botY + h * 0.88;
        final dsR = math.min(w, h) * 0.12;
        final dsSegs = 10;
        final dsPts = <Offset>[];
        for (int i = 0; i < dsSegs; i++) {
          final a = 2 * math.pi * i / dsSegs;
          dsPts.add(toScreen(
              dsCx + dsR * math.cos(a), dsCy + dsR * math.sin(a), frontZ));
        }
        canvas.drawPath(
            buildPath(dsPts),
            Paint()
              ..color = Color.lerp(baseColor, Colors.black, 0.25)!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0);

      case _CampingSubType.container:
        // Horizontal ridge lines (3-4 lines)
        final ridgePaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.18)!.withAlpha(0xAA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        for (int i = 1; i <= 4; i++) {
          final frac = i / 5;
          canvas.drawLine(
              toScreen(x + w * 0.05, botY + h * frac, frontZ),
              toScreen(x + w * 0.95, botY + h * frac, frontZ),
              ridgePaint);
        }
        // Latch/handle rectangle indicators
        final latchPaint = Paint()
          ..color = Color.lerp(baseColor, Colors.black, 0.30)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        // Center latch
        final lw2 = w * 0.10, lh2 = h * 0.06;
        final lcx = x + w * 0.5, lcy = botY + h * 0.5;
        canvas.drawPath(
            buildPath([
              toScreen(lcx - lw2, lcy - lh2, frontZ),
              toScreen(lcx + lw2, lcy - lh2, frontZ),
              toScreen(lcx + lw2, lcy + lh2, frontZ),
              toScreen(lcx - lw2, lcy + lh2, frontZ),
            ]),
            latchPaint);

      case _CampingSubType.defaultCamping:
        // X-strap on front face + buckle
        final strapColor = Color.lerp(baseColor, Colors.black, 0.25)!;
        final strapPaint = Paint()
          ..color = strapColor.withAlpha(0x88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            toScreen(x, botY, frontZ),
            toScreen(x + w, botY + h, frontZ),
            strapPaint);
        canvas.drawLine(
            toScreen(x + w, botY, frontZ),
            toScreen(x, botY + h, frontZ),
            strapPaint);
        // Buckle at center
        final bcx = x + w / 2, bcy = botY + h / 2;
        final bw2 = w * 0.06, bh2 = h * 0.06;
        canvas.drawPath(
            buildPath([
              toScreen(bcx - bw2, bcy - bh2, frontZ),
              toScreen(bcx + bw2, bcy - bh2, frontZ),
              toScreen(bcx + bw2, bcy + bh2, frontZ),
              toScreen(bcx - bw2, bcy + bh2, frontZ),
            ]),
            Paint()
              ..color = Color.lerp(baseColor, Colors.black, 0.35)!
              ..style = PaintingStyle.fill);
    }
  }

  /// Render label text ON the front face of the box
  void _drawFrontFaceLabel(Canvas canvas, String label, double x, double botY,
      double frontZ, double w, double h, Color baseColor) {
    // Compute front face width and height in screen space
    final bl = toScreen(x, botY, frontZ);
    final br = toScreen(x + w, botY, frontZ);
    final tl = toScreen(x, botY + h, frontZ);
    final faceScreenW = (br.dx - bl.dx).abs();
    final faceScreenH = (bl.dy - tl.dy).abs();

    // Skip if face too small for text
    if (faceScreenW < 20 || faceScreenH < 12) return;

    // Scale font to fit — max 13px, min 7px
    final maxFontForWidth = faceScreenW * 0.8 / math.max(label.length * 0.55, 1);
    final maxFontForHeight = faceScreenH * 0.35;
    final fontSize = maxFontForWidth.clamp(7.0, 13.0).clamp(7.0, maxFontForHeight);

    if (fontSize < 7.0) return;

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0x99FFFFFF),
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '..',
    )..layout(maxWidth: faceScreenW * 0.9);

    // If laid out text is wider than face, skip (fallback to floating pill)
    if (tp.width > faceScreenW * 0.9) return;

    // Center of front face in screen coords
    final faceCenterX = (bl.dx + br.dx) / 2;
    final faceCenterY = (bl.dy + tl.dy) / 2;

    tp.paint(
      canvas,
      Offset(faceCenterX - tp.width / 2, faceCenterY - tp.height / 2),
    );
  }

  // ── Load Order Badge ──
  void drawLoadOrderBadge(
      Canvas canvas, TrimBox box, double bx, double bz, double bw, double bd) {
    if (box.loadOrder == null) return;

    // Center of the top face in screen space
    final topY = box.y + box.h;
    final center = toScreen(bx + bw / 2, topY, bz + bd / 2);

    // Calculate perspective-aware size: use distance between two top-face corners
    final left = toScreen(bx, topY, bz + bd / 2);
    final right = toScreen(bx + bw, topY, bz + bd / 2);
    final faceWidth = (right.dx - left.dx).abs();

    // Circle radius: proportional to face width, with min/max
    final radius = (faceWidth * 0.18).clamp(10.0, 22.0);
    final fontSize = (radius * 1.1).clamp(12.0, 20.0);

    // White circle background
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xEEFFFFFF)
        ..style = PaintingStyle.fill,
    );

    // Thin dark border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Number text
    final tp = TextPainter(
      text: TextSpan(
        text: '${box.loadOrder}',
        style: TextStyle(
          color: const Color(0xFF222222),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  // ── Labels ──
  void drawBoxLabelAt(
      Canvas canvas, TrimBox box, double bx, double bz, double bw, double bd) {
    final center = toScreen(bx + bw / 2, box.y + box.h, bz + bd / 2);
    final text =
        '${(box.effectiveW * 100).round()}×${(box.effectiveD * 100).round()}×${(box.h * 100).round()}cm';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bg = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 14),
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(bg, const Radius.circular(4)),
        Paint()..color = const Color(0xCC000000));
    tp.paint(canvas, Offset(bg.left + 4, bg.top + 2));
  }

  void drawBoxNameLabelAt(
      Canvas canvas, TrimBox box, double bx, double bz, double bw, double bd) {
    final center = toScreen(bx + bw / 2, box.y + box.h, bz + bd / 2);

    final topArea = bw * bd;
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
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Skip if label wider than box front face
    final frontW =
        (toScreen(bx + bw, box.y + box.h, bz + bd).dx -
                toScreen(bx, box.y + box.h, bz + bd).dx)
            .abs();
    if (tp.width > frontW) return;

    final labelCenter = Offset(center.dx, center.dy - 12);
    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: labelCenter,
          width: tp.width + 10,
          height: tp.height + 6),
      const Radius.circular(3),
    );
    canvas.drawRRect(bg, Paint()..color = const Color(0x99000000));
    tp.paint(
        canvas,
        Offset(labelCenter.dx - tp.width / 2,
            labelCenter.dy - tp.height / 2));
  }
}
