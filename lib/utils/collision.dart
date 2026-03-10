import '../models/trim_box.dart';
import '../models/trunk_space.dart';

/// 충돌 감지 유틸리티
class CollisionDetector {
  final TrunkSpace space;

  const CollisionDetector(this.space);

  /// 두 박스가 겹치는지 확인 (AABB)
  bool boxesOverlap(TrimBox a, TrimBox b) {
    if (a.id == b.id) return false;
    return a.x < b.x + b.effectiveW &&
        a.x + a.effectiveW > b.x &&
        a.z < b.z + b.effectiveD &&
        a.z + a.effectiveD > b.z &&
        a.y < b.y + b.h &&
        a.y + a.h > b.y;
  }

  /// 박스가 트렁크 경계를 벗어나는지 확인
  bool isOutOfBounds(TrimBox box) {
    return box.x < -0.001 ||
        box.z < -0.001 ||
        box.x + box.effectiveW > space.w + 0.001 ||
        box.z + box.effectiveD > space.d + 0.001;
  }

  /// 박스가 트렁크 높이를 초과하는지 확인 (위치별 천장 높이 반영)
  bool isOverHeight(TrimBox box) {
    // 박스의 앞/뒤 z 위치에서 천장 높이를 각각 확인
    final ceilAtZ1 = space.ceilingHeightAt(box.z);
    final ceilAtZ2 = space.ceilingHeightAt(box.z + box.effectiveD);
    final minCeil = ceilAtZ1 < ceilAtZ2 ? ceilAtZ1 : ceilAtZ2;
    return box.y + box.h > minCeil + 0.001;
  }

  /// 박스가 왼쪽 휠하우스와 겹치는지 확인
  bool overlapsLeftWheelhouse(TrimBox box) {
    final lw = space.leftWheelhouse;
    // 왼쪽 휠하우스: x=[0, lw.w], z=[0, lw.d] (뒷좌석/뒷축 쪽)
    return box.x < lw.w &&
        box.x + box.effectiveW > 0 &&
        box.z < lw.d &&
        box.z + box.effectiveD > 0 &&
        box.y < lw.h &&
        box.y + box.h > 0;
  }

  /// 박스가 오른쪽 휠하우스와 겹치는지 확인
  bool overlapsRightWheelhouse(TrimBox box) {
    final rw = space.rightWheelhouse;
    // 오른쪽 휠하우스: x=[space.w-rw.w, space.w], z=[0, rw.d] (뒷좌석/뒷축 쪽)
    return box.x < space.w &&
        box.x + box.effectiveW > space.w - rw.w &&
        box.z < rw.d &&
        box.z + box.effectiveD > 0 &&
        box.y < rw.h &&
        box.y + box.h > 0;
  }

  /// 특정 박스가 충돌 상태인지 종합 판정
  bool hasCollision(TrimBox box, List<TrimBox> allBoxes) {
    if (isOutOfBounds(box)) return true;
    if (isOverHeight(box)) return true;
    if (overlapsLeftWheelhouse(box)) return true;
    if (overlapsRightWheelhouse(box)) return true;
    for (final other in allBoxes) {
      if (boxesOverlap(box, other)) return true;
    }
    return false;
  }

  /// 모든 충돌 박스 ID 반환
  Set<String> findAllCollisions(List<TrimBox> boxes) {
    final colliding = <String>{};
    for (final box in boxes) {
      if (isOutOfBounds(box) ||
          isOverHeight(box) ||
          overlapsLeftWheelhouse(box) ||
          overlapsRightWheelhouse(box)) {
        colliding.add(box.id);
      }
      for (final other in boxes) {
        if (boxesOverlap(box, other)) {
          colliding.add(box.id);
          colliding.add(other.id);
        }
      }
    }
    return colliding;
  }
}
