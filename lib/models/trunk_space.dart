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
        TrunkPreset.sorento => '쏘렌토 5인승 (바닥 109×107cm)',
        TrunkPreset.sorento7 => '쏘렌토 7인승·3열 접음 (바닥 109×107cm)',
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

  /// custom은 별도 다이얼로그로 생성하므로 null 반환.
  /// [seatSlide]: 2열 시트를 앞으로 당긴 거리 (쏘렌토만 반영, 최대 0.27)
  TrunkSpace? toTrunkSpace({double seatSlide = 0}) => switch (this) {
        TrunkPreset.tucson => TrunkSpace.tucson(),
        TrunkPreset.sorento => TrunkSpace.sorento(seatSlide: seatSlide),
        TrunkPreset.sorento7 => TrunkSpace.sorento7(seatSlide: seatSlide),
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


/// 뒤쪽 경계(닫힌 테일게이트 안쪽 면 + 루프 헤더)의 단면 점.
/// 높이 [y]에서 뒤쪽 경계가 z = d − [inset] 에 있다. inset 은 y 에 대해 단조 증가.
class ProfilePoint {
  final double y; // 높이 (m)
  final double inset; // 테일게이트 바닥선(z = d) 기준 앞쪽 오프셋 (m)

  const ProfilePoint(this.y, this.inset);

  Map<String, dynamic> toJson() => {'y': y, 'inset': inset};

  factory ProfilePoint.fromJson(Map<String, dynamic> json) => ProfilePoint(
        (json['y'] as num).toDouble(),
        (json['inset'] as num).toDouble(),
      );
}

/// 앞뒤 벽의 단면 프로필 (높이 → 안쪽 오프셋). 바닥(y=0, inset=0)에서 시작해
/// 위로 갈수록 안쪽으로 기울어진다.
/// - 뒤쪽(테일게이트): 이 선 뒤로 짐이 나오면 문이 닫히지 않는다.
/// - 앞쪽(2열 등받이): 등받이가 뒤로 누워 있어 위로 갈수록 적재 깊이가 줄어든다.
class WallProfile {
  /// y 오름차순, inset 비감소. 첫 점은 (0, 0) 으로 정규화된다.
  final List<ProfilePoint> points;

  const WallProfile(this.points);

  /// 높이 [y]에서의 inset (선형 보간, 범위 밖은 끝값 유지)
  double insetAt(double y) {
    if (points.isEmpty) return 0;
    if (y <= points.first.y) return points.first.inset;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (y <= b.y) {
        final span = b.y - a.y;
        if (span <= 1e-9) return b.inset;
        return a.inset + (b.inset - a.inset) * (y - a.y) / span;
      }
    }
    return points.last.inset;
  }

  /// inset 이 [inset] 이 되는 가장 낮은 높이 (역함수). 프로필 최대 inset 보다
  /// 크면 null (그 깊이는 프로필이 막지 않음).
  double? yAtInset(double inset) {
    if (points.isEmpty || inset <= points.first.inset) return points.isEmpty ? null : points.first.y;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (inset <= b.inset + 1e-12) {
        final span = b.inset - a.inset;
        if (span <= 1e-9) return a.y;
        return a.y + (b.y - a.y) * (inset - a.inset) / span;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> toJson() => [for (final p in points) p.toJson()];

  factory WallProfile.fromJson(List<dynamic> json) => WallProfile([
        for (final e in json) ProfilePoint.fromJson(e as Map<String, dynamic>),
      ]);
}

/// 테일게이트 개구부 — z = d 평면의 사다리꼴 (아래가 넓고 위가 좁다).
/// [frameDepth] 는 D필러 트림·헤더가 트렁크 안쪽으로 들어오는 두께로,
/// z ≥ d − frameDepth 구간의 짐은 이 사다리꼴 안에 있어야 한다.
class Aperture {
  final double bottomWidth; // 바닥 높이에서의 개구부 폭 (m)
  final double topWidth; // 개구부 상단 폭 (m)
  final double height; // 바닥에서 개구부 상단(헤드라이너 하단)까지 (m)
  final double frameDepth; // 개구부 프레임 두께 (m)

  const Aperture({
    required this.bottomWidth,
    required this.topWidth,
    required this.height,
    this.frameDepth = 0.06,
  });

  /// 높이 [y]에서의 개구부 폭 (상단 위로는 0)
  double widthAt(double y) {
    if (height <= 0) return bottomWidth;
    if (y >= height) return topWidth;
    if (y <= 0) return bottomWidth;
    return bottomWidth + (topWidth - bottomWidth) * (y / height);
  }

  Map<String, dynamic> toJson() => {
        'bottomWidth': bottomWidth,
        'topWidth': topWidth,
        'height': height,
        'frameDepth': frameDepth,
      };

  factory Aperture.fromJson(Map<String, dynamic> json) => Aperture(
        bottomWidth: (json['bottomWidth'] as num).toDouble(),
        topWidth: (json['topWidth'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        frameDepth: (json['frameDepth'] as num?)?.toDouble() ?? 0.06,
      );
}

/// 트렁크 공간 및 휠하우스 모델
class Wheelhouse {
  final double w; // 폭 (m)
  final double d; // 깊이 (m)
  final double h; // 높이 (m)

  /// 뒷좌석 등받이(z=0)에서 휠하우스가 시작하는 z. 2열을 앞으로 당기면 커진다.
  final double zStart;

  const Wheelhouse(
      {required this.w, required this.d, required this.h, this.zStart = 0});

  double get zEnd => zStart + d;

  Map<String, dynamic> toJson() =>
      {'w': w, 'd': d, 'h': h, if (zStart != 0) 'z': zStart};

  factory Wheelhouse.fromJson(Map<String, dynamic> json) => Wheelhouse(
        w: (json['w'] as num).toDouble(),
        d: (json['d'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        zStart: (json['z'] as num?)?.toDouble() ?? 0,
      );
}

// ── 쏘렌토 MQ4 (2020~, 디 올 뉴 쏘렌토 / 2024~ 더 뉴 쏘렌토 PE, 동일 차체) ──
//
// 근거 (2026-09-17 교차검증, 출처·범위는 backlog/sorento-mq4-measurements.md):
//  - 국내 줄자 실측 6건(3열 접음·2열 세움) + 영국 RiDC·오너 실측:
//      바닥 길이(2열 등받이→테일게이트, 2열 최후방) 102~112 → 1.07
//        (2열 슬라이드를 앞으로 당기면 최대 +27cm — 미모델링)
//      휠하우스 사이 폭 107.5~112.5 → 1.09, 휠하우스 위 최대 폭 137~140 → 1.38
//      높이: 뒷좌석 쪽 81~85 → 0.82, 개구부 76~84 → 0.79 로 낮아짐
//  - 5인승과 7인승(3열 접음)은 위쪽 적재 공간이 같고 바닥 아래 수납함만 다르다
//    (오너 증언; 기아 UK 공식 VDA 910L vs 821L 의 차이 ≈ 수납함). 미모델링.
//  - 테일게이트: 외판 하부는 거의 수직(5~7°), 허리선(바닥 위 약 0.41~0.46) 위 유리는
//    약 30° 기울어짐(기아 도면·측면 사진 계측). 개구부 상단에서 안쪽으로 약 0.22~0.26.
//    클리앙 "줄자 잰 치수에서 30cm 는 빼야", Autoblog "tailgate 각도 때문에 못 넣음" 과 일치.
//  - 개구부 폭: 바닥 110.6(RiDC 실측), 허리선 ~116, 상단 ~105(도면 추정).
//  - 2열 등받이는 위로 갈수록 뒤(트렁크 쪽)로 눕는다 (SAE J1100 기본 25°, 세움 20~22°).
//    등받이 상단 약 0.60, 헤드레스트 구간은 수직으로 본다 — 추정.
//  - 휠하우스 길이·높이는 실측이 없어 추정 (뒷축 위치·타이어 지름 → 0.58 × 0.35).
//
// 미모델링: 바닥 아래 수납함, 2열 슬라이드, 헤드레스트 사이 틈, 개구부 모서리 R.
const double _sorentoW = 1.38;
const double _sorentoD = 1.07;
const double _sorentoH = 0.82;

/// 2열 슬라이드 최대 (기아 UK/미국 VDA 616→821L 차이와 automobiledimension 27cm)
const double sorentoSeatSlideMax = 0.27;

Wheelhouse _sorentoWheelhouse(double seatSlide) =>
    Wheelhouse(w: 0.145, d: 0.58, h: 0.35, zStart: seatSlide);

String _sorentoVolumeLabel(bool fiveSeat, double seatSlide) {
  final t = (seatSlide / sorentoSeatSlideMax).clamp(0.0, 1.0);
  final rear = fiveSeat ? 705 : 616;
  final front = fiveSeat ? 910 : 821;
  final v = (rear + (front - rear) * t).round();
  final pos = seatSlide <= 0.001
      ? '2열 최후방'
      : seatSlide >= sorentoSeatSlideMax - 0.001
          ? '2열 최전방'
          : '2열 +${(seatSlide * 100).round()}cm';
  return 'VDA ${v}L ($pos)';
}
const Aperture _sorentoAperture = Aperture(
  bottomWidth: 1.10,
  topWidth: 1.05,
  height: 0.79,
  frameDepth: 0.12,
);
const WallProfile _sorentoRearProfile = WallProfile([
  ProfilePoint(0.0, 0.0),
  ProfilePoint(0.42, 0.04), // 하부 도어 트림: 거의 수직
  ProfilePoint(0.46, 0.07), // 허리선 턱 (유리 하단 트림)
  ProfilePoint(0.79, 0.26), // 유리 구간 tan 30° ≈ 0.58
]);
const WallProfile _sorentoFrontProfile = WallProfile([
  ProfilePoint(0.0, 0.0),
  ProfilePoint(0.60, 0.22), // 등받이 상단, 약 20° 기울기
  ProfilePoint(0.82, 0.22), // 헤드레스트 구간은 수직으로 본다
]);

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

  /// 닫힌 테일게이트 안쪽 면 프로필 (null 이면 수직 벽 = 테일게이트 간섭 없음)
  final WallProfile? rearProfile;

  /// 2열 등받이 프로필 (null 이면 수직 벽). inset 은 z = 0 기준 뒤쪽(테일게이트 쪽) 오프셋.
  final WallProfile? frontProfile;

  /// 테일게이트 개구부 (null 이면 개구부 = 트렁크 단면 전체)
  final Aperture? aperture;

  /// 테일게이트 쪽(z=d)으로 갈수록 천장이 내려오는 량 (m). SUV 의 실제 루프 라인.
  final double rearCeilingDrop;

  /// 천장 높이에서 벽이 안쪽으로 좁아지는 량 (한쪽, m) — 전 구간 균일 텀블홈.
  final double ceilingNarrow;

  /// 제조사/공인 트렁크 용량 표기 (예: 'VDA 813L'). 표시용.
  final String? officialVolumeLabel;

  /// 2열 시트를 앞으로 당긴 거리 (m). 깊이 d 에 이미 반영돼 있고, 표시·복원용.
  final double seatSlide;

  /// 닫힘 검사가 모델링돼 있는가
  bool get hasTailgateModel => rearProfile != null || aperture != null;

  /// 휠하우스 사이 바닥 폭
  double get floorWidthBetweenWheelhouses =>
      w - leftWheelhouse.w - rightWheelhouse.w;

  /// 계산된 바디 확장 (각 측면)
  double get bodyExtX => (bodyWidth - w) / 2;

  /// 실사용 부피(m³): (z, y) 격자로 단면 폭을 적분한다 — 테이퍼·C필러·
  /// 천장 드롭·개구부 프레임·테일게이트 프로필을 모두 반영하고 휠하우스를 뺀다.
  /// 직육면체 w·d·h 보다 작고 현실에 가깝다.
  double get usableVolume {
    final cached = _volumeCache[this];
    if (cached != null) return cached;
    final v = _computeUsableVolume();
    _volumeCache[this] = v;
    return v;
  }

  static final Expando<double> _volumeCache = Expando<double>('usableVolume');

  double _computeUsableVolume() {
    const nz = 48, ny = 16;
    var v = 0.0;
    for (var i = 0; i < nz; i++) {
      final z = (i + 0.5) / nz * d;
      final ceil = ceilingHeightAt(z);
      if (ceil <= 0) continue;
      var section = 0.0;
      for (var j = 0; j < ny; j++) {
        final y = (j + 0.5) / ny * ceil;
        if (z < frontInsetAt(y)) continue; // 등받이 기울기 안쪽
        final width = xMaxAt(z, y) - xMinAt(z, y);
        if (width > 0) section += width * (ceil / ny);
      }
      v += section * (d / nz);
    }
    v -= leftWheelhouse.w * leftWheelhouse.d * leftWheelhouse.h;
    v -= rightWheelhouse.w * rightWheelhouse.d * rightWheelhouse.h;
    return v < 0 ? 0 : v;
  }

  /// 실내 천장 높이 — 뒷좌석 쪽 드롭([ceilingDrop], 세단형)과 테일게이트 쪽
  /// 드롭([rearCeilingDrop], SUV 루프 라인)을 반영. 테일게이트 프로필은 제외.
  double interiorCeilingAt(double z) {
    if (d == 0) return h;
    final t = (z / d).clamp(0.0, 1.0);
    return h - ceilingDrop * (1 - t) * (1 - t) - rearCeilingDrop * t * t;
  }

  /// 높이 [y]에서 2열 등받이가 z = 0 기준 얼마나 뒤(테일게이트 쪽)로 와 있나
  double frontInsetAt(double y) => frontProfile?.insetAt(y) ?? 0.0;

  /// 높이 [y]에서 짐이 닿을 수 있는 최소 z (등받이 기울기 한계)
  double frontDepthAt(double y) => frontInsetAt(y);

  /// 높이 [y]에서 뒤쪽 경계(닫힌 테일게이트·헤더)가 z = d 에서 얼마나 앞에 있나.
  /// 개구부 상단 위로는 최소 프레임 두께만큼 들어온다.
  double rearInsetAt(double y) {
    var inset = rearProfile?.insetAt(y) ?? 0.0;
    final ap = aperture;
    if (ap != null && y >= ap.height - 1e-9 && ap.frameDepth > inset) {
      inset = ap.frameDepth;
    }
    return inset;
  }

  /// 높이 [y]에서 짐이 닿을 수 있는 최대 z (테일게이트 닫힘 한계)
  double rearDepthAt(double y) => d - rearInsetAt(y);

  /// 깊이 [z]에서 뒤쪽 경계가 허용하는 최대 높이 (프로필의 역함수)
  double rearCeilingAt(double z) {
    final inset = d - z;
    if (inset < 0) return 0;
    final ap = aperture;
    var limit = h;
    if (ap != null && inset < ap.frameDepth - 1e-9) {
      limit = ap.height < limit ? ap.height : limit;
    }
    final rp = rearProfile;
    if (rp != null) {
      final y = rp.yAtInset(inset);
      if (y != null && y < limit) limit = y;
    }
    return limit < 0 ? 0 : limit;
  }

  /// 깊이 z 위치에서의 천장 높이 (실내 천장과 뒤쪽 경계 중 낮은 쪽)
  double ceilingHeightAt(double z) {
    final interior = interiorCeilingAt(z);
    if (!hasTailgateModel) return interior;
    final rear = rearCeilingAt(z);
    return rear < interior ? rear : interior;
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

  /// 개구부 프레임 구간(z ≥ d − frameDepth)에서 높이 [y]의 한쪽 좁아짐
  double apertureNarrowAt(double z, double y) {
    final ap = aperture;
    if (ap == null) return 0;
    if (z < d - ap.frameDepth - 1e-9) return 0;
    final n = (w - ap.widthAt(y)) / 2;
    return n < 0 ? 0 : n;
  }

  /// (z, y) 위치에서 짐이 차지할 수 있는 왼쪽 경계 x.
  /// 테이퍼(뒷좌석 쪽 바닥) + C필러 상단 좁아짐(천장 60% 위) + 개구부 프레임.
  double xMinAt(double z, double y) {
    var x = taperAt(z);
    final narrow = topNarrowAt(z) + ceilingNarrow;
    if (narrow > 0.001) {
      final ceilH = interiorCeilingAt(z);
      final start = ceilH * 0.6;
      if (y > start && ceilH > start) {
        x += narrow * ((y - start) / (ceilH - start)).clamp(0.0, 1.0);
      }
    }
    final ap = apertureNarrowAt(z, y);
    return ap > x ? ap : x;
  }

  /// (z, y) 위치에서 짐이 차지할 수 있는 오른쪽 경계 x
  double xMaxAt(double z, double y) => w - xMinAt(z, y);

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
    this.rearProfile,
    this.frontProfile,
    this.aperture,
    this.rearCeilingDrop = 0.0,
    this.ceilingNarrow = 0.0,
    this.officialVolumeLabel,
    this.seatSlide = 0.0,
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

  /// 쏘렌토 MQ4 5인승. 치수 근거는 파일 상단 주석. 위쪽 적재 공간은 7인승과 같다.
  /// [seatSlide]: 2열 시트를 앞으로 당긴 거리 (0~0.27). 바닥이 그만큼 길어지고
  /// 차체에 붙은 휠하우스는 등받이에서 그만큼 멀어진다.
  factory TrunkSpace.sorento({double seatSlide = 0}) => TrunkSpace(
        w: _sorentoW,
        d: _sorentoD + seatSlide,
        h: _sorentoH,
        leftWheelhouse: _sorentoWheelhouse(seatSlide),
        rightWheelhouse: _sorentoWheelhouse(seatSlide),
        seatSplitRatio: const [0.6, 0.4],
        taperRatio: 0.0,
        ceilingDrop: 0.0,
        rearCeilingDrop: 0.03,
        rearTopNarrow: 0.0,
        ceilingNarrow: 0.07,
        vehicleName: 'SORENTO 5인승',
        officialVolumeLabel: _sorentoVolumeLabel(true, seatSlide),
        seatSlide: seatSlide,
        bodyWidth: 1.90,
        trunkLipHeight: 0.78,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.60,
        aperture: _sorentoAperture,
        rearProfile: _sorentoRearProfile,
        frontProfile: _sorentoFrontProfile,
      );

  /// 쏘렌토 MQ4 7인승, 3열 접은 상태. 접힌 3열 위가 바닥이 되며 실측상 5인승과
  /// 같은 상자 치수다 (바닥 아래 수납함만 다름).
  factory TrunkSpace.sorento7({double seatSlide = 0}) => TrunkSpace(
        w: _sorentoW,
        d: _sorentoD + seatSlide,
        h: _sorentoH,
        leftWheelhouse: _sorentoWheelhouse(seatSlide),
        rightWheelhouse: _sorentoWheelhouse(seatSlide),
        seatSplitRatio: const [0.6, 0.4],
        taperRatio: 0.0,
        ceilingDrop: 0.0,
        rearCeilingDrop: 0.03,
        rearTopNarrow: 0.0,
        ceilingNarrow: 0.07,
        vehicleName: 'SORENTO 7인승 (3열 접음)',
        officialVolumeLabel: _sorentoVolumeLabel(false, seatSlide),
        seatSlide: seatSlide,
        bodyWidth: 1.90,
        trunkLipHeight: 0.78,
        roofExtension: 0.12,
        bumperDepth: 0.07,
        bodyDepth: 0.60,
        aperture: _sorentoAperture,
        rearProfile: _sorentoRearProfile,
        frontProfile: _sorentoFrontProfile,
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
        if (rearProfile != null) 'rearProfile': rearProfile!.toJson(),
        if (frontProfile != null) 'frontProfile': frontProfile!.toJson(),
        if (aperture != null) 'aperture': aperture!.toJson(),
        if (rearCeilingDrop != 0.0) 'rearCeilingDrop': rearCeilingDrop,
        if (ceilingNarrow != 0.0) 'ceilingNarrow': ceilingNarrow,
        if (officialVolumeLabel != null) 'officialVolumeLabel': officialVolumeLabel,
        if (seatSlide != 0.0) 'seatSlide': seatSlide,
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
      rearProfile: json['rearProfile'] is List
          ? WallProfile.fromJson(json['rearProfile'] as List<dynamic>)
          : null,
      frontProfile: json['frontProfile'] is List
          ? WallProfile.fromJson(json['frontProfile'] as List<dynamic>)
          : null,
      aperture: json['aperture'] is Map
          ? Aperture.fromJson(json['aperture'] as Map<String, dynamic>)
          : null,
      rearCeilingDrop: (json['rearCeilingDrop'] as num?)?.toDouble() ?? 0.0,
      ceilingNarrow: (json['ceilingNarrow'] as num?)?.toDouble() ?? 0.0,
      officialVolumeLabel: json['officialVolumeLabel'] as String?,
      seatSlide: (json['seatSlide'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
