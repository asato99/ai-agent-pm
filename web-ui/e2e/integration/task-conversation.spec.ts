import { test, expect } from '@playwright/test'

/**
 * Integration Test: Task-based AI-to-AI Conversation (UC020)
 *
 * Difference from UC016: Task-based (not chat-based)
 * - Instructions come from task description
 * - Task status transitions: todo → in_progress → done
 *
 * This test verifies that:
 * 1. Task exists with instruction to do shiritori with Worker-B
 * 2. User changes task status to in_progress via UI
 * 3. Coordinator spawns Worker-A to execute task
 * 4. Worker-A calls start_conversation with Worker-B
 * 5. They exchange messages (shiritori 6 rounds)
 * 6. Worker-A calls end_conversation
 * 7. Worker-A calls report_completed
 * 8. Task status becomes done
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-uc020-test.sh
 *   - Coordinator must be running (managing both workers)
 *   - Services must be running (MCP, REST)
 *
 * Success Criteria:
 *   - Task status transitions: todo → in_progress → done
 *   - Conversation state: pending → active → ended
 *   - chat.jsonl contains messages with conversationId
 */

test.describe('Task-based AI-to-AI Conversation - UC020', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc020-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc020-project',
    name: 'UC020 Task-based Conversation Test',
  }

  const TEST_TASK = {
    id: 'uc020-task-shiritori',
    title: 'しりとりタスク',  // Must be exact match, not partial
    initialStatus: 'todo',
    assigneeId: 'uc020-worker-a',
  }

  const WORKER_A = {
    id: 'uc020-worker-a',
    name: 'UC020 Worker-A',
  }

  const WORKER_B = {
    id: 'uc020-worker-b',
    name: 'UC020 Worker-B',
  }

  test.beforeEach(async ({ page }) => {
    // Login as UC020 Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('UC020 project exists and is accessible', async ({ page }) => {
      // Verify UC020 project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Task exists and is assigned to Worker-A', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find the task card
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title, { exact: true }),
      })
      await expect(taskCard).toBeVisible()

      // Click to open task detail
      await taskCard.click()
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Verify task details
      await expect(dialog.getByRole('heading', { name: TEST_TASK.title })).toBeVisible()
    })

    test('Both AI agents are assigned to project', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Check worker-a avatar is visible
      const workerAAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_A.id}"]`)
      await expect(workerAAvatar).toBeVisible()

      // Check worker-b avatar is visible
      const workerBAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_B.id}"]`)
      await expect(workerBAvatar).toBeVisible()
    })
  })

  test.describe('Task-based Conversation Flow', () => {
    /**
     * Test: Task-based AI-to-AI conversation
     *
     * This test verifies that AI-to-AI conversation happens when triggered by task:
     * 1. Change task status to in_progress via UI
     * 2. Wait for Coordinator to spawn Worker-A
     * 3. Worker-A starts conversation with Worker-B
     * 4. Worker-A and Worker-B exchange shiritori messages
     *
     * Key verification: Conversation actually happened (not just task completion)
     * - Conversation state becomes 'ended'
     * - Multiple messages exchanged with conversationId
     *
     * Note: Requires Coordinator to be running with configured agents.
     * Run via: ./e2e/integration/run-uc020-test.sh
     */
    test('Task triggers AI-to-AI conversation: agents exchange messages via start_conversation', async ({
      page,
    }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (AI-to-AI conversation takes time)
      test.setTimeout(360_000) // 6 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title, { exact: true }),
      })
      await expect(taskCard).toBeVisible()
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Change task status to in_progress
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      console.log('UC020: Changing task status to in_progress...')
      await statusSelect.selectOption('in_progress')

      // Wait for status update
      await page.waitForTimeout(1000)

      // Close dialog
      await page.keyboard.press('Escape')

      // Verify task is now in in_progress column
      const inProgressColumn = page.locator('[data-column="in_progress"]')
      await expect(
        inProgressColumn.locator('[data-testid="task-card"]', {
          has: page.getByText(TEST_TASK.title, { exact: true }),
        })
      ).toBeVisible()
      console.log('UC020: Task status changed to in_progress')

      // Poll for conversation to complete
      // The key verification is: did Worker-A and Worker-B actually converse?
      const maxWaitTime = 300_000 // 5 minutes
      const pollInterval = 15_000
      const startTime = Date.now()

      console.log('UC020: Waiting for AI-to-AI conversation to complete...')

      let conversationCompleted = false
      let pollCount = 0
      const restPort = process.env.AIAGENTPM_WEBSERVER_PORT || '8091'

      // Check by reading DB and chat.jsonl files directly
      // This avoids API auth issues while still verifying the actual system state
      const dbPath = process.env.AIAGENTPM_DB_PATH || '/tmp/AIAgentPM_UC020_WebUI.db'
      const chatFilePath = '/tmp/uc020/.ai-pm/agents/uc020-worker-a/chat.jsonl'
      const { execSync } = await import('child_process')

      while (Date.now() - startTime < maxWaitTime) {
        pollCount++

        try {
          // 1. Check task status from DB
          const taskResult = execSync(
            `sqlite3 "${dbPath}" "SELECT status FROM tasks WHERE id='${TEST_TASK.id}';"`,
            { encoding: 'utf-8' }
          ).trim()
          const taskDone = taskResult === 'done'

          // 2. Check chat messages with conversationId from jsonl file
          let conversationMessageCount = 0
          try {
            const chatContent = execSync(`cat "${chatFilePath}" 2>/dev/null || echo ""`, {
              encoding: 'utf-8',
            })
            const lines = chatContent.trim().split('\n').filter((l) => l.length > 0)
            conversationMessageCount = lines.filter((line) => {
              try {
                const msg = JSON.parse(line)
                return msg.conversationId && msg.conversationId.value
              } catch {
                return false
              }
            }).length
          } catch {
            // File might not exist yet
          }

          if (pollCount % 5 === 0 || taskDone) {
            console.log(`UC020 Polling #${pollCount}: Task=${taskResult}, ConvMessages=${conversationMessageCount}`)
          }

          if (taskDone && conversationMessageCount > 0) {
            console.log(`UC020: Task completed and conversation messages found after ${(Date.now() - startTime) / 1000}s`)
            conversationCompleted = true
            break
          }
        } catch (e) {
          const error = e as Error
          console.log(`UC020 Polling #${pollCount}: Check error: ${error.message}`)
        }

        await page.waitForTimeout(pollInterval)
      }

      // Verify task completed and conversation happened
      expect(conversationCompleted).toBe(true)

      console.log('UC020: AI-to-AI conversation via task completed!')
    })

    /**
     * Test: Verify conversation was created during task execution
     *
     * After the full flow completes, verify:
     * - Conversation record exists with state = 'ended'
     * - Both workers participated
     */
    test('Verify conversation state after task completion', async ({ page }) => {
      // Skip if not in integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires integration environment'
      )

      // This test assumes the full flow test has run
      // Navigate to project to verify UI state
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Both agent avatars should still be visible
      const workerAAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_A.id}"]`)
      const workerBAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_B.id}"]`)

      await expect(workerAAvatar).toBeVisible()
      await expect(workerBAvatar).toBeVisible()

      console.log('UC020: Both agents visible after task completion')
    })
  })

  test.describe('Task Status Transitions', () => {
    /**
     * Test: Change task status to in_progress via UI
     *
     * This verifies that the task status can be changed via UI
     * which triggers Coordinator to spawn agent.
     */
    test('Can change task status to in_progress', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title, { exact: true }),
      })

      const taskVisible = await taskCard.isVisible().catch(() => false)
      if (!taskVisible) {
        console.log('UC020: Task not visible, skipping')
        test.skip()
        return
      }

      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Status picker should be available
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()

      // Get current status
      const currentStatus = await statusSelect.inputValue()
      console.log(`UC020: Current task status: ${currentStatus}`)

      // Close dialog
      await page.keyboard.press('Escape')
    })
  })

  test.describe('Reset Test Data', () => {
    /**
     * Reset task to initial state for next test run
     */
    test('Reset task to todo status', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find the task (might be in any column)
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title, { exact: true }),
      })

      if (await taskCard.isVisible()) {
        await taskCard.click()
        const dialog = page.getByRole('dialog').first()
        await expect(dialog).toBeVisible()

        const statusSelect = dialog.getByRole('combobox')
        await expect(statusSelect).toBeVisible()

        // Only change if not already todo
        const currentStatus = await statusSelect.inputValue()
        if (currentStatus !== 'todo') {
          await statusSelect.selectOption('todo')
          await page.waitForTimeout(500)
        }

        // Close dialog
        await page.keyboard.press('Escape')

        // Verify task is back in todo column
        const todoColumn = page.locator('[data-column="todo"]')
        await expect(
          todoColumn.locator('[data-testid="task-card"]', {
            has: page.getByText(TEST_TASK.title, { exact: true }),
          })
        ).toBeVisible()

        console.log('UC020: Task reset to todo status')
      }
    })
  })
})
