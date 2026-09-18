import {
  test, expect, shot, startDesktop, addBundle, waitForSnackGone, waitForSnack, waitForDim, waitForStable,
  diffRatio, saveDiff, isDimmed, countTiles, snackKind, textHue, setField, waitForFirstFrame, D, RD, DESKTOP,
} from './helpers';

/** 저장/복원 — 자동 저장, 이름 저장/불러오기, 손상된 localStorage */

test.use({ viewport: DESKTOP });

const SAVE_DIALOG = { name: [640, 484], save: [735, 541], cancel: [535, 541] } as const;

async function reloadApp(page) {
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 30000 });
  await waitForFirstFrame(page);
  await page.waitForTimeout(600); // 자동 저장 복원(비동기)
  await page.mouse.move(600, 880);
  return waitForStable(page, undefined, 5000, 3);
}

test('자동 저장 → 새로고침 → 같은 장면 (차종·2열 슬라이드·배치 그대로)', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'minimal')).kind).toBe('green');
  await waitForSnackGone(page);
  // 2열 중간으로 바꿔 트렁크 상태도 저장되는지 본다
  await page.mouse.click(...D.seatSlide);
  await page.waitForTimeout(600);
  await page.mouse.click(...D.seatMid);
  expect((await waitForSnack(page, 8000)).kind).toBe('green');
  await waitForSnackGone(page);
  await page.waitForTimeout(1200); // 자동 저장 디바운스(0.8초)
  await page.mouse.move(600, 880);
  const before = await waitForStable(page);
  await shot(page, 'persistence-autosave-01-before');
  const tilesBefore = countTiles(before);
  expect(tilesBefore).toBe(9);

  const keys = await page.evaluate(() => Object.keys(localStorage));
  console.log('[persistence] localStorage keys: ' + keys.join(', '));
  expect(keys.some((k) => k.includes('autosave')), '자동 저장 키가 있어야 한다').toBe(true);

  const after = await reloadApp(page);
  await shot(page, 'persistence-autosave-02-after-reload');
  saveDiff(before, after, RD.canvas, 'persistence-autosave-03-diff');
  expect(countTiles(after), '짐 개수 복원').toBe(tilesBefore);
  expect(diffRatio(before, after, RD.appBarControls), '차종·2열 슬라이드 복원').toBeLessThan(0.002);
  expect(diffRatio(before, after, RD.canvasCore), '배치가 같은 자리로 복원').toBeLessThan(0.01);
  expect(diffRatio(before, after, RD.panelList), '목록 복원').toBeLessThan(0.01);
  expect(snackKind(after), '복원은 조용해야 한다 (SnackBar 없음)').toBeNull();
  expect(textHue(after, RD.pill)).toBe('green');
});

test('이름 저장 → 전부 삭제 → 불러오기 → 복원', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'solo')).kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const saved = await waitForStable(page);
  await shot(page, 'persistence-named-01-scene');
  expect(countTiles(saved)).toBe(6);

  // 저장
  await page.mouse.click(...D.save);
  expect(await waitForDim(page, saved, true, 5000), '배치 저장 다이얼로그').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(400);
  await setField(page, ...SAVE_DIALOG.name, 'e2e-solo');
  await shot(page, 'persistence-named-02-save-dialog');
  await page.mouse.click(...SAVE_DIALOG.save);
  const snack = await waitForSnack(page, 6000);
  await shot(page, 'persistence-named-03-saved-snack');
  expect(snack.kind, '저장 완료 SnackBar 는 초록').toBe('green');
  await waitForSnackGone(page);

  const keys = await page.evaluate(() => Object.keys(localStorage));
  expect(keys.some((k) => k.includes('trimbox_scene_e2e-solo')), '이름 저장 키: ' + keys.join(', ')).toBe(true);

  // 전부 삭제
  for (let i = 0; i < 6; i++) {
    await page.mouse.click(...D.firstTileDelete);
    await page.waitForTimeout(300);
  }
  await page.mouse.move(600, 880);
  const cleared = await waitForStable(page);
  await shot(page, 'persistence-named-04-cleared');
  expect(countTiles(cleared), '전부 삭제').toBe(0);
  expect(diffRatio(saved, cleared, RD.canvasCore)).toBeGreaterThan(0.01);

  // 불러오기
  await page.mouse.click(...D.load);
  expect(await waitForDim(page, cleared, true, 5000), '불러오기 다이얼로그').toBeGreaterThanOrEqual(0);
  await page.waitForTimeout(600);
  await shot(page, 'persistence-named-05-load-dialog');
  await page.mouse.click(600, 330); // 첫 번째 저장 항목
  const loadedSnack = await waitForSnack(page, 6000);
  await shot(page, 'persistence-named-06-loaded-snack');
  expect(loadedSnack.kind, '불러오기 SnackBar 는 초록').toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const restored = await waitForStable(page);
  await shot(page, 'persistence-named-07-restored');
  expect(isDimmed(saved, restored)).toBe(false);
  expect(countTiles(restored), '짐 6개 복원').toBe(6);
  expect(diffRatio(saved, restored, RD.canvasCore), '배치가 저장 당시와 같다').toBeLessThan(0.01);
});

const CORRUPT: [string, string][] = [
  ['깨진 장면 JSON 문자열', JSON.stringify('{"space": {"w": 1.0, "boxes": [')],
  ['형이 다른 값(숫자)', '12345'],
  ['스키마가 다른 JSON', JSON.stringify(JSON.stringify({ space: 'x', boxes: 7 }))],
  ['필드가 빠진 박스', JSON.stringify(JSON.stringify({ space: { w: 1, d: 1, h: 1 }, boxes: [{ id: 'a' }, null, 3] }))],
  // 마지막: shared_preferences 가 디코드조차 못 하는 값. 이 값은 시작할 때 지워지지 않고
  // 다음 자동 저장이 덮어쓸 때 고쳐진다 (아래 "자동 저장이 다시 쓰인다" 단언이 그 확인이다).
  ['JSON 이 아닌 원시 값', '{{{not-json'],
];

test('손상된 자동 저장 값 5종에도 에러·빨간 SnackBar 없이 빈 트렁크로 시작하고 저장소가 스스로 복구된다', async ({ page }) => {
  await startDesktop(page);
  expect((await addBundle(page, 'solo')).kind).toBe('green');
  await page.waitForTimeout(1500); // 자동 저장
  const key = await page.evaluate(() => Object.keys(localStorage).find((k) => k.includes('autosave')) ?? null);
  expect(key, '자동 저장 키').not.toBeNull();

  for (const [label, value] of CORRUPT) {
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), [key!, value] as const);
    const after = await reloadApp(page);
    const safe = label.replace(/[^\w가-힣]+/g, '-');
    await shot(page, `persistence-corrupt-${safe}`);
    expect(snackKind(after), `${label}: 에러 SnackBar 가 없어야 한다`).toBeNull();
    expect(countTiles(after), `${label}: 손상된 저장본은 버리고 빈 트렁크로 시작`).toBe(0);
    const left = await page.evaluate((k) => localStorage.getItem(k), key!);
    if (left === value) console.log(`[persistence] "${label}" 값은 시작 시 지워지지 않았다 (다음 자동 저장에서 덮어씀)`);
  }

  // 앱이 살아 있는지: 번들을 다시 추가할 수 있고 자동 저장도 다시 된다
  const again = await addBundle(page, 'solo');
  expect(again.kind, '손상 복구 후에도 정상 동작').toBe('green');
  await waitForSnackGone(page);
  expect(countTiles(await shot(page))).toBe(6);
  const healed = await page.evaluate((k) => localStorage.getItem(k), key!);
  expect(healed && healed.length > 100 && !healed.startsWith('{{{'), '자동 저장이 다시 쓰인다').toBeTruthy();
});
