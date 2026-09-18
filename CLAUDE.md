# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

TrimBox Simulator는 캠핑용 트렁크 짐 적재 시뮬레이터입니다.
캠퍼가 차량을 선택하고, 캠핑 장비를 목록에서 골라 트렁크에 자동/수동 배치하여 적재 가능 여부를 3D로 확인하는 앱입니다.

**핵심 가치**: "내 캠핑 짐이 내 차 트렁크에 들어가는지 3초 안에 확인"
**1차 배포 범위 (2026-09 결정)**: 쏘렌토 MQ4 1대(5인승 / 7인승·3열 접음), 로컬 웹으로 검증, 최종 타깃은 Android 앱. Flutter 유지.
**분석 문서**: `backlog/release-1-deep-analysis.md` (왜 다시 만들었는지, 남은 확인 사항)

## Architecture

- Flutter (package `trimbox`), 웹·Android 공용
- 3D 렌더링은 `CustomPainter` 위에 직접 만든 코어 (`lib/render3d/`): 원근 오빗 카메라, 법선 컬링 + 램버트 음영, 분리 평면 기반 뒤→앞 위상 정렬(painter's algorithm), 레이-AABB 피킹. 외부 3D 엔진 없음.
- 월드 좌표: x = 폭(0..w, 테일게이트에서 봤을 때 왼쪽→오른쪽), y = 높이(0 = 바닥), z = 깊이(0 = 뒷좌석 등받이, d = 테일게이트 개구부). 카메라 yaw=0 은 테일게이트 뒤.
- 유효성 판단은 `lib/utils/collision.dart` 의 `CollisionDetector` 하나가 단일 진실이다. 자동배치·화면·테스트가 모두 이것을 쓴다. 사유는 `CollisionKind` (경계·천장·휠하우스·테일게이트·등받이·개구부·겹침), 문장은 `describe()`. 지지/중력 규칙은 `lib/models/support.dart` 의 `SupportRule` 하나.
- 트렁크 형상은 `TrunkSpace` 의 함수로만 읽는다: `xMinAt/xMaxAt(z, y)` 좌우 경계, `interiorCeilingAt(z)` 실내 천장, `rearDepthAt(y)` 닫힌 테일게이트 한계(문이 닫히는 최대 z), `frontDepthAt(y)` 등받이 한계(최소 z), `aperture` 개구부. 렌더러·충돌·패커·부피가 전부 같은 함수를 쓴다.

### Key Files
| File | Purpose |
|------|---------|
| `lib/screens/simulator_screen.dart` | 메인 화면: 상태, 카메라 조작, 드래그, 자동배치 호출, 저장/복원 |
| `lib/render3d/camera.dart` | `OrbitCamera` — 투영/역투영, 트렁크 맞춤(fitTrunk), 각도·거리 제한 |
| `lib/render3d/geometry.dart` | `Aabb`, `Face`, 트렁크 껍데기 면 생성, AABB 면, 램버트 음영 |
| `lib/render3d/depth_sort.dart` | 뒤→앞 위상 정렬 (모든 분리축이 일치할 때만 순서 제약) |
| `lib/render3d/picking.dart` | 레이-AABB, 레이-수평면 교차 |
| `lib/render3d/trunk_painter_3d.dart` | 페인터: 껍데기 Picture 캐시, 바닥 매트·격자, 고정물·짐 메시, 그림자/라벨/순서 배지, 테일게이트 경고 |
| `lib/render3d/mesh.dart` | 공유 정점 메시·빌더·장식선 |
| `lib/render3d/fixtures.dart` | 고정물 메시: 휠하우스 아치, 개구부 프레임(D필러·헤더·씰), 범퍼·테일램프, 2열 등받이·헤드레스트 |
| `lib/render3d/gear_shapes.dart` | 짐 모양 메시 (`GearShape`: box·cylinder·softBag·cooler·crate·flat·hardCase). 항상 박스 AABB 안에 그린다 |
| `lib/models/auto_layout.dart` | 자동배치 엔진 (극점 후보 + 눕히기 + 떨어뜨리기 + 검증 게이트 + 재시도) |
| `lib/models/support.dart` | 적층/중력 규칙 `SupportRule` (지지 면적 50% 이상), `supportersAt` |
| `lib/models/gear_physics.dart` | 장비 물리 속성: 무게·연질·압축률·세움·접근성 (이름 있는 제품은 확인값, 나머지는 카테고리 밀도) |
| `lib/models/packing_advisor.dart` | 적재 조언 (무거운 짐 위층·가벼운 짐 위·연질 위 단단한 짐·자주 꺼내는 짐 묻힘) |
| `lib/models/trunk_space.dart` | 트렁크 모델, 형상 함수(xMinAt/xMaxAt, interiorCeilingAt, rearDepthAt, frontDepthAt), `WallProfile`·`Aperture`, 프리셋, `usableVolume` |
| `lib/models/trim_box.dart` | 박스 모델 (위치, rotY, keepUpright, soft/compressibility/squash, weightKg, accessPriority, loadOrder). 기하는 `effectiveW/D/H`·`top` 을 쓴다 |
| `lib/utils/collision.dart` | AABB 충돌: 박스-박스(0.5mm 허용), 경계·테이퍼·C필러·천장, 휠하우스 |
| `lib/utils/scene_storage.dart` | shared_preferences 저장소: 이름 저장, 자동 저장, 온보딩 플래그, `ensureReadable` (깨진 값 복구 뒤 읽기) |
| `lib/utils/prefs_repair.dart` | 웹 localStorage 에 JSON 이 아닌 TrimBox 값이 있으면 시작 시 지운다 (shared_preferences_web 은 그런 값을 조용히 건너뛰어 쓰레기가 남음). 조건부 import, 비웹은 no-op |
| `lib/widgets/add_box_dialog.dart` | 장비 선택 다이얼로그 (프리셋 198개 — 2026-09-17 교차검증 `backlog/gear-db-audit.md`, 번들 3종, 검색, 수량) |
| `lib/widgets/box_list_panel.dart` | 박스 목록·판정 버튼·통계 패널 (모바일 시트 겸용, 폰 가로는 `compact` 압축 배치) |

### Screen Layout
- 폭 > 900: 캔버스 3 : 패널 1 옆 패널. 폰 세로: `DraggableScrollableSheet` (초기 높이 목표 220px = 손잡이+빈 상태 안내+CTA, 본문 높이의 28~50%로 클램프 → 390×844 는 28% 그대로). 폰 가로(가로가 더 길고 높이 < 500): 오른쪽 300px 압축 패널(한 줄 액션바 · 36px 히어로 줄 · 통계 한 줄, 목록 3행 이상).
- 스텝 뷰 컨트롤은 캔버스 왼쪽 위 고정 폭 316px (라벨 160px 고정이라 ✕ ‹ › 가 단계마다 움직이지 않음). 캔버스 왼쪽 아래는 캡션·테일게이트 상태 알약 자리다. 알약은 걸림(빨강) → 트렁크 밖 미적재 짐(주황 "미적재 N개") → 초록 순.
- 온보딩 조작법은 터치 폼팩터(Android/iOS 또는 짧은 변 < 600 또는 터치 입력 있음)면 제스처 안내, 아니면 마우스·단축키 안내. 캔버스 높이 < 450 이면 압축 카드(폭이 되면 두 단).
- 판정·자동배치·조언 다이얼로그는 `scrollable` + `actionsOverflowButtonSpacing: 8`. 화면에 입력란이 없으므로 `resizeToAvoidBottomInset: false`.

### Vehicle Presets
1차 메뉴에는 쏘렌토 두 구성 + 커스텀만 노출된다 (`_releasePresets`). 나머지 프리셋(투싼·싼타페·카니발·아이오닉5·아반떼)은 코드와 테스트에 남아 있다.

쏘렌토 MQ4 는 줄자 실측 8건과 기아 도면으로 교차검증했다 (`backlog/sorento-mq4-measurements.md`). 5인승과 7인승(3열 접음)은 같은 상자 치수이고 바닥 아래 수납함만 다르다(미모델링).

| 항목 | 값 | 신뢰도 |
|---|---|---|
| 최대 폭 w / 휠하우스 사이 | 1.38 / 1.09 | 높음 |
| 바닥 깊이 d (2열 최후방) | 1.07 (+2열 슬라이드 0~0.27) | 높음 |
| 높이 h → 개구부 | 0.82 → 0.79 (`rearCeilingDrop 0.03`) | 중간 |
| 휠하우스(좁은 구간) w×d×h | 0.145 × 0.69 × 0.30 — 폭 138 구간은 테일게이트 쪽 38cm 뿐 | 폭 높음, 길이 중간, 높이 추정 |
| 개구부 (바닥/상단 폭, 높이, 프레임 턱) | 1.10 / 1.05, 0.79, 0.02 | 바닥 폭 높음, 나머지 추정 |
| 테일게이트 프로필 (y → 안쪽 inset) | (0,0) (0.48,0.03) (0.52,0.06) (0.79,0.18) | 중간 |
| 등받이 프로필 | (0,0) (0.60,0.15) (0.82,0.15) | 낮음 — 약 14° |
| 실사용 부피 | 약 950 L (ADAC 실측 980 L) | – |

2026-09-18 에 실제 적재 사례(ADAC 용량, What Car? 캐리어 10개, 골프백·캐리어·캐노피 가방 오너 후기)로 보정했다. 사례는 `test/validation/real_world_sorento_test.dart` 가 지킨다 — 치수를 바꾸면 이 테스트부터 돌린다.

형상 규칙: 좌우 경계는 개구부 프레임 구간(z ≥ d − 0.12)에서 개구부 폭으로, 천장 60% 위에서 텀블홈(`ceilingNarrow`)만큼 좁아진다. 천장은 테일게이트 쪽으로 낮아진다. 짐 윗면이 높을수록 뒤(테일게이트)와 앞(등받이) 한계가 안쪽으로 들어오며, 박스는 윗면 높이에서의 한계만 검사하면 된다(프로필이 단조). 다른 프리셋은 옛 세단형 규칙(`ceilingDrop`, `taperRatio`, `rearTopNarrow`)을 그대로 쓴다.

2열 슬라이드: `TrunkSpace.sorento(seatSlide: 0..0.27)`. 바닥 d 가 그만큼 길어지고 차체에 붙은 휠하우스는 `Wheelhouse.zStart` 만큼 등받이에서 멀어진다. 당긴 만큼은 바닥이 없는 빈틈(`floorStartZ`)이라, 바닥면의 절반 이상이 실제 바닥에 걸쳐야 지지된다(`SupportRule.floorSupportRatio`). 앱바의 "2열 최후방/중간/최전방" 메뉴, 판정 다이얼로그의 "2열 +Ncm 적용" 제안이 이것을 쓴다.

### 짐 물리 규칙 (2순위, 2026-09-17)
- 연질 짐(`soft`)은 `compressibility` 까지 한 축만 눌러 넣는다: 높이 절반 → 높이 최대 → 깊이 최대. 실제 치수는 `effectiveW/D/H`, 공칭 치수 `w/d/h` 는 유지. 자동배치는 연질 짐을 단단한 짐 뒤에 넣고, 필요한 만큼만 누른다.
- 무게: 20kg 이상(`floorOnlyKg`)은 바닥에만, 12kg 이상(`heavyKg`)은 낮고 깊게 선호. 8kg 이상 짐을 자기 무게 40% 미만 짐 위에 올리면 벌점·조언. 5kg 이상 단단한 짐은 연질 짐 위에 안 놓는다.
- `accessPriority`(쿨러·냉장고·구급함)는 테일게이트 쪽 선호.
- 규칙의 문턱은 `AutoLayoutEngine` 상수 하나에 있고 `PackingAdvisor` 가 같은 상수를 쓴다.
- 연질 짐은 높이가 5cm 까지 다른 받침(예: 28cm 가방 + 30cm 휠하우스) 위에 걸쳐도 받쳐진다(`softSagTol`). 세워 싣는 짐은 개구부보다 3cm 높아도 기울여 통과(`uprightTiltAllowance`).
- 패커 단계: 정렬 변형(바닥 전용 짐 먼저, 연질 뒤) → 세워 놓기 편향·연질 촘촘 패스 → 못 넣은 것 먼저 재시도 → 무작위 재시도(8회 연속 개선 없으면 중단) → 결선(최선 + 재시도 0회의 최선)을 각각 보수 → 승자만 전체 곱 탐색 → 4cm 격자 채우기(2개). 후보는 극점 쌍 O(n) 이고, 모든 한도는 시간이 아니라 횟수라서 기기 속도와 무관하게 같은 판정이 나온다.

## Development Commands

```bash
flutter pub get
flutter run -d chrome        # 개발 실행
flutter test                 # 단위·위젯·검증 테스트 (680여 개, 약 3분)
flutter analyze
flutter build web            # 웹 빌드 → build/web
npx playwright test          # 브라우저 E2E 32개, 약 12분 (build/web 을 서빙, 스크린샷은 e2e/screenshots/). 빠른 확인은 npx playwright test e2e/smoke.spec.ts
flutter build apk --debug    # Android (JDK 17 필요: flutter config --jdk-dir <JDK17>)
```

WSL 에서 작업할 때는 Windows Flutter 를 `cmd.exe /c "flutter ..."` 로 실행한다. 줄바꿈은 `.gitattributes` 로 LF 정규화되어 있다.

## Conventions
- 새 규칙을 추가할 때 화면·엔진·테스트에 각각 복사하지 말 것. `CollisionDetector` / `SupportRule` 에만 넣는다.
- 자동배치 결과는 반드시 물리 검증(충돌 0, 부양 0)을 통과해야 한다. `test/models/auto_layout_test.dart` 의 `expectPhysicallyValid` 를 재사용한다.
- 웹 E2E 는 고정 뷰포트 좌표 클릭 + 스크린샷 픽셀 단언이다(`e2e/helpers.ts`: 스낵바·상태 알약·패널 상태 행의 색, 영역 diff, 콘솔 에러 시 실패). 레이아웃을 바꾸면 `e2e/helpers.ts`(데스크톱 `D`/`RD`), `e2e/smoke.spec.ts`, `e2e/mobile.spec.ts`(폰 `M`/`RM`, 크기별 `SANITY`) 의 좌표를 갱신한다. 새 좌표는 위젯 테스트에서 `tester.getRect(...)` 를 `debugPrint` 로 찍어 얻는다(`simulator_edit_test.dart` 의 STEP-VIEW-COORDS 처럼; 상태 알약은 페인터가 그리므로 캔버스 아래에서 41~71px 위, x 4~134 영역). 데스크톱 좌표가 여전히 맞는지는 `test/widgets/simulator_smoke_coords_test.dart` 가 먼저 알려 준다. `SemanticsBinding.ensureSemantics()` 를 웹에서 켜면 포인터 입력이 먹지 않으므로 쓰지 않는다.
- 커밋 전 `flutter test` 와 `flutter analyze`. 한국어 커밋 메시지.

## Status (2026-09-18)
완료: 3D 코어 재작성(W1), 자동배치 재작성(W2), 추가 즉시 자동 배치·자동 저장·모바일 시트·Android 저장소(W3), 문서·스모크 테스트(W4 일부), 쏘렌토 MQ4 실측 교차검증 + 테일게이트 닫힘·개구부·등받이 기울기 모델(W5), 장비 DB 교차검증 + 연질·무게·접근성 규칙 + 2열 슬라이드(W6), 보이는 현실감(고정물·짐 모양 메시) + 실제 적재 사례 검증·모델 보정 + 테스트 대확장(W7), 브라우저 E2E 32개가 찾은 UI 9건 수정 — 스텝 컨트롤 고정, 폰 가로 압축 패널, 작은 폰 시트 높이, 낮은 화면 온보딩, 터치 조작법, 미적재 주황 알약, 차종 메뉴 설명 줄, 빈 배치 저장 차단, 웹 저장소 복구(W8).
남은 것: 사용자 실측으로 프로필 보정(체크리스트는 measurements 문서 5절), Android 실기기 확인, 공유 이미지 정리, 장비 치수 미확인 항목(gear-db-audit 5절).
