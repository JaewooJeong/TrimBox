// 폰 라벨 정책(LabelPolicy.compact): 순서 배지는 전부, 이름 알약은 선택·문제 짐 + 큰 면
// compactLabelLimit 개까지만, 겹치는 알약은 그리지 않는다. 선택 논리는 순수 함수
// compactLabelIds 로, 그린 결과는 TrunkPainter3D.lastDrawnLabels 훅으로 검사한다.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/label_layout.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

import 'scene_fixtures.dart';

const _phone = Size(390, 550);

/// 휠하우스 사이 바닥에 3열 × 5줄 + 위에 얹은 1개 = 16개 (전부 보인다, 순서 1..16)
List<TrimBox> _grid16(TrunkSpace s) {
  final out = <TrimBox>[];
  var i = 0;
  const cols = 3, rows = 5;
  const bw = 0.32, bd = 0.18;
  final x0 = s.leftWheelhouse.w + 0.015;
  final xStep = (s.floorWidthBetweenWheelhouses - 0.03 - bw) / (cols - 1);
  final zStep = (s.d - 0.06 - bd) / (rows - 1);
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      out.add(TrimBox(
        id: 'g$i',
        label: '짐 $i 캠핑 장비 이름이 길다',
        w: bw,
        d: bd,
        h: 0.15 + 0.04 * ((r + c) % 4),
        x: x0 + c * xStep,
        z: 0.03 + r * zStep,
        color: campingColors[i % campingColors.length],
      )..loadOrder = i + 1);
      i++;
    }
  }
  final under = out[1];
  out.add(TrimBox(
    id: 'g$i',
    label: '위에 얹은 짐',
    w: 0.24,
    d: 0.14,
    h: 0.10,
    x: under.x + 0.04,
    y: under.h,
    z: under.z + 0.02,
    color: campingColors[i % campingColors.length],
  )..loadOrder = i + 1);
  return out;
}

/// 4인 가족 세트에 카탈로그 항목을 더해 16개를 자동 배치한 현실적인 장면
List<TrimBox> _packed16(TrunkSpace s) {
  final labels = [...gearBundleLabels(familyBundle)];
  for (final g in gearCatalog()) {
    if (labels.length >= 16) break;
    if (g.label == '커스텀' || labels.contains(g.label)) continue;
    labels.add(g.label);
  }
  return pack(s, gearBoxes(labels.take(16).toList()));
}

TrunkPainter3D _paint(
  TrunkSpace space,
  List<TrimBox> boxes, {
  required LabelPolicy policy,
  Size size = _phone,
  String? selected,
  String? dragging,
  Set<String> colliding = const {},
  Set<String> blocked = const {},
  int? step,
}) {
  final painter = TrunkPainter3D(
    space: space,
    boxes: boxes,
    camera: OrbitCamera.fitTrunk(space, size),
    selectedBoxId: selected,
    draggingBoxId: dragging,
    collidingBoxIds: colliding,
    tailgateBlockedIds: blocked,
    highlightLoadOrder: step,
    labelPolicy: policy,
  );
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
  return painter;
}

List<Rect> _pills(TrunkPainter3D p) =>
    [for (final l in p.lastDrawnLabels) if (l.pill != null) l.pill!];
List<Rect> _badges(TrunkPainter3D p) =>
    [for (final l in p.lastDrawnLabels) if (l.badge != null) l.badge!];
Set<String> _pillIds(TrunkPainter3D p) =>
    {for (final l in p.lastDrawnLabels) if (l.pill != null) l.boxId};

void _expectNoPairwiseOverlap(List<Rect> rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      expect(rects[i].overlaps(rects[j]), isFalse,
          reason: '알약 $i ${rects[i]} 와 $j ${rects[j]} 가 겹친다');
    }
  }
}

void main() {
  group('compactLabelIds (순수 논리)', () {
    final areas = <(String, double)>[
      ('a', 100),
      ('b', 900),
      ('c', 500),
      ('d', 900),
      ('e', 300),
      ('f', 700),
    ];

    test('선택·드래그·충돌·테일게이트 짐은 면적과 무관하게 항상 들어간다', () {
      final ids = compactLabelIds(
        areas: areas,
        selected: 'a',
        dragging: 'e',
        colliding: {'c'},
        blocked: {'a'},
        limit: 0,
      );
      expect(ids, {'a', 'c', 'e'});
    });

    test('그 밖의 짐은 면적이 큰 순서로 정확히 limit 개', () {
      final ids = compactLabelIds(areas: areas, limit: 3);
      expect(ids, {'b', 'd', 'f'});
      expect(compactLabelIds(areas: areas, limit: 1), {'b'});
      // 문제 짐은 limit 를 소비하지 않는다
      final withSel = compactLabelIds(areas: areas, selected: 'a', limit: 3);
      expect(withSel, {'a', 'b', 'd', 'f'});
    });

    test('면적이 같으면 먼저 그린 짐이 우선한다 (결정적)', () {
      final tie = <(String, double)>[
        ('p', 400),
        ('q', 400),
        ('r', 400),
        ('s', 400),
      ];
      expect(compactLabelIds(areas: tie, limit: 2), {'p', 'q'});
      expect(compactLabelIds(areas: tie, limit: 3), {'p', 'q', 'r'});
      // 순서를 바꾸면 결과도 그 순서를 따른다
      expect(compactLabelIds(areas: tie.reversed.toList(), limit: 2), {'s', 'r'});
    });

    test('빈 입력·limit 0·음수·초과는 안전하다', () {
      expect(compactLabelIds(areas: const [], limit: 3), isEmpty);
      expect(compactLabelIds(areas: const [], selected: 'x', limit: 3), isEmpty);
      expect(compactLabelIds(areas: areas, limit: 0), isEmpty);
      expect(compactLabelIds(areas: areas, limit: -1), isEmpty);
      expect(compactLabelIds(areas: areas, limit: 99).length, areas.length);
    });

    test('그리지 않은 짐 id 는 문제 짐이라도 넣지 않는다', () {
      final ids = compactLabelIds(
          areas: areas, selected: 'zzz', colliding: {'nope'}, limit: 1);
      expect(ids, {'b'});
    });

    test('입력 목록을 바꾸지 않는다', () {
      final copy = [...areas];
      compactLabelIds(areas: areas, limit: 2);
      expect(areas, copy);
    });
  });

  group('TrunkPainter3D compact 정책 (390×550, 16개 장면)', () {
    final sorento = TrunkSpace.sorento();

    testWidgets('알약 수 ≤ 문제 짐 + compactLabelLimit, 알약끼리 겹침 0, 폭 ≤ 120+12',
        (tester) async {
      for (final boxes in [_grid16(sorento), _packed16(sorento)]) {
        expect(boxes.length, greaterThanOrEqualTo(10));
        final problem = {boxes[0].id, boxes[2].id, boxes.last.id};
        final p = _paint(sorento, boxes,
            policy: LabelPolicy.compact,
            selected: boxes[0].id,
            colliding: {boxes[2].id},
            blocked: {boxes.last.id});
        final pills = _pills(p);
        final drawnProblem =
            p.lastDrawnLabels.where((l) => problem.contains(l.boxId)).length;
        expect(pills.length,
            lessThanOrEqualTo(drawnProblem + TrunkPainter3D.compactLabelLimit));
        _expectNoPairwiseOverlap(pills);
        for (final r in pills) {
          expect(r.width, lessThanOrEqualTo(TrunkPainter3D.compactPillMaxWidth + 12));
        }
      }
    });

    testWidgets('문제 짐이 없으면 알약은 정확히 compactLabelLimit 개 이하이고 all 보다 적다',
        (tester) async {
      final boxes = _grid16(sorento);
      final compact = _paint(sorento, boxes, policy: LabelPolicy.compact);
      final all = _paint(sorento, boxes, policy: LabelPolicy.all);
      expect(_pills(compact).length,
          lessThanOrEqualTo(TrunkPainter3D.compactLabelLimit));
      expect(_pills(compact), isNotEmpty);
      expect(_pills(all).length, greaterThan(_pills(compact).length));
    });

    testWidgets('순서 배지는 정책과 무관하게 보이는 짐마다 그린다', (tester) async {
      final boxes = _grid16(sorento);
      final compact = _paint(sorento, boxes, policy: LabelPolicy.compact);
      final all = _paint(sorento, boxes, policy: LabelPolicy.all);
      expect(_badges(compact).length, _badges(all).length);
      expect(_badges(compact).length, boxes.length);
      expect({for (final l in compact.lastDrawnLabels) l.boxId},
          {for (final b in boxes) b.id});
    });

    testWidgets('선택·드래그·충돌·걸림 짐은 작아도 알약을 얻는다 (큰 짐이 3개 넘게 있어도)',
        (tester) async {
      // 넓은 큰 짐 4개(2×2), 앞에 작고 낮은 짐 하나. 알약은 면 폭이 충분해야 들어가므로
      // 큰 짐은 폭도 넉넉하게 준다 (0.5 m ≈ 폰 폭에서 120px 이상).
      final big = [
        for (var i = 0; i < 4; i++)
          TrimBox(
            id: 'big$i',
            label: '큰 짐 $i',
            w: 0.50,
            d: 0.40,
            h: 0.40,
            x: 0.16 + (i % 2) * 0.54,
            z: 0.05 + (i ~/ 2) * 0.42,
            color: campingColors[i],
          )..loadOrder = i + 1,
      ];
      final small = TrimBox(
        id: 'small',
        label: '작은 선택 짐',
        w: 0.36,
        d: 0.12,
        h: 0.12,
        x: 0.50,
        z: 0.90,
        color: campingColors[5],
      )..loadOrder = 5;
      final boxes = [...big, small];
      for (final role in ['selected', 'dragging', 'colliding', 'blocked']) {
        final p = _paint(
          sorento,
          boxes,
          policy: LabelPolicy.compact,
          selected: role == 'selected' ? 'small' : null,
          dragging: role == 'dragging' ? 'small' : null,
          colliding: role == 'colliding' ? {'small'} : const {},
          blocked: role == 'blocked' ? {'small'} : const {},
        );
        expect(_pillIds(p), contains('small'), reason: role);
        expect(_pills(p).length,
            lessThanOrEqualTo(1 + TrunkPainter3D.compactLabelLimit));
        _expectNoPairwiseOverlap(_pills(p));
      }
      // 문제 짐이 아니면 작은 짐은 알약을 못 받는다 (큰 짐 4개 중 3개가 받는다)
      final none = _paint(sorento, boxes, policy: LabelPolicy.compact);
      expect(_pillIds(none), isNot(contains('small')));
      expect(_pills(none).length, TrunkPainter3D.compactLabelLimit,
          reason: '${none.lastDrawnLabels.map((l) => '${l.boxId}:${l.pill}')}');
    });

    testWidgets('스텝 뷰(highlightLoadOrder)에서도 두 정책 모두 순서 이후 짐은 숨긴다',
        (tester) async {
      final boxes = _grid16(sorento);
      for (final policy in LabelPolicy.values) {
        final p = _paint(sorento, boxes, policy: policy, step: 5);
        expect(_badges(p).length, 5, reason: '$policy');
        for (final l in p.lastDrawnLabels) {
          final order = boxes.firstWhere((b) => b.id == l.boxId).loadOrder!;
          expect(order, lessThanOrEqualTo(5));
        }
      }
    });

    testWidgets('showLabels=false 면 어느 정책이든 라벨을 그리지 않는다', (tester) async {
      final boxes = _grid16(sorento);
      for (final policy in LabelPolicy.values) {
        final painter = TrunkPainter3D(
          space: sorento,
          boxes: boxes,
          camera: OrbitCamera.fitTrunk(sorento, _phone),
          showLabels: false,
          labelPolicy: policy,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), _phone);
        recorder.endRecording().dispose();
        expect(painter.lastDrawnLabels, isEmpty);
      }
    });

    testWidgets('훅은 프레임마다 비운다', (tester) async {
      final boxes = _grid16(sorento);
      final painter = TrunkPainter3D(
        space: sorento,
        boxes: boxes,
        camera: OrbitCamera.fitTrunk(sorento, _phone),
        labelPolicy: LabelPolicy.compact,
      );
      for (var i = 0; i < 2; i++) {
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), _phone);
        recorder.endRecording().dispose();
      }
      expect(_badges(painter).length, boxes.length);
    });

    testWidgets('all 정책의 알약 폭 한도는 160+12 로 그대로', (tester) async {
      final boxes = _grid16(sorento);
      final p = _paint(sorento, boxes, policy: LabelPolicy.all, size: const Size(960, 640));
      expect(_pills(p), isNotEmpty);
      for (final r in _pills(p)) {
        expect(r.width, lessThanOrEqualTo(160 + 12));
      }
    });
  });
}
