import { defineConfig } from '@playwright/test';

/**
 * 실행: `flutter build web` 후 `npx playwright test`
 * build/web 을 정적 서버로 띄워 스모크 테스트를 돌린다.
 */
export default defineConfig({
  testDir: './e2e',
  testMatch: /.*\.spec\.ts/,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  timeout: 60000,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
  webServer: {
    command: 'npx http-server build/web -p 8080 -c-1 --silent',
    port: 8080,
    reuseExistingServer: !process.env.CI,
    timeout: 15000,
  },
});
