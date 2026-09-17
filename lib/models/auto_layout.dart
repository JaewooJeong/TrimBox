import 'dart:math' as math;

import '../utils/collision.dart';
import 'support.dart';
import 'trim_box.dart';
import 'trunk_space.dart';

/// 자동 배치 전략 (정렬 순서와 점수 가중치가 다르다)
enum LayoutStrategy {
  balanced, // 부피 큰 것부터, 낮고 깊게
  maxUtilization, // 긴 것부터, 벽·이웃에 붙여 빈틈 최소화
  easyAccess, // 작은 짐은 테일게이트 쪽으로
}

extension LayoutStrategyExt on LayoutStrategy {
  String get label => switch (this) {
        LayoutStrategy.balanced => '균형 배치',
        LayoutStrategy.maxUtilization => '최대 적재',
        LayoutStrategy.easyAccess => '접근 우선',
      };
}

/// 한 박스의 배치 결과. [w], [d], [h]는 배치된 방향의 치수(눕히기 포함)이며
/// 적용 시 rotY 는 0 으로 둔다.
class BoxPlacement {
  final TrimBox box;
  final double x;
  final double y;
  final double z;
  final double w;
  final double d;
  final double h;
  final int loadOrder; // 1 = 가장 먼저 싣는 짐 (가장 깊숙이·아래)

  const BoxPlacement({
    required this.box,
    required this.x,
    required this.y,
    required this.z,
    required this.w,
    required this.d,
    required this.h,
    required this.loadOrder,
  });

  /// 원래 치수 그대로가 아니면(90° 회전 또는 눕힘) true
  bool get rotated =>
      (w - box.w).abs() > 1e-9 ||
      (d - box.d).abs() > 1e-9 ||
      (h - box.h).abs() > 1e-9;

  /// 높이가 바뀌었으면 눕힌 것
  bool get laidFlat => (h - box.h).abs() > 1e-9;

  /// 이 배치를 실제 박스에 적용
  void applyTo(TrimBox target) {
    target
      ..w = w
      ..d = d
      ..h = h
      ..rotY = 0
      ..x = x
      ..y = y
      ..z = z
      ..loadOrder = loadOrder;
  }
}

/// 배치 결과
class AutoLayoutResult {
  final List<BoxPlacement> placements;
  final double utilizationPercent;
  final bool allBoxesFit;
  final List<TrimBox> unfitBoxes;
  final Map<String, String> unfitReasons; // box.id → 사유
  final LayoutStrategy strategy;

  const AutoLayoutResult({
    required this.placements,
    required this.utilizationPercent,
    required this.allBoxesFit,
    required this.unfitBoxes,
    required this.strategy,
    this.unfitReasons = const {},
  });

  int get placedCount => placements.length;
  int get totalCount => placements.length + unfitBoxes.length;
}

class _Orientation {
  final double w, d, h;
  const _Orientation(this.w, this.d, this.h);
}

class _Candidate {
  final double x, y, z;
  final _Orientation o;
  final double score;
  const _Candidate(this.x, this.y, this.z, this.o, this.score);
}

/// 극점(extreme point) 휴리스틱 기반 3D 적재.
///
/// 원칙
/// - 후보 위치는 이미 놓인 박스·휠하우스의 모서리와 벽 경계에서만 만든다.
/// - 후보의 높이는 [SupportRule]로 "떨어뜨려" 정한다 (공중부양 없음).
/// - 유효성은 [CollisionDetector] 하나로만 판단한다 (화면과 같은 규칙).
/// - 결과는 마지막에 다시 검증하고, 검증에 실패한 배치는 미적재로 돌린다.
class AutoLayoutEngine {
  /// 좌표 격자 (1cm). 후보 좌표는 이 격자로 올림해 화면 스냅과 어긋나지 않게 한다.
  static const double grid = 0.01;

  /// [restarts]: 기본 정렬들로 전부 못 넣었을 때 추가로 시도할 무작위 순서 수.
  /// [budget]: 추가 시도에 쓸 최대 시간. [seed]: 재현용 난수 시드.
  static AutoLayoutResult computeLayout(
    TrunkSpace trunk,
    List<TrimBox> boxes, {
    LayoutStrategy strategy = LayoutStrategy.balanced,
    int restarts = 0,
    Duration budget = const Duration(milliseconds: 800),
    int seed = 1234,
  }) {
    if (boxes.isEmpty) {
      return AutoLayoutResult(
        placements: const [],
        utilizationPercent: 0,
        allBoxesFit: true,
        unfitBoxes: const [],
        strategy: strategy,
      );
    }

    // 정렬 순서 몇 가지를 모두 시도해 (배치 개수 ↓, 적재율 ↓) 가장 좋은 결과를 쓴다.
    final sw = Stopwatch()..start();
    AutoLayoutResult? best;
    void consider(AutoLayoutResult r) {
      if (best == null ||
          r.placedCount > best!.placedCount ||
          (r.placedCount == best!.placedCount &&
              r.utilizationPercent > best!.utilizationPercent + 1e-9)) {
        best = r;
      }
    }

    for (final order in _sortVariants(boxes, strategy)) {
      consider(_pack(trunk, order, boxes, strategy));
      if (best!.allBoxesFit) return best!;
    }

    // 못 넣은 박스를 맨 앞에 두고 다시 (가장 효과가 큰 재시도)
    for (var round = 0; round < 2 && !best!.allBoxesFit; round++) {
      final unfitIds = best!.unfitBoxes.map((b) => b.id).toSet();
      final base = _sortVariants(boxes, strategy).first;
      final order = [
        ...base.where((b) => unfitIds.contains(b.id)),
        ...base.where((b) => !unfitIds.contains(b.id)),
      ];
      consider(_pack(trunk, order, boxes, strategy));
    }

    // 무작위 순서 재시도 (시간 예산 안에서)
    final rnd = math.Random(seed);
    for (var i = 0;
        i < restarts && !best!.allBoxesFit && sw.elapsed < budget;
        i++) {
      // 부피에 잡음을 섞은 내림차순: 큰 것 먼저라는 원칙은 대체로 유지
      final keyed = {
        for (final b in boxes) b.id: _vol(b) * (0.6 + rnd.nextDouble() * 0.8),
      };
      final order = List<TrimBox>.from(boxes)
        ..sort((a, b) => keyed[b.id]!.compareTo(keyed[a.id]!));
      consider(_pack(trunk, order, boxes, strategy));
    }
    return best!;
  }

  static AutoLayoutResult _pack(
    TrunkSpace trunk,
    List<TrimBox> sorted,
    List<TrimBox> boxes,
    LayoutStrategy strategy,
  ) {
    final detector = CollisionDetector(trunk);
    final placed = <TrimBox>[]; // 배치된 사본 (rotY = 0, 치수 = 배치 방향)
    final placedOf = <String, TrimBox>{};
    final unfit = <TrimBox>[];

    void tryPlace(TrimBox box) {
      final c = _bestCandidate(trunk, detector, placed, box, strategy, boxes);
      if (c == null) {
        unfit.add(box);
        return;
      }
      final copy = box.copyWith(
        x: c.x,
        y: c.y,
        z: c.z,
        w: c.o.w,
        d: c.o.d,
        h: c.o.h,
        rotY: 0,
      );
      placed.add(copy);
      placedOf[box.id] = copy;
    }

    for (final box in sorted) {
      tryPlace(box);
    }
    // 2차: 나머지가 놓인 뒤 생긴 자리에 다시 시도
    if (unfit.isNotEmpty) {
      final retry = List<TrimBox>.from(unfit);
      unfit.clear();
      for (final box in retry) {
        tryPlace(box);
      }
    }
    // 3차: 극점 후보에 없는 틈새를 3cm 격자로 전수 탐색 (남은 박스만)
    if (unfit.isNotEmpty) {
      final retry = List<TrimBox>.from(unfit);
      unfit.clear();
      for (final box in retry) {
        final c = _scanCandidate(trunk, detector, placed, box);
        if (c == null) {
          unfit.add(box);
          continue;
        }
        final copy = box.copyWith(
            x: c.x, y: c.y, z: c.z, w: c.o.w, d: c.o.d, h: c.o.h, rotY: 0);
        placed.add(copy);
        placedOf[box.id] = copy;
      }
    }

    // 결과 게이트: 충돌·부양이 있으면 그 박스는 미적재로
    final bad = detector.findAllCollisions(placed);
    for (final p in placed) {
      final others = placed.where((o) => o.id != p.id);
      if (!SupportRule.isSupported(p, others, trunk)) bad.add(p.id);
    }
    if (bad.isNotEmpty) {
      for (final id in bad) {
        final orig = boxes.firstWhere((b) => b.id == id);
        if (!unfit.contains(orig)) unfit.add(orig);
        placedOf.remove(id);
      }
      placed.removeWhere((p) => bad.contains(p.id));
    }

    // 적재 순서: 깊은 곳(z 작음) → 낮은 곳 → 왼쪽
    final ordered = List<TrimBox>.from(placed)
      ..sort((a, b) {
        final za = (a.z / 0.25).floor(), zb = (b.z / 0.25).floor();
        if (za != zb) return za.compareTo(zb);
        if ((a.y - b.y).abs() > 1e-6) return a.y.compareTo(b.y);
        return a.x.compareTo(b.x);
      });
    final placements = <BoxPlacement>[];
    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      placements.add(BoxPlacement(
        box: boxes.firstWhere((b) => b.id == p.id),
        x: p.x,
        y: p.y,
        z: p.z,
        w: p.w,
        d: p.d,
        h: p.h,
        loadOrder: i + 1,
      ));
    }

    final reasons = <String, String>{
      for (final b in unfit) b.id: _unfitReason(trunk, b, placed),
    };

    final usedVol = placed.fold<double>(0, (s, b) => s + b.w * b.d * b.h);
    final totalVol = trunk.usableVolume;
    return AutoLayoutResult(
      placements: placements,
      utilizationPercent:
          totalVol <= 0 ? 0 : (usedVol / totalVol * 100).clamp(0, 100),
      allBoxesFit: unfit.isEmpty,
      unfitBoxes: unfit,
      unfitReasons: reasons,
      strategy: strategy,
    );
  }

  /// 세 전략을 모두 돌려 (배치 개수 ↓, 적재율 ↓) 순으로 정렬
  static List<AutoLayoutResult> generateAlternatives(
    TrunkSpace trunk,
    List<TrimBox> boxes, {
    int restarts = 0,
    Duration budget = const Duration(milliseconds: 800),
  }) {
    final results = [
      for (final s in LayoutStrategy.values)
        computeLayout(trunk, boxes,
            strategy: s, restarts: restarts, budget: budget),
    ];
    results.sort((a, b) {
      if (a.placedCount != b.placedCount) {
        return b.placedCount.compareTo(a.placedCount);
      }
      return b.utilizationPercent.compareTo(a.utilizationPercent);
    });
    return results;
  }

  // ── 내부 ──

  static double _vol(TrimBox b) => b.w * b.d * b.h;
  static double _maxDim(TrimBox b) => math.max(b.w, math.max(b.d, b.h));
  static double _minDim(TrimBox b) => math.min(b.w, math.min(b.d, b.h));

  /// 전략별 기본 정렬을 먼저, 그 다음 보조 정렬들을 시도한다.
  static List<List<TrimBox>> _sortVariants(
      List<TrimBox> boxes, LayoutStrategy s) {
    List<TrimBox> by(int Function(TrimBox, TrimBox) cmp) =>
        List<TrimBox>.from(boxes)..sort(cmp);
    int volDesc(TrimBox a, TrimBox b) {
      final c = _vol(b).compareTo(_vol(a));
      return c != 0 ? c : _maxDim(b).compareTo(_maxDim(a));
    }

    int longDesc(TrimBox a, TrimBox b) {
      final c = _maxDim(b).compareTo(_maxDim(a));
      return c != 0 ? c : _vol(b).compareTo(_vol(a));
    }

    // 납작한(최소 치수 큰 것부터 = 두꺼운) 순: 바닥에 깔기 좋은 것 먼저
    int thickDesc(TrimBox a, TrimBox b) {
      final c = _minDim(b).compareTo(_minDim(a));
      return c != 0 ? c : _vol(b).compareTo(_vol(a));
    }

    // 세워야 하는 짐(쿨러 등)을 먼저 놓고 나머지
    int uprightFirst(TrimBox a, TrimBox b) {
      if (a.keepUpright != b.keepUpright) return a.keepUpright ? -1 : 1;
      return volDesc(a, b);
    }

    return switch (s) {
      LayoutStrategy.balanced => [by(volDesc), by(uprightFirst), by(longDesc), by(thickDesc)],
      LayoutStrategy.maxUtilization => [by(longDesc), by(volDesc), by(thickDesc), by(uprightFirst)],
      LayoutStrategy.easyAccess => [by(volDesc), by(thickDesc), by(uprightFirst), by(longDesc)],
    };
  }

  static List<_Orientation> _orientations(TrimBox b) {
    final out = <_Orientation>[];
    void add(double w, double d, double h) {
      for (final o in out) {
        if ((o.w - w).abs() < 1e-9 &&
            (o.d - d).abs() < 1e-9 &&
            (o.h - h).abs() < 1e-9) {
          return;
        }
      }
      out.add(_Orientation(w, d, h));
    }

    add(b.w, b.d, b.h);
    add(b.d, b.w, b.h);
    if (!b.keepUpright) {
      add(b.w, b.h, b.d);
      add(b.h, b.w, b.d);
      add(b.d, b.h, b.w);
      add(b.h, b.d, b.w);
    }
    return out;
  }

  static double _snapUp(double v) => ((v - 1e-7) * 100).ceil() / 100;
  static double _snapDown(double v) => ((v + 1e-7) * 100).floor() / 100;

  /// 후보 (x, z) 집합
  static (List<double>, List<double>) _candidateAxes(
    TrunkSpace trunk,
    List<TrimBox> placed,
    _Orientation o,
  ) {
    final xs = <double>{0.0};
    final zs = <double>{0.0};
    for (final p in placed) {
      xs.add(_snapUp(p.x + p.effectiveW));
      xs.add(_snapDown(p.x));
      xs.add(_snapDown(p.x - o.w));
      zs.add(_snapUp(p.z + p.effectiveD));
      zs.add(_snapDown(p.z));
      zs.add(_snapDown(p.z - o.d));
    }
    final lw = trunk.leftWheelhouse;
    final rw = trunk.rightWheelhouse;
    if (lw.w > 0) {
      xs.add(_snapUp(lw.w));
      zs.add(_snapUp(lw.d));
    }
    if (rw.w > 0) {
      xs.add(_snapDown(trunk.w - rw.w - o.w));
      zs.add(_snapUp(rw.d));
    }
    // 오른쪽 벽에 붙이는 후보
    xs.add(_snapDown(trunk.w - o.w));
    // 테이퍼 왼쪽 경계 (뒤쪽이 가장 좁다)
    for (final z in zs.toList()) {
      xs.add(_snapUp(trunk.taperAt(z)));
      xs.add(_snapDown(trunk.w - trunk.taperAt(z) - o.w));
    }
    final xl = xs.where((x) => x >= -1e-9 && x + o.w <= trunk.w + 1e-9).toList()
      ..sort();
    final zl = zs.where((z) => z >= -1e-9 && z + o.d <= trunk.d + 1e-9).toList()
      ..sort();
    return (xl, zl);
  }

  static _Candidate? _bestCandidate(
    TrunkSpace trunk,
    CollisionDetector detector,
    List<TrimBox> placed,
    TrimBox box,
    LayoutStrategy strategy,
    List<TrimBox> all,
  ) {
    _Candidate? best;
    final (wy, wz, wx, contactBonus) = switch (strategy) {
      LayoutStrategy.balanced => (6.0, 1.0, 0.3, 0.03),
      LayoutStrategy.maxUtilization => (4.0, 1.0, 0.5, 0.08),
      LayoutStrategy.easyAccess => (6.0, 1.0, 0.3, 0.03),
    };
    // 접근 우선: 부피 하위 40% 는 테일게이트 쪽을 선호
    var zWeight = wz;
    if (strategy == LayoutStrategy.easyAccess) {
      final vols = all.map((b) => b.w * b.d * b.h).toList()..sort();
      final cut = vols[(vols.length * 0.4).floor().clamp(0, vols.length - 1)];
      if (box.w * box.d * box.h <= cut) zWeight = -0.4;
    }

    for (final o in _orientations(box)) {
      if (o.w > trunk.w + 1e-9 || o.d > trunk.d + 1e-9 || o.h > trunk.h + 1e-9) {
        continue;
      }
      final probe = box.copyWith(w: o.w, d: o.d, h: o.h, rotY: 0);
      final (xs, zs) = _candidateAxes(trunk, placed, o);
      for (final z in zs) {
        for (final x in xs) {
          probe
            ..x = x
            ..z = z;
          // 떨어뜨리기: 낮은 유효 층부터 충돌 없는 첫 층
          double? y;
          for (final level in SupportRule.validLevels(probe, placed, trunk)) {
            probe.y = level;
            if (!detector.hasCollision(probe, placed)) {
              y = level;
              break;
            }
          }
          if (y == null) continue;

          var score = y * wy + z * zWeight + x * wx;
          score -= contactBonus * _contacts(trunk, placed, probe);
          if (best == null || score < best.score) {
            best = _Candidate(x, y, z, o, score);
          }
        }
      }
    }
    return best;
  }

  /// 2cm 격자 전수 탐색 (극점 후보로 못 찾은 틈새용). 낮고 깊은 자리 우선.
  static _Candidate? _scanCandidate(
    TrunkSpace trunk,
    CollisionDetector detector,
    List<TrimBox> placed,
    TrimBox box,
  ) {
    const step = 0.03;
    final used = placed.fold<double>(0, (s, p) => s + p.w * p.d * p.h);
    if (used + _vol(box) > trunk.usableVolume) return null;
    _Candidate? best;
    for (final o in _orientations(box)) {
      if (o.w > trunk.w + 1e-9 || o.d > trunk.d + 1e-9 || o.h > trunk.h + 1e-9) {
        continue;
      }
      final probe = box.copyWith(w: o.w, d: o.d, h: o.h, rotY: 0);
      final maxX = trunk.w - o.w;
      final maxZ = trunk.d - o.d;
      for (var z = 0.0; z <= maxZ + 1e-9; z += step) {
        for (var x = 0.0; x <= maxX + 1e-9; x += step) {
          probe
            ..x = _snapDown(x)
            ..z = _snapDown(z);
          double? y;
          for (final level in SupportRule.validLevels(probe, placed, trunk)) {
            probe.y = level;
            if (!detector.hasCollision(probe, placed)) {
              y = level;
              break;
            }
          }
          if (y == null) continue;
          final score = y * 6 + probe.z + probe.x * 0.3;
          if (best == null || score < best.score) {
            best = _Candidate(probe.x, y, probe.z, o, score);
          }
        }
      }
    }
    return best;
  }

  /// 벽·바닥·이웃과 맞닿은 면 수 (빈틈 줄이기용 보너스)
  static int _contacts(TrunkSpace trunk, List<TrimBox> placed, TrimBox b) {
    const tol = 0.011;
    var n = 0;
    if (b.y <= tol) n++;
    if (b.z <= tol) n++;
    if ((b.x - trunk.taperAt(b.z)).abs() <= tol) n++;
    if ((b.x + b.effectiveW - (trunk.w - trunk.taperAt(b.z))).abs() <= tol) n++;
    for (final p in placed) {
      final yOverlap = b.y < p.y + p.h && b.y + b.h > p.y;
      final zOverlap = b.z < p.z + p.effectiveD && b.z + b.effectiveD > p.z;
      final xOverlap = b.x < p.x + p.effectiveW && b.x + b.effectiveW > p.x;
      if (yOverlap && zOverlap) {
        if ((b.x - (p.x + p.effectiveW)).abs() <= tol ||
            ((b.x + b.effectiveW) - p.x).abs() <= tol) {
          n++;
        }
      }
      if (yOverlap && xOverlap) {
        if ((b.z - (p.z + p.effectiveD)).abs() <= tol ||
            ((b.z + b.effectiveD) - p.z).abs() <= tol) {
          n++;
        }
      }
    }
    return n;
  }

  static String _unfitReason(TrunkSpace trunk, TrimBox b, List<TrimBox> placed) {
    final dims = [b.w, b.d, b.h]..sort();
    final space = [trunk.w, trunk.d, trunk.h]..sort();
    final tooBig = dims[0] > space[0] + 1e-9 ||
        dims[1] > space[1] + 1e-9 ||
        dims[2] > space[2] + 1e-9;
    if (tooBig) {
      return '트렁크보다 큼 (${_cm(b.w)}×${_cm(b.d)}×${_cm(b.h)}cm)';
    }
    if (b.keepUpright && b.h > trunk.h + 1e-9) {
      return '세운 높이 ${_cm(b.h)}cm 가 천장 ${_cm(trunk.h)}cm 초과';
    }
    final used = placed.fold<double>(0, (s, p) => s + p.w * p.d * p.h);
    if (used + b.w * b.d * b.h > trunk.usableVolume) return '남은 부피 부족';
    return '빈 자리 없음';
  }

  static String _cm(double m) => (m * 100).round().toString();
}
