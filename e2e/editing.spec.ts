import {
  test, expect, shot, startDesktop, addBundle, addCustomBox, waitForSnackGone, waitForStable, diffRatio,
  isDimmed, countTiles, bboxOfDiff, center, countHue, drag, D, RD, DESKTOP,
} from './helpers';

/** 편집 — 회전·삭제·실행 취소/다시 실행·드래그·카메라·단축키 도움말 */

test.use({ viewport: DESKTOP });

const TILE_META = { x: 1100, y: 195, w: 50, h: 17 }; // 첫 타일의 "R:0°" 표시

test('회전: 패널 버튼 · R 키 · 실행 취소', async ({ page }) => {
  await startDesktop(page);
  const res = await addCustomBox(page, 'ROT', 70, 30, 25);
  expect(res.kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const s0 = await shot(page, 'editing-rotate-00');

  // 패널 회전 버튼
  await page.mouse.click(...D.firstTileRotate);
  await page.mouse.move(600, 880);
  const s1 = await waitForStable(page);
  await shot(page, 'editing-rotate-01-button');
  expect(diffRatio(s0, s1, RD.canvasCore), '회전하면 캔버스의 박스 모양이 바뀐다').toBeGreaterThan(0.005);
  expect(diffRatio(s0, s1, TILE_META), '타일의 치수/R 표시가 바뀐다').toBeGreaterThan(0.01);

  // Ctrl+Z → 원래대로
  await page.keyboard.press('Control+z');
  const s2 = await waitForStable(page);
  expect(diffRatio(s0, s2, TILE_META), '실행 취소 후 타일 표시 복원').toBeLessThan(0.002);

  // 타일을 눌러 선택 → R 키
  await page.mouse.click(...D.firstTile);
  await page.waitForTimeout(300);
  const sel = await shot(page);
  expect(countHue(sel, RD.firstTileTopBorder, 'blue'), '선택 타일 파란 테두리').toBeGreaterThan(100);
  await page.keyboard.press('r');
  const s3 = await waitForStable(page);
  await shot(page, 'editing-rotate-02-key');
  expect(diffRatio(sel, s3, TILE_META), 'R 키로 회전').toBeGreaterThan(0.01);
  expect(diffRatio(s1, s3, TILE_META), '버튼 회전과 R 키 회전의 결과 표시는 같다').toBeLessThan(0.002);
});

test('삭제: 패널 버튼 · Delete 키 · Ctrl+Z/Y · Ctrl+Shift+Z · 패널 undo/redo 버튼', async ({ page }) => {
  await startDesktop(page);
  const res = await addBundle(page, 'solo');
  expect(res.kind).toBe('green');
  await waitForSnackGone(page);
  const n0 = countTiles(await shot(page, 'editing-delete-00'));
  expect(n0, '솔로 백패킹은 6개').toBe(6);

  const tiles = async () => { await page.waitForTimeout(350); return countTiles(await shot(page)); };

  await page.mouse.click(...D.firstTileDelete);
  expect(await tiles(), '패널 삭제 버튼').toBe(5);
  await page.keyboard.press('Control+z');
  expect(await tiles(), 'Ctrl+Z').toBe(6);
  await page.keyboard.press('Control+y');
  expect(await tiles(), 'Ctrl+Y').toBe(5);
  await page.mouse.click(...D.undo);
  expect(await tiles(), '패널 실행 취소 버튼').toBe(6);
  await page.mouse.click(...D.redo);
  expect(await tiles(), '패널 다시 실행 버튼').toBe(5);

  // 선택 후 Delete 키
  await page.mouse.click(...D.firstTile);
  await page.waitForTimeout(300);
  await page.keyboard.press('Delete');
  expect(await tiles(), 'Delete 키').toBe(4);
  await page.keyboard.press('Control+z');
  expect(await tiles()).toBe(5);
  await page.keyboard.press('Control+Shift+z');
  expect(await tiles(), 'Ctrl+Shift+Z 다시 실행').toBe(4);

  // 선택 후 Backspace 도 삭제
  await page.mouse.click(...D.firstTile);
  await page.waitForTimeout(300);
  await page.keyboard.press('Backspace');
  expect(await tiles(), 'Backspace 키').toBe(3);
  await shot(page, 'editing-delete-01-end');
});

test('캔버스에서 박스를 마우스로 드래그 → 이동, Ctrl+Z → 복귀', async ({ page }) => {
  await startDesktop(page);
  await page.mouse.move(600, 880);
  const empty = await shot(page);
  const res = await addCustomBox(page, 'DRAG', 40, 30, 30);
  expect(res.kind).toBe('green');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const s0 = await shot(page, 'editing-drag-00');
  const box0 = bboxOfDiff(empty, s0, RD.canvasCore);
  expect(box0, '박스가 캔버스에 그려져야 한다').not.toBeNull();
  const [cx, cy] = center(box0!);

  await drag(page, cx, cy, cx + 220, cy + 120, { steps: 16 });
  await page.mouse.move(600, 880);
  const s1 = await waitForStable(page);
  await shot(page, 'editing-drag-01-moved');
  const box1 = bboxOfDiff(empty, s1, RD.canvasCore);
  expect(box1).not.toBeNull();
  const [nx] = center(box1!);
  expect(nx - cx, '박스가 오른쪽으로 옮겨져야 한다').toBeGreaterThan(80);
  expect(countHue(s1, RD.firstTileTopBorder, 'blue'), '드래그한 박스가 선택된다').toBeGreaterThan(100);

  await page.keyboard.press('Control+z');
  const s2 = await waitForStable(page);
  await shot(page, 'editing-drag-02-undone');
  const box2 = bboxOfDiff(empty, s2, RD.canvasCore);
  const [ux] = center(box2!);
  expect(Math.abs(ux - cx), '실행 취소로 원위치').toBeLessThan(12);
});

test('단축키 도움말(? 키·앱바 아이콘) · 카메라: 오빗 · 휠 줌 · 우클릭 패닝 · Q/E · 0 리셋', async ({ page }) => {
  await startDesktop(page);

  // ── 단축키 도움말 ──
  const base = await shot(page);
  await page.keyboard.press('Shift+?');
  await page.waitForTimeout(700);
  const open1 = await shot(page, 'editing-shortcuts-01-key');
  expect(isDimmed(base, open1), '? 키로 도움말 열림').toBe(true);
  expect(countHue(open1, { x: 440, y: 300, w: 120, h: 350 }, 'blue'), '카테고리 제목(파랑)').toBeGreaterThan(30);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(600);
  expect(isDimmed(base, await shot(page))).toBe(false);

  await page.mouse.click(...D.help);
  await page.waitForTimeout(700);
  const open2 = await shot(page, 'editing-shortcuts-02-icon');
  expect(isDimmed(base, open2), '앱바 ? 아이콘으로 도움말 열림').toBe(true);
  await page.mouse.click(812, 266); // 닫기 X
  await page.waitForTimeout(600);
  await page.mouse.move(600, 500);
  await page.waitForTimeout(300);
  expect(isDimmed(base, await shot(page)), '닫기 버튼').toBe(false);

  // ── 카메라 ──
  await addBundle(page, 'minimal');
  await waitForSnackGone(page);
  await page.mouse.move(600, 880);
  const home = await shot(page, 'editing-camera-00-home');

  const expectChangedThenReset = async (label: string, name: string) => {
    await page.mouse.move(600, 880);
    const moved = await waitForStable(page);
    await shot(page, name);
    expect(diffRatio(home, moved, RD.canvasCore), `${label}: 화면이 바뀌어야 한다`).toBeGreaterThan(0.05);
    await page.keyboard.press('0');
    const back = await waitForStable(page);
    expect(diffRatio(home, back, RD.canvasCore), `${label} 후 0 키로 카메라 리셋`).toBeLessThan(0.01);
  };

  await drag(page, 150, 150, 330, 230); // 빈 곳 드래그 = 오빗
  await expectChangedThenReset('오빗', 'editing-camera-01-orbit');

  await page.mouse.move(480, 480);
  await page.mouse.wheel(0, -600);
  await expectChangedThenReset('휠 줌', 'editing-camera-02-zoom');

  await drag(page, 480, 300, 640, 380, { button: 'right' });
  await expectChangedThenReset('우클릭 패닝', 'editing-camera-03-pan');

  await page.keyboard.press('q');
  await expectChangedThenReset('Q 회전', 'editing-camera-04-q');

  await page.keyboard.press('e');
  await expectChangedThenReset('E 회전', 'editing-camera-05-e');
});
