/**
 * Download real trunk photos for similarity comparison.
 * Usage: npx ts-node e2e/download-trunk-photos.ts
 */
import * as fs from 'fs';
import * as path from 'path';
import * as https from 'https';
import * as http from 'http';

const REAL_PHOTOS_DIR = path.join(__dirname, 'real-photos');

interface VehiclePhotos {
  id: string;
  korean: string;
  urls: string[];
}

// These URLs will be populated from web search results
const VEHICLE_PHOTOS: VehiclePhotos[] = [
  {
    id: 'sorento',
    korean: '쏘렌토',
    urls: [], // Will be filled
  },
  {
    id: 'santafe',
    korean: '싼타페',
    urls: [],
  },
  {
    id: 'tucson',
    korean: '투싼',
    urls: [],
  },
  {
    id: 'carnival',
    korean: '카니발',
    urls: [],
  },
  {
    id: 'ioniq5',
    korean: '아이오닉5',
    urls: [],
  },
];

function downloadFile(url: string, dest: string): Promise<boolean> {
  return new Promise((resolve) => {
    const protocol = url.startsWith('https') ? https : http;
    const file = fs.createWriteStream(dest);

    const req = protocol.get(url, {
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept': 'image/*',
      }
    }, (response) => {
      // Follow redirects
      if (response.statusCode === 301 || response.statusCode === 302) {
        const redirectUrl = response.headers.location;
        if (redirectUrl) {
          file.close();
          fs.unlinkSync(dest);
          downloadFile(redirectUrl, dest).then(resolve);
          return;
        }
      }

      if (response.statusCode !== 200) {
        file.close();
        fs.unlinkSync(dest);
        resolve(false);
        return;
      }

      response.pipe(file);
      file.on('finish', () => {
        file.close();
        // Verify file is a valid image (at least 1KB)
        const stats = fs.statSync(dest);
        if (stats.size < 1024) {
          fs.unlinkSync(dest);
          resolve(false);
        } else {
          resolve(true);
        }
      });
    });

    req.on('error', () => {
      file.close();
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      resolve(false);
    });

    req.on('timeout', () => {
      req.destroy();
      file.close();
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      resolve(false);
    });
  });
}

async function main() {
  console.log('🚗 Downloading real trunk photos...\n');

  for (const vehicle of VEHICLE_PHOTOS) {
    const dir = path.join(REAL_PHOTOS_DIR, vehicle.id);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    if (vehicle.urls.length === 0) {
      console.log(`⚠️  ${vehicle.korean}: URL 목록 비어있음 — 스킵`);
      continue;
    }

    console.log(`📥 ${vehicle.korean} (${vehicle.urls.length} URLs)...`);
    let downloaded = 0;

    for (let i = 0; i < vehicle.urls.length; i++) {
      const url = vehicle.urls[i];
      const ext = url.match(/\.(png|jpg|jpeg|webp)/i)?.[1] || 'jpg';
      const dest = path.join(dir, `trunk-${String(i + 1).padStart(2, '0')}.${ext}`);

      const ok = await downloadFile(url, dest);
      if (ok) {
        downloaded++;
        console.log(`  ✅ ${i + 1}/${vehicle.urls.length}: trunk-${String(i + 1).padStart(2, '0')}.${ext}`);
      } else {
        console.log(`  ❌ ${i + 1}/${vehicle.urls.length}: 다운로드 실패`);
      }
    }

    console.log(`  → ${downloaded}/${vehicle.urls.length} 다운로드 완료\n`);
  }

  console.log('✅ 다운로드 완료! 이제 similarity-compare.ts를 실행하세요.');
}

main().catch(console.error);
