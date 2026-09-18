import 'geometry.dart';
import 'vec3.dart';

/// 서로 겹치지 않는 축 정렬 상자들을 뒤→앞 순서로 정렬한다 (painter's algorithm).
///
/// 원리: 두 AABB를 가르는 축 정렬 평면이 있으면, 카메라와 같은 쪽에 있는
/// 상자는 다른 상자에 가려질 수 없으므로 나중에 그린다. 이 관계로
/// 위상 정렬하고, 순환(드물게 발생)은 카메라에서 먼 것을 먼저 그려 끊는다.
/// 겹치는 상자 쌍(충돌 상태)은 순서 제약을 두지 않는다.
List<int> sortBackToFront(List<Aabb> boxes, Vec3 camPos) =>
    DepthGraph(boxes, camPos).order();

/// 뒤→앞 제약 그래프. 순환을 찾아낼 수 있어서 호출부가 물체를 나눠 순환을 풀 수 있다
/// (`scene.dart` 의 `sceneDrawOrder`).
class DepthGraph {
  final List<Aabb> boxes;
  final Vec3 camPos;

  /// after[i] = i 다음에 그려야 하는 상자들, before[j] = j 보다 먼저 그려야 하는 상자들
  late final List<Set<int>> after;
  late final List<Set<int>> before;

  DepthGraph(this.boxes, this.camPos) {
    final n = boxes.length;
    after = List<Set<int>>.generate(n, (_) => <int>{});
    before = List<Set<int>>.generate(n, (_) => <int>{});
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final r = depthOrder(boxes[i], boxes[j], camPos);
        if (r == 0) continue;
        if (r < 0) {
          after[i].add(j);
          before[j].add(i);
        } else {
          after[j].add(i);
          before[i].add(j);
        }
      }
    }
  }

  /// 위상 정렬. 순환은 그 순환에 속한 상자 중 카메라에서 가장 먼 것을 먼저 그려 끊는다
  /// (순환 밖의 상자는 제약을 그대로 지킨다).
  List<int> order() {
    final n = boxes.length;
    if (n <= 1) return List<int>.generate(n, (i) => i);
    final indeg = [for (final b in before) b.length];
    final dist = [for (final b in boxes) (b.center - camPos).length];
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
        for (final i in _cycleAmong(done)) {
          if (pick == -1 || dist[i] > dist[pick]) pick = i;
        }
      }
      done[pick] = true;
      result.add(pick);
      for (final j in after[pick]) {
        if (!done[j]) indeg[j]--;
      }
    }
    return result;
  }

  /// 순환 하나 (그리는 순서대로: c[0] → c[1] → … → c[0]). 없으면 null.
  List<int>? findCycle() {
    final n = boxes.length;
    final indeg = [for (final b in before) b.length];
    final done = List<bool>.filled(n, false);
    final queue = <int>[
      for (var i = 0; i < n; i++)
        if (indeg[i] == 0) i
    ];
    var count = 0;
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      done[i] = true;
      count++;
      for (final j in after[i]) {
        if (--indeg[j] == 0) queue.add(j);
      }
    }
    if (count == n) return null;
    return _cycleAmong(done);
  }

  /// 아직 안 그린 상자들 사이의 순환. 남은 상자는 모두 남은 선행 상자가 있으므로
  /// 선행을 거슬러 올라가면 반드시 되돌아온다.
  List<int> _cycleAmong(List<bool> done) {
    final n = boxes.length;
    var cur = -1;
    // 위상 정렬이 막힌 상태: 남은 것 중 아무거나에서 시작
    for (var i = 0; i < n; i++) {
      if (!done[i]) {
        cur = i;
        break;
      }
    }
    final seenAt = <int, int>{};
    final path = <int>[];
    while (!seenAt.containsKey(cur)) {
      seenAt[cur] = path.length;
      path.add(cur);
      var next = -1;
      for (final p in before[cur]) {
        if (!done[p]) {
          next = p;
          break;
        }
      }
      if (next == -1) return [cur]; // 방어: 선행이 없으면 그냥 그린다
      cur = next;
    }
    // path 는 선행을 거슬러 올라간 순서 → 뒤집으면 그리는 순서
    return path.sublist(seenAt[cur]!).reversed.toList();
  }
}

/// -1: a를 먼저 그린다, 1: b를 먼저 그린다, 0: 제약 없음
///
/// 분리 평면이 여러 축에 있으면 모든 축의 답이 같을 때만 제약을 둔다.
/// 카메라가 어떤 분리 평면에서 a 쪽, 다른 평면에서 b 쪽에 있으면
/// 두 상자는 서로를 가릴 수 없으므로 순서를 강제할 이유가 없다
/// (강제하면 불필요한 순환이 생긴다).
int depthOrder(Aabb a, Aabb b, Vec3 cam, {double eps = 1e-4}) {
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
