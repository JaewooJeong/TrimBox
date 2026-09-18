import {
  test, expect, shot, startDesktop, addBundle, waitForSnackGone, textHue, countHue, D, RD, DESKTOP,
} from './helpers';

/**
 * 테일게이트 닫힘 규칙 — 위에 쌓인 짐을 테일게이트 쪽(z+)으로 밀면 알약이 빨강으로 바뀌고
 * 빨간 반투명 닫힘 면이 나타난다. 실행 취소로 초록으로 돌아온다.
 */

test.use({ viewport: DESKTOP });

// 4인 가족 세트에서 위쪽에 놓이는 롤테이블(15번) 라벨 부근
const TOP_BOX: [number, number] = [417, 390];

async function pushTowardTailgate(page, presses = 40) {
  for (let i = 0; i < presses; i++) {
    await page.keyboard.press('ArrowDown');
    await page.waitForTimeout(15);
  }
  await page.waitForTimeout(500);
}

test('위쪽 짐을 테일게이트 쪽으로 밀면 빨강 경고 → Ctrl+Z 로 복구 → 다시 밀고 패널 실행 취소 버튼으로 복구', async ({ page }) => {
  await startDesktop(page);
  const res = await addBundle(page, 'family');
  expect(res.kind).toBe('green');
  await waitForSnackGone(page);
  const packed = await shot(page, 'tailgate-01-packed');
  expect(textHue(packed, RD.pill)).toBe('green');
  const redBefore = countHue(packed, RD.canvas, 'alarm');

  await page.mouse.click(...TOP_BOX);
  await page.waitForTimeout(400);
  const selected = await shot(page, 'tailgate-02-selected');
  expect(countHue(selected, RD.panelList, 'blue'), '선택된 목록 타일에 파란 테두리').toBeGreaterThan(200);

  await pushTowardTailgate(page);
  const blocked = await shot(page, 'tailgate-03-blocked');
  expect(textHue(blocked, RD.pill), '알약이 빨강(테일게이트 안 닫힘)').toBe('red');
  expect(countHue(blocked, RD.canvas, 'alarm') - redBefore, '빨간 닫힘 면/빨간 외곽선이 나타난다').toBeGreaterThan(1500);
  expect(textHue(blocked, RD.panelStatus), '패널 상태 행도 문제(빨강)').toBe('red');

  // ① Ctrl+Z 를 초록이 될 때까지 (최대 60번)
  const undoUntilGreen = async (step: () => Promise<void>) => {
    let n = 0;
    let cur = await shot(page);
    while (textHue(cur, RD.pill) !== 'green' && n < 60) {
      await step();
      await page.waitForTimeout(70);
      n++;
      if (n % 5 === 0 || n < 3) cur = await shot(page);
    }
    return n;
  };
  const undos = await undoUntilGreen(() => page.keyboard.press('Control+z'));
  let cur = await shot(page, 'tailgate-04-undone');
  console.log(`[tailgate] Ctrl+Z ${undos}회로 초록 복귀`);
  expect(textHue(cur, RD.pill), 'Ctrl+Z 로 초록 복귀').toBe('green');
  expect(countHue(cur, RD.canvas, 'alarm') - redBefore).toBeLessThan(300);

  // ② 다시 밀고, 이번에는 패널의 실행 취소 버튼으로
  await page.mouse.click(...TOP_BOX);
  await page.waitForTimeout(400);
  await pushTowardTailgate(page);
  cur = await shot(page, 'tailgate-05-blocked-again');
  expect(textHue(cur, RD.pill)).toBe('red');
  const clicks = await undoUntilGreen(() => page.mouse.click(...D.undo));
  await page.mouse.move(600, 500);
  await page.waitForTimeout(800); // 툴팁 사라짐
  cur = await shot(page, 'tailgate-06-undo-button');
  console.log(`[tailgate] 실행 취소 버튼 ${clicks}회로 초록 복귀`);
  expect(textHue(cur, RD.pill), '실행 취소 버튼으로 초록 복귀').toBe('green');
  expect(textHue(cur, RD.panelStatus)).not.toBe('red');
});
