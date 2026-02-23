part of 'isometric_painter.dart';

/// 그리드, 오브젝트 배치, 스태킹 가이드, 치수 라벨 렌더링
extension GuideRendering on IsometricPainter {
  void drawGrid(Canvas canvas) {
    final pw = projW;
    final pd = projD;
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
  void drawObjects(Canvas canvas) {
    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;

    final List<({double depth, VoidCallback draw})> objects = [];

    // 휠하우스 → view-space 변환
    const whFill = Color(0xFF8A8A8A);
    const whStroke = Color(0xFF666666);

    final lvw = boxToView(0, space.d - lw.d, lw.w, lw.d);
    objects.add((
      depth: (lvw.vx + lvw.vw / 2) + (lvw.vz + lvw.vd / 2),
      draw: () {
        drawWheelhouse(
          canvas,
          x: lvw.vx, z: lvw.vz,
          w: lvw.vw, h: lw.h, d: lvw.vd,
          fillColor: whFill,
          strokeColor: whStroke,
        );
        drawWheelhouseTexture(canvas, lvw.vx, lw.h, lvw.vz, lvw.vw, lvw.vd);
      },
    ));

    final rvw = boxToView(space.w - rw.w, space.d - rw.d, rw.w, rw.d);
    objects.add((
      depth: (rvw.vx + rvw.vw / 2) + (rvw.vz + rvw.vd / 2),
      draw: () {
        drawWheelhouse(
          canvas,
          x: rvw.vx, z: rvw.vz,
          w: rvw.vw, h: rw.h, d: rvw.vd,
          fillColor: whFill,
          strokeColor: whStroke,
        );
        drawWheelhouseTexture(canvas, rvw.vx, rw.h, rvw.vz, rvw.vw, rvw.vd);
      },
    ));

    // 박스 → view-space 변환
    for (final box in boxes) {
      final vb = boxToView(box.x, box.z, box.effectiveW, box.effectiveD);
      final isSelected = box.id == selectedBoxId;
      final isColliding = collidingBoxIds.contains(box.id);

      // S9: 위치 기반 밝기 조정 (앞쪽 밝음, 뒤쪽 약간 어두움)
      final zNorm = projD > 0 ? (vb.vz + vb.vd / 2) / projD : 0.5;
      final depthDarken = (1.0 - zNorm) * 0.03;
      final adjustedColor = Color.lerp(box.color, Colors.black, depthDarken)!;

      Color strokeColor;
      double strokeWidth;
      if (isColliding) {
        strokeColor = const Color(0xFFFF4D4D);
        strokeWidth = 2.5;
      } else if (isSelected) {
        strokeColor = const Color(0xFF4DA3FF);
        strokeWidth = 2.5;
      } else {
        strokeColor = Color.lerp(adjustedColor, Colors.black, 0.35)!;
        strokeWidth = 1.2;
      }

      objects.add((
        depth: (vb.vx + vb.vw / 2) + (vb.vz + vb.vd / 2),
        draw: () {
          drawIsometricBox(
            canvas,
            x: vb.vx, y: box.y, z: vb.vz,
            w: vb.vw, h: box.h, d: vb.vd,
            fillColor: adjustedColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            isSelected: isSelected,
            category: box.category,
          );
          if (isSelected) {
            drawBoxLabelAt(canvas, box, vb);
          } else {
            drawBoxNameLabelAt(canvas, box, vb);
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

  /// 드래그 중 스태킹 가이드 렌더링
  void drawStackingGuides(Canvas canvas) {
    final dragBox = boxes.where((b) => b.id == draggingBoxId).firstOrNull;
    if (dragBox == null) return;

    final dragArea = dragBox.effectiveW * dragBox.effectiveD;

    for (final other in boxes) {
      if (other.id == dragBox.id) continue;

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

      final wouldExceed = topY + dragBox.h > space.h + 0.001;
      final guideColor = (isStackable && !wouldExceed)
          ? const Color(0x6600CC66)
          : const Color(0x55FF4444);

      final vb =
          boxToView(other.x, other.z, other.effectiveW, other.effectiveD);
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
  void drawDimensionLabels(Canvas canvas) {
    final pw = projW;
    final pd = projD;

    final wMid = toIso(pw / 2, 0, pd);
    paintDimLabel(
      canvas,
      '${(pw * 100).round()}cm',
      Offset(wMid.dx, wMid.dy + 16),
    );

    final dMid = toIso(pw, 0, pd / 2);
    paintDimLabel(
      canvas,
      '${(pd * 100).round()}cm',
      Offset(dMid.dx + 10, dMid.dy + 8),
    );

    final hMid = toIso(0, space.h / 2, 0);
    paintDimLabel(
      canvas,
      '↕${(space.h * 100).round()}cm',
      Offset(hMid.dx + 8, hMid.dy - 6),
    );
  }

  void paintDimLabel(Canvas canvas, String text, Offset pos) {
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
}
