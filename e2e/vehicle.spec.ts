import {
  test, expect, shot, startDesktop, addBundle, waitForSnackGone, waitForSnack, waitForDim, waitForStable,
  diffRatio, isDimmed, textHue, setField, D, RD, DESKTOP,
} from './helpers';

/** 앱바: 2열 슬라이드 메뉴 · 차종 프리셋 메뉴 · 커스텀 트렁크 다이얼로그 */

test.use({ viewport: DESKTOP });

const SEAT_MENU = { x: 360, y: 12, w: 170, h: 160 };
const PRESET_MENU = { x: 113, y: 12, w: 280, h: 188 };
const CUSTOM = { w: [560, 446], d: [640, 446], h: [720, 446], ok: [718, 572], cancel: [645, 572] } as const;

test('2열 슬라이드: 메뉴 열기 → 중간 → 최전방 → 최후방 (앱바·캡션·캔버스가 따라 바뀐다)', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'minimal')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const rear = await shot(page, 'vehicle-seat-00-rear');

  // settle=false: SnackBar 가 떠 있는 채로 진행 (캡션·알약은 가려지므로 앱바·캔버스만 본다)
  const pick = async (item: readonly [number, number], name: string, settle = true) => {
    const before = await shot(page);
    await page.mouse.click(...D.seatSlide);
    await page.waitForTimeout(600);
    const menu = await shot(page, `${name}-menu`);
    expect(diffRatio(before, menu, SEAT_MENU), '2열 슬라이드 메뉴가 열린다').toBeGreaterThan(0.1);
    await page.mouse.click(...item);
    // 바닥 깊이가 바뀌면 다시 배치하고 판정 SnackBar 를 띄운다
    const snack = await waitForSnack(page, 8000);
    expect(snack.kind, '슬라이드 변경 후에도 전부 들어간다').toBe('green');
    if (settle) await waitForSnackGone(page);
    await page.mouse.move(600, 880);
    const s = await waitForStable(page);
    await shot(page, name);
    return s;
  };

  const mid = await pick(D.seatMid, 'vehicle-seat-01-mid');
  expect(diffRatio(rear, mid, RD.appBarControls), '앱바 라벨(바닥 깊이·2열 위치)이 바뀐다').toBeGreaterThan(0.01);
  expect(diffRatio(rear, mid, RD.caption), '하단 캡션(깊이·VDA)이 바뀐다').toBeGreaterThan(0.005);
  expect(diffRatio(rear, mid, RD.canvasCore), '트렁크가 깊어져 캔버스가 바뀐다').toBeGreaterThan(0.05);
  expect(textHue(mid, RD.pill)).toBe('green');

  const front = await pick(D.seatFront, 'vehicle-seat-02-front', false);
  expect(diffRatio(mid, front, RD.appBarControls)).toBeGreaterThan(0.01);
  expect(diffRatio(mid, front, RD.canvasCore)).toBeGreaterThan(0.05);

  const back = await pick(D.seatRear, 'vehicle-seat-03-rear-again');
  expect(diffRatio(rear, back, RD.appBarControls), '최후방으로 돌아오면 앱바가 처음과 같다').toBeLessThan(0.002);
  expect(diffRatio(rear, back, RD.caption), '캡션도 처음과 같다').toBeLessThan(0.002);
});

test('차종: 5인승 → 7인승·3열 접음 → 커스텀(치수 입력) → 취소 경로 → 5인승 복귀', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'solo')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const five = await shot(page, 'vehicle-preset-00-five');

  // 7인승
  await page.mouse.click(...D.preset);
  await page.waitForTimeout(600);
  const menu = await shot(page, 'vehicle-preset-01-menu');
  expect(diffRatio(five, menu, PRESET_MENU), '차종 메뉴가 열린다').toBeGreaterThan(0.1);
  await page.mouse.click(...D.presetSorento7);
  expect((await waitForSnack(page, 8000)).kind, '7인승에서도 솔로 세트는 들어간다').toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const seven = await shot(page, 'vehicle-preset-02-seven');
  expect(diffRatio(five, seven, RD.appBarControls), '앱바 차종 라벨이 바뀐다').toBeGreaterThan(0.02);
  expect(diffRatio(five, seven, RD.caption), '캡션이 7인승으로 바뀐다').toBeGreaterThan(0.005);
  expect(textHue(seven, RD.pill)).toBe('green');

  // 커스텀 → 취소: 아무것도 바뀌지 않는다
  await page.mouse.click(...D.preset);
  await page.waitForTimeout(600);
  await page.mouse.click(...D.presetCustom);
  expect(await waitForDim(page, seven, true, 5000), '커스텀 트렁크 다이얼로그').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  await shot(page, 'vehicle-preset-03-custom-dialog');
  await page.mouse.click(...CUSTOM.cancel);
  expect(await waitForDim(page, seven, false, 5000)).toBeGreaterThanOrEqual(0);
  await page.mouse.move(600, 880);
  const cancelled = await waitForStable(page);
  expect(diffRatio(seven, cancelled, RD.appBarControls), '취소하면 차종이 그대로').toBeLessThan(0.002);
  expect(diffRatio(seven, cancelled, RD.canvasCore)).toBeLessThan(0.005);

  // 커스텀 → 130×90×60 적용
  await page.mouse.click(...D.preset);
  await page.waitForTimeout(600);
  await page.mouse.click(...D.presetCustom);
  expect(await waitForDim(page, seven, true, 5000)).toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  await setField(page, ...CUSTOM.w, '130');
  await setField(page, ...CUSTOM.d, '90');
  await setField(page, ...CUSTOM.h, '60');
  await shot(page, 'vehicle-preset-04-custom-filled');
  await page.mouse.click(...CUSTOM.ok);
  await page.waitForTimeout(800);
  const snack = await waitForSnack(page, 8000);
  if (snack.kind) await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const custom = await waitForStable(page);
  await shot(page, 'vehicle-preset-05-custom');
  expect(isDimmed(seven, custom)).toBe(false);
  expect(diffRatio(seven, custom, RD.appBarControls), '앱바가 "커스텀 (130×90cm)" 로').toBeGreaterThan(0.02);
  expect(diffRatio(seven, custom, RD.canvasCore), '커스텀 트렁크 형상으로 다시 그려진다').toBeGreaterThan(0.05);
  expect(textHue(custom, RD.panelStatus), '커스텀 트렁크에서도 솔로 세트는 문제 없이 들어간다').not.toBe('red');

  // 5인승 복귀
  await page.mouse.click(...D.preset);
  await page.waitForTimeout(600);
  await page.mouse.click(...D.presetSorento5);
  const s5 = await waitForSnack(page, 8000);
  if (s5.kind) await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const again = await waitForStable(page);
  await shot(page, 'vehicle-preset-06-five-again');
  expect(diffRatio(five, again, RD.appBarControls), '5인승으로 돌아오면 앱바가 처음과 같다').toBeLessThan(0.002);
  expect(diffRatio(five, again, RD.caption)).toBeLessThan(0.002);
  expect(textHue(again, RD.pill)).toBe('green');
});
