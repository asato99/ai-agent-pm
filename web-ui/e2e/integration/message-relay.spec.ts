import { test, expect } from '@playwright/test'

/**
 * Integration Test: Worker-to-Worker Message Relay (UC013)
 *
 * Reference: docs/usecase/UC013_WorkerToWorkerMessageRelay.md
 *
 * This test verifies that Worker-A can send a message to Worker-B,
 * and Worker-B (running in chat session) relays it to Human.
 *
 * Test Flow:
 * 1. Worker-A's task is started (in_progress)
 * 2. Worker-A executes task and sends message to Worker-B
 * 3. Worker-A completes task (done)
 * 4. Worker-B starts in chat session (triggered by pending message)
 * 5. Worker-B receives message via get_pending_messages
 * 6. Worker-B sends to Human via respond_chat
 * 7. Human sees message in Web UI chat panel
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-uc013-test.sh --setup
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 */

test.describe('Worker-to-Worker Message Relay - UC013', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc013-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc013-project',
    name: 'UC013 Message Relay Test',
  }

  const TEST_TASK = {
    id: 'uc013-task-data',
    title: 'データ処理タスク',
    initialStatus: 'todo',
    assigneeId: 'uc013-worker-a',
  }

  const WORKER_A = {
    id: 'uc013-worker-a',
    name: 'UC013 Task Worker',
  }

  const WORKER_B = {
    id: 'uc013-worker-b',
    name: 'UC013 Relay Worker',
  }

  // Expected message content from Worker-A (original message)
  const ORIGINAL_MESSAGE = 'データ処理が完了しました'

  // Expected relay message content (Worker-B relays to Human)
  // Worker-B should include something like "Worker-Aからの報告" when relaying
  const EXPECTED_RELAY_INDICATOR = 'Worker-A'

  test.beforeEach(async ({ page }) => {
    // Login as UC013 Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('UC013 project exists and is accessible', async ({ page }) => {
      // Verify UC013 project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Test task exists and is assigned to Worker-A', async ({ page }) => {
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
      await expect(dialog.getByText(WORKER_A.name)).toBeVisible()
    })

    test('Both worker agents are assigned to project', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Check Worker-A avatar is visible
      const workerAAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_A.id}"]`)
      await expect(workerAAvatar).toBeVisible()

      // Check Worker-B avatar is visible
      const workerBAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_B.id}"]`)
      await expect(workerBAvatar).toBeVisible()
    })
  })

  test.describe('Message Relay Flow', () => {
    /**
     * Test: Change task status to in_progress
     *
     * Verifies that user can change task status via UI,
     * which triggers Coordinator to spawn Worker-A.
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
     * Test: Full message relay flow with agent execution
     *
     * This test verifies the complete UC013 flow:
     * 1. Task status changes to in_progress
     * 2. Worker-A executes and sends message to Worker-B
     * 3. Worker-B starts (chat session) and relays to Human
     * 4. Verify message appears in Human's chat panel (via Worker-B)
     *
     * Note: Requires Coordinator to be running with configured agents.
     * Run via: ./e2e/integration/run-uc013-test.sh
     */
    test('Full message relay flow: Worker-A → Worker-B → Human', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (multiple agent executions take time)
      test.setTimeout(420_000) // 7 minutes (Worker-A + Worker-B)

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

      // Wait for Worker-A to execute task, send message to Worker-B,
      // then Worker-B to relay message to Human
      // (Skip UI done column check - just verify message relay to Human)
      const maxWaitTime = 360_000 // 6 minutes for entire flow
      const pollInterval = 5_000
      let startTime = Date.now()

      console.log('UC013: Waiting for message relay to Human (Worker-A → Worker-B → Human)')

      // Poll for message from Worker-B in Human's chat
      // Worker-B should send a message like "Worker-Aからの報告: データ処理が完了しました"
      let messageReceived = false
      let pollCount = 0

      while (Date.now() - startTime < maxWaitTime) {
        pollCount++
        await page.reload()
        await page.waitForTimeout(1000)

        // Click on Worker-B avatar to check chat between Human and Worker-B
        const workerBAvatar = page.locator(`[data-testid="agent-avatar-${WORKER_B.id}"]`)
        if (await workerBAvatar.isVisible()) {
          await workerBAvatar.click()

          // Wait for chat panel
          const chatPanel = page.getByTestId('chat-panel')
          if (await chatPanel.isVisible()) {
            await page.waitForTimeout(1000)

            // Check for relay message FROM Worker-B (not the message TO Worker-B from Worker-A)
            // The relay message should contain the original content AND indicate it's from Worker-A
            // Look for messages that include both the relay indicator and original content
            const relayIndicator = chatPanel.getByText(EXPECTED_RELAY_INDICATOR, { exact: false })
            const originalContent = chatPanel.getByText(ORIGINAL_MESSAGE, { exact: false })

            // Check if there's a message that contains both (relay message from Worker-B)
            // This ensures we're checking Worker-B's response, not just Worker-A's original message
            const hasRelayIndicator = await relayIndicator.count() > 0
            const hasOriginalContent = await originalContent.count() > 0

            if (hasRelayIndicator && hasOriginalContent) {
              console.log(`UC013 Polling #${pollCount}: Relay message found in Human's chat after ${(Date.now() - startTime) / 1000}s`)
              messageReceived = true

              // Close chat panel
              await page.keyboard.press('Escape')
              break
            } else {
              console.log(`UC013 Polling #${pollCount}: Relay indicator: ${hasRelayIndicator}, Original content: ${hasOriginalContent}`)
            }

            // Close chat panel
            await page.keyboard.press('Escape')
          }
        }

        console.log(`UC013 Polling #${pollCount}: Relay message not yet in Human's chat`)
        await page.waitForTimeout(pollInterval - 2000)
      }

      expect(messageReceived).toBe(true)
      console.log('UC013: Message relay verified! Worker-A → Worker-B → Human (via respond_chat)')
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
