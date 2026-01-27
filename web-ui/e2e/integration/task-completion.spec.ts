import { test, expect } from '@playwright/test'

/**
 * Integration Test: Task Completion Flow (UC001)
 *
 * This test verifies the normal task completion flow:
 * 1. Task is assigned to an agent
 * 2. Task status is changed to in_progress via UI
 * 3. Coordinator detects and spawns agent
 * 4. Agent executes task and reports completion
 * 5. Task status becomes done
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/setup/setup-integration-env.sh
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 */

test.describe('Task Completion Flow - UC001', () => {
  // NOTE: Only human agents can login to Web UI (restriction added in 891ff08)
  // Use integ-owner (type: human) instead of integ-manager (type: ai)
  const TEST_CREDENTIALS = {
    agentId: 'integ-owner',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'integ-project',
    name: 'Integration Test Project',
  }

  const TEST_TASK = {
    id: 'integ-task-countdown',
    title: 'カウントダウンタスク',
    initialStatus: 'todo',
    assigneeId: 'integ-worker',
  }

  test.beforeEach(async ({ page }) => {
    // Login as integration manager
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('Integration project exists and is accessible', async ({ page }) => {
      // Verify integration project is listed
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
      await expect(dialog.getByText('Integration Worker')).toBeVisible()
    })
  })

  test.describe('Task Completion Flow', () => {
    /**
     * Test: Change task status to in_progress
     *
     * This verifies the first step of task execution:
     * - User changes task status from todo to in_progress via UI
     * - This triggers Coordinator to spawn agent (if running)
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

      // Status picker is directly in TaskDetailPanel
      // Use combobox role - there's only one in the dialog
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
     * Test: Full task completion flow with agent execution
     *
     * This test verifies the complete flow:
     * 1. Task status changes to in_progress
     * 2. Wait for Coordinator to spawn agent
     * 3. Wait for agent to complete task
     * 4. Verify task status becomes done
     *
     * Note: Requires Coordinator to be running with configured agent.
     * Run via: ./e2e/integration/run-uc001-test.sh
     */
    test('Full task completion with agent execution', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (agent execution takes time)
      test.setTimeout(240_000) // 4 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Status picker is directly in TaskDetailPanel
      // Use combobox role - there's only one in the dialog
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      await statusSelect.selectOption('in_progress')

      // Wait for status update
      await page.waitForTimeout(500)

      // Close dialog
      await page.keyboard.press('Escape')

      // Poll UI for task status change to 'done'
      // Agent execution can take up to 180 seconds (may require multiple agent spawns)
      const maxWaitTime = 180_000 // 180 seconds
      const pollInterval = 5_000 // 5 seconds
      const startTime = Date.now()

      console.log(`Polling UI for task completion`)

      let taskCompleted = false
      let pollCount = 0
      const doneColumn = page.locator('[data-column="done"]')
      const taskCardInDone = doneColumn.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })

      while (Date.now() - startTime < maxWaitTime) {
        pollCount++
        await page.reload()
        await page.waitForTimeout(1000) // Wait for page to load

        // Check which column the task is in
        const inProgressColumn = page.locator('[data-column="in_progress"]')
        const taskInProgress = await inProgressColumn
          .locator('[data-testid="task-card"]', {
            has: page.getByText(TEST_TASK.title),
          })
          .count()

        const taskInDone = await taskCardInDone.count()

        if (taskInDone > 0) {
          console.log(`Polling #${pollCount}: Task found in 'done' column after ${(Date.now() - startTime) / 1000}s`)
          taskCompleted = true
          break
        } else if (taskInProgress > 0) {
          console.log(`Polling #${pollCount}: Task still in 'in_progress'`)
        } else {
          console.log(`Polling #${pollCount}: Task not found in expected columns`)
        }

        await page.waitForTimeout(pollInterval - 1000) // Already waited 1000ms after reload
      }

      if (!taskCompleted) {
        console.log(`Polling timed out after ${maxWaitTime / 1000}s`)
      }

      expect(taskCompleted).toBe(true)

      // Final verification - task should be visible in done column
      await expect(taskCardInDone).toBeVisible({ timeout: 5_000 })

      // Task completion verified!
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

        // Status picker is directly in TaskDetailPanel
        // Use combobox role - there's only one in the dialog
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
