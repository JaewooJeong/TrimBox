part of 'isometric_painter.dart';

/// Grid, object drawing, stacking guides, dimension labels
extension GuideRendering on IsometricPainter {
  void drawGrid(Canvas canvas) {
    final w = space.w, d = space.d;
    const unit = 0.10;
    const majorUnit = 0.50;

    final minorPaint = Paint()
      ..color = const Color(0x25999999)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final majorPaint = Paint()
      ..color = const Color(0x50AAAAAA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Lines along X (at each Z depth) — follow floor taper
    for (double z = 0; z <= d + 0.001; z += unit) {
      final xLeft = space.taperAt(z);
      final xRight = w - space.taperAt(z);
      final isMajor =
          (z / majorUnit - (z / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(
        toScreen(xLeft, 0, z),
        toScreen(xRight, 0, z),
        isMajor ? majorPaint : minorPaint,
      );
    }

    // Lines along Z (at each X position)
    for (double x = 0; x <= w + 0.001; x += unit) {
      final isMajor =
          (x / majorUnit - (x / majorUnit).round()).abs() < 0.001;
      canvas.drawLine(
        toScreen(x, 0, 0),
        toScreen(x, 0, d),
        isMajor ? majorPaint : minorPaint,
      );
    }
  }

  /// Depth sort key: front face z = closer to camera = drawn later
  double _objectDepth(double cx, double cz, [double cd = 0]) => cz + cd;

  /// Render wheelhousees + boxes depth-sorted
  void drawObjects(Canvas canvas) {
    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;

    final List<({double depth, VoidCallback draw})> objects = [];

    // Wheelhouse color matches trunk interior walls
    const whFill = Color(0xFF2D2A27);
    const whStroke = Color(0xFF1E1C1A);

    // Left wheelhouse (뒷축 쪽, z=0 근처)
    final lwx = 0.0, lwz = 0.0;
    objects.add((
      depth: _objectDepth(lwx + lw.w / 2, lwz, lw.d),
      draw: () {
        drawWheelhouse(canvas,
            x: lwx,
            z: lwz,
            w: lw.w,
            h: lw.h,
            d: lw.d,
            fillColor: whFill,
            strokeColor: whStroke);
      },
    ));

    // Right wheelhouse (뒷축 쪽, z=0 근처)
    final rwx = space.w - rw.w, rwz = 0.0;
    objects.add((
      depth: _objectDepth(rwx + rw.w / 2, rwz, rw.d),
      draw: () {
        drawWheelhouse(canvas,
            x: rwx,
            z: rwz,
            w: rw.w,
            h: rw.h,
            d: rw.d,
            fillColor: whFill,
            strokeColor: whStroke);
      },
    ));

    // Boxes
    for (final box in boxes) {
      final bw = box.effectiveW;
      final bd = box.effectiveD;
      final isSelected = box.id == selectedBoxId;
      final isColliding = collidingBoxIds.contains(box.id);

      // Step view filtering
      final stepMode = highlightLoadOrder != null;
      final order = box.loadOrder;
      if (stepMode && order == null) continue; // no load order → hide in step mode
      if (stepMode && order != null && order > highlightLoadOrder!) continue; // future steps hidden

      final isDimmed = stepMode && order != null && order < highlightLoadOrder!;
      final isCurrentStep = stepMode && order == highlightLoadOrder;

      Color strokeColor;
      double strokeWidth;
      if (isCurrentStep) {
        strokeColor = const Color(0xFF00E676);
        strokeWidth = 3.0;
      } else if (isColliding) {
        strokeColor = const Color(0xFFFF4D4D);
        strokeWidth = 2.5;
      } else if (isSelected) {
        strokeColor = const Color(0xFF4DA3FF);
        strokeWidth = 2.5;
      } else {
        strokeColor = Color.lerp(box.color, Colors.black, 0.35)!;
        strokeWidth = 1.2;
      }

      final effectiveColor = isDimmed
          ? Color.lerp(box.color, const Color(0xFF333333), 0.65)!
          : box.color;

      objects.add((
        depth: _objectDepth(box.x + bw / 2, box.z, bd),
        draw: () {
          drawIsometricBox(canvas,
              x: box.x,
              y: box.y,
              z: box.z,
              w: bw,
              h: box.h,
              d: bd,
              fillColor: effectiveColor,
              strokeColor: isDimmed
                  ? Color.lerp(strokeColor, const Color(0xFF333333), 0.5)!
                  : strokeColor,
              strokeWidth: strokeWidth,
              isSelected: isSelected && !stepMode,
              category: box.category,
              label: box.label,
              origWcm: box.w * 100,
              origDcm: box.d * 100,
              origHcm: box.h * 100);
          if (isSelected && !stepMode) {
            drawBoxLabelAt(canvas, box, box.x, box.z, bw, bd);
          }
          if (isCurrentStep) {
            drawBoxLabelAt(canvas, box, box.x, box.z, bw, bd);
          }
          drawLoadOrderBadge(canvas, box, box.x, box.z, bw, bd);
        },
      ));
    }

    // Painter's algorithm: lower depth drawn first
    objects.sort((a, b) => a.depth.compareTo(b.depth));
    for (final obj in objects) {
      obj.draw();
    }
  }

  /// Stacking guides during drag
  void drawStackingGuides(Canvas canvas) {
    final dragBox =
        boxes.where((b) => b.id == draggingBoxId).firstOrNull;
    if (dragBox == null) return;

    final dragArea = dragBox.effectiveW * dragBox.effectiveD;

    for (final other in boxes) {
      if (other.id == dragBox.id) continue;

      final overlapX =
          math.min(dragBox.x + dragBox.effectiveW,
                  other.x + other.effectiveW) -
              math.max(dragBox.x, other.x);
      final overlapZ =
          math.min(dragBox.z + dragBox.effectiveD,
                  other.z + other.effectiveD) -
              math.max(dragBox.z, other.z);

      if (overlapX <= 0 || overlapZ <= 0) continue;

      final overlapArea = overlapX * overlapZ;
      final isStackable = overlapArea >= dragArea * 0.5;
      final topY = other.y + other.h;
      final wouldExceed = topY + dragBox.h > space.h + 0.001;

      final guideColor = (isStackable && !wouldExceed)
          ? const Color(0x6600CC66)
          : const Color(0x55FF4444);

      final ow = other.effectiveW, od = other.effectiveD;
      final topFace = buildPath([
        toScreen(other.x, topY, other.z),
        toScreen(other.x + ow, topY, other.z),
        toScreen(other.x + ow, topY, other.z + od),
        toScreen(other.x, topY, other.z + od),
      ]);

      canvas.drawPath(
          topFace,
          Paint()
            ..color = guideColor
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          topFace,
          Paint()
            ..color = (isStackable && !wouldExceed)
                ? const Color(0xAA00CC66)
                : const Color(0xAAFF4444)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  /// Dimension labels at trunk opening edges
  void drawDimensionLabels(Canvas canvas) {
    final w = space.w, d = space.d, h = space.h;

    // Width at bottom of opening
    final wMid = toScreen(w / 2, 0, d);
    _paintDimLabel(
        canvas, '${(w * 100).round()}cm', Offset(wMid.dx, wMid.dy + 16));

    // Depth on right side
    final dMid = toScreen(w, 0, d / 2);
    _paintDimLabel(
        canvas, '${(d * 100).round()}cm', Offset(dMid.dx + 16, dMid.dy));

    // Height on left edge of opening
    final hBot = toScreen(0, 0, d);
    final hTop = toScreen(0, h, d);
    final hMid = Offset(
        (hBot.dx + hTop.dx) / 2 - 20, (hBot.dy + hTop.dy) / 2);
    _paintDimLabel(canvas, '↕${(h * 100).round()}cm', hMid);
  }

  void _paintDimLabel(Canvas canvas, String text, Offset pos) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: Color(0x99FFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }
}
