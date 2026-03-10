import { test, expect } from '@playwright/test';
import { compareScreenshot } from './helpers/visual-compare';

/**
 * 6개 차종 Visual Regression 테스트
 * 차종별 3가지 상태를 캡처하여 baseline과 비교:
 *   1. 빈 트렁크 (empty)
 *   2. 장비 추가 후 (items-loaded)
 *   3. 자동 배치 적용 후 (auto-layout)
 *
 * 총 18개 golden screenshots = 6 vehicles × 3 states
 */

const LOAD_TIMEOUT = 3000;
const RENDER_WAIT = 1500;

// Vehicle dropdown positions (index-based, 48px per item)
const VEHICLES = [
  { name: '투싼',     dropdownIndex: 1 },
  { name: '쏘렌토',   dropdownIndex: 2 },
  { name: '싼타페',   dropdownIndex: 3 },
  { name: '카니발',   dropdownIndex: 4 },
  { name: '아이오닉5', dropdownIndex: 5 },
  { name: '아반떼',   dropdownIndex: 6 },
] as const;

// Dropdown click coordinates
const DROPDOWN_X = 185;
const DROPDOWN_Y = 27;
const DROPDOWN_ITEM_HEIGHT = 48;

// UI button coordinates (from existing test patterns)
const OVERLAY_DISMISS = { x: 460, y: 480 };
const CAMPING_PRESET_BTN = { x: 1097, y: 597 };
const PRESET_4PERSON = { x: 608, y: 430 };
const ADD_BTN = { x: 790, y: 744 };
const AUTO_LAYOUT_BTN = { x: 1155, y: 561 };
const STRATEGY_MAX_LOAD = { x: 500, y: 447 };
const APPLY_BTN = { x: 783, y: 667 };
const VERDICT_CLOSE = { x: 608, y: 625 };

async function initApp(page: import('@playwright/test').Page) {
  await page.goto('/', { waitUntil: 'networkidle' });
  await page.waitForTimeout(LOAD_TIMEOUT);
  // Dismiss overlay
  await page.mouse.click(OVERLAY_DISMISS.x, OVERLAY_DISMISS.y);
  await page.waitForTimeout(1000);
}

async function selectVehicle(page: import('@playwright/test').Page, dropdownIndex: number) {
  // Open dropdown
  await page.mouse.click(DROPDOWN_X, DROPDOWN_Y);
  await page.waitForTimeout(500);
  // Select vehicle
  await page.mouse.click(DROPDOWN_X, DROPDOWN_Y + dropdownIndex * DROPDOWN_ITEM_HEIGHT);
  await page.waitForTimeout(RENDER_WAIT);
}

async function addCampingPreset(page: import('@playwright/test').Page) {
  // Open camping preset dialog
  await page.mouse.click(CAMPING_PRESET_BTN.x, CAMPING_PRESET_BTN.y);
  await page.waitForTimeout(1500);
  // Select "4인 가족 캠핑"
  await page.mouse.click(PRESET_4PERSON.x, PRESET_4PERSON.y);
  await page.waitForTimeout(1000);
  // Click "추가"
  await page.mouse.click(ADD_BTN.x, ADD_BTN.y);
  await page.waitForTimeout(2000);
}

async function applyAutoLayout(page: import('@playwright/test').Page) {
  // Open auto-layout dialog
  await page.mouse.click(AUTO_LAYOUT_BTN.x, AUTO_LAYOUT_BTN.y);
  await page.waitForTimeout(2000);
  // Select "최대 적재" strategy
  await page.mouse.click(STRATEGY_MAX_LOAD.x, STRATEGY_MAX_LOAD.y);
  await page.waitForTimeout(500);
  // Apply
  await page.mouse.click(APPLY_BTN.x, APPLY_BTN.y);
  await page.waitForTimeout(2000);
  // Close verdict dialog
  await page.mouse.click(VERDICT_CLOSE.x, VERDICT_CLOSE.y);
  await page.waitForTimeout(RENDER_WAIT);
}

function screenshotName(vehicleName: string, state: string): string {
  // Romanize vehicle names for file names
  const nameMap: Record<string, string> = {
    '투싼': 'tucson',
    '쏘렌토': 'sorento',
    '싼타페': 'santafe',
    '카니발': 'carnival',
    '아이오닉5': 'ioniq5',
    '아반떼': 'avante',
  };
  return `vr-${nameMap[vehicleName] || vehicleName}-${state}`;
}

// Generate tests for each vehicle
for (const vehicle of VEHICLES) {
  test.describe(`차종 렌더링 회귀 — ${vehicle.name}`, () => {

    test(`${vehicle.name}: 빈 트렁크`, async ({ page }) => {
      await initApp(page);

      // Default is 쏘렌토 (index 2), switch if different
      if (vehicle.dropdownIndex !== 2) {
        await selectVehicle(page, vehicle.dropdownIndex);
      }

      const buf = await page.screenshot({ type: 'png' }) as Buffer;
      const name = screenshotName(vehicle.name, 'empty');
      const result = compareScreenshot(buf, name, 0.1, 2.0);
      expect(result.match, `${vehicle.name} 빈 트렁크 diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
    });

    test(`${vehicle.name}: 장비 적재 후`, async ({ page }) => {
      await initApp(page);

      if (vehicle.dropdownIndex !== 2) {
        await selectVehicle(page, vehicle.dropdownIndex);
      }

      await addCampingPreset(page);

      const buf = await page.screenshot({ type: 'png' }) as Buffer;
      const name = screenshotName(vehicle.name, 'items-loaded');
      const result = compareScreenshot(buf, name, 0.1, 3.0);
      expect(result.match, `${vehicle.name} 장비 적재 diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
    });

    test(`${vehicle.name}: 자동 배치 적용`, async ({ page }) => {
      await initApp(page);

      if (vehicle.dropdownIndex !== 2) {
        await selectVehicle(page, vehicle.dropdownIndex);
      }

      await addCampingPreset(page);
      await applyAutoLayout(page);

      const buf = await page.screenshot({ type: 'png' }) as Buffer;
      const name = screenshotName(vehicle.name, 'auto-layout');
      const result = compareScreenshot(buf, name, 0.1, 3.0);
      expect(result.match, `${vehicle.name} 자동 배치 diff: ${result.diffPercent.toFixed(2)}%`).toBe(true);
    });
  });
}
