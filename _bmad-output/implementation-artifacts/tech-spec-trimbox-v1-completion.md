---
title: 'TrimBox Simulator v1 완성'
slug: 'trimbox-v1-completion'
created: '2026-02-20'
status: 'completed'
stepsCompleted: [1, 2, 3, 4]
team: 'Sugarmount'
tech_stack: ['Flutter 3.9+', 'Dart', 'CustomPainter', 'flutter_test']
files_to_modify:
  - 'lib/models/trunk_space.dart'
  - 'lib/models/trim_box.dart'
  - 'lib/screens/simulator_screen.dart'
  - 'lib/widgets/box_list_panel.dart'
files_to_create:
  - 'lib/widgets/trunk_size_dialog.dart'
  - 'test/models/trim_box_test.dart'
  - 'test/models/trunk_space_test.dart'
  - 'test/models/scene_test.dart'
  - 'test/utils/collision_test.dart'
code_patterns: ['StatefulWidget', 'CustomPainter', 'AABB collision', 'isometric projection', 'enum + named constructors']
test_patterns: ['flutter_test unit tests', 'group/test structure']
---

# Tech-Spec: TrimBox Simulator v1 완성

**Created:** 2026-02-20
**Team:** Sugarmount

## Overview

### Problem Statement

TrimBox Simulator의 핵심 기능(아이소메트릭 뷰, 박스 CRUD, 드래그앤드롭, 충돌감지, JSON 저장/불러오기)은 구현되었으나, PRD 1단계 완성에 필요한 기능이 미구현 상태.

### Solution

PRD 1단계 미구현 기능 4개 + 테스트를 추가 구현하여 v1을 완성한다:
1. 트렁크 크기 선택 (프리셋 + 커스텀)
2. 경계 밖 배치 차단 (드래그 클램핑)
3. 공간 효율 표시 (면적 점유율)
4. 유닛 테스트

### Scope

**In Scope:**
- 트렁크 크기 프리셋(SUV/세단/밴) + 커스텀 입력 UI (AppBar 드롭다운)
- 드래그 시 경계 클램핑 (트렁크 영역 밖으로 이동 불가)
- 트렁크 크기 변경 시 기존 박스 클램핑 (경계 밖 박스 자동 재배치)
- 패널 하단 통계바에 바닥 면적 점유율(%) + LinearProgressIndicator 추가
- 모델/충돌/JSON 직렬화 유닛 테스트

**Out of Scope:**
- 3D/2D 뷰 전환 (v1.1로 이관)
- 자동 최적 배치 (Bin Packing) — 2단계
- AR 확장
- 위젯/통합 테스트
- 스크린샷/공유 기능
- 라이트 모드

## Context for Development

### Codebase Patterns

- **상태 관리**: `StatefulWidget` + `setState()` (별도 상태 관리 라이브러리 없음)
- **렌더링**: `CustomPainter` (IsometricPainter) + `RepaintBoundary`
- **좌표 변환**: 3D(x,y,z) → 2D 아이소메트릭 (`toIso`), 역변환 (`_screenToIsoX/Dx`)
- **충돌**: AABB 기반 `CollisionDetector` 클래스
- **모델**: `TrimBox`, `TrunkSpace`, `Scene` — 모두 `toJson()`/`fromJson()` 지원
- **그리드 스냅**: `box.snapToGrid(gridUnit)` — 10cm 단위
- **반응형**: `LayoutBuilder` 기반 (> 700px 우측 패널, 아니면 하단 패널)

### Anchor Points (코드 수정 위치)

#### Feature 1: 트렁크 크기 프리셋
| 위치 | 파일:라인 | 현재 코드 | 변경 내용 |
|------|-----------|-----------|-----------|
| `_space` 선언 | `simulator_screen.dart:34` | `final TrunkSpace _space = TrunkSpace.defaultSUV()` | `late TrunkSpace _space` 로 변경 |
| `_detector` 초기화 | `simulator_screen.dart:52,57` | `late final CollisionDetector _detector` | `late CollisionDetector _detector` (final 제거) |
| AppBar 빌드 | `simulator_screen.dart:64-69` | 단순 Text 타이틀 | `title: Row(...)` + DropdownButton 추가 |
| 프리셋 팩토리 | `trunk_space.dart:36-42` | `defaultSUV()` 만 존재 | `.sedan()`, `.van()` 추가 |
| `_scale` 상수 | `simulator_screen.dart:50` | `static const double _scale = 280.0` | 제거, 동적 계산으로 전환 |
| `_toIso` 메서드 | `simulator_screen.dart:281-285` | `_scale` 상수 참조 | `_lastScale` 동적 값 참조 |
| `_screenToIsoX/Dx` | `simulator_screen.dart:222-228` | `_scale` 상수 참조 | `_lastScale` 동적 값 참조 |

#### Feature 2: 드래그 클램핑
| 위치 | 파일:라인 | 현재 코드 | 변경 내용 |
|------|-----------|-----------|-----------|
| 드래그 업데이트 | `simulator_screen.dart:167-168` | `box.x = _dragStartX + dx3d` | clamp 추가 |
| 드래그 종료 | `simulator_screen.dart:177` | `snapToGrid`만 호출 | snapToGrid 후 clampTo 호출 |
| 키보드 이동 | `simulator_screen.dart:193-203` | 바운드 체크 없음 | clamp 추가 |
| clampTo 메서드 | `trim_box.dart:39` 근처 | 없음 | `clampTo(double maxW, double maxD)` 추가 |

#### Feature 3: 공간 효율 표시
| 위치 | 파일:라인 | 현재 코드 | 변경 내용 |
|------|-----------|-----------|-----------|
| BoxListPanel 생성자 | `box_list_panel.dart:17-28` | space 파라미터 없음 | `TrunkSpace space` 추가 |
| BoxListPanel 호출 | `simulator_screen.dart:120-130` | space 미전달 | `space: _space` 추가 |
| 통계바 | `box_list_panel.dart:175-197` | 부피만 표시 | 면적 점유율 + 프로그레스 바 추가 |

#### Feature 4: 유닛 테스트
| 대상 | 테스트 파일 | 상태 |
|------|------------|------|
| TrimBox 모델 | `test/models/trim_box_test.dart` | 신규 생성 |
| TrunkSpace 모델 | `test/models/trunk_space_test.dart` | 신규 생성 |
| Scene 직렬화 | `test/models/scene_test.dart` | 신규 생성 |
| CollisionDetector | `test/utils/collision_test.dart` | 신규 생성 |

### Files to Reference

| File | Purpose |
| ---- | ------- |
| `lib/models/trunk_space.dart` | 트렁크/휠하우스 모델 — 프리셋 + enum 추가 대상 |
| `lib/models/trim_box.dart` | 박스 모델 — `clampTo()` 메서드 추가 |
| `lib/models/scene.dart` | 씬 직렬화 — 테스트 대상 |
| `lib/screens/simulator_screen.dart` | 메인 화면 — AppBar 크기 선택, 클램핑, 효율 표시, scale 자동 계산 |
| `lib/utils/collision.dart` | 충돌 감지 — 테스트 대상 |
| `lib/widgets/box_list_panel.dart` | 패널 — 통계바에 점유율 프로그레스 바 추가 |
| `lib/widgets/add_box_dialog.dart` | 기존 다이얼로그 패턴 참조 |

### Technical Decisions

- **프리셋 구조**: `enum TrunkPreset { suv, sedan, van, custom }` — `trunk_space.dart`에 배치
- **트렁크 프리셋**: `TrunkSpace`에 named constructor 패턴 (`TrunkSpace.defaultSUV()`, `.sedan()`, `.van()`, `.custom(...)`)
- **프리셋 라벨**: 치수 포함 표기 (예: `SUV (108×107cm)`)
- **크기 선택 UI**: AppBar `title: Row([Text('TrimBox'), SizedBox, DropdownButton<TrunkPreset>])` — actions는 v1.1 뷰 전환용 예약
- **커스텀 휠하우스**: 기본값 0 (없음), `ExpansionTile`로 접힌 상태 기본
- **커스텀 크기 다이얼로그**: `lib/widgets/trunk_size_dialog.dart` 신규 생성 (AddBoxDialog 패턴 참조)
- **클램핑 구조**: `TrimBox.clampTo(double maxW, double maxD)` 메서드 + Screen에서 루프 호출
- **`_space` 동적 변경**: `late TrunkSpace` + `CollisionDetector` 재생성
- **크기 변경 시 박스 처리**: `setState(() { ... })` 블록 안에서 전체 박스 클램핑 → `_updateCollisions()` (중간 불일치 상태 방지)
- **커스텀 드롭다운 라벨**: custom 선택 후 드롭다운에 `커스텀 (W×Dcm)` 동적 표시 (`selectedItemBuilder` 활용)
- **scale 자동 계산**: 아이소메트릭 투영 범위 기반 동적 계산
  ```
  isoWidth = (space.w + space.d) * cos(30°)
  isoHeight = (space.w + space.d) * sin(30°) + space.h
  scaleX = canvasWidth * 0.8 / isoWidth
  scaleY = canvasHeight * 0.8 / isoHeight
  scale = min(scaleX, scaleY)
  ```
- **scale 구조**: `_calculateScale(Size canvasSize)` 순수 메서드 + `_lastScale` 인스턴스 변수 캐싱 (드래그 핸들러에서 참조)
- **효율 계산**: `(박스면적합 / (space.w * space.d - 좌휠면적 - 우휠면적)) * 100`
- **효율 색상**: `Color.lerp(red, green, ratio)` 그라데이션
- **테스트**: `flutter_test` 패키지만 사용, 외부 의존성 없음

## Implementation Plan

### Tasks

- [x] **Task 1: TrunkPreset enum + 프리셋 팩토리 추가**
  - File: `lib/models/trunk_space.dart`
  - Action:
    - `enum TrunkPreset { suv, sedan, van, custom }` 추가
    - `TrunkPreset`에 extension: `label` (예: `SUV (108×107cm)`), `toTrunkSpace()` (custom은 null 반환)
    - `TrunkSpace.sedan()` 팩토리 추가 (w:0.90, d:0.85, h:0.65, 휠하우스 w:0.15 d:0.30 h:0.10)
    - `TrunkSpace.van()` 팩토리 추가 (w:1.30, d:1.20, h:0.90, 휠하우스 w:0.20 d:0.40 h:0.15)
    - `TrunkSpace.custom()` 팩토리 추가 (모든 파라미터 필수)

- [x] **Task 2: TrimBox.clampTo() 메서드 추가**
  - File: `lib/models/trim_box.dart`
  - Action:
    - `snapToGrid()` 아래에 `clampTo(double maxW, double maxD)` 추가
    - `x = x.clamp(0, maxW - effectiveW)`, `z = z.clamp(0, maxD - effectiveD)`
  - Notes: effectiveW/D 사용하여 회전 상태 반영

- [x] **Task 3: 커스텀 트렁크 크기 다이얼로그 생성**
  - File: `lib/widgets/trunk_size_dialog.dart` (신규)
  - Action:
    - `AddBoxDialog` 패턴 참조하여 `TrunkSizeDialog` 위젯 생성
    - 필수 필드: 트렁크 가로(cm), 세로(cm), 높이(cm) — 양수만 허용
    - 선택 필드: `ExpansionTile` '휠하우스 (선택)' — 좌/우 W/D/H (기본 0)
    - 유효성 검증: 음수/0/빈 값 입력 시 에러 메시지 표시
    - 반환: `TrunkSpace` 인스턴스 또는 null (취소)
  - Notes: 디자인 토큰 색상 유지 (backlog/uiux.md 참조)

- [x] **Task 4: AppBar 드롭다운 + _space 동적 변경 + scale 자동 계산** (통합)
  - File: `lib/screens/simulator_screen.dart`
  - Action:
    - `final TrunkSpace _space` → `late TrunkSpace _space` 변경 (line 34)
    - `late final CollisionDetector _detector` → `late CollisionDetector _detector` 변경 (line 52)
    - `static const double _scale = 280.0` 제거 (line 50)
    - `double _lastScale = 280.0` 인스턴스 변수 추가
    - `_calculateScale(Size canvasSize)` 순수 메서드 추가:
      ```
      isoWidth = (_space.w + _space.d) * _cosA
      isoHeight = (_space.w + _space.d) * _sinA + _space.h
      scaleX = canvasSize.width * 0.8 / isoWidth
      scaleY = canvasSize.height * 0.8 / isoHeight
      return min(scaleX, scaleY)
      ```
    - `_buildCanvas()` 내부에서 scale 계산 후 `_lastScale` 갱신, `IsometricPainter(scale: _lastScale, ...)` 전달
    - `_toIso()` 메서드 (line 281-285): `_scale` → `_lastScale` 참조로 변경
    - `_screenToIsoX()`, `_screenToIsoDx()` (line 222-228): `_scale` → `_lastScale` 참조로 변경
    - `_selectedPreset` 상태 변수 추가 (`TrunkPreset _selectedPreset = TrunkPreset.suv`)
    - `initState()`에서 `_space = TrunkPreset.suv.toTrunkSpace()!; _detector = CollisionDetector(_space);`
    - AppBar `title`을 `Row`로 변경: `Text('TrimBox') + SizedBox(width:16) + DropdownButton<TrunkPreset>`
    - 드롭다운 onChange 핸들러 `_onPresetChanged(TrunkPreset)`:
      - custom이면 `TrunkSizeDialog` 표시, 결과 null이면 무시
      - 그 외: `_space = preset.toTrunkSpace()!`
      - 전체 변경을 `setState(() { ... })` 블록으로 감싸기:
        - `_detector = CollisionDetector(_space)`
        - 전체 박스 `clampTo(_space.w, _space.d)` + `snapToGrid` 호출
        - `_updateCollisions()`
    - 커스텀 선택 시 드롭다운 `selectedItemBuilder`로 `커스텀 (${(_space.w*100).round()}×${(_space.d*100).round()}cm)` 동적 라벨 표시

- [x] **Task 5: 드래그 클램핑 적용**
  - File: `lib/screens/simulator_screen.dart`
  - Action:
    - `_onPanUpdate` (line 167-168): `box.x`/`box.z` 설정 후 `box.clampTo(_space.w, _space.d)` 호출
    - `_onPanEnd` (line 177): `snapToGrid` 후 `box.clampTo(_space.w, _space.d)` 호출
    - `_onKeyEvent` (line 193-203): 각 방향키 이동 후 `box.snapToGrid` → `box.clampTo(_space.w, _space.d)` 순서 호출

- [x] **Task 6: 공간 효율 표시**
  - File: `lib/widgets/box_list_panel.dart`
  - Action:
    - 생성자에 `required this.space` 파라미터 추가
    - `_statsBar()` 메서드 수정:
      - 유효 면적 계산: `space.w * space.d - (space.leftWheelhouse.w * space.leftWheelhouse.d) - (space.rightWheelhouse.w * space.rightWheelhouse.d)`
      - 박스 면적 합: `boxes.fold(0.0, (sum, b) => sum + b.effectiveW * b.effectiveD)`
      - 점유율: `(boxArea / effectiveArea * 100).clamp(0, 100)`
      - `LinearProgressIndicator(value: ratio, color: Color.lerp(Color(0xFFFF4D4D), Color(0xFF6BD06B), ratio))` 추가
      - 퍼센트 텍스트: `점유율: XX%`
  - File: `lib/screens/simulator_screen.dart`
  - Action:
    - `_buildPanel()`에서 `BoxListPanel` 호출 시 `space: _space` 추가

- [x] **Task 7: 유닛 테스트 — TrimBox**
  - File: `test/models/trim_box_test.dart` (신규)
  - Action:
    - group 'TrimBox':
      - test '생성 및 기본값 검증'
      - test '90도 회전 시 effectiveW/D 스왑'
      - test '360도 회전 시 원래 방향 복귀'
      - test 'snapToGrid 10cm 단위'
      - test 'clampTo 경계 내 유지'
      - test 'clampTo 회전 상태 반영'
      - test 'toJson/fromJson 라운드트립'
      - test 'copyWith 동작'

- [x] **Task 8: 유닛 테스트 — TrunkSpace**
  - File: `test/models/trunk_space_test.dart` (신규)
  - Action:
    - group 'TrunkSpace':
      - test 'defaultSUV 치수 검증'
      - test 'sedan 치수 검증'
      - test 'van 치수 검증'
      - test 'custom 생성'
      - test 'toJson/fromJson 라운드트립'
    - group 'TrunkPreset':
      - test 'label에 치수 포함'
      - test 'toTrunkSpace 반환값 검증'
      - test 'custom은 null 반환'

- [x] **Task 9: 유닛 테스트 — Scene**
  - File: `test/models/scene_test.dart` (신규)
  - Action:
    - group 'Scene':
      - test '빈 씬 직렬화/역직렬화'
      - test '박스 포함 씬 라운드트립'
      - test 'toJsonString/fromJsonString 일관성'
      - test '기본 버전/그리드 값'

- [x] **Task 10: 유닛 테스트 — CollisionDetector**
  - File: `test/utils/collision_test.dart` (신규)
  - Action:
    - group 'CollisionDetector':
      - test '겹치지 않는 두 박스'
      - test '겹치는 두 박스'
      - test '경계 밖 박스 감지'
      - test '경계 내 박스 정상'
      - test '왼쪽 휠하우스 겹침'
      - test '오른쪽 휠하우스 겹침'
      - test '휠하우스 위 박스 (y > 휠하우스 높이) 정상'
      - test 'findAllCollisions 종합'

### Acceptance Criteria

- [x] **AC-1**: Given 앱이 실행되면, when AppBar를 보면, then 'TrimBox' 타이틀 옆에 트렁크 크기 드롭다운이 표시된다
- [x] **AC-2**: Given 드롭다운에서 '세단'을 선택하면, when 트렁크 뷰를 보면, then 세단 크기(90×85cm)의 트렁크가 표시되고 scale이 자동 조정된다
- [x] **AC-3**: Given 드롭다운에서 '커스텀'을 선택하면, when 다이얼로그가 열리면, then 트렁크 W/D/H 입력 필드와 접힌 휠하우스 설정이 보인다
- [x] **AC-3b**: Given 커스텀 다이얼로그에서 유효한 값을 입력하고 확인하면, when 트렁크 뷰를 보면, then 입력한 크기의 트렁크가 표시된다
- [x] **AC-4**: Given SUV에 박스를 배치한 상태에서, when 세단으로 변경하면, then 경계 밖 박스가 세단 영역 내로 자동 클램핑된다
- [x] **AC-5**: Given 박스를 드래그할 때, when 트렁크 경계에 도달하면, then 박스가 경계 밖으로 나가지 않고 멈춘다
- [x] **AC-6**: Given 키보드 화살표로 박스를 이동할 때, when 경계에 도달하면, then 더 이상 이동하지 않는다
- [x] **AC-7**: Given 박스를 배치하면, when 패널 하단 통계바를 보면, then 면적 점유율(%)과 프로그레스 바가 표시된다
- [x] **AC-8**: Given 점유율이 높아지면, when 프로그레스 바 색상을 보면, then 빨강→초록 그라데이션으로 변한다
- [x] **AC-9**: Given 트렁크 크기를 변경하면, when 뷰의 scale을 보면, then 새 크기에 맞게 자동 조정된다
- [x] **AC-10**: Given `flutter test` 실행 시, when 모든 테스트가 돌아가면, then 100% 통과한다
- [x] **AC-11**: Given 커스텀 다이얼로그에서 음수/0을 입력하면, when 확인 버튼을 누르면, then 에러 메시지가 표시되고 트렁크가 변경되지 않는다

## Additional Context

### Dependencies

- 추가 패키지 불필요 (Flutter SDK 내장 기능만 사용)
- Task 4는 Task 1~2에 의존 (프리셋/clampTo 먼저)
- Task 5는 Task 2에 의존 (clampTo 메서드)
- Task 6은 Task 1에 의존 (BoxListPanel에 space 파라미터)
- Task 7~10은 Task 1~2에 의존 (프리셋/clampTo 테스트 포함)

### Testing Strategy

- `test/models/trim_box_test.dart` — 생성, 회전, snapToGrid, clampTo, toJson/fromJson
- `test/models/trunk_space_test.dart` — 프리셋 팩토리, enum, 치수 검증, toJson/fromJson
- `test/models/scene_test.dart` — 직렬화/역직렬화 라운드트립
- `test/utils/collision_test.dart` — 박스 겹침, 경계 초과, 휠하우스 겹침, findAllCollisions
- 수동 테스트: 드래그 클램핑, 크기 전환 시 뷰 변화, 프로그레스 바 색상 확인

### Commit Strategy

1. **커밋 1**: Task 1-2 — 모델 변경 (프리셋 enum/팩토리 + clampTo)
2. **커밋 2**: Task 3-4 — UI (커스텀 다이얼로그 + AppBar 드롭다운 + scale 자동 계산)
3. **커밋 3**: Task 5 — 드래그 클램핑
4. **커밋 4**: Task 6 — 공간 효율 표시
5. **커밋 5**: Task 7-10 — 유닛 테스트

### Notes

- 팀: Sugarmount
- 기존 backlog 문서: `backlog/prd.md`, `backlog/uiux.md`, `backlog/uiflow.md`
- 디자인 토큰은 `backlog/uiux.md`에 정의됨
- test/ 디렉토리 비어있음 — 신규 생성 필요
- v1.1 후보: 3D/2D 뷰 전환 (TopDownPainter), 회전 애니메이션 (200ms)

## Review Notes
- Adversarial review completed
- Findings: 19 total, 7 fixed, 12 skipped (noise/out-of-scope)
- Resolution approach: auto-fix
- Fixed: F1(FocusNode leak), F2(build mutation), F4(delete+snap), F5(load space), F6(ID collision), F9(rotate clamp), F18(test gap)
