/// 트렁크 공간 및 휠하우스 모델
class Wheelhouse {
  final double w; // 폭 (m)
  final double d; // 깊이 (m)
  final double h; // 높이 (m)

  const Wheelhouse({required this.w, required this.d, required this.h});

  Map<String, dynamic> toJson() => {'w': w, 'd': d, 'h': h};

  factory Wheelhouse.fromJson(Map<String, dynamic> json) => Wheelhouse(
        w: (json['w'] as num).toDouble(),
        d: (json['d'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );
}

class TrunkSpace {
  final double w; // 트렁크 폭 (m)
  final double d; // 트렁크 깊이 (m)
  final double h; // 트렁크 높이 (m)
  final Wheelhouse leftWheelhouse;
  final Wheelhouse rightWheelhouse;
  final double gridUnit; // 그리드 단위 (m), 기본 0.1

  const TrunkSpace({
    required this.w,
    required this.d,
    required this.h,
    required this.leftWheelhouse,
    required this.rightWheelhouse,
    this.gridUnit = 0.10,
  });

  /// PRD 기본 트렁크 (SUV 기준)
  factory TrunkSpace.defaultSUV() => const TrunkSpace(
        w: 1.08,
        d: 1.07,
        h: 0.80,
        leftWheelhouse: Wheelhouse(w: 0.18, d: 0.36, h: 0.12),
        rightWheelhouse: Wheelhouse(w: 0.18, d: 0.36, h: 0.12),
      );

  Map<String, dynamic> toJson() => {
        'w': w,
        'd': d,
        'h': h,
        'wheelhouse': {
          'left': leftWheelhouse.toJson(),
          'right': rightWheelhouse.toJson(),
        },
      };

  factory TrunkSpace.fromJson(Map<String, dynamic> json) {
    final wh = json['wheelhouse'] as Map<String, dynamic>;
    return TrunkSpace(
      w: (json['w'] as num).toDouble(),
      d: (json['d'] as num).toDouble(),
      h: (json['h'] as num).toDouble(),
      leftWheelhouse:
          Wheelhouse.fromJson(wh['left'] as Map<String, dynamic>),
      rightWheelhouse:
          Wheelhouse.fromJson(wh['right'] as Map<String, dynamic>),
    );
  }
}
