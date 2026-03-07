# Research: 3D Bin Packing & Auto-Layout for TrimBox Simulator

Date: 2026-03-07

## Table of Contents

1. [3D Bin Packing Algorithms](#1-3d-bin-packing-algorithms)
2. [Auto-Layout / Auto-Arrange Strategies](#2-auto-layout--auto-arrange-strategies)
3. [Handling Non-Rectangular Containers (Car Trunks)](#3-handling-non-rectangular-containers)
4. [Visual Packing Tools & UX Patterns](#4-visual-packing-tools--ux-patterns)
5. [Flutter/Dart Implementation Considerations](#5-flutterdart-implementation-considerations)
6. [Realistic Rendering Techniques for 2D Canvas](#6-realistic-rendering-techniques)
7. [Recommended Approach for TrimBox](#7-recommended-approach-for-trimbox)
8. [Open Source References](#8-open-source-references)

---

## 1. 3D Bin Packing Algorithms

The 3D Bin Packing Problem (3D-BPP) is NP-complete. No polynomial-time exact solution exists for practical sizes, so all real-world systems use heuristics or metaheuristics.

### 1.1 Algorithm Families

| Family | Description | Pros | Cons |
|--------|-------------|------|------|
| **Constructive Heuristics** | Build solution incrementally using deterministic rules | Fast, predictable | No optimality guarantee |
| **Metaheuristics** | Iteratively improve an initial solution (GA, SA, Tabu) | Better solutions | Slower, non-deterministic |
| **Exact Algorithms** | Guarantee optimal solution (ILP, branch-and-bound) | Optimal | Impractical for >15 items |
| **ML/RL-based** | Train agents to select placement sequences | Can reach 97% utilization | Requires training data, complex |

### 1.2 Key Constructive Heuristics

#### Bottom-Left-Fill (BLF) / Bottom-Left-Back (BLB)
- Place each item at the lowest, leftmost, backmost position available
- Simple to implement, reasonable results
- Good fit for TrimBox since trunk loads from the opening (back to front)

#### Largest Area Fit First (LAFF)
- Place the box covering the largest floor area first
- Its height becomes the "layer height"
- Subsequent boxes fill the remaining space at that layer level
- When a layer fills, start a new layer above
- Two variants: full 3D stacking within layers, or 2D-only stacking

#### Extreme Point (EP) Heuristics
- When an item is placed at position (x, y, z), generate new candidate positions ("extreme points") by projecting from the item's three exposed corners:
  - (x + width, y, z) -- to the right
  - (x, y + depth, z) -- behind
  - (x, y, z + height) -- above
- Select the best EP for the next item using scoring (e.g., prefer bottom-left-back)
- Very efficient: placing m items generates at most 6m extreme points to evaluate

**This is the recommended core algorithm for TrimBox.** It naturally handles stacking, is easy to extend with constraints, and produces good results.

#### First Fit Decreasing (FFD) / Best Fit Decreasing (BFD)
- Sort items by volume (largest first)
- Place each item using First Fit (first valid position) or Best Fit (tightest fit)
- EP-FFD and EP-BFD combine extreme points with these strategies

#### EB-AFIT (Erhan Baltacioglu, Air Force Institute of Technology)
- Layer-building heuristic with backtracking
- Supports full 6-orientation rotation
- Excellent runtime performance and container utilization
- Well-tested in logistics (C# implementation available)

### 1.3 Sorting Strategies (Pre-Processing)

Items should be sorted before placement. Common strategies:

| Strategy | Sort Key | Best For |
|----------|----------|----------|
| Volume descending | w * d * h | General packing |
| Floor area descending | w * d | Layer-based algorithms |
| Height descending | h | Stable stacking |
| Longest dimension descending | max(w,d,h) | Narrow containers |
| Priority-based | user-defined level | Camping/access order |

### 1.4 Rotation Handling

For each item, test all valid orientations and pick the best:

```
6 orientations for a box (w, d, h):
  (w, d, h)  (w, h, d)  (d, w, h)
  (d, h, w)  (h, w, d)  (h, d, w)
```

For trunk packing, restrict to 2 orientations (rotate 90 degrees on floor only):
- (w, d, h) and (d, w, h)
- Items generally should not be placed on their sides

---

## 2. Auto-Layout / Auto-Arrange Strategies

### 2.1 Packing Priority System

For a camping/travel trunk packing simulator, items need priority beyond just size:

**Weight-based rules:**
- Heavy items go in first (bottom, toward rear axle)
- Light items on top
- This improves vehicle stability and handling

**Access-based rules (camping-specific loading order):**
1. **First in (bottom/back):** Tent, sleeping pads, large bins
2. **Middle layer:** Cooking gear bins, cooler, camp chairs
3. **Last in (top/front, easy access):** Snacks, rain gear, headlamp, first aid
4. **Never bury:** Items needed during drive (water, snacks, phone charger)

**Fragility rules:**
- Fragile items on top, never load-bearing
- Heavy items never stacked on light/fragile items

### 2.2 Recommended Priority Model for TrimBox

```dart
enum PackingPriority {
  first,    // Load first (goes deepest) -- tent, sleeping bags
  normal,   // Standard priority -- bins, cooler
  last,     // Load last (most accessible) -- snacks, rain gear
  top,      // Must be on top layer -- fragile items
}
```

Each TrimBox item gets a `priority` field. The auto-layout algorithm:
1. Groups items by priority
2. Packs `first` items using EP-BFD, placing them at the back (high Z)
3. Packs `normal` items in remaining space
4. Packs `last` items near the trunk opening (low Z)
5. Packs `top` items only on top of existing items (stacking)

### 2.3 Multi-Layout Generation

Generate multiple layout alternatives by varying:
- Sort order within same priority group (by volume, by height, by floor area)
- Rotation choices (prefer width-aligned vs depth-aligned)
- Placement scoring (prefer back-left vs back-right vs centered)

Present 3-5 alternatives to the user, scored by:
- Space utilization percentage
- Access score (are "last" items actually accessible?)
- Stability score (center of gravity, support ratio)

---

## 3. Handling Non-Rectangular Containers

Car trunks are not perfect rectangular boxes. TrimBox already models:
- Ceiling drop (slopes down toward rear)
- Rear top narrowing (C-pillar effect)
- Taper ratio (bottom edges narrow toward rear)
- Wheelhousees (protruding obstacles)

### 3.1 Approach: AABB with Constraint Validation

**Do NOT try to model the trunk as an irregular mesh for packing.** Instead:

1. Use the bounding rectangle (w x d x h) as the primary packing space
2. After placing each item, validate against trunk shape constraints:
   - `ceilingHeightAt(z)`: Is the box top below the ceiling at its Z position?
   - `topNarrowAt(z)`: Is the box within the narrowed walls at its height?
   - `taperAt(z)`: Is the box within the tapered floor edges?
   - Wheelhouse collision: Does the box overlap with wheelhouse AABBs?
3. If validation fails, try the next extreme point or next rotation

This is much simpler than true irregular-container packing and leverages TrimBox's existing `TrunkSpace` shape helpers and `CollisionDetector`.

### 3.2 Pseudo-code for Constraint-Aware Placement

```
function canPlace(box, position, trunkSpace):
    // Basic bounds check
    if position.x + box.w > trunkSpace.w: return false
    if position.y + box.d > trunkSpace.d: return false
    if position.z + box.h > trunkSpace.h: return false

    // Ceiling height check at box's depth position
    maxH = trunkSpace.ceilingHeightAt(position.y)
    if position.z + box.h > maxH: return false

    // Wall narrowing check at box's height
    narrow = trunkSpace.topNarrowAt(position.y)
    effectiveW = trunkSpace.w - 2 * narrow * (position.z / trunkSpace.h)
    xMin = narrow * (position.z / trunkSpace.h)
    if position.x < xMin: return false
    if position.x + box.w > trunkSpace.w - xMin: return false

    // Wheelhouse collision
    if overlapsWheelhouse(box, position, trunkSpace): return false

    // Box-box collision
    if overlapsAnyExistingBox(box, position, placedBoxes): return false

    return true
```

### 3.3 Wheelhouse Avoidance

Wheelhousees are modeled as rectangular protrusions from the side walls. Two strategies:
- **Exclusion zones:** Mark wheelhouse volumes as occupied before packing starts
- **Virtual pre-placed items:** Add invisible "boxes" representing wheelhousees to the placed items list, so the EP algorithm naturally avoids them

The virtual pre-placed items approach is elegant because it requires zero changes to the core packing algorithm.

---

## 4. Visual Packing Tools & UX Patterns

### 4.1 Existing Tools Reviewed

**3DPACK.ING** (https://3dpack.ing/)
- Drag-and-drop with real-time collision prevention
- 6-orientation rotation controls
- Snap-to-grid for precise placement
- Multi-selection for moving groups
- Center of gravity visualization (red sphere)
- Undo/redo for experimentation
- Hybrid: auto-optimize + manual adjustment

**EasyCargo** (https://www.easycargo3d.com/)
- Interactive 3D view with rotate/zoom
- Drag-and-drop with auto-snap alignment
- Full loading plan editor
- Runs in browser (web-based)

**PTV Logistics**
- Interactive 3D visualization API
- Professional logistics focus

### 4.2 UX Best Practices for TrimBox

**Auto-Layout Flow:**
1. User adds all boxes to the scene (can be empty trunk)
2. User taps "Auto Arrange" button
3. Algorithm runs (should be <500ms for typical 5-20 boxes)
4. Boxes animate to their new positions (one by one, ~200ms each)
5. Show utilization score and any unfitted items
6. "Try Another" cycles through alternative layouts
7. User can manually adjust any box after auto-layout

**Visual Feedback During Auto-Layout:**
- Sequential box placement animation (boxes slide/fly into position)
- Progress indicator for the arrangement being tried
- Color coding: green = well-placed, yellow = tight fit, red = could not place
- Ghost outlines showing where the next box will go

**Post-Layout Interaction:**
- Any manual move breaks auto-layout mode
- "Re-optimize" button to re-run with current manual adjustments locked
- "Reset" to clear all positions and start over
- Comparison view: show two layouts side by side (optional, advanced)

### 4.3 Collision & Stacking UX

- Real-time collision prevention (items snap to valid positions)
- Visual stacking indicators (highlight support surface)
- Weight/stability warnings (center of gravity indicator)
- "Lock" individual items to prevent auto-layout from moving them

---

## 5. Flutter/Dart Implementation Considerations

### 5.1 No Existing Dart 3D Bin Packing Library

There are no Dart/Flutter packages for 3D bin packing. The algorithm must be implemented natively in Dart. This is actually preferable because:
- Full control over trunk-specific constraints
- No platform channel overhead
- Can integrate directly with existing TrimBox models

### 5.2 Recommended Dart Implementation Structure

```dart
/// Core packing algorithm
class TrunkPacker {
  final TrunkSpace trunk;
  final List<TrimBox> boxes;
  final PackingStrategy strategy;

  PackingResult pack() {
    final sorted = _sortBoxes(boxes, strategy);
    final extremePoints = <Point3D>[Point3D(0, 0, 0)];
    final placed = <PlacedBox>[];
    final unplaced = <TrimBox>[];

    // Add wheelhousees as virtual placed boxes
    _addWheelhouseBlocks(placed, extremePoints);

    for (final box in sorted) {
      final placement = _findBestPlacement(box, extremePoints, placed);
      if (placement != null) {
        placed.add(placement);
        _updateExtremePoints(extremePoints, placement, placed);
      } else {
        unplaced.add(box);
      }
    }

    return PackingResult(
      placements: placed,
      unplacedItems: unplaced,
      utilization: _calculateUtilization(placed),
    );
  }

  PlacedBox? _findBestPlacement(
    TrimBox box,
    List<Point3D> eps,
    List<PlacedBox> placed,
  ) {
    PlacedBox? best;
    double bestScore = double.infinity;

    // Sort EPs: prefer bottom (low z), then back (high y), then left (low x)
    final sortedEPs = _sortExtremePoints(eps);

    for (final ep in sortedEPs) {
      for (final rotation in [false, true]) {
        final w = rotation ? box.depth : box.width;
        final d = rotation ? box.width : box.depth;
        final h = box.height;

        if (_canPlace(w, d, h, ep, placed)) {
          final score = _placementScore(ep, w, d, h);
          if (score < bestScore) {
            bestScore = score;
            best = PlacedBox(box, ep, rotation, w, d, h);
          }
        }
      }
    }
    return best;
  }

  bool _canPlace(double w, double d, double h, Point3D pos, List<PlacedBox> placed) {
    // Bounds + ceiling + narrowing + taper + wheelhouse + box-box collision
    // Uses existing TrunkSpace shape helpers and CollisionDetector
  }

  void _updateExtremePoints(List<Point3D> eps, PlacedBox placed, List<PlacedBox> all) {
    // Generate 3 new EPs from the placed box corners
    // Project each onto nearest surface (floor, wall, or existing box)
    // Remove EPs that are now inside the placed box
  }

  double _placementScore(Point3D ep, double w, double d, double h) {
    // Lower score = better placement
    // Prefer: bottom (low z) > back (high y) > left (low x)
    return ep.z * 1000 - ep.y * 100 + ep.x * 10;
  }
}
```

### 5.3 Generating Multiple Layouts

```dart
class MultiLayoutGenerator {
  List<PackingResult> generateAlternatives(TrunkSpace trunk, List<TrimBox> boxes) {
    final results = <PackingResult>[];

    final strategies = [
      PackingStrategy.volumeDescending,
      PackingStrategy.floorAreaDescending,
      PackingStrategy.heightDescending,
      PackingStrategy.priorityThenVolume,
    ];

    for (final strategy in strategies) {
      results.add(TrunkPacker(trunk, boxes, strategy).pack());
    }

    // Sort results by utilization, return top N
    results.sort((a, b) => b.utilization.compareTo(a.utilization));
    return results.take(5).toList();
  }
}
```

### 5.4 CustomPainter Performance

For complex scenes with many boxes and auto-layout animation:

**Use RepaintBoundary:**
- Wrap the trunk painter in RepaintBoundary to isolate repaints
- Static elements (trunk shell, grid) rarely change; separate from dynamic elements (boxes)

**Optimize shouldRepaint:**
- Only return true when box positions actually change
- Compare previous and current box lists by reference, not deep equality

**Avoid heavy work in paint():**
- Pre-compute projection matrices outside paint()
- Cache path objects for repeated shapes (trunk outline, grid)
- Use canvas.save()/restore() efficiently

**Animation strategy:**
- For auto-layout animation, use AnimationController with Tween
- Animate one box at a time (sequential) for clarity
- Use canvas.drawShadow() for drop shadows during animation

### 5.5 Flutter GPU (Future)

Flutter 3.24+ introduces Flutter GPU, a low-level graphics API. `flutter_scene` enables real-time 3D rendering with glTF models. This could be a future upgrade path but is not needed for the current 1-point perspective CustomPainter approach.

---

## 6. Realistic Rendering Techniques

### 6.1 Perspective Projection (Already Implemented)

TrimBox uses 1-point perspective: `f = focalLen / (camZ - z) * scale`, projecting 3D points to 2D screen coordinates. This is working well.

### 6.2 Lighting & Shading Enhancements

**Directional light with dot product:**
- Define a light direction vector (e.g., from upper-left-front)
- For each face, compute `intensity = dot(faceNormal, lightDir)`
- Modulate face color by intensity
- Add ambient light component to prevent fully black faces

**Depth-based darkening (already implemented):**
- `depthDarken = (1 - z/d) * 0.35` -- items farther back are darker
- This simulates light falloff inside the trunk

### 6.3 Shadow Techniques for CustomPainter

**Drop shadows on floor:**
```dart
// For each box, draw a shadow path on the floor plane
final shadowPaint = Paint()
  ..color = Colors.black.withOpacity(0.3)
  ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0);
canvas.drawPath(shadowPath, shadowPaint);
```

**Contact shadows (ambient occlusion lines):**
- Already implemented at wall-floor and ceiling-wall junctions
- Extend to box-floor and box-box contact edges
- Draw thin dark lines where surfaces meet

**Canvas.drawShadow():**
- Flutter's built-in shadow for Path objects
- Takes elevation parameter for shadow size/blur
- Good for floating/animating boxes during drag

### 6.4 Material Simulation

**Trunk carpet texture (procedural):**
- Use noise pattern: small random dots or stippling
- Two-pass: base color fill, then scattered micro-dots in slightly different shade
- Alternative: fine crosshatch lines at very low opacity

**Plastic surfaces (boxes, wheelhouses):**
- Subtle gradient on each face (lighter at top edge, darker at bottom)
- Thin highlight line along top edges (specular reflection)
- Slight transparency variation for depth

**Fabric/soft items:**
- Slightly rounded corners (use RRect instead of Rect for projected faces)
- Softer color transitions between faces
- No sharp specular highlights

### 6.5 Depth Sorting

Current approach (sort by front face Z) works well. For more complex scenes:
- Painter's algorithm: draw back-to-front
- For overlapping boxes at same depth, sort by Y then X
- Special case: stacked boxes must draw bottom before top

---

## 7. Recommended Approach for TrimBox

### 7.1 Algorithm Choice: Extreme Point with Best Fit Decreasing (EP-BFD)

**Why EP-BFD:**
- Simple to implement (~200-300 lines of Dart)
- Naturally handles stacking (Z-axis extreme points)
- Easy to add trunk shape constraints as validation
- Fast enough for real-time (<100ms for 20 boxes)
- Well-documented in academic literature

### 7.2 Implementation Phases

**Phase 1: Core Packing (Epic 9.1)**
1. Implement `TrunkPacker` with EP-BFD algorithm
2. Sort items by volume descending
3. 2 rotations only (0 and 90 degrees on floor)
4. Validate against trunk bounds + wheelhousees
5. Return placed positions + unplaced list

**Phase 2: Stacking Optimization (Epic 9.2)**
1. Generate Z-axis extreme points (on top of placed boxes)
2. Validate stacking: 50%+ overlap area, ceiling height check
3. Prefer stacking small items on large items
4. Support ratio validation (4-corner support check)

**Phase 3: Priority & Multi-Layout (Epic 9.3, 9.4)**
1. Add priority field to TrimBox
2. Group-then-pack: pack each priority group sequentially
3. Generate 3-5 alternatives with different sort strategies
4. Score and rank alternatives
5. Show unfitted items with clear messaging

**Phase 4: Animation & UX (Epic 9.3)**
1. Sequential box placement animation (200ms per box)
2. "Try Another" button cycles alternatives
3. Manual adjustment after auto-layout
4. "Re-optimize" with locked items

### 7.3 Trunk Shape Integration

Leverage existing TrunkSpace helpers:
- `ceilingHeightAt(z)` for ceiling constraint
- `topNarrowAt(z)` for wall narrowing constraint
- `taperAt(z)` for floor taper constraint
- Wheelhouse dimensions from vehicle presets

Add wheelhousees as virtual pre-placed items (zero-change to core algorithm).

### 7.4 Performance Budget

| Operation | Target | Notes |
|-----------|--------|-------|
| Pack 5 boxes | <10ms | Typical camping load |
| Pack 20 boxes | <100ms | Heavy camping trip |
| Pack 50 boxes | <500ms | Stress test |
| Animation per box | 200ms | Smooth sequential placement |
| Total auto-layout UX | <3s | Including animation for 10 boxes |

---

## 8. Open Source References

### Algorithm Implementations

| Repository | Language | Algorithm | Notes |
|------------|----------|-----------|-------|
| [jerry800416/3D-bin-packing](https://github.com/jerry800416/3D-bin-packing) | Python | Greedy + gravity | Best reference: stability, gravity, load-bearing, visualization |
| [enzoruiz/3dbinpacking](https://github.com/enzoruiz/3dbinpacking) | Python | Greedy placement | Simpler, good starting point |
| [skjolber/3d-bin-container-packing](https://github.com/skjolber/3d-bin-container-packing) | Java | LAFF + brute force | Production quality, Maven package |
| [davidmchapman/3DContainerPacking](https://github.com/davidmchapman/3DContainerPacking) | C# | EB-AFIT | Layer-building, full rotation |
| [olragon/binpackingjs](https://github.com/olragon/binpackingjs) | JavaScript | 2D/3D/4D | JS port, closest to Dart syntax |
| [alexfrom0815/Online-3D-BPP-DRL](https://github.com/alexfrom0815/Online-3D-BPP-DRL) | Python | Deep RL | Research reference only |

### Key Papers

- Crainic, Perboli, Tadei: "Extreme Point-Based Heuristics for Three-Dimensional Bin Packing" (INFORMS Journal on Computing, 2008)
- Baltacioglu, Moore, Hill: "The Distributor's Three-Dimensional Pallet-Packing Problem" (Int. J. Operational Research, 2006)
- "A Constructive Heuristic Algorithm for 3D Bin Packing of Irregular Shaped Items" (arXiv:2206.15116)

### Visualization & UX References

- [3DPACK.ING Manual Placement](https://3dpack.ing/blog/manual-placement) -- Best UX reference for drag-drop packing
- [EasyCargo](https://www.easycargo3d.com/) -- Browser-based 3D loading planner
- [Optioryx Blog: 3D Bin Packing](https://www.optioryx.com/blog/3d-bin-packing) -- Algorithm overview with business context

### Rendering References

- [Mamboleoo: How to Render 3D in 2D Canvas](https://www.mamboleoo.be/articles/how-to-render-3d-in-2d-canvas) -- Projection math
- [Charles Petzold: Rudimentary 3D on 2D Canvas](https://www.charlespetzold.com/blog/2024/09/Rudimentary-3D-on-the-2D-HTML-Canvas.html) -- Face normals, lighting
- [xem.github.io: 3D Projection](https://xem.github.io/articles/projection.html) -- Projection formulas
- [ScratchAPixel: Perspective Projection](https://www.scratchapixel.com/lessons/3d-basic-rendering/perspective-and-orthographic-projection-matrix/projection-matrices-what-you-need-to-know-first.html) -- Matrix math

### Flutter References

- [Flutter GPU Blog Post](https://blog.flutter.dev/getting-started-with-flutter-gpu-f33d497b7c11) -- Future 3D rendering path
- [Flutter 3D Rendering Sample](https://github.com/hamed-rezaee/flutter_3d_rendering) -- CustomPainter 3D example
- [RepaintBoundary Optimization](https://ms3byoussef.medium.com/optimizing-flutter-ui-with-repaintboundary-2402052224c7) -- Performance guide
- [Flutter Canvas drawShadow](https://api.flutter.dev/flutter/dart-ui/Canvas/drawShadow.html) -- Shadow API
- [Flutter CustomPainter API](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html) -- Official docs
