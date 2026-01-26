import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright configuration for integration tests
 *
 * These tests run against real backend services (MCP server, REST server, Coordinator)
 * Unlike E2E tests which use MSW mocks, integration tests verify the full system behavior.
 *
 * Prerequisites:
 *   1. Build the project: swift build -c release
 *   2. Run setup: ./e2e/integration/setup/setup-integration-env.sh
 *   3. Services should be running (started by setup script)
 *
 * Usage:
 *   npx playwright test --config=e2e/integration/playwright.integration.config.ts
 */
export default defineConfig({
  testDir: './',
  fullyParallel: false, // Integration tests should run sequentially
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1, // Single worker for integration tests
  reporter: [
    ['html', { outputFolder: '../../playwright-report-integration' }],
    ['list'],
  ],
  timeout: 60_000, // Longer timeout for integration tests
  use: {
    // Connect to the real backend
    baseURL: process.env.INTEGRATION_WEB_URL || 'http://localhost:5173',
    trace: 'on',
    screenshot: 'on',
    video: 'on',
  },
  projects: [
    {
      name: 'integration',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // No webServer config - services should be started externally by setup script
})
