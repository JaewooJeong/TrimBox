import { test, expect, Page } from '@playwright/test';

/**
 * 스모크 테스트 — 핵심 플로우가 실제 웹 빌드에서 에러 없이 동작하는지.
 *
 * Flutter 웹은 캔버스에 그리므로 DOM 텍스트가 없다. 그래서 고정 뷰포트에서
 * 좌표로 조작하고, (1) 페이지 에러가 없고 (2) 스크린샷이 남는 것을 확인한다.
 * 스크린샷은 e2e/screenshots/ 에 저장되며 사람이 훑어본다.
 *
 * 사전 조건: `flutter build web` 결과가 build/web 에 있어야 한다.
 * 좌표는 1280×960(데스크톱), 390×844(모바일) 기준이며 레이아웃이 바뀌면 갱신한다.
 */

const SHOTS = 'e2e/screenshots';

async function waitForApp(page: Page) {
  await page.goto('/', { waitUntil: 'networkidle' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 30000 });
  await page.waitForTimeout(2500); // 첫 프레임 + 폴백 폰트
}

function collectErrors(page: Page) {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push('console: ' + m.text());
  });
  return errors;
}

async function drag(page: Page, x0: number, y0: number, x1: number, y1: number, steps = 12) {
  await page.mouse.move(x0, y0);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) {
    await page.mouse.move(x0 + ((x1 - x0) * i) / steps, y0 + ((y1 - y0) * i) / steps);
    await page.waitForTimeout(20);
  }
  await page.mouse.up();
  await page.waitForTimeout(400);
}

// 데스크톱 1280×960 좌표
const D = {
  onboarding: [460, 480],
  cta: [1097, 597], // 캠핑 장비 선택하기
  bundleFamily: [608, 430], // 4인 가족 캠핑 카드
  bundleSolo: [778, 430], // 솔로 백패킹 카드
  dialogAdd: [790, 744], // 추가
  quickCheck: [1029, 773], // 들어갈까? (통계 영역의 상태 행 1줄 포함)
  autoLayout: [1180, 773], // 자동 배치
  preset: [230, 28], // 차종 드롭다운
  presetSorento7: [300, 122], // 메뉴: 쏘렌토 7인승·3열 접음 (헤더 + 2번째 항목)
  seatSlide: [450, 28], // 2열 슬라이드 드롭다운 (차종 드롭다운 오른쪽)
  seatSlideFront: [520, 150], // 메뉴 3번째 항목: 2열 최전방
} as const;

test.describe('데스크톱', () => {
  test.use({ viewport: { width: 1280, height: 960 } });

  test('4인 가족 세트 추가 → 자동 배치 → 판정 → 회전', async ({ page }) => {
    const errors = collectErrors(page);
    await waitForApp(page);
    await page.mouse.click(...D.onboarding);
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${SHOTS}/desktop-01-empty.png` });

    await page.mouse.click(...D.cta);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: `${SHOTS}/desktop-02-dialog.png` });
    await page.mouse.click(...D.bundleFamily);
    await page.waitForTimeout(500);
    await page.mouse.click(...D.dialogAdd);
    await page.waitForTimeout(5000);
    await page.screenshot({ path: `${SHOTS}/desktop-03-auto-packed.png` });

    await page.mouse.click(...D.quickCheck);
    await page.waitForTimeout(6000);
    await page.screenshot({ path: `${SHOTS}/desktop-04-verdict.png` });
    await page.keyboard.press('Escape');
    await page.waitForTimeout(500);

    await drag(page, 150, 150, 330, 230);
    await page.screenshot({ path: `${SHOTS}/desktop-05-orbit.png` });
    await page.keyboard.press('0');
    await page.waitForTimeout(300);

    // 박스 드래그 (화면 중앙 부근의 박스를 오른쪽으로)
    await drag(page, 640, 620, 760, 660);
    await page.screenshot({ path: `${SHOTS}/desktop-06-after-drag.png` });
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(400);

    expect(errors, errors.join('\n')).toEqual([]);
  });

  test('테일게이트 닫힘 검사: 짐을 뒤로 밀면 경고, 2열 슬라이드·7인승 전환', async ({ page }) => {
    const errors = collectErrors(page);
    await waitForApp(page);
    await page.mouse.click(...D.onboarding);
    await page.waitForTimeout(400);
    await page.mouse.click(...D.cta);
    await page.waitForTimeout(1200);
    await page.mouse.click(...D.bundleFamily);
    await page.waitForTimeout(500);
    await page.mouse.click(...D.dialogAdd);
    await page.waitForTimeout(5000);

    // 위쪽에 놓인 박스를 클릭해 선택하고 화살표로 테일게이트 쪽(z+)으로 민다
    await page.mouse.click(417, 390);
    await page.waitForTimeout(300);
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press('ArrowDown');
      await page.waitForTimeout(15);
    }
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${SHOTS}/desktop-08-tailgate-blocked.png` });
    await drag(page, 150, 150, 330, 230);
    await page.screenshot({ path: `${SHOTS}/desktop-09-tailgate-blocked-orbit.png` });
    await page.keyboard.press('0');
    await page.waitForTimeout(300);

    // 2열 슬라이드 메뉴 → 최전방
    await page.mouse.click(...D.seatSlide);
    await page.waitForTimeout(600);
    await page.screenshot({ path: `${SHOTS}/desktop-10-seat-slide-menu.png` });
    await page.mouse.click(...D.seatSlideFront);
    await page.waitForTimeout(3000);
    await page.screenshot({ path: `${SHOTS}/desktop-11-seat-slide-front.png` });

    // 7인승(3열 접음) 프리셋
    await page.mouse.click(...D.preset);
    await page.waitForTimeout(600);
    await page.screenshot({ path: `${SHOTS}/desktop-12-preset-menu.png` });
    await page.mouse.click(...D.presetSorento7);
    await page.waitForTimeout(2500);
    await page.screenshot({ path: `${SHOTS}/desktop-13-sorento7.png` });

    expect(errors, errors.join('\n')).toEqual([]);
  });

  test('새로고침 후에도 에러 없이 복원된다', async ({ page }) => {
    const errors = collectErrors(page);
    await waitForApp(page);
    await page.mouse.click(...D.onboarding);
    await page.waitForTimeout(400);
    await page.mouse.click(...D.cta);
    await page.waitForTimeout(1200);
    await page.mouse.click(...D.bundleSolo);
    await page.waitForTimeout(500);
    await page.mouse.click(...D.dialogAdd);
    await page.waitForTimeout(2500);

    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(3500);
    await page.screenshot({ path: `${SHOTS}/desktop-07-restored.png` });
    expect(errors, errors.join('\n')).toEqual([]);
  });
});

// 모바일 390×844 좌표
const M = {
  onboarding: [195, 300],
  cta: [195, 787], // 캠핑 장비 선택하기 (시트 안)
} as const;

test.describe('모바일', () => {
  test.use({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    deviceScaleFactor: 2,
  });

  test('빈 트렁크 → 장비 다이얼로그가 열린다', async ({ page }) => {
    const errors = collectErrors(page);
    await waitForApp(page);
    await page.mouse.click(...M.onboarding);
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${SHOTS}/mobile-01-empty.png` });
    await page.mouse.click(...M.cta);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: `${SHOTS}/mobile-02-dialog.png` });
    expect(errors, errors.join('\n')).toEqual([]);
  });
});
