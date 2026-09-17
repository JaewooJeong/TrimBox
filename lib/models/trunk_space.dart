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
enum TrunkPreset { tucson, sorento, sorento7, santafe, carnival, ioniq5, avante, custom }

extension TrunkPresetExt on TrunkPreset {
  String get label => switch (this) {
        TrunkPreset.tucson => '투싼 (104×91cm)',
        TrunkPreset.sorento => '쏘렌토 5인승 (108×110cm)',
        TrunkPreset.sorento7 => '쏘렌토 7인승·3열 접음 (108×118cm)',
        TrunkPreset.santafe => '싼타페 (111×105cm)',
        TrunkPreset.carnival => '카니발 (125×85cm)',
        TrunkPreset.ioniq5 => '아이오닉5 (100×95cm)',
        TrunkPreset.avante => '아반떼 (102×71cm)',
        TrunkPreset.custom => '커스텀',
      };

  VehicleCategory? get category => switch (this) {
        TrunkPreset.tucson => VehicleCategory.suv,
        TrunkPreset.sorento => VehicleCategory.suv,
        TrunkPreset.sorento7 => VehicleCategory.suv,
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
        TrunkPreset.sorento7 => TrunkSpace.sorento7(),
        TrunkPreset.santafe => TrunkSpace.santafe(),
        TrunkPreset.carnival => TrunkSpace.carnival(),
        TrunkPreset.ioniq5 => TrunkSpace.ioniq5(),
        TrunkPreset.avante => TrunkSpace.avante(),
        TrunkPreset.custom => null,
      };

  /// 트렁크 적재량(리터) — 천장 드롭·테이퍼·휠하우스를 반영한 실사용 부피
  int? get volumeLiters {
    final s = toTrunkSpace();
    if (s == null) return null;
    return (s.usableVolume * 1000).round(); // m³ → L
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

  /// 트렁크 내부 형상 파라미터 (리얼리즘 렌더링용)
  final double ceilingDrop;    // 뒤쪽(z=0)에서 천장이 내려오는 량 (m)
  final double rearTopNarrow;  // 뒤쪽 상단 추가 좁아짐 — C필러 효과 (m)

  /// 차량 바디 프로필 치수
  final double bodyWidth;      // 차량 전체 후면 폭 (m)
  final double trunkLipHeight; // 지면~트렁크 바닥 높이 (m)
  final double roofExtension;  // 트렁크 천장 위 루프 확장 (m)
  final double bumperDepth;    // 범퍼 돌출 깊이 (m)
  final double bodyDepth;      // 사이드 패널 깊이 (m)

  /// 차량 외장 색상 (기본: 미드나잇 블랙 메탈릭)
  final int bodyColor;

  /// 계산된 바디 확장 (각 측면)
  double get bodyExtX => (bodyWidth - w) / 2;

  /// 실사용 부피(m³): 깊이 방향으로 잘라 (폭 − 테이퍼) × 천장 높이를 적분하고
  /// 휠하우스 부피를 뺀다. 직육면체 w·d·h 보다 작고 현실에 가깝다.
  double get usableVolume {
    const n = 50;
    var v = 0.0;
    for (var i = 0; i < n; i++) {
      final z = (i + 0.5) / n * d;
      final width = w - 2 * taperAt(z);
      v += width * ceilingHeightAt(z) * (d / n);
    }
    v -= leftWheelhouse.w * leftWheelhouse.d * leftWheelhouse.h;
    v -= rightWheelhouse.w * rightWheelhouse.d * rightWheelhouse.h;
    return v < 0 ? 0 : v;
  }

  /// 깊이 z 위치에서의 천장 높이
  double ceilingHeightAt(double z) {
    if (d == 0 || ceilingDrop == 0) return h;
    final t = (z / d).clamp(0.0, 1.0);
    return h - ceilingDrop * (1 - t) * (1 - t);
  }

  /// 깊이 z 위치에서의 상단 추가 좁아짐
  double topNarrowAt(double z) {
    if (d == 0 || rearTopNarrow == 0) return 0;
    final t = (z / d).clamp(0.0, 1.0);
    return rearTopNarrow * (1 - t);
  }

  /// 깊이 z 위치에서의 하단 테이퍼
  double taperAt(double z) {
    if (d == 0 || taperRatio == 0) return 0;
    final t = (z / d).clamp(0.0, 1.0);
    return (w * taperRatio / 2) * (1 - t);
  }

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
    this.ceilingDrop = 0.0,
    this.rearTopNarrow = 0.0,
    this.bodyWidth = 1.40,
    this.trunkLipHeight = 0.55,
    this.roofExtension = 0.12,
    this.bumperDepth = 0.07,
    this.bodyDepth = 0.55,
    this.bodyColor = 0xFF1C2526,
  });

  /// 투싼 (좌석 올린 상태) — 6:4 분할
  factory TrunkSpace.tucson() => const TrunkSpace(
        w: 1.04,
        d: 0.91,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.14, d: 0.40, h: 0.35),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.06,
        ceilingDrop: 0.08,
        rearTopNarrow: 0.04,
        vehicleName: 'TUCSON',
        bodyWidth: 1.40,
        trunkLipHeight: 0.55,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.55,
      );

  /// 쏘렌토 MQ4 5인승 (2020~, 디 올 뉴 쏘렌토) — 추정치.
  /// 근거: 휠웰 사이 폭 1,041~1,053mm(kia-forums), 상부 폭 ~1,200mm(cinch),
  /// 최대 높이 774mm(how-many-bags-fit), 2열 뒤 깊이 약 1,100mm(국내 매트 제작사 실측 108~112cm).
  /// 휠하우스는 뒷축(테일게이트에서 약 0.6~1.1m)에 걸쳐 있어 뒷좌석 쪽 약 48cm 구간.
  factory TrunkSpace.sorento() => const TrunkSpace(
        w: 1.08,
        d: 1.10,
        h: 0.78,
        leftWheelhouse: Wheelhouse(w: 0.08, d: 0.48, h: 0.30),
        rightWheelhouse: Wheelhouse(w: 0.08, d: 0.48, h: 0.30),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.07,
        ceilingDrop: 0.12,
        rearTopNarrow: 0.05,
        vehicleName: 'SORENTO 5인승',
        bodyWidth: 1.44,
        trunkLipHeight: 0.58,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.60,
      );

  /// 쏘렌토 MQ4 7인승, 3열 접은 상태 — 추정치.
  /// 근거: how-many-bags-fit 3열 접은 깊이 1,183mm, 최대 높이 774mm.
  /// 접힌 3열 시트 위가 바닥이 되므로 5인승보다 천장이 1cm 낮고 깊이는 8cm 길다.
  factory TrunkSpace.sorento7() => const TrunkSpace(
        w: 1.08,
        d: 1.18,
        h: 0.77,
        leftWheelhouse: Wheelhouse(w: 0.08, d: 0.52, h: 0.30),
        rightWheelhouse: Wheelhouse(w: 0.08, d: 0.52, h: 0.30),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.07,
        ceilingDrop: 0.12,
        rearTopNarrow: 0.05,
        vehicleName: 'SORENTO 7인승 (3열 접음)',
        bodyWidth: 1.44,
        trunkLipHeight: 0.58,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.60,
      );

  /// 싼타페 — 6:4 분할 (w 수정: 1.09→1.11, WH 0.10→0.13)
  factory TrunkSpace.santafe() => const TrunkSpace(
        w: 1.11,
        d: 1.05,
        h: 0.80,
        leftWheelhouse: Wheelhouse(w: 0.13, d: 0.40, h: 0.35),
        rightWheelhouse: Wheelhouse(w: 0.13, d: 0.40, h: 0.35),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.06,
        ceilingDrop: 0.10,
        rearTopNarrow: 0.05,
        vehicleName: 'SANTA FE',
        bodyWidth: 1.45,
        trunkLipHeight: 0.56,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.60,
      );

  /// 카니발 — 5:5 분할 (미니밴: 천장 거의 안 내려옴)
  factory TrunkSpace.carnival() => const TrunkSpace(
        w: 1.25,
        d: 0.85,
        h: 0.88,
        leftWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.10, d: 0.30, h: 0.25),
        seatSplitRatio: [0.5, 0.5],
        taperRatio: 0.03,
        ceilingDrop: 0.04,
        rearTopNarrow: 0.02,
        vehicleName: 'CARNIVAL',
        bodyWidth: 1.63,
        trunkLipHeight: 0.50,
        roofExtension: 0.14,
        bumperDepth: 0.08,
        bodyDepth: 0.65,
      );

  /// 아이오닉5 — 6:4 분할
  factory TrunkSpace.ioniq5() => const TrunkSpace(
        w: 1.00,
        d: 0.95,
        h: 0.73,
        leftWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
        rightWheelhouse: Wheelhouse(w: 0.15, d: 0.35, h: 0.30),
        seatSplitRatio: [0.6, 0.4],
        taperRatio: 0.07,
        ceilingDrop: 0.10,
        rearTopNarrow: 0.05,
        vehicleName: 'IONIQ 5',
        bodyWidth: 1.38,
        trunkLipHeight: 0.55,
        roofExtension: 0.10,
        bumperDepth: 0.06,
        bodyDepth: 0.55,
      );

  /// 아반떼 (세단) — 분할 없음 (고정 뒷좌석), 트렁크 리드 때문에 앞뒤 폭 차이 큼
  factory TrunkSpace.avante() => const TrunkSpace(
        w: 1.02,
        d: 0.71,
        h: 0.43,
        leftWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
        rightWheelhouse: Wheelhouse(w: 0.05, d: 0.30, h: 0.25),
        taperRatio: 0.12,
        ceilingDrop: 0.06,
        rearTopNarrow: 0.04,
        vehicleName: 'AVANTE',
        bodyWidth: 1.34,
        trunkLipHeight: 0.45,
        roofExtension: 0.08,
        bumperDepth: 0.06,
        bodyDepth: 0.50,
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
        if (ceilingDrop != 0.0) 'ceilingDrop': ceilingDrop,
        if (rearTopNarrow != 0.0) 'rearTopNarrow': rearTopNarrow,
        if (vehicleName != null) 'vehicleName': vehicleName,
        'bodyWidth': bodyWidth,
        'trunkLipHeight': trunkLipHeight,
        'roofExtension': roofExtension,
        'bumperDepth': bumperDepth,
        'bodyDepth': bodyDepth,
        'bodyColor': bodyColor,
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
      ceilingDrop: (json['ceilingDrop'] as num?)?.toDouble() ?? 0.0,
      rearTopNarrow: (json['rearTopNarrow'] as num?)?.toDouble() ?? 0.0,
      vehicleName: json['vehicleName'] as String?,
      bodyWidth: (json['bodyWidth'] as num?)?.toDouble() ?? 1.40,
      trunkLipHeight: (json['trunkLipHeight'] as num?)?.toDouble() ?? 0.55,
      roofExtension: (json['roofExtension'] as num?)?.toDouble() ?? 0.12,
      bumperDepth: (json['bumperDepth'] as num?)?.toDouble() ?? 0.07,
      bodyDepth: (json['bodyDepth'] as num?)?.toDouble() ?? 0.55,
      bodyColor: (json['bodyColor'] as num?)?.toInt() ?? 0xFF1C2526,
    );
  }
}
