import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/render3d/gear_shapes.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/label_layout.dart';

void main() {
  group('접촉 그림자 윤곽 (gearFootprint)', () {
    const pad = 0.015;
    for (final shape in GearShape.values) {
      test('${shape.name}: AABB 밑면(+여유) 안, 밑면 높이', () {
        final rnd = math.Random(shape.index);
        for (var i = 0; i < 40; i++) {
          final a = Aabb(0.2, 0.1, 0.3, 0.2 + 0.05 + rnd.nextDouble(),
              0.1 + 0.05 + rnd.nextDouble() * 0.7, 0.3 + 0.05 + rnd.nextDouble());
          final fp = gearFootprint(shape, a, pad: pad);
          expect(fp.length, greaterThanOrEqualTo(4));
          for (final p in fp) {
            expect(p.y, a.y1);
            expect(p.x, inInclusiveRange(a.x1 - pad - 1e-9, a.x2 + pad + 1e-9));
            expect(p.z, inInclusiveRange(a.z1 - pad - 1e-9, a.z2 + pad + 1e-9));
          }
        }
      });
    }

    test('세운 통은 타원: 귀퉁이에는 그림자가 없다', () {
      final a = const Aabb(0, 0, 0, 0.25, 0.36, 0.25); // 워터저그
      final fp = gearFootprint(GearShape.cylinder, a, pad: 0);
      expect(fp.length, cylinderSides);
      for (final p in fp) {
        final dx = (p.x - 0.125) / 0.125, dz = (p.z - 0.125) / 0.125;
        expect(dx * dx + dz * dz, closeTo(1, 1e-9));
      }
    });

    test('눕힌 원통은 폭보다 좁은 띠, 천 가방·캐리어는 모서리를 딴 팔각', () {
      final lying = const Aabb(0, 0, 0, 0.8, 0.3, 0.3);
      final strip = gearFootprint(GearShape.cylinder, lying, pad: 0);
      final zs = strip.map((p) => p.z);
      expect(zs.reduce(math.max) - zs.reduce(math.min), lessThan(0.3 * 0.8));
      final xs = strip.map((p) => p.x);
      expect(xs.reduce(math.max) - xs.reduce(math.min), closeTo(0.8, 1e-9));
      expect(gearFootprint(GearShape.softBag, lying).length, 8);
      expect(gearFootprint(GearShape.hardCase, lying).length, 8);
      expect(gearFootprint(GearShape.box, lying).length, 4);
    });
  });

  group('눌린 천 가방의 주름', () {
    TrimBox bag({double squash = 0, double squashW = 0, int rotY = 0}) => TrimBox(
          id: 'b',
          label: '침낭',
          w: 0.40,
          d: 0.26,
          h: 0.26,
          rotY: rotY,
          color: const Color(0xFF2E5090),
          shape: GearShape.softBag,
          soft: true,
          compressibility: 0.4,
          squash: squash,
          squashW: squashW,
        );
    int creaseCount(TrimBox b) => gearMesh(b)
        .faces
        .expand((f) => f.lines)
        .where((l) => l.pts.length == 3) // 주름은 세 점 꺾은선, 끈은 두 점
        .length;

    test('안 눌린 가방에는 주름이 없다', () {
      expect(creaseCount(bag()), 0);
    });

    test('높이로 눌리면 옆면 네 곳에 가로 주름 (많이 눌릴수록 3줄)', () {
      expect(creaseCount(bag(squash: 0.10)), 4 * 2);
      expect(creaseCount(bag(squash: 0.30)), 4 * 3);
      // 가로 주름: 한 줄 안에서 y 변화가 작다
      final b = bag(squash: 0.30);
      final a = Aabb.fromBox(b);
      for (final f in gearMesh(b).faces) {
        for (final l in f.lines.where((l) => l.pts.length == 3)) {
          expect(f.normal.y.abs(), lessThan(1e-9)); // 옆면에만
          final ys = l.pts.map((p) => p.y);
          expect(ys.reduce(math.max) - ys.reduce(math.min), lessThan(a.h * 0.1));
        }
      }
    });

    test('옆으로 눌리면 윗면에 눌린 축과 수직인 주름 (회전도 반영)', () {
      for (final rot in [0, 90]) {
        final b = bag(squashW: 0.25, rotY: rot);
        final mesh = gearMesh(b);
        final creases = [
          for (final f in mesh.faces)
            for (final l in f.lines.where((l) => l.pts.length == 3)) (f, l)
        ];
        expect(creases.length, 3);
        for (final (f, l) in creases) {
          expect(f.normal.y, closeTo(1, 1e-9)); // 윗면
          final dx = (l.pts.last.x - l.pts.first.x).abs();
          final dz = (l.pts.last.z - l.pts.first.z).abs();
          // rot 0: w(=x) 가 눌림 → 주름은 z 방향. rot 90: w 가 월드 z → 주름은 x 방향.
          if (rot == 0) {
            expect(dz, greaterThan(dx));
          } else {
            expect(dx, greaterThan(dz));
          }
        }
      }
    });

    test('다른 모양은 눌림 값을 줘도 주름이 없다', () {
      final a = const Aabb(0, 0, 0, 0.5, 0.3, 0.3);
      for (final shape in GearShape.values) {
        if (shape == GearShape.softBag) continue;
        final plain = gearMeshFor(shape, a);
        final squashed = gearMeshFor(shape, a, squashY: 0.3, squashX: 0.2);
        expect(squashed.faces.expand((f) => f.lines).length,
            plain.faces.expand((f) => f.lines).length);
      }
    });
  });

  group('라벨 자리 잡기 (placeLabelGroup)', () {
    const face = Rect.fromLTWH(100, 100, 200, 120);
    const centre = Offset(200, 160);

    test('빈 화면이면 면 중심에 [배지][라벨]', () {
      final spot = placeLabelGroup(
          face: face, centre: centre, badgeWidth: 24, pillWidth: 90, placed: [])!;
      expect(spot.withPill, isTrue);
      expect(spot.overlapping, isFalse);
      expect(spot.rect.center.dy, 160);
      expect(spot.rect.width, 114);
      expect(spot.rect.center.dx, closeTo(200, 1e-9));
    });

    test('이웃 배지와 겹치면 위아래로 비켜 놓는다', () {
      final neighbourBadge = Rect.fromLTWH(140, 150, 20, 20); // 가운데 줄을 막음
      final spot = placeLabelGroup(
          face: face,
          centre: centre,
          badgeWidth: 24,
          pillWidth: 90,
          placed: [neighbourBadge])!;
      expect(spot.overlapping, isFalse);
      expect(spot.withPill, isTrue);
      expect(spot.rect.overlaps(neighbourBadge.inflate(2)), isFalse);
      expect(spot.rect.center.dy, isNot(160));
      // 면 밖으로 나가지 않는다
      expect(spot.rect.top, greaterThanOrEqualTo(face.top));
      expect(spot.rect.bottom, lessThanOrEqualTo(face.bottom));
    });

    test('줄마다 막혀 있으면 라벨을 떼고 배지만 남긴다', () {
      // 세로로 길게 면의 오른쪽 2/3 를 막은 이웃 라벨
      final wall = Rect.fromLTWH(170, 90, 140, 140);
      final spot = placeLabelGroup(
          face: face,
          centre: const Offset(140, 160),
          badgeWidth: 24,
          pillWidth: 90,
          placed: [wall])!;
      expect(spot.withPill, isFalse);
      expect(spot.overlapping, isFalse);
      expect(spot.rect.width, 24);
      expect(spot.rect.overlaps(wall.inflate(2)), isFalse);
    });

    test('어디에도 자리가 없으면 원래 자리에 그린다 (숨기지 않는다)', () {
      final everything = Rect.fromLTWH(0, 0, 1000, 1000);
      final spot = placeLabelGroup(
          face: face,
          centre: centre,
          badgeWidth: 24,
          pillWidth: 90,
          placed: [everything])!;
      expect(spot.overlapping, isTrue);
      expect(spot.rect.center.dy, 160);
    });

    test('배지도 라벨도 없으면 null, 라벨만 있으면 라벨만', () {
      expect(
          placeLabelGroup(
              face: face, centre: centre, badgeWidth: 0, pillWidth: null, placed: []),
          isNull);
      final spot = placeLabelGroup(
          face: face, centre: centre, badgeWidth: 0, pillWidth: 80, placed: [])!;
      expect(spot.withPill, isTrue);
      expect(spot.rect.width, 80);
    });

    test('여러 이웃을 차례로 놓아도 서로 겹치지 않는다 (자리가 있는 한)', () {
      final rnd = math.Random(8);
      for (var round = 0; round < 50; round++) {
        final placed = <Rect>[];
        for (var i = 0; i < 6; i++) {
          final f = Rect.fromLTWH(rnd.nextDouble() * 300, rnd.nextDouble() * 200,
              120 + rnd.nextDouble() * 120, 60 + rnd.nextDouble() * 100);
          final spot = placeLabelGroup(
              face: f,
              centre: f.center,
              badgeWidth: 24,
              pillWidth: 40 + rnd.nextDouble() * 60,
              placed: placed)!;
          if (!spot.overlapping) {
            for (final p in placed) {
              expect(spot.rect.overlaps(p), isFalse);
            }
          }
          placed.add(spot.rect);
        }
      }
    });
  });
}
