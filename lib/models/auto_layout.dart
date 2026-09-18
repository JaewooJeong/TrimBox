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

  /// 눌러 넣은 비율 (연질 짐만, 0 = 안 누름): 높이 / 폭 / 깊이 방향
  final double squash;
  final double squashW;
  final double squashD;

  const BoxPlacement({
    required this.box,
    required this.x,
    required this.y,
    required this.z,
    required this.w,
    required this.d,
    required this.h,
    required this.loadOrder,
    this.squash = 0,
    this.squashW = 0,
    this.squashD = 0,
  });

  bool get squashed => squashAmount > 1e-6;
  double get squashAmount => math.max(squash, math.max(squashW, squashD));

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
      ..squash = squash
      ..squashW = squashW
      ..squashD = squashD
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

  /// 눌러 넣은 연질 짐
  List<BoxPlacement> get squashedPlacements =>
      placements.where((p) => p.squashed).toList();

  /// 바닥이 아닌 곳에 놓인 무거운 짐 수 (적을수록 좋은 배치)
  int get heavyStackedCount => placements
      .where((p) => p.box.weightKg >= AutoLayoutEngine.heavyKg && p.y > 0.015)
      .length;
}

class _Orientation {
  final double w, d, h;
  final double sw, sd, sh; // 연질 짐 축별 압축 비율
  const _Orientation(this.w, this.d, this.h, [this.sw = 0, this.sd = 0, this.sh = 0]);

  /// 압축 반영 치수
  double get ew => w * (1 - sw);
  double get ed => d * (1 - sd);
  double get eh => h * (1 - sh);

  _Orientation withSquash(_Squash s) => _Orientation(w, d, h, s.w, s.d, s.h);
}

/// 축별 압축 조합 (한 번에 한 축만)
class _Squash {
  final double w, d, h;
  const _Squash(this.w, this.d, this.h);
  static const none = _Squash(0, 0, 0);
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

  /// 이 무게(kg) 이상이면 "무거운 짐": 바닥·안쪽을 강하게 선호하고 높이 올리면 조언
  static const double heavyKg = 12;

  /// 이 무게(kg) 이상이면 자동배치는 바닥에만 놓는다 (가득 찬 쿨러 등)
  static const double floorOnlyKg = 20;

  /// 마지막 격자 전수 탐색을 해 볼 미적재 박스 수 (큰 것부터). 시간이 아니라 개수로
  /// 끊어야 기기 속도와 무관하게 같은 판정이 나온다.
  static const int scanMaxBoxes = 2;

  /// 보수(ejection chain) 단계의 최대 시도 수 (빼 볼 박스 × 못 넣은 박스)
  static const int repairMaxAttempts = 24;

  /// 무작위 재시도가 이만큼 연속으로 나아지지 않으면 멈춘다
  static const int restartPatience = 8;

  /// 마지막에 보수·격자 채우기를 해 볼 상위 후보 수
  static const int poolSize = 1;

  /// "무거운 짐이 가벼운 짐 위" 규칙: 이 무게 이상인 짐이 자기 무게의
  /// [lightBaseRatio] 미만인 짐 위에 놓이면 벌점·조언
  static const double lightBaseKg = 8;
  static const double lightBaseRatio = 0.4;

  /// 연질 짐 압축 단계: 안 누름 → 높이 절반 → 높이 최대 → 깊이 최대.
  /// [coarse] 는 전수 탐색용 축약 단계.
  static List<_Squash> _squashLevels(TrimBox b,
      {bool coarse = false, bool tight = false}) {
    if (!b.soft || b.compressibility <= 0) return const [_Squash.none];
    final c = b.compressibility;
    // 빡빡한 패스: 처음부터 깊이를 최대로 눌러 촘촘히 세운다 (캐디백·침낭 여러 개)
    if (tight) {
      return [_Squash(0, c, 0), _Squash(0, 0, c), _Squash.none];
    }
    if (coarse) {
      return [_Squash.none, _Squash(0, 0, c), _Squash(0, c, 0)];
    }
    return [
      _Squash.none,
      _Squash(0, 0, c * 0.5),
      _Squash(0, 0, c),
      _Squash(0, c, 0),
    ];
  }

  /// [restarts]: 기본 정렬들로 전부 못 넣었을 때 추가로 시도할 무작위 순서 수.
  /// [budget]: 추가 시도에 쓸 최대 시간. [seed]: 재현용 난수 시드.
  static AutoLayoutResult computeLayout(
    TrunkSpace trunk,
    List<TrimBox> boxes, {
    LayoutStrategy strategy = LayoutStrategy.balanced,
    int restarts = 0,
    Duration budget = const Duration(seconds: 5),
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
    // 보수 전 상위 후보들 (순위순). 마지막에 이들 모두를 보수·격자 채우기 해서
    // 가장 좋은 것을 고른다 — "재시도를 늘렸더니 보수가 안 되는 배치로 바뀌어
    // 판정이 나빠지는" 일을 막는다.
    final pool = <AutoLayoutResult>[];
    void consider(AutoLayoutResult r) {
      if (best == null || _better(r, best!)) best = r;
      pool.add(r);
      pool.sort((a, b) => _better(a, b) ? -1 : (_better(b, a) ? 1 : 0));
      if (pool.length > poolSize) pool.removeRange(poolSize, pool.length);
    }

    // 탐색 단계는 격자 전수 탐색(느림) 없이 돌리고, 마지막에 가장 좋은 결과의
    // 남은 박스만 전수 탐색으로 채운다.
    final variants = _sortVariants(boxes, strategy);
    for (final order in variants) {
      consider(_pack(trunk, order, boxes, strategy, scan: false));
      if (best!.allBoxesFit) return best!;
    }
    // 같은 순서를 "세워 놓기" 편향으로 한 번 더 (앞의 두 변형만 — 비용 절반)
    for (final order in variants.take(2)) {
      consider(_pack(trunk, order, boxes, strategy,
          scan: false, uprightBias: true));
      if (best!.allBoxesFit) return best!;
    }
    // 연질 짐이 있으면 처음부터 눌러 촘촘히 놓는 패스
    if (boxes.any((b) => b.soft && b.compressibility > 0)) {
      for (final order in variants.take(2)) {
        consider(_pack(trunk, order, boxes, strategy,
            scan: false, softTight: true));
        if (best!.allBoxesFit) return best!;
      }
    }

    // 못 넣은 박스를 맨 앞에 두고 다시 (가장 효과가 큰 재시도)
    for (var round = 0; round < 2 && !best!.allBoxesFit; round++) {
      final unfitIds = best!.unfitBoxes.map((b) => b.id).toSet();
      final base = _sortVariants(boxes, strategy).first;
      final order = [
        ...base.where((b) => unfitIds.contains(b.id)),
        ...base.where((b) => !unfitIds.contains(b.id)),
      ];
      consider(_pack(trunk, order, boxes, strategy, scan: false));
    }

    // 재시도 0회의 결과는 항상 결선에 올린다 (재시도를 늘려도 나빠지지 않게)
    final baseBest = best;

    // 무작위 순서 재시도 (시간 예산 안에서)
    final rnd = math.Random(seed);
    var lastImproved = 0;
    for (var i = 0;
        i < restarts &&
            !best!.allBoxesFit &&
            i - lastImproved < restartPatience &&
            sw.elapsed < budget;
        i++) {
      final before = best;
      // 부피에 잡음을 섞은 내림차순: 큰 것 먼저라는 원칙은 대체로 유지.
      // 짝수 회차는 바닥 면적 기준으로 섞어 다양성을 준다.
      final keyed = {
        for (final b in boxes)
          b.id: (i.isEven ? _vol(b) : _footprint(b)) *
              (0.6 + rnd.nextDouble() * 0.8),
      };
      final order = List<TrimBox>.from(boxes)
        ..sort((a, b) => keyed[b.id]!.compareTo(keyed[a.id]!));
      consider(_pack(trunk, order, boxes, strategy,
          scan: false, uprightBias: i % 3 == 2, softTight: i % 4 == 1));
      if (!identical(before, best)) lastImproved = i + 1;
    }

    if (best!.allBoxesFit) return best!;

    // 상위 후보(+ 기본 정렬만의 최선) 를 각각 보수·격자 채우기 하고 최종 승자를 고른다
    final finalists = <AutoLayoutResult>[...pool];
    if (baseBest != null && !finalists.contains(baseBest)) finalists.add(baseBest);
    AutoLayoutResult? winner;
    for (final f in finalists) {
      final r = _repair(trunk, f, boxes, strategy);
      if (winner == null || _better(r, winner)) winner = r;
      if (winner.allBoxesFit) return winner;
    }
    // 비싼 탐색(후보 축의 전체 곱 → 3cm 격자)은 최종 승자의 남은 박스에만
    var result = _fill(trunk, winner!, boxes, strategy, exhaustive: true);
    if (!result.allBoxesFit) result = _scanFill(trunk, result, boxes);
    return result;
  }

  /// 결과 비교: 배치 개수 → 적재율(1%p 이상 차이) → 위층의 무거운 짐 적은 쪽 → 적재율
  static bool _better(AutoLayoutResult a, AutoLayoutResult b) {
    if (a.placedCount != b.placedCount) return a.placedCount > b.placedCount;
    final du = a.utilizationPercent - b.utilizationPercent;
    if (du.abs() > 1.0) return du > 0;
    if (a.heavyStackedCount != b.heavyStackedCount) {
      return a.heavyStackedCount < b.heavyStackedCount;
    }
    return du > 1e-9;
  }

  /// 보수: 못 넣은 박스마다, 이미 놓인 작은 박스 하나를 빼고 둘을 다시 넣어 본다
  /// (깊이 1 의 ejection chain). 시간 예산 안에서만.
  static AutoLayoutResult _repair(
    TrunkSpace trunk,
    AutoLayoutResult result,
    List<TrimBox> boxes,
    LayoutStrategy strategy,
  ) {
    final detector = CollisionDetector(trunk);
    var placed = <TrimBox>[
      for (final p in result.placements)
        p.box.copyWith(
            x: p.x, y: p.y, z: p.z, w: p.w, d: p.d, h: p.h, rotY: 0,
            squash: p.squash, squashW: p.squashW, squashD: p.squashD),
    ];
    final unfit = List<TrimBox>.from(result.unfitBoxes);
    var attempts = 0;
    var improved = false;

    TrimBox? tryPlace(TrimBox original, List<TrimBox> into) {
      final c = _bestCandidate(trunk, detector, into, original, strategy, boxes);
      if (c == null) return null;
      return original.copyWith(
          x: c.x, y: c.y, z: c.z, w: c.o.w, d: c.o.d, h: c.o.h, rotY: 0,
          squash: c.o.sh, squashW: c.o.sw, squashD: c.o.sd);
    }

    for (final u in List<TrimBox>.from(unfit)) {
      if (attempts >= repairMaxAttempts) break;
      // 작은 박스부터 빼 본다 (큰 박스를 빼면 되돌려 넣기 어렵다)
      final candidates = (List<TrimBox>.from(placed)
            ..sort((a, b) => _vol(a).compareTo(_vol(b))))
          .take(10);
      for (final p in candidates) {
        if (attempts++ >= repairMaxAttempts) break;
        final without = placed.where((b) => b.id != p.id).toList();
        final uPlaced = tryPlace(u, without);
        if (uPlaced == null) continue;
        without.add(uPlaced);
        final pOriginal = boxes.firstWhere((b) => b.id == p.id);
        final pPlaced = tryPlace(pOriginal, without);
        if (pPlaced == null) continue;
        without.add(pPlaced);
        placed = without;
        unfit.remove(u);
        improved = true;
        break;
      }
    }
    if (!improved) return result;
    // 뺀 박스 위에 얹혀 있던 짐이 검증 게이트에서 탈락할 수 있다 — 나아졌을 때만 채택
    final repaired =
        _finalize(trunk, detector, placed, unfit, boxes, result.strategy);
    return _better(repaired, result) ? repaired : result;
  }

  /// [result] 의 미적재 박스를 후보 축의 전체 곱(O(n²) 후보)으로 한 번 더 찾아 넣는다.
  static AutoLayoutResult _fill(
    TrunkSpace trunk,
    AutoLayoutResult result,
    List<TrimBox> boxes,
    LayoutStrategy strategy, {
    required bool exhaustive,
  }) {
    final detector = CollisionDetector(trunk);
    final placed = <TrimBox>[
      for (final p in result.placements)
        p.box.copyWith(
            x: p.x, y: p.y, z: p.z, w: p.w, d: p.d, h: p.h, rotY: 0,
            squash: p.squash, squashW: p.squashW, squashD: p.squashD),
    ];
    final unfit = <TrimBox>[];
    var changed = false;
    for (final box in result.unfitBoxes) {
      final c = _bestCandidate(trunk, detector, placed, box, strategy, boxes,
          exhaustive: exhaustive);
      if (c == null) {
        unfit.add(box);
        continue;
      }
      placed.add(box.copyWith(
          x: c.x, y: c.y, z: c.z, w: c.o.w, d: c.o.d, h: c.o.h, rotY: 0,
          squash: c.o.sh, squashW: c.o.sw, squashD: c.o.sd));
      changed = true;
    }
    if (!changed) return result;
    final filled = _finalize(trunk, detector, placed, unfit, boxes, strategy);
    return _better(filled, result) ? filled : result;
  }

  /// [result] 의 미적재 박스를 3cm 격자 전수 탐색으로 빈틈에 채운다.
  static AutoLayoutResult _scanFill(
      TrunkSpace trunk, AutoLayoutResult result, List<TrimBox> boxes) {
    final detector = CollisionDetector(trunk);
    final placed = <TrimBox>[
      for (final p in result.placements)
        p.box.copyWith(
            x: p.x, y: p.y, z: p.z, w: p.w, d: p.d, h: p.h, rotY: 0,
            squash: p.squash, squashW: p.squashW, squashD: p.squashD),
    ];
    final unfit = <TrimBox>[];
    var scanned = 0;
    for (final box in result.unfitBoxes) {
      final c = scanned++ < scanMaxBoxes
          ? _scanCandidate(trunk, detector, placed, box)
          : null;
      if (c == null) {
        unfit.add(box);
        continue;
      }
      placed.add(box.copyWith(
          x: c.x, y: c.y, z: c.z, w: c.o.w, d: c.o.d, h: c.o.h, rotY: 0,
          squash: c.o.sh, squashW: c.o.sw, squashD: c.o.sd));
    }
    if (unfit.length == result.unfitBoxes.length) return result;
    return _finalize(trunk, detector, placed, unfit, boxes, result.strategy);
  }

  static AutoLayoutResult _pack(
    TrunkSpace trunk,
    List<TrimBox> sorted,
    List<TrimBox> boxes,
    LayoutStrategy strategy, {
    bool scan = true,
    bool uprightBias = false,
    bool softTight = false,
  }) {
    final detector = CollisionDetector(trunk);
    final placed = <TrimBox>[]; // 배치된 사본 (rotY = 0, 치수 = 배치 방향)
    final unfit = <TrimBox>[];

    void tryPlace(TrimBox box, {bool exhaustive = false}) {
      final c = _bestCandidate(trunk, detector, placed, box, strategy, boxes,
          uprightBias: uprightBias,
          softTight: softTight,
          exhaustive: exhaustive);
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
        squash: c.o.sh, squashW: c.o.sw, squashD: c.o.sd,
      );
      placed.add(copy);
    }

    for (final box in sorted) {
      tryPlace(box);
    }
    // 2차: 나머지가 놓인 뒤 생긴 자리(새 받침)에 다시 시도
    if (unfit.isNotEmpty) {
      final retry = List<TrimBox>.from(unfit);
      unfit.clear();
      for (final box in retry) {
        tryPlace(box);
      }
    }
    // 3차: 극점 후보에 없는 틈새를 3cm 격자로 전수 탐색 (남은 박스만)
    if (scan && unfit.isNotEmpty) {
      final retry = List<TrimBox>.from(unfit);
      unfit.clear();
      for (final box in retry) {
        final c = _scanCandidate(trunk, detector, placed, box);
        if (c == null) {
          unfit.add(box);
          continue;
        }
        placed.add(box.copyWith(
            x: c.x, y: c.y, z: c.z, w: c.o.w, d: c.o.d, h: c.o.h, rotY: 0,
            squash: c.o.sh, squashW: c.o.sw, squashD: c.o.sd));
      }
    }

    return _finalize(trunk, detector, placed, unfit, boxes, strategy);
  }

  /// 검증 게이트 → 적재 순서 → 결과 객체
  static AutoLayoutResult _finalize(
    TrunkSpace trunk,
    CollisionDetector detector,
    List<TrimBox> placed,
    List<TrimBox> unfit,
    List<TrimBox> boxes,
    LayoutStrategy strategy,
  ) {
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
        squash: p.squash,
        squashW: p.squashW,
        squashD: p.squashD,
      ));
    }

    final reasons = <String, String>{
      for (final b in unfit) b.id: _unfitReason(trunk, b, placed),
    };

    final usedVol = placed.fold<double>(0, (s, b) => s + b.volume);
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

  static double _vol(TrimBox b) => b.volume;

  /// 가장 납작하게 놓았을 때의 바닥 면적 (세워야 하는 짐은 w×d)
  static double _footprint(TrimBox b) {
    if (b.keepUpright) return b.w * b.d;
    final dims = [b.w, b.d, b.h]..sort();
    return dims[1] * dims[2];
  }
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

    // 바닥 면적 큰 것부터: 바닥층을 빈틈 없이 깔고 작은 것을 위에 올린다
    int areaDesc(TrimBox a, TrimBox b) {
      final c = _footprint(b).compareTo(_footprint(a));
      return c != 0 ? c : _vol(b).compareTo(_vol(a));
    }

    // 무거운 것 먼저 (바닥·안쪽을 차지), 같은 무게면 부피
    int heavyFirst(TrimBox a, TrimBox b) {
      final c = b.weightKg.compareTo(a.weightKg);
      return c != 0 ? c : volDesc(a, b);
    }

    final variants = switch (s) {
      LayoutStrategy.balanced => [by(volDesc), by(heavyFirst), by(areaDesc), by(uprightFirst), by(longDesc), by(thickDesc)],
      LayoutStrategy.maxUtilization => [by(longDesc), by(areaDesc), by(volDesc), by(heavyFirst), by(thickDesc), by(uprightFirst)],
      LayoutStrategy.easyAccess => [by(volDesc), by(heavyFirst), by(thickDesc), by(areaDesc), by(uprightFirst), by(longDesc)],
    };
    // 바닥에만 둘 수 있는 무거운 짐(가득 찬 쿨러 등)은 항상 먼저 바닥을 차지하고,
    // 연질 짐(침낭·타프 천 등)은 단단한 짐을 다 놓은 뒤 틈과 위에 채운다
    return [for (final v in variants) _softLast(_floorOnlyFirst(v))];
  }

  /// 단단한 짐 먼저, 연질 짐은 원래 순서를 유지한 채 뒤로
  static List<TrimBox> _softLast(List<TrimBox> order) => [
        ...order.where((b) => !b.soft),
        ...order.where((b) => b.soft),
      ];

  /// 바닥 전용(20kg 이상) 짐을 부피 순으로 맨 앞에
  static List<TrimBox> _floorOnlyFirst(List<TrimBox> order) {
    final heavy = order.where((b) => b.weightKg >= floorOnlyKg).toList()
      ..sort((a, b) => _vol(b).compareTo(_vol(a)));
    return [...heavy, ...order.where((b) => b.weightKg < floorOnlyKg)];
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
      xs.add(_snapDown(p.x - o.ew));
      zs.add(_snapUp(p.z + p.effectiveD));
      zs.add(_snapDown(p.z));
      zs.add(_snapDown(p.z - o.ed));
    }
    final lw = trunk.leftWheelhouse;
    final rw = trunk.rightWheelhouse;
    if (lw.w > 0) {
      xs.add(_snapUp(lw.w));
      zs.add(_snapUp(lw.zEnd));
      if (lw.zStart > 0) zs.add(_snapDown(lw.zStart - o.ed));
    }
    if (rw.w > 0) {
      xs.add(_snapDown(trunk.w - rw.w - o.ew));
      zs.add(_snapUp(rw.zEnd));
      if (rw.zStart > 0) zs.add(_snapDown(rw.zStart - o.ed));
    }
    // 오른쪽 벽에 붙이는 후보
    xs.add(_snapDown(trunk.w - o.ew));
    // 폭을 거의 다 쓰는 긴 짐(캐디백·캐노피 가방)은 가운데 자리 하나뿐일 수 있다
    if (o.ew > trunk.w * 0.75) xs.add(_snapDown((trunk.w - o.ew) / 2));
    // 높이 올라가면 벽이 안쪽으로 기운다(텀블홈): 그 높이의 좌우 경계에 붙이는 후보
    final zMid = trunk.d / 2;
    final tops = <int>{
      (o.eh * 100).round(),
      for (final p in placed) ((p.top + o.eh) * 100).round(),
    };
    for (final t in tops) {
      final top = t / 100;
      final xMin = trunk.xMinAt(zMid, top);
      if (xMin <= 0.001) continue;
      xs.add(_snapUp(xMin));
      xs.add(_snapDown(trunk.xMaxAt(zMid, top) - o.ew));
    }
    // 테일게이트 닫힘 한계에 붙이는 후보: 바닥에 놓일 때와 각 박스 위에 놓일 때
    // 윗면 높이에서 허용되는 최대 z 에서 뒤로 물린 자리
    if (trunk.hasTailgateModel) {
      zs.add(_snapDown(trunk.rearDepthAt(o.eh) - o.ed));
      for (final p in placed) {
        zs.add(_snapDown(trunk.rearDepthAt(p.top + o.eh) - o.ed));
      }
    }
    // 2열 슬라이드 빈틈: 절반만 걸치는 자리와 빈틈이 끝나는 자리
    if (trunk.floorStartZ > 0) {
      zs.add(_snapUp(trunk.floorStartZ - o.ed * 0.5));
      zs.add(_snapUp(trunk.floorStartZ));
    }
    // 등받이 기울기: 윗면 높이에서 허용되는 최소 z 에 붙이는 후보
    if (trunk.frontProfile != null) {
      zs.add(_snapUp(trunk.frontDepthAt(o.eh)));
      for (final p in placed) {
        zs.add(_snapUp(trunk.frontDepthAt(p.top + o.eh)));
      }
    }
    // 테이퍼 왼쪽 경계 (뒤쪽이 가장 좁다)
    for (final z in zs.toList()) {
      xs.add(_snapUp(trunk.taperAt(z)));
      xs.add(_snapDown(trunk.w - trunk.taperAt(z) - o.ew));
    }
    final xl = xs.where((x) => x >= -1e-9 && x + o.ew <= trunk.w + 1e-9).toList()
      ..sort();
    final zl = zs.where((z) => z >= -1e-9 && z + o.ed <= trunk.d + 1e-9).toList()
      ..sort();
    return (xl, zl);
  }

  /// 후보 (x, z) 점 목록 — 축의 곱(O(n²)) 대신 극점 쌍(O(n))만 만든다.
  /// 각 놓인 박스의 모서리 쌍, 그 모서리와 벽·휠하우스·프로필 경계의 조합,
  /// 그리고 경계끼리의 조합. 빠른 기본 경로이며, 못 찾으면 [_candidateAxes] 의
  /// 전체 곱으로 한 번 더 찾는다.
  static List<(double, double)> _candidatePoints(
    TrunkSpace trunk,
    List<TrimBox> placed,
    _Orientation o,
  ) {
    final (xs0, zs0) = _candidateAxes(trunk, const [], o);
    final seen = <int>{};
    final out = <(double, double)>[];
    void add(double x, double z) {
      if (x < -1e-9 || z < -1e-9) return;
      if (x + o.ew > trunk.w + 1e-9 || z + o.ed > trunk.d + 1e-9) return;
      final key = (x * 100).round() * 10000 + (z * 100).round();
      if (seen.add(key)) out.add((x, z));
    }

    for (final x in xs0) {
      for (final z in zs0) {
        add(x, z);
      }
    }
    final zMid = trunk.d / 2;
    for (final p in placed) {
      final xp = [
        _snapUp(p.x + p.effectiveW),
        _snapDown(p.x),
        _snapDown(p.x - o.ew),
        _snapDown(p.x + p.effectiveW - o.ew),
      ];
      final zp = [
        _snapUp(p.z + p.effectiveD),
        _snapDown(p.z),
        _snapDown(p.z - o.ed),
        _snapDown(p.z + p.effectiveD - o.ed),
      ];
      // p 위에 얹을 때의 앞뒤 한계와 좌우 한계
      final top = p.top + o.eh;
      final zProf = <double>[
        if (trunk.hasTailgateModel) _snapDown(trunk.rearDepthAt(top) - o.ed),
        if (trunk.frontProfile != null) _snapUp(trunk.frontDepthAt(top)),
      ];
      final xMin = trunk.xMinAt(zMid, top);
      final xTumble = <double>[
        if (xMin > 0.001) _snapUp(xMin),
        if (xMin > 0.001) _snapDown(trunk.xMaxAt(zMid, top) - o.ew),
      ];
      for (final x in xp) {
        for (final z in zp) {
          add(x, z);
        }
        for (final z in zs0) {
          add(x, z);
        }
        for (final z in zProf) {
          add(x, z);
        }
      }
      for (final z in zp) {
        for (final x in xs0) {
          add(x, z);
        }
        for (final x in xTumble) {
          add(x, z);
        }
      }
      for (final z in zProf) {
        for (final x in xs0) {
          add(x, z);
        }
        for (final x in xTumble) {
          add(x, z);
        }
      }
    }
    out.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return out;
  }

  static _Candidate? _bestCandidate(
    TrunkSpace trunk,
    CollisionDetector detector,
    List<TrimBox> placed,
    TrimBox box,
    LayoutStrategy strategy,
    List<TrimBox> all, {
    bool uprightBias = false,
    bool softTight = false,
    bool exhaustive = false,
  }) {
    final (wy, wz, wx, contactBonus) = switch (strategy) {
      LayoutStrategy.balanced => (6.0, 1.0, 0.3, 0.03),
      LayoutStrategy.maxUtilization => (4.0, 1.0, 0.5, 0.08),
      LayoutStrategy.easyAccess => (6.0, 1.0, 0.3, 0.03),
    };
    // 접근 우선: 부피 하위 40% 는 테일게이트 쪽을 선호
    var zWeight = wz;
    if (strategy == LayoutStrategy.easyAccess) {
      final vols = all.map((b) => b.volume).toList()..sort();
      final cut = vols[(vols.length * 0.4).floor().clamp(0, vols.length - 1)];
      if (box.volume <= cut) zWeight = -0.4;
    }
    // 자주 꺼내는 짐(쿨러 등)은 전략과 무관하게 테일게이트 쪽
    if (box.accessPriority) zWeight = -0.8;
    // 무거운 짐은 낮고 깊게
    final heavy = box.weightKg >= heavyKg;
    final yWeight = heavy ? wy * 2.5 : wy;
    if (heavy && !box.accessPriority) zWeight = wz * 2.0;

    // 압축은 필요한 만큼만: 덜 누른 단계에서 자리가 나오면 그걸로 끝
    for (final squash in _squashLevels(box, tight: softTight)) {
      _Candidate? best;
      for (final o0 in _orientations(box)) {
        final o = o0.withSquash(squash);
        if (o.ew > trunk.w + 1e-9 || o.ed > trunk.d + 1e-9 || o.eh > trunk.h + 1e-9) {
          continue;
        }
        final probe = box.copyWith(
            w: o.w, d: o.d, h: o.h, rotY: 0,
            squash: o.sh, squashW: o.sw, squashD: o.sd);
        final List<(double, double)> points;
        if (exhaustive) {
          final (xs, zs) = _candidateAxes(trunk, placed, o);
          points = [
            for (final z in zs)
              for (final x in xs) (x, z),
          ];
        } else {
          points = _candidatePoints(trunk, placed, o);
        }
        final biasTerm = uprightBias ? o.ew * o.ed * 4.0 : 0.0;
        {
          for (final (x, z) in points) {
            // 가지치기: y·적층 벌점·테일게이트 항은 0 이상, 접촉 보너스는 최대 6면.
            // 이 하한이 이미 찾은 최선보다 나쁘면 비싼 층·충돌 계산을 건너뛴다.
            if (best != null) {
              final lowerBound =
                  z * zWeight + x * wx + biasTerm - contactBonus * 6;
              if (lowerBound >= best.score) continue;
            }
            probe
              ..x = x
              ..z = z
              ..y = 0;
            if (_cannotFitAnyLevel(detector, probe)) continue;
            // 바닥면이 겹치는 박스만 지지·충돌에 관여한다 (한 번만 추린다)
            final near = _xzNeighbors(probe, placed);
            // 떨어뜨리기: 낮은 유효 층부터 충돌 없는 첫 층
            double? y;
            var stackPenalty = 0.0;
            for (final level in SupportRule.validLevels(probe, near, trunk)) {
              probe.y = level;
              if (detector.hasCollision(probe, near)) continue;
              final penalty = _stackPenalty(probe, level, near);
              if (penalty == null) continue; // 허용 안 함 (단단한 짐이 연질 위)
              y = level;
              stackPenalty = penalty;
              break;
            }
            if (y == null) continue;

            var score = y * yWeight + z * zWeight + x * wx + stackPenalty;
            if (trunk.hasTailgateModel) {
              // 윗면이 높을수록 테일게이트 쪽(z 큼)에서 닫힘 한계에 걸리므로
              // 윗면 높이 비율만큼 z 를 더 무겁게 본다
              score += z * ((y + o.eh) / trunk.h) * 1.5;
            }
            // 세워 놓기 편향: 바닥을 덜 차지하는 방향 우선 (캐리어·상자를 세워 싣는 배치)
            score += biasTerm;
            score -= contactBonus * _contacts(trunk, placed, probe);
            if (best == null || score < best.score) {
              best = _Candidate(x, y, z, o, score);
            }
          }
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  /// [probe] 의 바닥면과 xz 로 겹치는 박스들. 겹치지 않는 박스는 받치지도 부딪히지도 않는다.
  static List<TrimBox> _xzNeighbors(TrimBox probe, List<TrimBox> placed) {
    final x1 = probe.x, x2 = probe.x + probe.effectiveW;
    final z1 = probe.z, z2 = probe.z + probe.effectiveD;
    final out = <TrimBox>[];
    for (final p in placed) {
      if (p.x < x2 - 1e-6 &&
          p.x + p.effectiveW > x1 + 1e-6 &&
          p.z < z2 - 1e-6 &&
          p.z + p.effectiveD > z1 + 1e-6) {
        out.add(p);
      }
    }
    return out;
  }

  /// 바닥 높이(y = 0)에 놓아도 경계·테일게이트·등받이에 걸리면 더 높은 층에서도
  /// 걸린다 (벽과 앞뒤 프로필은 위로 갈수록 안쪽으로만 들어온다). 놓인 짐을 돌아보지
  /// 않는 O(1) 검사로 비싼 층·충돌 계산을 거른다.
  static bool _cannotFitAnyLevel(CollisionDetector detector, TrimBox probeAtFloor) =>
      detector.isOutOfBounds(probeAtFloor) ||
      detector.blocksTailgate(probeAtFloor) ||
      detector.hitsSeatBack(probeAtFloor);

  /// 층 [y]에 놓았을 때의 적층 벌점. null 이면 그 층은 쓰지 않는다.
  /// - 단단한 짐을 연질 짐 위에: 불허 (눌리고 불안정)
  /// - 무거운 짐을 자기 절반보다 가벼운 짐 위에: 벌점
  static double? _stackPenalty(TrimBox probe, double y, List<TrimBox> placed) {
    if (y <= SupportRule.heightTol) return 0;
    if (probe.weightKg >= floorOnlyKg) return null; // 가득 찬 쿨러 등은 바닥에만
    final supporters = SupportRule.supportersAt(probe, y, placed);
    if (supporters.isEmpty) return 0; // 휠하우스 위
    var penalty = 0.0;
    if (!probe.soft && supporters.any((s) => s.soft)) {
      if (probe.weightKg >= 5) return null;
      penalty += 0.15;
    }
    if (probe.weightKg >= lightBaseKg) {
      final lightest = supporters.map((s) => s.weightKg).reduce(math.min);
      if (lightest > 0 && lightest < probe.weightKg * lightBaseRatio) penalty += 0.4;
      if (lightest == 0 && probe.weightKg >= heavyKg) penalty += 0.2;
    }
    return penalty;
  }

  /// 2cm 격자 전수 탐색 (극점 후보로 못 찾은 틈새용). 낮고 깊은 자리 우선.
  static _Candidate? _scanCandidate(
    TrunkSpace trunk,
    CollisionDetector detector,
    List<TrimBox> placed,
    TrimBox box,
  ) {
    const step = 0.04;
    final used = placed.fold<double>(0, (s, p) => s + p.volume);
    if (used + box.volume > trunk.usableVolume) return null;
    for (final squash in _squashLevels(box, coarse: true)) {
      _Candidate? best;
      for (final o0 in _orientations(box)) {
        final o = o0.withSquash(squash);
        if (o.ew > trunk.w + 1e-9 || o.ed > trunk.d + 1e-9 || o.eh > trunk.h + 1e-9) {
          continue;
        }
        final probe = box.copyWith(
            w: o.w, d: o.d, h: o.h, rotY: 0,
            squash: o.sh, squashW: o.sw, squashD: o.sd);
        final maxX = trunk.w - o.ew;
        final maxZ = trunk.d - o.ed;
        for (var z = 0.0; z <= maxZ + 1e-9; z += step) {
          for (var x = 0.0; x <= maxX + 1e-9; x += step) {
            probe
              ..x = _snapDown(x)
              ..z = _snapDown(z)
              ..y = 0;
            if (_cannotFitAnyLevel(detector, probe)) continue;
            final near = _xzNeighbors(probe, placed);
            double? y;
            var stackPenalty = 0.0;
            for (final level in SupportRule.validLevels(probe, near, trunk)) {
              probe.y = level;
              if (detector.hasCollision(probe, near)) continue;
              final penalty = _stackPenalty(probe, level, near);
              if (penalty == null) continue;
              y = level;
              stackPenalty = penalty;
              break;
            }
            if (y == null) continue;
            final score = y * 6 + probe.z + probe.x * 0.3 + stackPenalty;
            if (best == null || score < best.score) {
              best = _Candidate(probe.x, y, probe.z, o, score);
            }
          }
        }
      }
      if (best != null) return best;
    }
    return null;
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
      final yOverlap = b.y < p.top && b.top > p.y;
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
    final ap = trunk.aperture;
    if (ap != null &&
        !CollisionDetector.fitsThroughAperture(b.w, b.d, b.h, ap,
            keepUpright: b.keepUpright)) {
      final how = b.keepUpright ? ' (세운 채로)' : '';
      return '개구부 ${_cm(ap.bottomWidth)}×${_cm(ap.height)}cm 를 통과 못 함$how';
    }
    final used = placed.fold<double>(0, (s, p) => s + p.volume);
    if (used + b.volume > trunk.usableVolume) return '남은 부피 부족';
    final shaped = trunk.hasTailgateModel || trunk.frontProfile != null;
    if (b.soft && b.compressibility > 0) {
      return '${(b.compressibility * 100).round()}% 눌러도 빈 자리 없음';
    }
    return shaped ? '빈 자리 없음 (등받이·테일게이트 기울기 반영)' : '빈 자리 없음';
  }

  static String _cm(double m) => (m * 100).round().toString();
}
