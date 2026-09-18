import 'dart:math' as math;
import 'dart:ui' show Color;

import '../models/trim_box.dart';
import '../models/trunk_space.dart';
import 'camera.dart';
import 'depth_sort.dart';
import 'fixtures.dart';
import 'gear_shapes.dart';
import 'geometry.dart';
import 'mesh.dart';
import 'vec3.dart';

/// 페인터가 "무엇을 어디에 어떤 순서로" 그리는지를 정하는 순수 함수들.
/// 페인터와 테스트가 같은 함수를 쓰므로, 그림과 물리(`TrunkSpace`·`CollisionDetector`)의
/// 일치를 캔버스 없이 검증할 수 있다.

/// 뒤→앞 정렬 대상 하나 (고정물 또는 박스, 또는 순환을 풀려고 자른 그 조각)
class SceneObject {
  /// 정렬에 쓰는 경계 상자 (조각이면 조각의 상자)
  final Aabb aabb;

  /// 원래 물체 전체의 경계 상자 (라벨·그림자·충돌 와이어는 이걸로 그린다)
  final Aabb fullAabb;
  final Color color;
  final TrimBox? box;
  final Mesh mesh;
  final double alpha;
  final bool outline;
  final int fadeSide;

  /// [sceneObjects] 목록에서의 원래 물체 번호 (조각들은 같은 번호)
  final int origin;

  /// 이 물체의 조각 중 가장 먼저 그려지는가 → 접촉 그림자를 같이 그린다
  final bool isFirstPart;

  /// 이 물체의 조각 중 가장 나중에 그려지는가 → 라벨·배지·충돌 와이어를 같이 그린다
  final bool isLastPart;

  const SceneObject(
    this.aabb,
    this.color,
    this.box,
    this.mesh, {
    this.alpha = 1.0,
    this.outline = true,
    this.fadeSide = 0,
    this.origin = 0,
    Aabb? fullAabb,
    this.isFirstPart = true,
    this.isLastPart = true,
  }) : fullAabb = fullAabb ?? aabb;

  bool get isFixture => box == null;
  bool get isSplit => !(isFirstPart && isLastPart) || !identical(aabb, fullAabb);

  SceneObject _with({Aabb? aabb, Mesh? mesh, bool? first, bool? last}) =>
      SceneObject(
        aabb ?? this.aabb,
        color,
        box,
        mesh ?? this.mesh,
        alpha: alpha,
        outline: outline,
        fadeSide: fadeSide,
        origin: origin,
        fullAabb: fullAabb,
        isFirstPart: first ?? isFirstPart,
        isLastPart: last ?? isLastPart,
      );
}

/// 박스와 같이 뒤→앞 정렬해야 하는 고정물 전부 (휠하우스 아치, 프레임, 차체 윤곽)
List<FixtureObject> buildSceneFixtures(TrunkSpace space) {
  final out = <FixtureObject>[];
  for (final left in [true, false]) {
    final mesh = wheelhouseMesh(space, left: left);
    if (mesh == null) continue;
    out.add(FixtureObject(
      left ? Aabb.leftWheelhouse(space) : Aabb.rightWheelhouse(space),
      mesh,
      wheelhouseColor,
    ));
  }
  out.addAll(frameFixtures(space));
  out.addAll(bodyFixtures(space));
  return out;
}

/// 그릴 물체 목록 (정렬 전): 고정물 다음에 박스
List<SceneObject> sceneObjects(
  TrunkSpace space,
  Iterable<TrimBox> boxes, {
  List<FixtureObject>? fixtures,
}) {
  final out = <SceneObject>[];
  for (final f in fixtures ?? buildSceneFixtures(space)) {
    out.add(SceneObject(f.aabb, f.color, null, f.mesh,
        alpha: f.alpha,
        outline: f.outline,
        fadeSide: f.fadeSide,
        origin: out.length));
  }
  for (final b in boxes) {
    out.add(SceneObject(Aabb.fromBox(b), b.color, b, gearMesh(b),
        origin: out.length));
  }
  return out;
}

/// 한 프레임에서 순환을 풀려고 물체를 자르는 최대 횟수
const int maxDepthSplits = 24;

/// 페인터가 쓰는 그리기 순서 (먼저 그리는 것부터).
///
/// 물체 사이는 AABB 분리 평면 위상 정렬([DepthGraph]), 물체 안은 볼록 메시라 순서가
/// 필요 없다. 세 물체가 돌아가며 서로를 가리는 순환(긴 휠하우스 + 그 위에 얹힌 짐 +
/// 옆에 세운 짐 같은 흔한 배치)은 어떤 순서로도 맞게 그릴 수 없으므로, 순환에 든 물체
/// 하나를 이웃의 면 평면으로 잘라 두 조각으로 만들어 푼다 (Newell 방식). 조각은 절단선을
/// 긋지 않아 이어 그리면 원래 물체와 같아 보인다.
List<SceneObject> sceneDrawOrder(
  TrunkSpace space,
  Iterable<TrimBox> boxes,
  OrbitCamera camera, {
  List<FixtureObject>? fixtures,
}) {
  var parts = sceneObjects(space, boxes, fixtures: fixtures);
  final cam = camera.position;
  var graph = DepthGraph([for (final o in parts) o.aabb], cam);

  for (var splits = 0; splits < maxDepthSplits; splits++) {
    final cycle = graph.findCycle();
    if (cycle == null) break;
    final split = _chooseSplit(parts, cycle, cam);
    if (split == null) break; // 못 푸는 순환 → DepthGraph.order 가 먼 것부터 끊는다
    final x = parts[split.index];
    final lo = Aabb(x.aabb.x1, x.aabb.y1, x.aabb.z1, //
        split.axis == 0 ? split.value : x.aabb.x2,
        split.axis == 1 ? split.value : x.aabb.y2,
        split.axis == 2 ? split.value : x.aabb.z2);
    final hi = Aabb(
        split.axis == 0 ? split.value : x.aabb.x1,
        split.axis == 1 ? split.value : x.aabb.y1,
        split.axis == 2 ? split.value : x.aabb.z1,
        x.aabb.x2,
        x.aabb.y2,
        x.aabb.z2);
    parts = [
      ...parts.sublist(0, split.index),
      x._with(
          aabb: lo,
          mesh: clipMesh(x.mesh, split.axis, split.value, keepBelow: true)),
      x._with(
          aabb: hi,
          mesh: clipMesh(x.mesh, split.axis, split.value, keepBelow: false)),
      ...parts.sublist(split.index + 1),
    ];
    graph = DepthGraph([for (final o in parts) o.aabb], cam);
  }

  final ordered = [for (final i in graph.order()) parts[i]];
  if (ordered.length == parts.length && ordered.every((o) => !o.isSplit)) {
    return ordered;
  }
  // 조각난 물체: 그림자는 첫 조각, 라벨·와이어는 마지막 조각과 함께
  final firstAt = <int, int>{}, lastAt = <int, int>{};
  for (var i = 0; i < ordered.length; i++) {
    firstAt.putIfAbsent(ordered[i].origin, () => i);
    lastAt[ordered[i].origin] = i;
  }
  return [
    for (var i = 0; i < ordered.length; i++)
      ordered[i]._with(
        first: firstAt[ordered[i].origin] == i,
        last: lastAt[ordered[i].origin] == i,
      ),
  ];
}

class _Split {
  final int index;
  final int axis;
  final double value;
  const _Split(this.index, this.axis, this.value);
}

/// 순환 c[0] → c[1] → … → c[0] (그리는 순서) 을 끊는 절단을 고른다.
/// 물체 X 를 순환 속 이웃 Y 의 면 평면으로 잘랐을 때, 두 조각 모두에서
/// "앞 이웃 → 조각 → 뒤 이웃" 제약이 동시에 남지 않으면 그 순환은 풀린다.
_Split? _chooseSplit(List<SceneObject> parts, List<int> cycle, Vec3 cam) {
  const margin = 0.004; // 너무 얇은 조각은 만들지 않는다
  final k = cycle.length;
  if (k < 2) return null;

  bool mustPrecede(Aabb a, Aabb b) => depthOrder(a, b, cam) < 0; // a 먼저

  _Split? best;
  var bestSize = -1.0;
  for (var ci = 0; ci < k; ci++) {
    final xi = cycle[ci];
    final x = parts[xi].aabb;
    final prev = parts[cycle[(ci - 1 + k) % k]].aabb;
    final next = parts[cycle[(ci + 1) % k]].aabb;
    for (final y in [prev, next]) {
      for (var axis = 0; axis < 3; axis++) {
        for (final value in [y.minOn(axis), y.maxOn(axis)]) {
          if (value <= x.minOn(axis) + margin || value >= x.maxOn(axis) - margin) {
            continue;
          }
          final lo = Aabb(x.x1, x.y1, x.z1, axis == 0 ? value : x.x2,
              axis == 1 ? value : x.y2, axis == 2 ? value : x.z2);
          final hi = Aabb(axis == 0 ? value : x.x1, axis == 1 ? value : x.y1,
              axis == 2 ? value : x.z1, x.x2, x.y2, x.z2);
          final broken = [lo, hi].every(
              (p) => !(mustPrecede(prev, p) && mustPrecede(p, next)));
          if (!broken) continue;
          // 되도록 큰 물체를, 되도록 가운데에서 자른다 (조각이 덜 잘게 나뉜다)
          final size = math.min(value - x.minOn(axis), x.maxOn(axis) - value);
          if (size > bestSize) {
            bestSize = size;
            best = _Split(xi, axis, value);
          }
        }
      }
    }
  }
  return best;
}

/// 페인터가 그리는 껍데기 면 (헤드레스트 구간 처리 포함)
List<ShellFace> drawnShell(TrunkSpace space, {int stations = 10}) {
  final seat = seatLayout(space);
  return buildTrunkShell(
    space,
    stations: stations,
    headrestZoneY: (seat?.hasHeadrests ?? false) ? seat!.topY : null,
    headrestRecess: seat?.recess ?? 0,
  );
}

/// 닫힌 테일게이트 안쪽 면이 양쪽 벽과 만나는 선 [왼쪽, 오른쪽] (점선으로 그린다).
/// 이 선 뒤(+z)로는 짐을 놓을 수 없다. 테일게이트 모델이 없으면 빈 목록.
List<List<Vec3>> tailgateLimitPolylines(TrunkSpace space, {double inset = 0.004}) {
  if (!space.hasTailgateModel) return const [];
  final prof = rearProfilePolyline(space);
  if (prof.length < 2) return const [];
  return [
    [
      for (final p in prof)
        Vec3(space.xMinAt(p.z, p.y) + inset, p.y, p.z),
    ],
    [
      for (final p in prof)
        Vec3(space.xMaxAt(p.z, p.y) - inset, p.y, p.z),
    ],
  ];
}

/// 천장 높이에서의 닫힘 한계를 바닥에 내린 선 (없으면 null)
List<Vec3>? tailgateLimitFloorLine(TrunkSpace space) {
  if (!space.hasTailgateModel) return null;
  final zTop = rearProfilePolyline(space).last.z;
  if (space.d - zTop <= 0.01) return null;
  return [
    Vec3(space.xMinAt(zTop, 0), 0.002, zTop),
    Vec3(space.xMaxAt(zTop, 0), 0.002, zTop),
  ];
}

/// 헤드레스트 구간의 적재 한계면 (등받이 프로필의 수직 구간). 실제 면은 없고
/// 헤드레스트 앞면이 놓이는 평면이라 외곽을 점선으로 그린다. 법선은 짐칸 쪽(+z).
/// 헤드레스트 구간이 없으면 null (등받이 면 자체가 한계).
Face? seatLimitFace(TrunkSpace space) {
  final seat = seatLayout(space);
  if (seat == null || !seat.hasHeadrests) return null;
  final z = seat.planeZ, y0 = seat.topY, y1 = seat.ceilY;
  return Face([
    Vec3(space.xMinAt(z, y0), y0, z),
    Vec3(space.xMaxAt(z, y0), y0, z),
    Vec3(space.xMaxAt(z, y1), y1, z),
    Vec3(space.xMinAt(z, y1), y1, z),
  ], const Vec3(0, 0, 1));
}

/// 2열을 앞으로 당겨 생긴 바닥 빈틈 (z ∈ [0, floorStartZ]) 의 네 꼭짓점. 없으면 null.
List<Vec3>? seatGapStrip(TrunkSpace space, {double y = 0.0012}) {
  final gapZ = space.floorStartZ.clamp(0.0, space.d).toDouble();
  if (gapZ <= 0.005) return null;
  return [
    Vec3(0, y, 0),
    Vec3(space.w, y, 0),
    Vec3(space.w, y, gapZ),
    Vec3(0, y, gapZ),
  ];
}
