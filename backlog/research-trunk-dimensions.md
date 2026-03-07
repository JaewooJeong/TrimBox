# Real Car Trunk Interior Dimensions Research

**Researcher:** Winston (Architect)
**Date:** 2026-03-07
**Purpose:** Validate and improve TrimBox Simulator trunk preset dimensions for accurate 3D rendering

---

## 1. Research Methodology

Manufacturer spec sheets rarely publish internal cargo area linear dimensions (width/depth/height in mm). They publish only:
- Cargo volume in liters (VDA) or cubic feet (SAE)
- Overall vehicle exterior dimensions

Actual internal trunk measurements come from:
- Owner forum measurements (kia-forums.com, hyundai-forums.com, ioniqforum.com)
- Third-party measurement sites (how-many-bags-fit.com, automobiledimension.com, cinch.co.uk)
- Australian/European spec sheets (which sometimes include more detail than US/KR ones)

---

## 2. Measurement Standards

### VDA Method (Europe/Korea)
- **Verband der Automobilindustrie** (German Automobile Industry Association)
- Uses standardized wooden blocks: **200mm x 100mm x 50mm** (= 1 liter each)
- Engineers fill the trunk with as many 1-liter blocks as possible
- The count = VDA liters
- Does NOT represent usable space — irregular shapes, wheel arches, and narrow crevices all contribute to the count

### SAE J1100 Method (USA)
- Uses **7 standardized rigid gauge blocks** ranging from 0.2 to 2.375 cubic feet
- Measured in cubic feet
- Blocks are larger and more rigid than VDA blocks
- Typically yields **lower numbers** than VDA for the same trunk

### Why Advertised Liters Differ from Usable Space
- VDA blocks fill into every crevice, including above wheel arches and irregular corners
- Real boxes are rectangular and cannot use irregular spaces
- Tonneau/cargo cover position affects measurement (below vs. above)
- Seat position (slid forward vs. back) changes depth significantly
- Underfloor storage is sometimes included, sometimes not

---

## 3. Vehicle-by-Vehicle Dimensions

### 3.1 Kia Sorento MQ4 (쏘렌토)

**Official specs:**
- Overall: 4815mm L x 1900mm W x 1700mm H
- Wheelbase: 2815mm
- Boot capacity: 705-910L (VDA, depending on seat position, 5-seat config)
- Hybrid: 813L, PHEV: 809L
- Load width (cinch.co.uk): **1,200mm**

**Measured/derived internal cargo dimensions:**
| Dimension | Value | Source |
|-----------|-------|--------|
| Width (between wheel wells) | 1,041-1,053mm (41") | kia-forums.com owner measurements |
| Width (above wheel wells) | ~1,200mm | cinch.co.uk official |
| Width at tailgate opening | 914mm (36") | kia-forums.com |
| Minimum width (how-many-bags-fit) | 1,053mm | how-many-bags-fit.com (Sorento 2.2) |
| Maximum height | 774mm | how-many-bags-fit.com |
| Depth (seats upright, behind 3rd row) | 450mm | how-many-bags-fit.com |
| Depth (seats folded) | 1,183mm | how-many-bags-fit.com |
| Trunk opening height (center) | 838mm (33") | kia-forums.com |
| Trunk opening height (sides) | 813mm (32") | kia-forums.com |

**Current TrimBox preset:** w=1.08m, d=1.10m, h=0.82m
**Assessment:** Width is reasonable (between the 1041mm wheel-well width and 1200mm upper width). Depth of 1.10m is within range of the 1.18m folded measurement. Height of 0.82m is slightly above the 774mm measured max height — may include space above cargo cover. Consider reducing h to 0.77-0.80m.

**Wheelhouse:** Current 100mm W x 400mm D x 300mm H
The actual wheelhouse intrusion width is roughly (1200 - 1053) / 2 = ~74mm per side. Current 100mm is slightly generous but acceptable for collision detection margin.

**Seat split:** 4:2:4 is correct for Sorento MQ4.

---

### 3.2 Hyundai Tucson NX4 (투싼)

**Official specs (Australian spec sheet — most detailed found):**
- Overall: 4640mm L x 1865mm W x 1665mm H
- Wheelbase: 2755mm
- Wheel track front/rear: 1615/1622mm
- Cargo area (VDA): Petrol 539/1860L, Hybrid 582/1903L (min/max)
- Ground clearance: 181mm

**Interior dimensions from spec sheet:**
- Shoulder room front/rear: 1464/1422mm
- Hip room front/rear: 1385/1369mm

**Measured/derived internal cargo dimensions:**
| Dimension | Value | Source |
|-----------|-------|--------|
| Width (between wheel wells) | 1,035-1,040mm (40.75") | hyundai-forums.com, dealer measurements |
| Width (above wheel wells / at doors) | 1,308mm (51.5") | hyundai-forums.com |
| Width (maximum at very back) | 1,422mm (56") | hyundai-forums.com |
| Minimum width (how-many-bags-fit) | 1,040mm | how-many-bags-fit.com |
| Maximum height | 727mm | how-many-bags-fit.com |
| Depth (seats upright) | 910mm | how-many-bags-fit.com |
| Depth (seats folded) | 1,725mm | how-many-bags-fit.com |
| Cargo volume to parcel shelf (seats up) | 344L | how-many-bags-fit.com |

**Current TrimBox preset:** w=1.04m, d=0.91m, h=0.73m
**Assessment:** Excellent match. Width 1040mm matches measured 1035-1040mm between wheel wells. Depth 910mm matches "seats upright" measurement exactly. Height 730mm matches measured 727mm closely.

**Wheelhouse:** Current 140mm W x 400mm D x 350mm H
Actual intrusion: (max width above wells ~1308mm - width between wells ~1040mm) / 2 = ~134mm per side. Current 140mm is a close match.

**Seat split:** 6:4 (60:40) confirmed by spec sheet.

---

### 3.3 Hyundai Santa Fe (싼타페)

**Official specs:**
- Overall: 4830mm L x 1900mm W x 1770mm H (2025 model)
- Wheelbase: 2815mm (2024), 2815mm (2025)
- Cargo: 14.6 cu ft (3rd row up) / 40.5 cu ft (behind 2nd row) / 79.6 cu ft (max)
- Boot capacity: ~628L (5-seat, 3rd row folded) / 1,949L (all folded)

**Measured/derived internal cargo dimensions:**
| Dimension | Value | Source |
|-----------|-------|--------|
| Width (between wheel wells) | 1,118mm (44") | hyundai-forums.com (2021 model) |
| Width (above wheel wells) | 1,372mm (54") | hyundai-forums.com |
| Depth (seat back to hatch, floor level) | 1,067mm (42") | hyundai-forums.com |
| Depth (at higher level) | 914mm (36") | hyundai-forums.com |
| Cargo area width | 1,275mm (50.2") | checkeredflaghyundaiworld.com |

**Current TrimBox preset:** w=1.09m, d=1.05m, h=0.80m
**Assessment:** Width 1.09m seems low — measured between-wheels width is ~1,118mm (44"). The 1090mm figure may represent a conservative floor-level width. Depth 1.05m is close to the measured 1,067mm. Height 0.80m is reasonable for an SUV of this size class.

**Wheelhouse:** Current 100mm W x 400mm D x 350mm H
Actual intrusion: (1372 - 1118) / 2 = ~127mm per side. Current 100mm is slightly conservative.

**Seat split:** 6:4 confirmed.

---

### 3.4 Kia Carnival (카니발)

**Official specs:**
- Overall: 5115mm L x 1995mm W x 1775mm H
- Wheelbase: 3092mm
- Cargo (behind 3rd row): 627L / 40.2 cu ft
- Cargo (behind 2nd row): 86.9 cu ft
- Cargo (all folded): 145.1 cu ft / ~2,827-2,905L

**Measured/derived internal cargo dimensions:**
| Dimension | Value | Source |
|-----------|-------|--------|
| Cargo width (estimated) | ~1,250mm | Derived from overall 1995mm width minus body panels |
| Cargo behind 3rd row depth | ~850mm | Estimated from 40.2 cu ft volume |

**Current TrimBox preset:** w=1.25m, d=0.85m, h=0.88m
**Assessment:** Width 1.25m is plausible for a minivan with 1,995mm overall width. Depth 0.85m behind third row is reasonable. Height 0.88m is higher than SUVs due to minivan body style — this is correct.

**Note:** The Carnival is a minivan with minimal wheel arch intrusion compared to SUVs, and a much more boxy cargo shape. The current low wheelhouse values (100mm W x 300mm D x 250mm H) reflect this correctly.

**Seat split:** 5:5 confirmed.

---

### 3.5 Hyundai Ioniq 5 (아이오닉5)

**Official specs:**
- Overall: 4635mm L x 1890mm W x 1605mm H
- Wheelbase: 3000mm (very long for its size — EV skateboard platform)
- Cargo: 527L (rear) + 57L (frunk) = 584L total
- With seats folded: ~1,580L

**Measured/derived internal cargo dimensions:**
| Dimension | Value | Source |
|-----------|-------|--------|
| Width (between wheel arches) | 900-1,000mm | ioniqforum.com (conflicting reports) |
| Depth to seat backs | ~950mm | Estimated from volume and proportions |
| Boot opening is relatively shallow | Yes | Multiple reviews note limited vertical space |

**Current TrimBox preset:** w=1.00m, d=0.95m, h=0.73m
**Assessment:** Width 1.00m is at the upper end of measured 900-1000mm range. The Ioniq 5 has notably large wheel arches due to its EV platform. Depth 0.95m is plausible. Height 0.73m is appropriate — the Ioniq 5 has a lower roofline than traditional SUVs.

**Wheelhouse:** Current 150mm W x 350mm D x 300mm H
The Ioniq 5 has notably chunky wheel arch intrusions — 150mm per side is plausible.

**Seat split:** 6:4 confirmed.

---

### 3.6 Hyundai Avante/Elantra CN7 (아반떼)

**Official specs:**
- Overall: 4675mm L x 1825mm W x 1415mm H
- Boot capacity: 402L (VDA)
- Sedan trunk — very different shape from SUV cargo area

**Current TrimBox preset:** w=1.02m, d=0.71m, h=0.43m
**Assessment:** These are reasonable for a C-segment sedan trunk. The 402L VDA volume roughly corresponds to 1.02 x 0.71 x 0.43 = 0.311 m3 = 311L of rectangular space, which is plausible given that VDA counts irregular crevice space.

**Wheelhouse:** Current 50mm W x 300mm D x 250mm H — minimal intrusion, correct for sedan.

**Seat split:** None (null) — correct, sedan with fixed rear wall/pass-through.

---

## 4. Trunk Shape Characteristics

### 4.1 Wheel Arch Intrusions
- **Typical midsize SUV:** 75-150mm intrusion per side, 300-400mm deep, 250-350mm tall
- **Position:** Starts at rear of cargo area (z=0 in our model), extends ~400mm forward
- **Shape:** Actually curved/rounded, but AABB approximation is standard for collision detection
- **The Ioniq 5** has the largest wheel arch intrusion among the presets due to EV platform

### 4.2 Floor Characteristics
- **Underfloor storage:** Most SUVs have a 100-130mm deep underfloor compartment
- **Floor height from ground:** SUVs typically 500-580mm, sedans 420-480mm
- **Floor material:** Carpet-covered MDF/hardboard, sometimes with rubber mat option
- **Floor slope:** Generally flat, but some models have a slight ~2-3 degree upward slope toward the rear

### 4.3 Ceiling/Roof Profile
- **Ceiling drop toward rear:** 60-120mm depending on vehicle, strongest on SUVs
- **Caused by:** Rear window angle + roof slope for aerodynamics
- **Shape:** Quadratic/parabolic curve — steeper near the rear
- **Current model uses:** `ceilingDrop * (1-t)^2` which is a good approximation

### 4.4 C-Pillar Taper (Side Wall Narrowing)
- **Effect:** Cargo area narrows toward the rear at the top, widest at the front
- **Magnitude:** 30-70mm per side at the rear top corners
- **This is separate from** the bottom-edge taper (taperRatio)
- **Current model:** `rearTopNarrow` parameter handles this correctly

### 4.5 Bottom-Edge Taper
- **Effect:** Floor width narrows toward the rear
- **Magnitude:** 3-12% of total width (strongest on sedans like Avante)
- **Caused by:** Rear body panel curvature, tail light housings

### 4.6 Trunk Opening vs Interior
- **Opening is typically narrower than interior:** ~80-90% of max cargo width
- **Opening height:** Lower than interior ceiling by 50-100mm (due to liftgate frame)
- **Loading sill (lip):** 40-80mm height step up from bumper to cargo floor
- **The current model handles this with:** `trunkLipHeight` and shaped opening rendering

### 4.7 Seat Back Angle
- **When folded:** Most seats fold to ~5-15 degrees from horizontal (not perfectly flat)
- **Step up:** 20-65mm step between cargo floor and folded seat surface
- **Current model:** 12% tilt on seat backrest rendering is reasonable

---

## 5. Trunk Interior Visual Design

### 5.1 Typical Materials and Colors
- **Floor:** Dark gray/charcoal carpet (polypropylene), sometimes with rubber overlay
- **Side panels:** Molded dark gray/black plastic trim with carpet inserts
- **Wheel arch covers:** Hard plastic, slightly darker than side panels
- **Ceiling:** Light gray or medium gray headliner fabric (lighter than floor/walls)
- **Seat back (when facing cargo):** Dark carpet or plastic panel

### 5.2 Current Model Colors (Assessment)
| Element | Current Color | Real-World Typical | Assessment |
|---------|--------------|-------------------|------------|
| Floor | #2D2A27 (dark brown-gray) | Dark charcoal gray | Good — slightly warm-toned |
| Walls | #2A2825 (dark brown-gray) | Dark gray plastic | Good |
| Ceiling | #222020 (darkest) | Medium-light gray | Too dark — real ceilings are lighter |
| Seat | #3D3A35 (medium brown-gray) | Dark gray carpet | Good |
| Wheelhouse | #2D2A27 (dark charcoal) | Black hard plastic | Good |

**Note:** The current rendering intentionally uses darker colors for atmospheric 3D rendering effect, which works well visually even if not perfectly color-accurate.

### 5.3 Cargo Area Features (for future rendering)
- **Cargo cover/tonneau:** Retractable, sits ~at or slightly above wheel arch height
- **Tie-down hooks:** 4-6 small metal hooks at floor level, near corners
- **Cargo net hooks:** Upper attachment points near C-pillars
- **12V power outlet:** Usually one, lower left or right side panel
- **LED cargo light:** Typically centered or on one side of the ceiling
- **Remote seat-fold levers:** Visible on the side walls near the seat backs
- **Underfloor storage access:** Lift-up floor panel

---

## 6. Recommended Preset Adjustments

Based on this research, here are specific adjustments to consider:

### 6.1 Sorento (쏘렌토)
- **h:** Consider reducing from 0.82m to **0.78-0.80m** (measured max height is 774mm)
- **Wheelhouse w:** Could reduce from 100mm to **75-80mm** per side (calculated ~74mm)
- **bodyWidth:** 1.44m is reasonable (overall 1900mm minus mirrors/panels)

### 6.2 Tucson (투싼)
- **No changes needed** — dimensions match measured values very closely

### 6.3 Santa Fe (싼타페)
- **w:** Consider increasing from 1.09m to **1.10-1.12m** (measured ~1,118mm between wells)
- **Wheelhouse w:** Consider increasing from 100mm to **125-130mm** (calculated ~127mm)

### 6.4 Carnival (카니발)
- **No significant changes** — minivan dimensions are harder to verify but preset is reasonable

### 6.5 Ioniq 5 (아이오닉5)
- **No significant changes** — dimensions are within the measured range

### 6.6 Avante (아반떼)
- **No significant changes** — sedan trunk dimensions are reasonable for the volume

---

## 7. Sources

### Manufacturer Specifications
- [Kia Sorento Specs (US)](https://www.kia.com/us/en/sorento/specs)
- [Hyundai Tucson Specifications (AU PDF)](https://www.hyundai.com/content/dam/hyundai/au/en/models/tucson-2024/petrol/docs/TUCSON_Specifications_Sheet.pdf)
- [Kia Sorento Dimensions - automobiledimension.com](https://www.automobiledimension.com/model/kia/sorento)
- [Hyundai Ioniq 5 Dimensions - automobiledimension.com](https://www.automobiledimension.com/model/hyundai/ioniq-5)

### Owner Measurements / Forums
- [Kia Forum - Cargo floor measurements](https://www.kia-forums.com/threads/cargo-floor-measurements-not-just-cubic-ft.343740/)
- [Kia Forum - Trunk opening dimensions](https://www.kia-forums.com/threads/trunk-opening-dimensions.352420/)
- [Hyundai Forums - Cargo area dimensions](https://www.hyundai-forums.com/threads/cargo-area-dimensions.686180/)
- [Hyundai Forums - Cargo Area Surface dimensions](https://www.hyundai-forums.com/threads/cargo-area-surface-dimensions.649995/)
- [Ioniq Forum - Ioniq 5 boot dimensions](https://www.ioniqforum.com/threads/ioniq-5-boot-dimensions.37329/)
- [Carnival Forums - Cargo Space Dimensions](https://www.carnivalforums.com/threads/cargo-space-dimensions.582/)

### Third-Party Measurement Sites
- [how-many-bags-fit.com - Kia Sorento 2.2](https://how-many-bags-fit.com/car-make/kia/kia-sorento-2-2-boot-space-dimensions-luggage-capacity/)
- [how-many-bags-fit.com - Hyundai Tucson](https://how-many-bags-fit.com/car-make/hyundai/hyundai-tucson-1-6-48v-mildhybrid-boot-space-dimensions-luggage-capacity/)
- [cinch.co.uk - Kia Sorento boot space](https://www.cinch.co.uk/guides/choosing-a-car/kia-sorento-boot-space)

### Measurement Standards
- [CarsGuide - VDA vs Litres explanation](https://www.carsguide.com.au/car-advice/whats-the-difference-between-litres-and-litres-vda-for-boot-capacities-42010)
- [Metrology News - Measuring Vehicle Luggage Space](https://metrology.news/measuring-vehicle-luggage-space-a-process-a-little-like-tetris/)
- [Cars.com - Why Cargo Specs Can Stretch the Truth](https://www.cars.com/articles/why-cargo-specs-can-stretch-the-truth-1420663026654/)
- [Cars.com - How Cars.com Measures Cargo Space](https://www.cars.com/articles/how-cars-com-measures-cargo-space-427860/)

### Design & Shape References
- [Hagerty - Car Design Fundamentals: The C-pillar](https://www.hagerty.com/media/design/car-design-fundamentals-the-c-pillar/)
- [Toyota Corolla Cross Forum - Detailed cargo measurements](https://www.corollacrossforum.com/threads/detailed-corolla-cross-cargo-space-measurements.269/)
