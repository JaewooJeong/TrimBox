import 'dart:math' as math;

import '../models/trim_box.dart';
import '../models/trunk_space.dart';

/// 충돌(배치 불가) 사유
enum CollisionKind {
  bounds, // 트렁크 경계 밖 (바닥·벽·테이퍼·C필러·개구부 프레임)
  ceiling, // 실내 천장 초과
  wheelhouse, // 휠하우스와 겹침
  tailgate, // 닫힌 테일게이트(또는 루프 헤더)에 걸림 → 문이 안 닫힘
  seatBack, // 뒤로 누운 2열 등받이에 걸림
  aperture, // 어떤 방향으로도 개구부를 통과할 수 없음
  overlap, // 다른 짐과 겹침
}

extension CollisionKindExt on CollisionKind {
  String get label => switch (this) {
        CollisionKind.bounds => '트렁크 경계 밖',
        CollisionKind.ceiling => '천장 초과',
        CollisionKind.wheelhouse => '휠하우스와 겹침',
        CollisionKind.tailgate => '테일게이트 닫힘 불가',
        CollisionKind.seatBack => '2열 등받이에 걸림',
        CollisionKind.aperture => '개구부 통과 불가',
        CollisionKind.overlap => '다른 짐과 겹침',
      };
}

/// 충돌 감지 — 배치 유효성의 단일 진실. 화면·자동배치·테스트가 모두 이것을 쓴다.
class CollisionDetector {
  final TrunkSpace space;

  const CollisionDetector(this.space);

  /// 겹침 판정 허용 오차 (0.5mm). 1cm 격자 스냅과 부동소수점 반올림으로
  /// 맞닿은 박스가 겹침으로 오판되는 것을 막는다.
  static const double overlapTol = 0.0005;

  /// 경계·천장·테일게이트 판정 허용 오차 (5mm)
  static const double boundsTol = 0.005;

  /// 두 박스가 겹치는지 확인 (AABB)
  bool boxesOverlap(TrimBox a, TrimBox b) {
    if (a.id == b.id) return false;
    const t = overlapTol;
    return a.x < b.x + b.effectiveW - t &&
        a.x + a.effectiveW > b.x + t &&
        a.z < b.z + b.effectiveD - t &&
        a.z + a.effectiveD > b.z + t &&
        a.y < b.top - t &&
        a.top > b.y + t;
  }

  /// 박스가 트렁크 경계를 벗어나는지 확인 (바닥 z 범위 + (z, y) 별 좌우 경계).
  /// 좌우 경계는 뒷좌석 쪽 테이퍼·C필러(z 작을수록 좁음)와 개구부 프레임
  /// (z ≥ d − frameDepth 에서 좁음)을 모두 반영하므로 박스의 앞·뒤 z 에서
  /// 각각 윗면 높이로 확인한다.
  bool isOutOfBounds(TrimBox box) {
    const tol = boundsTol;
    final z1 = box.z, z2 = box.z + box.effectiveD;
    if (box.x < -tol || z1 < -tol || z2 > space.d + tol) return true;
    final yTop = box.top;
    for (final z in [z1, z2]) {
      if (box.x < space.xMinAt(z, yTop) - tol ||
          box.x + box.effectiveW > space.xMaxAt(z, yTop) + tol) {
        return true;
      }
    }
    return false;
  }

  /// 박스가 실내 천장을 초과하는지 (뒷좌석 쪽 천장 드롭 반영).
  /// 테일게이트·헤더에 의한 뒤쪽 높이 제한은 [blocksTailgate] 가 따로 본다.
  bool isOverHeight(TrimBox box) {
    final c1 = space.interiorCeilingAt(box.z);
    final c2 = space.interiorCeilingAt(box.z + box.effectiveD);
    return box.top > math.min(c1, c2) + boundsTol;
  }

  /// 닫힌 테일게이트(또는 루프 헤더) 안쪽 면보다 뒤로 튀어나온 길이 (m).
  /// 0 이하면 문이 닫힌다. 프로필은 위로 갈수록 안쪽으로 들어오므로
  /// 박스 윗면 높이에서의 한계만 보면 된다.
  double tailgateOverhang(TrimBox box) {
    if (!space.hasTailgateModel) return 0;
    // 트렁크 밖에 세워 둔(미적재) 박스는 문을 막는 게 아니라 안 실린 것
    if (box.z >= space.d - boundsTol) return 0;
    final limit = space.rearDepthAt(box.top);
    return box.z + box.effectiveD - limit;
  }

  /// 이 박스 때문에 테일게이트가 닫히지 않는가
  bool blocksTailgate(TrimBox box) => tailgateOverhang(box) > boundsTol;

  /// 뒤로 누운 2열 등받이 안쪽으로 파고든 길이 (m). 등받이는 위로 갈수록
  /// 뒤로 오므로 박스 윗면 높이에서의 한계만 보면 된다.
  double seatBackIntrusion(TrimBox box) {
    if (space.frontProfile == null) return 0;
    if (box.z >= space.d - boundsTol) return 0; // 트렁크 밖
    return space.frontDepthAt(box.top) - box.z;
  }

  /// 2열 등받이에 걸리는가
  bool hitsSeatBack(TrimBox box) => seatBackIntrusion(box) > boundsTol;

  /// 어떤 방향으로도 개구부를 통과할 수 없는 박스인가 (위치와 무관).
  /// 세워서만 싣는 짐은 높이를 세운 채로만 통과를 시도한다.
  bool exceedsAperture(TrimBox box) {
    final ap = space.aperture;
    if (ap == null) return false;
    return !fitsThroughAperture(box.w, box.d, box.h, ap,
        keepUpright: box.keepUpright);
  }

  /// w×d×h 박스가 개구부 사다리꼴을 통과할 수 있는 단면 방향이 있는가.
  /// 단면 (가로 a, 세로 b)은 b ≤ 개구부 높이, a ≤ 높이 b 에서의 개구부 폭.
  static bool fitsThroughAperture(
    double w,
    double d,
    double h,
    Aperture ap, {
    bool keepUpright = false,
  }) {
    const tol = boundsTol;
    final sections = <(double, double)>[(w, h), (d, h)];
    if (!keepUpright) {
      sections.addAll([(w, d), (d, w), (h, w), (h, d)]);
    }
    for (final (a, b) in sections) {
      if (b <= ap.height + tol && a <= ap.widthAt(b) + tol) return true;
    }
    return false;
  }

  /// 박스가 왼쪽 휠하우스와 겹치는지 확인
  bool overlapsLeftWheelhouse(TrimBox box) {
    final lw = space.leftWheelhouse;
    // 왼쪽 휠하우스: x=[0, lw.w], z=[lw.zStart, lw.zEnd] (뒷좌석/뒷축 쪽)
    return box.x < lw.w &&
        box.x + box.effectiveW > 0 &&
        box.z < lw.zEnd &&
        box.z + box.effectiveD > lw.zStart &&
        box.y < lw.h &&
        box.top > 0;
  }

  /// 박스가 오른쪽 휠하우스와 겹치는지 확인
  bool overlapsRightWheelhouse(TrimBox box) {
    final rw = space.rightWheelhouse;
    // 오른쪽 휠하우스: x=[space.w-rw.w, space.w], z=[rw.zStart, rw.zEnd]
    return box.x < space.w &&
        box.x + box.effectiveW > space.w - rw.w &&
        box.z < rw.zEnd &&
        box.z + box.effectiveD > rw.zStart &&
        box.y < rw.h &&
        box.top > 0;
  }

  /// 트렁크 자체(다른 짐 제외)와의 충돌 사유들
  List<CollisionKind> _spaceViolations(TrimBox box) => [
        if (isOutOfBounds(box)) CollisionKind.bounds,
        if (isOverHeight(box)) CollisionKind.ceiling,
        if (overlapsLeftWheelhouse(box) || overlapsRightWheelhouse(box))
          CollisionKind.wheelhouse,
        if (blocksTailgate(box)) CollisionKind.tailgate,
        if (hitsSeatBack(box)) CollisionKind.seatBack,
        if (exceedsAperture(box)) CollisionKind.aperture,
      ];

  /// 특정 박스의 모든 충돌 사유 (없으면 빈 목록)
  List<CollisionKind> violations(TrimBox box, Iterable<TrimBox> allBoxes) {
    final out = _spaceViolations(box);
    for (final other in allBoxes) {
      if (boxesOverlap(box, other)) {
        out.add(CollisionKind.overlap);
        break;
      }
    }
    return out;
  }

  /// 사람이 읽을 사유 문장들 (cm 포함)
  List<String> describe(TrimBox box, Iterable<TrimBox> allBoxes) {
    final out = <String>[];
    for (final v in violations(box, allBoxes)) {
      switch (v) {
        case CollisionKind.ceiling:
          final c = math.min(space.interiorCeilingAt(box.z),
              space.interiorCeilingAt(box.z + box.effectiveD));
          out.add('천장 초과 +${_cm(box.top - c)}cm');
        case CollisionKind.tailgate:
          out.add('테일게이트 닫힘 불가 (+${_cm(tailgateOverhang(box))}cm 튀어나옴)');
        case CollisionKind.seatBack:
          out.add('2열 등받이에 걸림 (${_cm(seatBackIntrusion(box))}cm)');
        case CollisionKind.aperture:
          final ap = space.aperture!;
          out.add('개구부 ${_cm(ap.bottomWidth)}×${_cm(ap.height)}cm 통과 불가');
        default:
          out.add(v.label);
      }
    }
    return out;
  }

  /// 특정 박스가 충돌 상태인지 종합 판정
  bool hasCollision(TrimBox box, List<TrimBox> allBoxes) {
    if (isOutOfBounds(box)) return true;
    if (isOverHeight(box)) return true;
    if (overlapsLeftWheelhouse(box)) return true;
    if (overlapsRightWheelhouse(box)) return true;
    if (blocksTailgate(box)) return true;
    if (hitsSeatBack(box)) return true;
    if (exceedsAperture(box)) return true;
    for (final other in allBoxes) {
      if (boxesOverlap(box, other)) return true;
    }
    return false;
  }

  /// 모든 충돌 박스 ID 반환
  Set<String> findAllCollisions(List<TrimBox> boxes) {
    final colliding = <String>{};
    for (final box in boxes) {
      if (_spaceViolations(box).isNotEmpty) colliding.add(box.id);
      for (final other in boxes) {
        if (boxesOverlap(box, other)) {
          colliding.add(box.id);
          colliding.add(other.id);
        }
      }
    }
    return colliding;
  }

  /// 테일게이트가 닫히지 않게 하는 박스 ID 들
  Set<String> tailgateBlockers(Iterable<TrimBox> boxes) =>
      {for (final b in boxes) if (blocksTailgate(b)) b.id};

  static String _cm(double m) => (m * 100).round().toString();
}
