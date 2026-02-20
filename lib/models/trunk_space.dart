/// 트렁크 크기 프리셋
enum TrunkPreset { suv, sedan, van, custom }

extension TrunkPresetExt on TrunkPreset {
  String get label => switch (this) {
        TrunkPreset.suv => 'SUV (108×107cm)',
        TrunkPreset.sedan => '세단 (90×85cm)',
        TrunkPreset.van => '밴 (130×120cm)',
        TrunkPreset.custom => '커스텀',
      };

  /// custom은 별도 다이얼로그로 생성하므로 null 반환
  TrunkSpace? toTrunkSpace() => switch (this) {
        TrunkPreset.suv => TrunkSpace.defaultSUV(),
        TrunkPreset.sedan => TrunkSpace.sedan(),
        TrunkPreset.van => TrunkSpace.van(),
        TrunkPreset.custom => null,
      };
}

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

  factory TrunkSpace.sedan() => const TrunkSpace(
        w: 0.90,
        d: 0.85,
        h: 0.65,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.30, h: 0.10),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.30, h: 0.10),
      );

  factory TrunkSpace.van() => const TrunkSpace(
        w: 1.30,
        d: 1.20,
        h: 0.90,
        leftWheelhouse: Wheelhouse(w: 0.20, d: 0.40, h: 0.15),
        rightWheelhouse: Wheelhouse(w: 0.20, d: 0.40, h: 0.15),
      );

  factory TrunkSpace.custom({
    required double w,
    required double d,
    required double h,
    Wheelhouse leftWheelhouse = const Wheelhouse(w: 0, d: 0, h: 0),
    Wheelhouse rightWheelhouse = const Wheelhouse(w: 0, d: 0, h: 0),
  }) =>
      TrunkSpace(
        w: w,
        d: d,
        h: h,
        leftWheelhouse: leftWheelhouse,
        rightWheelhouse: rightWheelhouse,
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
