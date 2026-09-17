# TrimBox Simulator

**내 캠핑 짐이 내 차 트렁크에 들어가는지 3초 안에 확인**

캠퍼가 차량을 고르고 캠핑 장비를 선택하면, 트렁크에 자동으로 배치해 "들어가는지"를 3D로 보여주는 시뮬레이터입니다.
1차 배포는 **쏘렌토 MQ4 1대(5인승 / 7인승·3열 접음)** 기준이며, 웹으로 검증한 뒤 Android 앱으로 냅니다.

## 주요 기능

- **3D 트렁크 뷰**: 빈 곳을 드래그해 회전, 휠/핀치로 줌, 우클릭 드래그로 패닝. 가림 순서가 정확한 painter's algorithm 렌더링
- **장비 선택**: 캠핑 장비 프리셋 199개, 추천 번들 3종(2인 미니멀 / 4인 가족 / 솔로 백패킹), 검색·수량
- **추가 즉시 자동 배치**: 장비를 넣으면 바로 배치해 "16개 모두 들어갑니다 (적재율 71%)" 처럼 판정
- **자동 배치 엔진**: 극점 후보 + 눕히기(쿨러·버너·수납함은 세워서만) + 지지 규칙(면적 50%) + 충돌 판정기 검증. 공중부양·충돌 없는 결과만 낸다
- **테일게이트 닫힘 검사**: 닫힌 테일게이트의 안쪽 면(허리선 위 유리 기울기)과 2열 등받이 기울기, 개구부 크기를 모델링. 짐이 문에 걸리면 빨간 면과 "테일게이트 안 닫힘"으로 표시하고, 개구부를 어떤 방향으로도 못 지나는 짐은 미적재 사유로 알린다
- **수동 조정**: 박스 드래그(적층 지원), 회전, 삭제, Undo/Redo
- **적재 순서 가이드**: 안쪽·아래부터 번호를 매기고 스텝별로 보여준다
- **저장**: 이름으로 저장/불러오기, 작업 상태 자동 저장·복원 (웹 localStorage / Android SharedPreferences)

## 시작하기

```bash
flutter pub get
flutter run -d chrome        # 개발 실행
flutter test                 # 테스트 176개
flutter analyze
flutter build web            # build/web (로컬 서빙: python -m http.server -d build/web 8080)
npx playwright test          # 스모크 E2E (build/web 필요, 스크린샷은 e2e/screenshots/)
flutter build apk --debug    # Android (JDK 17: flutter config --jdk-dir <JDK17 경로>)
```

## 프로젝트 구조

```
lib/
├── main.dart
├── render3d/                  # 3D 코어 (외부 엔진 없음)
│   ├── vec3.dart              # 벡터, 반직선
│   ├── camera.dart            # 오빗 카메라: 투영/역투영, 트렁크 맞춤
│   ├── geometry.dart          # AABB, 면, 트렁크 껍데기 생성, 램버트 음영
│   ├── depth_sort.dart        # 뒤→앞 위상 정렬 (분리 평면)
│   ├── picking.dart           # 레이-AABB / 레이-평면
│   └── trunk_painter_3d.dart  # 페인터 (껍데기 캐시, 격자, 박스, 라벨)
├── models/
│   ├── trunk_space.dart       # 트렁크 모델·프리셋·형상 함수·실사용 부피
│   ├── trim_box.dart          # 박스 모델
│   ├── support.dart           # 적층/중력 규칙 (SupportRule)
│   ├── auto_layout.dart       # 자동배치 엔진
│   └── scene.dart             # 직렬화
├── screens/simulator_screen.dart
├── widgets/                   # 장비 선택 다이얼로그, 목록 패널, 트렁크 크기 다이얼로그
└── utils/
    ├── collision.dart         # 충돌 판정 (단일 진실)
    ├── scene_storage.dart     # shared_preferences 저장소
    └── file_io*.dart          # 파일 내보내기/공유 (웹)
```

## 좌표계와 규칙

- x = 폭(테일게이트에서 봤을 때 왼쪽→오른쪽), y = 높이(바닥 0), z = 깊이(뒷좌석 0, 테일게이트 d)
- 트렁크 형상: 천장 드롭(뒤쪽으로 2차식), C필러 상단 좁아짐, 바닥 테이퍼, 휠하우스(뒷좌석 쪽)
- 유효성은 `CollisionDetector` 하나로만 판단하고, 적층은 `SupportRule` 하나로만 판단한다

## 차종 프리셋 (1차 노출)

| 차종 | 폭 (휠하우스 사이~최대) | 깊이 | 높이 (개구부~실내) | 근거 |
|------|----|------|------|------|
| 쏘렌토 5인승 | 109~138 | 107 | 79~82 | 줄자 실측 8건 + 기아 도면 교차검증 (`backlog/sorento-mq4-measurements.md`) |
| 쏘렌토 7인승·3열 접음 | 109~138 | 107 | 79~82 | 5인승과 같은 상자, 바닥 아래 수납함만 다름 |

테일게이트 프로필·등받이 기울기·개구부는 `lib/models/trunk_space.dart` 상단 상수에 있고, 직접 잰 값으로 바꾸면 된다.
투싼·싼타페·카니발·아이오닉5·아반떼 프리셋은 코드에 남아 있으며 2차에 노출한다.

## 테스트

- `test/render3d/` 카메라 투영·역투영 일관성, 정렬 제약, 피킹
- `test/models/support_test.dart` 지지 규칙, 중력 정착
- `test/models/auto_layout_test.dart` 감사에서 찾은 회귀 + 4차종 무작위 800회 물리 유효성(충돌 0·부양 0·테일게이트 닫힘)
- `test/utils/collision_test.dart` 쏘렌토 실측 형상: 테일게이트 닫힘, 등받이, 개구부 통과, 프레임 구간 폭
- `e2e/smoke.spec.ts` 실제 웹 빌드 플로우 스모크 (고정 뷰포트 좌표 클릭, 에러 0 + 스크린샷)

## 문서

- `backlog/release-1-deep-analysis.md` — 1차 배포 심층 분석 (왜 다시 만들었는지, 남은 확인 사항)
- `backlog/sorento-mq4-measurements.md` — 쏘렌토 MQ4 치수 교차검증 기록과 사용자 실측 체크리스트
- `CLAUDE.md` — 작업 가이드

## 라이선스

MIT License
