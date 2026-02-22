import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/scene.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/models/trim_box.dart';

void main() {
  group('Scene', () {
    test('빈 씬 직렬화/역직렬화', () {
      final scene = Scene(space: TrunkSpace.tucson());
      final json = scene.toJson();
      final restored = Scene.fromJson(json);

      expect(restored.version, '1.0.0');
      expect(restored.boxes, isEmpty);
      expect(restored.space.w, 1.04);
    });

    test('박스 포함 씬 라운드트립', () {
      final boxes = [
        TrimBox(
          id: 'b1',
          label: 'Box 1',
          w: 0.4,
          d: 0.3,
          h: 0.3,
          x: 0.1,
          z: 0.2,
          color: const Color(0xFFFF0000),
        ),
        TrimBox(
          id: 'b2',
          label: 'Box 2',
          w: 0.2,
          d: 0.2,
          h: 0.5,
          x: 0.5,
          z: 0.5,
          rotY: 90,
          color: const Color(0xFF00FF00),
        ),
      ];
      final scene = Scene(space: TrunkSpace.tucson(), boxes: boxes);
      final json = scene.toJson();
      final restored = Scene.fromJson(json);

      expect(restored.boxes.length, 2);
      expect(restored.boxes[0].id, 'b1');
      expect(restored.boxes[1].rotY, 90);
      expect(restored.boxes[1].x, 0.5);
    });

    test('toJsonString/fromJsonString 일관성', () {
      final scene = Scene(
        space: TrunkSpace.tucson(),
        boxes: [
          TrimBox(
            id: 'b1',
            label: 'Test',
            w: 0.3,
            d: 0.3,
            h: 0.3,
            color: const Color(0xFFFF0000),
          ),
        ],
      );
      final jsonStr = scene.toJsonString();
      final restored = Scene.fromJsonString(jsonStr);

      expect(restored.boxes.length, 1);
      expect(restored.boxes[0].id, 'b1');
      expect(restored.space.w, scene.space.w);
    });

    test('기본 버전/그리드 값', () {
      final scene = Scene(space: TrunkSpace.tucson());
      expect(scene.version, '1.0.0');
      expect(scene.gridUnit, 0.10);
    });
  });
}
