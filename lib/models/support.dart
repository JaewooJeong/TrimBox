import 'dart:math' as math;

import 'trim_box.dart';
import 'trunk_space.dart';

/// 적층(지지) 규칙 — 화면 드래그, 중력 정착, 자동배치, 테스트가 모두 이 하나를 쓴다.
///
/// 규칙: 박스 바닥면과 XZ로 겹치는 지지면(다른 박스 윗면, 휠하우스 윗면)을
/// 높이별로 묶어 면적을 합산하고, 합산 지지 면적이 바닥면의 [minRatio] 이상인
/// 높이만 유효한 층으로 본다. 바닥(0)은 항상 유효하다.
class SupportRule {
  /// 같은 층으로 묶는 높이 오차 (1.5cm)
  static const double heightTol = 0.015;

  /// 연질 짐이 처져서 같이 받쳐지는 높이 차 (5cm). 침낭·가방은 높이가 조금 다른
  /// 받침(예: 28cm 가방과 30cm 휠하우스) 위에 걸쳐 놓이면 낮은 쪽으로 처져 닿는다.
  static const double softSagTol = 0.05;

  /// [box] 를 놓을 때 아래쪽으로 허용하는 높이 차
  static double _downTol(TrimBox box) => box.soft ? softSagTol : heightTol;

  /// 최소 지지 면적 비율
  static const double minRatio = 0.5;

  /// 박스 footprint에 대한 (지지면 높이, 겹침 면적) 목록
  static List<({double topY, double area})> _supports(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    final bx1 = box.x, bx2 = box.x + box.effectiveW;
    final bz1 = box.z, bz2 = box.z + box.effectiveD;
    final out = <({double topY, double area})>[];

    void add(double x1, double z1, double x2, double z2, double top) {
      final ox = math.min(bx2, x2) - math.max(bx1, x1);
      final oz = math.min(bz2, z2) - math.max(bz1, z1);
      if (ox > 1e-6 && oz > 1e-6) out.add((topY: top, area: ox * oz));
    }

    for (final o in others) {
      if (o.id == box.id) continue;
      add(o.x, o.z, o.x + o.effectiveW, o.z + o.effectiveD, o.top);
    }
    final lw = space.leftWheelhouse;
    if (lw.w > 0 && lw.d > 0 && lw.h > 0) {
      add(0, lw.zStart, lw.w, lw.zEnd, lw.h);
    }
    final rw = space.rightWheelhouse;
    if (rw.w > 0 && rw.d > 0 && rw.h > 0) {
      add(space.w - rw.w, rw.zStart, space.w, rw.zEnd, rw.h);
    }
    return out;
  }

  /// 높이별 합산 지지 면적. 키 = 대표 높이.
  /// 높이별 합산 지지 면적. 키 = 그 층에서 가장 높은 받침의 높이 (짐은 가장 높은
  /// 받침에 얹히고, [downTol] 안에 있는 낮은 받침도 함께 받친다).
  static Map<double, double> _groupByLevel(
      List<({double topY, double area})> supports, double downTol) {
    final sorted = List<({double topY, double area})>.from(supports)
      ..sort((a, b) => b.topY.compareTo(a.topY));
    final groups = <double, double>{};
    for (final s in sorted) {
      double? key;
      for (final h in groups.keys) {
        if (s.topY <= h + 1e-9 && h - s.topY <= downTol) {
          key = h;
          break;
        }
      }
      if (key == null) {
        groups[s.topY] = s.area;
      } else {
        groups[key] = groups[key]! + s.area;
      }
    }
    return groups;
  }

  /// 유효한 지지 층 목록 (바닥 0 포함, 오름차순).
  /// [others]에는 지지 후보로 볼 박스만 넘긴다 (예: 중력 정착 시 아래 박스만).
  static List<double> validLevels(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    final area = box.effectiveW * box.effectiveD;
    final groups = _groupByLevel(_supports(box, others, space), _downTol(box));
    // 바닥은 footprint 의 절반 이상이 실제 바닥(z ≥ floorStartZ) 위에 있을 때만 유효.
    // 2열 슬라이드 빈틈 위에 통째로 놓인 작은 짐은 유효한 층이 없을 수 있다 (빈 목록).
    final levels = <double>[
      if (floorSupportRatio(box, space) >= minRatio - 1e-9 &&
          !intersectsWheelhouseAt(box, 0.0, space))
        0.0,
    ];
    for (final e in groups.entries) {
      if (e.key > heightTol &&
          e.value >= area * minRatio - 1e-9 &&
          !intersectsWheelhouseAt(box, e.key, space)) {
        levels.add(e.key);
      }
    }
    levels.sort();
    return levels;
  }

  /// 박스를 높이 [y] 에 두면 휠하우스 덩어리 안으로 들어가는가. 바닥면의 절반이 바닥 위여도
  /// 나머지가 휠하우스에 걸치면 그 층은 유효하지 않다 — 삭제·드래그 뒤 중력 정착이 짐을
  /// 휠하우스 속으로 떨어뜨리지 않게 (CollisionDetector 의 휠하우스 판정과 같은 부피).
  static bool intersectsWheelhouseAt(TrimBox box, double y, TrunkSpace space) {
    const t = 0.0005;
    final top = y + box.effectiveH;
    bool hit(double x1, double z1, double x2, double z2, double h) {
      if (h <= 0 || x2 - x1 <= 0 || z2 - z1 <= 0) return false;
      return box.x < x2 - t &&
          box.x + box.effectiveW > x1 + t &&
          box.z < z2 - t &&
          box.z + box.effectiveD > z1 + t &&
          y < h - t &&
          top > t;
    }

    final lw = space.leftWheelhouse;
    final rw = space.rightWheelhouse;
    return hit(0, lw.zStart, lw.w, lw.zEnd, lw.h) ||
        hit(space.w - rw.w, rw.zStart, space.w, rw.zEnd, rw.h);
  }

  /// 박스 바닥면 중 실제 바닥(2열 슬라이드 빈틈 뒤쪽) 위에 있는 비율 (0..1)
  static double floorSupportRatio(TrimBox box, TrunkSpace space) {
    final gap = space.floorStartZ;
    final d = box.effectiveD;
    if (gap <= 0 || d <= 0) return 1.0;
    final onFloor = (box.z + d) - math.max(box.z, gap);
    return (onFloor / d).clamp(0.0, 1.0);
  }

  /// 받쳐 줄 층이 없을 때 짐을 두는 높이: 휠하우스 덩어리를 뚫지 않는 가장 낮은 높이
  /// (바닥, 아니면 휠하우스 윗면). 미지지 상태이지만 충돌은 아니다.
  static double restLevelWithoutSupport(TrimBox box, TrunkSpace space) {
    final candidates = <double>[
      0.0,
      if (space.leftWheelhouse.h > 0) space.leftWheelhouse.h,
      if (space.rightWheelhouse.h > 0) space.rightWheelhouse.h,
    ]..sort();
    for (final y in candidates) {
      if (!intersectsWheelhouseAt(box, y, space)) return y;
    }
    return candidates.last;
  }

  /// 발밑(footprint 가 겹치고 윗면이 현재 높이 이하인 짐·휠하우스) 중 가장 높은 윗면.
  /// 아무것도 없으면 휠하우스를 뚫지 않는 바닥 높이.
  static double restOnWhateverIsBelow(
      TrimBox box, Iterable<TrimBox> all, TrunkSpace space) {
    const t = 0.0005;
    var y = restLevelWithoutSupport(box, space);
    for (final o in all) {
      if (o.id == box.id) continue;
      if (o.top > box.y + 1e-9) continue;
      final overlap = box.x < o.x + o.effectiveW - t &&
          box.x + box.effectiveW > o.x + t &&
          box.z < o.z + o.effectiveD - t &&
          box.z + box.effectiveD > o.z + t;
      if (overlap) y = math.max(y, o.top);
    }
    return y;
  }

  /// 현재 box.y 에 가장 가까운 유효 층 (드래그 중 점프 방지용)
  static double nearestLevel(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    double best = restLevelWithoutSupport(box, space);
    double bestDist = double.infinity;
    for (final level in validLevels(box, others, space)) {
      final dist = (level - box.y).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = level;
      }
    }
    return best;
  }

  /// 가장 높은 유효 층. 유효한 층이 없으면(빈틈 위) 바닥 높이 0 을 돌려준다 —
  /// 그 상태는 [isSupported] 가 false 로 알려 준다.
  static double highestLevel(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    final levels = validLevels(box, others, space);
    return levels.isEmpty ? restLevelWithoutSupport(box, space) : levels.last;
  }

  /// 높이 [y]에서 박스 바닥면이 지지되는 면적 비율 (0..1).
  /// 바닥(y ≈ 0)은 1.0 으로 본다.
  static double supportRatio(
    TrimBox box,
    double y,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    if (y <= heightTol) return floorSupportRatio(box, space);
    final area = box.effectiveW * box.effectiveD;
    if (area <= 0) return 0;
    var sum = 0.0;
    for (final s in _supports(box, others, space)) {
      if (s.topY <= y + heightTol && y - s.topY <= _downTol(box)) sum += s.area;
    }
    return (sum / area).clamp(0.0, 1.0);
  }

  /// 높이 [y]에서 박스 바닥면을 받치는 다른 박스들 (휠하우스·바닥 제외)
  static List<TrimBox> supportersAt(
    TrimBox box,
    double y,
    Iterable<TrimBox> others,
  ) {
    final bx1 = box.x, bx2 = box.x + box.effectiveW;
    final bz1 = box.z, bz2 = box.z + box.effectiveD;
    final out = <TrimBox>[];
    for (final o in others) {
      if (o.id == box.id) continue;
      if (o.top > y + heightTol || y - o.top > _downTol(box)) continue;
      final ox = math.min(bx2, o.x + o.effectiveW) - math.max(bx1, o.x);
      final oz = math.min(bz2, o.z + o.effectiveD) - math.max(bz1, o.z);
      if (ox > 1e-6 && oz > 1e-6) out.add(o);
    }
    return out;
  }

  /// 박스가 현재 y에서 물리적으로 지지되는가
  static bool isSupported(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) =>
      supportRatio(box, box.y, others, space) >= minRatio - 1e-9;

  /// [box] 를 높이 [y] 에 놓으면 다른 박스와 겹치는가 (0.5mm 허용)
  static bool _overlapsAnyAt(TrimBox box, double y, Iterable<TrimBox> all) {
    const t = 0.0005;
    final top = y + box.effectiveH;
    for (final o in all) {
      if (o.id == box.id) continue;
      if (box.x < o.x + o.effectiveW - t &&
          box.x + box.effectiveW > o.x + t &&
          box.z < o.z + o.effectiveD - t &&
          box.z + box.effectiveD > o.z + t &&
          y < o.top - t &&
          top > o.y + t) {
        return true;
      }
    }
    return false;
  }

  /// 중력 정착: 아래층부터 차례로 각 박스를 "아래에 있는 박스들" 위의
  /// 가장 높은 유효 층으로 내린다. 다단 붕괴를 위해 반복한다.
  /// 반환값: 하나라도 위치가 바뀌었는지.
  static bool settle(List<TrimBox> boxes, TrunkSpace space,
      {int maxIterations = 10}) {
    var anyChanged = false;
    for (var iter = 0; iter < maxIterations; iter++) {
      var changed = false;
      final sorted = List<TrimBox>.from(boxes)
        ..sort((a, b) => a.y.compareTo(b.y));
      for (var i = 0; i < sorted.length; i++) {
        final box = sorted[i];
        final below = sorted.sublist(0, i);
        // 가장 높은 유효 층부터, 다른 짐과 겹치지 않는 첫 층. 지지 면적만 보면
        // 옆의 더 높은 짐을 뚫고 내려가는 층을 고를 수 있다.
        var levels = validLevels(box, below, space).reversed.toList();
        // 받쳐 줄 곳이 없으면(2열 빈틈 위, 휠하우스에 반만 걸침) 휠하우스를 뚫지 않는 가장
        // 낮은 높이까지 내려간다 — 미지지로 남지만 충돌은 만들지 않는다
        if (levels.isEmpty) levels = [restLevelWithoutSupport(box, space)];
        double? y;
        for (final level in levels) {
          if (!_overlapsAnyAt(box, level, boxes)) {
            y = level;
            break;
          }
        }
        // 겹치지 않는 유효 층이 없다(내려앉을 자리를 다른 짐이 먼저 차지함): 발밑에 있는 가장
        // 높은 것 위에 얹는다 — 지지 면적은 모자라도(미지지, isSupported 가 알린다) 허공에
        // 뜨지는 않는다. 올라가는 일은 없다.
        if (y == null) {
          final rest = restOnWhateverIsBelow(box, boxes, space);
          if (rest > box.y + 1e-9) continue; // 얹을 곳이 지금보다 높으면 그대로 둔다
          y = rest;
        }
        if ((box.y - y).abs() > 1e-6) {
          box.y = y;
          changed = true;
        }
      }
      if (!changed) break;
      anyChanged = true;
    }
    return anyChanged;
  }
}
