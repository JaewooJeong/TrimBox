# TrimBox Simulator

**내 캠핑 짐이 내 차 트렁크에 들어가는지 3초 안에 확인**

세계 최초 소비자용 3D 트렁크 패킹 시뮬레이터. 캠퍼가 자신의 차량을 선택하고, 캠핑 장비를 골라 트렁크에 자동/수동 배치하여 적재 가능 여부를 시각적으로 확인할 수 있습니다.

## 주요 기능

- **6개 한국 인기 차종** 프리셋 (투싼, 쏘렌토, 싼타페, 카니발, 아이오닉5, 아반떼) + 커스텀
- **191개 캠핑 장비** 프리셋 (텐트, 쿨러, 의자, 테이블, 침낭 등 카테고리별)
- **EP-BFD 자동배치** 알고리즘 (균형/최대적재/접근우선 3가지 전략)
- **적재 순서 가이드** 스텝별 시각화
- **1-Point Perspective** 리얼리즘 렌더링 (카펫, 차체, LED 조명, 그림자)
- **충돌 감지** (AABB: 박스-박스, 경계, 휠하우스, 높이)
- **공유 카드** 생성 (이미지 + 적재 요약 텍스트)
- **Scene 저장/불러오기** (JSON)
- **Undo/Redo** 지원

## 스크린샷

> `flutter run -d chrome` 실행 후 브라우저에서 확인

## 시작하기

```bash
# 의존성 설치
flutter pub get

# 개발 서버 실행
flutter run -d chrome

# 웹 빌드
flutter build web

# 테스트
flutter test

# 정적 분석
flutter analyze
```

## 프로젝트 구조

```
lib/
├── main.dart
├── models/
│   ├── trim_box.dart          # 박스 모델 (위치, 회전, 카테고리)
│   ├── trunk_space.dart       # 트렁크 모델 (6차종 프리셋, 형상 함수)
│   ├── auto_layout.dart       # EP-BFD 자동배치 알고리즘
│   ├── scene.dart             # Scene 직렬화
│   └── collision_detector.dart # AABB 충돌 감지
├── painters/
│   ├── isometric_painter.dart      # 1-point perspective 투영
│   ├── trunk_renderer.dart         # 트렁크 내부 렌더링
│   ├── box_renderer.dart           # 박스 렌더링 (서브타입 텍스처)
│   ├── vehicle_body_renderer.dart  # 차체 외형 렌더링
│   └── guide_renderer.dart         # 그리드, 라벨, 가이드
├── screens/
│   └── simulator_screen.dart  # 메인 화면, 상태 관리
├── widgets/
│   ├── add_box_dialog.dart    # 장비 선택 다이얼로그
│   ├── box_list_panel.dart    # 박스 목록 패널
│   └── ...
└── utils/
    ├── collision.dart         # 충돌 감지 유틸리티
    └── scene_storage.dart     # 웹 저장소
```

## 차종 프리셋

| 차종 | 폭(m) | 깊이(m) | 높이(m) | 카테고리 |
|------|--------|---------|---------|---------|
| 투싼 | 1.04 | 0.91 | 0.73 | SUV |
| **쏘렌토** (기본) | 1.08 | 1.10 | 0.78 | SUV |
| 싼타페 | 1.11 | 1.05 | 0.80 | SUV |
| 카니발 | 1.25 | 0.85 | 0.88 | 미니밴 |
| 아이오닉5 | 1.00 | 0.95 | 0.73 | SUV |
| 아반떼 | 1.02 | 0.71 | 0.43 | 세단 |

## 자동배치 알고리즘

**EP-BFD** (Extreme Point + Best Fit Decreasing):

1. 박스를 부피 내림차순으로 정렬
2. 극점(Extreme Point)에서 최적 위치 탐색
3. 트렁크 형상 검증 (천장 드롭, C필러, 테이퍼, 휠하우스)
4. 3가지 전략으로 대안 생성, 적재율/접근성/안정성 평가

## 테스트

```bash
flutter test                    # 전체 166개 테스트
flutter test test/integration/  # E2E 통합 테스트 (43개)
flutter test test/models/       # 모델 단위 테스트
flutter test test/widgets/      # 위젯 테스트
```

## 기술 스택

- **Framework**: Flutter (Web)
- **Rendering**: CustomPainter (1-point perspective)
- **Algorithm**: EP-BFD (Extreme Point + Best Fit Decreasing)
- **Testing**: flutter_test (166 tests, 0 analyze issues)

## 라이선스

MIT License
