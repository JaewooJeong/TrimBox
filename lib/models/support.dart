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
      add(o.x, o.z, o.x + o.effectiveW, o.z + o.effectiveD, o.y + o.h);
    }
    final lw = space.leftWheelhouse;
    if (lw.w > 0 && lw.d > 0 && lw.h > 0) add(0, 0, lw.w, lw.d, lw.h);
    final rw = space.rightWheelhouse;
    if (rw.w > 0 && rw.d > 0 && rw.h > 0) {
      add(space.w - rw.w, 0, space.w, rw.d, rw.h);
    }
    return out;
  }

  /// 높이별 합산 지지 면적. 키 = 대표 높이.
  static Map<double, double> _groupByLevel(
      List<({double topY, double area})> supports) {
    final groups = <double, double>{};
    for (final s in supports) {
      double? key;
      for (final h in groups.keys) {
        if ((s.topY - h).abs() <= heightTol) {
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
    final groups = _groupByLevel(_supports(box, others, space));
    final levels = <double>[0.0];
    for (final e in groups.entries) {
      if (e.key > heightTol && e.value >= area * minRatio - 1e-9) {
        levels.add(e.key);
      }
    }
    levels.sort();
    return levels;
  }

  /// 현재 box.y 에 가장 가까운 유효 층 (드래그 중 점프 방지용)
  static double nearestLevel(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    double best = 0;
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

  /// 가장 높은 유효 층
  static double highestLevel(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) =>
      validLevels(box, others, space).last;

  /// 높이 [y]에서 박스 바닥면이 지지되는 면적 비율 (0..1).
  /// 바닥(y ≈ 0)은 1.0 으로 본다.
  static double supportRatio(
    TrimBox box,
    double y,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) {
    if (y <= heightTol) return 1.0;
    final area = box.effectiveW * box.effectiveD;
    if (area <= 0) return 0;
    var sum = 0.0;
    for (final s in _supports(box, others, space)) {
      if ((s.topY - y).abs() <= heightTol) sum += s.area;
    }
    return (sum / area).clamp(0.0, 1.0);
  }

  /// 박스가 현재 y에서 물리적으로 지지되는가
  static bool isSupported(
    TrimBox box,
    Iterable<TrimBox> others,
    TrunkSpace space,
  ) =>
      supportRatio(box, box.y, others, space) >= minRatio - 1e-9;

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
        final y = highestLevel(box, below, space);
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
