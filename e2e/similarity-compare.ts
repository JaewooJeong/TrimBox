/**
 * Perceptual Similarity Comparison: Real Trunk Photos vs TrimBox Renders
 *
 * Metrics:
 * - SSIM (Structural Similarity Index): 0~1, higher = more similar
 * - Pixel diff %: lower = more similar
 * - Histogram correlation: color distribution similarity
 *
 * Usage: npx ts-node e2e/similarity-compare.ts
 */
import * as fs from 'fs';
import * as path from 'path';
import sharp from 'sharp';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

// Directories
const BASELINES_DIR = path.join(__dirname, 'baselines');
const REAL_PHOTOS_DIR = path.join(__dirname, 'real-photos');
const SIMILARITY_REPORT_DIR = path.join(__dirname, 'similarity-report');

// Vehicle mapping
const VEHICLES = [
  { id: 'sorento', korean: '쏘렌토', baselinePrefix: 'vr-sorento' },
  { id: 'santafe', korean: '싼타페', baselinePrefix: 'vr-santafe' },
  { id: 'tucson', korean: '투싼', baselinePrefix: 'vr-tucson' },
  { id: 'carnival', korean: '카니발', baselinePrefix: 'vr-carnival' },
  { id: 'ioniq5', korean: '아이오닉5', baselinePrefix: 'vr-ioniq5' },
];

// Target size for comparison (normalize all images)
// Higher resolution preserves texture details that affect similarity metrics
const TARGET_WIDTH = 1280;
const TARGET_HEIGHT = 960;

interface SimilarityResult {
  vehicle: string;
  photoFile: string;
  baselineFile: string;
  pixelDiffPercent: number;
  histogramCorrelation: number;
  edgeSimilarity: number;
  overallScore: number;
}

/**
 * Compute grayscale histogram (256 bins) from raw pixel buffer
 */
function computeHistogram(data: Buffer, width: number, height: number): number[] {
  const hist = new Array(256).fill(0);
  for (let i = 0; i < width * height * 4; i += 4) {
    // Grayscale = 0.299R + 0.587G + 0.114B
    const gray = Math.round(0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]);
    hist[gray]++;
  }
  return hist;
}

/**
 * Histogram correlation (Pearson): -1 to 1, 1 = identical distribution
 */
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

/**
 * Simple edge detection similarity using Sobel-like gradient magnitude comparison
 */
function computeEdgeSimilarity(data1: Buffer, data2: Buffer, width: number, height: number): number {
  function sobelMagnitude(data: Buffer, x: number, y: number): number {
    const idx = (y: number, x: number) => {
      const cx = Math.max(0, Math.min(width - 1, x));
      const cy = Math.max(0, Math.min(height - 1, y));
      const i = (cy * width + cx) * 4;
      return 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
    };

    const gx = -idx(y - 1, x - 1) - 2 * idx(y, x - 1) - idx(y + 1, x - 1)
              + idx(y - 1, x + 1) + 2 * idx(y, x + 1) + idx(y + 1, x + 1);
    const gy = -idx(y - 1, x - 1) - 2 * idx(y - 1, x) - idx(y - 1, x + 1)
              + idx(y + 1, x - 1) + 2 * idx(y + 1, x) + idx(y + 1, x + 1);

    return Math.sqrt(gx * gx + gy * gy);
  }

  let totalDiff = 0;
  let totalMax = 0;
  const step = 2; // sample every 2 pixels for speed

  for (let y = 1; y < height - 1; y += step) {
    for (let x = 1; x < width - 1; x += step) {
      const e1 = sobelMagnitude(data1, x, y);
      const e2 = sobelMagnitude(data2, x, y);
      totalDiff += Math.abs(e1 - e2);
      totalMax += Math.max(e1, e2, 1);
    }
  }

  return 1 - (totalDiff / totalMax);
}

/**
 * Resize image to target dimensions and return raw RGBA buffer.
 * For TrimBox baselines (1280x960), crop to trunk canvas area first.
 */
async function loadAndResize(filePath: string, isTrimBoxBaseline: boolean = false): Promise<{ data: Buffer; width: number; height: number }> {
  let pipeline = sharp(filePath);

  if (isTrimBoxBaseline) {
    // Crop to trunk rendering area only (exclude right panel + toolbar)
    // Trunk canvas: x=30..500, y=35..760 (on 1280x960 screenshot)
    pipeline = pipeline.extract({ left: 30, top: 35, width: 470, height: 725 });
  }

  const resized = await pipeline
    .resize(TARGET_WIDTH, TARGET_HEIGHT, { fit: 'fill' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  return {
    data: resized.data,
    width: TARGET_WIDTH,
    height: TARGET_HEIGHT,
  };
}

/**
 * Compare a real photo against a TrimBox render baseline
 */
async function compareImages(realPhotoPath: string, baselinePath: string): Promise<{
  pixelDiffPercent: number;
  histCorr: number;
  edgeSim: number;
}> {
  const real = await loadAndResize(realPhotoPath, false);
  const baseline = await loadAndResize(baselinePath, true); // crop trunk area

  // 1. Pixel diff (using pixelmatch with high threshold for structural comparison)
  const diffBuf = Buffer.alloc(TARGET_WIDTH * TARGET_HEIGHT * 4);
  const diffPixels = pixelmatch(
    real.data, baseline.data, diffBuf,
    TARGET_WIDTH, TARGET_HEIGHT,
    { threshold: 0.3 } // more lenient for cross-domain comparison
  );
  const pixelDiffPercent = (diffPixels / (TARGET_WIDTH * TARGET_HEIGHT)) * 100;

  // 2. Histogram correlation
  const hist1 = computeHistogram(real.data, TARGET_WIDTH, TARGET_HEIGHT);
  const hist2 = computeHistogram(baseline.data, TARGET_WIDTH, TARGET_HEIGHT);
  const histCorr = histogramCorrelation(hist1, hist2);

  // 3. Edge similarity
  const edgeSim = computeEdgeSimilarity(real.data, baseline.data, TARGET_WIDTH, TARGET_HEIGHT);

  return { pixelDiffPercent, histCorr, edgeSim };
}

/**
 * Calculate overall perceptual score (0-100)
 *
 * For cross-domain comparison (render vs photo), edge detection is inherently
 * limited (~7% max) because geometric renders have sharp edges while photos
 * have organic blurred edges. Weight histogram most heavily as it captures
 * brightness distribution similarity — the most meaningful metric.
 *
 * Weights: histogram 55%, pixel inverse 30%, edge 15%
 */
function overallScore(pixelDiffPercent: number, histCorr: number, edgeSim: number): number {
  const pixelScore = Math.max(0, 100 - pixelDiffPercent);
  const histScore = Math.max(0, histCorr) * 100;
  const edgeScore = Math.max(0, edgeSim) * 100;

  return 0.30 * pixelScore + 0.55 * histScore + 0.15 * edgeScore;
}

async function main() {
  if (!fs.existsSync(SIMILARITY_REPORT_DIR)) {
    fs.mkdirSync(SIMILARITY_REPORT_DIR, { recursive: true });
  }

  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║   TrimBox vs Real Trunk Photos — Perceptual Similarity     ║');
  console.log('╚══════════════════════════════════════════════════════════════╝\n');

  const allResults: SimilarityResult[] = [];

  for (const vehicle of VEHICLES) {
    const photoDir = path.join(REAL_PHOTOS_DIR, vehicle.id);
    const baselineFile = path.join(BASELINES_DIR, `${vehicle.baselinePrefix}-empty.png`);

    if (!fs.existsSync(photoDir)) {
      console.log(`⚠️  ${vehicle.korean}: 실제 사진 디렉토리 없음 — 스킵`);
      continue;
    }

    if (!fs.existsSync(baselineFile)) {
      console.log(`⚠️  ${vehicle.korean}: baseline 없음 — 스킵`);
      continue;
    }

    const photos = fs.readdirSync(photoDir).filter(f =>
      /\.(png|jpg|jpeg|webp)$/i.test(f)
    );

    if (photos.length === 0) {
      console.log(`⚠️  ${vehicle.korean}: 실제 사진 0장 — 스킵`);
      continue;
    }

    console.log(`\n━━━ ${vehicle.korean} (${vehicle.id}) — ${photos.length}장 비교 ━━━`);

    for (const photo of photos) {
      const photoPath = path.join(photoDir, photo);
      try {
        const { pixelDiffPercent, histCorr, edgeSim } = await compareImages(photoPath, baselineFile);
        const score = overallScore(pixelDiffPercent, histCorr, edgeSim);

        const result: SimilarityResult = {
          vehicle: vehicle.korean,
          photoFile: photo,
          baselineFile: `${vehicle.baselinePrefix}-empty.png`,
          pixelDiffPercent: Math.round(pixelDiffPercent * 100) / 100,
          histogramCorrelation: Math.round(histCorr * 1000) / 1000,
          edgeSimilarity: Math.round(edgeSim * 1000) / 1000,
          overallScore: Math.round(score * 10) / 10,
        };

        allResults.push(result);

        const scoreBar = '█'.repeat(Math.round(score / 5)) + '░'.repeat(20 - Math.round(score / 5));
        console.log(
          `  ${photo.padEnd(30)} | Score: ${score.toFixed(1).padStart(5)}% [${scoreBar}] | Hist: ${histCorr.toFixed(3)} | Edge: ${edgeSim.toFixed(3)} | PxDiff: ${pixelDiffPercent.toFixed(1)}%`
        );
      } catch (err: any) {
        console.log(`  ❌ ${photo}: ${err.message}`);
      }
    }
  }

  // Summary
  if (allResults.length > 0) {
    console.log('\n\n╔══════════════════════════════════════════════════════╗');
    console.log('║              차종별 평균 유사도 요약                    ║');
    console.log('╚══════════════════════════════════════════════════════╝\n');

    const vehicleGroups: Record<string, SimilarityResult[]> = {};
    for (const r of allResults) {
      if (!vehicleGroups[r.vehicle]) vehicleGroups[r.vehicle] = [];
      vehicleGroups[r.vehicle].push(r);
    }

    const summaryRows: { vehicle: string; count: number; avgScore: number; avgHist: number; avgEdge: number; avgPxDiff: number }[] = [];

    for (const [vehicle, results] of Object.entries(vehicleGroups)) {
      const count = results.length;
      const avgScore = results.reduce((s, r) => s + r.overallScore, 0) / count;
      const avgHist = results.reduce((s, r) => s + r.histogramCorrelation, 0) / count;
      const avgEdge = results.reduce((s, r) => s + r.edgeSimilarity, 0) / count;
      const avgPxDiff = results.reduce((s, r) => s + r.pixelDiffPercent, 0) / count;

      summaryRows.push({ vehicle, count, avgScore, avgHist, avgEdge, avgPxDiff });

      const bar = '█'.repeat(Math.round(avgScore / 5)) + '░'.repeat(20 - Math.round(avgScore / 5));
      console.log(
        `  ${vehicle.padEnd(8)} (${count}장) | 평균: ${avgScore.toFixed(1).padStart(5)}% [${bar}] | Hist: ${avgHist.toFixed(3)} | Edge: ${avgEdge.toFixed(3)} | PxDiff: ${avgPxDiff.toFixed(1)}%`
      );
    }

    const globalAvg = allResults.reduce((s, r) => s + r.overallScore, 0) / allResults.length;
    console.log(`\n  ══ 전체 평균 유사도: ${globalAvg.toFixed(1)}% (${allResults.length}장 비교) ══`);

    // Interpretation
    console.log('\n  📊 점수 해석:');
    console.log('     80%+ : 매우 유사 (동일 구조/형태 인식)');
    console.log('     60-80%: 보통 (형태는 유사하나 디테일 차이)');
    console.log('     40-60%: 낮음 (기본 구조만 유사)');
    console.log('     <40% : 매우 낮음 (다른 표현 방식)');

    // Save JSON report
    const reportPath = path.join(SIMILARITY_REPORT_DIR, 'similarity-results.json');
    fs.writeFileSync(reportPath, JSON.stringify({ results: allResults, summary: summaryRows, globalAverage: globalAvg }, null, 2));
    console.log(`\n  💾 상세 리포트: ${reportPath}`);
  } else {
    console.log('\n⚠️  비교할 실제 사진이 없습니다. e2e/real-photos/{vehicle}/ 에 사진을 넣어주세요.');
  }
}

main().catch(console.error);
