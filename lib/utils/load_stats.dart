import '../models/trim_box.dart';
import '../models/trunk_space.dart';

/// 화면에 보여 주는 적재 통계 — 캔버스 오버레이, 패널 통계, 공유 카드가 모두 이것을 쓴다.
///
/// 자동배치가 못 넣은 짐은 테일게이트 밖(z ≥ d − 0.005)에 세워 두는데, 그 짐은 트렁크에
/// 실린 것이 아니므로 통계에서 뺀다 ([PackingAdvisor] 와 같은 기준). 부피는 자동배치의
/// 적재율과 같은 정의(공칭 부피 / `usableVolume`)라서 판정 문구의 % 와 일치한다.
class LoadStats {
  /// 트렁크 밖에 세워 둔 짐으로 보는 경계 여유
  static const double parkedTol = 0.005;

  final TrunkSpace space;

  /// 트렁크 안에 있는 짐
  final List<TrimBox> inside;

  /// 트렁크 밖에 세워 둔 짐 (못 넣은 짐)
  final List<TrimBox> parked;

  LoadStats._(this.space, this.inside, this.parked);

  factory LoadStats.of(Iterable<TrimBox> boxes, TrunkSpace space) {
    final inside = <TrimBox>[];
    final parked = <TrimBox>[];
    for (final b in boxes) {
      (isParked(b, space) ? parked : inside).add(b);
    }
    return LoadStats._(space, inside, parked);
  }

  static bool isParked(TrimBox box, TrunkSpace space) =>
      box.z >= space.d - parkedTol;

  /// 실린 짐의 공칭 부피 합 (m³)
  double get usedVolume => inside.fold(0.0, (sum, b) => sum + b.volume);

  /// 실사용 트렁크 부피 (m³)
  double get totalVolume => space.usableVolume;

  int get usedLiters => (usedVolume * 1000).round();
  int get totalLiters => (totalVolume * 1000).round();
  int get remainingLiters => (totalLiters - usedLiters).clamp(0, 999999);

  /// 부피 적재율 (%)
  double get volumePercent {
    final total = totalVolume;
    if (total <= 0) return 0;
    return (usedVolume / total * 100).clamp(0, 999).toDouble();
  }

  /// 바닥 면적 점유 비율 (0..1) — 휠하우스를 뺀 바닥 대비, 실린 짐의 바닥면 합
  double get areaRatio {
    final floor = space.w * space.d -
        space.leftWheelhouse.w * space.leftWheelhouse.d -
        space.rightWheelhouse.w * space.rightWheelhouse.d;
    if (floor <= 0) return 0;
    final used =
        inside.fold(0.0, (sum, b) => sum + b.effectiveW * b.effectiveD);
    return (used / floor).clamp(0.0, 1.0).toDouble();
  }

  /// 가장 높은 윗면 (눌러 넣은 연질 짐은 눌린 높이 기준)
  double get maxTop => inside.fold(0.0, (m, b) => b.top > m ? b.top : m);

  /// 천장까지 남은 높이 (cm, 음수 없음)
  int get remainingHeightCm =>
      ((space.h - maxTop) * 100).round().clamp(0, 9999);
}
