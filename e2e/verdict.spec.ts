import {
  test, expect, shot, startDesktop, addBundle, addCustomBox, waitForSnackGone,
  textHue, isDimmed, diffRatio, countHue, verdictDotHue, waitForDim, waitForStable, bboxOfHue, center, D, RD, DESKTOP, Bundle,
} from './helpers';

/**
 * 판정 플로우 — 번들 3종은 전부 들어가야 하고(초록), 너무 긴 짐은 안 들어가며(주황)
 * 2열 슬라이드 제안을 적용하면 들어간다.
 */

test.use({ viewport: DESKTOP });

const timings: Record<string, number> = {};

test.afterAll(() => {
  console.log('[timing] desktop add→verdict(ms): ' + JSON.stringify(timings));
});

for (const [bundle, title, hasGuide] of [
  ['minimal', '2인 미니멀 캠핑', true],
  ['family', '4인 가족 캠핑', true],
  ['solo', '솔로 백패킹', true],
] as [Bundle, string, boolean][]) {
  test(`번들 "${title}" → 초록 SnackBar · 초록 테일게이트 알약 · 들어갈까? 다이얼로그`, async ({ page }) => {
    await startDesktop(page);
    const res = await addBundle(page, bundle);
    await shot(page, `verdict-${bundle}-01-snack`);
    timings[bundle] = res.ms;
    expect(res.kind, '전부 들어가면 SnackBar 는 초록이어야 한다').toBe('green');
    expect(res.ms, '추가 → 판정 SnackBar 까지 8초 미만').toBeLessThan(8000);

    await waitForSnackGone(page);
    const idle = await shot(page, `verdict-${bundle}-02-idle`);
    expect(textHue(idle, RD.pill), '테일게이트 알약은 초록').toBe('green');
    expect(textHue(idle, RD.panelStatus), '패널 상태 행에 문제(빨강)가 없어야 한다').not.toBe('red');
    // 박스가 실제로 그려졌는지: 적재율 오버레이가 나타난다
    expect(countHue(idle, RD.overlay, 'green') + countHue(idle, RD.overlay, 'amber') + countHue(idle, RD.overlay, 'red'))
      .toBeGreaterThan(20);

    // 들어갈까? → 다이얼로그(배경 dim) → Escape 로 닫힘
    await page.mouse.click(...(hasGuide ? D.quickCheckWithGuide : D.quickCheckNoGuide));
    await page.waitForTimeout(1500);
    const dlg = await shot(page, `verdict-${bundle}-03-quickcheck`);
    expect(isDimmed(idle, dlg), '판정 다이얼로그가 열리면 배경이 어두워진다').toBe(true);
    // 다이얼로그 제목 옆 점이 초록 (모두 적재 가능)
    expect(verdictDotHue(dlg), '모두 적재 가능 = 초록 점').toBe('green');

    await page.keyboard.press('Escape');
    await page.waitForTimeout(800);
    const closed = await shot(page, `verdict-${bundle}-04-closed`);
    expect(isDimmed(idle, closed), 'Escape 후 배경 dim 이 풀려야 한다').toBe(false);
    // 들어갈까? 는 배치를 바꾸지 않는다 (SnackBar 영역 제외)
    expect(diffRatio(idle, closed, RD.canvasCore)).toBeLessThan(0.01);

    if (bundle !== 'minimal') return;
    // 판정 다이얼로그의 "순서 가이드"(초록 외곽선 버튼) → 스텝 뷰로 들어간다
    await page.mouse.click(...D.quickCheckWithGuide);
    expect(await waitForDim(page, idle, true, 8000)).toBeGreaterThanOrEqual(0);
    await page.waitForTimeout(500);
    const again = await shot(page);
    const guide = bboxOfHue(again, { x: 540, y: 560, w: 150, h: 200 }, 'green');
    expect(guide, '"순서 가이드" 초록 버튼').not.toBeNull();
    await page.mouse.click(...center(guide!));
    expect(await waitForDim(page, idle, false, 4000), '다이얼로그가 닫힌다').toBeGreaterThanOrEqual(0);
    await page.mouse.move(600, 500);
    const step = await waitForStable(page);
    await shot(page, 'verdict-minimal-05-step-from-dialog');
    const stepBox = bboxOfHue(step, { x: 200, y: 870, w: 560, h: 80 }, 'green');
    expect(stepBox, '스텝 컨트롤(초록 테두리)이 보인다').not.toBeNull();
    expect(diffRatio(idle, step, RD.canvasCore), '1단계는 첫 짐만 보인다').toBeGreaterThan(0.02);
    await page.mouse.click(stepBox!.x + 29, stepBox!.y + stepBox!.h / 2); // ✕
    await page.mouse.move(600, 880);
    const out = await waitForStable(page);
    expect(diffRatio(idle, out, RD.canvasCore), '스텝 뷰를 닫으면 전체 배치로 복귀').toBeLessThan(0.01);
  });
}

test('안 들어가는 짐(100×125×20) → 주황 SnackBar → "2열 +27cm 적용" → 초록', async ({ page }) => {
  await startDesktop(page);
  const before = await shot(page);
  const res = await addCustomBox(page, 'BIG', 100, 125, 20);
  await shot(page, 'verdict-nofit-01-snack');
  expect(res.kind, '깊이 125cm 는 107cm 트렁크에 안 들어간다 → 주황').toBe('amber');
  expect(res.ms).toBeLessThan(8000);

  await waitForSnackGone(page, 12000);
  const idle = await shot(page, 'verdict-nofit-02-idle');
  expect(textHue(idle, RD.panelStatus), '패널 상태 행은 문제(빨강)').toBe('red');
  // 목록 타일에 빨간 테두리(충돌/경계 밖)
  expect(countHue(idle, RD.firstTileTopBorder, 'red')).toBeGreaterThan(100);

  // 들어갈까? → 제안 버튼
  await page.mouse.click(...D.quickCheckNoGuide);
  await page.waitForTimeout(1500);
  const dlg = await shot(page, 'verdict-nofit-03-quickcheck');
  expect(isDimmed(idle, dlg)).toBe(true);
  const suggest = { x: 565, y: 580, w: 160, h: 44 };
  expect(countHue(dlg, suggest, 'green'), '"2열 +Ncm 적용" 초록 외곽선 버튼').toBeGreaterThan(60);
  // 다이얼로그 제목의 빨간 점
  expect(verdictDotHue(dlg), '적재 불가 = 빨간 점').toBe('red');

  await page.mouse.click(645, 602);
  await page.waitForTimeout(1800);
  // 적용하면 새 판정 다이얼로그("모두 적재 가능!", 초록 점)가 뜬다
  const verdict = await shot(page, 'verdict-nofit-04-applied-dialog');
  expect(isDimmed(idle, verdict), '적용 후 판정 다이얼로그').toBe(true);
  expect(verdictDotHue(verdict), '적용 후 판정은 초록 점').toBe('green');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);
  await waitForSnackGone(page);
  const done = await shot(page, 'verdict-nofit-05-applied');
  expect(isDimmed(idle, done), '제안 적용 후 다이얼로그가 닫혀야 한다').toBe(false);
  expect(diffRatio(before, done, RD.appBarControls), '앱바 2열/바닥 깊이 표시가 바뀌어야 한다').toBeGreaterThan(0.01);
  expect(textHue(done, RD.pill)).toBe('green');
  expect(textHue(done, RD.panelStatus)).not.toBe('red');
  expect(countHue(done, RD.firstTileTopBorder, 'red'), '타일의 빨간 테두리가 사라져야 한다').toBe(0);
});
