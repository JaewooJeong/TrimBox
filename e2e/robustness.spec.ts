import {
  test, expect, shot, startDesktop, addBundle, openAddDialog, waitForSnackGone, waitForSnack, waitForDim,
  waitForStable, diffRatio, isDimmed, countTiles, countRuns, textHue, heapMB, D, RD, DESKTOP, Shot,
} from './helpers';

/** 견고성 — 창 크기 변경, 추가/삭제 반복, 연타, 모든 다이얼로그 열고 닫기 */

test.use({ viewport: DESKTOP });

test('세션 중 창 크기 변경(1280→900→600→500→1280)에도 장면이 유지된다', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'minimal')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const s0 = await waitForStable(page);
  expect(countTiles(s0)).toBe(9);

  for (const w of [900, 600, 500]) {
    await page.setViewportSize({ width: w, height: 960 });
    await page.waitForTimeout(900);
    const s = await shot(page, `robustness-resize-${w}`);
    // 어느 레이아웃에서든 캔버스에 짐(순서 배지의 파랑)이 그대로 보여야 한다
    const canvasW = w >= 600 ? w - 280 : w;
    expect(countRuns(s, { x: 0, y: 60, w: canvasW, h: 600 }, 'blue'), `폭 ${w}: 캔버스에 짐이 보인다`).toBeGreaterThan(0);
    if (w >= 600) {
      // 옆 패널 레이아웃: 목록 타일(빨간 삭제 아이콘) 9개
      expect(countRuns(s, { x: w - 56, y: 162, w: 20, h: 584 }, 'red'), `폭 ${w}: 목록 9개`).toBe(9);
    }
  }

  await page.setViewportSize(DESKTOP);
  await page.waitForTimeout(900);
  await page.mouse.move(600, 880);
  const back = await waitForStable(page);
  await shot(page, 'robustness-resize-back-1280');
  expect(countTiles(back), '짐 9개 그대로').toBe(9);
  expect(textHue(back, RD.pill)).toBe('green');
  expect(diffRatio(s0, back, RD.panelList), '목록이 그대로').toBeLessThan(0.005);
  expect(diffRatio(s0, back, RD.canvasCore), '원래 크기로 돌아오면 화면도 같다').toBeLessThan(0.02);
});

test('추가/삭제 20회 반복: 에러 없음 · 잔여 짐 없음 · 힙이 폭증하지 않는다', async ({ page }) => {
  test.setTimeout(150000);
  await startDesktop(page);
  const heap0 = await heapMB(page);
  const times: number[] = [];
  for (let i = 0; i < 20; i++) {
    await page.mouse.click(...D.addBox);
    await page.waitForTimeout(450);
    await page.mouse.click(...D.firstItem);
    await page.waitForTimeout(120);
    const t0 = Date.now();
    await page.mouse.click(...D.dialogAdd);
    const snack = await waitForSnack(page, 8000);
    times.push(Date.now() - t0);
    expect(snack.kind, `${i + 1}번째 추가`).toBe('green');
    expect(countTiles(snack.shot), `${i + 1}번째 추가 후 1개`).toBe(1);
    await page.mouse.click(...D.firstTileDelete);
    await page.waitForTimeout(250);
  }
  await page.mouse.move(600, 500);
  await page.waitForTimeout(600);
  const end = await shot(page, 'robustness-soak-end');
  expect(countTiles(end), '마지막에는 빈 트렁크').toBe(0);
  const heap1 = await heapMB(page);
  const sorted = [...times].sort((a, b) => a - b);
  console.log(`[soak] 20회 추가→판정 ms: 중앙값 ${sorted[10]}, 최대 ${sorted[19]}, 처음 ${times[0]}, 마지막 ${times[19]}`);
  console.log(`[soak] JS heap: ${heap0} MB → ${heap1} MB`);
  if (heap0 !== null && heap1 !== null) expect(heap1 - heap0, '힙 증가량(MB)').toBeLessThan(200);
  expect(times[19], '20번째도 처음보다 크게 느려지지 않는다').toBeLessThan(Math.max(3000, times[0] * 4));

  // 앱이 살아 있다
  expect((await addBundle(page, 'solo')).kind).toBe('green');
});

test('"추가" 연타·더블클릭에도 짐이 중복으로 들어가지 않는다 → 스크린샷 내보내기(1x) PNG 다운로드', async ({ page }) => {
  await startDesktop(page);
  // "박스 추가" 버튼 더블클릭 → 다이얼로그는 하나만
  const base = await shot(page);
  await page.mouse.dblclick(...D.addBox);
  expect(await waitForDim(page, base, true, 5000)).toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(700);
  await page.mouse.click(...D.bundleSolo);
  await page.waitForTimeout(400);
  // "추가" 더블클릭 + 연타
  await page.mouse.dblclick(...D.dialogAdd);
  await page.mouse.click(...D.dialogAdd, { delay: 10 });
  await page.mouse.click(...D.dialogAdd, { delay: 10 });
  const snack = await waitForSnack(page, 8000);
  expect(snack.kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const s = await shot(page, 'robustness-double-add');
  expect(isDimmed(base, s), '다이얼로그가 겹쳐 열리지 않았다(배경 dim 없음)').toBe(false);
  expect(countTiles(s), '솔로 세트 6개가 한 번만 들어간다').toBe(6);

  // 스크린샷 내보내기
  await page.mouse.click(...D.screenshot);
  expect(await waitForDim(page, s, true, 5000), '해상도 선택 다이얼로그').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  const download = page.waitForEvent('download', { timeout: 15000 });
  await page.mouse.click(551, 469); // 1x (표준)
  const dl = await download;
  expect(dl.suggestedFilename(), '파일 이름').toMatch(/\.png$/i);
  const saved = await waitForSnack(page, 8000);
  await shot(page, 'robustness-screenshot-saved');
  expect(saved.kind, '저장 완료 SnackBar').toBe('green');
});

test('모든 다이얼로그·메뉴를 열고 취소해도 앱이 반응한다', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'minimal')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const idle = await waitForStable(page);

  const openAndCancel = async (name: string, open: () => Promise<void>, cancel: () => Promise<void>, dims = true) => {
    await open();
    if (dims) {
      expect(await waitForDim(page, idle, true, 8000), `${name}: 열림`).toBeGreaterThanOrEqual(0);
    } else {
      await page.waitForTimeout(600);
      expect(diffRatio(idle, await shot(page), { x: 100, y: 10, w: 450, h: 190 }), `${name}: 메뉴 열림`).toBeGreaterThan(0.05);
    }
    await page.waitForTimeout(250);
    await cancel();
    await page.mouse.move(600, 880);
    expect(await waitForDim(page, idle, false, 5000), `${name}: 닫힘`).toBeGreaterThanOrEqual(0);
    const after = await waitForStable(page, RD.canvasCore, 3000);
    expect(isDimmed(idle, after), `${name}: 닫힘`).toBe(false);
    expect(diffRatio(idle, after, RD.canvasCore), `${name}: 취소는 장면을 바꾸지 않는다`).toBeLessThan(0.005);
    expect(countTiles(after), `${name}: 짐 개수 그대로`).toBe(9);
  };
  const click = (p: readonly [number, number]) => async () => { await page.mouse.click(p[0], p[1]); };
  const esc = async () => { await page.keyboard.press('Escape'); };

  await openAndCancel('add-escape', click(D.addBox), esc);
  await openAndCancel('add-cancel', click(D.addBox), click(D.dialogCancel));
  await openAndCancel('save', click(D.save), click([535, 541]));
  await openAndCancel('load', click(D.load), click([672, 693]));
  await openAndCancel('screenshot', click(D.screenshot), esc);
  await openAndCancel('autolayout', click(D.autoLayoutWithGuide), click([683, 647]));
  await openAndCancel('quickcheck', click(D.quickCheckWithGuide), esc);
  await openAndCancel('shortcuts', async () => { await page.keyboard.press('Shift+?'); }, esc);
  await openAndCancel('preset-menu', click(D.preset), esc, false);
  await openAndCancel('seat-menu', click(D.seatSlide), esc, false);
  await openAndCancel('custom-trunk', async () => {
    await page.mouse.click(...D.preset);
    await page.waitForTimeout(600);
    await page.mouse.click(...D.presetCustom);
  }, click([645, 572]));

  // 여전히 반응한다: Q 로 카메라가 돌고 0 으로 돌아온다
  await page.keyboard.press('q');
  const turned = await waitForStable(page);
  expect(diffRatio(idle, turned, RD.canvasCore), '키 입력이 여전히 먹는다').toBeGreaterThan(0.05);
  await page.keyboard.press('0');
  const reset = await waitForStable(page);
  expect(diffRatio(idle, reset, RD.canvasCore)).toBeLessThan(0.01);
});
