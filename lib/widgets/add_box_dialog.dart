import 'package:flutter/material.dart';

import '../models/gear_physics.dart';
import '../models/trim_box.dart';

/// 박스 프리셋 카테고리
enum _PresetCategory { custom, carrier, camping, moving }

extension on _PresetCategory {
  String get label => switch (this) {
        _PresetCategory.custom => '직접 입력',
        _PresetCategory.carrier => '캐리어',
        _PresetCategory.camping => '캠핑',
        _PresetCategory.moving => '이사박스',
      };
}

/// 캠핑 서브 카테고리
enum _PresetSubCategory {
  tent,
  tarp,
  tableChair,
  cooler,
  sleepingGear,
  cooking,
  storage,
  carbivouac,
  misc,
}

extension on _PresetSubCategory {
  String get label => switch (this) {
        _PresetSubCategory.tent => '텐트',
        _PresetSubCategory.tarp => '타프',
        _PresetSubCategory.tableChair => '테이블&의자',
        _PresetSubCategory.cooler => '쿨러',
        _PresetSubCategory.sleepingGear => '침낭&매트',
        _PresetSubCategory.cooking => '버너&조리',
        _PresetSubCategory.storage => '수납/정리',
        _PresetSubCategory.carbivouac => '차박',
        _PresetSubCategory.misc => '기타',
      };
}

/// 박스 프리셋 데이터
class _BoxPreset {
  final String label;
  final int w, d, h;
  final _PresetCategory category;
  final _PresetSubCategory? subCategory;
  const _BoxPreset(this.label, this.w, this.d, this.h, this.category,
      [this.subCategory]);
}

const _presets = [
  // ── 직접 입력 ──
  _BoxPreset('커스텀', 40, 30, 30, _PresetCategory.custom),

  // ══════════════════════════════════════
  // ── 캐리어 / 가방 ──
  // ══════════════════════════════════════
  _BoxPreset('기내용 캐리어 (20")', 36, 23, 55, _PresetCategory.carrier),
  _BoxPreset('중형 캐리어 (24")', 45, 28, 65, _PresetCategory.carrier),
  _BoxPreset('대형 캐리어 (28")', 48, 30, 75, _PresetCategory.carrier),
  _BoxPreset('캠핑 더플백 60L', 60, 35, 30, _PresetCategory.carrier),
  _BoxPreset('캠핑 더플백 90L', 70, 40, 35, _PresetCategory.carrier),
  _BoxPreset('등산 배낭 40L', 55, 30, 25, _PresetCategory.carrier),
  _BoxPreset('등산 배낭 65L', 70, 35, 30, _PresetCategory.carrier),
  _BoxPreset('아이스 토트백', 38, 28, 35, _PresetCategory.carrier),

  // ══════════════════════════════════════
  // ── 캠핑: 텐트 (수납 크기) ──
  // ══════════════════════════════════════
  _BoxPreset('네이처하이크 클라우드업2 (2인)', 45, 12, 12,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('네이처하이크 클라우드업3 (3인)', 51, 18, 18,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('네이처하이크 Star River 2', 45, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('4인용 돔텐트 (일반)', 55, 20, 20,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('네이처하이크 P시리즈 4P', 48, 18, 18,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('스노우피크 볼트 텐트', 66, 25, 25, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('스노우피크 엔트리팩TS 텐트', 74, 22, 25, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('스노우피크 엔트리팩TS 쉘터', 77, 27, 31, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('코베아 네스트W (4인 거실형)', 80, 35, 35, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('거실형 텐트 (중형, 일반)', 65, 25, 25,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('2-3인 돔텐트 (일반)', 60, 22, 22,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('코베아 고스트 팬텀', 85, 35, 35,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('코베아 팝업 텐트 (2-3인)', 90, 9, 90, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('DOD 원터치 텐트 (3-4인)', 75, 22, 22, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('DOD 카마보코 텐트 3M', 69, 35, 31,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('DOD 카마보코 텐트 3S', 68, 28, 28,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('DOD 원폴 텐트 L', 62, 24, 24,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('콜맨 코쿤3 (4인 거실형)', 85, 40, 40, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('콜맨 인스턴트 텐트 4', 102, 28, 21, _PresetCategory.camping,
      _PresetSubCategory.tent),
  _BoxPreset('힐레베르그 아틀라스', 55, 45, 40,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('힐레베르그 나키 2', 50, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('MSR 허바허바 NX 2', 46, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('MSR 엘릭서 4', 56, 18, 18,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('빅아그네스 코퍼스퍼 UL2', 50, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('노르디스크 아스가르드 12.6', 114, 37, 37,
      _PresetCategory.camping, _PresetSubCategory.tent),

  // ══════════════════════════════════════
  // ── 캠핑: 타프 (수납 크기) ──
  // ══════════════════════════════════════
  _BoxPreset('렉타타프 (대형/폴대 포함)', 80, 22, 22, _PresetCategory.camping,
      _PresetSubCategory.tarp),
  _BoxPreset('미니타프 (소형)', 55, 15, 15, _PresetCategory.camping,
      _PresetSubCategory.tarp),
  _BoxPreset('타프 폴대 세트 (280cm)', 75, 12, 12, _PresetCategory.camping,
      _PresetSubCategory.tarp),
  _BoxPreset('스노우피크 헥사타프 L', 80, 22, 17,
      _PresetCategory.camping, _PresetSubCategory.tarp),
  _BoxPreset('스노우피크 렉타타프 L', 80, 22, 17,
      _PresetCategory.camping, _PresetSubCategory.tarp),
  _BoxPreset('헥사타프 (중형, 폴대 제외)', 64, 18, 14,
      _PresetCategory.camping, _PresetSubCategory.tarp),
  _BoxPreset('DOD 이지타프', 67, 14, 14,
      _PresetCategory.camping, _PresetSubCategory.tarp),
  _BoxPreset('네이처하이크 울트라라이트 타프', 30, 12, 12,
      _PresetCategory.camping, _PresetSubCategory.tarp),

  // ══════════════════════════════════════
  // ── 캠핑: 테이블 & 의자 (수납 크기) ──
  // ══════════════════════════════════════
  _BoxPreset('헬리녹스 테이블원', 41, 11, 11, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 테이블원 하드탑', 41, 12, 11,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 택티컬 테이블 M', 43, 12, 13,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('롤테이블 (4인/120cm)', 90, 17, 16, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('접이식 테이블 (2인/60cm)', 60, 45, 5, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('접이식 테이블 (4인/120cm, 2단 접이)', 60, 60, 7, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('코베아 슬림2폴딩 테이블', 80, 40, 7,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('스노우라인 큐브 테이블 M4', 40, 14, 8,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('스노우피크 로우체어30', 101, 18, 16,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 체어원', 35, 12, 12, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 체어원 라지', 39, 12, 13, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 체어투', 46, 13, 11,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 체어제로', 36, 11, 10,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 선셋체어', 46, 12, 14, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('헬리녹스 코트원', 54, 16, 16,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('네이처하이크 YL06 체어', 50, 13, 13,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('네이처하이크 T01 문체어 S', 62, 13, 13,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('코베아 WS 폴딩 벤치 체어', 60, 18, 8,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('DOD 스고이스 의자', 46, 39, 11,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('일반 캠핑의자 (접이식)', 85, 20, 15, _PresetCategory.camping,
      _PresetSubCategory.tableChair),
  _BoxPreset('릴렉스 체어 (접이식, 대형)', 105, 20, 15,
      _PresetCategory.camping, _PresetSubCategory.tableChair),

  // ══════════════════════════════════════
  // ── 캠핑: 쿨러/아이스박스 ──
  // ══════════════════════════════════════
  _BoxPreset('스탠리 쿨러 15L', 43, 33, 29, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('스탠리 쿨러 28L', 54, 40, 47, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('예티 탄드라 35', 54, 40, 39, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('예티 탄드라 45', 65, 40, 39, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('예티 탄드라 65', 78, 44, 41,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('예티 로드아웃 GoBox 30', 52, 38, 29,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('소형 아이스박스 (25L)', 45, 29, 32, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('대형 아이스박스 (50L)', 60, 40, 42, _PresetCategory.camping,
      _PresetSubCategory.cooler),
  _BoxPreset('도메틱 CI55', 57, 52, 43,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('도메틱 CI42', 64, 39, 34,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('도메틱 Patrol 20', 53, 36, 38,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('콜맨 익스트림 52QT', 65, 38, 42,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('콜맨 익스트림 28QT', 47, 31, 44,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('이글루 BMX 52', 67, 42, 41,
      _PresetCategory.camping, _PresetSubCategory.cooler),

  // ══════════════════════════════════════
  // ── 캠핑: 침낭 & 매트 (수납 크기) ──
  // ══════════════════════════════════════
  _BoxPreset('다운침낭 (경량)', 26, 12, 12, _PresetCategory.camping,
      _PresetSubCategory.sleepingGear),
  _BoxPreset('일반 침낭 (3계절)', 40, 26, 26, _PresetCategory.camping,
      _PresetSubCategory.sleepingGear),
  _BoxPreset('에어매트 (싱글)', 30, 12, 12, _PresetCategory.camping,
      _PresetSubCategory.sleepingGear),
  _BoxPreset('에어매트 (더블)', 52, 20, 22, _PresetCategory.camping,
      _PresetSubCategory.sleepingGear),
  _BoxPreset('자충매트 (싱글)', 62, 15, 15, _PresetCategory.camping,
      _PresetSubCategory.sleepingGear),
  _BoxPreset('네이처하이크 CW280 다운침낭', 26, 12, 12,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('네이처하이크 스노우버드 침낭', 39, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('씨투써밋 스파크 SP2', 24, 14, 14,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('코베아 컴포트 플러스 1000 침낭', 40, 26, 26,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('써모레스트 네오에어 X라이트', 23, 10, 10,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('써모레스트 Z라이트솔', 51, 13, 14,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('네모 텐서 매트', 25, 10, 10,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('엑스페드 신매트 UL', 27, 11, 11,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),

  // ══════════════════════════════════════
  // ── 캠핑: 버너 & 조리도구 ──
  // ══════════════════════════════════════
  _BoxPreset('코베아 슬림트윈 투버너', 54, 34, 7, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('코베아 알파인마스터 2.0', 17, 17, 21, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('코베아 3웨이 올인원 L', 49, 28, 16,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('코베아 큐브', 26, 24, 12,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('휴대용 싱글버너', 35, 28, 10, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('스노우피크 기가파워', 36, 25, 10,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('스노우피크 HOME&CAMP 버너', 30, 9, 12,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('프리머스 옴니퓨얼 II', 14, 8, 9,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('MSR 포켓로켓', 8, 5, 3,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('제트보일 플래시', 18, 10, 10,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('코펠세트 (2-3인)', 20, 20, 15, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('코펠세트 (4-5인)', 28, 23, 13, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('티타늄 코펠 (소형)', 18, 15, 7, _PresetCategory.camping,
      _PresetSubCategory.cooking),
  _BoxPreset('스탠리 캠프쿡세트', 28, 16, 28,
      _PresetCategory.camping, _PresetSubCategory.cooking),

  // ══════════════════════════════════════
  // ── 캠핑: 수납/정리 ──
  // ══════════════════════════════════════
  _BoxPreset('스노우피크 쉘프컨테이너 25', 52, 33, 21, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('스노우피크 쉘프컨테이너 50', 63, 41, 27, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('스노우피크 멀티컨테이너 M', 44, 16, 15,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('스노우피크 기어컨테이너', 38, 27, 31,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('카즈미 캐리백 50L', 54, 36, 26,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('카즈미 필드 캐비닛 박스', 46, 33, 31,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('코베아 컨테이너 하드케이스 45L', 56, 35, 24,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('폴딩박스 (32L)', 48, 30, 29, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('폴딩박스 (56L)', 52, 36, 30, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('트렁크 정리함 (소형)', 33, 32, 30, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('트렁크 정리함 (대형)', 65, 32, 30, _PresetCategory.camping,
      _PresetSubCategory.storage),
  _BoxPreset('불스원 트렁크 오거나이저', 41, 22, 32,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('트렁크 정리함 (중형, 일반)', 56, 32, 26,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('이케아 SAMLA 박스 45L', 57, 39, 28,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('캠핑 식기 수납가방', 38, 25, 15,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('양념통 세트 수납백', 30, 20, 12,
      _PresetCategory.camping, _PresetSubCategory.storage),

  // ══════════════════════════════════════
  // ── 캠핑: 차박 전용 ──
  // ══════════════════════════════════════
  _BoxPreset('차박매트 SUV 접이식', 80, 40, 15,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('리어게이트 차량 텐트', 74, 30, 20,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('12V 전기장판', 60, 30, 8,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('차박 커튼세트', 40, 30, 10,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('차박 모기장', 45, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('EcoFlow DELTA 2', 40, 21, 28,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('EcoFlow DELTA mini', 38, 18, 24,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('잭커리 500 파워뱅크', 30, 20, 24,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('차량용 인버터', 25, 15, 8,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('270도 어닝 (수납)', 200, 25, 20,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),

  // ══════════════════════════════════════
  // ── 캠핑: 기타 장비 ──
  // ══════════════════════════════════════
  _BoxPreset('루메나 M3 랜턴', 10, 4, 4, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('골제로 랜턴', 10, 4, 4, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('클레이모어 울트라미니', 9, 3, 7,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('충전식 LED 랜턴 (중형)', 12, 12, 24,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('카즈미 LED 랜턴', 9, 9, 19,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 랜턴 (대형)', 15, 15, 28, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('스노우피크 화로대 L', 56, 64, 3,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('코베아 파이어캠프2', 44, 30, 10,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('워터저그 5L (일반)', 18, 18, 28,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('워터저그 10L (일반)', 25, 25, 36,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('장작 한 묶음', 40, 30, 25, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('숯 (3kg 봉지)', 40, 20, 12, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('팩/해머 세트', 35, 15, 10, _PresetCategory.camping,
      _PresetSubCategory.misc),
  _BoxPreset('캠핑 그라운드시트', 40, 15, 15,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 선풍기 (접이식)', 20, 16, 35,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('파세코 캠프-10 등유 난로', 33, 33, 47,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('타프스크린 메쉬쉘터', 70, 25, 25,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 식기세트 4인', 30, 30, 15,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('더치오븐 10인치', 28, 28, 15,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('메쉬 모기장 텐트', 65, 18, 18,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 빨래줄 세트', 25, 8, 5,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 세면도구 파우치', 25, 15, 10,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 구급함', 25, 18, 10,
      _PresetCategory.camping, _PresetSubCategory.misc),

  // ── 캠핑: 추가 텐트 ──
  _BoxPreset('6인 거실형 텐트 (일반)', 88, 35, 30,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('3-4인 돔텐트 (일반)', 60, 20, 20,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('콜맨 스카이돔 다크룸 6P', 65, 23, 23,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('로벤스 로지 3 EXP', 50, 18, 18,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('반고 오메가 450 (4인)', 55, 21, 21,
      _PresetCategory.camping, _PresetSubCategory.tent),

  // ── 추가 테이블/의자 ──
  _BoxPreset('문캠프 릴렉스 체어 L', 52, 14, 14,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('알루미늄 롤테이블 (2인/90cm)', 72, 16, 14,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('키친 스탠드 테이블', 80, 50, 10,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('미니 사이드 테이블', 32, 10, 10,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('해먹 (수납)', 35, 12, 12,
      _PresetCategory.camping, _PresetSubCategory.tableChair),

  // ── 추가 조리 ──
  _BoxPreset('캠핑 와플메이커', 24, 14, 10,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('캠핑 핫샌드위치 메이커', 35, 15, 4,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('그리들 (철판)', 46, 30, 4,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('접이식 바비큐 그릴', 45, 30, 8,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('캠핑 드립커피 세트', 20, 12, 15,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('캠핑 주전자 (1.5L)', 18, 18, 12,
      _PresetCategory.camping, _PresetSubCategory.cooking),

  // ── 추가 침낭/매트 ──
  _BoxPreset('듀얼 커플 침낭', 50, 35, 30,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('캠핑 베개 (접이식)', 25, 15, 8,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('모포/담요', 45, 30, 15,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),

  // ── 추가 쿨러 ──
  _BoxPreset('아이스박스 30L (일반)', 52, 33, 35,
      _PresetCategory.camping, _PresetSubCategory.cooler),
  _BoxPreset('다이소 소프트 쿨러백', 30, 21, 30,
      _PresetCategory.camping, _PresetSubCategory.cooler),

  // ── 추가 수납 ──
  _BoxPreset('텐트 전용 캐리백', 75, 25, 25,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('타프폴대 수납백', 70, 12, 12,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('캠핑 신발 수납백', 35, 25, 15,
      _PresetCategory.camping, _PresetSubCategory.storage),
  _BoxPreset('대형 메쉬 수납백', 60, 35, 20,
      _PresetCategory.camping, _PresetSubCategory.storage),

  // ── 추가 차박 ──
  _BoxPreset('차량용 냉장고 (15L)', 60, 26, 32,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
  _BoxPreset('차량용 냉장고 (25L)', 57, 30, 36,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),

  // ── 추가 기타 ──
  _BoxPreset('캠핑 우산/타프연결대', 75, 8, 8,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('에어 소파 (수납)', 35, 18, 12,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 돗자리 (접이식)', 50, 30, 8,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 라디오/스피커', 18, 8, 8,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('장작 가방', 55, 25, 5,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('캠핑 행거/옷걸이대', 80, 10, 10,
      _PresetCategory.camping, _PresetSubCategory.misc),

  // ══════════════════════════════════════
  // ── 이사박스 ──
  // ══════════════════════════════════════
  _BoxPreset('소형 이사박스', 31, 26, 31, _PresetCategory.moving),
  _BoxPreset('중형 이사박스', 46, 41, 46, _PresetCategory.moving),
  _BoxPreset('대형 이사박스', 46, 46, 61, _PresetCategory.moving),
  _BoxPreset('옷걸이 이사박스', 50, 50, 100, _PresetCategory.moving),
  _BoxPreset('책 이사박스', 38, 28, 28, _PresetCategory.moving),

  // ── 추가 캠핑 장비 (200개 달성) ──
  _BoxPreset('Snow Peak 에어 매트 (접이)', 56, 20, 14,
      _PresetCategory.camping, _PresetSubCategory.sleepingGear),
  _BoxPreset('Coleman 텐트 팩 (4인)', 65, 22, 22,
      _PresetCategory.camping, _PresetSubCategory.tent),
  _BoxPreset('캠핑 토치/파이어스타터', 12, 6, 6,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('접이식 물통 (10L)', 30, 30, 5,
      _PresetCategory.camping, _PresetSubCategory.misc),
  _BoxPreset('Helinox 코트 원 컨버터블', 55, 16, 16,
      _PresetCategory.camping, _PresetSubCategory.tableChair),
  _BoxPreset('코베아 캠프1 플러스 스토브', 13, 13, 10,
      _PresetCategory.camping, _PresetSubCategory.cooking),
  _BoxPreset('차량용 루프백 (소프트)', 90, 50, 15,
      _PresetCategory.camping, _PresetSubCategory.carbivouac),
];

/// 컬러 팔레트 (박스 색상 선택용)
const _colorPalette = [
  Color(0xFFFFB3BA),
  Color(0xFFBAE1FF),
  Color(0xFFBAFFC9),
  Color(0xFFFFFFBA),
  Color(0xFFE3BAFF),
  Color(0xFFFFD4A3),
  Color(0xFFA3FFE0),
  Color(0xFFFFA3D4),
];

/// S7: 카테고리별 기본 색상 팔레트
const _categoryColors = {
  _PresetCategory.carrier: [
    Color(0xFF2C3E50), // 다크 네이비
    Color(0xFFC0392B), // 레드
    Color(0xFF1A1A2E), // 블랙
    Color(0xFF34495E), // 슬레이트
  ],
  _PresetCategory.moving: [
    Color(0xFFB8956A), // 골판지
    Color(0xFFD4A574), // 밝은 골판지
    Color(0xFFA0826D), // 어두운 골판지
  ],
  _PresetCategory.camping: [
    Color(0xFF556B2F), // 올리브
    Color(0xFF2F4F4F), // 다크 슬레이트
    Color(0xFFD4652B), // 번트 오렌지
    Color(0xFF1B4332), // 다크 그린
    Color(0xFF8B4513), // 새들 브라운
    Color(0xFF4A6741), // 포레스트 그린
    Color(0xFF704214), // 초콜릿
    Color(0xFF2E5090), // 딥 블루
    Color(0xFF6B3A2A), // 마호가니
    Color(0xFF5C6B4E), // 세이지
  ],
};

/// 추천 세트 (프리셋 번들)
class _PresetBundle {
  final String name;
  final String description;
  final List<String> itemLabels;

  const _PresetBundle({
    required this.name,
    required this.description,
    required this.itemLabels,
  });

  /// Resolve item labels to preset indices (with duplicates for multiples)
  List<int> resolveIndices() {
    final result = <int>[];
    for (final label in itemLabels) {
      final idx = _presets.indexWhere((p) => p.label == label);
      if (idx != -1) {
        result.add(idx);
      }
    }
    return result;
  }

  /// Total item count
  int get itemCount => itemLabels.length;

  /// Estimated total volume in liters
  double get totalVolumeLiters {
    double vol = 0;
    for (final label in itemLabels) {
      final preset = _presets.where((p) => p.label == label).firstOrNull;
      if (preset != null) {
        vol += preset.w * preset.d * preset.h / 1000.0; // cm^3 -> liters
      }
    }
    return vol;
  }
}

const _presetBundles = [
  _PresetBundle(
    name: '2인 미니멀 캠핑',
    description: '가볍게 떠나는 2인 캠핑',
    itemLabels: [
      '네이처하이크 클라우드업2 (2인)',
      '헬리녹스 테이블원',
      '헬리녹스 체어원',
      '헬리녹스 체어원',
      '소형 아이스박스 (25L)',
      '다운침낭 (경량)',
      '다운침낭 (경량)',
      '코베아 알파인마스터 2.0',
      '코펠세트 (2-3인)',
    ],
  ),
  _PresetBundle(
    name: '4인 가족 캠핑',
    description: '온 가족이 함께하는 캠핑',
    itemLabels: [
      '코베아 네스트W (4인 거실형)',
      '렉타타프 (대형/폴대 포함)',
      '롤테이블 (4인/120cm)',
      '일반 캠핑의자 (접이식)',
      '일반 캠핑의자 (접이식)',
      '일반 캠핑의자 (접이식)',
      '일반 캠핑의자 (접이식)',
      '대형 아이스박스 (50L)',
      '일반 침낭 (3계절)',
      '일반 침낭 (3계절)',
      '일반 침낭 (3계절)',
      '일반 침낭 (3계절)',
      '코베아 슬림트윈 투버너',
      '코펠세트 (4-5인)',
      '스노우피크 쉘프컨테이너 50',
      '장작 한 묶음',
    ],
  ),
  _PresetBundle(
    name: '솔로 백패킹',
    description: '혼자 가볍게 떠나는 백패킹',
    itemLabels: [
      '네이처하이크 클라우드업2 (2인)',
      '헬리녹스 체어원',
      '에어매트 (싱글)',
      '다운침낭 (경량)',
      '코베아 알파인마스터 2.0',
      '티타늄 코펠 (소형)',
    ],
  ),
];

/// 장비 카탈로그의 공개 뷰 (테스트·도구용). 치수는 cm.
class GearCatalogItem {
  final String label;
  final int w, d, h;
  final String category; // 'camping' | 'carrier' | 'moving' | 'custom'
  final String? subCategory; // 'tent' | 'tarp' | ... (캠핑만)

  const GearCatalogItem(
      this.label, this.w, this.d, this.h, this.category, this.subCategory);
}

/// 추천 세트의 공개 뷰
class GearBundleInfo {
  final String name;
  final List<String> itemLabels;

  const GearBundleInfo(this.name, this.itemLabels);
}

/// 전체 장비 프리셋 (직접 입력용 '커스텀' 포함)
List<GearCatalogItem> gearCatalog() => [
      for (final p in _presets)
        GearCatalogItem(
            p.label, p.w, p.d, p.h, p.category.name, p.subCategory?.name),
    ];

/// 추천 세트 3종
List<GearBundleInfo> gearBundles() => [
      for (final b in _presetBundles) GearBundleInfo(b.name, b.itemLabels),
    ];

/// 박스 추가 다이얼로그 — 카테고리별 프리셋 + 멀티 셀렉트 + W, D, H (cm 단위) + 컬러 선택
class AddBoxDialog extends StatefulWidget {
  const AddBoxDialog({super.key});

  @override
  State<AddBoxDialog> createState() => _AddBoxDialogState();
}

class _AddBoxDialogState extends State<AddBoxDialog> {
  // 현재 선택된 카테고리 탭
  _PresetCategory _selectedCategory = _PresetCategory.camping;

  // 캠핑 서브카테고리 필터 (null = 전체)
  _PresetSubCategory? _selectedSubCategory;

  // 멀티 셀렉트: 선택된 프리셋 인덱스 → 수량 (1 이상)
  final Map<int, int> _selectedPresetQuantities = {};

  // Helper accessors for backward compatibility
  int get _selectedCount {
    int total = 0;
    for (final q in _selectedPresetQuantities.values) {
      total += q;
    }
    return total;
  }

  bool _isPresetSelected(int idx) => _selectedPresetQuantities.containsKey(idx);

  int _presetQuantity(int idx) => _selectedPresetQuantities[idx] ?? 0;

  void _selectPreset(int idx, {int quantity = 1}) {
    _selectedPresetQuantities[idx] = quantity;
  }

  void _deselectPreset(int idx) {
    _selectedPresetQuantities.remove(idx);
  }

  void _clearSelection() {
    _selectedPresetQuantities.clear();
  }

  // 검색 필터
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchFieldKey = GlobalKey();
  String _searchQuery = '';

  // 직접 입력 모드용 컨트롤러
  final _wCtrl = TextEditingController(text: '40');
  final _dCtrl = TextEditingController(text: '30');
  final _hCtrl = TextEditingController(text: '30');
  final _labelCtrl = TextEditingController();
  int? _selectedColorIndex; // null = 자동 (순서대로)

  /// S7: 프리셋 카운터 (카테고리별 색상 순환용)
  final _categoryCounter = <_PresetCategory, int>{};

  @override
  void dispose() {
    _wCtrl.dispose();
    _dCtrl.dispose();
    _hCtrl.dispose();
    _labelCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 현재 카테고리+서브카테고리+검색어에 맞는 프리셋 필터링 (인덱스 포함)
  List<(int, _BoxPreset)> _filteredPresets() {
    final query = _searchQuery.toLowerCase();
    final result = <(int, _BoxPreset)>[];
    for (int i = 0; i < _presets.length; i++) {
      final p = _presets[i];
      // 검색어가 있으면 카테고리 무시하고 전체 검색
      if (query.isNotEmpty) {
        if (p.label.toLowerCase().contains(query)) {
          result.add((i, p));
        }
        continue;
      }
      if (p.category != _selectedCategory) continue;
      if (_selectedCategory == _PresetCategory.camping &&
          _selectedSubCategory != null &&
          p.subCategory != _selectedSubCategory) {
        continue;
      }
      result.add((i, p));
    }
    return result;
  }

  /// _PresetCategory -> BoxCategory 매핑
  static const _categoryMap = {
    _PresetCategory.custom: BoxCategory.custom,
    _PresetCategory.carrier: BoxCategory.carrier,
    _PresetCategory.camping: BoxCategory.camping,
    _PresetCategory.moving: BoxCategory.moving,
  };

  /// 이 높이보다 낮으면 (낮은 폰 + 키보드) 머리말을 고정하지 않고 목록과 함께 스크롤한다.
  /// 머리말(~200px) + 하단 버튼(~60px) 을 빼고도 목록이 120px 이상 남는 경계.
  static const double _compactHeight = 400;

  @override
  Widget build(BuildContext context) {
    final isCustom = _selectedCategory == _PresetCategory.custom;
    final selectedCount = _selectedCount;

    return Dialog(
      backgroundColor: const Color(0xFF252525),
      // 360dp 폰에서 하단 버튼 줄과 목록이 들어가도록 좌우 여백을 줄인다.
      // 넓은 화면은 maxWidth 480 에 걸리므로 크기·위치가 그대로다.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < _compactHeight;
            final header = _buildHeader(isCustom, selectedCount);
            final scrolling = compact ? header : const <Widget>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact) ...header,
                const Divider(color: Color(0xFF444444), height: 1),

                // 컨텐츠 영역
                Flexible(
                  child: isCustom
                      ? _buildCustomInput(leading: scrolling)
                      : _buildPresetList(leading: scrolling),
                ),

                const Divider(color: Color(0xFF444444), height: 1),
                _buildBottomBar(isCustom, selectedCount),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 머리말: 제목 + 카테고리 + 서브카테고리 + 검색
  List<Widget> _buildHeader(bool isCustom, int selectedCount) {
    return [
      // 제목
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            const Text('박스 추가',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            if (selectedCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4DA3FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$selectedCount개 선택',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),

      // 카테고리 탭
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildCategoryChips(),
      ),
      const SizedBox(height: 4),

      // 서브카테고리 (캠핑만)
      if (_selectedCategory == _PresetCategory.camping)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildSubCategoryChips(),
        ),

      // 검색 필드 (프리셋 모드에서만)
      if (!isCustom)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SizedBox(
            height: 36,
            child: TextField(
              // 키보드가 올라오며 머리말이 목록 안으로 옮겨져도 입력 상태·포커스를 유지한다
              key: _searchFieldKey,
              focusNode: _searchFocus,
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: '장비 검색 (예: 헬리녹스, 쿨러, 텐트...)',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey[500], size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close,
                            color: Colors.grey[500], size: 16),
                        tooltip: '검색어 지우기',
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                        }),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF333333),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
    ];
  }

  /// 하단 버튼 줄
  Widget _buildBottomBar(bool isCustom, int selectedCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          // 왼쪽 남는 폭 전부를 쓰되, 그래도 모자라면(360dp 미만) 글자가 흐려지며 잘린다
          Expanded(
            child: (!isCustom && selectedCount > 0)
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _clearSelection()),
                      child: const Text('선택 해제',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4DA3FF),
            ),
            onPressed: (isCustom || selectedCount > 0) ? _onConfirm : null,
            child: Text(
              isCustom
                  ? '추가'
                  : selectedCount > 0
                      ? '추가 ($selectedCount개)'
                      : '추가',
            ),
          ),
        ],
      ),
    );
  }

  /// 카테고리 칩 바
  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _PresetCategory.values.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: ChoiceChip(
              label: Text(cat.label),
              selected: isSelected,
              onSelected: (_) {
                setState(() {
                  _selectedCategory = cat;
                  _selectedSubCategory = null;
                  _clearSelection();
                });
              },
              selectedColor: const Color(0xFF4DA3FF),
              backgroundColor: const Color(0xFF3A3A3A),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
              ),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 캠핑 서브카테고리 칩 바
  Widget _buildSubCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // "전체" 칩
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2, bottom: 6),
            child: ChoiceChip(
              label: const Text('전체'),
              selected: _selectedSubCategory == null,
              onSelected: (_) {
                setState(() {
                  _clearSelection();
                  _selectedSubCategory = null;
                });
              },
              selectedColor: const Color(0xFF3D7A3D),
              backgroundColor: const Color(0xFF333333),
              labelStyle: TextStyle(
                color: _selectedSubCategory == null
                    ? Colors.white
                    : Colors.white54,
                fontSize: 12,
              ),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              visualDensity: VisualDensity.compact,
            ),
          ),
          ..._PresetSubCategory.values.map((sub) {
            final isSelected = _selectedSubCategory == sub;
            // 해당 서브카테고리에 프리셋이 있는지 확인
            final hasItems = _presets.any((p) =>
                p.category == _PresetCategory.camping &&
                p.subCategory == sub);
            if (!hasItems) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 6, top: 2, bottom: 6),
              child: ChoiceChip(
                label: Text(sub.label),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _clearSelection();
                    _selectedSubCategory = sub;
                  });
                },
                selectedColor: const Color(0xFF3D7A3D),
                backgroundColor: const Color(0xFF333333),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 12,
                ),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 번들 카드 위젯 (캠핑 카테고리 상단)
  Widget _buildBundleCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '추천 세트',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presetBundles.map((bundle) {
                final bundleFullySelected = _isBundleFullySelected(bundle);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        if (bundleFullySelected) {
                          _removeBundle(bundle);
                        } else {
                          // Select all bundle items with correct quantities
                          _applyBundle(bundle);
                        }
                      });
                    },
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: bundleFullySelected
                            ? const Color(0xFF3D7A3D)
                            : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: bundleFullySelected
                              ? const Color(0xFF6BD06B)
                              : const Color(0xFF555555),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bundle.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${bundle.itemCount}개 장비',
                            style: const TextStyle(
                              color: Color(0xFFAAAAAA),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '~${bundle.totalVolumeLiters.round()}L',
                            style: const TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Check if a bundle is fully selected (handling duplicate items via quantities)
  bool _isBundleFullySelected(_PresetBundle bundle) {
    final indices = bundle.resolveIndices();
    if (indices.isEmpty) return false;
    // Count occurrences needed per index
    final needed = <int, int>{};
    for (final idx in indices) {
      needed[idx] = (needed[idx] ?? 0) + 1;
    }
    for (final entry in needed.entries) {
      if (_presetQuantity(entry.key) < entry.value) return false;
    }
    return true;
  }

  /// 인덱스별 필요 수량
  static Map<int, int> _bundleNeeds(_PresetBundle bundle) {
    final needed = <int, int>{};
    for (final idx in bundle.resolveIndices()) {
      needed[idx] = (needed[idx] ?? 0) + 1;
    }
    return needed;
  }

  /// 세트 해제: 이 세트 몫만 뺀다. 함께 선택된 다른 세트가 같은 장비를 쓰면
  /// (예: 2인 미니멀과 솔로 백패킹의 텐트·체어원) 그 세트에 필요한 수량은 남긴다.
  void _removeBundle(_PresetBundle bundle) {
    final others = [
      for (final b in _presetBundles)
        if (!identical(b, bundle) && _isBundleFullySelected(b)) _bundleNeeds(b),
    ];
    for (final entry in _bundleNeeds(bundle).entries) {
      var keep = 0;
      for (final o in others) {
        final n = o[entry.key] ?? 0;
        if (n > keep) keep = n;
      }
      final left = _presetQuantity(entry.key) - entry.value;
      final next = left > keep ? left : keep;
      if (next <= 0) {
        _deselectPreset(entry.key);
      } else {
        _selectPreset(entry.key, quantity: next);
      }
    }
  }

  /// Apply a bundle: set quantities for all items in the bundle
  void _applyBundle(_PresetBundle bundle) {
    final indices = bundle.resolveIndices();
    final needed = <int, int>{};
    for (final idx in indices) {
      needed[idx] = (needed[idx] ?? 0) + 1;
    }
    for (final entry in needed.entries) {
      // Use max of current quantity and bundle-required quantity
      final current = _presetQuantity(entry.key);
      if (current < entry.value) {
        _selectPreset(entry.key, quantity: entry.value);
      }
    }
  }

  static const int _maxQuantity = 9;

  /// 프리셋 목록 (체크박스 멀티셀렉트 + 수량).
  /// [leading]: 낮은 화면에서 목록과 함께 스크롤할 머리말 위젯들.
  Widget _buildPresetList({List<Widget> leading = const []}) {
    final filtered = _filteredPresets();
    // 검색 중에는 결과가 바로 보이도록 추천 세트를 접는다
    final showBundles = _selectedCategory == _PresetCategory.camping &&
        _selectedSubCategory == null &&
        _searchQuery.isEmpty;

    // 목록 앞에 붙는 고정 항목들 (머리말, 추천 세트, 결과 없음 안내)
    final prefix = <Widget>[
      if (leading.isNotEmpty)
        Column(mainAxisSize: MainAxisSize.min, children: leading),
      if (showBundles) _buildBundleCards(),
      if (filtered.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('항목이 없습니다',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ),
        ),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: prefix.length + filtered.length,
      itemBuilder: (context, idx) {
        if (idx < prefix.length) return prefix[idx];

        final (presetIndex, preset) = filtered[idx - prefix.length];
        final isChecked = _isPresetSelected(presetIndex);
        final qty = _presetQuantity(presetIndex);

        return InkWell(
          onTap: () {
            setState(() {
              if (isChecked) {
                _deselectPreset(presetIndex);
              } else {
                _selectPreset(presetIndex);
              }
            });
          },
          child: Container(
            // 수량 버튼(32px)이 붙는 선택된 행도 높이가 같도록 여백을 줄인다 (24+20 = 32+12)
            padding: EdgeInsets.symmetric(
                horizontal: 16, vertical: isChecked ? 6 : 10),
            color: isChecked
                ? const Color(0xFF4DA3FF).withValues(alpha: 0.15)
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectPreset(presetIndex);
                        } else {
                          _deselectPreset(presetIndex);
                        }
                      });
                    },
                    activeColor: const Color(0xFF4DA3FF),
                    checkColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF666666)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    preset.label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isChecked) ...[
                  const SizedBox(width: 4),
                  _quantityStepper(presetIndex, qty),
                ],
                // 좁은 화면에서 선택된 행은 수량 버튼에 자리를 내주고 치수를 숨긴다
                if (!(narrow && isChecked)) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${preset.w}x${preset.d}x${preset.h}',
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// 선택된 행의 수량 조절: [−] n [+]. 1 에서 − 를 누르면 선택 해제.
  Widget _quantityStepper(int presetIndex, int qty) {
    Widget button(IconData icon, String tooltip, VoidCallback? onTap) {
      return SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          color: Colors.white,
          disabledColor: const Color(0xFF666666),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF3A3A3A),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.remove, '수량 줄이기', () {
          setState(() {
            if (qty <= 1) {
              _deselectPreset(presetIndex);
            } else {
              _selectPreset(presetIndex, quantity: qty - 1);
            }
          });
        }),
        SizedBox(
          width: 24,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        button(
          Icons.add,
          '수량 늘리기',
          qty >= _maxQuantity
              ? null
              : () => setState(
                  () => _selectPreset(presetIndex, quantity: qty + 1)),
        ),
      ],
    );
  }

  /// 직접 입력 모드
  Widget _buildCustomInput({List<Widget> leading = const []}) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...leading,
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildCustomFields(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFields() {
    return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField('라벨', _labelCtrl, '예: 캠핑 박스',
              keyboardType: TextInputType.text),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildField('가로(cm)', _wCtrl, '40')),
              const SizedBox(width: 8),
              Expanded(child: _buildField('세로(cm)', _dCtrl, '30')),
              const SizedBox(width: 8),
              Expanded(child: _buildField('높이(cm)', _hCtrl, '30')),
            ],
          ),
          const SizedBox(height: 12),
          // 컬러 선택기
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '색상',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorChip(null, '자동'),
              ...List.generate(
                  _colorPalette.length, (i) => _colorChip(i, null)),
            ],
          ),
        ],
    );
  }

  Widget _colorChip(int? colorIndex, String? label) {
    final isSelected = _selectedColorIndex == colorIndex;
    final color = colorIndex != null ? _colorPalette[colorIndex] : null;

    return GestureDetector(
      onTap: () => setState(() => _selectedColorIndex = colorIndex),
      child: Container(
        width: label != null ? null : 28,
        height: 28,
        padding:
            label != null ? const EdgeInsets.symmetric(horizontal: 8) : null,
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF444444),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: label != null
            ? Center(
                child: Text(
                  label,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint,
      {TextInputType keyboardType =
          const TextInputType.numberWithOptions(decimal: true)}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF666666)),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4DA3FF)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF4DA3FF), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  /// 카테고리별 자동 색상 계산
  Color? _getAutoCategoryColor(_PresetCategory category) {
    final colors = _categoryColors[category];
    if (colors == null || colors.isEmpty) return null;
    final count = _categoryCounter[category] ?? 0;
    _categoryCounter[category] = count + 1;
    return colors[count % colors.length];
  }

  void _onConfirm() {
    if (_selectedCategory == _PresetCategory.custom) {
      // 직접 입력 모드: 단일 아이템 반환
      final w = double.tryParse(_wCtrl.text);
      final d = double.tryParse(_dCtrl.text);
      final h = double.tryParse(_hCtrl.text);
      if (w == null ||
          d == null ||
          h == null ||
          w <= 0 ||
          d <= 0 ||
          h <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효한 크기를 입력하세요')),
        );
        return;
      }
      int? colorValue;
      if (_selectedColorIndex != null) {
        colorValue = _colorPalette[_selectedColorIndex!].toARGB32();
      }

      Navigator.pop(context, <Map<String, dynamic>>[
        {
          'w': w / 100.0,
          'd': d / 100.0,
          'h': h / 100.0,
          'label': _labelCtrl.text.isEmpty ? null : _labelCtrl.text,
          if (colorValue != null) 'color': colorValue,
          'category': BoxCategory.custom.index,
        },
      ]);
    } else {
      // 프리셋 멀티 셀렉트 모드 (quantity 지원)
      if (_selectedPresetQuantities.isEmpty) return;

      final results = <Map<String, dynamic>>[];
      for (final entry in _selectedPresetQuantities.entries) {
        final idx = entry.key;
        final qty = entry.value;
        final preset = _presets[idx];
        final boxCat = _categoryMap[preset.category] ?? BoxCategory.custom;

        for (int q = 0; q < qty; q++) {
          int? colorValue;
          if (_selectedColorIndex != null) {
            colorValue = _colorPalette[_selectedColorIndex!].toARGB32();
          } else {
            final autoColor = _getAutoCategoryColor(preset.category);
            if (autoColor != null) {
              colorValue = autoColor.toARGB32();
            }
          }

          // 무게·연질·세움·접근성은 gear_physics 가 단일 진실
          final physics = gearPhysicsFor(
            label: preset.label,
            category: preset.category.name,
            subCategory: preset.subCategory?.name,
            wCm: preset.w,
            dCm: preset.d,
            hCm: preset.h,
          );
          results.add({
            ...physics.toItemFields(),
            'w': preset.w / 100.0,
            'd': preset.d / 100.0,
            'h': preset.h / 100.0,
            'label': preset.label,
            if (colorValue != null) 'color': colorValue,
            'category': boxCat.index,
          });
        }
      }

      Navigator.pop(context, results);
    }
  }
}
