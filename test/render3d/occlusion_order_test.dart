// 그리기 순서 속성 테스트: 페인터가 쓰는 sceneDrawOrder 가 가림 관계를 뒤집지 않는다.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/geometry.dart';
import 'package:trimbox/render3d/scene.dart';
import 'package:trimbox/render3d/vec3.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'scene_fixtures.dart';

/// 분리 평면 기준으로 a 가 b 보다 확실히 앞(카메라 쪽)에 있는가.
/// 분리축이 여럿이면 전부 같은 답일 때만 — 축마다 답이 다르면 두 상자는 서로를
/// 가릴 수 없다 (카메라에서 나간 반직선이 한 평면을 두 번 건너야 하므로).
bool _strictlyInFront(Aabb a, Aabb b, Vec3 cam) {
  const eps = 1e-4;
  int? verdict; // 1 = a 가 앞
  for (var axis = 0; axis < 3; axis++) {
    int r;
    if (a.maxOn(axis) <= b.minOn(axis) + eps) {
      final plane = (a.maxOn(axis) + b.minOn(axis)) / 2;
      r = cam[axis] < plane ? 1 : -1; // 카메라가 a 쪽이면 a 가 앞
    } else if (b.maxOn(axis) <= a.minOn(axis) + eps) {
      final plane = (b.maxOn(axis) + a.minOn(axis)) / 2;
      r = cam[axis] > plane ? 1 : -1;
    } else {
      continue;
    }
    if (verdict == null) {
      verdict = r;
    } else if (verdict != r) {
      return false;
    }
  }
  return verdict == 1;
}

Rect? _screenRect(Aabb a, OrbitCamera cam, Size size) {
  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final c in a.corners) {
    final p = cam.project(c, size);
    if (p == null) return null;
    l = math.min(l, p.screen.dx);
    r = math.max(r, p.screen.dx);
    t = math.min(t, p.screen.dy);
    b = math.max(b, p.screen.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// 앱과 같은 방식: 자동 배치하고, 못 넣은 짐은 테일게이트 밖에 나란히 세운다.
List<TrimBox> _randomScene(TrunkSpace space, math.Random rnd) {
  final catalog = gearCatalog().where((g) => g.label != '커스텀').toList();
  final n = 5 + rnd.nextInt(16);
  final boxes = [
    for (var i = 0; i < n; i++)
      gearBox(catalog[rnd.nextInt(catalog.length)].label, i),
  ];
  final result = AutoLayoutEngine.computeLayout(space, boxes,
      budget: const Duration(milliseconds: 150));
  for (final p in result.placements) {
    p.applyTo(p.box);
  }
  var x = 0.0;
  for (final u in result.unfitBoxes) {
    u
      ..rotY = 0
      ..x = x
      ..y = 0
      ..z = space.d + 0.06;
    x += u.effectiveW + 0.05;
  }
  return boxes;
}

OrbitCamera _randomCamera(TrunkSpace space, Size size, math.Random rnd) {
  final yaw = (rnd.nextDouble() * 2 - 1) * OrbitCamera.maxYawAbs;
  final pitch = OrbitCamera.minPitch +
      rnd.nextDouble() * (OrbitCamera.maxPitch - OrbitCamera.minPitch);
  final fit = OrbitCamera.fitTrunk(space, size, yaw: yaw, pitch: pitch);
  // 앱의 줌 범위 (맞춤 거리의 0.45~2.5배)
  final zoom = 0.45 + rnd.nextDouble() * (2.5 - 0.45);
  return fit.copyWith(distance: fit.distance * zoom).clamped(
      minDistance: fit.distance * 0.45, maxDistance: fit.distance * 2.5);
}

void main() {
  const size = Size(960, 640);
  final spaces = <String, TrunkSpace>{
    'sorento': TrunkSpace.sorento(),
    'sorento slide 0.27': TrunkSpace.sorento(seatSlide: 0.27),
    'tucson': TrunkSpace.tucson(),
  };

  spaces.forEach((name, space) {
    test('$name: 무작위 적재 × 무작위 카메라에서 가림 순서가 뒤집히지 않는다', () {
      final rnd = math.Random(name.hashCode ^ 0x5eed);
      var pairsChecked = 0, fixturePairs = 0, splitFrames = 0, frames = 0;
      final bad = <String>[];

      for (var scene = 0; scene < 14; scene++) {
        final boxes = _randomScene(space, rnd);
        for (var c = 0; c < 10; c++) {
          final cam = _randomCamera(space, size, rnd);
          final order = sceneDrawOrder(space, boxes, cam);
          expect(order.length, greaterThan(boxes.length)); // 고정물 포함
          splitFrames += order.any((o) => o.isSplit) ? 1 : 0;
          frames++;
          final rects = [for (final o in order) _screenRect(o.aabb, cam, size)];

          for (var i = 0; i < order.length; i++) {
            for (var j = i + 1; j < order.length; j++) {
              final a = order[i], b = order[j]; // a 를 먼저 그린다
              if (a.origin == b.origin) continue; // 같은 물체의 조각
              final ra = rects[i], rb = rects[j];
              if (ra == null || rb == null) continue;
              final overlap = ra.intersect(rb);
              if (overlap.width <= 1 || overlap.height <= 1) continue;
              pairsChecked++;
              if (a.isFixture || b.isFixture) fixturePairs++;
              if (_strictlyInFront(a.aabb, b.aabb, cam.position)) {
                bad.add('scene $scene cam(yaw ${cam.yaw.toStringAsFixed(2)}, '
                    'pitch ${cam.pitch.toStringAsFixed(2)}): '
                    '${a.box?.label ?? 'fixture'} ${a.aabb} 가 '
                    '${b.box?.label ?? 'fixture'} ${b.aabb} 보다 앞인데 먼저 그려짐');
              }
            }
          }
        }
      }
      expect(bad, isEmpty,
          reason: '${bad.length}건\n${bad.take(8).join('\n')}');
      // ignore: avoid_print
      print('[occlusion] $name: $frames frames, $splitFrames needed splitting, '
          '$pairsChecked overlapping pairs checked');
      expect(pairsChecked, greaterThan(2000));
      expect(fixturePairs, greaterThan(200));
    });
  });

  test('겹친(충돌 중인) 상자가 섞여 있어도 나머지 순서는 지켜진다', () {
    final space = TrunkSpace.sorento();
    final rnd = math.Random(42);
    final boxes = _randomScene(space, rnd);
    // 드래그 중처럼 한 상자를 다른 상자 속으로 밀어 넣는다
    boxes.first
      ..x = boxes.last.x + 0.02
      ..y = boxes.last.y
      ..z = boxes.last.z + 0.02;
    for (var c = 0; c < 20; c++) {
      final cam = _randomCamera(space, size, rnd);
      final order = sceneDrawOrder(space, boxes, cam);
      expect(order.map((o) => o.box?.id).whereType<String>().toSet().length,
          boxes.length);
      // 물체마다 그림자는 한 번, 라벨도 한 번
      for (final b in boxes) {
        final mine = order.where((o) => o.box?.id == b.id);
        expect(mine.where((o) => o.isFirstPart).length, 1);
        expect(mine.where((o) => o.isLastPart).length, 1);
      }
    }
  });
}
