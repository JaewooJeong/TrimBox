# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

TrimBox Simulator는 캠핑용 트렁크 짐 적재 시뮬레이터입니다.
캠퍼가 자신의 차량(쏘렌토, 싼타페 등)을 선택하고, 캠핑 장비를 목록에서 골라 트렁크에 자동/수동 배치하여 적재 가능 여부를 시각적으로 확인하는 앱입니다.

**핵심 가치**: "내 캠핑 짐이 내 차 트렁크에 들어가는지 3초 안에 확인"
**타겟 유저**: 주말 캠퍼, 캠핑 입문자(캠린이), 미니멀 캠퍼
**경쟁자**: 없음 (세계 최초 소비자용 3D 트렁크 패킹 시뮬레이터)

## Architecture

- Flutter web app (package name: `trimbox`)
- **1-point perspective** rendering via `CustomPainter` (class name `IsometricPainter` kept for compat)
- Fixed camera behind trunk looking in
- `toScreen(x,y,z)`: `f = focalLen/(camZ-z)*scale`, `sx = (x-camX)*f`, `sy = -(y-camY)*f`

### Key Files
| File | Purpose |
|------|---------|
| `lib/screens/simulator_screen.dart` | Main screen, interaction, state management |
| `lib/painters/isometric_painter.dart` | Paint orchestrator, perspective projection |
| `lib/painters/trunk_renderer.dart` | Trunk interior (walls, floor, ceiling, seat) |
| `lib/painters/box_renderer.dart` | Box/item rendering with face shading |
| `lib/painters/vehicle_body_renderer.dart` | Opening frame, bumper lip, body surround |
| `lib/painters/guide_renderer.dart` | Grid, labels, stacking guides |
| `lib/models/trunk_space.dart` | Trunk dimensions, shape helpers, presets |
| `lib/models/trim_box.dart` | Box model with position, rotation, category |
| `lib/models/collision_detector.dart` | AABB collision: box-box, bounds, wheelhouse |
| `lib/widgets/add_box_dialog.dart` | Box creation dialog with 48 camping presets |

### Vehicle Presets (6 Korean cars + custom)
| Preset | W(m) | D(m) | H(m) | WH(w×d×h) | Taper | CeilDrop |
|--------|------|------|------|-----------|-------|----------|
| 투싼 | 1.04 | 0.91 | 0.73 | 0.14×0.40×0.35 | 0.06 | 0.08 |
| **쏘렌토** (default) | 1.08 | 1.10 | 0.78 | 0.08×0.40×0.30 | 0.07 | 0.12 |
| 싼타페 | 1.11 | 1.05 | 0.80 | 0.13×0.40×0.35 | 0.06 | 0.10 |
| 카니발 | 1.25 | 0.85 | 0.88 | 0.10×0.30×0.25 | 0.03 | 0.04 |
| 아이오닉5 | 1.00 | 0.95 | 0.73 | 0.15×0.35×0.30 | 0.07 | 0.10 |
| 아반떼 | 1.02 | 0.71 | 0.43 | 0.05×0.30×0.25 | 0.12 | 0.06 |

### Trunk Shape Model
- `ceilingHeightAt(z)`: quadratic ceiling drop toward rear
- `topNarrowAt(z)`: C-pillar linear narrowing
- `taperAt(z)`: bottom-edge linear taper
- Collision detection uses AABB (visual shape != collision geometry)

## Development Commands

```bash
flutter pub get          # Get dependencies
flutter run              # Run in debug mode
flutter test             # Run tests (74 tests)
flutter analyze          # Analyze code
dart format .            # Format code
flutter build web        # Build for web
```

## Current Backlog — MVP Commercialization Roadmap

Based on comprehensive research (2026-03-07):
- Research docs: `backlog/competitive-research.md`, `backlog/research-trunk-dimensions.md`, `backlog/research-auto-layout-algorithms.md`

### Phase 0: Immediate Fixes (parallel, <1 day)
- [x] P0-1: Camping gear presets expanded to 48 items (DONE)
- [ ] P0-2: Preset dimension corrections (Sorento h→0.78, Santa Fe w→1.11/wh→0.13)
- [ ] P0-3: Named save/load (배치 이름 지정 + 시나리오별 저장)

### Phase 1: Core MVP (1 week)
- [ ] P1-1: Gear preset UI with category tree + sub-categories + multi-select
- [ ] P1-2: Auto-layout algorithm (Extreme Point + Best Fit Decreasing)
  - Dart implementation ~200-300 lines
  - Validate placements against ceilingHeightAt/topNarrowAt/taperAt + wheelhouse
  - Treat wheelhouses as pre-placed virtual items
  - Priority packing: heavy→deep+low, fragile→top, frequent→near opening
  - Generate 3-5 alternative layouts, score by utilization/access/stability
- [ ] P1-3: Auto-layout property-based tests

### Phase 2: Usability (1 week)
- [ ] P2-1: Loading order visualization (step-by-step numbered guide)
- [ ] P2-2: Space utilization % + remaining space indicator
- [ ] P2-3: Share card (image + summary "쏘렌토 + 4인 캠핑 → 92% 적재")

### Phase 3: Realism (post-MVP)
- [ ] P3-1: Trunk material textures (carpet floor, plastic walls)
- [ ] P3-2: Vehicle body exterior rendering (bumper, taillights)
- [ ] P3-3: Box shape variety (cylinders for tents, soft shapes for sleeping bags)
- [ ] P3-4: Seat folding visualization
- [ ] P3-5: Alignment snap-to-neighbor guides
- [ ] P3-6: Fix stacked-box drag (screenToFloor for y>0)

### Legacy Epics (deprioritized)
- Epic 07: Camera polish → Phase 3+
- Epic 08: 2D floorplan → Phase 2 candidate
- Epic 10: UX polish → Phase 2-3

## Key Technical Decisions
- Auto-layout algorithm: EP-BFD (Extreme Point + Best Fit Decreasing)
- Non-rectangular trunk: pack in bounding box, validate against shape helpers
- No 3D engine needed — CustomPainter is sufficient
- Camping color palette: olive, dark slate, orange, dark green (not pastels)
- `shouldRepaint` should compare fields instead of always returning true

## Testing Strategy
- 74 tests currently passing (models, painters, collision, stacking)
- Auto-layout needs property-based tests: bounds, no-overlap, ceiling, wheelhouse
- Target: 95% unit test coverage

## Commit Strategy
- Incremental commits per feature
- Run `flutter test` and `flutter analyze` before each commit
- Korean commit messages preferred
