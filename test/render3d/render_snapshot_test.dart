// 시각 확인용 하네스: TrunkPainter3D 를 PNG 로 떠서 build/render_snapshots/ 에 쓴다.
// 픽셀 비교는 하지 않는다 (예외 없이 그려지는지만 검사). 글자는 테스트 폰트(Ahem)라
// 네모로 나온다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';
import 'package:trimbox/utils/collision.dart';

import 'scene_fixtures.dart';

const _outDir = 'build/render_snapshots';
const _desktop = Size(960, 640);
const _phone = Size(390, 560);

Future<void> _shoot(
  WidgetTester tester,
  String name,
  TrunkSpace space,
  List<TrimBox> boxes, {
  Size size = _desktop,
  double yaw = 0,
  double? pitch,
  String? selected,
  Set<String> colliding = const {},
  Set<String> blocked = const {},
  int? step,
  double scale = 1.0,
}) async {
  final cam = pitch == null
      ? OrbitCamera.fitTrunk(space, size, yaw: yaw)
      : OrbitCamera.fitTrunk(space, size, yaw: yaw, pitch: pitch);
  final painter = TrunkPainter3D(
    space: space,
    boxes: boxes,
    camera: cam,
    selectedBoxId: selected,
    collidingBoxIds: colliding,
    tailgateBlockedIds: blocked,
    highlightLoadOrder: step,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  await tester.runAsync(() async {
    final image = await picture.toImage(
        (size.width * scale).round(), (size.height * scale).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
  picture.dispose();
}

void main() {
  final sorento = TrunkSpace.sorento();

  testWidgets('1 빈 쏘렌토', (tester) async {
    await _shoot(tester, '01_empty_default', sorento, const []);
    await _shoot(tester, '01_empty_yaw_left', sorento, const [], yaw: -0.6);
    await _shoot(tester, '01_empty_yaw_right', sorento, const [], yaw: 0.6);
    await _shoot(tester, '01_empty_top', sorento, const [], pitch: 1.0);
    await _shoot(tester, '01_empty_phone', sorento, const [], size: _phone);
  });

  testWidgets('2 4인 가족 세트 적재', (tester) async {
    final boxes = packedBundle(sorento, familyBundle);
    expect(boxes, isNotEmpty);
    await _shoot(tester, '02_family_default', sorento, boxes);
    await _shoot(tester, '02_family_yaw_left', sorento, boxes, yaw: -0.6);
    await _shoot(tester, '02_family_yaw_right', sorento, boxes,
        yaw: 0.6,
        selected: boxes.firstWhere((b) => b.shape == GearShape.cooler).id);
    await _shoot(tester, '02_family_top', sorento, boxes, pitch: 1.0);
    await _shoot(tester, '02_family_phone', sorento, boxes, size: _phone);
    await _shoot(tester, '02_family_step5', sorento, boxes, step: 5, yaw: 0.35);
  });

  testWidgets('3 테일게이트 걸림', (tester) async {
    final boxes = packedBundle(sorento, '2인 미니멀 캠핑');
    // 테일게이트 바로 앞에 키 큰 캐리어를 세운다 → 유리 기울기에 걸린다
    final tall = gearBox('대형 캐리어 (28")', 90)
      ..x = 0.62
      ..y = 0
      ..z = sorento.d - 0.31;
    boxes.add(tall);
    final detector = CollisionDetector(sorento);
    final blocked = detector.tailgateBlockers(boxes);
    final colliding = detector.findAllCollisions(boxes);
    expect(blocked, contains(tall.id));
    await _shoot(tester, '03_tailgate_blocked', sorento, boxes,
        blocked: blocked, colliding: colliding, yaw: 0.45);
    await _shoot(tester, '03_tailgate_blocked_phone', sorento, boxes,
        blocked: blocked, colliding: colliding, size: _phone);
  });

  testWidgets('4 눌린 연질 짐', (tester) async {
    final bags = gearBoxes([
      '일반 침낭 (3계절)',
      '일반 침낭 (3계절)',
      '듀얼 커플 침낭',
      '캠핑 더플백 60L',
      '모포/담요',
      '다운침낭 (경량)',
      '대형 아이스박스 (50L)',
      '스노우피크 쉘프컨테이너 50',
    ]);
    // 손으로 놓고 눌러 둔다 (물리 검증 대상이 아니라 그림 확인용)
    bags[0]..x = 0.20..z = 0.30..squash = 0.30;
    bags[1]..x = 0.20..z = 0.30..y = bags[0].top;
    bags[2]..x = 0.65..z = 0.25..squash = 0.30;
    bags[3]..x = 0.20..z = 0.62..squashW = 0.20;
    bags[4]..x = 0.70..z = 0.66..squash = 0.40;
    bags[5]..x = 0.72..z = 0.62..y = bags[4].top..squashD = 0.30;
    bags[6]..x = 0.70..z = 0.26..y = bags[2].top;
    bags[7]..x = 0.20..z = 0.62..y = bags[3].top;
    await _shoot(tester, '04_squashed', sorento, bags, yaw: -0.35);
    await _shoot(tester, '04_squashed_phone', sorento, bags, size: _phone);
  });

  testWidgets('5 2열 슬라이드 0.27', (tester) async {
    final slid = TrunkSpace.sorento(seatSlide: 0.27);
    await _shoot(tester, '05_slide_empty', slid, const [], yaw: 0.6);
    final boxes = packedBundle(slid, familyBundle);
    await _shoot(tester, '05_slide_family', slid, boxes, yaw: -0.5);
  });

  testWidgets('6 쏘렌토 7인승', (tester) async {
    final s7 = TrunkSpace.sorento7();
    final boxes = packedBundle(s7, '2인 미니멀 캠핑');
    await _shoot(tester, '06_sorento7', s7, boxes, yaw: 0.3);
  });

  testWidgets('8 순환 가림 (휠하우스 위에 걸친 짐 + 앞에 세운 판)', (tester) async {
    TrimBox at(String label, int i, double x, double y, double z) =>
        gearBox(label, i)
          ..x = x
          ..y = y
          ..z = z
          ..loadOrder = i + 1;
    final boxes = [
      at('스노우피크 쉘프컨테이너 50', 0, 0.15, 0, 0.15), // 63×41×27
      at('캠핑 더플백 60L', 1, 0.03, 0.30, 0.15), // 60×35×30, 휠하우스 위로 걸침
      at('접이식 테이블 (2인/60cm)', 2, 0.15, 0, 0.58)
        ..w = 0.60
        ..d = 0.05
        ..h = 0.45, // 세워 실음
    ];
    boxes[0].y = 0;
    boxes[1].y = math.max(boxes[0].top, sorento.leftWheelhouse.h);
    await _shoot(tester, '08_cyclic_occlusion', sorento, boxes,
        yaw: -0.99, pitch: 0.40, selected: boxes[1].id);
    await _shoot(tester, '08_cyclic_occlusion_step', sorento, boxes,
        yaw: -0.99, pitch: 0.40, step: 3);
  });

  testWidgets('7 구형 프리셋 (투싼, 테일게이트 모델 없음)', (tester) async {
    final tucson = TrunkSpace.tucson();
    final boxes = packedBundle(tucson, '2인 미니멀 캠핑');
    await _shoot(tester, '07_tucson', tucson, boxes, yaw: -0.4);
    await _shoot(tester, '07_tucson_empty', tucson, const []);
  });
}
