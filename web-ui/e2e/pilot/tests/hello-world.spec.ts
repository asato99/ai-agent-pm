import { test, expect } from '@playwright/test'
import { execSync } from 'child_process'
import * as fs from 'fs'
import * as path from 'path'
import {
  loginAsOwner,
  navigateToProject,
  sendRequirementToManager,
  waitForAllTasksComplete,
  waitForTasksCreated,
  getTaskStatuses,
  DEFAULT_PILOT_CONFIG,
  PilotConfig,
} from '../utils/pilot-helpers'
import { ProgressMonitor } from '../utils/progress-monitor'

/**
 * Pilot Test: hello-world scenario
 *
 * This test verifies that real AI agents can:
 * 1. Receive requirements from Owner (via chat)
 * 2. Create and assign tasks (Manager)
 * 3. Implement code (Worker-Dev)
 * 4. Verify the implementation (Worker-Review)
 *
 * The test script acts as Owner, operating the UI via Playwright.
 * All other agents are real AI using actual LLM API calls.
 *
 * Prerequisites:
 *   - Run: ./e2e/pilot/run-pilot-hello.sh
 *   - Coordinator must be running with real LLM access
 *   - API keys must be configured
 *
 * Reference: web-ui/e2e/pilot/scenarios/hello-world.md
 */

test.describe('Pilot: hello-world', () => {
  const PILOT_CONFIG: PilotConfig = {
    ...DEFAULT_PILOT_CONFIG,
    scenarioTimeout: 30 * 60 * 1000, // 30 minutes for full scenario
    phaseTimeout: 10 * 60 * 1000, // 10 minutes per phase
    taskTimeout: 5 * 60 * 1000, // 5 minutes per task
  }

  const CREDENTIALS = {
    agentId: 'pilot-owner',
    passkey: 'test-passkey',
  }

  const PROJECT = {
    id: 'pilot-hello',
    name: 'Hello World パイロット',
  }

  const WORKSPACE_PATH =
    process.env.PILOT_WORKSPACE_PATH || '/tmp/pilot_hello_workspace'

  const REQUIREMENT_MESSAGE = `「Hello, World!」を出力するPythonスクリプト hello.py を作成してください。
作成後、実行して動作確認も行ってください。`

  let monitor: ProgressMonitor

  test.beforeAll(async () => {
    // Ensure workspace directory exists and is clean
    if (fs.existsSync(WORKSPACE_PATH)) {
      fs.rmSync(WORKSPACE_PATH, { recursive: true })
    }
    fs.mkdirSync(WORKSPACE_PATH, { recursive: true })
    console.log(`[Pilot] Workspace prepared: ${WORKSPACE_PATH}`)
  })

  test.beforeEach(async () => {
    monitor = new ProgressMonitor()
  })

  test.afterEach(async () => {
    // Output progress report for analysis
    console.log(monitor.generateReport())
  })

  test.describe('Phase 1: Environment Verification', () => {
    test('Verify pilot agents and project exist', async ({ page }) => {
      // Login as Owner
      await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
      monitor.recordEvent('agent_started', { agent: 'pilot-owner', role: 'test-script' })

      // Verify project is visible in project list
      await expect(page.getByText(PROJECT.name)).toBeVisible()

      // Navigate to project
      await navigateToProject(page, PROJECT.id)

      // Verify initial state: no tasks yet
      const tasks = await getTaskStatuses(page)
      console.log(`[Pilot] Initial task count: ${tasks.length}`)

      // Note: Tasks may or may not exist depending on whether this is a fresh run
      // The important verification is that the project loads successfully
    })
  })

  test.describe('Phase 2: Requirements Delivery', () => {
    test('Send requirement to Manager via chat', async ({ page }) => {
      // Skip if not in pilot environment
      test.skip(
        !process.env.PILOT_WITH_COORDINATOR,
        'Requires pilot environment with Coordinator'
      )

      await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
      await navigateToProject(page, PROJECT.id)

      // Send requirement to Manager
      await sendRequirementToManager(
        page,
        'pilot-manager',
        REQUIREMENT_MESSAGE
      )

      monitor.recordEvent('chat_message', {
        from: 'pilot-owner',
        to: 'pilot-manager',
        message: REQUIREMENT_MESSAGE.substring(0, 50) + '...',
      })

      // Verify message was sent (appears in chat)
      const chatPanel = page.locator('[data-testid="chat-panel"]')
      await expect(chatPanel.getByText(/Hello, World!/)).toBeVisible()
    })
  })

  test.describe('Phase 3: AI Development Execution', () => {
    test('Wait for Manager to create tasks', async ({ page }) => {
      // Skip if not in pilot environment
      test.skip(
        !process.env.PILOT_WITH_COORDINATOR,
        'Requires pilot environment with Coordinator'
      )

      // Set timeout for this phase
      test.setTimeout(PILOT_CONFIG.phaseTimeout)

      await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
      await navigateToProject(page, PROJECT.id)

      console.log('[Pilot] Waiting for Manager to create tasks...')

      // Wait for at least 1 task to be created
      // Note: Ideally Manager creates 2 tasks (implementation + verification),
      // but AI behavior can vary. Accepting 1 task minimum to validate infrastructure.
      const result = await waitForTasksCreated(
        page,
        1,
        PILOT_CONFIG.phaseTimeout
      )

      if (result.success) {
        for (const task of result.tasks) {
          monitor.recordEvent('task_created', {
            id: task.id,
            title: task.title,
            status: task.status,
          })
        }
      }

      expect(result.success).toBe(true)
      expect(result.tasks.length).toBeGreaterThanOrEqual(1)
    })

    test('Wait for all tasks to complete', async ({ page }) => {
      // Skip if not in pilot environment
      test.skip(
        !process.env.PILOT_WITH_COORDINATOR,
        'Requires pilot environment with Coordinator'
      )

      // Set full scenario timeout
      test.setTimeout(PILOT_CONFIG.scenarioTimeout)

      await loginAsOwner(page, CREDENTIALS.agentId, CREDENTIALS.passkey)
      await navigateToProject(page, PROJECT.id)

      console.log('[Pilot] Waiting for AI agents to complete all tasks...')
      console.log('[Pilot] This may take 10-30 minutes')

      // Wait for all tasks to reach 'done' status
      const result = await waitForAllTasksComplete(page, PILOT_CONFIG)

      // Record final states
      for (const task of result.tasks) {
        monitor.recordEvent('status_change', {
          task: task.title || task.id,
          status: task.status,
        })
      }

      // Verify all tasks completed
      expect(result.success).toBe(true)

      // Check for loop detection
      if (monitor.detectLoop()) {
        monitor.recordEvent('warning', { message: 'Loop pattern detected' })
      }
    })
  })

  test.describe('Phase 4: Deliverable Verification', () => {
    test('Verify hello.py was created', async ({ page }) => {
      // Skip if not in pilot environment
      test.skip(
        !process.env.PILOT_WITH_COORDINATOR,
        'Requires pilot environment with Coordinator'
      )

      const helloPath = path.join(WORKSPACE_PATH, 'hello.py')

      // Check file exists
      expect(fs.existsSync(helloPath)).toBe(true)

      // Check file has content
      const content = fs.readFileSync(helloPath, 'utf-8')
      expect(content.length).toBeGreaterThan(0)

      // Check content contains expected elements
      expect(content).toContain('print')
      expect(content.toLowerCase()).toMatch(/hello.*world/i)

      console.log('[Pilot] hello.py content:')
      console.log(content)

      monitor.recordEvent('agent_completed', {
        agent: 'pilot-worker-dev',
        deliverable: 'hello.py',
      })
    })

    test('Verify hello.py outputs correct result', async ({ page }) => {
      // Skip if not in pilot environment
      test.skip(
        !process.env.PILOT_WITH_COORDINATOR,
        'Requires pilot environment with Coordinator'
      )

      const helloPath = path.join(WORKSPACE_PATH, 'hello.py')

      // Execute the Python script
      let output: string
      try {
        output = execSync(`python3 "${helloPath}"`, {
          encoding: 'utf-8',
          timeout: 10000,
        }).trim()
      } catch (error) {
        console.error('[Pilot] Execution error:', error)
        throw error
      }

      console.log(`[Pilot] Execution output: "${output}"`)

      // Verify output
      expect(output).toBe('Hello, World!')

      monitor.recordEvent('agent_completed', {
        agent: 'pilot-worker-review',
        verification: 'output matches expected',
      })

      console.log('[Pilot] ========================================')
      console.log('[Pilot] PILOT TEST PASSED')
      console.log('[Pilot] ========================================')
    })
  })
})
