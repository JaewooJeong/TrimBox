import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import '../utils/load_stats.dart';
import 'camera.dart';
import 'fixtures.dart';
import 'gear_shapes.dart';
import 'geometry.dart';
import 'label_layout.dart';
import 'mesh.dart';
import 'scene.dart';
import 'vec3.dart';

/// 정적 트렁크 껍데기 렌더링을 카메라·크기·트렁크가 같을 때 재사용하기 위한 캐시.
/// 드래그 중(카메라 고정)에는 박스만 다시 그린다.
class SceneCache {
  OrbitCamera? camera;
  Size? size;
  TrunkSpace? space;
  ui.Picture? shell;

  /// 고정물 메시(휠하우스·프레임·차체 윤곽)는 트렁크가 같으면 그대로 쓴다
  TrunkSpace? _fixtureSpace;
  List<FixtureObject>? _fixtures;

  List<FixtureObject> fixturesFor(TrunkSpace sp) {
    if (_fixtures == null || !identical(_fixtureSpace, sp)) {
      _fixtureSpace = sp;
      _fixtures = buildSceneFixtures(sp);
    }
    return _fixtures!;
  }

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

/// 캔버스 상태 표시의 종류 (색을 정한다)
enum CaptionStatusKind { ok, unloaded, blocked }

/// 원근 카메라 + painter's algorithm 기반 트렁크 3D 페인터.
///
/// 그리기 순서: 배경 → 트렁크 껍데기(캐시: 차 밖 범퍼, 바닥·벽·천장, 매트·격자·
/// 접촉 음영, 벽 포켓, 등받이 쿠션·헤드레스트) → 고정물·박스(뒤→앞 위상 정렬,
/// 물체 안에서는 법선 컬링 — 모든 메시가 볼록) → 테일게이트 경고 → 캡션.
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
  static const Color _floorColor = Color(0xFF37373A); // 카펫
  static const Color _wallColor = Color(0xFF56534F); // 플라스틱 사이드 트림
  static const Color _ceilingColor = Color(0xFF8C8985); // 헤드라이너
  static const Color _seatGapColor = Color(0xFF24262A);
  static const Color _cushionColor = Color(0xFF494D55);
  static const Color _headrestColor = Color(0xFF52565E);
  static const Color _recessColor = Color(0xFF131518);
  static const Color _bumperColor = Color(0xFF2A2C30);
  static const Color _scuffColor = Color(0xFF7E838A);
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

  /// 성능 측정용: 박스·고정물 패스만 그린다.
  @visibleForTesting
  void paintObjectsOnly(Canvas canvas, Size size) => _paintObjects(canvas, size);

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

  // ── 껍데기 (정적 → Picture 캐시) ──

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
        ShellPart.seatBack => _seatGapColor,
        ShellPart.seatRecess => _recessColor,
        ShellPart.frame => frameColor,
        ShellPart.tailgate => _wallColor,
      };

  /// 빛은 열린 테일게이트 쪽에서 들어온다: 안쪽(z 작은 쪽)일수록 어둡게.
  double _depthLight(double z) {
    if (space.d <= 0) return 1.0;
    return 0.80 + 0.20 * (z / space.d).clamp(0.0, 1.0);
  }

  Color _scale(Color c, double k) => Color.fromARGB(
        (c.a * 255).round(),
        (c.r * 255 * k).round().clamp(0, 255),
        (c.g * 255 * k).round().clamp(0, 255),
        (c.b * 255 * k).round().clamp(0, 255),
      );

  void _drawShell(Canvas canvas, Size size) {
    final camPos = camera.position;
    final seat = seatLayout(space);
    final faces = drawnShell(space, stations: 10)
        .where((f) => f.face.facesCamera(camPos))
        .toList()
      ..sort((a, b) => (b.face.centroid - camPos)
          .length
          .compareTo((a.face.centroid - camPos).length));

    _drawOutside(canvas, size);

    var seatVisible = false;
    final fill = Paint();
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final sf in faces) {
      final path = _projectPath(sf.face.pts, size);
      if (path == null) continue;
      final lit = sf.part == ShellPart.seatRecess
          ? 1.0
          : _depthLight(sf.face.centroid.z);
      final color = shadeColor(_scale(_shellBase(sf.part), lit), sf.face.normal);
      canvas.drawPath(path, fill..color = color);
      // 인접 면 사이 안티앨리어싱 틈 메우기
      canvas.drawPath(path, gap..color = color);
      if (sf.part == ShellPart.seatBack) seatVisible = true;
    }

    _drawFloorDetails(canvas, size);
    _drawWallDetails(canvas, size, camPos);
    if (seatVisible && seat != null) _drawSeat(canvas, size, seat, camPos);
    _drawSeatLimitOutline(canvas, size, camPos);
    _drawTailgateLimitLines(canvas, size);
    if (space.aperture == null) _drawOpeningOutline(canvas, size);
  }

  /// 차 밖: 범퍼 윗면(바닥보다 2.5cm 낮은 턱)과 못 넣은 짐을 세워 두는 자리
  void _drawOutside(Canvas canvas, Size size) {
    if (camera.position.y <= 0.01) return;
    final ext = bodyOverhang(space);
    final d = space.d, x0 = -ext, x1 = space.w + ext;
    const sillY = -0.025, bumperZ = 0.12;

    void quad(List<Vec3> pts, Color color, Vec3 normal) {
      final path = _projectPath(pts, size);
      if (path == null) return;
      canvas.drawPath(path, Paint()..color = shadeColor(color, normal));
    }

    // 범퍼 뒷면 (아래로 말려 내려감) → 윗면 → 턱
    quad([
      Vec3(x0, sillY, d + bumperZ),
      Vec3(x1, sillY, d + bumperZ),
      Vec3(x1 - 0.02, sillY - 0.16, d + bumperZ + 0.035),
      Vec3(x0 + 0.02, sillY - 0.16, d + bumperZ + 0.035),
    ], _scale(_bumperColor, 0.8), const Vec3(0, 0.21, 0.98));
    quad([
      Vec3(x0, sillY, d),
      Vec3(x1, sillY, d),
      Vec3(x1, sillY, d + bumperZ),
      Vec3(x0, sillY, d + bumperZ),
    ], _bumperColor, const Vec3(0, 1, 0));
    // 범퍼 보호 플레이트
    final al = _apertureInset();
    quad([
      Vec3(al + 0.03, sillY + 0.001, d + 0.035),
      Vec3(space.w - al - 0.03, sillY + 0.001, d + 0.035),
      Vec3(space.w - al - 0.05, sillY + 0.001, d + 0.10),
      Vec3(al + 0.05, sillY + 0.001, d + 0.10),
    ], _scale(_scuffColor, 0.62), const Vec3(0, 1, 0));
    quad([
      Vec3(x0, sillY, d),
      Vec3(x1, sillY, d),
      Vec3(x1, 0, d),
      Vec3(x0, 0, d),
    ], _scale(_bumperColor, 0.55), const Vec3(0, 0, 1));

    // 테일게이트 바깥 지면 (못 넣은 짐을 세워 두는 자리)
    final ground = _projectPath([
      Vec3(-0.15, -0.002, d + bumperZ),
      Vec3(space.w + 0.15, -0.002, d + bumperZ),
      Vec3(space.w + 0.15, -0.002, d + 0.8),
      Vec3(-0.15, -0.002, d + 0.8),
    ], size);
    if (ground != null) {
      canvas.drawPath(
          ground, Paint()..color = Colors.white.withValues(alpha: 0.05));
    }
  }

  /// 바닥 높이에서 개구부가 벽보다 안쪽으로 들어온 거리 (개구부 모델이 없으면 벽)
  double _apertureInset() {
    final ap = space.aperture;
    if (ap == null) return space.xMinAt(space.d, 0);
    return math.max(0.0, (space.w - ap.widthAt(0)) / 2);
  }

  double get _zWallMax => space.aperture == null
      ? space.d
      : space.d - space.aperture!.frameDepth - 1e-6;

  void _fillPoly(Canvas canvas, Size size, List<Vec3> pts, Paint paint) {
    final path = _projectPath(pts, size);
    if (path != null) canvas.drawPath(path, paint);
  }

  /// 바닥: 카고 매트, 10cm 격자, 벽·등받이·휠하우스와 만나는 곳의 접촉 음영, 스커프 플레이트
  void _drawFloorDetails(Canvas canvas, Size size) {
    if (camera.position.y <= 0.01) return;
    final outline = _projectPath(floorOutline(space, stations: 10), size);
    if (outline == null) return;
    final s = space;
    const y = 0.0012;

    canvas.save();
    canvas.clipPath(outline);

    // 2열을 앞으로 당기면 등받이와 바닥 사이에 빈틈이 생긴다 (짐을 받칠 바닥이 없다)
    final gapStrip = seatGapStrip(s, y: y);
    final gapZ = gapStrip == null ? 0.0 : gapStrip[2].z;
    if (gapStrip != null) {
      _fillPoly(canvas, size, gapStrip, Paint()..color = _recessColor);
    }

    // 카고 매트 (휠하우스 사이, 모서리를 딴 직사각형)
    final taper0 = s.taperAt(0);
    final mx0 = math.max(s.leftWheelhouse.w, taper0) + 0.02;
    final mx1 = s.w - math.max(s.rightWheelhouse.w, taper0) - 0.02;
    final mz0 = gapZ + 0.03, mz1 = s.d - 0.085;
    if (mx1 - mx0 > 0.2 && mz1 - mz0 > 0.2) {
      const c = 0.03;
      final mat = [
        Vec3(mx0 + c, y, mz0), Vec3(mx1 - c, y, mz0), Vec3(mx1, y, mz0 + c), //
        Vec3(mx1, y, mz1 - c), Vec3(mx1 - c, y, mz1), Vec3(mx0 + c, y, mz1),
        Vec3(mx0, y, mz1 - c), Vec3(mx0, y, mz0 + c),
      ];
      final path = _projectPath(mat, size);
      if (path != null) {
        final base = shadeColor(
            Color.lerp(_floorColor, Colors.white, 0.075)!, Vec3.unitY);
        canvas.drawPath(path, Paint()..color = base.withValues(alpha: 0.9));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.black.withValues(alpha: 0.35),
        );
      }
    }

    // 격자: 10cm, 50cm 마다 진하게
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1.0;
    final strong = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    const step = 0.1;
    for (var i = 0; i * step <= s.w + 1e-9; i++) {
      final x = i * step;
      _drawSegment(canvas, size, Vec3(x, y, gapZ), Vec3(x, y, s.d),
          i % 5 == 0 ? strong : thin);
    }
    for (var i = 0; i * step <= s.d + 1e-9; i++) {
      final z = i * step;
      if (z < gapZ - 1e-9) continue;
      _drawSegment(canvas, size, Vec3(0, y, z), Vec3(s.w, y, z),
          i % 5 == 0 ? strong : thin);
    }

    // 접촉 음영 (값싼 앰비언트 오클루전): 넓고 옅은 띠 + 좁고 진한 띠
    final zw = _zWallMax;
    for (final layer in const [[0.075, 0.10], [0.035, 0.14]]) {
      final wdt = layer[0];
      final p = Paint()..color = Colors.black.withValues(alpha: layer[1]);
      // 양쪽 벽
      _fillPoly(canvas, size, [
        Vec3(s.xMinAt(0, 0), y, 0),
        Vec3(s.xMinAt(zw, 0), y, s.d),
        Vec3(s.xMinAt(zw, 0) + wdt, y, s.d),
        Vec3(s.xMinAt(0, 0) + wdt, y, 0),
      ], p);
      _fillPoly(canvas, size, [
        Vec3(s.xMaxAt(0, 0), y, 0),
        Vec3(s.xMaxAt(zw, 0), y, s.d),
        Vec3(s.xMaxAt(zw, 0) - wdt, y, s.d),
        Vec3(s.xMaxAt(0, 0) - wdt, y, 0),
      ], p);
      // 등받이 밑 (빈틈이 있으면 바닥이 시작되는 곳)
      _fillPoly(canvas, size, [
        Vec3(0, y, gapZ), Vec3(s.w, y, gapZ), //
        Vec3(s.w, y, gapZ + wdt), Vec3(0, y, gapZ + wdt),
      ], p);
      // 휠하우스 둘레
      for (final a in [Aabb.leftWheelhouse(s), Aabb.rightWheelhouse(s)]) {
        if (a.isEmpty) continue;
        _fillPoly(canvas, size, [
          Vec3(a.x1 - wdt, y, a.z1 - wdt),
          Vec3(a.x2 + wdt, y, a.z1 - wdt),
          Vec3(a.x2 + wdt, y, a.z2 + wdt),
          Vec3(a.x1 - wdt, y, a.z2 + wdt),
        ], p);
      }
    }
    if (gapZ > 0.005) {
      _drawSegment(
        canvas,
        size,
        Vec3(s.xMinAt(gapZ, 0), y, gapZ),
        Vec3(s.xMaxAt(gapZ, 0), y, gapZ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();

    // 스커프 플레이트 (개구부 문턱): 밝은 수지 띠 + 미끄럼 방지 리브
    final al = _apertureInset();
    final sx0 = al + 0.006, sx1 = s.w - al - 0.006;
    final sz0 = s.d - 0.06, sz1 = s.d - 0.003;
    if (sx1 - sx0 > 0.2) {
      final plate = _projectPath([
        Vec3(sx0, y, sz0), Vec3(sx1, y, sz0), Vec3(sx1, y, sz1), Vec3(sx0, y, sz1), //
      ], size);
      if (plate != null) {
        canvas.drawPath(
            plate, Paint()..color = shadeColor(_scuffColor, Vec3.unitY));
        final rib = Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..strokeWidth = 1.0;
        for (final t in const [0.25, 0.5, 0.75]) {
          final z = sz0 + (sz1 - sz0) * t;
          _drawSegment(canvas, size, Vec3(sx0 + 0.02, y, z),
              Vec3(sx1 - 0.02, y, z), rib);
        }
        canvas.drawPath(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = Colors.black.withValues(alpha: 0.45),
        );
      }
    }
  }

  /// 보이는 쪽 벽: 바닥과 만나는 음영 띠, 휠하우스 뒤의 사이드 트림 포켓
  void _drawWallDetails(Canvas canvas, Size size, Vec3 camPos) {
    final s = space;
    final zw = _zWallMax;
    for (final left in [true, false]) {
      final visible = left
          ? camPos.x > s.xMinAt(s.d / 2, 0)
          : camPos.x < s.xMaxAt(s.d / 2, 0);
      if (!visible) continue;
      double wx(double z, double y) => left
          ? s.xMinAt(math.min(z, zw), y) + 0.0015
          : s.xMaxAt(math.min(z, zw), y) - 0.0015;
      List<Vec3> onWall(List<List<double>> zy) =>
          [for (final p in zy) Vec3(wx(p[0], p[1]), p[1], p[0])];

      // 바닥 쪽 음영
      for (final layer in const [[0.07, 0.10], [0.03, 0.13]]) {
        _fillPoly(
          canvas,
          size,
          onWall([
            [0, 0], [s.d, 0], [s.d, layer[0]], [0, layer[0]], //
          ]),
          Paint()..color = Colors.black.withValues(alpha: layer[1]),
        );
      }

      // 포켓: 휠하우스 뒤 ~ 프레임 앞
      final wh = left ? s.leftWheelhouse : s.rightWheelhouse;
      final z0 = (wh.w > 0 ? wh.zEnd : s.d * 0.5) + 0.05;
      final z1 = (s.aperture == null ? s.d - 0.04 : zw) - 0.05;
      final kneeY = s.interiorCeilingAt(z1) * 0.6;
      final y0 = 0.11, y1 = math.min(0.37, kneeY - 0.04);
      if (z1 - z0 >= 0.12 && y1 - y0 >= 0.10) {
        const c = 0.022;
        final pocket = onWall([
          [z0 + c, y0], [z1 - c, y0], [z1, y0 + c], [z1, y1 - c], //
          [z1 - c, y1], [z0 + c, y1], [z0, y1 - c], [z0, y0 + c],
        ]);
        final path = _projectPath(pocket, size);
        if (path != null) {
          canvas.drawPath(
              path, Paint()..color = Colors.black.withValues(alpha: 0.30));
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..color = Colors.black.withValues(alpha: 0.35),
          );
          // 위쪽 안 그림자, 아래쪽 하이라이트 → 파인 느낌
          _drawSegment(
            canvas,
            size,
            Vec3(wx(z0 + c, y1), y1 - 0.004, z0 + c),
            Vec3(wx(z1 - c, y1), y1 - 0.004, z1 - c),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.45)
              ..strokeWidth = 2.5,
          );
          _drawSegment(
            canvas,
            size,
            Vec3(wx(z0 + c, y0), y0, z0 + c),
            Vec3(wx(z1 - c, y0), y0, z1 - c),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.16)
              ..strokeWidth = 1.2,
          );
        }
      }
    }
  }

  /// 2열 등받이: 분할 비율대로 쿠션 패널(사이 틈은 어두운 바탕), 박음질 선,
  /// 헤드레스트와 기둥. 전부 등받이 프로필 평면 위 또는 그 뒤(실내 쪽)에 있다.
  void _drawSeat(Canvas canvas, Size size, SeatLayout seat, Vec3 camPos) {
    final s = space;
    // 쿠션은 등받이 프로필의 꺾이는 점에서만 나눈다 (벽 꺾임 높이는 쿠션과 무관)
    final prof = frontProfilePolyline(s, withKnee: false);
    const gapX = 0.009, bottom = 0.02, topGap = 0.012;
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.5);
    final seam = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = 1.0;
    final cushionTop = seat.topY - (seat.hasHeadrests ? topGap : 0.03);

    for (var i = 0; i + 1 < prof.length; i++) {
      final a = prof[i], b = prof[i + 1];
      if (b.y - a.y < 1e-9) continue;
      final y0 = math.max(a.y, bottom), y1 = math.min(b.y, cushionTop);
      if (y1 - y0 < 0.02) continue;
      double zAt(double y) => a.z + (b.z - a.z) * (y - a.y) / (b.y - a.y);
      final normal = Vec3(0, -(b.z - a.z), b.y - a.y).normalized;
      if (normal.dot(camPos - Vec3(s.w / 2, y0, zAt(y0))) <= 0) continue;
      final lit = _depthLight(zAt((y0 + y1) / 2));
      fill.color = shadeColor(_scale(_cushionColor, lit), normal);

      for (final sec in seat.sections) {
        double xa(double y) =>
            math.max(sec[0], s.xMinAt(zAt(y), y)) + gapX;
        double xb(double y) =>
            math.min(sec[1], s.xMaxAt(zAt(y), y)) - gapX;
        if (xb(y1) - xa(y1) < 0.05) continue;
        final path = _projectPath([
          Vec3(xa(y0), y0, zAt(y0)),
          Vec3(xb(y0), y0, zAt(y0)),
          Vec3(xb(y1), y1, zAt(y1)),
          Vec3(xa(y1), y1, zAt(y1)),
        ], size);
        if (path == null) continue;
        canvas.drawPath(path, fill);
        canvas.drawPath(path, edge);
        // 가로 박음질
        for (final t in const [0.36, 0.70]) {
          final y = y0 + (y1 - y0) * t;
          _drawSegment(canvas, size, Vec3(xa(y) + 0.02, y, zAt(y)),
              Vec3(xb(y) - 0.02, y, zAt(y)), seam);
        }
      }
    }

    if (!seat.hasHeadrests) return;
    final meshes = headrestMeshes(seat);
    final order = List<int>.generate(meshes.length, (i) => i)
      ..sort((i, j) {
        final ci = Vec3(seat.headrests[i].cx, seat.topY, seat.planeZ);
        final cj = Vec3(seat.headrests[j].cx, seat.topY, seat.planeZ);
        return (cj - camPos).length.compareTo((ci - camPos).length);
      });
    final post = Paint()
      ..color = const Color(0xFF9A9EA4)
      ..strokeWidth = 2.0;
    final zPost = seat.planeZ - seat.recess * 0.4;
    for (final i in order) {
      final hr = seat.headrests[i];
      for (final dx in [-hr.w * 0.22, hr.w * 0.22]) {
        _drawSegment(canvas, size, Vec3(hr.cx + dx, seat.topY, zPost),
            Vec3(hr.cx + dx, hr.y0 + 0.01, zPost), post);
      }
      _drawMesh(canvas, size, meshes[i], _scale(_headrestColor, 0.92), camPos,
          hardEdges: false,
          silhouette: Colors.black.withValues(alpha: 0.55),
          silhouetteWidth: 1.0);
    }
  }

  /// 닫힌 테일게이트 안쪽 면이 양쪽 벽과 만나는 선 (= 이 선 뒤로는 못 놓음).
  /// 프레임 구간 안쪽은 프레임 면이 가리므로 프레임 앞까지만 그린다.
  void _drawTailgateLimitLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _limitLine.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final line in tailgateLimitPolylines(space)) {
      final proj = _projectPoints(line, size);
      if (proj == null) continue;
      _drawDashedPolyline(canvas, proj, paint);
    }
    // 바닥에도: 테일게이트 바닥선에서 천장 한계까지 안쪽으로 얼마나 들어오는지
    final floorLine = tailgateLimitFloorLine(space);
    if (floorLine != null) {
      final floor = _projectPoints(floorLine, size);
      if (floor != null) {
        _drawDashedPolyline(canvas, floor,
            Paint()
              ..color = _limitLine.withValues(alpha: 0.35)
              ..strokeWidth = 1.0
              ..style = PaintingStyle.stroke);
      }
    }
  }

  /// 헤드레스트 구간의 적재 한계면 외곽 (헤드레스트 사이로 짐을 밀어 넣을 수 없다는 표시).
  /// 파인 공간은 그림일 뿐이고 짐은 이 평면까지만 간다.
  void _drawSeatLimitOutline(Canvas canvas, Size size, Vec3 camPos) {
    final face = seatLimitFace(space);
    if (face == null || !face.facesCamera(camPos)) return;
    final p = _projectPoints(face.pts, size);
    if (p == null) return;
    // 아래 변은 등받이 윗선과 겹치므로 양옆과 천장 쪽만
    _drawDashedPolyline(
        canvas,
        [p[0], p[3], p[2], p[1]],
        Paint()
          ..color = _limitLine.withValues(alpha: 0.45)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
        dash: 4,
        gap: 4);
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

  // ── 물체 (고정물 + 박스) ──

  void _paintObjects(Canvas canvas, Size size) {
    final camPos = camera.position;
    final ordered = sceneDrawOrder(
      space,
      boxes.where(_isVisibleInStepView),
      camera,
      fixtures: cache?.fixturesFor(space),
    );
    final placedLabels = <Rect>[];
    for (final obj in ordered) {
      _drawObject(canvas, size, obj, camPos, placedLabels);
    }
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

  /// 카메라가 옆으로 돌아가면 그쪽 기둥·차체 윤곽이 짐칸을 가린다 → 단면도처럼 흐리게.
  double _sideFade(int side, Vec3 camPos) {
    if (side == 0) return 1.0;
    // 카메라가 개구부 가장자리를 넘어 옆으로 나간 거리
    final edge = _apertureInset();
    final beyond =
        side < 0 ? edge - camPos.x : camPos.x - (space.w - edge);
    final t = (beyond / 0.8).clamp(0.0, 1.0);
    return 1.0 - 0.62 * t;
  }

  /// 어두운 짐은 밝은 모서리(하이라이트), 밝은 짐은 어두운 모서리
  Color _edgeColorFor(Color base) => base.computeLuminance() < 0.10
      ? Color.lerp(base, Colors.white, 0.30)!
      : Color.lerp(base, Colors.black, 0.55)!;

  void _drawObject(Canvas canvas, Size size, SceneObject obj, Vec3 camPos,
      List<Rect> placedLabels) {
    final box = obj.box;
    if (box == null) {
      var fade = _sideFade(obj.fadeSide, camPos);
      if (obj.alpha < 1) fade = fade * fade * fade; // 차체 윤곽은 더 빨리 사라진다
      _drawMesh(canvas, size, obj.mesh, obj.color, camPos,
          opacity: obj.alpha * fade,
          colorFaceAlpha: fade,
          hardEdges: obj.outline,
          edgeColor: Colors.black.withValues(alpha: 0.38 * fade),
          silhouette: obj.outline
              ? Colors.black.withValues(alpha: 0.45 * fade)
              : null,
          silhouetteWidth: 1.0);
      return;
    }

    final isColliding = collidingBoxIds.contains(box.id);
    final isSelected = box.id == selectedBoxId;
    final opacity = _opacityFor(box);

    var base = obj.color;
    if (isColliding) base = Color.lerp(base, _danger, 0.45)!;
    final edgeColor = _edgeColorFor(base).withValues(alpha: 0.9 * opacity);

    if (obj.isFirstPart) {
      _drawContactShadow(canvas, size, obj.fullAabb, box.shape, opacity);
    }
    _drawMesh(canvas, size, obj.mesh, base, camPos,
        opacity: opacity,
        edgeColor: edgeColor,
        silhouette: isSelected ? _accent.withValues(alpha: opacity) : edgeColor,
        silhouetteWidth: isSelected ? 2.5 : 1.1);

    // 순환을 풀려고 자른 물체는 마지막 조각을 그린 뒤에 와이어·라벨을 얹는다
    if (!obj.isLastPart) return;

    // 실제 판정 경계(AABB). 충돌 중이면 빨간 와이어로 물리 경계를 보여준다.
    final visible = [
      for (final f in aabbFaces(obj.fullAabb))
        if (f.facesCamera(camPos)) f
    ];
    List<Offset>? largest;
    var largestArea = 0.0;
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = _danger.withValues(alpha: opacity);
    for (final f in visible) {
      final pts = _projectPoints(f.pts, size);
      if (pts == null) continue;
      if (isColliding) canvas.drawPath(_pathFrom(pts), wire);
      final area = _polygonArea(pts);
      if (area > largestArea) {
        largestArea = area;
        largest = pts;
      }
    }

    if (showLabels && largest != null && largestArea > 700) {
      _drawLabel(canvas, box, largest, opacity, placedLabels);
    }
  }

  /// 메시 하나를 그린다: 법선 컬링 → 면 채우기 → 모서리/장식선 → 실루엣.
  /// 메시가 볼록이라 보이는 면끼리는 화면에서 겹치지 않는다 (면 정렬 불필요).
  void _drawMesh(
    Canvas canvas,
    Size size,
    Mesh mesh,
    Color base,
    Vec3 camPos, {
    double opacity = 1.0,
    double colorFaceAlpha = 1.0,
    bool hardEdges = true,
    Color? edgeColor,
    Color? silhouette,
    double silhouetteWidth = 1.0,
  }) {
    final verts = mesh.verts;
    final proj = List<Offset?>.filled(verts.length, null);
    for (var i = 0; i < verts.length; i++) {
      proj[i] = camera.project(verts[i], size)?.screen;
    }

    final fill = Paint();
    final stroke = Paint()..style = PaintingStyle.stroke;
    final front = List<bool>.filled(mesh.faces.length, false);
    final drawn = <int>[];
    final paths = <Path>[];
    final shades = <Color>[];

    // 1) 면 채우기 (모서리선이 이웃 면에 덮이지 않게 선은 나중에 한꺼번에)
    for (var fi = 0; fi < mesh.faces.length; fi++) {
      final f = mesh.faces[fi];
      if (f.normal.dot(camPos - verts[f.idx[0]]) <= 0) continue;
      front[fi] = true;
      // 절단면은 앞 조각이 덮는다. 반투명이면 비쳐 보이므로 그리지 않는다.
      if (f.isCap && opacity < 0.99) continue;

      final path = Path();
      var ok = true;
      for (var k = 0; k < f.idx.length; k++) {
        final p = proj[f.idx[k]];
        if (p == null) {
          ok = false;
          break;
        }
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (!ok) continue;
      path.close();

      var c = f.color ?? base;
      if (f.tint > 0) {
        c = Color.lerp(c, Colors.white, f.tint)!;
      } else if (f.tint < 0) {
        c = Color.lerp(c, Colors.black, -f.tint)!;
      }
      final alpha = f.color != null ? f.color!.a * colorFaceAlpha : opacity;
      final shaded = shadeColor(c, f.normal).withValues(alpha: alpha);
      canvas.drawPath(path, fill..color = shaded);
      if (alpha >= 0.99) {
        // 이어지는 면 사이 안티앨리어싱 틈 메우기
        canvas.drawPath(
            path,
            stroke
              ..strokeWidth = 1.0
              ..color = shaded);
      }
      drawn.add(fi);
      paths.add(path);
      shades.add(shaded);
    }

    // 2) 모서리선·장식선
    final lineAlpha = math.sqrt(opacity.clamp(0.0, 1.0));
    for (var n = 0; n < drawn.length; n++) {
      final f = mesh.faces[drawn[n]];
      if (hardEdges && !f.smooth && edgeColor != null) {
        stroke
          ..strokeWidth = 1.0
          ..color = edgeColor;
        if (f.cutEdges.isEmpty) {
          canvas.drawPath(paths[n], stroke);
        } else {
          // 절단선은 실제 모서리가 아니다
          final edges = Path();
          for (var k = 0; k < f.idx.length; k++) {
            if (f.cutEdges.contains(k)) continue;
            final a = proj[f.idx[k]]!, b = proj[f.idx[(k + 1) % f.idx.length]]!;
            edges
              ..moveTo(a.dx, a.dy)
              ..lineTo(b.dx, b.dy);
          }
          canvas.drawPath(edges, stroke);
        }
      }
      for (final line in f.lines) {
        final lp = _projectPoints(line.pts, size);
        if (lp == null) continue;
        final lc = line.tone < 0
            ? Color.lerp(shades[n], Colors.black, -line.tone)!
            : Color.lerp(shades[n], Colors.white, line.tone)!;
        stroke
          ..strokeWidth = line.width
          ..color = lc.withValues(alpha: lineAlpha);
        final lpath = Path()..moveTo(lp[0].dx, lp[0].dy);
        for (var k = 1; k < lp.length; k++) {
          lpath.lineTo(lp[k].dx, lp[k].dy);
        }
        if (line.closed) lpath.close();
        canvas.drawPath(lpath, stroke);
      }
    }

    if (silhouette == null || !mesh.closed) return;
    // 실루엣: 보이는 면과 안 보이는 면이 공유하는 모서리
    final nv = verts.length;
    final count = <int, int>{};
    for (var fi = 0; fi < mesh.faces.length; fi++) {
      if (!front[fi]) continue;
      final idx = mesh.faces[fi].idx;
      for (var k = 0; k < idx.length; k++) {
        final a = idx[k], b = idx[(k + 1) % idx.length];
        final key = a < b ? a * nv + b : b * nv + a;
        count[key] = (count[key] ?? 0) + 1;
      }
    }
    final sil = Path();
    var any = false;
    final cutKeys = mesh.cutEdgeKeys;
    count.forEach((key, n) {
      if (n != 1 || cutKeys.contains(key)) return;
      final pa = proj[key ~/ nv], pb = proj[key % nv];
      if (pa == null || pb == null) return;
      sil
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy);
      any = true;
    });
    if (any) {
      canvas.drawPath(
          sil,
          stroke
            ..strokeWidth = silhouetteWidth
            ..strokeCap = StrokeCap.round
            ..color = silhouette);
    }
  }

  /// 접촉 그림자: 모양의 바닥 윤곽 (세운 통은 타원, 천 가방은 모서리를 딴 사각형)
  void _drawContactShadow(
      Canvas canvas, Size size, Aabb a, GearShape shape, double opacity) {
    final pts = _projectPoints([
      for (final p in gearFootprint(shape, a)) Vec3(p.x, p.y + 0.002, p.z),
    ], size);
    if (pts == null) return;
    canvas.drawPath(
      _pathFrom(pts),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  /// 가장 크게 보이는 AABB 면 가운데에 [순서 배지][라벨]. 라벨이 안 들어가면 배지만.
  /// 먼저 놓인 이웃의 배지·라벨([placed])과 겹치면 면 안에서 위아래로 비켜 놓고,
  /// 그래도 겹치면 배지만 남긴다.
  void _drawLabel(Canvas canvas, TrimBox box, List<Offset> facePts,
      double opacity, List<Rect> placed) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    var cx = 0.0, cy = 0.0;
    for (final p in facePts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
      cx += p.dx;
      cy += p.dy;
    }
    cx /= facePts.length;
    cy /= facePts.length;
    final faceW = maxX - minX;

    final order = box.loadOrder;
    const badgeR = 10.0;
    final badgeW = order != null ? badgeR * 2 + 4 : 0.0;

    TextPainter? tp;
    final room = math.min(faceW - 18 - badgeW, 160.0);
    if (room >= 30) {
      tp = TextPainter(
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
      )..layout(maxWidth: room);
    }

    final found = placeLabelGroup(
      face: Rect.fromLTRB(minX, minY, maxX, maxY),
      centre: Offset(cx, cy),
      badgeWidth: badgeW,
      pillWidth: tp == null ? null : tp.width + 12,
      placed: placed,
    );
    if (found == null) return;
    final spot = found.rect;
    final withPill = found.withPill;
    placed.add(spot);

    var left = spot.left;
    final midY = spot.center.dy;
    if (order != null) {
      final c = Offset(left + badgeR, midY);
      canvas.drawCircle(
          c, badgeR + 1, Paint()..color = Colors.black.withValues(alpha: 0.45 * opacity));
      canvas.drawCircle(
          c, badgeR, Paint()..color = _accent.withValues(alpha: opacity));
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
      left += badgeW;
    }

    if (withPill && tp != null) {
      final pill =
          Rect.fromLTWH(left, midY - tp.height / 2 - 3, tp.width + 12, tp.height + 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(6)),
        Paint()..color = Colors.black.withValues(alpha: 0.6 * opacity),
      );
      tp.paint(canvas, Offset(left + 6, midY - tp.height / 2));
    }
  }

  // ── 캡션 ──

  /// 캔버스 왼쪽 아래 상태 표시의 문구와 종류.
  ///
  /// 우선순위: 테일게이트에 걸린 짐(빨강) → 트렁크 밖에 세워 둔 못 넣은 짐(주황) → 초록.
  /// 못 넣은 짐이 있는데 초록 "닫힘 OK" 만 보이면 "다 실렸다" 로 읽힌다. 밖에 세워 둔
  /// 짐의 기준은 통계([LoadStats])와 같다.
  static (String, CaptionStatusKind) captionStatus(
    TrunkSpace space,
    List<TrimBox> boxes,
    Set<String> tailgateBlockedIds,
  ) {
    final blocked = tailgateBlockedIds.length;
    if (blocked > 0) {
      return ('테일게이트 안 닫힘 · $blocked개 걸림', CaptionStatusKind.blocked);
    }
    final parked = boxes.where((b) => LoadStats.isParked(b, space)).length;
    if (parked > 0) {
      return parked == boxes.length
          ? ('미적재 $parked개 · 실은 짐 없음', CaptionStatusKind.unloaded)
          : ('미적재 $parked개 · 실은 짐은 테일게이트 닫힘 OK',
              CaptionStatusKind.unloaded);
    }
    return ('테일게이트 닫힘 OK', CaptionStatusKind.ok);
  }

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
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: math.max(120.0, size.width - 24)); // 폰 폭에서는 두 줄로
    var y = size.height - tp.height - 10;
    tp.paint(canvas, Offset(12, y));

    if (space.hasTailgateModel && boxes.isNotEmpty) {
      final (status, kind) = captionStatus(space, boxes, tailgateBlockedIds);
      final color = switch (kind) {
        CaptionStatusKind.ok => const Color(0xFF6BD06B),
        CaptionStatusKind.unloaded => const Color(0xFFFFC46B),
        CaptionStatusKind.blocked => _danger,
      };
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
