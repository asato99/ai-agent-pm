import { test, expect } from '@playwright/test'

/**
 * Integration Test: Send Message from Task Session (UC012)
 *
 * Reference: docs/usecase/UC012_SendMessageFromTaskSession.md
 *
 * This test verifies that a worker executing a task can send a message
 * to another agent (Human) using the send_message tool, and the message
 * is visible in the Web UI chat panel.
 *
 * Test Flow:
 * 1. Task is assigned to worker
 * 2. Task status is changed to in_progress via UI
 * 3. Coordinator detects and spawns worker
 * 4. Worker executes task and calls send_message
 * 5. Worker reports completion
 * 6. Task status becomes done
 * 7. Human agent shows unread indicator
 * 8. User opens chat panel and sees the message
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-uc012-test.sh --setup
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 */

test.describe('Send Message from Task Session - UC012', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc012-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc012-project',
    name: 'UC012 SendMessage Test',
  }

  const TEST_TASK = {
    id: 'uc012-task-sendmsg',
    title: 'メッセージ送信テストタスク',
    initialStatus: 'todo',
    assigneeId: 'uc012-worker',
  }

  const TEST_WORKER = {
    id: 'uc012-worker',
    name: 'UC012 Worker',
  }

  const EXPECTED_MESSAGE = 'タスク実行中からの報告です。処理が正常に完了しました。'

  test.beforeEach(async ({ page }) => {
    // Login as UC012 Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('UC012 project exists and is accessible', async ({ page }) => {
      // Verify UC012 project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Test task exists and is assigned to worker', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find the task card
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await expect(taskCard).toBeVisible()

      // Click to open task detail
      await taskCard.click()
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Verify task details
      await expect(dialog.getByRole('heading', { name: TEST_TASK.title })).toBeVisible()
      await expect(dialog.getByText('Assignee')).toBeVisible()
      await expect(dialog.getByText(TEST_WORKER.name)).toBeVisible()
    })

    test('Worker agent is assigned to project', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Check agent avatar is visible
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_WORKER.id}"]`)
      await expect(agentAvatar).toBeVisible()
    })
  })

  test.describe('Send Message Flow', () => {
    /**
     * Test: Change task status to in_progress
     *
     * Verifies that user can change task status via UI,
     * which triggers Coordinator to spawn agent.
     */
    test('Change task status to in_progress via UI', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Change status to in_progress
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      await statusSelect.selectOption('in_progress')

      // Wait for status update
      await page.waitForTimeout(500)

      // Close dialog
      await page.keyboard.press('Escape')

      // Verify task is now in in_progress column
      const inProgressColumn = page.locator('[data-column="in_progress"]')
      await expect(
        inProgressColumn.locator('[data-testid="task-card"]', {
          has: page.getByText(TEST_TASK.title),
        })
      ).toBeVisible()
    })

    /**
     * Test: Full send_message flow with agent execution
     *
     * This test verifies the complete UC012 flow:
     * 1. Task status changes to in_progress
     * 2. Wait for agent to execute and send message
     * 3. Verify task completes (done status)
     * 4. Verify message appears in Human's chat panel
     *
     * Note: Requires Coordinator to be running with configured agent.
     * Run via: ./e2e/integration/run-uc012-test.sh
     */
    test('Full send_message flow with agent execution', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (agent execution takes time)
      test.setTimeout(300_000) // 5 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Change status to in_progress
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      await statusSelect.selectOption('in_progress')

      // Wait for status update
      await page.waitForTimeout(500)

      // Close dialog
      await page.keyboard.press('Escape')

      // Poll UI for task status change to 'done'
      const maxWaitTime = 240_000 // 4 minutes
      const pollInterval = 5_000 // 5 seconds
      const startTime = Date.now()

      console.log('UC012: Polling UI for task completion')

      let taskCompleted = false
      let pollCount = 0
      const doneColumn = page.locator('[data-column="done"]')
      const taskCardInDone = doneColumn.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })

      while (Date.now() - startTime < maxWaitTime) {
        pollCount++
        await page.reload()
        await page.waitForTimeout(1000)

        const taskInDone = await taskCardInDone.count()

        if (taskInDone > 0) {
          console.log(`UC012 Polling #${pollCount}: Task found in 'done' column after ${(Date.now() - startTime) / 1000}s`)
          taskCompleted = true
          break
        } else {
          console.log(`UC012 Polling #${pollCount}: Task not yet in 'done' column`)
        }

        await page.waitForTimeout(pollInterval - 1000)
      }

      expect(taskCompleted).toBe(true)

      // Task completed, now verify message was received

      // Check for unread indicator on worker agent (sender has message in their chat.jsonl)
      // The message should appear in Human's chat panel since Human is the receiver
      console.log('UC012: Verifying message in chat panel')

      // Click on worker avatar to open chat
      const workerAvatar = page.locator(`[data-testid="agent-avatar-${TEST_WORKER.id}"]`)
      await expect(workerAvatar).toBeVisible()
      await workerAvatar.click()

      // Wait for chat panel
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for messages to load
      await page.waitForTimeout(2000)

      // Verify the expected message is visible
      const messageElement = chatPanel.getByText(EXPECTED_MESSAGE, { exact: false })
      await expect(messageElement).toBeVisible({ timeout: 10000 })

      console.log('UC012: Message verified in chat panel!')
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
        has: page.getByText(TEST_TASK.title),
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
            has: page.getByText(TEST_TASK.title),
          })
        ).toBeVisible()
      }
    })
  })
})
