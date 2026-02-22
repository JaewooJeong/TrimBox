/// 차종 카테고리
enum VehicleCategory { suv, sedan, minivan }

extension VehicleCategoryExt on VehicleCategory {
  String get label => switch (this) {
        VehicleCategory.suv => 'SUV',
        VehicleCategory.sedan => '세단',
        VehicleCategory.minivan => '미니밴',
      };
}

/// 트렁크 크기 프리셋 — 실제 한국 인기 차종 기반
enum TrunkPreset { tucson, sorento, santafe, carnival, ioniq5, avante, custom }

extension TrunkPresetExt on TrunkPreset {
  String get label => switch (this) {
        TrunkPreset.tucson => '투싼 (104×91cm)',
        TrunkPreset.sorento => '쏘렌토 (105×100cm)',
        TrunkPreset.santafe => '싼타페 (128×105cm)',
        TrunkPreset.carnival => '카니발 (125×85cm)',
        TrunkPreset.ioniq5 => '아이오닉5 (100×95cm)',
        TrunkPreset.avante => '아반떼 (102×71cm)',
        TrunkPreset.custom => '커스텀',
      };

  VehicleCategory? get category => switch (this) {
        TrunkPreset.tucson => VehicleCategory.suv,
        TrunkPreset.sorento => VehicleCategory.suv,
        TrunkPreset.santafe => VehicleCategory.suv,
        TrunkPreset.carnival => VehicleCategory.minivan,
        TrunkPreset.ioniq5 => VehicleCategory.suv,
        TrunkPreset.avante => VehicleCategory.sedan,
        TrunkPreset.custom => null,
      };

  /// custom은 별도 다이얼로그로 생성하므로 null 반환
  TrunkSpace? toTrunkSpace() => switch (this) {
        TrunkPreset.tucson => TrunkSpace.tucson(),
        TrunkPreset.sorento => TrunkSpace.sorento(),
        TrunkPreset.santafe => TrunkSpace.santafe(),
        TrunkPreset.carnival => TrunkSpace.carnival(),
        TrunkPreset.ioniq5 => TrunkSpace.ioniq5(),
        TrunkPreset.avante => TrunkSpace.avante(),
        TrunkPreset.custom => null,
      };

  /// 트렁크 적재량(리터)
  int? get volumeLiters {
    final s = toTrunkSpace();
    if (s == null) return null;
    // 전체 공간에서 휠하우스 부피 제외
    final totalVol = s.w * s.d * s.h;
    final lhVol = s.leftWheelhouse.w * s.leftWheelhouse.d * s.leftWheelhouse.h;
    final rhVol =
        s.rightWheelhouse.w * s.rightWheelhouse.d * s.rightWheelhouse.h;
    return ((totalVol - lhVol - rhVol) * 1000).round(); // m³ → L
  }
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
  final double gridUnit; // 그리드 단위 (m), 기본 0.01

  const TrunkSpace({
    required this.w,
    required this.d,
    required this.h,
    required this.leftWheelhouse,
    required this.rightWheelhouse,
    this.gridUnit = 0.01,
  });

  /// 투싼 (좌석 올린 상태)
  factory TrunkSpace.tucson() => const TrunkSpace(
        w: 1.04,
        d: 0.91,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
      );

  /// 쏘렌토
  factory TrunkSpace.sorento() => const TrunkSpace(
        w: 1.05,
        d: 1.00,
        h: 0.77,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.40, h: 0.35),
      );

  /// 싼타페
  factory TrunkSpace.santafe() => const TrunkSpace(
        w: 1.28,
        d: 1.05,
        h: 0.80,
        leftWheelhouse: Wheelhouse(w: 0.10, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.10, d: 0.40, h: 0.35),
      );

  /// 카니발
  factory TrunkSpace.carnival() => const TrunkSpace(
        w: 1.25,
        d: 0.85,
        h: 0.88,
        leftWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
      );

  /// 아이오닉5
  factory TrunkSpace.ioniq5() => const TrunkSpace(
        w: 1.00,
        d: 0.95,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
      );

  /// 아반떼 (세단)
  factory TrunkSpace.avante() => const TrunkSpace(
        w: 1.02,
        d: 0.71,
        h: 0.43,
        leftWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
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
