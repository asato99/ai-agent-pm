import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright configuration for pilot tests
 *
 * Pilot tests run with real AI agents and real LLM API calls.
 * Unlike E2E tests which use MSW mocks, pilot tests verify actual AI-driven development.
 *
 * Key differences from integration tests:
 *   - Much longer timeouts (up to 60 minutes)
 *   - Always capture video, trace, and screenshots
 *   - Single worker, no retries
 *   - Support for observation mode (PILOT_SLOW_MO)
 *
 * Prerequisites:
 *   1. Build the project: swift build -c release
 *   2. Run: ./e2e/pilot/run-pilot-hello.sh
 *   3. LLM API keys must be configured
 *
 * Usage:
 *   PILOT_WEB_URL="http://localhost:5173" \
 *   PILOT_WITH_COORDINATOR="true" \
 *   npx playwright test --config=e2e/pilot/playwright.pilot.config.ts
 */
export default defineConfig({
  testDir: './tests',
  outputDir: '../../test-results/pilot', // Video and trace output
  fullyParallel: false, // Pilot tests must run sequentially
  forbidOnly: !!process.env.CI,
  retries: 0, // No retries - pilot tests should pass or fail definitively
  workers: 1, // Single worker for pilot tests
  reporter: [
    ['html', { outputFolder: '../../playwright-report-pilot' }],
    ['list'],
  ],
  // Pilot tests can run up to 60 minutes
  timeout: 60 * 60 * 1000,
  use: {
    // Connect to the real backend
    baseURL: process.env.PILOT_WEB_URL || 'http://localhost:5173',
    // Always capture for debugging and analysis
    trace: 'on',
    screenshot: 'on',
    video: 'on',
    // Support observation mode via PILOT_SLOW_MO environment variable
    // Support headed mode via PILOT_HEADED environment variable
    launchOptions: {
      slowMo: process.env.PILOT_SLOW_MO ? parseInt(process.env.PILOT_SLOW_MO) : 0,
    },
    headless: process.env.PILOT_HEADED !== 'true',
  },
  projects: [
    {
      name: 'pilot',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // No webServer config - services should be started externally by run script
})
