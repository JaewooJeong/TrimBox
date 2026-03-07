import 'dart:math' as math;

import 'trim_box.dart';
import 'trunk_space.dart';

/// 자동 배치 전략
enum LayoutStrategy {
  balanced,       // 기본: 활용도 + 접근성 균형
  maxUtilization, // 최대 밀집 배치
  easyAccess,     // 자주 쓰는 짐이 입구 가까이
}

extension LayoutStrategyExt on LayoutStrategy {
  String get label => switch (this) {
        LayoutStrategy.balanced => '균형 배치',
        LayoutStrategy.maxUtilization => '최대 적재',
        LayoutStrategy.easyAccess => '접근 우선',
      };
}

/// 배치 결과
class AutoLayoutResult {
  final List<BoxPlacement> placements;
  final double utilizationPercent;
  final bool allBoxesFit;
  final List<TrimBox> unfitBoxes;
  final LayoutStrategy strategy;

  const AutoLayoutResult({
    required this.placements,
    required this.utilizationPercent,
    required this.allBoxesFit,
    required this.unfitBoxes,
    required this.strategy,
  });
}

/// 개별 박스 배치 정보
class BoxPlacement {
  final TrimBox box;
  final double x;
  final double y;
  final double z;
  final bool rotated;
  final int loadOrder; // 1 = 가장 먼저 적재 (가장 깊숙이)

  const BoxPlacement({
    required this.box,
    required this.x,
    required this.y,
    required this.z,
    required this.rotated,
    required this.loadOrder,
  });
}

/// 3D 극점 (Extreme Point)
class _EP {
  final double x, y, z;
  const _EP(this.x, this.y, this.z);

  @override
  String toString() => 'EP($x, $y, $z)';
}

/// 배치된 박스의 AABB
class _PlacedAABB {
  final double x1, y1, z1; // min corner
  final double x2, y2, z2; // max corner
  final bool isWheelhouse;

  const _PlacedAABB(this.x1, this.y1, this.z1, this.x2, this.y2, this.z2,
      {this.isWheelhouse = false});

  bool overlaps(_PlacedAABB other) {
    return x1 < other.x2 &&
        x2 > other.x1 &&
        y1 < other.y2 &&
        y2 > other.y1 &&
        z1 < other.z2 &&
        z2 > other.z1;
  }

  bool containsPoint(double px, double py, double pz) {
    return px >= x1 && px <= x2 && py >= y1 && py <= y2 && pz >= z1 && pz <= z2;
  }
}

/// EP-BFD 기반 자동 배치 엔진
class AutoLayoutEngine {
  /// 주어진 박스들을 트렁크에 자동 배치
  static AutoLayoutResult computeLayout(
    TrunkSpace trunk,
    List<TrimBox> boxes, {
    LayoutStrategy strategy = LayoutStrategy.balanced,
  }) {
    if (boxes.isEmpty) {
      return AutoLayoutResult(
        placements: [],
        utilizationPercent: 0,
        allBoxesFit: true,
        unfitBoxes: [],
        strategy: strategy,
      );
    }

    // 1. 박스 정렬 (BFD — Best Fit Decreasing)
    final sorted = _sortBoxes(boxes, strategy);

    // 2. 휠하우스를 가상 배치 박스로 추가
    final placed = <_PlacedAABB>[];
    _addWheelhouseBlocks(trunk, placed);

    // 3. 극점 초기화
    final eps = <_EP>[const _EP(0, 0, 0)];

    // 4. 각 박스를 최적 위치에 배치
    final placements = <BoxPlacement>[];
    final unfitBoxes = <TrimBox>[];
    int loadOrder = 0;

    for (final box in sorted) {
      final placement = _findBestPlacement(
        trunk, box, eps, placed, strategy,
      );

      if (placement != null) {
        loadOrder++;
        final aabb = _PlacedAABB(
          placement.x,
          placement.y,
          placement.z,
          placement.x + (placement.rotated ? box.d : box.w),
          placement.y + box.h,
          placement.z + (placement.rotated ? box.w : box.d),
        );
        placed.add(aabb);
        placements.add(BoxPlacement(
          box: box,
          x: placement.x,
          y: placement.y,
          z: placement.z,
          rotated: placement.rotated,
          loadOrder: loadOrder,
        ));

        // 5. 새 극점 생성
        _generateExtremePoints(eps, aabb, placed, trunk);
      } else {
        unfitBoxes.add(box);
      }
    }

    // 6. 적재율 계산
    final utilization = _calculateUtilization(trunk, placements);

    return AutoLayoutResult(
      placements: placements,
      utilizationPercent: utilization,
      allBoxesFit: unfitBoxes.isEmpty,
      unfitBoxes: unfitBoxes,
      strategy: strategy,
    );
  }

  /// 3가지 전략으로 대안 레이아웃 생성
  static List<AutoLayoutResult> generateAlternatives(
    TrunkSpace trunk,
    List<TrimBox> boxes,
  ) {
    final results = <AutoLayoutResult>[];

    for (final strategy in LayoutStrategy.values) {
      results.add(computeLayout(trunk, boxes, strategy: strategy));
    }

    // 적재율 내림차순 정렬
    results.sort(
        (a, b) => b.utilizationPercent.compareTo(a.utilizationPercent));
    return results;
  }

  // ── 정렬 ──

  static List<TrimBox> _sortBoxes(List<TrimBox> boxes, LayoutStrategy strategy) {
    final sorted = List<TrimBox>.from(boxes);
    switch (strategy) {
      case LayoutStrategy.balanced:
        // 부피 내림차순
        sorted.sort((a, b) =>
            (b.w * b.d * b.h).compareTo(a.w * a.d * a.h));
        break;
      case LayoutStrategy.maxUtilization:
        // 바닥 면적 내림차순 (넓은 박스 먼저 → 빈틈 최소화)
        sorted.sort((a, b) =>
            (b.w * b.d).compareTo(a.w * a.d));
        break;
      case LayoutStrategy.easyAccess:
        // 높이 내림차순 (큰 박스 뒤에, 작은 박스 앞에)
        sorted.sort((a, b) =>
            (b.h).compareTo(a.h));
        break;
    }
    return sorted;
  }

  // ── 휠하우스 가상 블록 ──

  static void _addWheelhouseBlocks(TrunkSpace trunk, List<_PlacedAABB> placed) {
    final lw = trunk.leftWheelhouse;
    if (lw.w > 0 && lw.d > 0 && lw.h > 0) {
      // 왼쪽 휠하우스: x=[0, lw.w], z=[trunk.d-lw.d, trunk.d], y=[0, lw.h]
      placed.add(_PlacedAABB(
        0, 0, trunk.d - lw.d,
        lw.w, lw.h, trunk.d,
        isWheelhouse: true,
      ));
    }

    final rw = trunk.rightWheelhouse;
    if (rw.w > 0 && rw.d > 0 && rw.h > 0) {
      // 오른쪽 휠하우스: x=[trunk.w-rw.w, trunk.w], z=[trunk.d-rw.d, trunk.d], y=[0, rw.h]
      placed.add(_PlacedAABB(
        trunk.w - rw.w, 0, trunk.d - rw.d,
        trunk.w, rw.h, trunk.d,
        isWheelhouse: true,
      ));
    }
  }

  // ── 최적 배치 찾기 ──

  static _CandidatePlacement? _findBestPlacement(
    TrunkSpace trunk,
    TrimBox box,
    List<_EP> eps,
    List<_PlacedAABB> placed,
    LayoutStrategy strategy,
  ) {
    _CandidatePlacement? best;
    double bestScore = double.infinity;

    for (final ep in eps) {
      for (final rotated in [false, true]) {
        final bw = rotated ? box.d : box.w;
        final bd = rotated ? box.w : box.d;
        final bh = box.h;

        // Try the EP as-is, and also with x adjusted for taper
        final candidateXs = <double>{ep.x};
        // Adjust x to satisfy taper at this z
        final taper = trunk.taperAt(ep.z);
        final taperEnd = trunk.taperAt(ep.z + bd);
        final minTaper = math.max(taper, taperEnd);
        if (ep.x < minTaper) {
          candidateXs.add(minTaper);
        }

        for (final cx in candidateXs) {
          // 지지면(y) 계산: 이 ep 위치에서 실제 놓일 수 있는 y 높이
          final supportY = _findSupportY(cx, ep.z, bw, bd, ep.y, placed);

          if (_canPlace(trunk, cx, supportY, ep.z, bw, bd, bh, placed)) {
            final score = _placementScore(
              trunk, cx, supportY, ep.z, bw, bd, bh, strategy,
            );
            if (score < bestScore) {
              bestScore = score;
              best = _CandidatePlacement(cx, supportY, ep.z, rotated);
            }
          }
        }
      }
    }
    return best;
  }

  /// ep.y 이상에서 실제 지지면 y 값을 계산
  /// 해당 XZ 영역에 기존 박스가 있으면 그 위에 올림
  static double _findSupportY(
    double x, double z, double bw, double bd, double minY,
    List<_PlacedAABB> placed,
  ) {
    double supportY = minY;
    for (final p in placed) {
      if (p.isWheelhouse) continue;
      // XZ 겹침 확인
      final overlapX = math.min(x + bw, p.x2) - math.max(x, p.x1);
      final overlapZ = math.min(z + bd, p.z2) - math.max(z, p.z1);
      if (overlapX > 0 && overlapZ > 0) {
        // 50% 이상 겹쳐야 스태킹
        final overlapArea = overlapX * overlapZ;
        final boxArea = bw * bd;
        if (overlapArea >= boxArea * 0.5) {
          if (p.y2 > supportY) {
            supportY = p.y2;
          }
        }
      }
    }
    return supportY;
  }

  // ── 배치 가능 여부 확인 ──

  static bool _canPlace(
    TrunkSpace trunk,
    double x, double y, double z,
    double bw, double bd, double bh,
    List<_PlacedAABB> placed,
  ) {
    const eps = 0.001;

    // 1. 기본 경계 확인
    if (x < -eps || y < -eps || z < -eps) return false;
    if (x + bw > trunk.w + eps) return false;
    if (z + bd > trunk.d + eps) return false;
    if (y + bh > trunk.h + eps) return false;

    // 2. 천장 높이 확인 (박스의 전체 깊이 범위에서)
    // 가장 제한적인 위치(z가 가장 작은 쪽 = 뒤쪽)에서 확인
    final ceilingH = trunk.ceilingHeightAt(z);
    if (y + bh > ceilingH + eps) return false;

    // z + bd 끝점에서도 확인
    final ceilingHEnd = trunk.ceilingHeightAt(z + bd);
    if (y + bh > ceilingHEnd + eps) return false;

    // 3. 테이퍼 확인
    final taper = trunk.taperAt(z);
    if (taper > eps) {
      if (x < taper - eps) return false;
      if (x + bw > trunk.w - taper + eps) return false;
    }
    final taperEnd = trunk.taperAt(z + bd);
    if (taperEnd > eps) {
      if (x < taperEnd - eps) return false;
      if (x + bw > trunk.w - taperEnd + eps) return false;
    }

    // 4. 상단 좁아짐 확인 (높이가 있는 박스)
    if (y + bh > 0.1) {
      final narrow = trunk.topNarrowAt(z);
      final heightRatio = (y + bh) / trunk.h;
      final narrowAtHeight = narrow * heightRatio;
      if (narrowAtHeight > eps) {
        if (x < narrowAtHeight - eps) return false;
        if (x + bw > trunk.w - narrowAtHeight + eps) return false;
      }
    }

    // 5. 기존 박스와 충돌 확인
    final candidate = _PlacedAABB(x, y, z, x + bw, y + bh, z + bd);
    for (final p in placed) {
      if (candidate.overlaps(p)) return false;
    }

    return true;
  }

  // ── 배치 점수 (낮을수록 좋음) ──

  static double _placementScore(
    TrunkSpace trunk,
    double x, double y, double z,
    double bw, double bd, double bh,
    LayoutStrategy strategy,
  ) {
    switch (strategy) {
      case LayoutStrategy.balanced:
        // 바닥(y 낮음) → 뒤(z 낮음) → 중앙(x 중앙에 가깝게)
        final xCenter = (x + bw / 2 - trunk.w / 2).abs();
        return y * 10000 + z * 100 + xCenter * 10;

      case LayoutStrategy.maxUtilization:
        // 바닥(y 낮음) → 왼쪽(x 낮음) → 뒤(z 낮음)
        return y * 10000 + x * 100 + z * 10;

      case LayoutStrategy.easyAccess:
        // 바닥(y 낮음) → 앞(z 높음, 입구 가까이) → 중앙
        final xCenter = (x + bw / 2 - trunk.w / 2).abs();
        return y * 10000 - z * 100 + xCenter * 10;
    }
  }

  // ── 극점 생성 ──

  static void _generateExtremePoints(
    List<_EP> eps,
    _PlacedAABB aabb,
    List<_PlacedAABB> placed,
    TrunkSpace trunk,
  ) {
    // 배치된 박스의 3개 모서리에서 새 극점 생성
    final newEPs = [
      _EP(aabb.x2, aabb.y1, aabb.z1), // 오른쪽
      _EP(aabb.x1, aabb.y1, aabb.z2), // 앞쪽
      _EP(aabb.x1, aabb.y2, aabb.z1), // 위쪽
    ];

    for (final ep in newEPs) {
      // 트렁크 범위 내인지 확인
      if (ep.x < -0.001 || ep.x > trunk.w + 0.001) continue;
      if (ep.y < -0.001 || ep.y > trunk.h + 0.001) continue;
      if (ep.z < -0.001 || ep.z > trunk.d + 0.001) continue;

      // 기존 배치 박스 내부에 있는지 확인
      // Use negative epsilon so boundary points (valid EPs) are NOT rejected
      bool insideExisting = false;
      for (final p in placed) {
        if (p.containsPoint(ep.x - 0.001, ep.y - 0.001, ep.z - 0.001)) {
          insideExisting = true;
          break;
        }
      }
      if (!insideExisting) {
        eps.add(ep);
      }
    }

    // 기존 극점 중 새 박스 내부에 들어간 것 제거
    eps.removeWhere((ep) =>
        aabb.containsPoint(ep.x - 0.001, ep.y - 0.001, ep.z - 0.001));
  }

  // ── 적재율 계산 ──

  static double _calculateUtilization(
    TrunkSpace trunk,
    List<BoxPlacement> placements,
  ) {
    if (placements.isEmpty) return 0;

    final lhVol = trunk.leftWheelhouse.w *
        trunk.leftWheelhouse.d *
        trunk.leftWheelhouse.h;
    final rhVol = trunk.rightWheelhouse.w *
        trunk.rightWheelhouse.d *
        trunk.rightWheelhouse.h;
    final totalVol = trunk.w * trunk.d * trunk.h - lhVol - rhVol;
    if (totalVol <= 0) return 0;

    double boxVol = 0;
    for (final p in placements) {
      boxVol += p.box.w * p.box.d * p.box.h;
    }

    return (boxVol / totalVol * 100).clamp(0, 100);
  }
}

/// 내부 후보 배치 정보
class _CandidatePlacement {
  final double x, y, z;
  final bool rotated;
  const _CandidatePlacement(this.x, this.y, this.z, this.rotated);
}
