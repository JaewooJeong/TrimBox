import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/scene.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/scene_migration.dart';

Map<String, dynamic> _rawBox(String id, String label,
        {Map<String, dynamic> extra = const {}}) =>
    {
      'id': id,
      'label': label,
      'size': {'w': 0.6, 'd': 0.4, 'h': 0.42},
      'pos': {'x': 0, 'y': 0, 'z': 0},
      'rotY': 0,
      'color': 0xFFBAE1FF,
      ...extra,
    };

String _sceneJson(List<Map<String, dynamic>> boxes) => json.encode({
      'version': '1.0.0',
      'space': TrunkSpace.sorento().toJson(),
      'boxes': boxes,
    });

void main() {
  test('물리 필드가 없는 장비 DB 짐은 채우고, 직접 입력·이미 채워진 짐은 그대로 둔다', () {
    final raw = _sceneJson([
      _rawBox('box-001', '대형 아이스박스 (50L)'),
      _rawBox('box-002', '일반 침낭 (3계절)'),
      _rawBox('box-003', '내가 만든 박스'),
      _rawBox('box-004', '대형 아이스박스 (50L)', extra: {'weight': 1.5}),
    ]);
    final scene = Scene.fromJsonString(raw);
    expect(backfillGearPhysics(scene, raw), 2);

    final cooler = scene.boxes[0];
    expect(cooler.weightKg, greaterThan(0));
    expect(cooler.keepUpright, isTrue);
    expect(cooler.accessPriority, isTrue);
    final bag = scene.boxes[1];
    expect(bag.soft, isTrue);
    expect(bag.compressibility, greaterThan(0));

    expect(scene.boxes[2].weightKg, 0, reason: '직접 입력한 박스');
    expect(scene.boxes[3].weightKg, 1.5, reason: '이미 값이 있으면 덮어쓰지 않는다');
  });

  test('두 번 돌려도 같고, JSON 이 이상해도 예외 없이 0', () {
    final raw = _sceneJson([_rawBox('box-001', '대형 아이스박스 (50L)')]);
    final scene = Scene.fromJsonString(raw);
    backfillGearPhysics(scene, raw);
    final saved = scene.toJsonString();
    final again = Scene.fromJsonString(saved);
    expect(backfillGearPhysics(again, saved), 0);
    expect(again.boxes.single.weightKg, scene.boxes.single.weightKg);
    expect(backfillGearPhysics(scene, '{not json'), 0);
    expect(backfillGearPhysics(scene, '[]'), 0);
  });
}
