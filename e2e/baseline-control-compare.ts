/**
 * Control Group: Real Photo vs Real Photo similarity
 *
 * Measures similarity between real trunk photos of the SAME vehicle
 * to establish a baseline for what "same subject, different photo" scores.
 * This gives context to the TrimBox vs Real Photo scores.
 *
 * Usage: npx tsx e2e/baseline-control-compare.ts
 */
import * as fs from 'fs';
import * as path from 'path';
import sharp from 'sharp';
import pixelmatch from 'pixelmatch';

const REAL_PHOTOS_DIR = path.join(__dirname, 'real-photos');
const TARGET_WIDTH = 1280;
const TARGET_HEIGHT = 960;

const VEHICLES = ['sorento', 'santafe', 'tucson', 'carnival', 'ioniq5'];
const VEHICLE_KOREAN: Record<string, string> = {
  sorento: '쏘렌토', santafe: '싼타페', tucson: '투싼',
  carnival: '카니발', ioniq5: '아이오닉5',
};

function computeHistogram(data: Buffer, width: number, height: number): number[] {
  const hist = new Array(256).fill(0);
  for (let i = 0; i < width * height * 4; i += 4) {
    const gray = Math.round(0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
    hist[gray]++;
  }
  return hist;
}

function histogramCorrelation(h1: number[], h2: number[]): number {
  const n = h1.length;
  const mean1 = h1.reduce((a, b) => a + b, 0) / n;
  const mean2 = h2.reduce((a, b) => a + b, 0) / n;
  let num = 0, den1 = 0, den2 = 0;
  for (let i = 0; i < n; i++) {
    const d1 = h1[i] - mean1;
    const d2 = h2[i] - mean2;
    num += d1 * d2;
    den1 += d1 * d1;
    den2 += d2 * d2;
  }
  const den = Math.sqrt(den1 * den2);
  return den === 0 ? 0 : num / den;
}

function computeEdgeSimilarity(data1: Buffer, data2: Buffer, width: number, height: number): number {
  function sobelMag(data: Buffer, x: number, y: number): number {
    const idx = (y: number, x: number) => {
      const cx = Math.max(0, Math.min(width - 1, x));
      const cy = Math.max(0, Math.min(height - 1, y));
      const i = (cy * width + cx) * 4;
      return 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    };
    const gx = -idx(y-1,x-1) - 2*idx(y,x-1) - idx(y+1,x-1) + idx(y-1,x+1) + 2*idx(y,x+1) + idx(y+1,x+1);
    const gy = -idx(y-1,x-1) - 2*idx(y-1,x) - idx(y-1,x+1) + idx(y+1,x-1) + 2*idx(y+1,x) + idx(y+1,x+1);
    return Math.sqrt(gx*gx + gy*gy);
  }
  let totalDiff = 0, totalMax = 0;
  for (let y = 1; y < height - 1; y += 2) {
    for (let x = 1; x < width - 1; x += 2) {
      const e1 = sobelMag(data1, x, y);
      const e2 = sobelMag(data2, x, y);
      totalDiff += Math.abs(e1 - e2);
      totalMax += Math.max(e1, e2, 1);
    }
  }
  return 1 - (totalDiff / totalMax);
}

async function loadImage(filePath: string): Promise<Buffer> {
  const { data } = await sharp(filePath)
    .resize(TARGET_WIDTH, TARGET_HEIGHT, { fit: 'fill' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return data;
}

function overallScore(pixelDiffPercent: number, histCorr: number, edgeSim: number): number {
  const pixelScore = Math.max(0, 100 - pixelDiffPercent);
  const histScore = Math.max(0, histCorr) * 100;
  const edgeScore = Math.max(0, edgeSim) * 100;
  // Cross-domain weights: histogram most important, edge least (inherently limited)
  return 0.30 * pixelScore + 0.55 * histScore + 0.15 * edgeScore;
}

async function main() {
  console.log('\n╔══════════════════════════════════════════════════════════════════╗');
  console.log('║  Control Group: Real Photo vs Real Photo (same vehicle)        ║');
  console.log('║  → 같은 차종 실사끼리의 유사도 = 우리 점수의 기준선              ║');
  console.log('╚══════════════════════════════════════════════════════════════════╝\n');

  const vehicleSummaries: { vehicle: string; avgScore: number; pairs: number }[] = [];

  for (const vehicleId of VEHICLES) {
    const photoDir = path.join(REAL_PHOTOS_DIR, vehicleId);
    if (!fs.existsSync(photoDir)) continue;

    const photos = fs.readdirSync(photoDir).filter(f => /\.(png|jpg|jpeg|webp)$/i.test(f));
    if (photos.length < 2) continue;

    console.log(`━━━ ${VEHICLE_KOREAN[vehicleId]} — 실사 vs 실사 (${photos.length}장 중 조합 비교) ━━━`);

    // Load all images
    const images: { name: string; data: Buffer }[] = [];
    for (const photo of photos) {
      try {
        const data = await loadImage(path.join(photoDir, photo));
        images.push({ name: photo, data });
      } catch { /* skip broken images */ }
    }

    // Compare all pairs (limit to first 10 images for speed)
    const subset = images.slice(0, 10);
    let totalScore = 0;
    let pairCount = 0;
    const scores: number[] = [];

    for (let i = 0; i < subset.length; i++) {
      for (let j = i + 1; j < subset.length; j++) {
        const diffPixels = pixelmatch(
          subset[i].data, subset[j].data, null,
          TARGET_WIDTH, TARGET_HEIGHT, { threshold: 0.3 }
        );
        const pxDiff = (diffPixels / (TARGET_WIDTH * TARGET_HEIGHT)) * 100;

        const h1 = computeHistogram(subset[i].data, TARGET_WIDTH, TARGET_HEIGHT);
        const h2 = computeHistogram(subset[j].data, TARGET_WIDTH, TARGET_HEIGHT);
        const histCorr = histogramCorrelation(h1, h2);

        const edgeSim = computeEdgeSimilarity(subset[i].data, subset[j].data, TARGET_WIDTH, TARGET_HEIGHT);
        const score = overallScore(pxDiff, histCorr, edgeSim);

        scores.push(score);
        totalScore += score;
        pairCount++;
      }
    }

    const avgScore = totalScore / pairCount;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);

    const bar = '█'.repeat(Math.round(avgScore / 5)) + '░'.repeat(20 - Math.round(avgScore / 5));
    console.log(`  ${pairCount}개 조합 비교`);
    console.log(`  평균: ${avgScore.toFixed(1)}% [${bar}]`);
    console.log(`  범위: ${minScore.toFixed(1)}% ~ ${maxScore.toFixed(1)}%\n`);

    vehicleSummaries.push({ vehicle: VEHICLE_KOREAN[vehicleId], avgScore, pairs: pairCount });
  }

  // Final comparison
  console.log('╔══════════════════════════════════════════════════════════════════╗');
  console.log('║                    기준선 vs TrimBox 비교                        ║');
  console.log('╚══════════════════════════════════════════════════════════════════╝\n');

  const globalAvg = vehicleSummaries.reduce((s, v) => s + v.avgScore, 0) / vehicleSummaries.length;
  console.log(`  실사 vs 실사 평균: ${globalAvg.toFixed(1)}%  ← 이것이 "같은 피사체" 기준선`);
  // Read latest TrimBox score from similarity report if available
  const reportPath = path.join(__dirname, 'similarity-report', 'similarity-results.json');
  let trimboxScore = 26.6;
  try {
    const report = JSON.parse(fs.readFileSync(reportPath, 'utf-8'));
    trimboxScore = Math.round(report.globalAverage * 10) / 10;
  } catch { /* use default */ }
  console.log(`  TrimBox vs 실사 평균: ${trimboxScore}%  ← 우리의 현재 점수`);
  console.log(`  달성률: ${((trimboxScore / globalAvg) * 100).toFixed(1)}% of 기준선\n`);

  console.log('  📊 해석:');
  console.log('     기준선이 100%가 아니라는 점이 핵심.');
  console.log('     실사끼리도 각도/조명 차이로 100%가 나오지 않음.');
  console.log('     TrimBox 점수를 기준선 대비 비율로 평가해야 의미있음.\n');
}

main().catch(console.error);
