# TrimBox Competitive Research Report
**Date: 2026-03-07**
**Analyst: Mary, Business Analyst**

---

## Executive Summary

After thorough research across English and Korean sources, the trunk/cargo packing simulator space reveals a clear gap: **there is no dedicated, consumer-facing car trunk packing simulator with realistic 3D visualization and vehicle-specific trunk shapes.** The market is dominated by (1) logistics/freight load planners targeting B2B users, and (2) simple volume calculators. TrimBox occupies a unique niche combining consumer-friendly UI, realistic 1-point perspective rendering, and Korean vehicle presets.

---

## 1. Direct Competitors (Car Trunk / Personal Vehicle Focus)

### 1.1 VolumTransport (Boxes in the Vehicle)
- **Platform:** Android only (Google Play)
- **Developer:** AplicacionesHerrbri (Spain)
- **Key Features:**
  - 3D bin packing simulation for cars, vans, trucks
  - AR measurement via phone camera (no tape measure needed)
  - Rotate and review 3D placement
  - Universal space mode for custom dimensions
  - Supports folded rear seat configurations
  - Load balancing across multiple trips
- **Visual Approach:** 3D visualization with rotation capability
- **Trunk Shape Modeling:** User enters rectangular dimensions (W x D x H); no vehicle-specific shapes or wheelhhouse modeling
- **Pricing:** Paid app (price varies by region on Google Play)
- **Target Users:** Freelancers, delivery couriers, small moving jobs
- **Strengths:**
  - AR measurement is a standout feature
  - Practical for everyday use (moving, deliveries)
  - 3D visualization with bin packing algorithm
- **Weaknesses:**
  - Android only, no iOS
  - No vehicle-specific trunk shapes (all rectangular)
  - No wheelhouse or C-pillar modeling
  - Logistics-focused, not consumer/camping oriented
  - No preloaded vehicle database

### 1.2 How-Many-Bags-Fit.com
- **Platform:** Web (browser-based)
- **Developer:** Strato-g Creative Ltd (UK)
- **Key Features:**
  - Boot space calculator for 1000+ car models
  - Supports suitcases, cabin bags, and travel bags
  - Vehicle comparison tool (boot dimensions side-by-side)
  - Reverse search: find vehicles that fit your luggage
  - NEW "3D AI Boot Space Packing Assistant" (in development)
  - Non-standard items: pushchairs, bikes, sports equipment
- **Visual Approach:** Primarily 2D calculator; 3D AI assistant is new/experimental
- **Trunk Shape Modeling:** Uses manufacturer-reported boot dimensions (L x W x H); simplified rectangular volume
- **Pricing:**
  - Free basic access
  - 24-hour pass: GBP 1.99
  - 7-day pass: GBP 3.99
  - 14-day pass: GBP 5.99
  - All passes include 12 months of membership benefits
- **Strengths:**
  - Largest vehicle database (1000+ models)
  - Practical for car buyers and trip planners
  - Low price point
  - Vehicle comparison feature is unique
- **Weaknesses:**
  - Not a true 3D simulator (primarily a calculator)
  - No drag-and-drop interaction
  - No trunk shape visualization
  - 3D AI feature is nascent/unproven
  - Limited luggage types in basic calculator (3 types)

### 1.3 Car Boot Carnage
- **Platform:** Web (browser-based, JavaScript required)
- **Developer:** Code Computerlove for JCT600 (UK motor retailer)
- **URL:** carbootcarnage.com
- **Key Features:**
  - Tetris-inspired packing game
  - Timed challenges with different scenarios (beach, camping, moving to uni, visiting in-laws)
  - Different item sets per scenario
  - Free to play, no download
- **Visual Approach:** 2D top-down Tetris-style grid
- **Trunk Shape Modeling:** Simple 2D grid (no 3D, no realistic trunk shape)
- **Pricing:** Free (marketing game for JCT600 dealership)
- **Strengths:**
  - Fun and engaging gamification
  - Scenario-based packing (different trips = different items)
  - Zero friction (web, free, no signup)
- **Weaknesses:**
  - Entertainment only, not a practical tool
  - 2D only, no realistic visualization
  - No actual vehicle dimensions
  - No save/load or practical planning features
  - Marketing vehicle, not a product

---

## 2. Logistics / Freight Load Planning Software (B2B)

These tools target professional logistics but represent the technical state of the art in 3D packing visualization.

### 2.1 EasyCargo
- **Platform:** Web-based
- **Key Features:**
  - Interactive 3D visualization (rotate, zoom, view from inside container)
  - Weight distribution / axle pressure calculation
  - Multi-stop route grouping
  - Excel/API import
  - Print reports from any viewpoint
  - Available in 14 languages
- **Visual Approach:** Full 3D with game-like interactive viewer
- **Container Modeling:** Trucks, containers, semi-trailers; customizable dimensions; 2/3 axle support
- **Pricing:** From $67/user/month; $499 annual; 10-day free trial
- **Ratings:** Highly rated on Capterra, GetApp, SourceForge for ease of use
- **Strengths:** Best-in-class 3D viewer; strong report generation; multi-language
- **Weaknesses:** Expensive for consumers; no car trunk presets; purely B2B logistics

### 2.2 3DPACK.ING
- **Platform:** Web-based
- **Key Features:**
  - AI-powered optimization (natural language input)
  - Center of gravity visualization (red sphere)
  - AI photo-based moving estimator (photograph belongings, get packing plan)
  - "Compact Mode" algorithm for maximum space efficiency
  - Excel import and API integration
- **Visual Approach:** 3D with AI optimization
- **Pricing:** 14-day free trial; pricing not publicly listed (contact sales)
- **Strengths:** AI photo recognition is innovative; natural language API; modern UX
- **Weaknesses:** Enterprise pricing; no consumer car trunk focus

### 2.3 3DBinPacking.com
- **Platform:** Web-based
- **Key Features:**
  - Pack a Shipment (optimize by count, space, or cost)
  - Stack Pallets tool
  - Try Out Box Sizes tool
  - Check Max Load tool
  - All tools in every plan
- **Visual Approach:** 3D visualization
- **Pricing:**
  - Extra Small: $39/mo (1,000 calculations)
  - Small: $119/mo (5,000 calculations)
  - Medium: $289/mo (20,000 calculations)
  - Large: $579/mo (100,000 calculations)
  - 14-day free trial, no credit card required
- **Strengths:** Granular pricing; claims 15-25% freight savings
- **Weaknesses:** Logistics focus; overkill for personal use

### 2.4 PackApp
- **Platform:** Web-based
- **Key Features:**
  - Preset and custom truck types
  - Center of gravity calculation
  - Automatic smallest-container recommendation
  - Step-by-step loading/unloading plans
  - Email sharing of load plans
- **Visual Approach:** 3D ground plan + 3D view
- **Pricing:** $593 (pay-per-calculation or monthly package)
- **Strengths:** Practical step-by-step instructions; cost optimization
- **Weaknesses:** Expensive; demo limited to 25 items and 2 containers

### 2.5 CargoLab
- **Platform:** Web-based
- **Key Features:**
  - Free 3D cargo load planner
  - Standard container optimization
  - No installation required
- **Visual Approach:** 3D
- **Pricing:** Freemium (free for standard containers)
- **Strengths:** Free tier available; no signup needed
- **Weaknesses:** Limited documentation; standard containers only; no car trunk support

### 2.6 Packer3D
- **Platform:** Desktop software
- **Key Features:**
  - Parallelepiped-based volume optimization
  - Axle pressure constraints
  - Cargo fragility and orientation rules
- **Visual Approach:** 3D
- **Pricing:** Not publicly listed
- **Strengths:** Advanced constraint modeling (fragility, orientation)
- **Weaknesses:** Desktop only; logistics-only

### 2.7 DeepPack (by InstaDeep)
- **Platform:** Web-based / API
- **Key Features:**
  - AI-powered load planning (deep learning)
  - 3D dynamic view with step-by-step loading instructions
  - Stackability, weight limits, priority rules
  - API integration for WMS/TMS/ERP
- **Visual Approach:** 3D dynamic visualization
- **Pricing:** Early access was free; discounted tiers for early adopters; enterprise pricing
- **Strengths:** State-of-the-art AI; 10% average space improvement over manual; fast convergence
- **Weaknesses:** Enterprise-only; no consumer application

### 2.8 Cargo-Planner
- **Platform:** Web-based
- **Key Features:**
  - Container, pallet, and truck calculator
  - Multiple SKU import with different dimensions/weights
  - 3D interactive visualization
  - PDF export for loaders
- **Visual Approach:** 3D interactive
- **Pricing:** Subscription-based (not publicly detailed)
- **Strengths:** Good PDF/report output for warehouse teams
- **Weaknesses:** B2B only

### 2.9 WeTransport Wetris (3D Truck Cargo Space Visualizer)
- **Platform:** Web-based
- **Key Features:**
  - Set truck dimensions (L x W x H)
  - "Arrange with AI" button for auto-organization
  - 3D visualization of cargo placement
- **Visual Approach:** 3D (browser-based)
- **Pricing:** Appears free
- **Strengths:** Simple and accessible; AI arrangement feature
- **Weaknesses:** Trucks only; minimal features

---

## 3. Korean Market Tools

### 3.1 LogiShop (로지숍) Loading Simulator
- **Platform:** Web-based (logishop.co.kr)
- **Key Features:**
  - Enter product dimensions and loading space height
  - Auto-stacking calculation (single layer if height not specified)
  - Optimal vehicle recommendation
- **Visual Approach:** 2D/simple visualization
- **Pricing:** Not publicly listed
- **Target:** Korean logistics companies
- **Strengths:** Korean-language; vehicle recommendation
- **Weaknesses:** No 3D; logistics-focused; no car trunk support

### 3.2 SHIPDAGO (쉽다고) Pallet Loading Simulator
- **Platform:** Web-based (shipdago.com)
- **Key Features:**
  - AI-based 3D container loading simulator
  - CBM calculator
  - Pallet calculator
- **Visual Approach:** 3D
- **Pricing:** Free tools available
- **Target:** Korean logistics/shipping
- **Strengths:** Korean-language; free
- **Weaknesses:** Container/pallet focus only; no personal vehicle support

### 3.3 CJ Logistics LoIS O'Pack
- **Platform:** Internal system (CJ Daehantongwoon)
- **Key Features:**
  - 3D simulation-based box recommendation
  - 0.04-second box size optimization
  - AI-powered packing algorithm
- **Visual Approach:** 3D simulation
- **Pricing:** Internal/enterprise only
- **Strengths:** Fastest optimization in Korean market
- **Weaknesses:** Not available to public; enterprise internal tool

### 3.4 Cello Square Loading Optimizer
- **Platform:** Web-based (Samsung SDS)
- **Key Features:**
  - IT-based loading optimization service
  - Container and truck loading plans
- **Visual Approach:** 3D
- **Pricing:** Enterprise pricing
- **Target:** Samsung SDS enterprise customers
- **Strengths:** Samsung-backed enterprise solution
- **Weaknesses:** Not consumer-accessible

### 3.5 LoadLogix (SSAFY Project)
- **Platform:** Web-based (open source on GitHub)
- **Key Features:**
  - Smart logistics loading service
  - 3D bin packing algorithm (address, size, weight)
  - Three.js-based 3D visualization
  - Ray tracing for item selection
  - Playback controls (play, pause, speed, rewind)
  - Loading height and transparency adjustment
- **Visual Approach:** 3D (Three.js)
- **Pricing:** Open source (SSAFY student project, award-winning)
- **Strengths:** Open source; advanced 3D features; Korean-developed
- **Weaknesses:** Delivery truck focus; not maintained as product; academic project

### 3.6 Box Shipping Simulator (박스 적재 시뮬레이터)
- **Platform:** Android (Google Play)
- **Key Features:**
  - Box loading for trucks and warehouses
- **Visual Approach:** Basic simulation
- **Pricing:** Free/low-cost
- **Strengths:** Simple and accessible
- **Weaknesses:** Very basic; truck/warehouse only; limited features

---

## 4. Car Manufacturer Configurator Trunk Features

### 4.1 Hyundai "Build Your Own"
- **Platform:** Web (hyundaiusa.com/build)
- **Trunk Visualization:** Static photos of trunk area; no 3D cargo simulation; shows trunk volume in specs
- **Gap:** No interactive packing tool; no luggage placement simulation

### 4.2 Hyundai India 360 WebGL Configurator
- **Platform:** Web (WebGL-based)
- **Trunk Visualization:** 360-degree interior/exterior view; can look at trunk area but cannot place items
- **Gap:** View-only; no packing simulation

### 4.3 Kia 3D Accessory Configurator
- **Platform:** Web (3dacc.kia.com)
- **Trunk Visualization:** Shows accessories in 3D; no cargo/luggage packing simulation
- **Gap:** Accessories only, not cargo planning

### 4.4 Volvo Developer 3D Assets
- **Platform:** Developer portal (Unity-based)
- **Trunk Visualization:** Full 3D vehicle models (XC40 Recharge) with doors, lights; used for VR/simulation
- **Gap:** Developer tool, not consumer-facing; no packing simulation

### 4.5 General Car Configurators (BMW, Audi, Mercedes, Tesla)
- **Trunk Visualization:** All major OEMs show static trunk photos or 360 views; none offer interactive cargo packing simulation
- **Gap:** Universal gap - NO major car manufacturer offers a trunk packing simulator

---

## 5. Open Source 3D Bin Packing Projects (GitHub)

| Project | Language | Visualization | Stars | Notes |
|---------|----------|---------------|-------|-------|
| skjolber/3d-bin-container-packing | Java | Three.js web viewer | High | LAFF algorithm + brute force |
| jerry800416/3D-bin-packing | Python | Matplotlib/Plotly | Medium | Color-coded 3D boxes |
| enzoruiz/3dbinpacking (py3dbp) | Python | Basic | Popular | Most-forked Python lib |
| davidmchapman/3DContainerPacking | C# | WebGL viewer | Medium | Camera icon to view solutions |
| lotuc/bin-pack | Clojure | Web (lotuc.org/bin-pack) | Low | Live interactive demo |
| Bruno-Ghiberto/3D_BIN_PACKING | Python | Plotly | Low | 6-axis rotation, CLI |
| dwave-examples/3d-bin-packing | Python | Basic | Medium | Quantum computing approach |
| JamesBremner/Pack | C++ | Basic | Low | 2D and 3D |

**Key Observation:** All open source projects focus on algorithmic optimization (minimizing bins or maximizing packing density). None model realistic vehicle trunk shapes with wheelhhouses, seat profiles, or ceiling curvature.

---

## 6. Camping-Specific Tools

**Finding: No dedicated camping trunk packing apps exist.** The search in both English and Korean returned only:
- Physical trunk organizer products (folding boxes, storage bins)
- General packing list apps (PackPoint, Packr, Easy Pack) that list what to bring but do NOT visualize spatial packing
- Blog posts with packing tips
- Korean trunk organizer shops (Caromi/카로미 - custom-fit physical organizers by vehicle model)

This represents a significant market opportunity for TrimBox, especially with camping preset items.

---

## 7. Competitive Landscape Matrix

| Feature | TrimBox | VolumTransport | How-Many-Bags-Fit | EasyCargo | 3DPACK.ING | Car Boot Carnage |
|---------|---------|---------------|-------------------|-----------|------------|-----------------|
| **Target** | Consumer | Sm. Business | Consumer | Enterprise | Enterprise | Entertainment |
| **Platform** | Web (Flutter) | Android | Web | Web | Web | Web |
| **Visual** | 1-pt Perspective | 3D rotate | 2D calculator | 3D interactive | 3D + AI | 2D Tetris |
| **Trunk Shape** | Realistic (ceiling, walls, wheelhouse) | Rectangular | Rectangular | Rectangular | Rectangular | Grid |
| **Vehicle Presets** | 6 Korean SUVs + custom | None (manual) | 1000+ (dimensions only) | Trucks/containers | Trucks/containers | None |
| **Drag & Drop** | Yes | No (auto-place) | No | Yes | Yes | Tetris-style |
| **Collision Detection** | Yes | Algorithm | No | Yes | Yes | Grid-based |
| **Stacking** | Yes | Yes | No | Yes | Yes | No |
| **AR** | No | Yes | No | No | Yes (photo) | No |
| **Save/Load** | Yes (JSON) | No | No | Yes | Yes | No |
| **Price** | Free | Paid | GBP 2-6 | $67/mo | Enterprise | Free |
| **Korean UI** | Yes | No | No | No | No | No |
| **Camping Focus** | Presets | No | No | No | No | Scenario only |

---

## 8. Key Findings and Strategic Implications

### TrimBox's Unique Advantages
1. **Only tool with realistic trunk shape modeling** - ceiling drop, C-pillar narrowing, wheelhouse protrusions, seat backrest with headrests, shaped opening, bumper lip. No competitor models any of these.
2. **Only consumer-focused car trunk packing simulator** - all 3D competitors target logistics/freight.
3. **Only tool with Korean vehicle presets** - no competitor has Sorento, Tucson, Santa Fe, Carnival, Ioniq 5, Avante data.
4. **Only tool with Korean-language UI for this category** - Korean logistics tools exist but none for personal car trunk packing.
5. **Free and web-based** - most capable competitors cost $39-$593+/month.

### Market Gaps TrimBox Could Exploit
1. **Camping packing mode** - zero competitors in this space; camping is huge in Korea
2. **Vehicle purchase decision aid** - "will my camping gear fit in a Sorento vs. Santa Fe?" comparison
3. **AR measurement** (future) - only VolumTransport has this; could differentiate further
4. **Share/social features** - no competitor has screenshot sharing or social packing lists
5. **AI auto-arrangement** - WeTransport Wetris and 3DPACK.ING have this; could be a future feature

### Threats
1. **Car OEMs could build this** - Hyundai/Kia have 3D configurator infrastructure but no trunk packing tool yet
2. **VolumTransport expanding to iOS** and adding vehicle presets
3. **How-Many-Bags-Fit.com's 3D AI assistant** - if they execute well on 3D, they have the vehicle database advantage
4. **AI-powered tools** (3DPACK.ING, DeepPack) moving downmarket to consumers

### Recommended Priorities
1. **Expand vehicle database** - add more global vehicles (Toyota RAV4, Honda CR-V, Tesla Model Y) to capture international users
2. **Add camping gear presets** - tent bags, coolers, camping chairs, sleeping bags with real dimensions
3. **Comparison mode** - side-by-side trunk comparison across vehicles
4. **Mobile app** (Flutter already supports iOS/Android) - VolumTransport proves mobile demand exists
5. **Screenshot/share** - social sharing of packed trunks for camping communities

---

## Sources

### Direct Competitors
- [VolumTransport](https://aplicacionesherrbri.com/boxes-fit-vehicle/)
- [How-Many-Bags-Fit.com Boot Space Calculator](https://how-many-bags-fit.com/boot-space-calculator/)
- [How-Many-Bags-Fit.com Membership Pricing](https://how-many-bags-fit.com/membership/)
- [Car Boot Carnage](https://carbootcarnage.com/)
- [JCT600 Car Boot Carnage Announcement](https://www.codecomputerlove.com/blog/jct600-launches-car-boot-carnage)

### B2B Logistics Tools
- [EasyCargo](https://www.easycargo3d.com/en/)
- [3DPACK.ING](https://3dpack.ing/)
- [3DBinPacking.com](https://www.3dbinpacking.com/en/)
- [3DBinPacking Pricing](https://www.3dbinpacking.com/en/pricing)
- [PackApp](https://www.packapp.info/en)
- [CargoLab](https://cargolab.app/)
- [Packer3D](http://www.packer3d.com/program/features/overview)
- [DeepPack](https://deeppack.ai/)
- [Cargo-Planner](https://cargo-planner.com/)
- [WeTransport Wetris](https://wentransport.com/wetris/wetris.html)
- [PIER2PIER 3D Load Calculator](https://www.pier2pier.com/loadcalc/)
- [SeaRates Load Calculator](https://www.searates.com/reference/stuffing/)

### Korean Market
- [LogiShop Loading Simulator](https://www.logishop.co.kr/ps_s)
- [SHIPDAGO Pallet Simulator](https://shipdago.com/pallet)
- [LoadLogix GitHub (SSAFY)](https://github.com/SW-LoadLogix/LoadLogix)
- [Box Shipping Simulator (Google Play)](https://play.google.com/store/apps/details?id=appinventor.ai_bateria031.BoxShipping&hl=en_US)
- [CJ Logistics 3D Box Recommendation](https://www.econovill.com/news/articleView.html?idxno=642072)
- [Cello Square Loading Optimizer](https://www.cello-square.com/en/service/view-165.do)

### Car Manufacturer Configurators
- [Hyundai USA Build](https://www.hyundaiusa.com/us/en/build)
- [Hyundai India 360 WebGL](https://www.hyundai.com/in/en/hyundai-story/webgl)
- [Kia 3D Accessory Configurator](https://3dacc.kia.com/)
- [Volvo Developer 3D Portal](https://developer.volvocars.com/3d/)
- [Threekit Car Configurator](https://www.threekit.com/industry/vehicles-and-auto-parts)

### Open Source Projects
- [skjolber/3d-bin-container-packing](https://github.com/skjolber/3d-bin-container-packing)
- [jerry800416/3D-bin-packing](https://github.com/jerry800416/3D-bin-packing)
- [enzoruiz/3dbinpacking](https://github.com/enzoruiz/3dbinpacking)
- [davidmchapman/3DContainerPacking](https://github.com/davidmchapman/3DContainerPacking)
- [lotuc/bin-pack](https://github.com/lotuc/bin-pack)
- [GitHub 3d-bin-packing topic](https://github.com/topics/3d-bin-packing)

### Measurement & Reference
- [Cars.com How We Measure Cargo Space](https://www.cars.com/articles/how-cars-com-measures-cargo-space-427860/)
- [Consumer Reports SUV Cargo Measurements](https://www.consumerreports.org/cars/buying-a-car/measured-cargo-room-for-suvs-and-minivans-a8103760998/)
- [Car Dimensions Tool](https://car-dimensions-tool.com/en/data-accuracy.php)
- [OptioRyx 3D Bin Packing Blog](https://blog.optioryx.com/3d-bin-packing)
