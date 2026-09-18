import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';

import 'scene_fixtures.dart';

/// 모양마다 하나씩 + 눌림·회전·경계 밖 주차까지 섞은 박스들
List<TrimBox> _mixedBoxes(TrunkSpace s) {
  final out = <TrimBox>[];
  var i = 0;
  for (final shape in GearShape.values) {
    final col = i % 3, row = i ~/ 3;
    out.add(TrimBox(
      id: 'm$i',
      label: '${shape.name} 짐',
      w: 0.30 + 0.05 * (i % 2),
      d: 0.22,
      h: 0.18 + 0.04 * (i % 3),
      x: 0.16 + col * 0.34,
      z: 0.05 + row * 0.26,
      rotY: i.isEven ? 0 : 90,
      color: campingColors[i % campingColors.length],
      shape: shape,
      soft: shape == GearShape.softBag,
      compressibility: shape == GearShape.softBag ? 0.4 : 0,
      squash: shape == GearShape.softBag ? 0.3 : 0,
    )..loadOrder = i + 1);
    i++;
  }
  // 위에 얹은 짐, 테일게이트 밖에 세워 둔 짐, 벽을 뚫은 짐
  out.add(TrimBox(
      id: 'top', label: '위', w: 0.2, d: 0.2, h: 0.1, x: 0.16, y: 0.3, z: 0.05,
      color: const Color(0xFFBAE1FF), shape: GearShape.cylinder));
  out.add(TrimBox(
      id: 'parked', label: '밖', w: 0.3, d: 0.3, h: 0.4, x: 0, z: s.d + 0.06,
      color: const Color(0xFF1A1A2E), shape: GearShape.hardCase));
  out.add(TrimBox(
      id: 'through', label: '벽', w: 0.3, d: 0.3, h: 0.3, x: -0.1, z: 0.4,
      color: const Color(0xFFFFFFBA)));
  return out;
}

void _paint(TrunkPainter3D painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

void main() {
  const sizes = [Size(960, 640), Size(390, 560), Size(1, 1)];

  for (final preset in TrunkPreset.values) {
    testWidgets('${preset.name}: 카메라·상태 조합이 예외 없이 그려진다',
        (tester) async {
      final space = preset.toTrunkSpace() ??
          TrunkSpace.custom(
            w: 1.2,
            d: 1.0,
            h: 0.8,
            leftWheelhouse: const Wheelhouse(w: 0.1, d: 0.3, h: 0.25),
          );
      final boxes = _mixedBoxes(space);
      final ids = boxes.map((b) => b.id).toList();

      final cameras = <OrbitCamera>[];
      for (final size in sizes) {
        cameras.add(OrbitCamera.fitTrunk(space, size));
      }
      const size = Size(960, 640);
      for (final yaw in [-OrbitCamera.maxYawAbs, -0.6, 0.6, OrbitCamera.maxYawAbs]) {
        for (final pitch in [OrbitCamera.minPitch, 1.0, OrbitCamera.maxPitch]) {
          cameras.add(OrbitCamera.fitTrunk(space, size, yaw: yaw, pitch: pitch));
        }
      }
      // 아주 가까이 (꼭짓점 일부가 near plane 뒤로 간다)
      cameras.add(OrbitCamera.fitTrunk(space, size).copyWith(distance: 0.4));
      cameras.add(OrbitCamera.fitTrunk(space, size, yaw: 1.2)
          .copyWith(distance: 0.9, pan: const Offset(120, -40)));

      final flagSets = <TrunkPainter3D Function(OrbitCamera)>[
        (c) => TrunkPainter3D(space: space, boxes: const [], camera: c),
        (c) => TrunkPainter3D(space: space, boxes: boxes, camera: c),
        (c) => TrunkPainter3D(
            space: space, boxes: boxes, camera: c, selectedBoxId: ids[1]),
        (c) => TrunkPainter3D(
            space: space,
            boxes: boxes,
            camera: c,
            selectedBoxId: ids[2],
            draggingBoxId: ids[2],
            collidingBoxIds: {ids[2], ids[3], 'through'}),
        (c) => TrunkPainter3D(
            space: space,
            boxes: boxes,
            camera: c,
            tailgateBlockedIds: {ids.last, ids[4]}),
        (c) => TrunkPainter3D(
            space: space, boxes: boxes, camera: c, highlightLoadOrder: 4),
        (c) => TrunkPainter3D(
            space: space, boxes: boxes, camera: c, showLabels: false),
      ];

      for (final cam in cameras) {
        for (final build in flagSets) {
          for (final s in [size, const Size(390, 560)]) {
            _paint(build(cam), s);
          }
        }
      }
    });
  }

  testWidgets('SceneCache: 같은 카메라면 껍데기를 재사용하고, 바뀌면 다시 그린다',
      (tester) async {
    final space = TrunkSpace.sorento();
    final boxes = _mixedBoxes(space);
    const size = Size(800, 600);
    final cache = SceneCache();
    final cam = OrbitCamera.fitTrunk(space, size);
    _paint(TrunkPainter3D(space: space, boxes: boxes, camera: cam, cache: cache),
        size);
    final first = cache.shell;
    expect(first, isNotNull);
    _paint(TrunkPainter3D(space: space, boxes: boxes, camera: cam, cache: cache),
        size);
    expect(identical(cache.shell, first), isTrue);
    _paint(
        TrunkPainter3D(
            space: space,
            boxes: boxes,
            camera: cam.copyWith(yaw: 0.3),
            cache: cache),
        size);
    expect(identical(cache.shell, first), isFalse);
    // 트렁크가 바뀌면 고정물도 다시 만든다
    final f1 = cache.fixturesFor(space);
    expect(identical(cache.fixturesFor(space), f1), isTrue);
    expect(identical(cache.fixturesFor(TrunkSpace.sorento(seatSlide: 0.1)), f1),
        isFalse);
    cache.dispose();
  });

  testWidgets('물체 패스 성능: 25개 물체', (tester) async {
    final space = TrunkSpace.sorento();
    // 가족 세트(16) 적재 + 미니멀 세트(9)는 테일게이트 밖에 세워 둠 = 25개
    final boxes = packedBundle(space, familyBundle);
    final extra = gearBoxes(
        gearBundleLabels('2인 미니멀 캠핑'));
    var x = 0.0;
    for (final b in extra) {
      b
        ..x = x
        ..z = space.d + 0.06;
      x += b.effectiveW + 0.05;
    }
    final all = [...boxes, ...extra];
    while (all.length < 25) {
      all.add(gearBox('헬리녹스 체어원', 100 + all.length)
        ..x = x
        ..z = space.d + 0.5);
      x += 0.4;
    }
    final scene = all.take(25).toList();
    expect(scene.length, 25);

    const size = Size(960, 640);
    final cache = SceneCache();
    final painter = TrunkPainter3D(
      space: space,
      boxes: scene,
      camera: OrbitCamera.fitTrunk(space, size, yaw: 0.35),
      selectedBoxId: scene.first.id,
      cache: cache,
    );

    double run(void Function(Canvas) body, int frames) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        final recorder = ui.PictureRecorder();
        body(Canvas(recorder));
        recorder.endRecording().dispose();
      }
      return sw.elapsedMicroseconds / frames / 1000.0;
    }

    run((c) => painter.paint(c, size), 10); // 워밍업 (JIT + 껍데기 캐시)
    final objectsMs = run((c) => painter.paintObjectsOnly(c, size), 60);
    final frameMs = run((c) => painter.paint(c, size), 60);
    final polys = scene.fold<int>(0, (n, b) => n + polygonCount(b));
    final maxPolys = scene.map(polygonCount).reduce(math.max);
    // ignore: avoid_print
    print('[render perf] 25 boxes + fixtures: objects pass '
        '${objectsMs.toStringAsFixed(2)} ms, full frame (cached shell) '
        '${frameMs.toStringAsFixed(2)} ms; box polygons total $polys, '
        'max per box $maxPolys');
    expect(maxPolys, lessThanOrEqualTo(70));
    // 넉넉한 상한 (CI 흔들림 대비). 목표는 8ms 미만.
    expect(objectsMs, lessThan(40));
    cache.dispose();
  });
}
