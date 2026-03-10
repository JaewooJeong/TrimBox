import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import * as fs from 'fs';
import * as path from 'path';

export interface CompareResult {
  match: boolean;
  diffPixels: number;
  totalPixels: number;
  diffPercent: number;
  diffImagePath: string | null;
}

const BASELINES_DIR = path.join(__dirname, '..', 'baselines');
const DIFFS_DIR = path.join(__dirname, '..', 'diffs');
const ACTUALS_DIR = path.join(__dirname, '..', 'actuals');

export function ensureDirs() {
  for (const dir of [BASELINES_DIR, DIFFS_DIR, ACTUALS_DIR]) {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Compare a screenshot buffer against a baseline image.
 * If no baseline exists, saves the current screenshot as the new baseline.
 * Returns comparison result.
 */
export function compareScreenshot(
  screenshotBuffer: Buffer,
  name: string,
  threshold: number = 0.1,
  maxDiffPercent: number = 1.0
): CompareResult {
  ensureDirs();

  const baselinePath = path.join(BASELINES_DIR, `${name}.png`);
  const actualPath = path.join(ACTUALS_DIR, `${name}.png`);
  const diffPath = path.join(DIFFS_DIR, `${name}-diff.png`);

  // Always save actual
  fs.writeFileSync(actualPath, screenshotBuffer);

  // If no baseline, create it and pass
  if (!fs.existsSync(baselinePath)) {
    fs.writeFileSync(baselinePath, screenshotBuffer);
    console.log(`[BASELINE CREATED] ${name}.png — first run, saved as baseline`);
    return {
      match: true,
      diffPixels: 0,
      totalPixels: 0,
      diffPercent: 0,
      diffImagePath: null,
    };
  }

  // Load baseline and actual
  const baseline = PNG.sync.read(fs.readFileSync(baselinePath));
  const actual = PNG.sync.read(screenshotBuffer);

  // Handle size mismatch
  if (baseline.width !== actual.width || baseline.height !== actual.height) {
    console.error(
      `[SIZE MISMATCH] ${name}: baseline=${baseline.width}x${baseline.height} actual=${actual.width}x${actual.height}`
    );
    return {
      match: false,
      diffPixels: -1,
      totalPixels: baseline.width * baseline.height,
      diffPercent: 100,
      diffImagePath: null,
    };
  }

  const { width, height } = baseline;
  const diff = new PNG({ width, height });

  const diffPixels = pixelmatch(
    baseline.data,
    actual.data,
    diff.data,
    width,
    height,
    { threshold }
  );

  const totalPixels = width * height;
  const diffPercent = (diffPixels / totalPixels) * 100;
  const match = diffPercent <= maxDiffPercent;

  // Save diff image if there are differences
  if (diffPixels > 0) {
    fs.writeFileSync(diffPath, PNG.sync.write(diff));
  }

  console.log(
    `[${match ? 'PASS' : 'FAIL'}] ${name}: ${diffPercent.toFixed(2)}% diff (${diffPixels}/${totalPixels} pixels)`
  );

  return { match, diffPixels, totalPixels, diffPercent, diffImagePath: diffPixels > 0 ? diffPath : null };
}

/**
 * Update baseline from current actual screenshot.
 */
export function updateBaseline(name: string) {
  ensureDirs();
  const actualPath = path.join(ACTUALS_DIR, `${name}.png`);
  const baselinePath = path.join(BASELINES_DIR, `${name}.png`);

  if (fs.existsSync(actualPath)) {
    fs.copyFileSync(actualPath, baselinePath);
    console.log(`[BASELINE UPDATED] ${name}.png`);
  }
}
