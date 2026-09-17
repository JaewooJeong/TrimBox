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
- 유효성 판단은 `lib/utils/collision.dart` 의 `CollisionDetector` 하나가 단일 진실이다. 자동배치·화면·테스트가 모두 이것을 쓴다. 지지/중력 규칙은 `lib/models/support.dart` 의 `SupportRule` 하나.

### Key Files
| File | Purpose |
|------|---------|
| `lib/screens/simulator_screen.dart` | 메인 화면: 상태, 카메라 조작, 드래그, 자동배치 호출, 저장/복원 |
| `lib/render3d/camera.dart` | `OrbitCamera` — 투영/역투영, 트렁크 맞춤(fitTrunk), 각도·거리 제한 |
| `lib/render3d/geometry.dart` | `Aabb`, `Face`, 트렁크 껍데기 면 생성, AABB 면, 램버트 음영 |
| `lib/render3d/depth_sort.dart` | 뒤→앞 위상 정렬 (모든 분리축이 일치할 때만 순서 제약) |
| `lib/render3d/picking.dart` | 레이-AABB, 레이-수평면 교차 |
| `lib/render3d/trunk_painter_3d.dart` | 페인터: 껍데기 Picture 캐시, 바닥 격자, 박스 면/그림자/라벨/순서 배지 |
| `lib/models/auto_layout.dart` | 자동배치 엔진 (극점 후보 + 눕히기 + 떨어뜨리기 + 검증 게이트 + 재시도) |
| `lib/models/support.dart` | 적층/중력 규칙 `SupportRule` (지지 면적 50% 이상) |
| `lib/models/trunk_space.dart` | 트렁크 모델, 형상 함수(ceilingHeightAt/taperAt/topNarrowAt), 프리셋, `usableVolume` |
| `lib/models/trim_box.dart` | 박스 모델 (위치, rotY, keepUpright, loadOrder) |
| `lib/utils/collision.dart` | AABB 충돌: 박스-박스(0.5mm 허용), 경계·테이퍼·C필러·천장, 휠하우스 |
| `lib/utils/scene_storage.dart` | shared_preferences 저장소: 이름 저장, 자동 저장, 온보딩 플래그 |
| `lib/widgets/add_box_dialog.dart` | 장비 선택 다이얼로그 (프리셋 199개, 번들 3종, 검색, 수량) |
| `lib/widgets/box_list_panel.dart` | 박스 목록·판정 버튼·통계 패널 (모바일 시트 겸용) |

### Vehicle Presets
1차 메뉴에는 쏘렌토 두 구성 + 커스텀만 노출된다 (`_releasePresets`). 나머지 프리셋(투싼·싼타페·카니발·아이오닉5·아반떼)은 코드와 테스트에 남아 있다.

| Preset | W | D | H | 휠하우스 (w×d×h) | 비고 |
|--------|---|---|---|---|---|
| 쏘렌토 5인승 (`sorento`) | 1.08 | 1.10 | 0.78 | 0.08×0.48×0.30 | 추정치. 근거는 `trunk_space.dart` 주석 |
| 쏘렌토 7인승·3열 접음 (`sorento7`) | 1.08 | 1.18 | 0.77 | 0.08×0.52×0.30 | 추정치 |

트렁크 형상: `ceilingHeightAt(z)` 뒤쪽(z=0)으로 갈수록 천장이 2차식으로 내려옴, `topNarrowAt(z)` C필러 상단 좁아짐, `taperAt(z)` 바닥 테이퍼. 충돌은 AABB + 이 함수들로 판정한다.

## Development Commands

```bash
flutter pub get
flutter run -d chrome        # 개발 실행
flutter test                 # 단위/통합 테스트 (164개)
flutter analyze
flutter build web            # 웹 빌드 → build/web
npx playwright test          # 스모크 E2E (build/web 을 서빙, 스크린샷은 e2e/screenshots/)
flutter build apk --debug    # Android (JDK 17 필요: flutter config --jdk-dir <JDK17>)
```

WSL 에서 작업할 때는 Windows Flutter 를 `cmd.exe /c "flutter ..."` 로 실행한다. 줄바꿈은 `.gitattributes` 로 LF 정규화되어 있다.

## Conventions
- 새 규칙을 추가할 때 화면·엔진·테스트에 각각 복사하지 말 것. `CollisionDetector` / `SupportRule` 에만 넣는다.
- 자동배치 결과는 반드시 물리 검증(충돌 0, 부양 0)을 통과해야 한다. `test/models/auto_layout_test.dart` 의 `expectPhysicallyValid` 를 재사용한다.
- 웹 E2E 는 고정 뷰포트 좌표 클릭이다. 레이아웃을 바꾸면 `e2e/smoke.spec.ts` 좌표를 갱신한다. `SemanticsBinding.ensureSemantics()` 를 웹에서 켜면 포인터 입력이 먹지 않으므로 쓰지 않는다.
- 커밋 전 `flutter test` 와 `flutter analyze`. 한국어 커밋 메시지.

## Status (2026-09-17)
완료: 3D 코어 재작성(W1), 자동배치 재작성(W2), 추가 즉시 자동 배치·자동 저장·모바일 시트·Android 저장소(W3), 문서·스모크 테스트(W4 일부).
남은 것: 쏘렌토 MQ4 실측치 확정(현재 추정치), Android 실기기 확인, 공유 이미지 정리, 스텝 뷰/JSON 내보내기 등 2차 기능 정리.
