// 적재 엔진 검증용 공용 도구 (테스트 파일이 아님 — *_test.dart 가 아니라서 실행되지 않는다).
//
// 원칙
// - 유효성의 단일 진실은 CollisionDetector / SupportRule 이다. 여기서는 그것을
//   그대로 부르는 검사와, 그것과 독립적으로 트렁크 형상 함수만으로 만든
//   점 표본 오라클(pointOracleViolations)을 함께 둔다. 두 검사가 어긋나면
//   판정기 쪽 버그다.
// - 실제 장비는 앱과 똑같이 gearPhysicsFor 로 물리 속성을 매긴다.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/gear_physics.dart';
import 'package:trimbox/models/support.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/utils/collision.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

const Color kGrey = Color(0xFF888888);

/// 경계 허용 오차(5mm) + 부동소수점 여유
const double kBoundsEps = CollisionDetector.boundsTol + 1e-6;

/// 치수(cm)로 박스 생성
TrimBox cmBox(
  String id,
  double wCm,
  double dCm,
  double hCm, {
  bool soft = false,
  double compress = 0,
  double kg = 0,
  bool access = false,
  bool upright = false,
  double x = 0,
  double y = 0,
  double z = 0,
  int rotY = 0,
}) =>
    TrimBox(
      id: id,
      label: id,
      w: wCm / 100,
      d: dCm / 100,
      h: hCm / 100,
      x: x,
      y: y,
      z: z,
      rotY: rotY,
      color: kGrey,
      soft: soft,
      compressibility: compress,
      weightKg: kg,
      accessPriority: access,
      keepUpright: upright,
    );

/// 카탈로그 항목의 물리 속성 (앱의 add_box_dialog 와 같은 호출)
GearPhysics physicsOf(GearCatalogItem item) => gearPhysicsFor(
      label: item.label,
      category: item.category,
      subCategory: item.subCategory,
      wCm: item.w,
      dCm: item.d,
      hCm: item.h,
    );

/// 카탈로그 항목 → 앱이 만드는 것과 같은 TrimBox
TrimBox gearBox(String id, GearCatalogItem item) {
  final ph = physicsOf(item);
  return TrimBox(
    id: id,
    label: item.label,
    w: item.w / 100.0,
    d: item.d / 100.0,
    h: item.h / 100.0,
    color: kGrey,
    category: BoxCategory.values.firstWhere((c) => c.name == item.category,
        orElse: () => BoxCategory.custom),
    keepUpright: ph.upright,
    soft: ph.soft,
    compressibility: ph.compress,
    weightKg: ph.weightKg,
    accessPriority: ph.access,
  );
}

/// 추천 세트 → 박스 목록 (라벨이 카탈로그에 없으면 StateError)
List<TrimBox> bundleBoxes(GearBundleInfo bundle) {
  final catalog = {for (final c in gearCatalog()) c.label: c};
  final out = <TrimBox>[];
  for (var i = 0; i < bundle.itemLabels.length; i++) {
    final item = catalog[bundle.itemLabels[i]];
    if (item == null) {
      throw StateError('번들 "${bundle.name}" 의 "${bundle.itemLabels[i]}" 가 카탈로그에 없음');
    }
    out.add(gearBox('b$i', item));
  }
  return out;
}

/// 기울기·개구부·휠하우스가 없는 직육면체 트렁크
TrunkSpace plainTrunk(double w, double d, double h) => TrunkSpace(
      w: w,
      d: d,
      h: h,
      leftWheelhouse: const Wheelhouse(w: 0, d: 0, h: 0),
      rightWheelhouse: const Wheelhouse(w: 0, d: 0, h: 0),
    );

/// 검증 대상 트렁크 (이름 → 생성자)
Map<String, TrunkSpace> namedTrunks() => {
      'sorento': TrunkSpace.sorento(),
      'sorento7': TrunkSpace.sorento7(),
      'sorento+13': TrunkSpace.sorento(seatSlide: 0.13),
      'sorento+27': TrunkSpace.sorento(seatSlide: 0.27),
      'tucson': TrunkSpace.tucson(),
      'carnival': TrunkSpace.carnival(),
      'avante': TrunkSpace.avante(),
      'custom': TrunkSpace.custom(
        w: 1.0,
        d: 0.9,
        h: 0.7,
        leftWheelhouse: const Wheelhouse(w: 0.12, d: 0.35, h: 0.25),
        rightWheelhouse: const Wheelhouse(w: 0.12, d: 0.35, h: 0.25),
      ),
    };

/// 배치 결과를 입력 박스의 사본에 적용해 돌려준다 (입력은 건드리지 않는다)
List<TrimBox> applied(AutoLayoutResult r) {
  final out = <TrimBox>[];
  for (final p in r.placements) {
    final b = p.box.copyWith();
    p.applyTo(b);
    out.add(b);
  }
  return out;
}

/// 무작위 강체/연질 혼합 박스 (물리 속성 포함)
List<TrimBox> randomPhysicsBoxes(math.Random rnd, int n, {String prefix = 'r'}) =>
    List.generate(n, (i) {
      final w = 10 + rnd.nextInt(80).toDouble();
      final d = 10 + rnd.nextInt(60).toDouble();
      final h = 5 + rnd.nextInt(50).toDouble();
      final kind = rnd.nextInt(10);
      final soft = kind < 3;
      final liters = w * d * h / 1000;
      // 무게: 0(모름) 20%, 나머지는 밀도 0.05~0.6 kg/L → 20kg 이상도 섞인다
      final kg = rnd.nextInt(5) == 0
          ? 0.0
          : double.parse((liters * (0.05 + rnd.nextDouble() * 0.55))
              .clamp(0.1, 45.0)
              .toStringAsFixed(1));
      return cmBox('$prefix$i', w, d, h,
          soft: soft,
          compress: soft ? [0.0, 0.1, 0.3, 0.45][rnd.nextInt(4)] : 0,
          kg: soft ? math.min(kg, 6.0) : kg,
          access: kind == 9,
          upright: !soft && rnd.nextInt(3) == 0);
    });

/// 카탈로그에서 무작위로 뽑은 실제 장비 (중복 허용, '커스텀' 제외)
List<TrimBox> randomGear(math.Random rnd, int n, {String prefix = 'g'}) {
  final catalog = gearCatalog().where((c) => c.category != 'custom').toList();
  return List.generate(
      n, (i) => gearBox('$prefix$i', catalog[rnd.nextInt(catalog.length)]));
}

/// 박스 상태 스냅샷 (입력 불변성·결정성 비교용)
String snapshot(TrimBox b) =>
    '${b.id}|${b.w}|${b.d}|${b.h}|${b.x}|${b.y}|${b.z}|${b.rotY}|'
    '${b.squash}|${b.squashW}|${b.squashD}|${b.keepUpright}|${b.soft}|'
    '${b.compressibility}|${b.weightKg}|${b.accessPriority}|${b.loadOrder}';

/// 배치 서명 (결정성 비교용)
String placementSignature(AutoLayoutResult r) {
  final ps = List<BoxPlacement>.from(r.placements)
    ..sort((a, b) => a.box.id.compareTo(b.box.id));
  final placed = ps
      .map((p) =>
          '${p.box.id}@${p.x},${p.y},${p.z}:${p.w}x${p.d}x${p.h}'
          '~${p.squash},${p.squashW},${p.squashD}#${p.loadOrder}')
      .join(';');
  final unfit = (r.unfitBoxes.map((b) => b.id).toList()..sort()).join(',');
  return '$placed || $unfit';
}

/// CollisionDetector 와 독립적인 점 표본 오라클: 박스의 8개 꼭짓점과 모서리·면
/// 표본점이 모두 트렁크 실내(등받이·테일게이트 프로필, 좌우 경계, 천장) 안에 있고
/// 휠하우스 밖인지 본다. 반환값은 위반 설명 목록 (없으면 빈 목록).
List<String> pointOracleViolations(TrunkSpace t, TrimBox b,
    {double tol = kBoundsEps, int samples = 5}) {
  final out = <String>[];
  final x1 = b.x, x2 = b.x + b.effectiveW;
  final z1 = b.z, z2 = b.z + b.effectiveD;
  final y1 = b.y, y2 = b.top;
  if (y1 < -1e-9) out.add('바닥 아래 y=$y1');
  double lerp(double a, double c, int i) => a + (c - a) * i / (samples - 1);
  for (var iz = 0; iz < samples; iz++) {
    final z = lerp(z1, z2, iz);
    if (z < -tol || z > t.d + tol) {
      out.add('z 범위 밖 z=${z.toStringAsFixed(3)}');
      continue;
    }
    final zc = z.clamp(0.0, t.d);
    final ceil = t.interiorCeilingAt(zc);
    if (y2 > ceil + tol) {
      out.add('천장 초과 z=${z.toStringAsFixed(3)} top=${y2.toStringAsFixed(3)} > ${ceil.toStringAsFixed(3)}');
    }
    for (var iy = 0; iy < samples; iy++) {
      final y = lerp(y1, y2, iy);
      if (z > t.rearDepthAt(y) + tol) {
        out.add('테일게이트 선 뒤 (y=${y.toStringAsFixed(3)}, z=${z.toStringAsFixed(3)} > ${t.rearDepthAt(y).toStringAsFixed(3)})');
      }
      if (z < t.frontDepthAt(y) - tol) {
        out.add('등받이 안쪽 (y=${y.toStringAsFixed(3)}, z=${z.toStringAsFixed(3)} < ${t.frontDepthAt(y).toStringAsFixed(3)})');
      }
      final xmin = t.xMinAt(zc, y), xmax = t.xMaxAt(zc, y);
      if (x1 < xmin - tol || x2 > xmax + tol) {
        out.add('좌우 경계 밖 (y=${y.toStringAsFixed(3)}, z=${z.toStringAsFixed(3)}): '
            '[${x1.toStringAsFixed(3)}, ${x2.toStringAsFixed(3)}] ⊄ '
            '[${xmin.toStringAsFixed(3)}, ${xmax.toStringAsFixed(3)}]');
      }
    }
  }
  // 휠하우스 (열린 구간 겹침, 0.5mm 여유)
  const e = CollisionDetector.overlapTol;
  bool hitsWh(double wx1, double wx2, Wheelhouse wh) =>
      wh.w > 0 &&
      wh.d > 0 &&
      wh.h > 0 &&
      x1 < wx2 - e &&
      x2 > wx1 + e &&
      z1 < wh.zEnd - e &&
      z2 > wh.zStart + e &&
      y1 < wh.h - e &&
      y2 > e;
  if (hitsWh(0, t.leftWheelhouse.w, t.leftWheelhouse)) out.add('왼쪽 휠하우스와 겹침');
  if (hitsWh(t.w - t.rightWheelhouse.w, t.w, t.rightWheelhouse)) {
    out.add('오른쪽 휠하우스와 겹침');
  }
  return out;
}

/// 자동배치 결과가 지켜야 하는 모든 불변식. [input] 은 computeLayout 에 넘긴 목록.
void expectPackingInvariants(
  TrunkSpace trunk,
  List<TrimBox> input,
  AutoLayoutResult r, {
  String ctx = '',
  bool strictRigidOnSoft = true,
}) {
  final boxes = applied(r);
  final det = CollisionDetector(trunk);
  String why(String m) => ctx.isEmpty ? m : '[$ctx] $m';
  String dump(TrimBox b) =>
      '${b.id}(${b.label}) pos=(${b.x.toStringAsFixed(3)}, ${b.y.toStringAsFixed(3)}, ${b.z.toStringAsFixed(3)}) '
      'dims=${b.w}×${b.d}×${b.h} eff=${b.effectiveW.toStringAsFixed(3)}×${b.effectiveD.toStringAsFixed(3)}×${b.effectiveH.toStringAsFixed(3)} '
      'kg=${b.weightKg} soft=${b.soft}';

  // ── 1. 단일 진실 판정기 ──
  final coll = det.findAllCollisions(boxes);
  expect(coll, isEmpty,
      reason: why('충돌: ${[
        for (final b in boxes)
          if (coll.contains(b.id)) '${dump(b)} → ${det.describe(b, boxes)}'
      ]}'));
  expect(det.tailgateBlockers(boxes), isEmpty, reason: why('테일게이트 안 닫힘'));

  final byId = {for (final b in input) b.id: b};
  for (final b in boxes) {
    final others = boxes.where((o) => o.id != b.id).toList();
    expect(SupportRule.isSupported(b, others, trunk), isTrue,
        reason: why('부양: ${dump(b)}'));
    expect(b.rotY, 0, reason: why('rotY 정규화: ${dump(b)}'));

    // ── 2. 독립 기하 검사 ──
    expect(b.z + b.effectiveD, lessThanOrEqualTo(trunk.rearDepthAt(b.top) + kBoundsEps),
        reason: why('테일게이트 한계: ${dump(b)}'));
    expect(b.z, greaterThanOrEqualTo(trunk.frontDepthAt(b.top) - kBoundsEps),
        reason: why('등받이 한계: ${dump(b)}'));
    final ap = trunk.aperture;
    if (ap != null &&
        b.z + b.effectiveD > trunk.d - ap.frameDepth + CollisionDetector.overlapTol + 1e-9) {
      final half = ap.widthAt(b.top) / 2, mid = trunk.w / 2;
      expect(b.x, greaterThanOrEqualTo(mid - half - kBoundsEps),
          reason: why('개구부 프레임 왼쪽: ${dump(b)}'));
      expect(b.x + b.effectiveW, lessThanOrEqualTo(mid + half + kBoundsEps),
          reason: why('개구부 프레임 오른쪽: ${dump(b)}'));
    }
    expect(pointOracleViolations(trunk, b), isEmpty, reason: why('점 표본 오라클: ${dump(b)}'));
    // 2열 슬라이드로 생긴 바닥 빈틈(z < floorStartZ): 바닥에 놓인 짐은 깊이의 절반
    // 이상이 실제 바닥 위에 있어야 한다 (SupportRule 과 독립적으로 계산)
    if (b.y <= SupportRule.heightTol && trunk.floorStartZ > 0 && b.effectiveD > 0) {
      final onFloor = (b.z + b.effectiveD) - math.max(b.z, trunk.floorStartZ);
      expect(onFloor / b.effectiveD, greaterThanOrEqualTo(SupportRule.minRatio - 1e-9),
          reason: why('바닥 빈틈 위: ${dump(b)}'));
    }

    // ── 3. 치수·압축 ──
    final orig = byId[b.id]!;
    final od = [orig.w, orig.d, orig.h]..sort();
    final nd = [b.w, b.d, b.h]..sort();
    for (var i = 0; i < 3; i++) {
      expect(nd[i], closeTo(od[i], 1e-9), reason: why('치수는 원래 치수의 순열이어야: ${dump(b)}'));
    }
    if (orig.keepUpright) {
      expect(b.h, closeTo(orig.h, 1e-9), reason: why('세워야 하는 짐이 눕혀짐: ${dump(b)}'));
    }
    final squashes = [b.squash, b.squashW, b.squashD];
    for (final s in squashes) {
      expect(s, greaterThanOrEqualTo(0), reason: why('음수 압축: ${dump(b)}'));
    }
    if (orig.soft && orig.compressibility > 0) {
      expect(squashes.where((s) => s > 1e-9).length, lessThanOrEqualTo(1),
          reason: why('두 축 이상 압축: $squashes ${dump(b)}'));
      expect(squashes.reduce(math.max), lessThanOrEqualTo(orig.compressibility + 1e-9),
          reason: why('압축률 초과: $squashes ${dump(b)}'));
    } else {
      expect(squashes.reduce(math.max), 0, reason: why('강체가 압축됨: ${dump(b)}'));
    }

    // ── 4. 무게 규칙 ──
    if (b.weightKg >= AutoLayoutEngine.floorOnlyKg) {
      expect(b.y, 0, reason: why('20kg 이상은 바닥: ${dump(b)}'));
    }
    if (!b.soft && b.weightKg >= 5) {
      // (a) 하중 기준: 연질 짐을 빼고도 50% 이상 지지돼야 한다 (항상 검사)
      final rigidOthers = others.where((o) => !o.soft).toList();
      expect(SupportRule.isSupported(b, rigidOthers, trunk), isTrue,
          reason: why('단단한 ${dump(b)} 가 연질 짐에 얹혀 있다 (연질 제외 지지 '
              '${(SupportRule.supportRatio(b, b.y, rigidOthers, trunk) * 100).round()}%)'));
      // (b) 접촉 기준: supportersAt 에 연질 짐이 없어야 한다 (조언 규칙과 같은 정의)
      if (strictRigidOnSoft) {
        final softUnder =
            SupportRule.supportersAt(b, b.y, others).where((s) => s.soft).toList();
        expect(softUnder, isEmpty,
            reason: why('단단한 ${dump(b)} 가 연질 ${softUnder.map(dump)} 위'));
      }
    }
  }

  // ── 5. 회계 ──
  final placedIds = r.placements.map((p) => p.box.id).toList();
  final unfitIds = r.unfitBoxes.map((b) => b.id).toList();
  expect(placedIds.toSet().length, placedIds.length, reason: why('배치 중복'));
  expect(unfitIds.toSet().length, unfitIds.length, reason: why('미적재 중복'));
  expect(placedIds.toSet().intersection(unfitIds.toSet()), isEmpty,
      reason: why('배치와 미적재에 동시에 있음'));
  expect({...placedIds, ...unfitIds}, input.map((b) => b.id).toSet(),
      reason: why('입력 = 배치 + 미적재'));
  expect(r.placedCount + r.unfitBoxes.length, input.length);
  expect(r.totalCount, input.length);
  for (final p in r.placements) {
    expect(identical(p.box, byId[p.box.id]), isTrue,
        reason: why('placement.box 는 입력 박스 그대로여야'));
  }
  for (final u in r.unfitBoxes) {
    expect(identical(u, byId[u.id]), isTrue, reason: why('unfitBoxes 는 입력 박스 그대로여야'));
    expect(r.unfitReasons[u.id], isNotNull, reason: why('${u.id} 사유 없음'));
    expect(r.unfitReasons[u.id]!.trim(), isNotEmpty, reason: why('${u.id} 사유 빈 문자열'));
  }
  expect(r.unfitReasons.keys.toSet(), unfitIds.toSet(), reason: why('사유 키 = 미적재'));
  expect(r.allBoxesFit, r.unfitBoxes.isEmpty);
  final orders = r.placements.map((p) => p.loadOrder).toList()..sort();
  expect(orders, List.generate(orders.length, (i) => i + 1), reason: why('loadOrder 1..n'));

  // ── 6. 적재율 ──
  expect(r.utilizationPercent, inInclusiveRange(0, 100));
  final usable = trunk.usableVolume;
  if (usable > 0) {
    final nominal = r.placements.fold<double>(0, (s, p) => s + p.box.volume);
    expect(r.utilizationPercent,
        closeTo((nominal / usable * 100).clamp(0, 100).toDouble(), 1e-6),
        reason: why('적재율 = 공칭 부피 / 실사용 부피'));
  }
}
