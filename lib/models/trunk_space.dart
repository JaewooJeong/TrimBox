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

  /// 뒷좌석 등받이 분할 비율 (예: [0.6, 0.4] = 6:4, [0.4, 0.2, 0.4] = 4:2:4)
  /// null이면 세단/고정 뒷좌석 (분할선 없음)
  final List<double>? seatSplitRatio;

  /// 뒷벽 테이퍼 비율 (0.0 = 테이퍼 없음, 0.12 = 뒷벽 폭이 12% 좁아짐)
  final double taperRatio;

  /// 차종명 (바닥 로고 표시용, null이면 표시 안 함)
  final String? vehicleName;

  const TrunkSpace({
    required this.w,
    required this.d,
    required this.h,
    required this.leftWheelhouse,
    required this.rightWheelhouse,
    this.gridUnit = 0.01,
    this.seatSplitRatio,
    this.taperRatio = 0.0,
    this.vehicleName,
  });

  /// 투싼 (좌석 올린 상태) — 6:4 분할
  factory TrunkSpace.tucson() => const TrunkSpace(
        w: 1.04,
        d: 0.91,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.05,
        vehicleName: 'TUCSON',
      );

  /// 쏘렌토 — 4:2:4 분할
  factory TrunkSpace.sorento() => const TrunkSpace(
        w: 1.05,
        d: 1.00,
        h: 0.77,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.40, h: 0.35),
        seatSplitRatio: [0.4, 0.2, 0.4],
        taperRatio: 0.04,
        vehicleName: 'SORENTO',
      );

  /// 싼타페 — 6:4 분할
  factory TrunkSpace.santafe() => const TrunkSpace(
        w: 1.28,
        d: 1.05,
        h: 0.80,
        leftWheelhouse: Wheelhouse(w: 0.10, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.10, d: 0.40, h: 0.35),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.04,
        vehicleName: 'SANTA FE',
      );

  /// 카니발 — 5:5 분할
  factory TrunkSpace.carnival() => const TrunkSpace(
        w: 1.25,
        d: 0.85,
        h: 0.88,
        leftWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
        seatSplitRatio: [0.5, 0.5],
        taperRatio: 0.03,
        vehicleName: 'CARNIVAL',
      );

  /// 아이오닉5 — 6:4 분할
  factory TrunkSpace.ioniq5() => const TrunkSpace(
        w: 1.00,
        d: 0.95,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.06,
        vehicleName: 'IONIQ 5',
      );

  /// 아반떼 (세단) — 분할 없음 (고정 뒷좌석)
  factory TrunkSpace.avante() => const TrunkSpace(
        w: 1.02,
        d: 0.71,
        h: 0.43,
        leftWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
        taperRatio: 0.12,
        vehicleName: 'AVANTE',
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
        if (seatSplitRatio != null) 'seatSplitRatio': seatSplitRatio,
        if (taperRatio != 0.0) 'taperRatio': taperRatio,
        if (vehicleName != null) 'vehicleName': vehicleName,
      };

  factory TrunkSpace.fromJson(Map<String, dynamic> json) {
    final wh = json['wheelhouse'] as Map<String, dynamic>;
    final rawSplit = json['seatSplitRatio'] as List<dynamic>?;
    return TrunkSpace(
      w: (json['w'] as num).toDouble(),
      d: (json['d'] as num).toDouble(),
      h: (json['h'] as num).toDouble(),
      leftWheelhouse:
          Wheelhouse.fromJson(wh['left'] as Map<String, dynamic>),
      rightWheelhouse:
          Wheelhouse.fromJson(wh['right'] as Map<String, dynamic>),
      seatSplitRatio: rawSplit?.map((e) => (e as num).toDouble()).toList(),
      taperRatio: (json['taperRatio'] as num?)?.toDouble() ?? 0.0,
      vehicleName: json['vehicleName'] as String?,
    );
  }
}
