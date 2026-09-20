import { expect, Page, test as base } from '@playwright/test';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import * as fs from 'fs';

/**
 * 공용 E2E 도우미.
 *
 * Flutter 웹(CanvasKit)은 DOM 텍스트가 없으므로 좌표로 조작하고 픽셀로 단언한다.
 * 모든 영역(Region)은 CSS px 기준이며, 스크린샷의 deviceScaleFactor 는 자동 보정한다.
 */

export const SHOTS = 'e2e/screenshots';

export type RGB = [number, number, number];
export type Region = { x: number; y: number; w: number; h: number };

export const C = {
  green: [0x6b, 0xd0, 0x6b] as RGB, // 전부 들어감 / 테일게이트 OK
  amber: [0xff, 0xaa, 0x33] as RGB, // 안 들어감 SnackBar
  advice: [0xff, 0xc4, 0x6b] as RGB, // 패널 조언 행
  red: [0xff, 0x4d, 0x4d] as RGB, // 테일게이트 안 닫힘 / 에러 SnackBar
  problem: [0xff, 0x6b, 0x6b] as RGB, // 패널 문제 행
  blue: [0x4d, 0xa3, 0xff] as RGB, // 선택 테두리
};

// ──── 에러 수집 ────

export function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push('console: ' + m.text());
  });
  return errors;
}

/** 모든 테스트가 콘솔/페이지 에러를 수집하고, 하나라도 있으면 실패한다. */
export const test = base.extend<{ errors: string[] }>({
  errors: [
    async ({ page }, use) => {
      const errors = collectErrors(page);
      await use(errors);
      expect(errors, 'console/page errors:\n' + errors.join('\n')).toEqual([]);
    },
    { auto: true },
  ],
});
export { expect };

// ──── 앱 구동 ────

export async function waitForApp(page: Page, opts: { fresh?: boolean } = {}) {
  await page.goto('/', { waitUntil: 'networkidle' });
  if (opts.fresh) {
    await page.evaluate(() => localStorage.clear());
    await page.reload({ waitUntil: 'networkidle' });
  }
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 30000 });
  await waitForFirstFrame(page);
}

/** 첫 프레임(앱바의 밝은 글자)이 그려지고, 폴백 폰트까지 들어와 화면이 멈출 때까지 */
export async function waitForFirstFrame(page: Page) {
  const t0 = Date.now();
  while (Date.now() - t0 < 20000) {
    const s = await shot(page);
    if (s.countColorNear({ x: 0, y: 0, w: s.cssWidth, h: 56 }, [255, 255, 255], 40) > 60 * s.scale * s.scale) break;
    await page.waitForTimeout(100);
  }
  await page.waitForTimeout(500);
  await waitForStable(page, undefined, 5000, 3);
}

// ──── 스크린샷/픽셀 ────

export class Shot {
  constructor(public png: PNG, public scale: number) {}

  px(x: number, y: number): RGB {
    const sx = Math.min(this.png.width - 1, Math.max(0, Math.round(x * this.scale)));
    const sy = Math.min(this.png.height - 1, Math.max(0, Math.round(y * this.scale)));
    const i = (sy * this.png.width + sx) * 4;
    const d = this.png.data;
    return [d[i], d[i + 1], d[i + 2]];
  }

  private bounds(r: Region) {
    const x0 = Math.max(0, Math.floor(r.x * this.scale));
    const y0 = Math.max(0, Math.floor(r.y * this.scale));
    const x1 = Math.min(this.png.width, Math.ceil((r.x + r.w) * this.scale));
    const y1 = Math.min(this.png.height, Math.ceil((r.y + r.h) * this.scale));
    return { x0, y0, x1, y1 };
  }

  avgColor(r: Region): RGB {
    const { x0, y0, x1, y1 } = this.bounds(r);
    let R = 0, G = 0, B = 0, n = 0;
    for (let y = y0; y < y1; y++)
      for (let x = x0; x < x1; x++) {
        const i = (y * this.png.width + x) * 4;
        R += this.png.data[i]; G += this.png.data[i + 1]; B += this.png.data[i + 2]; n++;
      }
    return n ? [R / n, G / n, B / n] : [0, 0, 0];
  }

  /** 영역 안에서 rgb 와 tol 이내인 픽셀 수 */
  countColorNear(r: Region, rgb: RGB, tol = 24): number {
    const { x0, y0, x1, y1 } = this.bounds(r);
    let n = 0;
    for (let y = y0; y < y1; y++)
      for (let x = x0; x < x1; x++) {
        const i = (y * this.png.width + x) * 4;
        const d = this.png.data;
        if (
          Math.abs(d[i] - rgb[0]) <= tol &&
          Math.abs(d[i + 1] - rgb[1]) <= tol &&
          Math.abs(d[i + 2] - rgb[2]) <= tol
        ) n++;
      }
    return n;
  }

  hasColorNear(r: Region, rgb: RGB, tol = 24, minPixels = 12): boolean {
    return this.countColorNear(r, rgb, tol) >= minPixels * this.scale * this.scale;
  }

  /** 영역에서 rgb 에 가까운 픽셀들의 경계 상자 (CSS px). 없으면 null */
  bboxOfColor(r: Region, rgb: RGB, tol = 24): Region | null {
    const { x0, y0, x1, y1 } = this.bounds(r);
    let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
    const d = this.png.data;
    for (let y = y0; y < y1; y++)
      for (let x = x0; x < x1; x++) {
        const i = (y * this.png.width + x) * 4;
        if (
          Math.abs(d[i] - rgb[0]) <= tol &&
          Math.abs(d[i + 1] - rgb[1]) <= tol &&
          Math.abs(d[i + 2] - rgb[2]) <= tol
        ) {
          if (x < minX) minX = x; if (x > maxX) maxX = x;
          if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
      }
    if (maxX < 0) return null;
    const s = this.scale;
    return { x: minX / s, y: minY / s, w: (maxX - minX + 1) / s, h: (maxY - minY + 1) / s };
  }

  crop(r: Region): PNG {
    const { x0, y0, x1, y1 } = this.bounds(r);
    const out = new PNG({ width: x1 - x0, height: y1 - y0 });
    PNG.bitblt(this.png, out, x0, y0, x1 - x0, y1 - y0, 0, 0);
    return out;
  }

  get cssWidth() { return this.png.width / this.scale; }
  get cssHeight() { return this.png.height / this.scale; }
}

export async function shot(page: Page, name?: string): Promise<Shot> {
  const buf = await page.screenshot(name ? { path: `${SHOTS}/${name}.png` } : {});
  const png = PNG.sync.read(buf);
  const vp = page.viewportSize();
  const scale = vp ? png.width / vp.width : 1;
  return new Shot(png, scale);
}

/** 두 스크린샷의 같은 영역에서 다른 픽셀 비율 (0..1) */
export function diffRatio(a: Shot, b: Shot, r?: Region, threshold = 0.1): number {
  const region = r ?? { x: 0, y: 0, w: a.cssWidth, h: a.cssHeight };
  const ca = a.crop(region);
  const cb = b.crop(region);
  if (ca.width !== cb.width || ca.height !== cb.height) return 1;
  const n = pixelmatch(ca.data, cb.data, undefined, ca.width, ca.height, { threshold });
  return n / (ca.width * ca.height);
}

export function saveDiff(a: Shot, b: Shot, r: Region, name: string) {
  const ca = a.crop(r), cb = b.crop(r);
  if (ca.width !== cb.width || ca.height !== cb.height) return;
  const out = new PNG({ width: ca.width, height: ca.height });
  pixelmatch(ca.data, cb.data, out.data, ca.width, ca.height, { threshold: 0.1 });
  fs.writeFileSync(`${SHOTS}/${name}.png`, PNG.sync.write(out));
}

/** 영역에 색이 나타날 때까지(또는 사라질 때까지) 폴링. 걸린 ms 를 돌려준다. 실패 시 -1 */
export async function waitForColor(
  page: Page, r: Region, rgb: RGB,
  opts: { timeout?: number; tol?: number; minPixels?: number; gone?: boolean; interval?: number } = {},
): Promise<number> {
  const { timeout = 8000, tol = 24, minPixels = 12, gone = false, interval = 120 } = opts;
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const s = await shot(page);
    if (s.hasColorNear(r, rgb, tol, minPixels) !== gone) return Date.now() - t0;
    await page.waitForTimeout(interval);
  }
  return -1;
}

/** 연속 `needed` 프레임이 같아질 때까지 기다린다 (애니메이션·폰트 로딩 종료) */
export async function waitForStable(page: Page, r?: Region, timeout = 5000, needed = 2): Promise<Shot> {
  const t0 = Date.now();
  let prev = await shot(page);
  let same = 1;
  while (Date.now() - t0 < timeout) {
    await page.waitForTimeout(150);
    const cur = await shot(page);
    same = diffRatio(prev, cur, r) < 0.0005 ? same + 1 : 1;
    prev = cur;
    if (same >= needed) return cur;
  }
  return prev;
}

// ──── 입력 ────

export async function drag(
  page: Page, x0: number, y0: number, x1: number, y1: number,
  opts: { steps?: number; button?: 'left' | 'right' | 'middle' } = {},
) {
  const { steps = 12, button = 'left' } = opts;
  await page.mouse.move(x0, y0);
  await page.mouse.down({ button });
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(x0 + ((x1 - x0) * i) / steps, y0 + ((y1 - y0) * i) / steps);
    await page.waitForTimeout(20);
  }
  await page.mouse.up({ button });
  await page.waitForTimeout(400);
}

/** CDP 로 진짜 터치 스와이프를 보낸다 (hasTouch 컨텍스트) */
export async function touchSwipe(
  page: Page, x0: number, y0: number, x1: number, y1: number, steps = 12,
) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: y0 }] });
  for (let i = 1; i <= steps; i++) {
    const x = x0 + ((x1 - x0) * i) / steps;
    const y = y0 + ((y1 - y0) * i) / steps;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] });
    await page.waitForTimeout(16);
  }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await cdp.detach();
  await page.waitForTimeout(500);
}

export async function tap(page: Page, x: number, y: number) {
  await page.touchscreen.tap(x, y);
}

export async function heapMB(page: Page): Promise<number | null> {
  try {
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('HeapProfiler.collectGarbage');
    await cdp.detach();
  } catch { /* GC 강제는 선택 사항 */ }
  return page.evaluate(() => {
    const m = (performance as any).memory;
    return m ? Math.round((m.usedJSHeapSize / 1048576) * 10) / 10 : null;
  });
}

// ──── 색 분류 (안티앨리어싱된 글자용) ────

export type Hue = 'green' | 'red' | 'amber' | 'blue' | 'alarm';

function isHue(r: number, g: number, b: number, hue: Hue): boolean {
  switch (hue) {
    case 'green': return g > 120 && g > r + 40 && g > b + 40;
    case 'red': return r > 150 && r > g + 70 && r > b + 70;
    case 'amber': return r > 180 && g > 110 && g < r - 25 && b < g - 40;
    case 'blue': return b > 180 && b > r + 80 && b > g + 30;
    // 경고 빨강(#FF4D4D 계열)만 — 주황 박스(g-b 차가 큼)는 제외
    case 'alarm': return r > 200 && g < 115 && b < 115 && Math.abs(g - b) < 35;
  }
}

export function countHue(s: Shot, r: Region, hue: Hue): number {
  const x0 = Math.max(0, Math.floor(r.x * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale));
  const x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  let n = 0;
  const d = s.png.data;
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (isHue(d[i], d[i + 1], d[i + 2], hue)) n++;
    }
  return n / (s.scale * s.scale);
}

/** 영역의 글자색을 green/red/amber 중 가장 많은 것으로 분류. 글자가 없으면 null */
export function textHue(s: Shot, r: Region, minPixels = 15): Hue | null {
  const hues: Hue[] = ['green', 'red', 'amber'];
  let best: Hue | null = null, bestN = minPixels;
  for (const h of hues) {
    const n = countHue(s, r, h);
    if (n > bestN) { best = h; bestN = n; }
  }
  return best;
}

export function luminance(c: RGB): number {
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

// ──── 데스크톱 1280×960 공용 좌표/영역/플로우 ────

export const DESKTOP = { width: 1280, height: 960 };

export const D = {
  onboarding: [460, 480],
  cta: [1097, 597], // 캠핑 장비 선택하기 (빈 상태)
  addBox: [1045, 76], // 패널 "박스 추가"
  save: [1126, 85],
  load: [1176, 85],
  screenshot: [1226, 85],
  wand: [1013, 135], // 패널 액션바의 자동 배치 아이콘
  share: [1063, 135],
  undo: [1113, 135],
  redo: [1163, 135],
  help: [1260, 28],
  // 장비 다이얼로그 (캠핑 탭)
  tabCustom: [516, 251],
  bundleMinimal: [482, 436],
  bundleFamily: [630, 436],
  bundleSolo: [778, 436],
  search: [640, 335],
  firstItem: [428, 507],
  dialogAdd: [830, 752],
  dialogCancel: [757, 752],
  // 직접 입력 탭 (다이얼로그 높이가 줄어 좌표가 다르다)
  customLabel: [640, 422],
  customW: [488, 482],
  customD: [640, 482],
  customH: [792, 482],
  customAdd: [830, 646],
  // 판정/자동 배치 버튼: "적재 순서 가이드" 버튼 유무에 따라 y 가 달라진다
  quickCheckWithGuide: [1029, 776],
  autoLayoutWithGuide: [1180, 776],
  stepGuide: [1119, 828],
  quickCheckNoGuide: [1029, 816],
  autoLayoutNoGuide: [1180, 816],
  preset: [230, 28],
  presetSorento5: [250, 71],
  presetSorento7: [250, 119],
  presetCustom: [250, 168],
  seatSlide: [420, 28],
  seatRear: [440, 43],
  seatMid: [440, 91],
  seatFront: [440, 139],
  firstTile: [1090, 193],
  firstTileRotate: [1198, 193],
  firstTileDelete: [1234, 193],
} as const;

export const RD = {
  snack: { x: 250, y: 925, w: 650, h: 25 }, // 캔버스 아래쪽만 (패널의 초록 게이지/글자 제외)
  pill: { x: 6, y: 906, w: 200, h: 28 },
  panelStatus: { x: 965, y: 928, w: 310, h: 26 },
  canvas: { x: 0, y: 62, w: 955, h: 835 }, // 상단 진행바/하단 캡션 제외
  canvasCore: { x: 120, y: 160, w: 700, h: 640 }, // 적재율 오버레이 제외
  appBarPreset: { x: 110, y: 8, w: 250, h: 40 },
  appBarControls: { x: 110, y: 8, w: 500, h: 40 },
  caption: { x: 0, y: 934, w: 600, h: 20 },
  panelList: { x: 965, y: 160, w: 310, h: 580 },
  firstTile: { x: 972, y: 164, w: 296, h: 58 },
  firstTileTopBorder: { x: 990, y: 165, w: 180, h: 6 }, // 아이콘을 피한 위쪽 테두리 띠
  overlay: { x: 838, y: 66, w: 112, h: 84 },
} as const;

export type SnackKind = 'green' | 'amber' | 'red' | null;

export function snackKind(s: Shot, r: Region = RD.snack): SnackKind {
  const total = r.w * r.h;
  if (s.countColorNear(r, C.green, 10) / (s.scale * s.scale) > total * 0.7) return 'green';
  if (s.countColorNear(r, C.amber, 10) / (s.scale * s.scale) > total * 0.7) return 'amber';
  if (s.countColorNear(r, C.red, 10) / (s.scale * s.scale) > total * 0.7) return 'red';
  return null;
}

/** SnackBar 가 나타날 때까지 폴링. {kind, ms} */
export async function waitForSnack(page: Page, timeout = 10000, r: Region = RD.snack) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const s = await shot(page);
    const kind = snackKind(s, r);
    if (kind) return { kind, ms: Date.now() - t0, shot: s };
    await page.waitForTimeout(80);
  }
  return { kind: null as SnackKind, ms: -1, shot: await shot(page) };
}

/** SnackBar 가 사라질 때까지 (기본 4초 표시 + 애니메이션) */
export async function waitForSnackGone(page: Page, timeout = 9000, r: Region = RD.snack) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const s = await shot(page);
    const px = r.w * r.h * s.scale * s.scale;
    const left = s.countColorNear(r, C.green, 10) + s.countColorNear(r, C.amber, 10) + s.countColorNear(r, C.red, 10);
    if (!snackKind(s, r) && left < px * 0.02) {
      await page.waitForTimeout(250);
      return;
    }
    await page.waitForTimeout(200);
  }
  throw new Error('SnackBar 가 사라지지 않음');
}

export async function startDesktop(page: Page, opts: { fresh?: boolean } = {}) {
  await waitForApp(page, opts);
  await page.mouse.click(...D.onboarding);
  await page.waitForTimeout(500);
}

export async function openAddDialog(page: Page) {
  const before = await shot(page);
  await page.mouse.click(...D.addBox);
  await page.waitForTimeout(900);
  const after = await shot(page);
  // 다이얼로그가 뜨면 배경(캔버스 구석)이 어두워진다
  expect(isDimmed(before, after), '장비 다이얼로그가 열려 배경이 어두워져야 한다').toBe(true);
}

/** 배경 dim 여부: 앱바 제목 영역의 밝기가 확 줄었는지 */
export function isDimmed(before: Shot, after: Shot, r: Region = { x: 14, y: 14, w: 86, h: 28 }): boolean {
  const a = luminance(before.avgColor(r));
  const b = luminance(after.avgColor(r));
  return b < a * 0.75;
}

export type Bundle = 'minimal' | 'family' | 'solo';

/** 번들을 추가하고 "추가" 클릭 → SnackBar 까지 걸린 시간을 돌려준다 */
export async function addBundle(page: Page, which: Bundle) {
  await openAddDialog(page);
  const pos = which === 'minimal' ? D.bundleMinimal : which === 'family' ? D.bundleFamily : D.bundleSolo;
  await page.mouse.click(...pos);
  await page.waitForTimeout(500);
  const t0 = Date.now();
  await page.mouse.click(...D.dialogAdd);
  const res = await waitForSnack(page, 12000);
  return { kind: res.kind, ms: res.kind ? Date.now() - t0 : -1, shot: res.shot };
}

export async function setField(page: Page, x: number, y: number, value: string) {
  await page.mouse.click(x, y);
  await page.waitForTimeout(200);
  await page.keyboard.press('Control+a');
  await page.keyboard.type(value);
  await page.waitForTimeout(150);
}

export async function addCustomBox(page: Page, label: string, w: number, d: number, h: number) {
  await openAddDialog(page);
  await page.mouse.click(...D.tabCustom);
  await page.waitForTimeout(700);
  await setField(page, ...D.customLabel, label);
  await setField(page, ...D.customW, String(w));
  await setField(page, ...D.customD, String(d));
  await setField(page, ...D.customH, String(h));
  const t0 = Date.now();
  await page.mouse.click(...D.customAdd);
  const res = await waitForSnack(page, 12000);
  return { kind: res.kind, ms: res.kind ? Date.now() - t0 : -1, shot: res.shot };
}

// ──── 목록 타일 수 세기 / 변화 위치 찾기 ────

/** 영역을 위→아래로 훑어 hue 픽셀이 있는 세로 구간(run)의 수를 센다 */
export function countRuns(s: Shot, r: Region, hue: Hue, minGap = 6): number {
  const x0 = Math.floor(r.x * s.scale), x1 = Math.ceil((r.x + r.w) * s.scale);
  const y0 = Math.floor(r.y * s.scale), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  const d = s.png.data;
  let runs = 0, gap = minGap * s.scale, inRun = false;
  for (let y = y0; y < y1; y++) {
    let hit = false;
    for (let x = x0; x < x1 && !hit; x++) {
      const i = (y * s.png.width + x) * 4;
      if (isHue(d[i], d[i + 1], d[i + 2], hue)) hit = true;
    }
    if (hit) {
      if (!inRun && gap >= minGap * s.scale) runs++;
      inRun = true; gap = 0;
    } else { inRun = false; gap++; }
  }
  return runs;
}

/** 데스크톱 패널 목록에 보이는 타일 수 (빨간 삭제 아이콘을 센다) */
export function countTiles(s: Shot): number {
  return countRuns(s, { x: 1224, y: 162, w: 20, h: 584 }, 'red');
}

/** 두 스크린샷이 다른 픽셀들의 경계 상자 (CSS px) */
export function bboxOfDiff(a: Shot, b: Shot, r: Region, tol = 40): Region | null {
  const x0 = Math.floor(r.x * a.scale), x1 = Math.ceil((r.x + r.w) * a.scale);
  const y0 = Math.floor(r.y * a.scale), y1 = Math.ceil((r.y + r.h) * a.scale);
  let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++) {
      const i = (y * a.png.width + x) * 4;
      const dd = Math.abs(a.png.data[i] - b.png.data[i]) + Math.abs(a.png.data[i + 1] - b.png.data[i + 1]) +
        Math.abs(a.png.data[i + 2] - b.png.data[i + 2]);
      if (dd > tol) {
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  if (maxX < 0) return null;
  const sc = a.scale;
  return { x: minX / sc, y: minY / sc, w: (maxX - minX + 1) / sc, h: (maxY - minY + 1) / sc };
}

export function center(r: Region): [number, number] {
  return [r.x + r.w / 2, r.y + r.h / 2];
}

/** 영역에서 hue 픽셀들의 경계 상자 (CSS px) */
export function bboxOfHue(s: Shot, r: Region, hue: Hue): Region | null {
  const x0 = Math.max(0, Math.floor(r.x * s.scale)), x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale)), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  let minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
  const d = s.png.data;
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (isHue(d[i], d[i + 1], d[i + 2], hue)) {
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
      }
    }
  if (maxX < 0) return null;
  return { x: minX / s.scale, y: minY / s.scale, w: (maxX - minX + 1) / s.scale, h: (maxY - minY + 1) / s.scale };
}

/** 배경이 dim 될 때까지(=다이얼로그가 뜰 때까지) 폴링. 걸린 ms, 실패 -1 */
export async function waitForDim(
  page: Page, base: Shot, want = true, timeout = 10000, r?: Region,
): Promise<number> {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (isDimmed(base, await shot(page), r) === want) return Date.now() - t0;
    await page.waitForTimeout(100);
  }
  return -1;
}

/**
 * 판정 다이얼로그 제목 옆 점의 색. 다이얼로그 크기가 내용에 따라 달라지므로
 * 왼쪽 위 영역에서 가장 위에 있는 초록/빨강 덩어리를 점으로 본다.
 */
export function verdictDotHue(s: Shot, r: Region = { x: 430, y: 200, w: 120, h: 200 }): 'green' | 'red' | null {
  const g = bboxOfHue(s, r, 'green');
  const a = bboxOfHue(s, r, 'alarm');
  if (!g && !a) return null;
  if (g && a) return g.y <= a.y ? 'green' : 'red';
  return g ? 'green' : 'red';
}

// ──── 폰 UI (backlog/phone-ux-w9.md) 도우미 ────

/** 트렁크 후미등의 실제 화면 색 (fixtures.lampColor 0xD9C8283C 가 어두운 차체 위에 평면 음영으로 그려진 값) */
export const LAMP: RGB = [132, 32, 44];

/** 영역에서 후미등 색 픽셀의 경계 상자 (CSS px). 트렁크가 시트에 가려지지 않았는지 볼 때 쓴다. 없으면 null */
export function lampBbox(s: Shot, r: Region): Region | null {
  return s.bboxOfColor(r, LAMP, 22);
}

/**
 * 폰 아래 시트의 위 경계 y (CSS px): 손잡이(#666666, 32×4, 시트 top+8) 를 x=cx 열에서 찾는다.
 * 시트 배경(#252525)만 인정하므로 결과 모달 시트(#2A2A2A)의 손잡이는 잡지 않는다. 실패 -1
 */
export function sheetTopByHandle(s: Shot, cx: number, from = 60): number {
  const near = (p: RGB, v: number, tol: number) =>
    Math.abs(p[0] - v) <= tol && Math.abs(p[1] - v) <= tol && Math.abs(p[2] - v) <= tol;
  for (let y = from; y < s.cssHeight - 12; y++) {
    if (!near(s.px(cx, y), 0x66, 14)) continue;
    if (!near(s.px(cx - 12, y), 0x66, 14) || !near(s.px(cx + 12, y), 0x66, 14)) continue;
    if (!near(s.px(cx, y - 3), 0x25, 4) || !near(s.px(cx, y + 5), 0x25, 4)) continue;
    if (!near(s.px(cx - 22, y), 0x25, 4) || !near(s.px(cx + 22, y), 0x25, 4)) continue;
    return y - 8;
  }
  return -1;
}

/** 영역을 위→아래로 훑어 hue 픽셀이 있는 첫 세로 구간(run)의 y 범위 (CSS px). 없으면 null */
export function firstHueRun(
  s: Shot, r: Region, hue: Hue, minPixelsPerRow = 1,
): { y0: number; y1: number } | null {
  const x0 = Math.max(0, Math.floor(r.x * s.scale)), x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale)), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  const d = s.png.data;
  let start = -1;
  for (let y = y0; y < y1; y++) {
    let n = 0;
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (isHue(d[i], d[i + 1], d[i + 2], hue)) n++;
    }
    const hit = n >= minPixelsPerRow * s.scale;
    if (hit && start < 0) start = y;
    if (!hit && start >= 0) return { y0: start / s.scale, y1: y / s.scale };
  }
  return start >= 0 ? { y0: start / s.scale, y1: y1 / s.scale } : null;
}

/** 영역에서 rgb 가 가로로 minFrac 이상 이어진 첫 행의 y (CSS px). 구분선·바 찾기용. 없으면 -1 */
export function findRowOfColor(s: Shot, r: Region, rgb: RGB, tol = 8, minFrac = 0.8): number {
  const x0 = Math.max(0, Math.floor(r.x * s.scale)), x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale)), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  const d = s.png.data;
  for (let y = y0; y < y1; y++) {
    let n = 0;
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (Math.abs(d[i] - rgb[0]) <= tol && Math.abs(d[i + 1] - rgb[1]) <= tol && Math.abs(d[i + 2] - rgb[2]) <= tol) n++;
    }
    if (n >= (x1 - x0) * minFrac) return y / s.scale;
  }
  return -1;
}

/** 폰 캔버스의 테일게이트 상태 알약 영역: 한 줄 캡션 바로 위 (캔버스 아래 경계 −54 .. −28) */
export function phonePillRegion(canvasBottom: number): Region {
  return { x: 4, y: canvasBottom - 54, w: 130, h: 26 };
}

/**
 * 전체 화면 장비 선택 페이지가 떠 있는가: 앱바 왼쪽 ✕ + '장비 선택' 제목(흰 글자)이 있고,
 * 메인 화면이라면 흰 글자가 있을 2열 버튼 자리(x 150..270)는 비어 있다.
 */
export function isGearPage(s: Shot): boolean {
  const white = (r: Region) => s.countColorNear(r, [255, 255, 255], 60) / (s.scale * s.scale);
  return white({ x: 72, y: 16, w: 80, h: 24 }) > 120 &&
    white({ x: 150, y: 8, w: 120, h: 40 }) < 5 &&
    white({ x: 16, y: 16, w: 24, h: 24 }) > 15;
}

/** 장비 페이지가 뜰 때까지(또는 사라질 때까지) 폴링. 걸린 ms, 실패 -1 */
export async function waitForGearPage(page: Page, want = true, timeout = 6000): Promise<number> {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    if (isGearPage(await shot(page)) === want) return Date.now() - t0;
    await page.waitForTimeout(100);
  }
  return -1;
}

/** 폰 시트 위 경계가 목표 범위에 들어올 때까지 폴링 (스냅 애니메이션 종료 대기). 마지막 값을 돌려준다 */
export async function waitForSheetTop(
  page: Page, cx: number, pred: (top: number) => boolean, timeout = 4000,
): Promise<number> {
  const t0 = Date.now();
  let top = -1;
  while (Date.now() - t0 < timeout) {
    top = sheetTopByHandle(await shot(page), cx);
    if (pred(top)) return top;
    await page.waitForTimeout(120);
  }
  return top;
}

/** 영역을 위→아래로 훑어 hue 픽셀이 있는 세로 구간(run)들의 y 범위 (CSS px) */
export function hueRuns(
  s: Shot, r: Region, hue: Hue, minPixelsPerRow = 1,
): { y0: number; y1: number }[] {
  const x0 = Math.max(0, Math.floor(r.x * s.scale)), x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale)), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  const d = s.png.data;
  const out: { y0: number; y1: number }[] = [];
  let start = -1;
  for (let y = y0; y < y1; y++) {
    let n = 0;
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (isHue(d[i], d[i + 1], d[i + 2], hue)) n++;
    }
    const hit = n >= minPixelsPerRow * s.scale;
    if (hit && start < 0) start = y;
    if (!hit && start >= 0) { out.push({ y0: start / s.scale, y1: y / s.scale }); start = -1; }
  }
  if (start >= 0) out.push({ y0: start / s.scale, y1: y1 / s.scale });
  return out;
}

/** 영역에서 rgb 에 가까운 픽셀이 한 행에 minPixels 이상 있는 첫 행의 y (CSS px). 글자 줄 찾기용. 없으면 -1 */
export function firstRowWithColor(s: Shot, r: Region, rgb: RGB, tol = 60, minPixels = 4): number {
  const x0 = Math.max(0, Math.floor(r.x * s.scale)), x1 = Math.min(s.png.width, Math.ceil((r.x + r.w) * s.scale));
  const y0 = Math.max(0, Math.floor(r.y * s.scale)), y1 = Math.min(s.png.height, Math.ceil((r.y + r.h) * s.scale));
  const d = s.png.data;
  for (let y = y0; y < y1; y++) {
    let n = 0;
    for (let x = x0; x < x1; x++) {
      const i = (y * s.png.width + x) * 4;
      if (Math.abs(d[i] - rgb[0]) <= tol && Math.abs(d[i + 1] - rgb[1]) <= tol && Math.abs(d[i + 2] - rgb[2]) <= tol) n++;
    }
    if (n >= minPixels * s.scale) return y / s.scale;
  }
  return -1;
}
