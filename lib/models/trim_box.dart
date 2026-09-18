import 'dart:math' as math;
import 'dart:ui';

/// 박스 카테고리
enum BoxCategory { custom, carrier, camping, moving }

/// 화면에 그리는 짐의 모양. 표시 전용이며 충돌·지지 판정은 항상 AABB 다.
/// 모든 모양은 박스의 AABB 안에 그려진다 (`lib/render3d/gear_shapes.dart`).
enum GearShape { box, cylinder, softBag, cooler, crate, flat, hardCase }

/// 저장된 이름에서 모양을 복원한다. 없거나 모르는 값이면 [GearShape.box].
GearShape gearShapeFromName(Object? name) {
  if (name is String) {
    for (final s in GearShape.values) {
      if (s.name == name) return s;
    }
  }
  return GearShape.box;
}

/// 트렁크에 배치하는 박스 모델
class TrimBox {
  final String id;
  String label;
  double w; // 폭 (m)
  double d; // 깊이 (m)
  double h; // 높이 (m)
  double x; // X 위치 (m)
  double y; // Y 위치 (m), 바닥=0
  double z; // Z 위치 (m)
  int rotY; // 회전 (0, 90, 180, 270)
  Color color;
  BoxCategory category;

  /// 세워서만 실을 수 있는 짐 (쿨러, 버너, 수납함 등). 자동배치가 눕히지 않는다.
  bool keepUpright;

  /// 연질 짐 (침낭·의류·타프 천 등). 눌러 넣을 수 있고, 위에 단단한 짐을 올리지 않는다.
  bool soft;

  /// 눌러 넣을 수 있는 최대 비율 (0 = 안 눌림, 0.4 = 높이를 40% 까지 줄일 수 있음)
  double compressibility;

  /// 현재 적용된 압축 비율 (0..compressibility). 높이 방향. 실제 높이는 [effectiveH].
  double squash;

  /// 폭·깊이 방향 압축 비율 (연질 짐이 옆으로 눌려 들어갈 때). 한 번에 한 축만 쓴다.
  double squashW;
  double squashD;

  /// 무게 (kg, 0 = 모름). 무거운 짐은 바닥·안쪽으로, 가벼운 짐 위에 올리지 않는다.
  double weightKg;

  /// 자주 꺼내는 짐 (쿨러 등) — 테일게이트 쪽을 선호
  bool accessPriority;

  /// 그릴 때의 모양 (표시 전용, 물리 판정과 무관)
  GearShape shape;

  /// 자동배치가 정한 적재 순서 (1부터). 손으로 옮기면 null 로 지워진다.
  /// JSON 에 `order` 로 저장한다 (재시작·불러오기 뒤에도 순서 가이드를 쓸 수 있게).
  int? loadOrder;

  TrimBox({
    required this.id,
    required this.label,
    required this.w,
    required this.d,
    required this.h,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.rotY = 0,
    required this.color,
    this.category = BoxCategory.custom,
    this.keepUpright = false,
    this.soft = false,
    this.compressibility = 0,
    this.squash = 0,
    this.squashW = 0,
    this.squashD = 0,
    this.weightKg = 0,
    this.accessPriority = false,
    this.shape = GearShape.box,
    this.loadOrder,
  });

  /// 회전·압축 적용 후 실제 폭/깊이
  double get effectiveW => (rotY == 90 || rotY == 270)
      ? d * (1 - squashD.clamp(0.0, 0.9))
      : w * (1 - squashW.clamp(0.0, 0.9));
  double get effectiveD => (rotY == 90 || rotY == 270)
      ? w * (1 - squashW.clamp(0.0, 0.9))
      : d * (1 - squashD.clamp(0.0, 0.9));

  /// 눌러 넣기를 반영한 실제 높이. 기하(충돌·지지·렌더링)는 이 값을 쓴다.
  double get effectiveH => h * (1 - squash.clamp(0.0, 0.9));

  /// 윗면 높이
  double get top => y + effectiveH;

  /// 공칭 부피 (m³, 압축 전)
  double get volume => w * d * h;

  /// 눌러 넣은 상태인가
  bool get isSquashed => squashAmount > 1e-6;

  /// 표시용 압축 비율 (세 축 중 최대)
  double get squashAmount => [squash, squashW, squashD].reduce(math.max);

  /// 90도 회전
  void rotate90() {
    rotY = (rotY + 90) % 360;
  }

  /// 그리드 스냅
  void snapToGrid(double gridUnit) {
    x = (x / gridUnit).round() * gridUnit;
    z = (z / gridUnit).round() * gridUnit;
  }

  /// 트렁크 경계 내로 클램핑 (회전 상태 반영)
  void clampTo(double maxW, double maxD) {
    x = x.clamp(0, (maxW - effectiveW).clamp(0, double.infinity));
    z = z.clamp(0, (maxD - effectiveD).clamp(0, double.infinity));
  }

  TrimBox copyWith({
    String? id,
    String? label,
    double? w,
    double? d,
    double? h,
    double? x,
    double? y,
    double? z,
    int? rotY,
    Color? color,
    BoxCategory? category,
    bool? keepUpright,
    bool? soft,
    double? compressibility,
    double? squash,
    double? squashW,
    double? squashD,
    double? weightKg,
    bool? accessPriority,
    GearShape? shape,
    int? loadOrder,
  }) {
    final copy = TrimBox(
      id: id ?? this.id,
      label: label ?? this.label,
      w: w ?? this.w,
      d: d ?? this.d,
      h: h ?? this.h,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      rotY: rotY ?? this.rotY,
      color: color ?? this.color,
      category: category ?? this.category,
      keepUpright: keepUpright ?? this.keepUpright,
      soft: soft ?? this.soft,
      compressibility: compressibility ?? this.compressibility,
      squash: squash ?? this.squash,
      squashW: squashW ?? this.squashW,
      squashD: squashD ?? this.squashD,
      weightKg: weightKg ?? this.weightKg,
      accessPriority: accessPriority ?? this.accessPriority,
      shape: shape ?? this.shape,
    );
    copy.loadOrder = loadOrder ?? this.loadOrder;
    return copy;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'size': {'w': w, 'd': d, 'h': h},
        'pos': {'x': x, 'y': y, 'z': z},
        'rotY': rotY,
        'color': color.toARGB32(),
        if (category != BoxCategory.custom) 'category': category.index,
        if (keepUpright) 'upright': true,
        if (soft) 'soft': true,
        if (compressibility > 0) 'compress': compressibility,
        if (squash > 0) 'squash': squash,
        if (squashW > 0) 'squashW': squashW,
        if (squashD > 0) 'squashD': squashD,
        if (weightKg > 0) 'weight': weightKg,
        if (accessPriority) 'access': true,
        if (shape != GearShape.box) 'shape': shape.name,
        if (loadOrder != null) 'order': loadOrder,
      };

  factory TrimBox.fromJson(Map<String, dynamic> json) {
    final size = json['size'] as Map<String, dynamic>;
    final pos = json['pos'] as Map<String, dynamic>;
    return TrimBox(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      w: (size['w'] as num).toDouble(),
      d: (size['d'] as num).toDouble(),
      h: (size['h'] as num).toDouble(),
      x: (pos['x'] as num).toDouble(),
      y: (pos['y'] as num).toDouble(),
      z: (pos['z'] as num).toDouble(),
      rotY: json['rotY'] as int? ?? 0,
      color: Color(json['color'] as int),
      category: json['category'] != null
          ? BoxCategory.values[(json['category'] as int)
              .clamp(0, BoxCategory.values.length - 1)]
          : BoxCategory.custom,
      keepUpright: json['upright'] == true,
      soft: json['soft'] == true,
      compressibility: (json['compress'] as num?)?.toDouble() ?? 0,
      squash: (json['squash'] as num?)?.toDouble() ?? 0,
      squashW: (json['squashW'] as num?)?.toDouble() ?? 0,
      squashD: (json['squashD'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight'] as num?)?.toDouble() ?? 0,
      accessPriority: json['access'] == true,
      shape: gearShapeFromName(json['shape']),
      loadOrder: (json['order'] as num?)?.toInt(),
    );
  }
}
