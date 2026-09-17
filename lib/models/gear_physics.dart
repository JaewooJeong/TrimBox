/// 장비의 물리 속성(무게·연질·압축률·세움·접근성)을 라벨과 카테고리에서 정한다.
///
/// 장비 DB(`add_box_dialog.dart`)는 치수와 카테고리만 갖고 있고, 물리 속성은
/// 여기서 한 번에 매긴다. 이름이 있는 제품은 [gearOverrides]에 리서치로 확인한
/// 무게를 두고, 나머지는 카테고리별 밀도(kg/L)로 추정한다.
class GearPhysics {
  final double weightKg; // 실을 때 무게 (쿨러·수납함은 내용물 포함 추정)
  final bool soft; // 연질 (눌러 넣을 수 있고 위에 단단한 짐을 올리지 않음)
  final double compress; // 최대 압축률 (0..0.5)
  final bool upright; // 세워서만
  final bool access; // 자주 꺼냄 (테일게이트 쪽 선호)

  const GearPhysics({
    required this.weightKg,
    this.soft = false,
    this.compress = 0,
    this.upright = false,
    this.access = false,
  });

  Map<String, dynamic> toItemFields() => {
        'weight': weightKg,
        'soft': soft,
        'compress': compress,
        'upright': upright,
        'access': access,
      };
}

/// 이름 있는 제품의 확인된 무게(kg)·속성. 치수는 DB 에 직접 넣는다.
/// 값의 근거: 제조사 스펙·리테일 스펙표 교차검증 (backlog/gear-db-audit.md)
const Map<String, GearPhysics> gearOverrides = {
  // ── 텐트 (폴대 포함 총중량; 폴대 가방이 길이를 정하므로 강체) ──
  '네이처하이크 클라우드업2 (2인)': GearPhysics(weightKg: 1.8),
  '네이처하이크 클라우드업3 (3인)': GearPhysics(weightKg: 2.4),
  '네이처하이크 Star River 2': GearPhysics(weightKg: 2.2),
  '스노우피크 볼트 텐트': GearPhysics(weightKg: 7.9),
  '스노우피크 엔트리팩TS 텐트': GearPhysics(weightKg: 8.0),
  '스노우피크 엔트리팩TS 쉘터': GearPhysics(weightKg: 12.0),
  '코베아 네스트W (4인 거실형)': GearPhysics(weightKg: 21),
  '코베아 고스트 팬텀': GearPhysics(weightKg: 17),
  'DOD 원터치 텐트 (3-4인)': GearPhysics(weightKg: 8.4),
  'DOD 카마보코 텐트 3M': GearPhysics(weightKg: 19.5),
  'DOD 카마보코 텐트 3S': GearPhysics(weightKg: 14.4),
  'DOD 원폴 텐트 L': GearPhysics(weightKg: 12),
  '콜맨 코쿤3 (4인 거실형)': GearPhysics(weightKg: 34),
  '콜맨 인스턴트 텐트 4': GearPhysics(weightKg: 9),
  '콜맨 스카이돔 다크룸 6P': GearPhysics(weightKg: 8.2),
  '힐레베르그 아틀라스': GearPhysics(weightKg: 11.1, soft: true, compress: 0.15),
  '힐레베르그 나키 2': GearPhysics(weightKg: 2.4),
  'MSR 허바허바 NX 2': GearPhysics(weightKg: 1.7),
  'MSR 엘릭서 4': GearPhysics(weightKg: 4.3),
  '빅아그네스 코퍼스퍼 UL2': GearPhysics(weightKg: 1.4),
  '노르디스크 아스가르드 12.6': GearPhysics(weightKg: 16),
  '반고 오메가 450 (4인)': GearPhysics(weightKg: 6.0),
  '로벤스 로지 3 EXP': GearPhysics(weightKg: 3.5),
  // ── 타프 ──
  '렉타타프 (대형/폴대 포함)': GearPhysics(weightKg: 10.5),
  '스노우피크 헥사타프 L': GearPhysics(weightKg: 3.6, soft: true, compress: 0.2),
  '스노우피크 렉타타프 L': GearPhysics(weightKg: 5.0, soft: true, compress: 0.2),
  'DOD 이지타프': GearPhysics(weightKg: 5.4),
  '네이처하이크 울트라라이트 타프': GearPhysics(weightKg: 0.4, soft: true, compress: 0.3),
  '헥사타프 (중형, 폴대 제외)': GearPhysics(weightKg: 2.5, soft: true, compress: 0.25),
  '타프 폴대 세트 (280cm)': GearPhysics(weightKg: 2.8),
  // ── 의자·테이블 (수납 가방 속 폴대 묶음 = 강체) ──
  '헬리녹스 체어원': GearPhysics(weightKg: 1.0),
  '헬리녹스 체어원 라지': GearPhysics(weightKg: 1.2),
  '헬리녹스 체어투': GearPhysics(weightKg: 1.2),
  '헬리녹스 체어제로': GearPhysics(weightKg: 0.5),
  '헬리녹스 선셋체어': GearPhysics(weightKg: 1.6),
  '헬리녹스 코트원': GearPhysics(weightKg: 2.2),
  'Helinox 코트 원 컨버터블': GearPhysics(weightKg: 2.2),
  '헬리녹스 테이블원': GearPhysics(weightKg: 0.7),
  '헬리녹스 테이블원 하드탑': GearPhysics(weightKg: 0.9),
  '헬리녹스 택티컬 테이블 M': GearPhysics(weightKg: 0.9),
  '스노우피크 로우체어30': GearPhysics(weightKg: 3.6),
  '네이처하이크 YL06 체어': GearPhysics(weightKg: 1.3),
  '네이처하이크 T01 문체어 S': GearPhysics(weightKg: 2.0),
  '코베아 WS 폴딩 벤치 체어': GearPhysics(weightKg: 3.5),
  '코베아 슬림2폴딩 테이블': GearPhysics(weightKg: 5.0),
  '스노우라인 큐브 테이블 M4': GearPhysics(weightKg: 1.3),
  'DOD 스고이스 의자': GearPhysics(weightKg: 2.3),
  '일반 캠핑의자 (접이식)': GearPhysics(weightKg: 2.8),
  '릴렉스 체어 (접이식, 대형)': GearPhysics(weightKg: 4.3),
  '롤테이블 (4인/120cm)': GearPhysics(weightKg: 5.7),
  '접이식 테이블 (4인/120cm, 2단 접이)': GearPhysics(weightKg: 5.0),
  '접이식 테이블 (2인/60cm)': GearPhysics(weightKg: 2.1),
  '알루미늄 롤테이블 (2인/90cm)': GearPhysics(weightKg: 4.5),
  // ── 쿨러: 실을 때 무게 = 공차 + 용량 L × 0.55kg (얼음·음식). 세움·자주 꺼냄 ──
  '스탠리 쿨러 15L': GearPhysics(weightKg: 11, upright: true, access: true),
  '스탠리 쿨러 28L': GearPhysics(weightKg: 22, upright: true, access: true),
  '예티 탄드라 35': GearPhysics(weightKg: 25, upright: true, access: true),
  '예티 탄드라 45': GearPhysics(weightKg: 31, upright: true, access: true),
  '예티 탄드라 65': GearPhysics(weightKg: 43, upright: true, access: true),
  '예티 로드아웃 GoBox 30': GearPhysics(weightKg: 12, upright: true),
  '도메틱 CI55': GearPhysics(weightKg: 41, upright: true, access: true),
  '도메틱 CI42': GearPhysics(weightKg: 31, upright: true, access: true),
  '도메틱 Patrol 20': GearPhysics(weightKg: 18, upright: true, access: true),
  '콜맨 익스트림 52QT': GearPhysics(weightKg: 32, upright: true, access: true),
  '콜맨 익스트림 28QT': GearPhysics(weightKg: 17.5, upright: true, access: true),
  '이글루 BMX 52': GearPhysics(weightKg: 34, upright: true, access: true),
  '아이스박스 30L (일반)': GearPhysics(weightKg: 22, upright: true, access: true),
  '소형 아이스박스 (25L)': GearPhysics(weightKg: 17, upright: true, access: true),
  '대형 아이스박스 (50L)': GearPhysics(weightKg: 32, upright: true, access: true),
  '아이스 토트백': GearPhysics(weightKg: 12, soft: true, compress: 0.15, upright: true, access: true),
  '다이소 소프트 쿨러백': GearPhysics(weightKg: 8, soft: true, compress: 0.15, upright: true, access: true),
  // ── 수납 (내용물 포함 추정) ──
  '스노우피크 쉘프컨테이너 25': GearPhysics(weightKg: 10, upright: true),
  '스노우피크 쉘프컨테이너 50': GearPhysics(weightKg: 16, upright: true),
  '스노우피크 멀티컨테이너 M': GearPhysics(weightKg: 3, soft: true, compress: 0.1),
  '스노우피크 기어컨테이너': GearPhysics(weightKg: 5, soft: true, compress: 0.15),
  '카즈미 필드 캐비닛 박스': GearPhysics(weightKg: 8, upright: true),
  '카즈미 캐리백 50L': GearPhysics(weightKg: 8, soft: true, compress: 0.2),
  '코베아 컨테이너 하드케이스 45L': GearPhysics(weightKg: 10, upright: true),
  '폴딩박스 (32L)': GearPhysics(weightKg: 7, upright: true),
  '폴딩박스 (56L)': GearPhysics(weightKg: 12, upright: true),
  '이케아 SAMLA 박스 45L': GearPhysics(weightKg: 10, upright: true),
  '불스원 트렁크 오거나이저': GearPhysics(weightKg: 4, soft: true, compress: 0.15),
  '트렁크 정리함 (중형, 일반)': GearPhysics(weightKg: 6, soft: true, compress: 0.15),
  // ── 취사 (버너는 가스통 분리, 세움) ──
  '코베아 슬림트윈 투버너': GearPhysics(weightKg: 4.9, upright: true),
  '코베아 알파인마스터 2.0': GearPhysics(weightKg: 0.9, upright: true),
  '코베아 3웨이 올인원 L': GearPhysics(weightKg: 5.5, upright: true),
  '코베아 큐브': GearPhysics(weightKg: 0.8, upright: true),
  '코베아 캠프1 플러스 스토브': GearPhysics(weightKg: 0.4, upright: true),
  '휴대용 싱글버너': GearPhysics(weightKg: 1.7, upright: true),
  '스노우피크 기가파워': GearPhysics(weightKg: 1.8, upright: true),
  '스노우피크 HOME&CAMP 버너': GearPhysics(weightKg: 1.4, upright: true),
  '프리머스 옴니퓨얼 II': GearPhysics(weightKg: 0.4, upright: true),
  'MSR 포켓로켓': GearPhysics(weightKg: 0.1),
  '제트보일 플래시': GearPhysics(weightKg: 0.4, upright: true),
  '코펠세트 (2-3인)': GearPhysics(weightKg: 1.1),
  '코펠세트 (4-5인)': GearPhysics(weightKg: 1.7),
  '티타늄 코펠 (소형)': GearPhysics(weightKg: 0.2),
  '스탠리 캠프쿡세트': GearPhysics(weightKg: 2.5),
  '더치오븐 10인치': GearPhysics(weightKg: 6.5),
  '그리들 (철판)': GearPhysics(weightKg: 4),
  '스노우피크 화로대 L': GearPhysics(weightKg: 5.5),
  '코베아 파이어캠프2': GearPhysics(weightKg: 5.4),
  // ── 침낭·매트: 다운 −45%, 합성 −30%, 에어매트 롤 −10%, 폼 매트 0 ──
  '다운침낭 (경량)': GearPhysics(weightKg: 0.7, soft: true, compress: 0.45),
  '네이처하이크 CW280 다운침낭': GearPhysics(weightKg: 0.6, soft: true, compress: 0.45),
  '네이처하이크 스노우버드 침낭': GearPhysics(weightKg: 1.0, soft: true, compress: 0.45),
  '씨투써밋 스파크 SP2': GearPhysics(weightKg: 0.5, soft: true, compress: 0.2),
  '일반 침낭 (3계절)': GearPhysics(weightKg: 1.9, soft: true, compress: 0.3),
  '코베아 컴포트 플러스 1000 침낭': GearPhysics(weightKg: 1.8, soft: true, compress: 0.3),
  '듀얼 커플 침낭': GearPhysics(weightKg: 4.3, soft: true, compress: 0.3),
  '모포/담요': GearPhysics(weightKg: 1.5, soft: true, compress: 0.4),
  '캠핑 베개 (접이식)': GearPhysics(weightKg: 0.3, soft: true, compress: 0.4),
  '에어매트 (싱글)': GearPhysics(weightKg: 0.8, soft: true, compress: 0.1),
  '에어매트 (더블)': GearPhysics(weightKg: 4.5, soft: true, compress: 0.1),
  '자충매트 (싱글)': GearPhysics(weightKg: 1.6, soft: true, compress: 0.1),
  '써모레스트 네오에어 X라이트': GearPhysics(weightKg: 0.4, soft: true, compress: 0.1),
  '써모레스트 Z라이트솔': GearPhysics(weightKg: 0.4),
  '네모 텐서 매트': GearPhysics(weightKg: 0.5, soft: true, compress: 0.1),
  '엑스페드 신매트 UL': GearPhysics(weightKg: 0.5, soft: true, compress: 0.1),
  'Snow Peak 에어 매트 (접이)': GearPhysics(weightKg: 1.9, soft: true, compress: 0.1),
  '차박매트 SUV 접이식': GearPhysics(weightKg: 4),
  // ── 전원·차박 ──
  'EcoFlow DELTA 2': GearPhysics(weightKg: 12, upright: true),
  'EcoFlow DELTA mini': GearPhysics(weightKg: 10.7, upright: true),
  '잭커리 500 파워뱅크': GearPhysics(weightKg: 6.0, upright: true),
  '차량용 냉장고 (15L)': GearPhysics(weightKg: 8.5, upright: true, access: true),
  '차량용 냉장고 (25L)': GearPhysics(weightKg: 9.5, upright: true, access: true),
  '270도 어닝 (수납)': GearPhysics(weightKg: 20),
  '차량용 루프백 (소프트)': GearPhysics(weightKg: 6, soft: true, compress: 0.3),
  // ── 기타 ──
  '장작 한 묶음': GearPhysics(weightKg: 10),
  '숯 (3kg 봉지)': GearPhysics(weightKg: 3.2),
  '워터저그 5L (일반)': GearPhysics(weightKg: 5.5, upright: true),
  '워터저그 10L (일반)': GearPhysics(weightKg: 11.5, upright: true),
  '접이식 물통 (10L)': GearPhysics(weightKg: 10.3, upright: true),
  '파세코 캠프-10 등유 난로': GearPhysics(weightKg: 6.5, upright: true),
  '캠핑 선풍기 (접이식)': GearPhysics(weightKg: 1.0),
  '루메나 M3 랜턴': GearPhysics(weightKg: 0.1),
  '골제로 랜턴': GearPhysics(weightKg: 0.1),
  '클레이모어 울트라미니': GearPhysics(weightKg: 0.1),
  '카즈미 LED 랜턴': GearPhysics(weightKg: 0.4, upright: true),
  '충전식 LED 랜턴 (중형)': GearPhysics(weightKg: 0.8, upright: true),
  '캠핑 랜턴 (대형)': GearPhysics(weightKg: 1.5, upright: true),
  '캠핑 구급함': GearPhysics(weightKg: 1.5, access: true),
};

/// 카테고리 키: 'tent' 'tarp' 'tableChair' 'cooler' 'sleepingGear' 'cooking'
/// 'storage' 'carbivouac' 'misc' (캠핑), 'carrier', 'moving', 'custom'
GearPhysics gearPhysicsFor({
  required String label,
  required String category,
  String? subCategory,
  required int wCm,
  required int dCm,
  required int hCm,
}) {
  final override = gearOverrides[label];
  if (override != null) return override;

  final liters = wCm * dCm * hCm / 1000.0;
  double kg(double perLiter, {double min = 0.3}) {
    final v = liters * perLiter;
    return v < min ? min : double.parse(v.toStringAsFixed(1));
  }

  bool has(List<String> words) => words.any(label.contains);

  // 라벨 키워드가 카테고리보다 우선 (예: 테이블&의자 안의 해먹)
  if (has(['침낭'])) return GearPhysics(weightKg: kg(0.09), soft: true, compress: 0.4);
  if (has(['매트'])) return GearPhysics(weightKg: kg(0.08), soft: true, compress: 0.15);
  if (has(['베개', '모포', '담요', '해먹', '돗자리', '에어 소파', '그라운드시트', '빨래줄', '커튼', '모기장', '파우치', '수납백', '폴딩백', '더플백', '배낭', '루프백', '전기장판'])) {
    return GearPhysics(weightKg: kg(0.1), soft: true, compress: 0.3);
  }
  if (has(['랜턴', '워터저그', '물통', '히터', '냉장고', '파워', 'EcoFlow', '잭커리', '버너', '스토브', '가스'])) {
    return GearPhysics(weightKg: kg(0.4), upright: true);
  }

  return switch (subCategory ?? category) {
    'tent' => GearPhysics(weightKg: kg(0.2, min: 1.5), soft: liters < 12, compress: liters < 12 ? 0.15 : 0),
    'tarp' => GearPhysics(weightKg: kg(0.15, min: 1)),
    'tableChair' => GearPhysics(weightKg: kg(0.18, min: 0.8)),
    'cooler' => GearPhysics(weightKg: kg(0.25, min: 5), upright: true, access: true),
    'sleepingGear' => GearPhysics(weightKg: kg(0.08), soft: true, compress: 0.3),
    'cooking' => GearPhysics(weightKg: kg(0.35, min: 0.5), upright: true),
    'storage' => GearPhysics(weightKg: kg(0.2, min: 1), upright: true),
    'carbivouac' => GearPhysics(weightKg: kg(0.25, min: 1)),
    'misc' => GearPhysics(weightKg: kg(0.3)),
    'carrier' => GearPhysics(weightKg: kg(0.18, min: 2)),
    'moving' => GearPhysics(weightKg: kg(0.25, min: 3)),
    _ => GearPhysics(weightKg: kg(0.2)),
  };
}
