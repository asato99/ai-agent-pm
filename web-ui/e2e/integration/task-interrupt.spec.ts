import { test, expect } from '@playwright/test'
import { execSync } from 'child_process'

/**
 * Integration Test: Task Interrupt via Status Change (UC010)
 * Reference: docs/usecase/UC010_TaskInterruptByStatusChange.md
 *
 * This test verifies the task interrupt flow:
 * 1. A countdown task is assigned to an agent
 * 2. Task status is changed to in_progress via UI
 * 3. Coordinator spawns agent to execute task
 * 4. While agent executes, status is changed to "blocked"
 * 5. Agent receives notification and stops execution
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/setup/setup-integration-env.sh
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 */

// Database path (must match run-uc010-test.sh)
const TEST_DB_PATH = '/tmp/AIAgentPM_UC010_WebUI.db'

// Threshold: if agent continues working more than this after interrupt, it's RED
// Threshold for agent response to interrupt signal
// Factors affecting response time:
// - Coordinator polling interval (2-5 seconds)
// - Agent must notice notification field in MCP response
// - Agent processes notification and calls get_notifications
// - Agent calls report_completed
// - Claude CLI API response time for each call
// A reasonable threshold allows for full notification detection cycle
const INTERRUPT_THRESHOLD_SECONDS = 60

test.describe('Task Interrupt Flow - UC010', () => {
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

  test.describe('Task Interrupt Flow', () => {
    /**
     * Test: Basic status change to blocked
     *
     * Verifies that task status can be changed to blocked via UI.
     * This is the basic UI verification without agent involvement.
     *
     * Note: Skip this test when running with Coordinator because
     * changing status to in_progress will spawn an agent and
     * interfere with the Full E2E test.
     */
    test('Change task status to blocked via UI', async ({ page }) => {
      // Skip when running with coordinator to avoid interfering with E2E test
      test.skip(
        !!process.env.INTEGRATION_WITH_COORDINATOR,
        'Skip basic UI test when running with Coordinator to avoid agent spawn interference'
      )

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // First change to in_progress (required before blocked)
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      await statusSelect.selectOption('in_progress')
      await page.waitForTimeout(500)

      // Now change to blocked
      await statusSelect.selectOption('blocked')
      await page.waitForTimeout(500)

      // Close dialog
      await page.keyboard.press('Escape')

      // Verify task is in blocked column
      const blockedColumn = page.locator('[data-column="blocked"]')
      await expect(
        blockedColumn.locator('[data-testid="task-card"]', {
          has: page.getByText(TEST_TASK.title),
        })
      ).toBeVisible()
    })

    /**
     * Test: Full interrupt flow with agent execution (PROPER RED TEST)
     *
     * UC010 Requirements (docs/usecase/UC010_TaskInterruptByStatusChange.md):
     * 1. Task status changes to in_progress (agent starts executing)
     * 2. User changes status to blocked via UI (interrupt signal)
     * 3. System creates notification for agent ← NOT IMPLEMENTED
     * 4. Agent detects notification via get_next_action ← NOT IMPLEMENTED
     * 5. Agent calls report_completed with result='blocked'
     * 6. Task ends with 'blocked' status
     *
     * ============================================================
     * PROPER TDD RED/GREEN TEST STRATEGY (DB Verification)
     * ============================================================
     *
     * Based on user feedback:
     * - "DBで確認する方がテストとして適切"
     * - "mcpの呼び出しが中断後に１度以上あってそれ以降の成果物やログであることが正確なレッド"
     *
     * TEST APPROACH:
     * 1. Change task to in_progress (agent starts)
     * 2. Wait for execution_log to be created (agent is working)
     * 3. Change task to blocked (interrupt signal)
     * 4. Get tasks.status_changed_at from DB (interrupt timestamp)
     * 5. Wait for agent to complete (or timeout)
     * 6. Get execution_logs.completed_at from DB
     * 7. Compare: completed_at vs status_changed_at
     *    - If (completed_at - status_changed_at) > threshold → Agent continued → FAIL (RED)
     *    - If (completed_at - status_changed_at) <= threshold → Agent stopped → PASS (GREEN)
     *
     * This is a proper RED test because:
     * - We assert that agent should STOP promptly after interrupt
     * - Without notification, agent continues to completion → large time diff → RED
     * - With notification, agent stops quickly → small time diff → GREEN
     *
     * Run via: ./e2e/integration/run-uc010-test.sh
     */
    test('Full interrupt flow with agent execution', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test
      test.setTimeout(300_000) // 5 minutes

      // Helper function to query DB
      const queryDb = (sql: string): string => {
        try {
          return execSync(`sqlite3 "${TEST_DB_PATH}" "${sql}"`, { encoding: 'utf-8' }).trim()
        } catch (e) {
          console.log(`DB query failed: ${sql}`)
          return ''
        }
      }

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Step 0: Ensure task is in todo status (reset if needed)
      console.log('Step 0: Ensuring task is in todo status before starting...')
      const taskCardInit = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      }).first()

      if (await taskCardInit.isVisible()) {
        await taskCardInit.click()
        const dialogInit = page.getByRole('dialog').first()
        await expect(dialogInit).toBeVisible()

        const statusSelectInit = dialogInit.getByRole('combobox')
        const currentStatus = await statusSelectInit.inputValue()

        if (currentStatus !== 'todo') {
          console.log(`Task is in '${currentStatus}', resetting to 'todo'...`)
          await statusSelectInit.selectOption('todo')
          await page.waitForTimeout(1000)
          await page.reload()
          await page.waitForTimeout(5000)
          console.log('Task reset to todo')
        } else {
          await page.keyboard.press('Escape')
          await page.waitForTimeout(500)
        }
      }

      await page.reload()
      await page.waitForTimeout(1000)

      // Find and click the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await taskCard.click()

      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Step 1: Change to in_progress (triggers agent spawn)
      console.log('Step 1: Changing task to in_progress to trigger agent spawn...')
      const statusSelect = dialog.getByRole('combobox')
      await expect(statusSelect).toBeVisible()
      await statusSelect.selectOption('in_progress')
      await page.waitForTimeout(1000)
      await page.keyboard.press('Escape')

      // Step 2: Wait for agent to start (execution_log created)
      console.log('Step 2: Waiting for agent to start executing...')
      console.log('(Coordinator detection + agent spawn + CLI init takes ~30s)')

      let executionLogExists = false
      const logWaitStart = Date.now()

      while (Date.now() - logWaitStart < 60_000) {
        await page.waitForTimeout(5000)

        // Check if execution_log exists for this task
        const logCount = queryDb(
          `SELECT COUNT(*) FROM execution_logs WHERE task_id = '${TEST_TASK.id}'`
        )

        if (parseInt(logCount) > 0) {
          const logInfo = queryDb(
            `SELECT id, status, started_at FROM execution_logs WHERE task_id = '${TEST_TASK.id}' ORDER BY started_at DESC LIMIT 1`
          )
          console.log(`Execution log found: ${logInfo}`)
          executionLogExists = true
          break
        }

        console.log(`Waiting for execution_log... (${Math.round((Date.now() - logWaitStart) / 1000)}s)`)
      }

      if (!executionLogExists) {
        console.log('ERROR: No execution_log found after 60s - agent may not have started')
        expect(executionLogExists).toBe(true)
        return
      }

      // Wait a bit more to ensure agent is actively working
      console.log('Step 2.5: Verifying agent is actively working (10s)...')
      await page.waitForTimeout(10_000)

      // Step 3: Send interrupt signal (change to blocked)
      console.log('Step 3: Sending interrupt signal (changing status to blocked)...')
      await page.reload()
      await page.waitForTimeout(1000)

      const taskCardForBlocked = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      }).first()

      await taskCardForBlocked.click()
      const dialog2 = page.getByRole('dialog').first()
      await expect(dialog2).toBeVisible()

      const statusSelect2 = dialog2.getByRole('combobox')
      await statusSelect2.selectOption('blocked')
      await page.waitForTimeout(500)
      await page.keyboard.press('Escape')

      console.log('INTERRUPT SIGNAL SENT (status changed to blocked)')

      // Step 4: Get status_changed_at from DB (interrupt timestamp)
      await page.waitForTimeout(1000) // Wait for DB to be updated
      const statusChangedAtStr = queryDb(
        `SELECT status_changed_at FROM tasks WHERE id = '${TEST_TASK.id}'`
      )
      console.log(`DB: tasks.status_changed_at = ${statusChangedAtStr}`)

      // Validate status_changed_at exists
      if (!statusChangedAtStr) {
        console.log('ERROR: status_changed_at is NULL - status change was not recorded')
        expect(statusChangedAtStr).not.toBe('')
        return
      }

      // Step 5: Wait for agent to complete (or timeout)
      console.log('Step 5: Waiting for agent to complete (max 180s)...')

      const maxWaitTime = 180_000 // 3 minutes
      const pollInterval = 10_000
      const waitStart = Date.now()

      while (Date.now() - waitStart < maxWaitTime) {
        await page.waitForTimeout(pollInterval)

        // Check execution_log status
        const logStatus = queryDb(
          `SELECT status FROM execution_logs WHERE task_id = '${TEST_TASK.id}' ORDER BY started_at DESC LIMIT 1`
        )

        console.log(`Polling: execution_log.status = ${logStatus}`)

        if (logStatus !== 'running') {
          console.log(`Agent completed with status: ${logStatus}`)
          break
        }
      }

      // Step 6: Get execution_logs.completed_at from DB
      const completedAtStr = queryDb(
        `SELECT completed_at FROM execution_logs WHERE task_id = '${TEST_TASK.id}' ORDER BY started_at DESC LIMIT 1`
      )
      console.log(`DB: execution_logs.completed_at = ${completedAtStr}`)

      // Step 7: Calculate time difference and verify
      console.log('')
      console.log('============================================================')
      console.log('UC010 Test Result Analysis (TDD RED/GREEN Test - DB Verification)')
      console.log('============================================================')
      console.log('')
      console.log(`Interrupt signal (status_changed_at): ${statusChangedAtStr}`)
      console.log(`Agent completion (completed_at):      ${completedAtStr}`)

      if (!completedAtStr) {
        // Check execution_log status
        const logStatus = queryDb(
          `SELECT status FROM execution_logs WHERE task_id = '${TEST_TASK.id}' ORDER BY started_at DESC LIMIT 1`
        )

        console.log('')
        console.log('⚠️  RESULT: Agent did not complete (completed_at is NULL)')
        console.log(`   execution_log.status = ${logStatus}`)
        console.log('')

        if (logStatus === 'running') {
          // Agent is still running after interrupt signal - this is the RED case!
          console.log('❌ RESULT: Agent is STILL RUNNING after interrupt signal')
          console.log('')
          console.log('This is the expected RED test result!')
          console.log('Evidence:')
          console.log('  - Interrupt signal was sent (status changed to blocked)')
          console.log('  - Agent did NOT stop (execution_log.status is still "running")')
          console.log('  - Agent does not detect the status change because notification is not implemented')
          console.log('')
          console.log('To make this test GREEN:')
          console.log('  1. Implement notification table/system (UC010 Step 3)')
          console.log('  2. Add notification check in MCP responses (UC010 Step 5)')
          console.log('  3. Agent should detect and call report_completed(result="blocked")')
          console.log('============================================================')

          // This is a RED result - agent continued running after interrupt
          expect(
            true,
            'Agent is still running after interrupt signal. ' +
            'This means the interrupt notification system is NOT implemented. ' +
            'Implement UC010 notification to make this test GREEN.'
          ).toBe(false)
          return
        }

        // Agent stopped but completed_at is NULL - infrastructure issue
        console.log('This could mean:')
        console.log('  - Agent crashed or was killed externally')
        console.log('  - Execution log was not updated properly')
        console.log('')
        console.log('Since agent did not complete properly, we cannot verify interrupt behavior.')
        console.log('This is treated as a test infrastructure issue, not a RED/GREEN result.')
        console.log('')
        expect(completedAtStr, 'Agent must complete (completed_at must not be NULL) to verify interrupt behavior').not.toBe('')
        return
      }

      // Parse timestamps and calculate difference
      const statusChangedAt = new Date(statusChangedAtStr).getTime()
      const completedAt = new Date(completedAtStr).getTime()

      // Validate timestamp parsing
      if (isNaN(statusChangedAt) || isNaN(completedAt)) {
        console.log('')
        console.log('ERROR: Failed to parse timestamps')
        console.log(`  status_changed_at: ${statusChangedAtStr} → ${statusChangedAt}`)
        console.log(`  completed_at: ${completedAtStr} → ${completedAt}`)
        expect(isNaN(statusChangedAt), 'status_changed_at must be a valid timestamp').toBe(false)
        expect(isNaN(completedAt), 'completed_at must be a valid timestamp').toBe(false)
        return
      }

      const timeDiffSeconds = (completedAt - statusChangedAt) / 1000

      // Handle edge case: completed_at is before status_changed_at (shouldn't happen)
      if (timeDiffSeconds < 0) {
        console.log('')
        console.log('⚠️  WARNING: completed_at is BEFORE status_changed_at')
        console.log(`  This suggests agent completed before interrupt signal was sent.`)
        console.log(`  Time difference: ${timeDiffSeconds.toFixed(1)}s (negative)`)
        console.log('')
        console.log('Possible causes:')
        console.log('  - Agent completed very quickly before UI could send interrupt')
        console.log('  - Clock synchronization issue')
        console.log('  - Test timing issue')
        console.log('')
        // This is actually a GREEN scenario - agent completed before interrupt
        // No need to test interrupt behavior in this case
      }

      console.log(`Time difference: ${timeDiffSeconds.toFixed(1)} seconds`)
      console.log(`Threshold: ${INTERRUPT_THRESHOLD_SECONDS} seconds`)
      console.log('')

      const agentContinuedWorking = timeDiffSeconds > INTERRUPT_THRESHOLD_SECONDS

      if (agentContinuedWorking) {
        console.log('❌ RESULT: Agent CONTINUED WORKING after interrupt signal')
        console.log('')
        console.log('This is the expected RED test result!')
        console.log('Evidence:')
        console.log(`  - Agent completed ${timeDiffSeconds.toFixed(1)}s AFTER interrupt signal`)
        console.log(`  - This exceeds the ${INTERRUPT_THRESHOLD_SECONDS}s threshold`)
        console.log('  - Agent did not detect the status change to "blocked"')
        console.log('')
        console.log('To make this test GREEN:')
        console.log('  1. Implement notification table/system (UC010 Step 3)')
        console.log('  2. Add notification check in MCP responses (UC010 Step 5)')
        console.log('  3. Agent should detect and call report_completed(result="blocked")')
      } else {
        console.log('✅ RESULT: Agent STOPPED promptly after interrupt signal')
        console.log('')
        console.log('SUCCESS! The notification system is working:')
        console.log(`  - Agent completed within ${timeDiffSeconds.toFixed(1)}s of interrupt`)
        console.log(`  - This is within the ${INTERRUPT_THRESHOLD_SECONDS}s threshold`)
        console.log('  - Agent detected the status change and stopped')
        console.log('')
        console.log('UC010 is properly implemented!')
      }

      console.log('============================================================')

      // ASSERTION: Agent should have STOPPED promptly after interrupt
      // - GREEN: timeDiffSeconds <= threshold (agent stopped quickly)
      // - RED: timeDiffSeconds > threshold (agent continued working)
      expect(
        agentContinuedWorking,
        `Agent continued working ${timeDiffSeconds.toFixed(1)}s after interrupt signal was sent. ` +
        `This exceeds the ${INTERRUPT_THRESHOLD_SECONDS}s threshold. ` +
        `status_changed_at=${statusChangedAtStr}, completed_at=${completedAtStr}`
      ).toBe(false)
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

        // Use combobox to change status
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
