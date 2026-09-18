import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/fixtures.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/picking.dart';
import 'package:trimbox/render3d/vec3.dart';

const _sizes = [
  Size(1280, 900),
  Size(960, 640),
  Size(820, 1180),
  Size(390, 560),
  Size(360, 420),
  Size(844, 300),
];

Map<String, TrunkSpace> _spaces() => {
      'sorento': TrunkSpace.sorento(),
      'sorento slide 0.27': TrunkSpace.sorento(seatSlide: 0.27),
      'sorento7': TrunkSpace.sorento7(),
      'tucson': TrunkSpace.tucson(),
      'carnival': TrunkSpace.carnival(),
      'avante': TrunkSpace.avante(),
    };

/// 화면에 꼭 보여야 하는 점들: 바닥 네 귀, 개구부 외곽, 등받이 윗선
List<Vec3> _keyPoints(TrunkSpace s) {
  final seat = seatLayout(s);
  final zTop = s.frontInsetAt(s.h);
  final seatTopY = seat?.ceilY ?? s.interiorCeilingAt(zTop);
  return [
    Vec3(0, 0, 0),
    Vec3(s.w, 0, 0),
    Vec3(0, 0, s.d),
    Vec3(s.w, 0, s.d),
    ...openingOutline(s),
    Vec3(s.xMinAt(zTop, seatTopY), seatTopY, zTop),
    Vec3(s.xMaxAt(zTop, seatTopY), seatTopY, zTop),
    if (seat != null) ...[
      Vec3(0, seat.topY, s.frontInsetAt(seat.topY)),
      Vec3(s.w, seat.topY, s.frontInsetAt(seat.topY)),
    ],
  ];
}

void main() {
  group('fitTrunk: 캔버스 크기 × 각도 극단에서도 핵심 점이 8px 여백 안', () {
    const yaws = [-OrbitCamera.maxYawAbs, -0.6, 0.0, 0.6, OrbitCamera.maxYawAbs];
    const pitches = [
      OrbitCamera.minPitch,
      22 * math.pi / 180,
      1.0,
      OrbitCamera.maxPitch,
    ];
    _spaces().forEach((name, s) {
      for (final size in _sizes) {
        test('$name ${size.width.round()}×${size.height.round()}', () {
          for (final yaw in yaws) {
            for (final pitch in pitches) {
              final cam = OrbitCamera.fitTrunk(s, size, yaw: yaw, pitch: pitch);
              expect(cam.distance.isFinite && cam.distance > 0, isTrue);
              for (final p in _keyPoints(s)) {
                final pp = cam.project(p, size);
                final why = '$name $size yaw ${yaw.toStringAsFixed(2)} '
                    'pitch ${pitch.toStringAsFixed(2)} 점 $p';
                expect(pp, isNotNull, reason: why);
                expect(pp!.screen.dx, inInclusiveRange(8, size.width - 8),
                    reason: why);
                expect(pp.screen.dy, inInclusiveRange(8, size.height - 8),
                    reason: why);
              }
              // 너무 멀어지지도 않는다: 트렁크가 화면의 절반 이상을 쓴다 (가로 또는 세로)
              var l = double.infinity, r = -double.infinity;
              var t = double.infinity, b = -double.infinity;
              for (final x in [0.0, s.w]) {
                for (final y in [0.0, s.h]) {
                  for (final z in [0.0, s.d]) {
                    final q = cam.project(Vec3(x, y, z), size)!.screen;
                    l = math.min(l, q.dx);
                    r = math.max(r, q.dx);
                    t = math.min(t, q.dy);
                    b = math.max(b, q.dy);
                  }
                }
              }
              final fill = math.max((r - l) / size.width, (b - t) / size.height);
              expect(fill, greaterThan(0.7),
                  reason: '$name $size yaw $yaw pitch $pitch: 화면을 덜 채움 $fill');
            }
          }
        });
      }
    });
  });

  group('투영 ↔ 반직선 왕복', () {
    test('임의의 점: project → ray → 수평면 교점 오차 < 1mm', () {
      final rnd = math.Random(99);
      final s = TrunkSpace.sorento();
      var checked = 0;
      for (var i = 0; i < 400; i++) {
        final size = _sizes[rnd.nextInt(_sizes.length)];
        final yaw = (rnd.nextDouble() * 2 - 1) * OrbitCamera.maxYawAbs;
        final pitch = OrbitCamera.minPitch +
            rnd.nextDouble() * (OrbitCamera.maxPitch - OrbitCamera.minPitch);
        final cam = OrbitCamera.fitTrunk(s, size, yaw: yaw, pitch: pitch)
            .copyWith(
                pan: Offset(rnd.nextDouble() * 80 - 40, rnd.nextDouble() * 80 - 40));
        final p = Vec3(rnd.nextDouble() * s.w, rnd.nextDouble() * s.h,
            rnd.nextDouble() * (s.d + 0.5));
        final pp = cam.project(p, size);
        if (pp == null) continue;
        final ray = cam.ray(pp.screen, size);
        // 반직선은 그 점을 지난다 (어느 평면과도 무관하게)
        final along = (p - ray.origin).dot(ray.dir);
        expect((ray.at(along) - p).length, lessThan(1e-3));
        expect(along, closeTo(
            (p - cam.position).length, 1e-6)); // 깊이 = 카메라까지의 거리
        // 수평면 y = p.y 와의 교점 (드래그가 쓰는 경로). 시선이 평면과 거의 나란하면
        // 오차가 증폭되므로 그런 경우는 뺀다.
        if (ray.dir.y.abs() < 0.05) continue;
        final hit = rayPlaneY(ray, p.y);
        expect(hit, isNotNull);
        expect((hit! - p).length, lessThan(1e-3), reason: '$p via ${pp.screen}');
        checked++;
      }
      expect(checked, greaterThan(250));
    });
  });

  group('clamped', () {
    test('NaN·무한대 입력도 유한한 카메라가 된다', () {
      final s = TrunkSpace.sorento();
      final fit = OrbitCamera.fitTrunk(s, const Size(960, 640));
      for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
        final cam = OrbitCamera(
                target: fit.target, yaw: bad, pitch: bad, distance: bad)
            .clamped(minDistance: 1, maxDistance: 5, keepOutside: s);
        final pos = cam.position;
        expect(pos.x.isFinite && pos.y.isFinite && pos.z.isFinite, isTrue);
        expect(cam.distance, inInclusiveRange(1, 5));
      }
    });

    test('keepOutside 가 없으면 예전과 같다 (거리만 자른다)', () {
      final s = TrunkSpace.sorento();
      final fit = OrbitCamera.fitTrunk(s, const Size(960, 640));
      final cam = fit
          .copyWith(distance: 0.01)
          .clamped(minDistance: 0.3, maxDistance: 9);
      expect(cam.distance, 0.3);
    });

    test('문서화: keepOutside 없이 최대 확대 후 옆으로 돌리면 트렁크 안에 들어가는 경우가 있다',
        () {
      // 앱은 맞춤 거리를 캔버스 크기가 정해질 때의 각도(보통 정면)로 한 번만 잡고,
      // 그 0.45배까지 확대를 허용한다. 호출부가 keepOutside 를 넘겨야 하는 이유.
      final found = <String>[];
      for (final entry in _spaces().entries) {
        final s = entry.value;
        for (final size in _sizes) {
          final fit = OrbitCamera.fitTrunk(s, size); // 정면, 기본 피치
          for (final yaw in [-OrbitCamera.maxYawAbs, OrbitCamera.maxYawAbs]) {
            for (final pitch in [OrbitCamera.minPitch, 0.4]) {
              final plain = fit
                  .copyWith(yaw: yaw, pitch: pitch, distance: fit.distance * 0.45)
                  .clamped(
                      minDistance: fit.distance * 0.45,
                      maxDistance: fit.distance * 2.5);
              final p = plain.position;
              final inside = p.x > 0 &&
                  p.x < s.w &&
                  p.y > 0 &&
                  p.y < s.h &&
                  p.z > 0 &&
                  p.z < s.d;
              if (!inside) continue;
              found.add('${entry.key} ${size.width.round()}×${size.height.round()} '
                  'yaw ${yaw.toStringAsFixed(2)} pitch ${pitch.toStringAsFixed(2)} → $p');
              final safe = plain.clamped(
                  minDistance: fit.distance * 0.45,
                  maxDistance: fit.distance * 2.5,
                  keepOutside: s);
              final q = safe.position;
              expect(q.x <= 0 || q.x >= s.w || q.y >= s.h || q.z >= s.d, isTrue);
            }
          }
        }
      }
      // ignore: avoid_print
      print('[camera] inside-trunk without keepOutside: ${found.length} cases'
          '${found.isEmpty ? '' : ', e.g. ${found.first}'}');
    });

    test('NaN 을 만들지 않고, 카메라가 트렁크 안으로 들어가지 않는다', () {
      final rnd = math.Random(5);
      for (final s in _spaces().values) {
        for (final size in _sizes) {
          final fit = OrbitCamera.fitTrunk(s, size);
          for (var i = 0; i < 60; i++) {
            // 앱과 같은 줌 범위 (맞춤 거리의 0.45~2.5배) 에 말도 안 되는 입력을 넣는다
            final wild = OrbitCamera(
              target: fit.target,
              yaw: (rnd.nextDouble() * 2 - 1) * 10,
              pitch: (rnd.nextDouble() * 2 - 1) * 5,
              distance: rnd.nextBool()
                  ? rnd.nextDouble() * 0.2
                  : rnd.nextDouble() * 1000,
              pan: Offset(rnd.nextDouble() * 400 - 200, rnd.nextDouble() * 400 - 200),
            );
            final cam = wild.clamped(
                minDistance: fit.distance * 0.45,
                maxDistance: fit.distance * 2.5,
                keepOutside: s);
            final pos = cam.position;
            expect(pos.x.isFinite && pos.y.isFinite && pos.z.isFinite, isTrue);
            expect(cam.yaw.abs(), lessThanOrEqualTo(OrbitCamera.maxYawAbs));
            expect(cam.pitch,
                inInclusiveRange(OrbitCamera.minPitch, OrbitCamera.maxPitch));
            for (final v in [cam.forward, cam.right, cam.up]) {
              expect(v.x.isFinite && v.y.isFinite && v.z.isFinite, isTrue);
              expect(v.length, closeTo(1, 1e-9));
            }
            final inside = pos.x > 0 &&
                pos.x < s.w &&
                pos.y > 0 &&
                pos.y < s.h &&
                pos.z > 0 &&
                pos.z < s.d;
            expect(inside, isFalse,
                reason: '카메라가 트렁크 안: $pos (yaw ${cam.yaw}, pitch ${cam.pitch}, '
                    'dist ${cam.distance}, $size)');
            // 타깃은 항상 보인다
            expect(cam.project(cam.target, size), isNotNull);
          }
        }
      }
    });

    test('최소 줌에서도 가장 가까운 각도 조합이 트렁크 밖', () {
      for (final s in _spaces().values) {
        for (final size in _sizes) {
          for (final yaw in [-OrbitCamera.maxYawAbs, 0.0, OrbitCamera.maxYawAbs]) {
            for (final pitch in [OrbitCamera.minPitch, OrbitCamera.maxPitch]) {
              final fit = OrbitCamera.fitTrunk(s, size, yaw: yaw, pitch: pitch);
              final pos = fit
                  .copyWith(distance: fit.distance * 0.45)
                  .clamped(
                      minDistance: fit.distance * 0.45,
                      maxDistance: fit.distance * 2.5,
                      keepOutside: s)
                  .position;
              final inside = pos.x > 0 &&
                  pos.x < s.w &&
                  pos.y > 0 &&
                  pos.y < s.h &&
                  pos.z > 0 &&
                  pos.z < s.d;
              expect(inside, isFalse, reason: '$size yaw $yaw pitch $pitch → $pos');
            }
          }
        }
      }
    });
  });
}
