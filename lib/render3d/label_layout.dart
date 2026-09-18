import 'dart:ui';

/// 라벨 묶음([순서 배지][라벨 알약])을 놓을 자리
class LabelSpot {
  final Rect rect;

  /// false 면 자리가 없어 배지만 그린다
  final bool withPill;

  /// 빈 자리를 못 찾아 이웃과 겹친 채 원래 자리에 놓았는가
  final bool overlapping;

  const LabelSpot(this.rect, {required this.withPill, this.overlapping = false});
}

const double labelGroupHeight = 22.0;

/// 면의 화면 범위 [face] 안, 중심 [centre] 근처에 라벨 묶음을 놓는다.
/// 먼저 놓인 이웃의 묶음([placed])과 겹치면 위아래로 비켜 보고, 그래도 겹치면 라벨을
/// 떼고 배지만 남긴다. 그래도 안 되면 원래 자리 (라벨을 아예 숨기지는 않는다).
/// 놓을 것이 없으면(배지도 라벨도 없음) null.
LabelSpot? placeLabelGroup({
  required Rect face,
  required Offset centre,
  required double badgeWidth,
  required double? pillWidth,
  required List<Rect> placed,
}) {
  Rect at(double width, double y) {
    var left = centre.dx - width / 2;
    if (width <= face.width - 4) {
      left = left.clamp(face.left + 2, face.right - width - 2).toDouble();
    }
    return Rect.fromLTWH(left, y - labelGroupHeight / 2, width, labelGroupHeight);
  }

  bool free(Rect r) => !placed.any((p) => p.inflate(2).overlaps(r));

  final ys = <double>[
    centre.dy,
    for (final dy in const [-18.0, 18.0, -34.0, 34.0])
      if (centre.dy + dy - labelGroupHeight / 2 >= face.top + 2 &&
          centre.dy + dy + labelGroupHeight / 2 <= face.bottom - 2)
        centre.dy + dy,
  ];
  final full = badgeWidth + (pillWidth ?? 0);
  if (full <= 0) return null;
  for (final width in [full, if (pillWidth != null && badgeWidth > 0) badgeWidth]) {
    for (final y in ys) {
      final r = at(width, y);
      if (free(r)) return LabelSpot(r, withPill: width == full && pillWidth != null);
    }
  }
  return LabelSpot(at(full, centre.dy),
      withPill: pillWidth != null, overlapping: true);
}
