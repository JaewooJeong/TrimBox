import { Page } from '@playwright/test';
import {
  test, expect, shot, Shot, Region, C,
  waitForApp, waitForSnack, waitForSnackGone, waitForStable, waitForDim, waitForColor, touchSwipe,
  diffRatio, textHue, countHue, countRuns, bboxOfHue, luminance,
  lampBbox, sheetTopByHandle, firstHueRun, hueRuns, findRowOfColor, phonePillRegion, isGearPage, waitForGearPage,
  waitForSheetTop, bboxOfDiff,
} from './helpers';

/**
 * 모바일(터치) — 390×844 폰이 기준. 작은 폰(360×640), 가로(844×390), 태블릿(820×1180)은 훑어보기.
 * 최종 타깃이 Android 이므로 탭/스와이프는 실제 터치 이벤트로 보낸다.
 *
 * 폰 UI (backlog/phone-ux-w9.md): 장비 선택은 전체 화면 페이지, 판정·자동 배치 결과는 아래 모달 시트,
 * 캔버스는 시트 높이를 따라 줄어든다(첫 짐이 들어오면 시트가 28% → 45% 로 올라간다), 캔버스에서 짐을
 * 탭하면 캡션 위에 선택 도구 띠(회전·삭제·✕)가 뜬다.
 *
 * 좌표는 위젯 테스트(getRect)로 산출해 스크린샷으로 확인했다. 웹 빌드는 Windows Chrome UA 라 데스크톱
 * 밀도(텍스트 버튼 32px)로 그려지므로, android 밀도(48px)에서도 같은 위젯 안에 드는 지점을 골랐다.
 */

// ──── 390×844 좌표 ────

const M = {
  onboarding: [195, 300],
  cta: [195, 767], // 캠핑 장비 선택하기 (빈 시트, y 751..783)
  // 전체 화면 장비 페이지
  gearClose: [28, 28],
  gearFamily: [230, 268], // 4인 가족 캠핑 카드 (y 218..297)
  gearAdd: [300, 812], // 하단 전체 폭 '추가 (N개)' (y 788..836)
  // 짐이 있을 때 (시트 45%, 시트 위 경계 ≈ 489)
  quickCheck: [71, 537],
  autoLayout: [258, 537],
  addBox: [101, 592],
  guide: [199, 592],
  undo: [251, 592],
  redo: [303, 592],
  more: [355, 592],
  menuSave: [335, 601], // ⋯ 메뉴 첫 항목 '배치 저장'
  help: [368, 28],
  preset: [75, 28],
  seat: [200, 28],
  seatFront: [220, 139], // 2열 메뉴 3번째: 최전방 (+27cm)
  // 선택 도구 띠 버튼은 고정 좌표가 아니라 findToolbar() 로 찾는다 (띠가 위·아래로 옮겨 다닌다)
  // 대형 아이스박스 윗면 중심 (4인 가족 자동 배치는 결정적) — 첫 후보가 빗나가면 다음 후보
  boxCandidates: [[144, 282], [170, 254], [130, 212], [263, 289]] as [number, number][],
} as const;

const RM = {
  snack: { x: 100, y: 812, w: 200, h: 22 },
  appBarPreset: { x: 14, y: 8, w: 122, h: 40 },
  appBarSeat: { x: 140, y: 8, w: 120, h: 40 },
  title: { x: 20, y: 14, w: 100, h: 28 }, // dim 판정용 (앱바 차종 라벨)
  onboardingCard: { x: 30, y: 125, w: 330, h: 430 },
  canvasLoaded: { x: 0, y: 110, w: 390, h: 320 }, // 시트 45% 일 때 트렁크 영역 (칩·알약·도구 띠 제외)
  canvasCore: { x: 60, y: 130, w: 270, h: 240 },
  chip: { x: 210, y: 60, w: 172, h: 36 }, // 적재율 칩 (오른쪽 위)
} as const;

const VP = { width: 390, height: 844 };
const SHEET_EMPTY_TOP = 623; // 220px 고정 (빈 상태)
const SHEET_LOADED_TOP = 489; // 844 × (1 − 0.45)

/** 시트 위 경계 기준 상대 영역 */
const statsRegion = (top: number): Region => ({ x: 10, y: top + 133, w: 220, h: 20 }); // '박스 16개 · 부피 …' (상태 행 제외)
const statusRegion = (top: number): Region => ({ x: 14, y: top + 154, w: 260, h: 22 }); // 상태 행
const toolbarZone = (canvasBottom: number): Region => ({ x: 0, y: canvasBottom - 112, w: 390, h: 56 });

/**
 * 선택 도구 띠(파란 테두리, 높이 48)를 찾는다. 기본은 캡션 위(캔버스 아래 60px)지만, 선택한 짐이
 * 그 자리까지 내려와 있으면 띠가 캔버스 위쪽(칩 아래, 캔버스 top+48)으로 올라간다 — 두 자리를 다 본다.
 * 버튼 중심은 띠 오른쪽 끝 기준: 회전 −123, 삭제 −75, ✕ −27.
 */
function findToolbar(s: Shot, canvasBottom: number, width: number, canvasTop = 56) {
  const zones: Region[] = [
    { x: 0, y: canvasBottom - 112, w: width, h: 56 },
    { x: 0, y: canvasTop + 44, w: width, h: 56 },
  ];
  for (const zone of zones) {
    const bar = bboxOfHue(s, zone, 'blue');
    if (bar && bar.w > width * 0.85 && bar.h >= 44 && bar.h <= 52) {
      const y = bar.y + bar.h / 2;
      const right = bar.x + bar.w;
      return {
        bar, zone,
        rotate: [right - 123, y] as [number, number],
        delete: [right - 75, y] as [number, number],
        deselect: [right - 27, y] as [number, number],
      };
    }
  }
  return null;
}

/** 두 자리 중 어디든 띠(폭 ≥ 85%)가 있으면 그 폭, 없으면 0 */
function toolbarWidth(s: Shot, canvasBottom: number, width: number, canvasTop = 56): number {
  return findToolbar(s, canvasBottom, width, canvasTop)?.bar.w ?? 0;
}

const timings: Record<string, number> = {};
test.afterAll(() => {
  if (Object.keys(timings).length) console.log('[timing] phone add→snack / sheets (ms): ' + JSON.stringify(timings));
});

async function startPhone(page: Page) {
  await waitForApp(page);
  const start = await shot(page);
  await page.touchscreen.tap(...M.onboarding);
  await page.waitForTimeout(600);
  return start;
}

/** CTA(또는 '박스 추가') → 전체 화면 장비 페이지 → 4인 가족 → 추가 (16개) → SnackBar */
async function addFamily(page: Page, opener: readonly [number, number] = M.cta) {
  await page.touchscreen.tap(...opener);
  const openMs = await waitForGearPage(page);
  expect(openMs, '전체 화면 장비 페이지가 열린다 (✕ + 장비 선택 제목)').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  await page.touchscreen.tap(...M.gearFamily);
  await page.waitForTimeout(500);
  const t0 = Date.now();
  await page.touchscreen.tap(...M.gearAdd);
  const res = await waitForSnack(page, 12000, RM.snack);
  return { kind: res.kind, ms: Date.now() - t0, openMs };
}

/** 짐을 넣고 SnackBar 가 사라진 안정 상태까지. 시트가 45% 로 올라온 것을 확인한다 */
async function loadFamilyIdle(page: Page) {
  await startPhone(page);
  const res = await addFamily(page);
  expect(res.kind, '4인 가족 세트는 전부 들어간다').toBe('green');
  await waitForSnackGone(page, 9000, RM.snack);
  const idle = await waitForStable(page);
  const top = sheetTopByHandle(idle, 195);
  expect(Math.abs(top - SHEET_LOADED_TOP), `짐이 들어오면 시트가 45% (top≈${SHEET_LOADED_TOP}, 실제 ${top})`).toBeLessThan(6);
  return { idle, top };
}

/** 캔버스의 짐을 탭해 선택 도구 띠(파란 테두리 띠, 캔버스 아래 60px 위)를 띄운다 */
async function selectBoxOnCanvas(page: Page, canvasBottom: number) {
  for (const p of M.boxCandidates) {
    await page.touchscreen.tap(...p);
    await page.waitForTimeout(500);
    const s = await shot(page);
    const tb = findToolbar(s, canvasBottom, 390);
    if (tb) return { shot: s, bar: tb.bar, at: p, tb };
  }
  throw new Error('어느 후보 지점에서도 선택 도구 띠가 뜨지 않았다');
}

/** 결과 시트 제목 줄의 y (초록/빨강 점이 있는 행) — ✕ 는 같은 줄 오른쪽(x 352) */
function resultTitleY(s: Shot, dotColumn: Region): number {
  const g = firstHueRun(s, dotColumn, 'green', 4);
  const a = firstHueRun(s, dotColumn, 'alarm', 4);
  const run = g && a ? (g.y0 <= a.y0 ? g : a) : g ?? a;
  expect(run, '결과 시트 제목 줄의 점').not.toBeNull();
  return (run!.y0 + run!.y1) / 2;
}

test.describe('폰 390×844', () => {
  test.use({ viewport: VP, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  test('온보딩 → CTA → 전체 화면 장비 페이지 → 4인 가족 → 추가 (16개) → 초록 SnackBar → 시트 45% · 트렁크 온전 · 알약 초록', async ({ page }) => {
    const start = await startPhone(page);
    const empty = await shot(page, 'mobile-01-empty');
    expect(countHue(start, RM.onboardingCard, 'blue'), '온보딩 카드(파란 아이콘/테두리)').toBeGreaterThan(300);
    expect(countHue(empty, RM.onboardingCard, 'blue'), '탭하면 온보딩이 닫힌다').toBeLessThan(30);
    const emptyTop = sheetTopByHandle(empty, 195);
    expect(Math.abs(emptyTop - SHEET_EMPTY_TOP), `빈 상태 시트 위 경계 ≈ ${SHEET_EMPTY_TOP} (실제 ${emptyTop})`).toBeLessThan(6);
    const cta = bboxOfHue(empty, { x: 0, y: emptyTop, w: 390, h: 844 - emptyTop }, 'blue');
    expect(cta, '시트 안 파란 CTA').not.toBeNull();
    expect(cta!.y <= M.cta[1] && cta!.y + cta!.h >= M.cta[1], `CTA 세로 범위 ${cta!.y}..${cta!.y + cta!.h} 가 탭 지점 ${M.cta[1]} 을 포함`).toBe(true);
    expect(lampBbox(empty, { x: 0, y: 56, w: 390, h: emptyTop - 56 }), '빈 트렁크에도 후미등이 보인다').not.toBeNull();

    // ── 전체 화면 장비 페이지 ──
    await page.touchscreen.tap(...M.cta);
    timings.gearPageOpen = await waitForGearPage(page);
    expect(timings.gearPageOpen, 'CTA → 장비 페이지').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(400);
    const gear = await shot(page, 'mobile-02-gear-page');
    expect(isDimmedAppBarGone(empty, gear), '앱바의 차종·2열 버튼이 사라지고 페이지 앱바로 바뀐다').toBe(true);
    // 하단 고정 바: 위쪽 구분선(#444444)이 전체 폭으로, 그 아래 48px '추가' 버튼
    const barLine = findRowOfColor(gear, { x: 0, y: 760, w: 390, h: 40 }, [0x44, 0x44, 0x44], 10, 0.9);
    expect(barLine, '하단 고정 바의 위 구분선').toBeGreaterThan(0);
    expect(barLine, '구분선이 화면 아래쪽(≈780)에 있다').toBeGreaterThan(770);
    // 아직 고른 게 없으면 '추가' 는 비활성(회색): 파란 버튼 없음
    expect(bboxOfHue(gear, { x: 0, y: 780, w: 390, h: 64 }, 'blue'), '선택 전에는 파란 추가 버튼이 없다').toBeNull();

    await page.touchscreen.tap(...M.gearFamily);
    await page.waitForTimeout(500);
    const picked = await shot(page, 'mobile-02b-gear-selected');
    expect(countHue(picked, { x: 160, y: 218, w: 140, h: 80 }, 'green'), '4인 가족 카드가 초록으로 선택된다').toBeGreaterThan(1500);
    expect(countHue(picked, { x: 290, y: 10, w: 95, h: 36 }, 'blue'), '앱바 오른쪽 "16개 선택" 칩').toBeGreaterThan(200);
    const addBtn = bboxOfHue(picked, { x: 0, y: 780, w: 390, h: 64 }, 'blue');
    expect(addBtn, '하단 파란 "추가 (16개)" 버튼').not.toBeNull();
    expect(addBtn!.w, '추가 버튼이 (선택 해제 옆) 전체 폭').toBeGreaterThan(240);
    expect(addBtn!.y + addBtn!.h, '추가 버튼 아래가 화면 안').toBeLessThan(844 - 4);

    const t0 = Date.now();
    await page.touchscreen.tap(...M.gearAdd);
    const res = await waitForSnack(page, 12000, RM.snack);
    timings.family = Date.now() - t0;
    await shot(page, 'mobile-02c-snack');
    expect(res.kind, '폰에서도 4인 가족 세트는 전부 들어간다').toBe('green');
    expect(timings.family).toBeLessThan(8000);
    await waitForSnackGone(page, 9000, RM.snack);
    const idle = await waitForStable(page);
    await shot(page, 'mobile-03-idle');

    // ── 시트가 45% 로 올라왔고 트렁크는 잘리지 않는다 ──
    const top = sheetTopByHandle(idle, 195);
    expect(top, '시트 위 경계를 찾는다').toBeGreaterThan(0);
    expect(emptyTop - top, `첫 짐이 들어오면 시트가 올라온다 (${emptyTop} → ${top})`).toBeGreaterThan(100);
    expect(Math.abs(top - SHEET_LOADED_TOP), `시트 45% (top≈${SHEET_LOADED_TOP}, 실제 ${top})`).toBeLessThan(6);
    const lamps = lampBbox(idle, { x: 0, y: 56, w: 390, h: top - 56 });
    expect(lamps, '후미등(범퍼 옆 빨간 등)이 시트 위에 보인다').not.toBeNull();
    expect(lamps!.y + lamps!.h, '후미등 아래쪽이 시트·알약보다 위 = 트렁크가 가려지지 않았다').toBeLessThan(top - 60);
    expect(lamps!.x, '왼쪽 후미등').toBeLessThan(40);
    expect(lamps!.x + lamps!.w, '오른쪽 후미등').toBeGreaterThan(350);
    expect(textHue(idle, phonePillRegion(top)), '테일게이트 알약 초록').toBe('green');
    expect(countHue(idle, RM.chip, 'green'), '적재율 칩의 초록 % 숫자').toBeGreaterThan(20);
    expect(textHue(idle, statusRegion(top)), '시트 상태 행 초록').toBe('green');
    expect(luminance(idle.avgColor(statsRegion(top))), '통계 줄 글자가 있다').toBeGreaterThan(luminance([0x25, 0x25, 0x25]) + 4);
  });

  test('캔버스가 시트를 따라간다: 85% 로 올리면 트렁크가 작아져도 보이고 칩·알약은 빠진다, 12% 로 내리면 크게 + 알약', async ({ page }) => {
    const { idle, top: top0 } = await loadFamilyIdle(page);
    const lamps0 = lampBbox(idle, { x: 0, y: 56, w: 390, h: top0 - 56 })!;
    expect(lamps0).not.toBeNull();

    // ── 위로: 85% (top ≈ 174) — 최대치를 넘겨 끌면 남은 거리만큼 시트 안 목록이 스크롤돼 손잡이가
    // 화면 밖으로 나가므로, 조금 못 미치게 끌고 스냅에 맡긴다 ──
    await touchSwipe(page, 195, top0 + 10, 195, 205, 20);
    const top1 = await waitForSheetTop(page, 195, (t) => t > 0 && t < 200);
    const up = await waitForStable(page);
    await shot(page, 'mobile-05-sheet-up');
    expect(top1, `위로 끌면 시트가 85% 까지 올라온다 (top=${top1})`).toBeLessThan(200);
    expect(top1).toBeGreaterThan(100);
    const canvasUp: Region = { x: 0, y: 56, w: 390, h: top1 - 56 };
    const lamps1 = lampBbox(up, canvasUp);
    expect(lamps1, '낮은 캔버스에도 트렁크(후미등)가 그려진다 — 가려지는 게 아니라 줄어든다').not.toBeNull();
    expect(lamps1!.y + lamps1!.h, '후미등이 시트 위에서 끝난다').toBeLessThanOrEqual(top1);
    expect(lamps1!.h, `트렁크가 작아진다 (후미등 높이 ${lamps0.h.toFixed(0)} → ${lamps1!.h.toFixed(0)})`).toBeLessThan(lamps0.h * 0.7);
    // 캔버스 < 160px: 캡션·알약·칩을 그리지 않는다 (트렁크를 덮으니까)
    expect(up.countColorNear(phonePillRegion(top1), C.green, 20), '알약(초록 글자) 없음').toBeLessThan(6 * 4);
    expect(up.countColorNear(RM.chip, C.green, 20), '적재율 칩(초록 %) 없음').toBeLessThan(6 * 4);
    // 시트 위쪽 히어로 줄이 그대로 따라온다
    expect(bboxOfHue(up, { x: 130, y: top1 + 10, w: 260, h: 70 }, 'blue')?.w ?? 0, '자동 배치 버튼이 시트 맨 위').toBeGreaterThan(200);

    // ── 아래로: 12% (top ≈ 743) ──
    await touchSwipe(page, 195, top1 + 10, 195, 830, 20);
    const top2 = await waitForSheetTop(page, 195, (t) => t > 600);
    const down = await waitForStable(page);
    await shot(page, 'mobile-06-sheet-down');
    expect(top2, `아래로 끌면 시트가 내려간다 (top=${top2}, 12%≈743)`).toBeGreaterThan(700);
    const lamps2 = lampBbox(down, { x: 0, y: 56, w: 390, h: top2 - 56 });
    expect(lamps2, '트렁크가 크게 보인다').not.toBeNull();
    // 폭 390 에서는 트렁크가 이미 폭에 맞춰져 있어 캔버스가 높아져도 조금만 커진다 (85% 때보다는 확실히 크다)
    expect(lamps2!.h, `트렁크가 줄지 않는다 (후미등 높이 45%: ${lamps0.h.toFixed(0)}, 12%: ${lamps2!.h.toFixed(0)})`).toBeGreaterThanOrEqual(lamps0.h * 0.97);
    expect(lamps2!.h).toBeGreaterThan(lamps1!.h * 1.5);
    console.log(`[info] 후미등 높이 45%/85%/12%: ${lamps0.h.toFixed(0)}/${lamps1!.h.toFixed(0)}/${lamps2!.h.toFixed(0)}px (시트 top ${top0}/${top1}/${top2})`);
    expect(textHue(down, phonePillRegion(top2)), '알약이 다시 보인다 · 초록').toBe('green');
    expect(countHue(down, RM.chip, 'green'), '적재율 칩이 다시 보인다').toBeGreaterThan(20);
    // 12% 시트에도 히어로 줄(들어갈까? · 자동 배치)은 보인다
    expect(bboxOfHue(down, { x: 130, y: top2 + 10, w: 260, h: 70 }, 'blue')?.w ?? 0, '자동 배치 버튼').toBeGreaterThan(200);
  });

  test('박스 탭 → 선택 도구 띠 → 삭제(박스 15개) → 시트 도구 줄의 실행 취소로 복원 → 다시 탭 → 회전(캔버스 변화)', async ({ page }) => {
    const { idle, top } = await loadFamilyIdle(page);
    const blue0 = countHue(idle, RM.canvasLoaded, 'blue');

    const sel = await selectBoxOnCanvas(page, top);
    await shot(page, 'mobile-07-select-toolbar');
    // 띠는 캡션 위(캔버스 아래 60px) 또는, 선택한 짐이 거기까지 내려와 있으면 캔버스 위쪽(칩 아래)
    const atBottom = sel.bar.y > top - 116 && sel.bar.y + sel.bar.h < top - 56;
    const atTop = sel.bar.y >= 100 && sel.bar.y <= 112;
    expect(atBottom || atTop, `도구 띠 자리 y=${sel.bar.y} (캡션 위 ≈${top - 108} 또는 캔버스 위 ≈104)`).toBe(true);
    expect(countHue(sel.shot, RM.canvasLoaded, 'blue') - blue0, '선택 외곽선(파랑)').toBeGreaterThan(150);
    expect(textHue(sel.shot, phonePillRegion(top)), '탭은 박스를 옮기지 않는다').toBe('green');
    // 띠 안의 빨간 삭제 아이콘
    expect(countHue(sel.shot, { x: sel.tb.delete[0] - 20, y: sel.bar.y, w: 40, h: sel.bar.h }, 'red'), '삭제 아이콘(빨강)').toBeGreaterThan(30);

    // 삭제 (텍스트 한 글자 차이는 pixelmatch 의 안티앨리어싱 무시에 걸리므로 원시 채널 차이로 본다)
    const before = sel.shot;
    await page.touchscreen.tap(...sel.tb.delete);
    await page.waitForTimeout(600);
    const deleted = await waitForStable(page);
    await shot(page, 'mobile-09-deleted');
    expect(bboxOfDiff(before, deleted, statsRegion(top)), '통계 줄 "박스 16개 · 부피 62%" → "15개 · 52%"').not.toBeNull();
    expect(toolbarWidth(deleted, top, 390), '삭제하면 도구 띠가 사라진다').toBe(0);
    expect(diffRatio(before, deleted, RM.canvasCore), '캔버스에서 짐이 빠진다').toBeGreaterThan(0.005);

    // 실행 취소 (시트 도구 줄)
    await page.touchscreen.tap(...M.undo);
    await page.waitForTimeout(600);
    const undone = await waitForStable(page);
    await shot(page, 'mobile-10-undone');
    expect(bboxOfDiff(before, undone, statsRegion(top)), '실행 취소 → 통계 줄이 "박스 16개" 로 돌아온다').toBeNull();
    expect(diffRatio(deleted, undone, RM.canvasCore), '짐이 캔버스에 돌아온다').toBeGreaterThan(0.005);
    expect(textHue(undone, phonePillRegion(top)), '복원 뒤에도 테일게이트 OK').toBe('green');

    // 다시 탭 → 회전: 캔버스가 바뀌고 띠는 남는다 (제자리 회전이라 판정은 바뀔 수 있다 — 여기서는 보지 않는다)
    const sel2 = await selectBoxOnCanvas(page, top);
    await page.touchscreen.tap(...sel2.tb.rotate);
    await page.waitForTimeout(500);
    const rotated = await waitForStable(page);
    await shot(page, 'mobile-08-rotated');
    expect(diffRatio(sel2.shot, rotated, RM.canvasCore), '회전하면 캔버스가 바뀐다').toBeGreaterThan(0.005);
    expect(toolbarWidth(rotated, top, 390), '회전 뒤에도 도구 띠가 남아 있다').toBeGreaterThan(360);
    console.log(`[info] 회전 뒤 테일게이트 알약: ${textHue(rotated, phonePillRegion(top))}`);
  });

  test('들어갈까? → 아래 시트(딤 · 초록 점 · 전체 폭 배치 저장/순서 가이드 · ✕) → ✕ 닫기 · 자동 배치 → 전략 3개 + 전체 폭 이 배치 적용', async ({ page }) => {
    const { idle } = await loadFamilyIdle(page);

    // ── 들어갈까? ──
    const t0 = Date.now();
    await page.touchscreen.tap(...M.quickCheck);
    expect(await waitForDim(page, idle, true, 8000, RM.title), '판정 시트가 뜨며 위쪽(앱바)이 어두워진다').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    timings.quickCheck = Date.now() - t0;
    const dlg = await shot(page, 'mobile-04-quickcheck');
    const titleY = resultTitleY(dlg, { x: 12, y: 150, w: 24, h: 500 });
    expect(titleY, '제목 줄이 화면 위쪽 절반(시트 top ≈ 280)').toBeGreaterThan(220);
    expect(titleY).toBeLessThan(480);
    expect(firstHueRun(dlg, { x: 12, y: 150, w: 24, h: 500 }, 'green', 4), '판정 점 초록').not.toBeNull();
    // 버튼: 파란 '배치 저장' 이 맨 아래 전체 폭, 그 위 초록 외곽선 '순서 가이드', 8px 간격
    const blueBtn = bboxOfHue(dlg, { x: 0, y: 700, w: 390, h: 144 }, 'blue');
    expect(blueBtn, '"배치 저장" 버튼').not.toBeNull();
    expect(blueBtn!.w, '전체 폭(좌우 16px 여백)').toBeGreaterThan(340);
    expect(blueBtn!.h, '48px 버튼').toBeGreaterThanOrEqual(44);
    expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThan(844 - 8);
    const greenBtn = bboxOfHue(dlg, { x: 0, y: 700, w: 390, h: blueBtn!.y - 700 }, 'green');
    expect(greenBtn, '"순서 가이드" 외곽선 버튼').not.toBeNull();
    expect(greenBtn!.w, '보조 버튼도 전체 폭').toBeGreaterThan(340);
    const gap = blueBtn!.y - (greenBtn!.y + greenBtn!.h);
    expect(gap, `버튼 세로 간격 ${gap.toFixed(1)}px (약 8px)`).toBeGreaterThanOrEqual(6);
    expect(gap).toBeLessThanOrEqual(12);
    // ✕ (제목 줄 오른쪽): 밝은 아이콘
    expect(dlg.countColorNear({ x: 340, y: titleY - 12, w: 24, h: 24 }, [255, 255, 255], 130) / 4, '✕ 아이콘').toBeGreaterThan(15);
    await page.touchscreen.tap(352, titleY);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '✕ 로 닫힘').toBeGreaterThanOrEqual(0);

    // ── 자동 배치 ──
    const t1 = Date.now();
    await page.touchscreen.tap(...M.autoLayout);
    expect(await waitForDim(page, idle, true, 10000, RM.title), '자동 배치 시트').toBeGreaterThanOrEqual(0);
    expect(await waitForColor(page, { x: 16, y: 784, w: 358, h: 48 }, C.blue, { minPixels: 4000, timeout: 10000 }), '"이 배치 적용" 파란 버튼').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(400);
    timings.autoLayoutSheet = Date.now() - t1;
    const auto = await shot(page, 'mobile-11-autolayout');
    const apply = bboxOfHue(auto, { x: 0, y: 770, w: 390, h: 74 }, 'blue');
    expect(apply!.w, '"이 배치 적용" 전체 폭').toBeGreaterThan(340);
    // 전략 카드 3장: 각 카드의 초록 "16개 모두" 글자 (x 250..310 열에서 세로 run 3개)
    const cards = countRuns(auto, { x: 250, y: 480, w: 60, h: 290 }, 'green', 10);
    expect(cards, '전략 카드 3장').toBe(3);
    // 선택된 카드의 파란 라디오는 첫 카드에
    // 열 x 28..52 에는 선택 카드의 2px 파란 테두리·4px 게이지도 걸리므로 12px 이상인 run(라디오 20px)만 본다
    const radioOf = (s: Shot) => hueRuns(s, { x: 28, y: 500, w: 24, h: 280 }, 'blue', 3).find((r) => r.y1 - r.y0 >= 12) ?? null;
    const radio0 = radioOf(auto);
    expect(radio0, '선택 라디오').not.toBeNull();
    // 2번째 카드를 탭하면 선택이 내려간다
    await page.touchscreen.tap(39, radio0!.y1 + 60);
    await page.waitForTimeout(400);
    const auto2 = await shot(page, 'mobile-11b-autolayout-card2');
    const radio1 = radioOf(auto2);
    expect(radio1, '2번째 카드 선택 라디오').not.toBeNull();
    expect(radio1!.y0 - radio0!.y0, '라디오가 카드 한 칸(≈78px) 내려간다').toBeGreaterThan(50);
    // ✕ 는 제목 줄(초록 ms 칩과 같은 줄) 오른쪽
    const msRow = firstHueRun(auto2, { x: 270, y: 400, w: 40, h: 150 }, 'green', 2);
    expect(msRow, '계산 시간 칩').not.toBeNull();
    await page.touchscreen.tap(352, (msRow!.y0 + msRow!.y1) / 2);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '✕ 로 자동 배치 시트 닫힘').toBeGreaterThanOrEqual(0);
  });

  test('⋯ 메뉴 → 배치 저장 → 저장 다이얼로그 → 취소 · ? → 조작법 다이얼로그 → 닫기', async ({ page }) => {
    const { idle } = await loadFamilyIdle(page);

    await page.touchscreen.tap(...M.more);
    await page.waitForTimeout(600);
    const menu = await shot(page, 'mobile-12-more-menu');
    // 메뉴(#333333 배경, 항목 '배치 저장'·'불러오기'·…)가 도구 줄 오른쪽 아래에 뜬다
    const menuGap: Region = { x: 270, y: 618, w: 30, h: 14 }; // 첫·둘째 항목 사이 (메뉴 배경만)
    expect(luminance(menu.avgColor(menuGap)) - luminance(idle.avgColor(menuGap)), '메뉴 배경(#333333)이 시트(#252525) 위에').toBeGreaterThan(8);
    expect(menu.countColorNear({ x: 300, y: 590, w: 70, h: 22 }, [255, 255, 255], 60) / 4, '"배치 저장" 항목 글자').toBeGreaterThan(40);
    expect(diffRatio(idle, menu, { x: 260, y: 560, w: 130, h: 220 }), '⋯ 메뉴가 열린다').toBeGreaterThan(0.02);
    await page.touchscreen.tap(...M.menuSave);
    expect(await waitForDim(page, idle, true, 5000, RM.title), '배치 저장 다이얼로그').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(500);
    const save = await shot(page, 'mobile-13-save-dialog');
    // 파란 것은 입력란 밑줄(2px)과 '저장' 버튼(≈32px) — 높이 24px 이상인 run 이 버튼
    const btnRun = hueRuns(save, { x: 120, y: 250, w: 270, h: 400 }, 'blue', 20).find((r) => r.y1 - r.y0 >= 24);
    expect(btnRun, '파란 "저장" 버튼').toBeTruthy();
    const saveBtn = bboxOfHue(save, { x: 120, y: btnRun!.y0, w: 270, h: btnRun!.y1 - btnRun!.y0 }, 'blue');
    expect(saveBtn, '파란 "저장" 버튼').not.toBeNull();
    expect(saveBtn!.x + saveBtn!.w, '저장 버튼이 화면 안').toBeLessThan(390);
    // 다이얼로그 제목 '배치 저장' (흰 글자, 저장 버튼 위쪽 어딘가)
    expect(save.countColorNear({ x: 60, y: saveBtn!.y - 340, w: 120, h: 200 }, [255, 255, 255], 60) / 4, '제목 글자').toBeGreaterThan(60);
    // 폰에서는 취소 · 저장 두 버튼이 한 줄 (파일로 내보내기는 입력란 아래 링크) — 취소는 저장 왼쪽
    await page.touchscreen.tap(saveBtn!.x - 45, saveBtn!.y + saveBtn!.h / 2);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '취소로 닫힘').toBeGreaterThanOrEqual(0);

    // ── ? → 조작법 ──
    await page.touchscreen.tap(...M.help);
    expect(await waitForDim(page, idle, true, 5000, RM.title), '조작법 다이얼로그').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(500);
    const help = await shot(page, 'mobile-14-help');
    // 제목 '조작법' (흰 글자, 다이얼로그 왼쪽 위) — 키보드 단축키 표(넓은 2열)가 아니다
    expect(help.countColorNear({ x: 60, y: 270, w: 90, h: 50 }, [255, 255, 255], 60) / 4, '"조작법" 제목').toBeGreaterThan(40);
    // '확인' 텍스트 버튼은 primary(파랑) 글자, 다이얼로그 오른쪽 아래
    const ok = bboxOfHue(help, { x: 200, y: 330, w: 170, h: 330 }, 'blue');
    expect(ok, '"확인" 버튼').not.toBeNull();
    await page.touchscreen.tap(ok!.x + ok!.w / 2, ok!.y + ok!.h / 2);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '확인으로 닫힘').toBeGreaterThanOrEqual(0);
  });

  test('앱바의 차종/2열 컨트롤 · 2열 최전방 적용 → 다시 배치 초록 · 한 손가락 오빗은 배치를 건드리지 않는다', async ({ page }) => {
    const { idle, top } = await loadFamilyIdle(page);
    const bright = (s: Shot, r: Region) => s.countColorNear(r, [255, 255, 255], 60) / (s.scale * s.scale);
    expect(bright(idle, RM.appBarPreset), '차종 버튼 글자').toBeGreaterThan(80);
    expect(bright(idle, RM.appBarSeat), '2열 버튼 글자').toBeGreaterThan(80);

    await page.touchscreen.tap(...M.seat);
    await page.waitForTimeout(700);
    const menu = await shot(page, 'mobile-15-seat-menu');
    expect(diffRatio(idle, menu, { x: 140, y: 10, w: 200, h: 160 }), '2열 메뉴가 열린다').toBeGreaterThan(0.1);
    await page.touchscreen.tap(...M.seatFront);
    const snack = await waitForSnack(page, 8000, RM.snack);
    expect(snack.kind, '슬라이드 적용 후 다시 배치 → 초록').toBe('green');
    await waitForSnackGone(page, 9000, RM.snack);
    const front = await waitForStable(page);
    await shot(page, 'mobile-16-seat-front');
    expect(diffRatio(idle, front, RM.appBarSeat), '2열 라벨이 "+27cm" 로').toBeGreaterThan(0.02);
    expect(diffRatio(idle, front, RM.canvasLoaded), '트렁크가 깊어진다').toBeGreaterThan(0.05);
    expect(bright(front, RM.appBarPreset), '좁은 화면에서도 차종 버튼이 남아 있다').toBeGreaterThan(80);
    expect(textHue(front, phonePillRegion(top)), '테일게이트 OK').toBe('green');

    // 빈 곳에서 시작하는 한 손가락 드래그 = 오빗
    await touchSwipe(page, 60, 130, 220, 190, 16);
    const orbited = await waitForStable(page);
    await shot(page, 'mobile-17-orbit');
    expect(diffRatio(front, orbited, RM.canvasLoaded), '한 손가락 드래그로 카메라가 돈다').toBeGreaterThan(0.08);
    expect(textHue(orbited, phonePillRegion(top)), '오빗은 배치를 건드리지 않는다').toBe('green');
    expect(toolbarWidth(orbited, top, 390), '오빗은 선택 띠를 띄우지 않는다').toBe(0);
  });
});

/** 장비 페이지가 열리면 메인 앱바(차종·2열 버튼)가 사라진다 */
function isDimmedAppBarGone(before: Shot, after: Shot): boolean {
  const white = (s: Shot, r: Region) => s.countColorNear(r, [255, 255, 255], 60) / (s.scale * s.scale);
  // 페이지 제목 '장비 선택' 의 마지막 글자가 x≈150 까지 오므로 그 오른쪽(2열 버튼 자리)만 본다
  return white(before, RM.appBarSeat) > 80 && white(after, { x: 156, y: 8, w: 110, h: 40 }) < 5 && isGearPage(after);
}

// ──── 작은 폰 360×640 ────

test.describe('작은 폰 360×640', () => {
  const vp = { width: 360, height: 640 };
  test.use({ viewport: vp, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
  const snackR: Region = { x: 90, y: 610, w: 108, h: 18 };
  const S = {
    cta: [180, 566], family: [230, 268], add: [270, 610],
    quick: [71, 425], box: [134, 225],
  } as const;
  const LOADED_TOP = 377; // 640 × 0.55

  test('CTA → 장비 페이지 → 4인 가족 → 초록 → 시트 45% · 알약 초록 → 박스 탭 → 도구 띠 · 선택 해제 → 들어갈까? 시트가 화면 안', async ({ page }) => {
    await waitForApp(page);
    await page.touchscreen.tap(180, 200);
    await page.waitForTimeout(600);
    const empty = await shot(page, 'mobile-s360-01-empty');
    const emptyTop = sheetTopByHandle(empty, 180);
    expect(Math.abs(emptyTop - 420), `빈 시트 220px (top=${emptyTop})`).toBeLessThan(6);
    const cta = bboxOfHue(empty, { x: 0, y: emptyTop, w: 360, h: 640 - emptyTop }, 'blue');
    expect(cta, 'CTA').not.toBeNull();
    expect(cta!.y <= S.cta[1] && cta!.y + cta!.h >= S.cta[1], `CTA ${cta!.y}..${cta!.y + cta!.h} ∋ ${S.cta[1]}`).toBe(true);

    await page.touchscreen.tap(...S.cta);
    expect(await waitForGearPage(page), 'CTA → 장비 페이지').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(400);
    await shot(page, 'mobile-s360-02-gear-page');
    await page.touchscreen.tap(...S.family);
    await page.waitForTimeout(500);
    const picked = await shot(page);
    const addBtn = bboxOfHue(picked, { x: 0, y: 576, w: 360, h: 64 }, 'blue');
    expect(addBtn, '"추가 (16개)" 버튼').not.toBeNull();
    expect(addBtn!.y + addBtn!.h, '버튼 아래가 화면 안').toBeLessThan(640 - 4);
    const t0 = Date.now();
    await page.touchscreen.tap(...S.add);
    const res = await waitForSnack(page, 12000, snackR);
    timings.s360 = Date.now() - t0;
    await shot(page, 'mobile-s360-02b-snack');
    expect(res.kind).toBe('green');
    expect(timings.s360).toBeLessThan(8000);
    await waitForSnackGone(page, 9000, snackR);
    const idle = await waitForStable(page);
    await shot(page, 'mobile-s360-03-idle');
    const top = sheetTopByHandle(idle, 180);
    expect(Math.abs(top - LOADED_TOP), `시트 45% (top=${top})`).toBeLessThan(6);
    const lamps = lampBbox(idle, { x: 0, y: 56, w: 360, h: top - 56 });
    expect(lamps, '후미등이 보인다').not.toBeNull();
    expect(lamps!.y + lamps!.h, '트렁크가 시트에 가려지지 않는다').toBeLessThan(top - 56);
    expect(textHue(idle, phonePillRegion(top)), '테일게이트 알약 초록').toBe('green');

    // 선택 도구 띠
    await page.touchscreen.tap(...S.box);
    await page.waitForTimeout(500);
    const sel = await shot(page, 'mobile-s360-04-select');
    const tb = findToolbar(sel, top, 360);
    expect(tb, '선택 도구 띠').not.toBeNull();
    expect(tb!.bar.w, '띠가 전체 폭').toBeGreaterThan(330);
    await page.touchscreen.tap(...tb!.deselect);
    await page.waitForTimeout(400);
    expect(toolbarWidth(await shot(page), top, 360), '✕ 로 선택 해제').toBe(0);

    // 판정 시트
    await page.touchscreen.tap(...S.quick);
    expect(await waitForDim(page, idle, true, 8000, RM.title), '판정 시트').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    const dlg = await shot(page, 'mobile-s360-05-quickcheck');
    const blueBtn = bboxOfHue(dlg, { x: 0, y: 540, w: 360, h: 100 }, 'blue');
    expect(blueBtn, '"배치 저장" 버튼').not.toBeNull();
    expect(blueBtn!.w).toBeGreaterThan(310);
    expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThanOrEqual(640 - 4);
    const greenBtn = bboxOfHue(dlg, { x: 0, y: 480, w: 360, h: blueBtn!.y - 480 }, 'green');
    expect(greenBtn, '"순서 가이드" 버튼').not.toBeNull();
    expect(greenBtn!.w).toBeGreaterThan(310);
    const titleY = resultTitleY(dlg, { x: 12, y: 60, w: 24, h: 400 });
    await page.touchscreen.tap(322, titleY);
    expect(await waitForDim(page, idle, false, 4000, RM.title), '✕ 로 닫힘').toBeGreaterThanOrEqual(0);
  });
});

// ──── 가로 844×390: 시트 대신 오른쪽 300px 압축 패널 (캔버스 0..544 × 56..390) ────

test.describe('가로 844×390', () => {
  const vp = { width: 844, height: 390 };
  test.use({ viewport: vp, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });
  const snackR: Region = { x: 211, y: 360, w: 253, h: 18 };
  const L = {
    cta: [694, 190], family: [230, 268], add: [500, 360],
    quick: [591, 316], auto: [715, 316], firstTileDelete: [805, 127],
    box: [210, 234],
    dimR: { x: 16, y: 14, w: 100, h: 28 } as Region,
    pill: phonePillRegion(390),
    listCol: { x: 793, y: 104, w: 22, h: 190 } as Region, // 삭제 아이콘 열
    canvas: { x: 0, y: 110, w: 544, h: 170 } as Region,
  } as const;

  async function loadLandscape(page: Page) {
    await waitForApp(page);
    await page.touchscreen.tap(250, 150);
    await page.waitForTimeout(600);
    const empty = await shot(page, 'mobile-landscape-01-empty');
    await page.touchscreen.tap(...L.cta);
    expect(await waitForGearPage(page), 'CTA → 전체 화면 장비 페이지 (가로)').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(400);
    const gear = await shot(page, 'mobile-landscape-02-gear-page');
    // 가로(높이 390)에서도 하단 '추가' 바가 화면 안에 있고 세트 카드가 보인다
    expect(findRowOfColor(gear, { x: 0, y: 320, w: 844, h: 30 }, [0x44, 0x44, 0x44], 10, 0.9), '하단 바 구분선').toBeGreaterThan(0);
    await page.touchscreen.tap(...L.family);
    await page.waitForTimeout(500);
    const picked = await shot(page);
    const addBtn = bboxOfHue(picked, { x: 0, y: 330, w: 844, h: 60 }, 'blue');
    expect(addBtn, '"추가 (16개)"').not.toBeNull();
    expect(addBtn!.w, '전체 폭').toBeGreaterThan(600);
    const t0 = Date.now();
    await page.touchscreen.tap(...L.add);
    const res = await waitForSnack(page, 12000, snackR);
    timings.landscape = Date.now() - t0;
    await shot(page, 'mobile-landscape-02b-snack');
    expect(res.kind).toBe('green');
    await waitForSnackGone(page, 9000, snackR);
    const idle = await waitForStable(page);
    await shot(page, 'mobile-landscape-03-idle');
    expect(textHue(idle, L.pill), '테일게이트 알약 초록').toBe('green');
    return { empty, idle };
  }

  test('CTA → 장비 페이지 → 4인 가족 → 초록 · 목록 3행 이상 · 첫 타일 삭제 · 들어갈까? 시트가 화면 안', async ({ page }) => {
    const { idle } = await loadLandscape(page);
    // 목록(y 104..294)의 빨간 삭제 아이콘 수 = 보이는 타일 수 (45px 간격)
    const tiles = countRuns(idle, L.listCol, 'red');
    expect(tiles, '가로 화면에서도 짐 목록이 3행 이상 보여야 한다').toBeGreaterThanOrEqual(3);
    await page.touchscreen.tap(...L.firstTileDelete);
    await page.waitForTimeout(800);
    const after = await waitForStable(page);
    await shot(page, 'mobile-landscape-04-deleted');
    expect(countRuns(after, L.listCol, 'red'), '삭제 뒤에도 목록이 3행 이상').toBeGreaterThanOrEqual(3);
    expect(diffRatio(idle, after, L.canvas), '캔버스에서 짐이 하나 빠졌다').toBeGreaterThan(0.002);
    expect(textHue(after, L.pill), '테일게이트 알약 초록').toBe('green');

    await page.touchscreen.tap(...L.quick);
    expect(await waitForDim(page, after, true, 8000, L.dimR), '판정 시트').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    const dlg = await shot(page, 'mobile-landscape-05-quickcheck');
    const blueBtn = bboxOfHue(dlg, { x: 0, y: 320, w: 844, h: 70 }, 'blue');
    expect(blueBtn, '"배치 저장" 버튼').not.toBeNull();
    expect(blueBtn!.w, '시트 폭(≈608)에 맞춘 전체 폭').toBeGreaterThan(500);
    expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThanOrEqual(390 - 4);
    const greenBtn = bboxOfHue(dlg, { x: 100, y: 260, w: 644, h: blueBtn!.y - 260 }, 'green');
    expect(greenBtn, '"순서 가이드" 버튼').not.toBeNull();
    expect(greenBtn!.w).toBeGreaterThan(500);
    const titleY = resultTitleY(dlg, { x: 112, y: 40, w: 28, h: 200 }); // 시트(x 102..741) 안 점
    await page.touchscreen.tap(704, titleY);
    expect(await waitForDim(page, after, false, 4000, L.dimR), '✕ 로 닫힘').toBeGreaterThanOrEqual(0);
  });

  test('가로에서도 캔버스 짐 탭 → 선택 도구 띠(캔버스 폭) → 회전 → ✕ 선택 해제', async ({ page }) => {
    const { idle } = await loadLandscape(page);
    await page.touchscreen.tap(...L.box);
    await page.waitForTimeout(500);
    const sel = await shot(page, 'mobile-landscape-06-select');
    const tb = findToolbar(sel, 390, 544);
    expect(tb, '선택 도구 띠').not.toBeNull();
    const bar = tb!.bar;
    expect(bar.w, '띠가 캔버스 폭(8..536)').toBeGreaterThan(500);
    expect(bar.x + bar.w, '띠가 옆 패널을 침범하지 않는다').toBeLessThanOrEqual(544);
    await page.touchscreen.tap(...tb!.rotate);
    await page.waitForTimeout(500);
    const rotated = await waitForStable(page);
    await shot(page, 'mobile-landscape-07-rotated');
    expect(diffRatio(sel, rotated, L.canvas), '회전하면 캔버스가 바뀐다').toBeGreaterThan(0.003);
    await page.touchscreen.tap(...tb!.deselect);
    await page.waitForTimeout(400);
    const off = await shot(page, 'mobile-landscape-08-deselected');
    expect(toolbarWidth(off, 390, 544), '✕ 로 띠가 사라진다').toBe(0);
    // 제자리 회전이라 60×40 아이스박스가 40×60 이 되며 테일게이트에 걸릴 수 있다 — 알약은 초록이든 빨강이든 남는다
    const pill = textHue(off, L.pill);
    expect(pill, '테일게이트 알약').not.toBeNull();
    console.log(`[info] 가로 회전 뒤 테일게이트 알약: ${pill}`);
  });
});

// ──── 태블릿 820×1180: 옆 280px 패널 + 기존 다이얼로그 UI 그대로 ────

test.describe('태블릿 820×1180', () => {
  const vp = { width: 820, height: 1180 };
  test.use({ viewport: vp, isMobile: true, hasTouch: true, deviceScaleFactor: 2 });

  test('온보딩 → 4인 가족 추가 → 초록 판정 → 들어갈까? 다이얼로그가 화면 안', async ({ page }) => {
    const c = { cta: [680, 709], family: [400, 546], add: [601, 862], pill: { x: 4, y: 1120, w: 140, h: 34 } } as const;
    const snackR: Region = { x: vp.width * 0.25, y: vp.height - 30, w: vp.width * 0.3, h: 18 };
    const dimR: Region = { x: 16, y: 14, w: 100, h: 28 };
    await waitForApp(page);
    await page.touchscreen.tap(vp.width * 0.3, vp.height * 0.4);
    await page.waitForTimeout(600);
    const empty = await shot(page, 'mobile-tablet-01-empty');

    await page.touchscreen.tap(...c.cta);
    expect(await waitForDim(page, empty, true, 5000, dimR), 'CTA → 장비 다이얼로그(태블릿은 다이얼로그)').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(500);
    await page.touchscreen.tap(...c.family);
    await page.waitForTimeout(500);
    const t0 = Date.now();
    await page.touchscreen.tap(...c.add);
    const res = await waitForSnack(page, 12000, snackR);
    timings.tablet = Date.now() - t0;
    await shot(page, 'mobile-tablet-02-snack');
    expect(res.kind).toBe('green');
    expect(timings.tablet).toBeLessThan(8000);
    await waitForSnackGone(page, 9000, snackR);
    const idle = await shot(page, 'mobile-tablet-03-idle');
    expect(textHue(idle, c.pill), '테일게이트 알약 초록').toBe('green');

    // 들어갈까? 버튼은 초록 테두리 — 위치를 찾아서 누른다
    const g = bboxOfHue(idle, { x: vp.width - 280, y: 200, w: 110, h: vp.height - 300 }, 'green');
    expect(g, '"들어갈까?" 버튼').not.toBeNull();
    await page.touchscreen.tap(g!.x + g!.w / 2, g!.y + g!.h / 2);
    expect(await waitForDim(page, idle, true, 8000, dimR), '판정 다이얼로그').toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(600);
    const dlg = await shot(page, 'mobile-tablet-04-quickcheck');
    const blueBtn = bboxOfHue(dlg, { x: 0, y: vp.height * 0.35, w: vp.width, h: vp.height * 0.65 }, 'blue');
    expect(blueBtn, '"배치 저장" 버튼이 보여야 한다').not.toBeNull();
    expect(blueBtn!.y + blueBtn!.h, '버튼 아래쪽이 화면 안').toBeLessThanOrEqual(vp.height - 4);
    expect(blueBtn!.h, '버튼이 잘리지 않았다').toBeGreaterThan(28);
  });
});
