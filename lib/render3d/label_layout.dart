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
  bool sideways = false,
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
  // sideways: 배지만 남았을 때는 좌우로도 비켜 본다 (겹친 두 배지 중 하나가 40% 가려지는 것을 막는다)
  final dxs = <double>[0.0, if (sideways) ...const [-18.0, 18.0, -30.0, 30.0]];
  for (final width in [full, if (pillWidth != null && badgeWidth > 0) badgeWidth]) {
    for (final y in ys) {
      for (final dx in dxs) {
        final r = at(width, y).shift(Offset(dx, 0));
        if (dx != 0 && (r.left < face.left - 4 || r.right > face.right + 4)) continue;
        if (free(r)) return LabelSpot(r, withPill: width == full && pillWidth != null);
      }
    }
  }
  return LabelSpot(at(full, centre.dy),
      withPill: pillWidth != null, overlapping: true);
}

/// 폰(compact) 라벨 정책에서 이름 알약을 붙일 짐 id 집합.
///
/// [areas] 는 이 프레임에 라벨을 그릴 짐을 그리는 순서대로 (id, 화면 투영 면적 px²)로 준
/// 것이다. 선택·드래그 중([selected]·[dragging])·충돌([colliding])·테일게이트에 걸린
/// ([blocked]) 짐은 항상 들어가고, 그 밖의 짐은 면적이 큰 순서로 [limit]개까지 들어간다.
/// 면적이 같으면 먼저 그린 짐이 우선한다 (결정적). [areas] 에 없는 id 는 넣지 않는다.
Set<String> compactLabelIds({
  required List<(String, double)> areas,
  String? selected,
  String? dragging,
  Set<String> colliding = const {},
  Set<String> blocked = const {},
  required int limit,
}) {
  final ids = <String>{};
  final rest = <int>[];
  for (var i = 0; i < areas.length; i++) {
    final id = areas[i].$1;
    if (id == selected ||
        id == dragging ||
        colliding.contains(id) ||
        blocked.contains(id)) {
      ids.add(id);
    } else {
      rest.add(i);
    }
  }
  rest.sort((a, b) {
    final byArea = areas[b].$2.compareTo(areas[a].$2);
    return byArea != 0 ? byArea : a.compareTo(b);
  });
  for (final i in rest.take(limit < 0 ? 0 : limit)) {
    ids.add(areas[i].$1);
  }
  return ids;
}
