/**
 * Standalone visual comparison runner.
 * Usage: npx ts-node e2e/compare-report.ts
 *
 * Compares all actuals against baselines and generates a diff report.
 */
import * as fs from 'fs';
import * as path from 'path';
import { compareScreenshot, ensureDirs } from './helpers/visual-compare';

const ACTUALS_DIR = path.join(__dirname, 'actuals');
const BASELINES_DIR = path.join(__dirname, 'baselines');

ensureDirs();

const actuals = fs.readdirSync(ACTUALS_DIR).filter(f => f.endsWith('.png'));
const baselines = fs.readdirSync(BASELINES_DIR).filter(f => f.endsWith('.png'));

console.log(`\n=== Visual Regression Report ===`);
console.log(`Actuals: ${actuals.length} | Baselines: ${baselines.length}\n`);

let passed = 0;
let failed = 0;
let newBaselines = 0;

for (const file of actuals) {
  const name = file.replace('.png', '');
  const actualBuf = fs.readFileSync(path.join(ACTUALS_DIR, file));
  const baselineExists = baselines.includes(file);

  if (!baselineExists) {
    console.log(`[NEW] ${name} — no baseline, saving as new`);
    fs.writeFileSync(path.join(BASELINES_DIR, file), actualBuf);
    newBaselines++;
    continue;
  }

  const result = compareScreenshot(actualBuf, name, 0.1, 2.0);
  if (result.match) {
    passed++;
  } else {
    failed++;
  }
}

console.log(`\n=== Summary ===`);
console.log(`Passed: ${passed} | Failed: ${failed} | New: ${newBaselines}`);
console.log(`Total: ${passed + failed + newBaselines}\n`);

if (failed > 0) {
  console.log(`Check e2e/diffs/ for diff images`);
  process.exit(1);
}
