import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';

TrimBox _box(String id, {double z = 0.3}) => TrimBox(
    id: id,
    label: id,
    w: 0.4,
    d: 0.3,
    h: 0.3,
    x: 0.3,
    z: z,
    color: const Color(0xFFBAE1FF));

void main() {
  final space = TrunkSpace.sorento();

  test('다 실렸고 걸린 짐이 없으면 초록 "테일게이트 닫힘 OK"', () {
    final (text, kind) =
        TrunkPainter3D.captionStatus(space, [_box('a')], const {});
    expect(text, '테일게이트 닫힘 OK');
    expect(kind, CaptionStatusKind.ok);
  });

  test('트렁크 밖에 세워 둔 짐이 있으면 초록이 아니라 주황 "미적재 N개"', () {
    final boxes = [
      _box('a'),
      _box('out1', z: space.d + 0.06),
      _box('out2', z: space.d - 0.005), // LoadStats 와 같은 경계
    ];
    final (text, kind) = TrunkPainter3D.captionStatus(space, boxes, const {});
    expect(text, '미적재 2개 · 실은 짐은 테일게이트 닫힘 OK');
    expect(kind, CaptionStatusKind.unloaded);
  });

  test('하나도 못 실었으면 "실은 짐 없음"', () {
    final (text, kind) = TrunkPainter3D.captionStatus(
        space, [_box('out', z: space.d + 0.06)], const {});
    expect(text, '미적재 1개 · 실은 짐 없음');
    expect(kind, CaptionStatusKind.unloaded);
  });

  test('테일게이트에 걸린 짐이 있으면 (밖에 둔 짐이 있어도) 빨강이 우선', () {
    final boxes = [_box('a'), _box('out', z: space.d + 0.06)];
    final (text, kind) = TrunkPainter3D.captionStatus(space, boxes, {'a'});
    expect(text, '테일게이트 안 닫힘 · 1개 걸림');
    expect(kind, CaptionStatusKind.blocked);
  });
}
