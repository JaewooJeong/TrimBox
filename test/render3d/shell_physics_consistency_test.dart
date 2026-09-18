// 그려진 것 = 허용되는 것. 페인터가 쓰는 순수 함수(scene.dart·geometry.dart·fixtures.dart)의
// 결과를 TrunkSpace 의 경계 함수, CollisionDetector 의 판정과 맞대 본다.
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/fixtures.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/scene.dart';
import 'package:trimbox/render3d/vec3.dart';
import 'package:trimbox/utils/collision.dart';

Map<String, TrunkSpace> _spaces() => {
      'sorento': TrunkSpace.sorento(),
      'sorento slide 0.13': TrunkSpace.sorento(seatSlide: 0.13),
      'sorento slide 0.27': TrunkSpace.sorento(seatSlide: 0.27),
      'sorento7': TrunkSpace.sorento7(),
      'tucson': TrunkSpace.tucson(),
      'santafe': TrunkSpace.santafe(),
      'carnival': TrunkSpace.carnival(),
      'ioniq5': TrunkSpace.ioniq5(),
      'avante': TrunkSpace.avante(),
    };

const _cm = 0.01;

double _zWallMax(TrunkSpace s) =>
    s.aperture == null ? s.d : s.d - s.aperture!.frameDepth - 1e-6;

/// 꼭짓점 + 변의 중점 (직선 근사가 곡선 경계에서 벗어나는지도 본다)
Iterable<Vec3> _verticesAndMidpoints(List<Vec3> pts) sync* {
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    yield a;
    yield (a + b) * 0.5;
  }
}

// ── 그려진 부피: 경계 면(법선이 빈 공간을 향함)에 여섯 방향 반직선을 쏴서 판단 ──

class _Boundary {
  final List<Vec3> pts;
  final Vec3 normal;
  const _Boundary(this.pts, this.normal);
}

class _DrawnVolume {
  final TrunkSpace s;
  final List<List<_Boundary>> byDir; // 방향별(±x, ±y, ±z) 막는 면
  final List<FixtureObject> frame;
  final List<({Aabb box, List<_Boundary> planes})> arches;

  _DrawnVolume._(this.s, this.byDir, this.frame, this.arches);

  static const dirs = [
    Vec3(-1, 0, 0), Vec3(1, 0, 0), Vec3(0, -1, 0), //
    Vec3(0, 1, 0), Vec3(0, 0, -1), Vec3(0, 0, 1),
  ];

  factory _DrawnVolume(TrunkSpace s) {
    final faces = <_Boundary>[];
    // 껍데기 (헤드레스트 뒤 장식 면 제외), 법선은 안쪽
    for (final sf in drawnShell(s)) {
      if (sf.behindSeatPlane) continue;
      faces.add(_Boundary(sf.face.pts, sf.face.normal));
    }
    // 헤드레스트 구간의 적재 한계면 (점선)
    final limit = seatLimitFace(s);
    if (limit != null) faces.add(_Boundary(limit.pts, limit.normal));
    // 닫힌 테일게이트 면 (점선·빨간 면). 모델이 없는 차는 개구부 외곽선 평면.
    if (s.hasTailgateModel) {
      for (final f in tailgateFaces(s)) {
        faces.add(_Boundary(f.pts, f.normal));
      }
    } else {
      faces.add(_Boundary(openingOutline(s), const Vec3(0, 0, -1)));
    }
    // 프레임 고정물의 면 (법선은 고체 바깥 = 빈 공간 쪽)
    final frame = frameFixtures(s);
    for (final f in frame) {
      for (final mf in f.mesh.faces) {
        faces.add(_Boundary(f.mesh.facePoints(mf), mf.normal));
      }
    }
    final byDir = [
      for (final d in dirs)
        [
          for (final f in faces)
            if (f.normal.dot(d) < -1e-6) f
        ],
    ];
    final arches = <({Aabb box, List<_Boundary> planes})>[];
    for (final left in [true, false]) {
      final mesh = wheelhouseMesh(s, left: left);
      if (mesh == null) continue;
      arches.add((
        box: left ? Aabb.leftWheelhouse(s) : Aabb.rightWheelhouse(s),
        planes: [
          for (final mf in mesh.faces)
            _Boundary(mesh.facePoints(mf), mf.normal)
        ],
      ));
    }
    return _DrawnVolume._(s, byDir, frame, arches);
  }

  bool contains(Vec3 p) {
    for (var i = 0; i < 6; i++) {
      var hit = false;
      for (final f in byDir[i]) {
        if (_rayHitsPolygon(p, dirs[i], f.pts)) {
          hit = true;
          break;
        }
      }
      if (!hit) return false;
    }
    if (_insideFrameSolid(p)) return false;
    for (final a in arches) {
      if (a.planes.every((pl) => pl.normal.dot(p - pl.pts[0]) < 0)) return false;
    }
    return true;
  }

  /// 프레임 고체 = z = d 면의 다각형을 프레임 두께만큼 민 것
  bool _insideFrameSolid(Vec3 p) {
    for (final f in frame) {
      if (p.z < f.aabb.z1 || p.z > f.aabb.z2) continue;
      for (final mf in f.mesh.faces) {
        if (mf.normal.z < 0.5) continue;
        if (_pointInPolygonXY(p, f.mesh.facePoints(mf))) return true;
      }
    }
    return false;
  }
}

bool _pointInPolygonXY(Vec3 p, List<Vec3> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// 부채꼴 삼각 분할 + Möller–Trumbore (양면, 가장자리 포함)
bool _rayHitsPolygon(Vec3 o, Vec3 d, List<Vec3> poly) {
  for (var i = 1; i + 1 < poly.length; i++) {
    final v0 = poly[0], v1 = poly[i], v2 = poly[i + 1];
    final e1 = v1 - v0, e2 = v2 - v0;
    final h = d.cross(e2);
    final a = e1.dot(h);
    if (a.abs() < 1e-14) continue;
    final f = 1 / a;
    final sv = o - v0;
    final u = f * sv.dot(h);
    if (u < -1e-7 || u > 1 + 1e-7) continue;
    final q = sv.cross(e1);
    final v = f * d.dot(q);
    if (v < -1e-7 || u + v > 1 + 1e-7) continue;
    final t = f * e2.dot(q);
    if (t >= -1e-9) return true;
  }
  return false;
}

TrimBox _probe(Vec3 c, [double size = 0.02]) => TrimBox(
      id: 'probe',
      label: 'probe',
      w: size,
      d: size,
      h: size,
      x: c.x - size / 2,
      y: c.y - size / 2,
      z: c.z - size / 2,
      color: const Color(0xFFFFFFFF),
    );

void main() {
  group('(a) 그려진 경계의 꼭짓점이 물리 경계 위에 있다 (1cm 이내)', () {
    _spaces().forEach((name, s) {
      test('$name: 옆벽·천장·등받이', () {
        final zMax = _zWallMax(s);
        var walls = 0, ceilings = 0, seats = 0;
        for (final sf in drawnShell(s)) {
          if (sf.behindSeatPlane) continue;
          for (final p in _verticesAndMidpoints(sf.face.pts)) {
            switch (sf.part) {
              case ShellPart.leftWall || ShellPart.rightWall:
                // 프레임 구간의 좁아짐은 벽이 아니라 기둥이 그린다 (아래 테스트)
                final z = math.min(p.z, zMax);
                final want = sf.part == ShellPart.leftWall
                    ? s.xMinAt(z, p.y)
                    : s.xMaxAt(z, p.y);
                expect((p.x - want).abs(), lessThanOrEqualTo(_cm),
                    reason: '$name ${sf.part.name} $p → x=$want');
                // 벽은 등받이 프로필과 테일게이트 프로필 사이에만 있다
                expect(p.z, greaterThanOrEqualTo(s.frontInsetAt(p.y) - _cm));
                expect(p.z, lessThanOrEqualTo(s.rearDepthAt(p.y) + _cm));
                expect(p.y, lessThanOrEqualTo(s.interiorCeilingAt(p.z) + _cm));
                walls++;
              case ShellPart.ceiling:
                expect((p.y - s.interiorCeilingAt(p.z)).abs(),
                    lessThanOrEqualTo(_cm),
                    reason: '$name 천장 $p');
                expect(p.z, greaterThanOrEqualTo(s.frontInsetAt(s.h) - _cm));
                expect(p.z, lessThanOrEqualTo(s.rearDepthAt(s.h) + _cm));
                expect(p.x, greaterThanOrEqualTo(s.xMinAt(p.z, p.y) - _cm));
                expect(p.x, lessThanOrEqualTo(s.xMaxAt(p.z, p.y) + _cm));
                ceilings++;
              case ShellPart.seatBack:
                expect((p.z - s.frontInsetAt(p.y)).abs(), lessThanOrEqualTo(_cm),
                    reason: '$name 등받이 $p');
                seats++;
              case ShellPart.floor:
                expect(p.y.abs(), lessThan(1e-9));
                expect(p.z, inInclusiveRange(-1e-9, s.d + 1e-9));
              default:
                break;
            }
          }
        }
        expect(walls, greaterThan(40));
        expect(ceilings, greaterThan(40));
        expect(seats, greaterThan(0));
      });

      test('$name: 헤드레스트 구간 한계면·헤드레스트 앞면이 프로필 평면 위', () {
        final limit = seatLimitFace(s);
        final seat = seatLayout(s);
        if (seat == null || !seat.hasHeadrests) {
          expect(limit, isNull);
          return;
        }
        for (final p in limit!.pts) {
          expect((p.z - s.frontInsetAt(p.y)).abs(), lessThanOrEqualTo(1e-9));
        }
        final ys = limit.pts.map((p) => p.y);
        expect(ys.reduce(math.min), closeTo(seat.topY, 1e-9));
        expect(ys.reduce(math.max),
            closeTo(s.interiorCeilingAt(seat.planeZ), 1e-9));
        for (final mesh in headrestMeshes(seat)) {
          final front = mesh.verts.map((v) => v.z).reduce(math.max);
          expect(front, closeTo(s.frontInsetAt(seat.topY + 0.05), 1e-9));
        }
      });

      test('$name: 테일게이트 한계 점선', () {
        final lines = tailgateLimitPolylines(s);
        if (!s.hasTailgateModel) {
          expect(lines, isEmpty);
          // 모델이 없는 차는 개구부 외곽선(z = d)이 뒤쪽 한계
          for (final p in openingOutline(s)) {
            expect(p.z, closeTo(s.d, 1e-9));
          }
          return;
        }
        expect(lines.length, 2);
        for (var side = 0; side < 2; side++) {
          final line = lines[side];
          expect(line.first.y, closeTo(0, 1e-9));
          expect(line.last.y, closeTo(s.h, 1e-9));
          for (var i = 0; i + 1 < line.length; i++) {
            for (final p in [line[i], (line[i] + line[i + 1]) * 0.5]) {
              expect((p.z - s.rearDepthAt(p.y)).abs(), lessThanOrEqualTo(_cm),
                  reason: '$name 한계선 $p');
            }
            // x 는 꼭짓점에서만 (프레임 구간 경계를 가로지르는 변은 직선 근사)
            final p = line[i];
            final want = side == 0 ? s.xMinAt(p.z, p.y) : s.xMaxAt(p.z, p.y);
            expect((p.x - want).abs(), lessThanOrEqualTo(_cm));
          }
        }
        // 닫힌 테일게이트 면(빨간 경고 면)도 같은 프로필
        for (final f in tailgateFaces(s)) {
          for (final p in f.pts) {
            expect((p.z - s.rearDepthAt(p.y)).abs(), lessThanOrEqualTo(_cm));
          }
        }
        final floor = tailgateLimitFloorLine(s);
        if (floor != null) {
          for (final p in floor) {
            expect(p.z, closeTo(s.rearDepthAt(s.h), 1e-9));
          }
        }
      });

      test('$name: 프레임 기둥 안쪽 면 = 개구부 가장자리', () {
        final ap = s.aperture;
        if (ap == null) return;
        final zf = s.d - ap.frameDepth;
        final top = math.min(ap.height, s.interiorCeilingAt(zf));
        var checked = 0;
        for (final f in frameFixtures(s)) {
          for (final mf in f.mesh.faces) {
            if (mf.normal.x.abs() < 0.9) continue; // 개구부 안쪽 면만
            for (final p in f.mesh.facePoints(mf)) {
              if (p.y > top - apertureCornerRadius(s) - 1e-9) continue;
              final want = mf.normal.x > 0
                  ? s.xMinAt(s.d - ap.frameDepth / 2, p.y)
                  : s.xMaxAt(s.d - ap.frameDepth / 2, p.y);
              expect((p.x - want).abs(), lessThanOrEqualTo(_cm),
                  reason: '$name 기둥 $p');
              checked++;
            }
          }
        }
        expect(checked, greaterThan(0));
      });
    });
  });

  group('(b) 탐침 상자(2cm): 판정기가 허용하는 곳 ⊂ 그려진 부피, 그려진 부피 밖 → 거부', () {
    _spaces().forEach((name, s) {
      test(name, () {
        final volume = _DrawnVolume(s);
        final detector = CollisionDetector(s);
        const step = 0.05, margin = 0.08;
        // 격자가 면·모서리와 정확히 겹치지 않게 살짝 어긋난 시작점
        const off = 0.0137;
        var accepted = 0, rejectedOutside = 0, total = 0;
        final bad = <String>[];

        void check(Vec3 c) {
          total++;
          final ok = detector.violations(_probe(c), const []).isEmpty;
          if (ok) {
            accepted++;
            if (!volume.contains(c)) {
              bad.add('허용인데 그려진 부피 밖: $c');
            }
            return;
          }
          // 2cm 넘게 밖: 주변 ±2cm 어디도 그려진 부피에 닿지 않는다
          var touches = false;
          outer:
          for (final dx in const [0.0, -0.02, 0.02]) {
            for (final dy in const [0.0, -0.02, 0.02]) {
              for (final dz in const [0.0, -0.02, 0.02]) {
                if (volume.contains(Vec3(c.x + dx, c.y + dy, c.z + dz))) {
                  touches = true;
                  break outer;
                }
              }
            }
          }
          if (!touches) rejectedOutside++;
        }

        void checkOutsideRejected(Vec3 c) {
          // (역방향) 그려진 부피에서 2cm 넘게 벗어난 탐침은 판정기가 거부해야 한다
          for (final dx in const [0.0, -0.02, 0.02]) {
            for (final dy in const [0.0, -0.02, 0.02]) {
              for (final dz in const [0.0, -0.02, 0.02]) {
                if (volume.contains(Vec3(c.x + dx, c.y + dy, c.z + dz))) return;
              }
            }
          }
          if (detector.violations(_probe(c), const []).isEmpty) {
            bad.add('그려진 부피 밖인데 허용: $c');
          }
        }

        for (var x = -margin + off; x <= s.w + margin; x += step) {
          for (var y = -margin + off; y <= s.h + margin; y += step) {
            for (var z = -margin + off; z <= s.d + margin; z += step) {
              final c = Vec3(x, y, z);
              check(c);
              checkOutsideRejected(c);
            }
          }
        }
        // 얇은 프레임 구간과 등받이·테일게이트 근처는 촘촘하게
        final zs = <double>[
          for (var z = s.d - 0.30; z <= s.d + 0.03; z += 0.011) z,
          for (var z = -0.03; z <= 0.30; z += 0.013) z,
        ];
        for (final z in zs) {
          for (var x = -0.04 + off; x <= s.w + 0.04; x += 0.037) {
            for (var y = 0.011; y <= s.h + 0.03; y += 0.043) {
              final c = Vec3(x, y, z);
              check(c);
              checkOutsideRejected(c);
            }
          }
        }

        expect(bad, isEmpty,
            reason: '$name: ${bad.length}건\n${bad.take(12).join('\n')}');
        // 검사가 실제로 양쪽을 다 밟았는지
        expect(accepted, greaterThan(total ~/ 20), reason: '$name 허용 $accepted');
        expect(rejectedOutside, greaterThan(total ~/ 20));
      });
    });
  });

  group('(c) 휠하우스 아치의 경계 상자 = 물리 휠하우스 AABB', () {
    final cases = <String, TrunkSpace>{
      for (final slide in [0.0, 0.05, 0.13, 0.2, 0.27])
        'sorento slide $slide': TrunkSpace.sorento(seatSlide: slide),
      'sorento7 slide 0.27': TrunkSpace.sorento7(seatSlide: 0.27),
      ..._spaces(),
    };
    cases.forEach((name, s) {
      test(name, () {
        for (final left in [true, false]) {
          final a = left ? Aabb.leftWheelhouse(s) : Aabb.rightWheelhouse(s);
          final mesh = wheelhouseMesh(s, left: left);
          if (a.isEmpty) {
            expect(mesh, isNull);
            continue;
          }
          double lo(double Function(Vec3) f) => mesh!.verts.map(f).reduce(math.min);
          double hi(double Function(Vec3) f) => mesh!.verts.map(f).reduce(math.max);
          expect(lo((v) => v.x), closeTo(a.x1, 1e-9));
          expect(hi((v) => v.x), closeTo(a.x2, 1e-9));
          expect(lo((v) => v.y), closeTo(a.y1, 1e-9));
          expect(hi((v) => v.y), closeTo(a.y2, 1e-9));
          expect(lo((v) => v.z), closeTo(a.z1, 1e-9));
          expect(hi((v) => v.z), closeTo(a.z2, 1e-9));
          // 물리 값과 직접 비교 (Aabb 팩토리를 거치지 않고)
          final wh = left ? s.leftWheelhouse : s.rightWheelhouse;
          expect(lo((v) => v.z), closeTo(wh.zStart, 1e-9));
          expect(hi((v) => v.z), closeTo(wh.zEnd, 1e-9));
          expect(hi((v) => v.y), closeTo(wh.h, 1e-9));
          expect(hi((v) => v.x) - lo((v) => v.x), closeTo(wh.w, 1e-9));
        }
      });
    });
  });

  group('(d) 2열 슬라이드 빈틈 띠는 정확히 z ∈ [0, floorStartZ]', () {
    test('슬라이드가 없으면 그리지 않는다', () {
      expect(seatGapStrip(TrunkSpace.sorento()), isNull);
      expect(seatGapStrip(TrunkSpace.tucson()), isNull);
    });

    for (final slide in [0.05, 0.13, 0.27]) {
      test('slide $slide', () {
        for (final s in [
          TrunkSpace.sorento(seatSlide: slide),
          TrunkSpace.sorento7(seatSlide: slide),
        ]) {
          final strip = seatGapStrip(s)!;
          final zs = strip.map((p) => p.z);
          expect(zs.reduce(math.min), closeTo(0, 1e-12));
          expect(zs.reduce(math.max), closeTo(s.floorStartZ, 1e-12));
          final xs = strip.map((p) => p.x);
          expect(xs.reduce(math.min), lessThanOrEqualTo(s.xMinAt(0, 0)));
          expect(xs.reduce(math.max), greaterThanOrEqualTo(s.xMaxAt(0, 0)));
          for (final p in strip) {
            expect(p.y, inInclusiveRange(0, 0.005)); // 바닥 위에 붙은 띠
          }
        }
      });
    }
  });
}
