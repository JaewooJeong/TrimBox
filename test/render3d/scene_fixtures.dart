// 렌더링 테스트 공용 장면 (스냅샷·스모크·성능 측정이 같이 쓴다).
import 'dart:ui';

import 'package:trimbox/models/auto_layout.dart';
import 'package:trimbox/models/gear_physics.dart';
import 'package:trimbox/models/trim_box.dart';
import 'package:trimbox/models/trunk_space.dart';
import 'package:trimbox/render3d/gear_shapes.dart';
import 'package:trimbox/widgets/add_box_dialog.dart';

/// 다이얼로그의 캠핑 자동 색상과 같은 팔레트
const campingColors = [
  Color(0xFF556B2F),
  Color(0xFF2F4F4F),
  Color(0xFFD4652B),
  Color(0xFF1B4332),
  Color(0xFF8B4513),
  Color(0xFF4A6741),
  Color(0xFF704214),
  Color(0xFF2E5090),
  Color(0xFF6B3A2A),
  Color(0xFF5C6B4E),
];

/// 카탈로그 라벨로 박스를 만든다 (앱의 추가 흐름과 같은 물리 속성).
TrimBox gearBox(String label, int index) {
  final item = gearCatalog().firstWhere((g) => g.label == label);
  final ph = gearPhysicsFor(
    label: item.label,
    category: item.category,
    subCategory: item.subCategory,
    wCm: item.w,
    dCm: item.d,
    hCm: item.h,
  );
  return TrimBox(
    id: 'g$index',
    label: item.label,
    w: item.w / 100.0,
    d: item.d / 100.0,
    h: item.h / 100.0,
    color: campingColors[index % campingColors.length],
    category: BoxCategory.camping,
    keepUpright: ph.upright,
    soft: ph.soft,
    compressibility: ph.compress,
    weightKg: ph.weightKg,
    accessPriority: ph.access,
    shape: ph.shape,
  );
}

List<TrimBox> gearBoxes(List<String> labels) =>
    [for (var i = 0; i < labels.length; i++) gearBox(labels[i], i)];

/// 추천 세트를 자동 배치한 결과 (못 넣은 짐은 뺀다)
List<TrimBox> packedBundle(TrunkSpace space, String bundleName,
    {List<String> extra = const []}) {
  final bundle = gearBundles().firstWhere((b) => b.name == bundleName);
  final boxes = gearBoxes([...bundle.itemLabels, ...extra]);
  return pack(space, boxes);
}

List<TrimBox> pack(TrunkSpace space, List<TrimBox> boxes) {
  final result = AutoLayoutEngine.computeLayout(space, boxes, restarts: 8);
  final out = <TrimBox>[];
  for (final p in result.placements) {
    p.applyTo(p.box);
    out.add(p.box);
  }
  return out;
}

const familyBundle = '4인 가족 캠핑';

List<String> gearBundleLabels(String bundleName) =>
    gearBundles().firstWhere((b) => b.name == bundleName).itemLabels;

/// 박스 하나를 그리는 데 쓰는 다각형 수
int polygonCount(TrimBox b) => gearMesh(b).faces.length;
