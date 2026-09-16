import 'geometry.dart';
import 'vec3.dart';

/// 서로 겹치지 않는 축 정렬 상자들을 뒤→앞 순서로 정렬한다 (painter's algorithm).
///
/// 원리: 두 AABB를 가르는 축 정렬 평면이 있으면, 카메라와 같은 쪽에 있는
/// 상자는 다른 상자에 가려질 수 없으므로 나중에 그린다. 이 관계로
/// 위상 정렬하고, 순환(드물게 발생)은 카메라에서 먼 것을 먼저 그려 끊는다.
/// 겹치는 상자 쌍(충돌 상태)은 순서 제약을 두지 않는다.
List<int> sortBackToFront(List<Aabb> boxes, Vec3 camPos) {
  final n = boxes.length;
  if (n <= 1) return List<int>.generate(n, (i) => i);

  // before[i] = i 다음에 그려야 하는 상자들
  final after = List<Set<int>>.generate(n, (_) => <int>{});
  final indeg = List<int>.filled(n, 0);

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final r = _order(boxes[i], boxes[j], camPos);
      if (r == 0) continue;
      if (r < 0) {
        // i 먼저
        if (after[i].add(j)) indeg[j]++;
      } else {
        if (after[j].add(i)) indeg[i]++;
      }
    }
  }

  final dist = List<double>.generate(
      n, (i) => (boxes[i].center - camPos).length);
  final done = List<bool>.filled(n, false);
  final result = <int>[];

  while (result.length < n) {
    // 진입 차수 0 중 가장 먼 것부터
    var pick = -1;
    for (var i = 0; i < n; i++) {
      if (done[i] || indeg[i] != 0) continue;
      if (pick == -1 || dist[i] > dist[pick]) pick = i;
    }
    if (pick == -1) {
      // 순환: 남은 것 중 가장 먼 것을 강제로 선택
      for (var i = 0; i < n; i++) {
        if (done[i]) continue;
        if (pick == -1 || dist[i] > dist[pick]) pick = i;
      }
    }
    done[pick] = true;
    result.add(pick);
    for (final j in after[pick]) {
      indeg[j]--;
    }
  }
  return result;
}

/// -1: a를 먼저 그린다, 1: b를 먼저 그린다, 0: 제약 없음
///
/// 분리 평면이 여러 축에 있으면 모든 축의 답이 같을 때만 제약을 둔다.
/// 카메라가 어떤 분리 평면에서 a 쪽, 다른 평면에서 b 쪽에 있으면
/// 두 상자는 서로를 가릴 수 없으므로 순서를 강제할 이유가 없다
/// (강제하면 불필요한 순환이 생긴다).
int _order(Aabb a, Aabb b, Vec3 cam, {double eps = 1e-4}) {
  var verdict = 0;
  for (var axis = 0; axis < 3; axis++) {
    final c = cam[axis];
    int r;
    if (a.maxOn(axis) <= b.minOn(axis) + eps) {
      // a | b 순으로 놓임. 카메라가 b 쪽이면 b가 앞 → a 먼저
      final p = (a.maxOn(axis) + b.minOn(axis)) / 2;
      r = c >= p ? -1 : 1;
    } else if (b.maxOn(axis) <= a.minOn(axis) + eps) {
      final p = (b.maxOn(axis) + a.minOn(axis)) / 2;
      r = c >= p ? 1 : -1;
    } else {
      continue;
    }
    if (verdict == 0) {
      verdict = r;
    } else if (verdict != r) {
      return 0;
    }
  }
  return verdict;
}
