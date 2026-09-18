// Scene / TrunkSpace / TrimBox JSON 직렬화 퍼즈: 왕복 동일성, 옛 형식, 손상 입력.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/scene.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/json_io.dart';

TrimBox randomBox(math.Random r, int i) => TrimBox(
      id: 'box-${i.toString().padLeft(3, '0')}',
      label: ['쿨러', 'tent "A"', '침낭\\n2', '', '🏕️ 의자'][r.nextInt(5)],
      w: (5 + r.nextInt(120)) / 100,
      d: (5 + r.nextInt(100)) / 100,
      h: (3 + r.nextInt(80)) / 100,
      x: r.nextInt(130) / 100,
      y: r.nextInt(70) / 100,
      z: r.nextInt(120) / 100,
      rotY: [0, 90, 180, 270][r.nextInt(4)],
      color: Color(0xFF000000 | r.nextInt(0xFFFFFF)),
      category: BoxCategory.values[r.nextInt(BoxCategory.values.length)],
      keepUpright: r.nextBool(),
      soft: r.nextBool(),
      compressibility: r.nextInt(50) / 100,
      squash: r.nextInt(3) == 0 ? r.nextInt(40) / 100 : 0,
      squashW: 0,
      squashD: r.nextInt(5) == 0 ? r.nextInt(30) / 100 : 0,
      weightKg: r.nextInt(400) / 10,
      accessPriority: r.nextBool(),
      shape: GearShape.values[r.nextInt(GearShape.values.length)],
    );

void expectSameBox(TrimBox a, TrimBox b) {
  expect(b.id, a.id);
  expect(b.label, a.label);
  for (final (x, y) in [
    (a.w, b.w), (a.d, b.d), (a.h, b.h), (a.x, b.x), (a.y, b.y), (a.z, b.z),
    (a.compressibility, b.compressibility), (a.squash, b.squash),
    (a.squashW, b.squashW), (a.squashD, b.squashD), (a.weightKg, b.weightKg),
  ]) {
    expect(y, closeTo(x, 1e-12));
  }
  expect(b.rotY, a.rotY);
  expect(b.color.toARGB32(), a.color.toARGB32());
  expect(b.category, a.category);
  expect(b.keepUpright, a.keepUpright);
  expect(b.soft, a.soft);
  expect(b.accessPriority, a.accessPriority);
  expect(b.shape, a.shape);
  expect(b.effectiveW, closeTo(a.effectiveW, 1e-12));
  expect(b.effectiveD, closeTo(a.effectiveD, 1e-12));
  expect(b.effectiveH, closeTo(a.effectiveH, 1e-12));
}

void main() {
  final spaces = <TrunkSpace>[
    for (final p in TrunkPreset.values)
      if (p.toTrunkSpace() != null) p.toTrunkSpace()!,
    TrunkSpace.sorento(seatSlide: 0.13),
    TrunkSpace.sorento7(seatSlide: 0.27),
    TrunkSpace.custom(w: 0.9, d: 0.8, h: 0.8),
  ];

  test('씬 JSON 왕복: 무작위 박스 300세트 × 모든 트렁크', () {
    final r = math.Random(42);
    for (var iter = 0; iter < 300; iter++) {
      final space = spaces[iter % spaces.length];
      final boxes = [for (var i = 0; i < r.nextInt(20); i++) randomBox(r, i)];
      final json = JsonIO.exportScene(Scene(space: space, boxes: boxes));
      final back = JsonIO.importScene(json);
      expect(back.boxes.length, boxes.length);
      for (var i = 0; i < boxes.length; i++) {
        expectSameBox(boxes[i], back.boxes[i]);
      }
      // 트렁크: 형상 함수가 같은 값을 내야 한다 (필드 비교 대신 동작 비교)
      final s2 = back.space;
      expect(s2.w, space.w);
      expect(s2.d, closeTo(space.d, 1e-12));
      expect(s2.h, space.h);
      expect(s2.seatSlide, closeTo(space.seatSlide, 1e-12));
      expect(s2.floorStartZ, closeTo(space.floorStartZ, 1e-12));
      expect(s2.leftWheelhouse.zStart, closeTo(space.leftWheelhouse.zStart, 1e-12));
      for (var k = 0; k < 20; k++) {
        final z = r.nextDouble() * space.d, y = r.nextDouble() * space.h;
        expect(s2.xMinAt(z, y), closeTo(space.xMinAt(z, y), 1e-12));
        expect(s2.ceilingHeightAt(z), closeTo(space.ceilingHeightAt(z), 1e-12));
        expect(s2.rearDepthAt(y), closeTo(space.rearDepthAt(y), 1e-12));
        expect(s2.frontDepthAt(y), closeTo(space.frontDepthAt(y), 1e-12));
      }
      expect(s2.usableVolume, closeTo(space.usableVolume, 1e-9));
      // 두 번째 왕복은 문자열까지 같아야 한다 (안정적인 직렬화)
      expect(JsonIO.exportScene(back), json);
    }
  });

  test('옛 형식: 새 필드가 하나도 없는 박스·트렁크도 읽힌다', () {
    final legacy = jsonEncode({
      'version': 1,
      'space': {
        'w': 1.08, 'd': 1.10, 'h': 0.78,
        'wheelhouse': {
          'left': {'w': 0.08, 'd': 0.48, 'h': 0.30},
          'right': {'w': 0.08, 'd': 0.48, 'h': 0.30},
        },
        'vehicleName': 'SORENTO 5인승',
      },
      'boxes': [
        {
          'id': 'box-001', 'label': '대형 아이스박스 (50L)',
          'size': {'w': 0.6, 'd': 0.4, 'h': 0.42},
          'pos': {'x': 0, 'y': 0, 'z': 0}, 'rotY': 0, 'color': 0xFF2244AA,
        },
      ],
    });
    final scene = JsonIO.importScene(legacy);
    expect(scene.space.hasTailgateModel, isFalse);
    expect(scene.space.seatSlide, 0);
    expect(scene.space.leftWheelhouse.zStart, 0);
    final b = scene.boxes.single;
    expect(b.soft, isFalse);
    expect(b.weightKg, 0);
    expect(b.shape, GearShape.box);
    expect(b.effectiveH, closeTo(0.42, 1e-12));
  });

  test('손상 입력은 FormatException 계열로 끝나고 다른 예외로 죽지 않는다', () {
    final good = JsonIO.exportScene(Scene(space: TrunkSpace.sorento(), boxes: [
      randomBox(math.Random(1), 0),
    ]));
    final bad = <String>[
      '', '   ', 'null', '[]', '{}', '{"space":{}}', '{"space":null,"boxes":[]}',
      good.substring(0, good.length ~/ 2),
      good.replaceFirst('"w"', '"ww"'),
      good.replaceFirst(RegExp(r'"h":\s*[0-9.]+'), '"h":"tall"'),
      '{"space":${jsonEncode(TrunkSpace.sorento().toJson())},"boxes":[{"id":1}]}',
      '{"space":${jsonEncode(TrunkSpace.sorento().toJson())},"boxes":"nope"}',
    ];
    for (final input in bad) {
      try {
        JsonIO.importScene(input);
      } on FormatException {
        // 기대한 실패
      } on TypeError {
        fail('TypeError 가 새어 나왔다 (FormatException 으로 감싸야 한다): '
            '${input.length > 60 ? input.substring(0, 60) : input}');
      } on NoSuchMethodError {
        fail('NoSuchMethodError 가 새어 나왔다: '
            '${input.length > 60 ? input.substring(0, 60) : input}');
      }
    }
  });

  test('알 수 없는 enum·음수·거대한 값도 읽을 때 죽지 않는다', () {
    final space = jsonEncode(TrunkSpace.sorento().toJson());
    final weird = '{"space":$space,"boxes":[{"id":"a","label":"x",'
        '"size":{"w":1e6,"d":0.0,"h":-1},"pos":{"x":-5,"y":-5,"z":1e9},'
        '"rotY":45,"color":-1,"category":99,"shape":"dodecahedron",'
        '"squash":5,"compress":-2,"weight":-10}]}';
    final scene = JsonIO.importScene(weird);
    final b = scene.boxes.single;
    expect(b.shape, GearShape.box);
    expect(b.effectiveH.isFinite, isTrue);
    expect(b.effectiveW.isFinite, isTrue);
  });
}
