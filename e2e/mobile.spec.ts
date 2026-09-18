import { Page } from '@playwright/test';
import {
  test, expect, shot, waitForApp, waitForSnack, waitForSnackGone, waitForStable, waitForDim, touchSwipe,
  diffRatio, textHue, countHue, countRuns, bboxOfHue, verdictDotHue, Region, Shot,
} from './helpers';

/**
 * 모바일(터치) — 390×844 폰이 기준. 작은 폰(360×640), 가로(844×390), 태블릿(820×1180)은 훑어보기.
 * 최종 타깃이 Android 이므로 탭/스와이프는 실제 터치 이벤트로 보낸다.
 */

const M = {
  onboarding: [195, 300],
  cta: [195, 787],
  bundleMinimal: [98, 378],
  bundleFamily: [246, 378],
  dialogAdd: [325, 694],
  quickCheck: [69, 671],
  autoLayout: [256, 671],
  preset: [75, 28],
  seat: [200, 28],
} as const;

const RM = {
  snack: { x: 100, y: 812, w: 200, h: 22 },
  pill: { x: 4, y: 552, w: 130, h: 30 },
  appBarPreset: { x: 14, y: 8, w: 122, h: 40 },
  appBarSeat: { x: 140, y: 8, w: 120, h: 40 },
  appBar: { x: 0, y: 4, w: 300, h: 48 },
  canvas: { x: 0, y: 160, w: 390, h: 385 },
  title: { x: 20, y: 14, w: 100, h: 28 }, // dim 판정용 (앱바 차종 라벨)
} as const;

const timings: Record<string, number> = {};
test.afterAll(() => {
  if (Object.keys(timings).length) console.log('[timing] phone add→verdict(ms): ' + JSON.stringify(timings));
});

/** 시트 위쪽 경계 y: "자동 배치" 파란 버튼이 시작하는 행 − 여백 */
function sheetTopY(s: Shot): number {
  const w = s.png.width, sc = s.scale;
  for (let y = Math.round(60 * sc); y < s.png.height; y++) {
    let n = 0;
    for (let x = Math.round(140 * sc); x < Math.round(375 * sc); x++) {
      const i = (y * w + x) * 4;
      const [r, g, b] = [s.png.data[i], s.png.data[i + 1], s.png.data[i + 2]];
      if (b > 180 && b > r + 80 && b > g + 30) n++;
    }
    if (n > 200 * sc) return y / sc - 24;
  }
  return -1;
}

async function startPhone(page: Page) {
  await waitForApp(page);
  const start = await shot(page);
  await page.touchscreen.tap(...M.onboarding);
  await page.waitForTimeout(600);
  return start;
}

async function addFamily(page: Page) {
  const base = await shot(page);
  await page.touchscreen.tap(...M.cta);
  expect(await waitForDim(page, base, true, 5000, RM.title), 'CTA 로 장비 다이얼로그가 열린다').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(500);
  await page.touchscreen.tap(...M.bundleFamily);
  await page.waitForTimeout(500);
  const t0 = Date.now();
  await page.touchscreen.tap(...M.dialogAdd);
  const res = await waitForSnack(page, 12000, RM.snack);
  return { kind: res.kind, ms: Date.now() - t0 };
}

test.describe('폰 390×844', () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  test('온보딩 닫기 → CTA → 4인 가족 → 초록 SnackBar → 들어갈까? 다이얼로그가 화면 안에 들어온다', async ({ page }) => {
    const start = await startPhone(page);
    const empty = await shot(page, 'mobile-01-empty');
    expect(countHue(start, { x: 30, y: 125, w: 330, h: 430 }, 'blue'), '온보딩 카드(파란 아이콘/테두리)').toBeGreaterThan(300);
    expect(countHue(empty, { x: 30, y: 125, w: 330, h: 430 }, 'blue'), '탭하면 온보딩이 닫힌다').toBeLessThan(30);

    const res = await addFamily(page);
    await shot(page, 'mobile-02-snack');
    timings.family = res.ms;
    expect(res.kind, '폰에서도 4인 가족 세트는 전부 들어간다').toBe('green');
    expect(res.ms).toBeLessThan(8000);
    await waitForSnackGone(page, 9000, RM.snack);
    const idle = await shot(page, 'mobile-03-idle');
    expect(textHue(idle, RM.pill), '테일게이트 알약 초록').toBe('green');

    // 들어갈까?
    await page.touchscreen.tap(...M.quickCheck);
    expect(await waitForDim(page, idle, true, 8000, RM.title)).toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    const dlg = await shot(page, 'mobile-04-quickcheck');
    expect(verdictDotHue(dlg, { x: 20, y: 100, w: 120, h: 400 }), '판정 점 초록').toBe('green');
    // 버튼 줄: 파란 "배치 저장" 버튼이 뷰포트 안에 온전히 있어야 한다
    const blueBtn = bboxOfHue(dlg, { x: 150, y: 420, w: 240, h: 424 }, 'blue');
    expect(blueBtn, '"배치 저장" 버튼이 보여야 한다').not.toBeNull();
    expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThan(844 - 8);
    expect(blueBtn!.x + blueBtn!.w, '버튼 오른쪽이 화면 안').toBeLessThan(390 - 8);
    expect(blueBtn!.h, '버튼이 잘리지 않았다(높이)').toBeGreaterThan(28);

    // 다이얼로그 바깥을 탭해 닫는다
    await page.touchscreen.tap(195, 40);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '바깥 탭으로 닫힘').toBeGreaterThanOrEqual(0);
  });

  test('바닥 시트를 끌어올리고 내린다 · 앱바의 차종/2열 컨트롤과 2열 메뉴 적용', async ({ page }) => {
    await startPhone(page);
    expect((await addFamily(page)).kind).toBe('green');
    await waitForSnackGone(page, 9000, RM.snack);

    // ── 시트 스와이프 ──
    const y0 = sheetTopY(await shot(page, 'mobile-05-sheet-initial'));
    expect(y0, '처음 시트 높이는 화면의 약 28%').toBeGreaterThan(560);
    await touchSwipe(page, 195, y0 + 10, 195, 180, 20);
    await page.waitForTimeout(700);
    const y1 = sheetTopY(await shot(page, 'mobile-06-sheet-up'));
    expect(y1, '위로 끌면 시트가 올라온다').toBeLessThan(260);
    expect(y1).toBeGreaterThan(0);
    await touchSwipe(page, 195, y1 + 10, 195, y0 + 10, 20);
    await page.waitForTimeout(700);
    const y2 = sheetTopY(await shot(page, 'mobile-07-sheet-down'));
    expect(y2, `아래로 끌면 시트가 내려간다 (y=${y2})`).toBeGreaterThan(540);

    // ── 앱바 ──
    await page.waitForTimeout(300);
    const idle = await shot(page);
    const bright = (s: Shot, r: Region) => s.countColorNear(r, [255, 255, 255], 60) / (s.scale * s.scale);
    expect(bright(idle, RM.appBarPreset), '차종 버튼 글자').toBeGreaterThan(80);
    expect(bright(idle, RM.appBarSeat), '2열 버튼 글자').toBeGreaterThan(80);

    await page.touchscreen.tap(...M.seat);
    await page.waitForTimeout(700);
    const menu = await shot(page, 'mobile-08-seat-menu');
    expect(diffRatio(idle, menu, { x: 140, y: 10, w: 200, h: 160 }), '2열 메뉴가 열린다').toBeGreaterThan(0.1);
    await page.touchscreen.tap(220, 139); // 2열 최전방 (+27cm)
    const snack = await waitForSnack(page, 8000, RM.snack);
    expect(snack.kind, '슬라이드 적용 후 다시 배치 → 초록').toBe('green');
    await waitForSnackGone(page, 9000, RM.snack);
    const front = await shot(page, 'mobile-09-seat-front');
    expect(diffRatio(idle, front, RM.appBarSeat), '2열 라벨이 "+27cm" 로').toBeGreaterThan(0.02);
    expect(diffRatio(idle, front, RM.canvas), '트렁크가 깊어진다').toBeGreaterThan(0.05);
    expect(bright(front, RM.appBarPreset), '좁은 화면에서도 차종 버튼이 남아 있다').toBeGreaterThan(80);
  });

  test('한 손가락 오빗(배치는 그대로) · 탭으로 박스 선택(파란 외곽선)', async ({ page }) => {
    await startPhone(page);
    expect((await addFamily(page)).kind).toBe('green');
    await waitForSnackGone(page, 9000, RM.snack);
    const idle = await waitForStable(page);
    const blue0 = countHue(idle, RM.canvas, 'blue');

    await page.touchscreen.tap(140, 440); // 대형 아이스박스 앞면
    await page.waitForTimeout(500);
    const sel = await shot(page, 'mobile-10-tap-select');
    expect(countHue(sel, RM.canvas, 'blue') - blue0, '선택 외곽선(파랑)').toBeGreaterThan(150);
    expect(textHue(sel, RM.pill), '탭은 박스를 옮기지 않는다').toBe('green');

    await touchSwipe(page, 60, 200, 220, 260, 16); // 빈 곳에서 시작
    const orbited = await waitForStable(page);
    await shot(page, 'mobile-11-orbit');
    expect(diffRatio(idle, orbited, RM.canvas), '한 손가락 드래그로 카메라가 돈다').toBeGreaterThan(0.08);
    expect(textHue(orbited, RM.pill), '오빗은 배치를 건드리지 않는다').toBe('green');
  });
});

// ──── 다른 화면 크기 훑어보기 ────

type Sanity = {
  name: string; title: string;
  vp: { width: number; height: number };
  cta: [number, number]; family: [number, number]; add: [number, number]; quick: [number, number];
  pill: Region;
};

const SANITY: Sanity[] = [
  {
    name: 's360', title: '작은 폰 360×640', vp: { width: 360, height: 640 },
    // 시트 초기 높이 220px (캔버스 56..420) — CTA 가 잘리지 않는다
    cta: [180, 590], family: [246, 280], add: [295, 588], quick: [69, 468],
    pill: { x: 4, y: 351, w: 130, h: 28 },
  },
  {
    name: 'landscape', title: '가로 844×390', vp: { width: 844, height: 390 },
    // 시트 대신 오른쪽 300px 압축 패널 (캔버스 0..544 × 56..390)
    cta: [694, 194], family: [412, 275], add: [613, 338], quick: [591, 316],
    pill: { x: 4, y: 319, w: 130, h: 44 },
  },
  {
    name: 'tablet', title: '태블릿 820×1180', vp: { width: 820, height: 1180 },
    cta: [680, 709], family: [400, 546], add: [601, 862], quick: [0, 0],
    pill: { x: 4, y: 1120, w: 140, h: 34 },
  },
];

for (const c of SANITY) {
  test.describe(c.title, () => {
    test.use({ viewport: c.vp, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

    test(`${c.title}: 온보딩 → 4인 가족 추가 → 초록 판정 → 들어갈까? 다이얼로그가 화면 안`, async ({ page }) => {
      const snackR: Region = { x: c.vp.width * 0.25, y: c.vp.height - 30, w: c.vp.width * 0.3, h: 18 };
      const dimR: Region = { x: 16, y: 14, w: 100, h: 28 };
      await waitForApp(page);
      await page.touchscreen.tap(c.vp.width * 0.3, c.vp.height * 0.4);
      await page.waitForTimeout(600);
      const empty = await shot(page, `mobile-${c.name}-01-empty`);

      await page.touchscreen.tap(...c.cta);
      expect(await waitForDim(page, empty, true, 5000, dimR), 'CTA → 장비 다이얼로그').toBeGreaterThanOrEqual(0);
      await page.waitForTimeout(500);
      await page.touchscreen.tap(...c.family);
      await page.waitForTimeout(500);
      const t0 = Date.now();
      await page.touchscreen.tap(...c.add);
      const res = await waitForSnack(page, 12000, snackR);
      timings[c.name] = Date.now() - t0;
      await shot(page, `mobile-${c.name}-02-snack`);
      expect(res.kind).toBe('green');
      expect(timings[c.name]).toBeLessThan(8000);
      await waitForSnackGone(page, 9000, snackR);
      const idle = await shot(page, `mobile-${c.name}-03-idle`);
      expect(textHue(idle, c.pill), '테일게이트 알약 초록').toBe('green');

      // 들어갈까? 버튼은 초록 테두리 — 태블릿은 위치를 찾아서 누른다
      let quick = c.quick;
      if (quick[0] === 0) {
        const g = bboxOfHue(idle, { x: c.vp.width - 280, y: 200, w: 110, h: c.vp.height - 300 }, 'green');
        expect(g, '"들어갈까?" 버튼').not.toBeNull();
        quick = [g!.x + g!.w / 2, g!.y + g!.h / 2];
      }
      await page.touchscreen.tap(...quick);
      expect(await waitForDim(page, idle, true, 8000, dimR), '판정 다이얼로그').toBeGreaterThanOrEqual(0);
      await page.waitForTimeout(600);
      const dlg = await shot(page, `mobile-${c.name}-04-quickcheck`);
      const blueBtn = bboxOfHue(dlg, { x: 0, y: c.vp.height * 0.35, w: c.vp.width, h: c.vp.height * 0.65 }, 'blue');
      expect(blueBtn, '"배치 저장" 버튼이 보여야 한다').not.toBeNull();
      expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThanOrEqual(c.vp.height - 4);
      expect(blueBtn!.h, '버튼이 잘리지 않았다').toBeGreaterThan(28);
    });
  });
}

test.describe('폰 390×844 — 판정 다이얼로그 버튼 간격', () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  // 예전 버그: 폰 폭에서는 판정 다이얼로그의 버튼 3개(확인/순서 가이드/배치 저장)가 한 줄에 안 들어가
  // 세로로 접히는데, "순서 가이드"와 "배치 저장" 사이 간격이 0px 이라 터치 오작동 위험이 있었다.
  // 지금은 actionsOverflowButtonSpacing 8px (외곽선 버튼의 경계 상자는 ±1px 오차).
  test('폰 판정 다이얼로그의 "순서 가이드"·"배치 저장" 버튼은 한 줄이거나 8px 간격으로 떨어져 있다', async ({ page }) => {
    await startPhone(page);
    expect((await addFamily(page)).kind).toBe('green');
    await waitForSnackGone(page, 9000, RM.snack);
    const idle = await shot(page);
    await page.touchscreen.tap(...M.quickCheck);
    expect(await waitForDim(page, idle, true, 8000, RM.title)).toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    const dlg = await shot(page, 'mobile-bug-verdict-buttons');
    const area = { x: 180, y: 600, w: 170, h: 120 };
    const green = bboxOfHue(dlg, area, 'green');
    const blue = bboxOfHue(dlg, area, 'blue');
    expect(green).not.toBeNull();
    expect(blue).not.toBeNull();
    const sameRow = Math.abs(green!.y - blue!.y) < 10;
    const gap = blue!.y - (green!.y + green!.h);
    expect(sameRow || gap >= 6, `버튼 세로 간격 ${gap.toFixed(1)}px (약 8px 이상이거나 한 줄이어야 한다)`).toBe(true);
  });
});

test.describe('가로 844×390 — 옆 패널 압축 배치', () => {
  test.use({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  // 예전 버그: 가로 폰(높이 390)에서는 시트 패널의 액션바·버튼·통계가 높이를 다 써서 짐 목록이 0줄이었다.
  // 지금은 오른쪽 300px 압축 패널(한 줄 액션바 · 36px 히어로 줄 · 통계 한 줄)이라 목록이 3행 이상 보인다.
  test('가로 폰에서 패널의 짐 목록이 3행 이상 보이고 삭제 버튼을 누를 수 있다', async ({ page }) => {
    const c = SANITY[1];
    await waitForApp(page);
    await page.touchscreen.tap(250, 150);
    await page.waitForTimeout(600);
    await page.touchscreen.tap(...c.cta);
    await page.waitForTimeout(1200);
    await page.touchscreen.tap(...c.family);
    await page.waitForTimeout(500);
    await page.touchscreen.tap(...c.add);
    const snackR: Region = { x: 211, y: 360, w: 253, h: 18 };
    expect((await waitForSnack(page, 12000, snackR)).kind).toBe('green');
    await waitForSnackGone(page, 9000, snackR);
    const idle = await shot(page, 'mobile-landscape-list');
    // 목록(y 104..294)의 빨간 삭제 아이콘 수 = 보이는 타일 수 (아이콘 열 x≈786..822, 50px 간격)
    const listCol = { x: 793, y: 104, w: 22, h: 190 };
    const tiles = countRuns(idle, listCol, 'red');
    expect(tiles, '가로 화면에서도 짐 목록이 3행 이상 보여야 한다').toBeGreaterThanOrEqual(3);
    // 첫 타일의 삭제 버튼을 누르면 타일이 하나 줄고, 판정은 여전히 초록
    await page.touchscreen.tap(804, 129);
    await page.waitForTimeout(800);
    const after = await shot(page, 'mobile-landscape-list-deleted');
    expect(countRuns(after, listCol, 'red'), '삭제 뒤에도 목록이 3행 이상').toBeGreaterThanOrEqual(3);
    expect(diffRatio(idle, after, { x: 60, y: 100, w: 440, h: 200 }), '캔버스에서 짐이 하나 빠졌다').toBeGreaterThan(0.002);
    expect(textHue(after, c.pill), '테일게이트 알약 초록').toBe('green');
  });
});
