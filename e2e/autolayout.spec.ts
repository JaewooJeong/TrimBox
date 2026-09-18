import { Page } from '@playwright/test';
import {
  test, expect, shot, startDesktop, addBundle, waitForSnackGone, waitForSnack, waitForDim, waitForStable,
  diffRatio, isDimmed, countHue, verdictDotHue, bboxOfHue, center, D, RD, DESKTOP,
} from './helpers';

/** 자동 배치 대안 다이얼로그(전략 3종)와 적재 순서 가이드(스텝 뷰) */

test.use({ viewport: DESKTOP });

const CARDS = [
  { x: 440, y: 371, w: 400, h: 72 }, // 균형 배치
  { x: 440, y: 450, w: 400, h: 72 }, // 최대 적재
  { x: 440, y: 528, w: 400, h: 72 }, // 접근 우선
];
const APPLY: [number, number] = [779, 647];
const CANCEL: [number, number] = [683, 647];
const STEP_AREA = { x: 200, y: 870, w: 560, h: 80 };

/**
 * 스텝 컨트롤은 라벨 길이에 따라 폭이 달라져 버튼이 단계마다 움직인다.
 * 그래서 초록 테두리 상자를 찾아 그 안의 상대 위치로 누른다.
 */
async function stepButtons(page: Page) {
  const s = await shot(page);
  const box = bboxOfHue(s, STEP_AREA, 'green');
  expect(box, '스텝 컨트롤(초록 테두리)이 보여야 한다').not.toBeNull();
  const y = box!.y + box!.h / 2;
  return {
    box: box!,
    close: [box!.x + 29, y] as [number, number],
    prev: [box!.x + 63, y] as [number, number],
    next: [box!.x + box!.w - 32, y] as [number, number],
  };
}

test('자동 배치: 전략 카드 3개 · 선택 이동 · 취소는 그대로 → 적용하면 판정·초록 SnackBar·순서 배지 → 스텝 뷰 다음/이전/닫기', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'family')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const idle = await shot(page);

  // ── 대안 다이얼로그 ──
  await page.mouse.click(...D.autoLayoutWithGuide);
  const ms = await waitForDim(page, idle, true, 12000);
  console.log(`[timing] desktop 자동 배치 대안 계산(16개): ${ms}ms`);
  expect(ms, '대안 다이얼로그가 12초 안에 떠야 한다').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(500);
  const dlg = await shot(page, 'autolayout-01-dialog');
  const blue = CARDS.map((c) => countHue(dlg, c, 'blue'));
  for (let i = 0; i < 3; i++) expect(blue[i], `전략 카드 ${i + 1} 의 파란 진행 막대`).toBeGreaterThan(300);
  for (let i = 0; i < 3; i++) expect(countHue(dlg, CARDS[i], 'green'), `카드 ${i + 1} "N개 모두"(초록)`).toBeGreaterThan(20);
  expect(blue[0], '첫 카드(추천)가 선택되어 파란 테두리').toBeGreaterThan(blue[1] + 300);

  await page.mouse.click(...center(CARDS[1]));
  await page.waitForTimeout(500);
  const dlg2 = await shot(page, 'autolayout-02-card2');
  expect(countHue(dlg2, CARDS[1], 'blue'), '두 번째 카드로 선택 이동').toBeGreaterThan(countHue(dlg2, CARDS[0], 'blue') + 300);

  await page.mouse.click(...CANCEL);
  expect(await waitForDim(page, idle, false, 4000)).toBeGreaterThanOrEqual(0);
  await page.mouse.move(600, 880);
  const cancelled = await waitForStable(page);
  expect(diffRatio(idle, cancelled, RD.canvasCore), '취소하면 배치가 그대로').toBeLessThan(0.005);

  // ── 접근 우선 전략 적용 ──
  await page.mouse.click(...D.autoLayoutWithGuide);
  expect(await waitForDim(page, idle, true, 12000)).toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  await page.mouse.click(...center(CARDS[2]));
  await page.waitForTimeout(400);
  await page.mouse.click(...APPLY);
  await page.waitForTimeout(1300);
  const verdict = await shot(page, 'autolayout-03-applied-verdict');
  expect(isDimmed(idle, verdict), '적용 후 판정 다이얼로그').toBe(true);
  expect(verdictDotHue(verdict), '판정 제목의 초록 점').toBe('green');
  await page.keyboard.press('Escape');
  const snack = await waitForSnack(page, 3000);
  expect(snack.kind, '적용 결과 SnackBar 는 초록').toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const applied = await shot(page, 'autolayout-04-applied');
  expect(countHue(applied, RD.canvasCore, 'blue'), '적재 순서 배지(파란 원)가 보인다').toBeGreaterThan(400);
  expect(countHue(applied, RD.pill, 'green')).toBeGreaterThan(15);

  // 스텝 뷰
  await page.mouse.click(...D.stepGuide);
  await page.mouse.move(600, 500);
  const step1 = await waitForStable(page);
  await shot(page, 'autolayout-05-step1');
  expect(countHue(step1, STEP_AREA, 'green'), '스텝 컨트롤(STEP n / N)이 보인다').toBeGreaterThan(150);
  expect(diffRatio(applied, step1, RD.canvasCore), '1단계는 첫 짐만 보인다').toBeGreaterThan(0.1);

  await page.mouse.click(...(await stepButtons(page)).next);
  await page.mouse.move(600, 500);
  const step2 = await waitForStable(page);
  await shot(page, 'autolayout-06-step2');
  expect(diffRatio(step1, step2, RD.canvasCore), '다음 단계에서 짐이 하나 더 보인다').toBeGreaterThan(0.005);
  expect(diffRatio(step1, step2, STEP_AREA), 'STEP 숫자/라벨이 바뀐다').toBeGreaterThan(0.002);

  await page.mouse.click(...(await stepButtons(page)).next);
  await page.mouse.move(600, 500);
  const step3 = await waitForStable(page);
  expect(diffRatio(step2, step3, RD.canvasCore)).toBeGreaterThan(0.005);

  await page.mouse.click(...(await stepButtons(page)).prev);
  await page.mouse.move(600, 500);
  const back2 = await waitForStable(page);
  expect(diffRatio(step2, back2, RD.canvasCore), '이전 단계로 돌아가면 같은 화면').toBeLessThan(0.002);

  await page.mouse.click(...(await stepButtons(page)).close);
  await page.mouse.move(600, 880);
  const closed = await waitForStable(page);
  await shot(page, 'autolayout-07-step-closed');
  expect(countHue(closed, { ...STEP_AREA, h: 36 }, 'green'), '스텝 컨트롤이 사라진다').toBeLessThan(10);
  expect(diffRatio(applied, closed, RD.canvasCore), '닫으면 전체 배치로 복귀').toBeLessThan(0.005);
});

// UX 버그: 스텝 컨트롤 폭이 라벨 길이에 따라 달라져 ✕/‹/› 버튼이 단계마다 움직인다.
// 같은 자리에서 "다음"을 연달아 누르다 보면 "이전"이나 "닫기"가 눌린다 (3단계에서 재현:
// 1단계의 ‹ 자리(399,912)가 3단계에서는 ✕ 이다). 버튼 위치가 고정되면 fixme 를 푼다.
test.fixme('BUG: 스텝 뷰의 다음/이전/닫기 버튼 위치가 단계마다 바뀐다', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'family')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.click(...D.stepGuide);
  await page.waitForTimeout(800);
  const xs: number[] = [];
  for (let i = 0; i < 4; i++) {
    const b = await stepButtons(page);
    xs.push(Math.round(b.next[0]));
    await page.mouse.click(...b.next);
    await page.waitForTimeout(500);
  }
  await shot(page, 'autolayout-bug-step-buttons-move');
  expect(Math.max(...xs) - Math.min(...xs), `"다음" 버튼 x 좌표들: ${xs.join(', ')}`).toBeLessThanOrEqual(2);
});
