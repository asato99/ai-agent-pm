import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright configuration for experiment tests
 *
 * Experiments reuse pilot infrastructure (lib/, tests/) via symlinks
 * but have independent scenarios, results, and generated directories.
 *
 * Usage:
 *   PILOT_SCENARIO="hello-world" \
 *   PILOT_VARIATION="baseline" \
 *   PILOT_BASE_DIR="path/to/experiments" \
 *   npx playwright test --config=experiments/playwright.experiment.config.ts
 */
export default defineConfig({
  testDir: './tests',
  outputDir: '../../test-results/experiments',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 0,
  workers: 1,
  reporter: [
    ['html', { outputFolder: '../../playwright-report-experiments' }],
    ['list'],
  ],
  timeout: 60 * 60 * 1000,
  use: {
    baseURL: process.env.PILOT_WEB_URL || 'http://localhost:5173',
    trace: 'on',
    screenshot: 'on',
    video: process.env.PILOT_RECORD === 'true' ? 'on' : 'off',
    launchOptions: {
      slowMo: process.env.PILOT_SLOW_MO ? parseInt(process.env.PILOT_SLOW_MO) : 0,
    },
    headless: process.env.PILOT_HEADED !== 'true',
  },
  projects: [
    {
      name: 'experiment',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
