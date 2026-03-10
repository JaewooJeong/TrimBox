import { Page, expect } from '@playwright/test';

/**
 * Wait for Flutter app to fully load and dismiss welcome overlay.
 */
export async function waitForAppLoad(page: Page) {
  // Wait for Flutter to render
  await page.waitForSelector('flt-glass-pane', { timeout: 30000 });
  // Extra wait for canvas rendering
  await page.waitForTimeout(2000);
}

/**
 * Dismiss the welcome/instruction overlay by clicking anywhere on it.
 */
export async function dismissOverlay(page: Page) {
  // The overlay has "아무 곳이나 클릭하여 닫기" (click anywhere to close)
  // Click center of viewport to dismiss
  await page.mouse.click(640, 480);
  await page.waitForTimeout(500);
}

/**
 * Open vehicle dropdown and select a preset.
 */
export async function selectVehicle(page: Page, vehicleName: string) {
  // Vehicle selector is a dropdown at top-left area
  // Click on the dropdown (approximately at x=110, y=22)
  await page.mouse.click(110, 22);
  await page.waitForTimeout(500);

  // Find and click the vehicle option text
  // Flutter renders text on canvas, so we use coordinates
  // The dropdown options appear below the selector
  const vehicleMap: Record<string, number> = {
    '투싼': 1,
    '쏘렌토': 2,
    '싼타페': 3,
    '카니발': 4,
    '아이오닉5': 5,
    '아반떼': 6,
    '커스텀': 7,
  };

  const index = vehicleMap[vehicleName] || 2;
  // Each dropdown item is about 48px tall, starting from dropdown position
  await page.mouse.click(110, 22 + index * 48);
  await page.waitForTimeout(800);
}

/**
 * Click "캠핑 장비 선택하기" button to open preset dialog.
 */
export async function openCampingPresetDialog(page: Page) {
  // The "캠핑 장비 선택하기" button is on the right panel
  // Based on screenshots: approximately at x=540, y=330 in right panel area
  // But with 1280 width, right panel starts around x=470
  // Button text: "캠핑 장비 선택하기" — blue button at right side
  await page.mouse.click(540, 330);
  await page.waitForTimeout(1000);
}

/**
 * Click "+ 박스 추가" button.
 */
export async function clickAddBox(page: Page) {
  // "+ 박스 추가" button is at top-right, approximately (530, 47)
  await page.mouse.click(530, 47);
  await page.waitForTimeout(800);
}

/**
 * In the add-box dialog, select a camping preset category.
 */
export async function selectPresetCategory(page: Page, categoryName: string) {
  // Categories are shown as chips/tabs in the dialog
  // "4인 가족 캠핑" is a common preset
  // Dialog is centered at viewport, category buttons near top of dialog
  // We'll click based on the category position in dialog
  const categoryMap: Record<string, { x: number; y: number }> = {
    '4인 가족 캠핑': { x: 500, y: 370 },
    '2인 미니멀': { x: 640, y: 370 },
    '솔로 캠핑': { x: 750, y: 370 },
  };

  const pos = categoryMap[categoryName] || { x: 500, y: 370 };
  await page.mouse.click(pos.x, pos.y);
  await page.waitForTimeout(500);
}

/**
 * Click "자동 배치" button to open auto-layout dialog.
 */
export async function clickAutoLayout(page: Page) {
  // "자동 배치" button is at bottom-right of screen
  // Based on screenshots: approximately (590, 490) or find blue button
  // Looking at screenshot 30: button is at bottom right area
  await page.mouse.click(600, 495);
  await page.waitForTimeout(1000);
}

/**
 * In auto-layout dialog, select strategy and apply.
 */
export async function applyAutoLayout(page: Page, strategy: '균형 배치' | '최대 적재' | '접근 우선' = '균형 배치') {
  // Strategy options in dialog:
  // 균형 배치 is first (default selected), at about y=230 from dialog top
  // 최대 적재 is second
  // 접근 우선 is third
  // "적용" toggle/button is at bottom of dialog

  // The dialog is centered. Based on screenshot 30:
  // Dialog center ~(400, 360)
  // Strategy radios are in the dialog body
  const strategyMap: Record<string, number> = {
    '균형 배치': 300,
    '최대 적재': 355,
    '접근 우선': 410,
  };

  const yPos = strategyMap[strategy] || 300;
  await page.mouse.click(400, yPos);
  await page.waitForTimeout(500);

  // Click the apply toggle (blue toggle at bottom-right of dialog)
  await page.mouse.click(470, 465);
  await page.waitForTimeout(1500);
}

/**
 * Click "들어갈까?" quick check button.
 */
export async function clickQuickCheck(page: Page) {
  // "들어갈까?" button - green button at bottom right
  await page.mouse.click(510, 495);
  await page.waitForTimeout(1000);
}

/**
 * Close any dialog by pressing Escape.
 */
export async function closeDialog(page: Page) {
  await page.keyboard.press('Escape');
  await page.waitForTimeout(500);
}

/**
 * Take a full-page screenshot and return as buffer.
 */
export async function takeScreenshot(page: Page): Promise<Buffer> {
  return await page.screenshot({ fullPage: false }) as Buffer;
}
