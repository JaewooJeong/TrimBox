import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import 'camera.dart';
import 'depth_sort.dart';
import 'geometry.dart';
import 'vec3.dart';

/// 정적 트렁크 껍데기 렌더링을 카메라·크기·트렁크가 같을 때 재사용하기 위한 캐시.
/// 드래그 중(카메라 고정)에는 박스만 다시 그린다.
class SceneCache {
  OrbitCamera? camera;
  Size? size;
  TrunkSpace? space;
  ui.Picture? shell;

  bool matches(OrbitCamera cam, Size sz, TrunkSpace sp) =>
      shell != null && camera == cam && size == sz && identical(space, sp);

  void store(OrbitCamera cam, Size sz, TrunkSpace sp, ui.Picture pic) {
    shell?.dispose();
    camera = cam;
    size = sz;
    space = sp;
    shell = pic;
  }

  void dispose() {
    shell?.dispose();
    shell = null;
  }
}

class _SceneObject {
  final Aabb aabb;
  final Color color;
  final TrimBox? box;

  /// 지정하면 AABB 면 대신 이 면들을 그린다 (개구부 프레임 등)
  final List<Face>? faces;

  const _SceneObject(this.aabb, this.color, this.box, {this.faces});

  bool get isFixture => box == null;
}

/// 원근 카메라 + painter's algorithm 기반 트렁크 3D 페인터.
///
/// 그리기 순서: 배경 → 트렁크 껍데기(법선 컬링, 먼 면부터) →
/// 휠하우스·박스(뒤→앞 위상 정렬) → 캡션.
class TrunkPainter3D extends CustomPainter {
  final TrunkSpace space;
  final List<TrimBox> boxes;
  final OrbitCamera camera;
  final String? selectedBoxId;
  final Set<String> collidingBoxIds;
  final String? draggingBoxId;

  /// 테일게이트를 못 닫게 하는 박스 (닫힘 한계 면을 빨갛게 보여준다)
  final Set<String> tailgateBlockedIds;

  /// 적재 순서 스텝 뷰: null 이면 전부 표시. 값이 있으면 그보다 큰 loadOrder는
  /// 숨기고, 작은 것은 흐리게 그린다.
  final int? highlightLoadOrder;
  final SceneCache? cache;
  final bool showLabels;

  TrunkPainter3D({
    required this.space,
    required this.boxes,
    required this.camera,
    this.selectedBoxId,
    this.collidingBoxIds = const {},
    this.draggingBoxId,
    this.tailgateBlockedIds = const {},
    this.highlightLoadOrder,
    this.cache,
    this.showLabels = true,
  });

  static const Color _bgTop = Color(0xFF1B1E22);
  static const Color _bgBottom = Color(0xFF101214);
  static const Color _floorColor = Color(0xFF3D3D40);
  static const Color _wallColor = Color(0xFF55524F);
  static const Color _ceilingColor = Color(0xFF605D5A);
  static const Color _seatColor = Color(0xFF3C4046);
  static const Color _wheelhouseColor = Color(0xFF66625E);
  static const Color _frameColor = Color(0xFF2B2D31);
  static const Color _limitLine = Color(0xFFFFC46B);
  static const Color _accent = Color(0xFF4DA3FF);
  static const Color _danger = Color(0xFFFF4D4D);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintShell(canvas, size);
    _paintObjects(canvas, size);
    _paintTailgateWarning(canvas, size);
    _paintCaption(canvas, size);
  }

  // ── 배경 ──

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          const [_bgTop, _bgBottom],
        ),
    );
  }

  // ── 껍데기 ──

  void _paintShell(Canvas canvas, Size size) {
    final c = cache;
    if (c != null && c.matches(camera, size, space)) {
      canvas.drawPicture(c.shell!);
      return;
    }
    final recorder = ui.PictureRecorder();
    final rc = Canvas(recorder, Offset.zero & size);
    _drawShell(rc, size);
    final pic = recorder.endRecording();
    if (c != null) {
      c.store(camera, size, space, pic);
      canvas.drawPicture(pic);
    } else {
      canvas.drawPicture(pic);
      pic.dispose();
    }
  }

  Color _shellBase(ShellPart part) => switch (part) {
        ShellPart.floor => _floorColor,
        ShellPart.ceiling => _ceilingColor,
        ShellPart.leftWall || ShellPart.rightWall => _wallColor,
        ShellPart.seatBack => _seatColor,
        ShellPart.frame => _frameColor,
        ShellPart.tailgate => _wallColor,
      };

  void _drawShell(Canvas canvas, Size size) {
    final camPos = camera.position;
    final faces = buildTrunkShell(space, stations: 10)
        .where((f) => f.face.facesCamera(camPos))
        .toList()
      ..sort((a, b) => (b.face.centroid - camPos)
          .length
          .compareTo((a.face.centroid - camPos).length));

    _drawOutsideGround(canvas, size);

    var seatVisible = false;
    for (final sf in faces) {
      final path = _projectPath(sf.face.pts, size);
      if (path == null) continue;
      final color = shadeColor(_shellBase(sf.part), sf.face.normal);
      canvas.drawPath(path, Paint()..color = color);
      // 인접 면 사이 안티앨리어싱 틈 메우기
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      if (sf.part == ShellPart.seatBack) seatVisible = true;
    }

    _drawFloorGrid(canvas, size);
    if (seatVisible) _drawSeatSplitLines(canvas, size);
    _drawTailgateLimitLines(canvas, size);
    _drawOpeningOutline(canvas, size);
  }

  /// 닫힌 테일게이트 안쪽 면이 양쪽 벽과 만나는 선 (= 이 선 뒤로는 못 놓음).
  /// 프레임 구간 안쪽은 프레임 면이 가리므로 프레임 앞까지만 그린다.
  void _drawTailgateLimitLines(Canvas canvas, Size size) {
    if (!space.hasTailgateModel) return;
    final prof = rearProfilePolyline(space);
    if (prof.length < 2) return;
    final paint = Paint()
      ..color = _limitLine.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final side in [0, 1]) {
      final pts = <Vec3>[];
      for (final p in prof) {
        final x = side == 0
            ? space.xMinAt(p.z, p.y) + 0.004
            : space.xMaxAt(p.z, p.y) - 0.004;
        pts.add(Vec3(x, p.y, p.z));
      }
      final proj = _projectPoints(pts, size);
      if (proj == null) continue;
      _drawDashedPolyline(canvas, proj, paint);
    }
    // 바닥에도: 테일게이트 바닥선에서 천장 한계까지 안쪽으로 얼마나 들어오는지
    final zTop = prof.last.z;
    if (space.d - zTop > 0.01) {
      final floor = _projectPoints([
        Vec3(space.xMinAt(zTop, 0), 0.002, zTop),
        Vec3(space.xMaxAt(zTop, 0), 0.002, zTop),
      ], size);
      if (floor != null) {
        _drawDashedPolyline(canvas, floor,
            Paint()
              ..color = _limitLine.withValues(alpha: 0.35)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke);
      }
    }
  }

  void _drawDashedPolyline(Canvas canvas, List<Offset> pts, Paint paint,
      {double dash = 6, double gap = 4}) {
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final len = (b - a).distance;
      if (len < 1e-3) continue;
      final dir = (b - a) / len;
      var t = 0.0;
      while (t < len) {
        final e = math.min(len, t + dash);
        canvas.drawLine(a + dir * t, a + dir * e, paint);
        t = e + gap;
      }
    }
  }

  /// 테일게이트가 안 닫힐 때: 닫힘 한계 면을 반투명 빨강으로 덮어 보여준다.
  void _paintTailgateWarning(Canvas canvas, Size size) {
    if (tailgateBlockedIds.isEmpty || !space.hasTailgateModel) return;
    final fill = Paint()..color = _danger.withValues(alpha: 0.16);
    final edge = Paint()
      ..color = _danger.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final f in tailgateFaces(space)) {
      final path = _projectPath(f.pts, size);
      if (path == null) continue;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }
  }

  /// 테일게이트 바깥 지면 (못 넣은 짐을 세워 두는 자리)
  void _drawOutsideGround(Canvas canvas, Size size) {
    if (camera.position.y <= 0.01) return;
    final path = _projectPath([
      Vec3(-0.15, -0.002, space.d),
      Vec3(space.w + 0.15, -0.002, space.d),
      Vec3(space.w + 0.15, -0.002, space.d + 0.8),
      Vec3(-0.15, -0.002, space.d + 0.8),
    ], size);
    if (path == null) return;
    canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.05));
  }

  void _drawFloorGrid(Canvas canvas, Size size) {
    final outline = _projectPath(floorOutline(space, stations: 10), size);
    if (outline == null) return;
    final camPos = camera.position;
    // 바닥이 카메라를 향할 때만 (아래에서 올려다보면 생략)
    if (camPos.y <= 0.01) return;

    canvas.save();
    canvas.clipPath(outline);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..strokeWidth = 1.0;
    final strong = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;
    const step = 0.1;
    for (var i = 0; i * step <= space.w + 1e-9; i++) {
      final x = i * step;
      _drawSegment(canvas, size, Vec3(x, 0.001, 0), Vec3(x, 0.001, space.d),
          i % 5 == 0 ? strong : paint);
    }
    for (var i = 0; i * step <= space.d + 1e-9; i++) {
      final z = i * step;
      _drawSegment(canvas, size, Vec3(0, 0.001, z), Vec3(space.w, 0.001, z),
          i % 5 == 0 ? strong : paint);
    }
    canvas.restore();
  }

  void _drawSeatSplitLines(Canvas canvas, Size size) {
    final ratios = space.seatSplitRatio;
    if (ratios == null || ratios.length < 2) return;
    final xl = space.xMinAt(0, 0);
    final xr = space.xMaxAt(0, 0);
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..strokeWidth = 2.0;
    // 등받이 프로필을 따라 (기울어진 등받이도 선이 면 위에 붙도록)
    final prof = frontProfilePolyline(space);
    var cum = 0.0;
    for (var i = 0; i < ratios.length - 1; i++) {
      cum += ratios[i];
      final x = xl + (xr - xl) * cum;
      for (var k = 0; k + 1 < prof.length; k++) {
        final a = prof[k], b = prof[k + 1];
        final y0 = math.max(a.y, 0.03);
        final y1 = math.min(b.y, space.h - 0.03);
        if (y1 <= y0) continue;
        double zAt(double y) => a.z + (b.z - a.z) * (y - a.y) / (b.y - a.y);
        _drawSegment(canvas, size, Vec3(x, y0, zAt(y0) + 0.003),
            Vec3(x, y1, zAt(y1) + 0.003), paint);
      }
    }
  }

  void _drawOpeningOutline(Canvas canvas, Size size) {
    final path = _projectPath(openingOutline(space), size);
    if (path == null) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // ── 물체 ──

  void _paintObjects(Canvas canvas, Size size) {
    final objects = <_SceneObject>[];
    final lw = Aabb.leftWheelhouse(space);
    if (!lw.isEmpty) objects.add(_SceneObject(lw, _wheelhouseColor, null));
    final rw = Aabb.rightWheelhouse(space);
    if (!rw.isEmpty) objects.add(_SceneObject(rw, _wheelhouseColor, null));
    objects.addAll(_frameObjects());

    for (final b in boxes) {
      if (!_isVisibleInStepView(b)) continue;
      objects.add(_SceneObject(Aabb.fromBox(b), b.color, b));
    }
    if (objects.isEmpty) return;

    final camPos = camera.position;
    final order = sortBackToFront(objects.map((o) => o.aabb).toList(), camPos);
    for (final idx in order) {
      _drawObject(canvas, size, objects[idx], camPos);
    }
  }

  /// 개구부 프레임(D필러 트림·헤더)을 고정물 3개로. AABB 는 정렬용이며
  /// 실제 면은 [frameFaces] 의 사다리꼴이다.
  List<_SceneObject> _frameObjects() {
    final ap = space.aperture;
    if (ap == null) return const [];
    final zf = space.d - ap.frameDepth;
    final ceil = space.interiorCeilingAt(zf);
    final top = math.min(ap.height, ceil);
    final xl = space.xMinAt(zf - 1e-6, 0), xr = space.xMaxAt(zf - 1e-6, 0);
    final al0 = (space.w - ap.widthAt(0)) / 2;
    final faces = frameFaces(space).map((f) => f.face).toList();
    // 왼쪽 기둥 / 오른쪽 기둥 / 헤더로 면을 나눈다
    final left = <Face>[], right = <Face>[], header = <Face>[];
    for (final f in faces) {
      final c = f.centroid;
      if (c.y >= top - 1e-6) {
        header.add(f);
      } else if (c.x < space.w / 2) {
        left.add(f);
      } else {
        right.add(f);
      }
    }
    final out = <_SceneObject>[];
    if (left.isNotEmpty && al0 > xl + 1e-6) {
      out.add(_SceneObject(Aabb(xl, 0, zf, al0, top, space.d), _frameColor, null,
          faces: left));
    }
    if (right.isNotEmpty && space.w - al0 < xr - 1e-6) {
      out.add(_SceneObject(
          Aabb(space.w - al0, 0, zf, xr, top, space.d), _frameColor, null,
          faces: right));
    }
    if (header.isNotEmpty && ceil > top + 1e-6) {
      out.add(_SceneObject(Aabb(xl, top, zf, xr, ceil, space.d), _frameColor, null,
          faces: header));
    }
    return out;
  }

  bool _isVisibleInStepView(TrimBox b) {
    final h = highlightLoadOrder;
    if (h == null || b.loadOrder == null) return true;
    return b.loadOrder! <= h;
  }

  double _opacityFor(TrimBox? b) {
    if (b == null) return 1.0;
    final h = highlightLoadOrder;
    if (h != null && b.loadOrder != null && b.loadOrder! < h) return 0.35;
    if (b.id == draggingBoxId) return 0.9;
    return 1.0;
  }

  void _drawObject(Canvas canvas, Size size, _SceneObject obj, Vec3 camPos) {
    final box = obj.box;
    final isColliding = box != null && collidingBoxIds.contains(box.id);
    final isSelected = box != null && box.id == selectedBoxId;
    final opacity = _opacityFor(box);

    var base = obj.color;
    if (isColliding) base = Color.lerp(base, _danger, 0.45)!;

    if (box != null) _drawContactShadow(canvas, size, obj.aabb, opacity);

    final faces =
        (obj.faces ?? aabbFaces(obj.aabb)).where((f) => f.facesCamera(camPos));
    Path? largestPath;
    var largestArea = 0.0;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Color.lerp(base, Colors.black, 0.55)!
          .withValues(alpha: 0.9 * opacity);

    for (final f in faces) {
      final pts = _projectPoints(f.pts, size);
      if (pts == null) continue;
      final path = _pathFrom(pts);
      final color = shadeColor(base, f.normal).withValues(alpha: opacity);
      canvas.drawPath(path, Paint()..color = color);
      if (obj.isFixture) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.black.withValues(alpha: 0.35),
        );
      } else {
        canvas.drawPath(path, edgePaint);
      }
      final area = _polygonArea(pts);
      if (area > largestArea) {
        largestArea = area;
        largestPath = path;
      }
    }

    if (box == null) return;

    if (isSelected || isColliding) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 2.0
        ..color = (isSelected ? _accent : _danger).withValues(alpha: opacity);
      for (final f in faces) {
        final pts = _projectPoints(f.pts, size);
        if (pts == null) continue;
        canvas.drawPath(_pathFrom(pts), outline);
      }
    }

    if (showLabels && largestPath != null && largestArea > 700) {
      _drawLabel(canvas, box, largestPath, largestArea, opacity);
    }
  }

  void _drawContactShadow(
      Canvas canvas, Size size, Aabb a, double opacity) {
    const pad = 0.015;
    final y = a.y1 + 0.002;
    final pts = _projectPoints([
      Vec3(a.x1 - pad, y, a.z1 - pad),
      Vec3(a.x2 + pad, y, a.z1 - pad),
      Vec3(a.x2 + pad, y, a.z2 + pad),
      Vec3(a.x1 - pad, y, a.z2 + pad),
    ], size);
    if (pts == null) return;
    canvas.drawPath(
      _pathFrom(pts),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _drawLabel(Canvas canvas, TrimBox box, Path facePath, double area,
      double opacity) {
    final bounds = facePath.getBounds();
    final maxW = math.max(40.0, math.min(bounds.width - 8, 160.0));
    final tp = TextPainter(
      text: TextSpan(
        text: box.isSquashed
            ? '${box.label} ↓${(box.squashAmount * 100).round()}%'
            : box.label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    if (tp.width > bounds.width + 4) return;

    final center = bounds.center;
    final pill = Rect.fromCenter(
      center: center,
      width: tp.width + 12,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.55 * opacity),
    );
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final order = box.loadOrder;
    if (order != null) {
      final c = Offset(bounds.left + 12, bounds.top + 12);
      canvas.drawCircle(
          c, 10, Paint()..color = _accent.withValues(alpha: opacity));
      final np = TextPainter(
        text: TextSpan(
          text: '$order',
          style: TextStyle(
            color: Colors.white.withValues(alpha: opacity),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      np.paint(canvas, Offset(c.dx - np.width / 2, c.dy - np.height / 2));
    }
  }

  // ── 캡션 ──

  void _paintCaption(Canvas canvas, Size size) {
    final name = space.vehicleName ?? '커스텀';
    final wIn = (space.floorWidthBetweenWheelhouses * 100).round();
    final wMax = (space.w * 100).round();
    final widthText = wIn < wMax ? '폭 $wIn~$wMax' : '폭 $wMax';
    final hMin = (space.ceilingHeightAt(space.rearDepthAt(space.h)) * 100).round();
    final hMax = (space.h * 100).round();
    final heightText = hMin < hMax ? '높이 $hMin~$hMax' : '높이 $hMax';
    final official = space.officialVolumeLabel;
    final text =
        '$name · $widthText × 깊이 ${(space.d * 100).round()} × $heightText cm${official != null ? ' · $official' : ''}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 12,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var y = size.height - tp.height - 10;
    tp.paint(canvas, Offset(12, y));

    if (space.hasTailgateModel && boxes.isNotEmpty) {
      final blocked = tailgateBlockedIds.length;
      final status = blocked == 0
          ? '테일게이트 닫힘 OK'
          : '테일게이트 안 닫힘 · $blocked개 걸림';
      final color = blocked == 0 ? const Color(0xFF6BD06B) : _danger;
      final sp = TextPainter(
        text: TextSpan(
          text: status,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      y -= sp.height + 4;
      final pill = Rect.fromLTWH(8, y - 3, sp.width + 12, sp.height + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(6)),
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
      sp.paint(canvas, Offset(14, y));
    }
  }

  // ── 투영 헬퍼 ──

  List<Offset>? _projectPoints(List<Vec3> pts, Size size) {
    final out = <Offset>[];
    for (final p in pts) {
      final pp = camera.project(p, size);
      if (pp == null) return null;
      out.add(pp.screen);
    }
    return out;
  }

  Path? _projectPath(List<Vec3> pts, Size size) {
    final proj = _projectPoints(pts, size);
    if (proj == null) return null;
    return _pathFrom(proj);
  }

  Path _pathFrom(List<Offset> pts) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  void _drawSegment(Canvas canvas, Size size, Vec3 a, Vec3 b, Paint paint) {
    final pa = camera.project(a, size);
    final pb = camera.project(b, size);
    if (pa == null || pb == null) return;
    canvas.drawLine(pa.screen, pb.screen, paint);
  }

  double _polygonArea(List<Offset> pts) {
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }

  @override
  bool shouldRepaint(covariant TrunkPainter3D old) => true;
}
