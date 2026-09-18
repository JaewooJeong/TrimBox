import 'dart:convert';

import '../models/gear_physics.dart';
import '../models/scene.dart';
import '../widgets/add_box_dialog.dart' show gearCatalog, GearCatalogItem;

/// 무게·연질·접근성·모양 필드가 생기기 전(2026-09-17 이전)에 저장된 씬 보정.
///
/// 저장된 박스에 물리 필드가 하나도 없고 라벨이 장비 DB 와 같으면 [gearPhysicsFor] 로
/// 채운다 (규칙의 단일 진실은 gear_physics). 직접 입력한 박스나 이미 필드가 있는 박스는
/// 건드리지 않는다. 반환값: 보정한 박스 수.
int backfillGearPhysics(Scene scene, String rawJson) {
  const physicsKeys = ['weight', 'soft', 'compress', 'access', 'shape'];

  List<dynamic> rawBoxes;
  try {
    final root = json.decode(rawJson);
    rawBoxes = (root is Map ? root['boxes'] : null) as List<dynamic>? ?? const [];
  } catch (_) {
    return 0;
  }

  Map<String, GearCatalogItem>? catalog; // 필요할 때만 만든다
  var patched = 0;
  for (var i = 0; i < scene.boxes.length && i < rawBoxes.length; i++) {
    final raw = rawBoxes[i];
    if (raw is! Map) continue;
    if (physicsKeys.any(raw.containsKey)) continue;

    final box = scene.boxes[i];
    catalog ??= {for (final item in gearCatalog()) item.label: item};
    final item = catalog[box.label];
    if (item == null || item.category == 'custom') continue;

    final physics = gearPhysicsFor(
      label: item.label,
      category: item.category,
      subCategory: item.subCategory,
      wCm: item.w,
      dCm: item.d,
      hCm: item.h,
    );
    box
      ..weightKg = physics.weightKg
      ..soft = physics.soft
      ..compressibility = physics.compress
      ..keepUpright = box.keepUpright || physics.upright
      ..accessPriority = physics.access
      ..shape = physics.shape;
    patched++;
  }
  return patched;
}
