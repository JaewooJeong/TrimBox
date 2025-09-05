좋습니다 👍
지금까지 **와이어프레임**을 잡았으니, 이번에는 **디자인 시스템/가이드** 형태로 정리해드릴게요.
(색상, 타이포그래피, 컴포넌트, 인터랙션 규칙 → Figma 토큰처럼 바로 적용 가능하게)

---

# 🎨 TrunkBox Simulator – 디자인 가이드

## 1. 디자인 토큰 (Design Tokens)

### 🎨 색상 팔레트

```json
{
  "color": {
    "background": {
      "default": "#1C1C1C",
      "surface": "#2E2E2E",
      "panel": "#252525"
    },
    "trunk": {
      "floor": "#2E2E2E",
      "wheelhouse": "#A9A9A9",
      "grid": "#CCCCCC"
    },
    "box": {
      "palette": ["#FFB3BA", "#BAE1FF", "#BAFFC9", "#FFFFBA", "#E3BAFF"],
      "selected": "#4DA3FF",
      "error": "#FF4D4D"
    },
    "text": {
      "primary": "#FFFFFF",
      "secondary": "#B3B3B3",
      "inverse": "#1C1C1C"
    },
    "accent": {
      "primary": "#4DA3FF",
      "success": "#6BD06B",
      "warning": "#FFC857",
      "danger": "#FF4D4D"
    }
  }
}
```

---

### ✍️ 타이포그래피

```json
{
  "typography": {
    "fontFamily": "Inter, Noto Sans KR, sans-serif",
    "h1": { "size": 24, "weight": 700, "lineHeight": 32 },
    "h2": { "size": 20, "weight": 600, "lineHeight": 28 },
    "body": { "size": 16, "weight": 400, "lineHeight": 24 },
    "caption": { "size": 12, "weight": 400, "lineHeight": 16 }
  }
}
```

---

### 📏 Spacing & Grid

* **Grid Unit**: 8px (기본)
* **Container Padding**: 16px
* **Gap (컴포넌트 간)**: 12px
* **Box Snap Grid (3D 내부)**: 10cm (UI는 16px 격자)

---

### 🔲 컴포넌트 스타일

* **Button**

  * Default: `background: accent.primary`, `text: white`
  * Hover: 10% 밝게
  * Disabled: `#444444`, `text: #888888`

* **Input Field**

  * Border: `1px solid #4DA3FF`
  * Background: `#1C1C1C`
  * Placeholder: `#888888`

* **Card / Panel**

  * Background: `#252525`
  * Radius: 12px
  * Shadow: `0 2px 6px rgba(0,0,0,0.25)`

---

## 2. 컴포넌트 가이드

### (1) 트렁크 뷰 (Main Canvas)

* 배경: 짙은 회색
* 바닥: 격자 표시 (10cm 간격)
* 휠하우스: 옅은 회색 직육면체
* 박스: 파스텔톤 반투명, 선택 시 테두리 파란색

### (2) 박스 리스트 (Side/Bottom Panel)

* 각 항목: Card 스타일
* 내용: `Box1 45×30×35cm`
* 액션 버튼: \[회전] \[삭제]

### (3) 컨트롤 버튼

* **+ 박스 추가**: Primary Blue
* **저장/불러오기/스크린샷**: Secondary (그레이톤)
* Hover/Active → 테두리 강조

---

## 3. 인터랙션 가이드

* **드래그 앤 드롭**

  * 상자 이동 시 바닥 그리드 스냅
  * 충돌하면 빨간 테두리

* **회전**

  * 90° 단위
  * 애니메이션 200ms ease-in-out

* **저장/불러오기**

  * 저장: JSON 파일 (box list + 위치)
  * 불러오기: JSON 파싱 후 재배치

---

## 4. 다크/라이트 모드

* **Dark (기본)**

  * 배경: #1C1C1C
  * 박스: 파스텔톤 강조
  * 그리드: 옅은 회색

* **Light (보조)**

  * 배경: #F9F9F9
  * 박스: 채도 낮은 톤
  * 그리드: 옅은 회색

---

✅ 이렇게 정리해두면 Figma에서 토큰 → Styles 등록 가능하고, 나중에 코드에서도 `theme.ts`나 `ThemeData`로 쉽게 이식할 수 있습니다.

---

👉 원하시면 제가 **Mermaid로 UI Flow 다이어그램**까지 정리해 드려서, 화면 이동/버튼 액션이 어떻게 이어지는지 시각적으로 표현할 수도 있는데요. 디자인 토큰에 이어 UI 플로우까지 드릴까요?
