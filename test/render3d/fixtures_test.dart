import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/fixtures.dart';
import 'package:trimbox/render3d/geometry.dart';

import 'mesh_checks.dart';

Map<String, TrunkSpace> _spaces() => {
      'sorento': TrunkSpace.sorento(),
      'sorento slide 0.27': TrunkSpace.sorento(seatSlide: 0.27),
      'sorento7': TrunkSpace.sorento7(),
      'tucson': TrunkSpace.tucson(),
      'santafe': TrunkSpace.santafe(),
      'carnival': TrunkSpace.carnival(),
      'ioniq5': TrunkSpace.ioniq5(),
      'avante': TrunkSpace.avante(),
      'custom': TrunkSpace.custom(w: 1.2, d: 1.0, h: 0.8),
    };

void main() {
  group('휠하우스 아치', () {
    _spaces().forEach((name, s) {
      test('$name: 모든 꼭짓점이 물리 휠하우스 AABB 안', () {
        for (final left in [true, false]) {
          final a = left ? Aabb.leftWheelhouse(s) : Aabb.rightWheelhouse(s);
          final mesh = wheelhouseMesh(s, left: left);
          if (a.isEmpty) {
            expect(mesh, isNull);
            continue;
          }
          final why = '$name ${left ? 'L' : 'R'}';
          expect(mesh, isNotNull);
          expectNoNaN(mesh!, why);
          expectInsideAabb(mesh, a, 1e-9, why);
          expectNormalsOutward(mesh, a.center, why);
          expectPlanarFaces(mesh, 1e-9, why);
          expectConvex(mesh, 1e-9, why);
          expectManifold(mesh, why);
          // 아치는 AABB 를 꽉 채운다: 바닥·윗면·앞뒤·짐칸 쪽 끝에 닿는다
          expect(mesh.verts.map((v) => v.y).reduce(math.max), closeTo(a.y2, 1e-9));
          expect(mesh.verts.map((v) => v.z).reduce(math.min), closeTo(a.z1, 1e-9));
          expect(mesh.verts.map((v) => v.z).reduce(math.max), closeTo(a.z2, 1e-9));
          expect(mesh.verts.map((v) => v.x).reduce(math.min), closeTo(a.x1, 1e-9));
          expect(mesh.verts.map((v) => v.x).reduce(math.max), closeTo(a.x2, 1e-9));
        }
      });
    });

    test('2열 슬라이드: 아치가 등받이에서 슬라이드만큼 떨어져 시작한다', () {
      final s = TrunkSpace.sorento(seatSlide: 0.27);
      final mesh = wheelhouseMesh(s, left: true)!;
      expect(mesh.verts.map((v) => v.z).reduce(math.min), closeTo(0.27, 1e-9));
    });

    test('어깨가 둥글다: 윗면 모서리 점은 AABB 모서리보다 안쪽', () {
      final s = TrunkSpace.sorento();
      final a = Aabb.leftWheelhouse(s);
      final mesh = wheelhouseMesh(s, left: true)!;
      // AABB 위쪽 앞 모서리(z1, y2) 근처에는 꼭짓점이 없어야 한다
      for (final v in mesh.verts) {
        final nearCorner = (v.z - a.z1).abs() < 0.02 && (v.y - a.y2).abs() < 0.02;
        expect(nearCorner, isFalse);
      }
    });
  });

  group('개구부 프레임', () {
    for (final entry in {
      'sorento': TrunkSpace.sorento(),
      'sorento slide': TrunkSpace.sorento(seatSlide: 0.27),
      'sorento7': TrunkSpace.sorento7(),
    }.entries) {
      test('${entry.key}: 프레임 구간(z ≥ d − frameDepth) 안에만 있다', () {
        final s = entry.value;
        final ap = s.aperture!;
        final zf = s.d - ap.frameDepth;
        final fixtures = frameFixtures(s);
        expect(fixtures.length, 7); // 기둥 2 + 헤더 + 윗면 조각 2 + 둥근 모서리 2
        for (final f in fixtures) {
          expectNoNaN(f.mesh, entry.key);
          for (final p in f.mesh.allPoints) {
            expect(p.z, inInclusiveRange(zf - 1e-9, s.d + 1e-9));
            expect(p.x, inInclusiveRange(-1e-9, s.w + 1e-9));
            expect(p.y, inInclusiveRange(-1e-9, s.interiorCeilingAt(zf) + 1e-9));
            expect(f.aabb.z1, greaterThanOrEqualTo(zf - 1e-9));
          }
        }
      });

      test('${entry.key}: 개구부 안으로 들어오는 것은 위쪽 모서리 R 뿐', () {
        final s = entry.value;
        final ap = s.aperture!;
        final zf = s.d - ap.frameDepth;
        final top = math.min(ap.height, s.interiorCeilingAt(zf));
        final r = apertureCornerRadius(s);
        expect(r, greaterThan(0.04));
        expect(r, lessThanOrEqualTo(0.08));
        double al(double y) => (s.w - ap.widthAt(y)) / 2;
        for (final f in frameFixtures(s)) {
          for (final p in f.mesh.allPoints) {
            final insideOpening = p.y < top - 1e-9 &&
                p.x > al(p.y) + 1e-9 &&
                p.x < s.w - al(p.y) - 1e-9;
            if (!insideOpening) continue;
            // 모서리 사각형 [al(top), al(top)+r] × [top−r, top] 안이어야 한다
            final dx = math.min(p.x - al(top), s.w - al(top) - p.x);
            expect(dx, lessThanOrEqualTo(r + 1e-9));
            expect(p.y, greaterThanOrEqualTo(top - r - 1e-9));
          }
        }
        // 테일게이트가 닫히는 짐은 프레임 구간에서 그 높이까지 올라올 수 없다
        expect(s.rearCeilingAt(zf), lessThan(top - r));
      });
    }

    test('개구부 모델이 없는 차는 프레임 고정물이 없다', () {
      expect(frameFixtures(TrunkSpace.tucson()), isEmpty);
      expect(frameFixtures(TrunkSpace.custom(w: 1, d: 1, h: 0.8)), isEmpty);
    });
  });

  group('차체 윤곽·테일램프', () {
    _spaces().forEach((name, s) {
      test('$name: 전부 차 밖 (z > d, 트렁크 폭 바깥)', () {
        for (final f in bodyFixtures(s)) {
          expectNoNaN(f.mesh, name);
          expect(f.alpha, lessThan(0.5));
          for (final p in f.mesh.allPoints) {
            expect(p.z, greaterThan(s.d));
            expect(p.x <= 1e-9 || p.x >= s.w - 1e-9, isTrue);
          }
        }
      });
    });
  });

  group('등받이·헤드레스트', () {
    test('쏘렌토: 6:4 쿠션 2개, 헤드레스트 3개가 수직 구간(y ≥ 0.60)에', () {
      final s = TrunkSpace.sorento();
      final seat = seatLayout(s)!;
      expect(seat.sections.length, 2);
      // 수치는 실측 보정으로 바뀔 수 있으니 모델에서 읽는다
      final pts = s.frontProfile!.points;
      expect(seat.topY, closeTo(pts[pts.length - 2].y, 1e-9));
      expect(seat.topY, greaterThanOrEqualTo(0.5));
      expect(seat.planeZ, closeTo(s.frontInsetAt(s.h), 1e-9));
      expect(seat.headrests.length, 3);
      final split = seat.sections[0][1];
      expect(split, closeTo(s.w * 0.6, 0.03));
    });

    test('분할 없는 세단은 등받이 장식이 없다', () {
      expect(seatLayout(TrunkSpace.avante()), isNull);
      expect(seatLayout(TrunkSpace.custom(w: 1, d: 1, h: 0.8)), isNull);
    });

    test('카니발 5:5 는 헤드레스트 2개', () {
      expect(seatLayout(TrunkSpace.carnival())!.headrests.length, 2);
    });

    _spaces().forEach((name, s) {
      test('$name: 헤드레스트는 프로필 평면보다 짐칸 쪽으로 나오지 않는다', () {
        final seat = seatLayout(s);
        if (seat == null) return;
        final meshes = headrestMeshes(seat);
        expect(meshes.length, seat.headrests.length);
        for (final mesh in meshes) {
          expectNoNaN(mesh, name);
          expectConvex(mesh, 1e-9, name);
          expectManifold(mesh, name);
          for (final p in mesh.allPoints) {
            expect(p.z, lessThanOrEqualTo(s.frontInsetAt(p.y) + 1e-9),
                reason: '$name: 헤드레스트가 짐칸으로 튀어나옴 $p');
            expect(p.y, greaterThanOrEqualTo(seat.topY - 1e-9));
            expect(p.y, lessThanOrEqualTo(seat.ceilY + 1e-9));
            expect(p.x, greaterThanOrEqualTo(s.xMinAt(seat.planeZ, p.y) - 1e-9));
            expect(p.x, lessThanOrEqualTo(s.xMaxAt(seat.planeZ, p.y) + 1e-9));
          }
        }
      });
    });
  });

  group('껍데기', () {
    _spaces().forEach((name, s) {
      test('$name: 그려진 옆벽은 물리 경계(xMinAt)보다 안쪽에 있지 않다', () {
        final seat = seatLayout(s);
        final zf = s.aperture == null
            ? s.d
            : s.d - s.aperture!.frameDepth - 1e-6;
        final faces = buildTrunkShell(s,
            stations: 10,
            headrestZoneY: (seat?.hasHeadrests ?? false) ? seat!.topY : null,
            headrestRecess: seat?.recess ?? 0);
        for (final sf in faces) {
          for (final p in sf.face.pts) {
            expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, isTrue);
          }
          if (sf.part != ShellPart.leftWall && sf.part != ShellPart.rightWall) {
            continue;
          }
          for (final p in sf.face.pts) {
            // 등받이 프로필 뒤(헤드레스트 구간의 파인 곳)는 짐칸이 아니다
            if (p.z < s.frontInsetAt(p.y) - 1e-9) continue;
            final z = p.z.clamp(0.0, zf).toDouble();
            if (sf.part == ShellPart.leftWall) {
              expect(p.x, lessThanOrEqualTo(s.xMinAt(z, p.y) + 1e-6),
                  reason: '$name 왼벽 $p');
            } else {
              expect(p.x, greaterThanOrEqualTo(s.xMaxAt(z, p.y) - 1e-6),
                  reason: '$name 오른벽 $p');
            }
          }
        }
      });
    });

    test('쏘렌토: 벽 꺾임(천장 높이 60%)에서 그림과 물리가 일치한다', () {
      final s = TrunkSpace.sorento();
      final faces = buildTrunkShell(s, stations: 10);
      final knee = s.interiorCeilingAt(0.5) * 0.6;
      // 꺾임 높이에 꼭짓점이 있고, 거기서 x = 0 (수직 구간의 끝)
      final atKnee = [
        for (final sf in faces)
          if (sf.part == ShellPart.leftWall)
            for (final p in sf.face.pts)
              if ((p.y - knee).abs() < 0.02 && p.z > 0.3 && p.z < 0.8) p
      ];
      expect(atKnee, isNotEmpty);
      for (final p in atKnee) {
        expect(p.x, closeTo(0, 1e-9));
      }
    });

    test('헤드레스트 구간은 프로필 평면 뒤로만 파인다', () {
      final s = TrunkSpace.sorento();
      final seat = seatLayout(s)!;
      final faces = buildTrunkShell(s,
          headrestZoneY: seat.topY, headrestRecess: seat.recess);
      final recess = faces.where((f) => f.part == ShellPart.seatRecess);
      expect(recess, isNotEmpty);
      for (final f in recess) {
        for (final p in f.face.pts) {
          expect(p.z, lessThan(seat.planeZ));
        }
      }
    });
  });
}
