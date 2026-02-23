import 'dart:ui';

/// 박스 카테고리
enum BoxCategory { custom, carrier, camping, moving }

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
  });

  /// 회전 적용 후 실제 폭/깊이
  double get effectiveW => (rotY == 90 || rotY == 270) ? d : w;
  double get effectiveD => (rotY == 90 || rotY == 270) ? w : d;

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
  }) =>
      TrimBox(
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'size': {'w': w, 'd': d, 'h': h},
        'pos': {'x': x, 'y': y, 'z': z},
        'rotY': rotY,
        'color': color.toARGB32(),
        if (category != BoxCategory.custom) 'category': category.index,
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
    );
  }
}
