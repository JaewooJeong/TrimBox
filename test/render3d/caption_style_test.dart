// 캡션 형식: full 은 기존 두 줄 문구 그대로, compact 는 한 줄(공식 용량·2열 표시 생략).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/camera.dart';
import 'package:trimbox/render3d/trunk_painter_3d.dart';

int _cm(double m) => (m * 100).round();

/// 캡션이 쓰는 것과 같은 숫자 (TrunkSpace 에서 읽는다)
({int wIn, int wMax, int d, int hMin, int hMax}) _nums(TrunkSpace s) => (
      wIn: _cm(s.floorWidthBetweenWheelhouses),
      wMax: _cm(s.w),
      d: _cm(s.d),
      hMin: _cm(s.ceilingHeightAt(s.rearDepthAt(s.h))),
      hMax: _cm(s.h),
    );

void main() {
  group('captionText', () {
    test('compact: 한 줄, 같은 숫자, 공식 용량·2열 표시 없음', () {
      for (final space in [
        TrunkSpace.sorento(),
        TrunkSpace.sorento(seatSlide: 0.10),
        TrunkSpace.sorento7(seatSlide: 0.27),
      ]) {
        final n = _nums(space);
        expect(n.wIn, lessThan(n.wMax));
        expect(n.hMin, lessThan(n.hMax));
        final text = TrunkPainter3D.captionText(space, CaptionStyle.compact);
        expect(text,
            '${space.vehicleName} · ${n.wIn}~${n.wMax}×${n.d}×${n.hMin}~${n.hMax} cm');
        expect(text, isNot(contains('\n')));
        expect(text, isNot(contains('VDA')));
        expect(text, isNot(matches(RegExp(r'\dL'))));
        expect(text, isNot(contains('2열')));
        expect(text, isNot(contains('깊이')));
      }
    });

    test('full: 기존 문구 그대로 (공식 용량과 2열 위치 포함)', () {
      final space = TrunkSpace.sorento(seatSlide: 0.10);
      final n = _nums(space);
      final text = TrunkPainter3D.captionText(space, CaptionStyle.full);
      expect(
          text,
          '${space.vehicleName} · 폭 ${n.wIn}~${n.wMax} × 깊이 ${n.d} × 높이 ${n.hMin}~${n.hMax} cm'
          ' · ${space.officialVolumeLabel}');
      expect(text, contains('2열 +10cm'));
      expect(text, matches(RegExp(r'VDA \d+L')));
    });

    test('범위 양끝이 같으면 숫자 하나만 (휠하우스·테일게이트 모델 없는 커스텀)', () {
      const space = TrunkSpace(
        w: 1.00,
        d: 0.80,
        h: 0.50,
        leftWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
        rightWheelhouse: Wheelhouse(w: 0, d: 0, h: 0),
      );
      expect(TrunkPainter3D.captionText(space, CaptionStyle.compact),
          '커스텀 · 100×80×50 cm');
      expect(TrunkPainter3D.captionText(space, CaptionStyle.full),
          '커스텀 · 폭 100 × 깊이 80 × 높이 50 cm');
    });
  });

  group('페인터', () {
    TrimBox box(String id, {double z = 0.3}) => TrimBox(
        id: id,
        label: id,
        w: 0.4,
        d: 0.3,
        h: 0.3,
        x: 0.3,
        z: z,
        color: const Color(0xFFBAE1FF));

    testWidgets('compact 캡션은 좁은 폭·상태 알약과 함께 예외 없이 그려진다', (tester) async {
      final space = TrunkSpace.sorento(seatSlide: 0.27);
      for (final size in const [Size(390, 550), Size(120, 200), Size(1, 1)]) {
        for (final style in CaptionStyle.values) {
          final painter = TrunkPainter3D(
            space: space,
            boxes: [box('a'), box('out', z: space.d + 0.06)],
            camera: OrbitCamera.fitTrunk(space, size),
            tailgateBlockedIds: const {'a'},
            captionStyle: style,
            labelPolicy: LabelPolicy.compact,
          );
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), size);
          recorder.endRecording().dispose();
        }
      }
    });

    test('상태 알약 문구는 캡션 형식과 무관하다', () {
      final space = TrunkSpace.sorento();
      final (text, kind) =
          TrunkPainter3D.captionStatus(space, [box('a')], const {'a'});
      expect(text, '테일게이트 안 닫힘 · 1개 걸림');
      expect(kind, CaptionStatusKind.blocked);
    });
  });
}
