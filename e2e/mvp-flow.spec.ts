import { test, expect } from '@playwright/test';
import { compareScreenshot } from './helpers/visual-compare';

const FLOW_TIMEOUT = 3000;

test.describe('MVP 전체 플로우 — 시각 회귀 테스트', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('http://localhost:8090', { waitUntil: 'networkidle' });
    await page.waitForTimeout(FLOW_TIMEOUT);
  });

  test('Step 1: 앱 초기 로드 — 오버레이 표시', async ({ page }) => {
    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step01-initial-load', 0.1, 2.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });

  test('Step 2: 오버레이 닫기 — 빈 트렁크', async ({ page }) => {
    // Dismiss overlay
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step02-empty-trunk', 0.1, 2.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });

  test('Step 3: 캠핑 장비 다이얼로그 열기', async ({ page }) => {
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);

    // Click "캠핑 장비 선택하기"
    await page.mouse.click(1097, 597);
    await page.waitForTimeout(1500);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step03-camping-dialog', 0.1, 2.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });

  test('Step 4: 4인 가족 캠핑 프리셋 선택 + 추가', async ({ page }) => {
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);
    await page.mouse.click(1097, 597);
    await page.waitForTimeout(1500);

    // Select 4인 가족 캠핑
    await page.mouse.click(608, 430);
    await page.waitForTimeout(1000);

    // Click 추가
    await page.mouse.click(790, 744);
    await page.waitForTimeout(2000);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step04-items-added', 0.1, 3.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });

  test('Step 5: 자동 배치 다이얼로그', async ({ page }) => {
    // Replay: dismiss → camping → preset → add
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);
    await page.mouse.click(1097, 597);
    await page.waitForTimeout(1500);
    await page.mouse.click(608, 430);
    await page.waitForTimeout(1000);
    await page.mouse.click(790, 744);
    await page.waitForTimeout(2000);

    // Click 자동 배치
    await page.mouse.click(1155, 561);
    await page.waitForTimeout(2000);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step05-auto-layout-dialog', 0.1, 3.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });

  test('Step 6: 자동 배치 적용 — 최종 결과', async ({ page }) => {
    // Replay full flow
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);
    await page.mouse.click(1097, 597);
    await page.waitForTimeout(1500);
    await page.mouse.click(608, 430);
    await page.waitForTimeout(1000);
    await page.mouse.click(790, 744);
    await page.waitForTimeout(2000);
    await page.mouse.click(1155, 561);
    await page.waitForTimeout(2000);

    // Select 최대 적재 & apply
    await page.mouse.click(500, 447);
    await page.waitForTimeout(500);
    await page.mouse.click(783, 667);
    await page.waitForTimeout(2000);

    // Close verdict
    await page.mouse.click(608, 625);
    await page.waitForTimeout(1500);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'step06-final-layout', 0.1, 3.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });
});

test.describe('차종 변경 테스트', () => {
  test('싼타페로 변경 후 빈 트렁크', async ({ page }) => {
    await page.goto('http://localhost:8090', { waitUntil: 'networkidle' });
    await page.waitForTimeout(FLOW_TIMEOUT);

    // Dismiss overlay
    await page.mouse.click(460, 480);
    await page.waitForTimeout(1000);

    // Click vehicle dropdown
    await page.mouse.click(185, 27);
    await page.waitForTimeout(500);

    // Select 싼타페 (3rd option)
    await page.mouse.click(185, 27 + 3 * 48);
    await page.waitForTimeout(1000);

    const buf = await page.screenshot({ type: 'png' }) as Buffer;
    const result = compareScreenshot(buf, 'vehicle-santafe', 0.1, 3.0);
    expect(result.match, `Diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
  });
});
