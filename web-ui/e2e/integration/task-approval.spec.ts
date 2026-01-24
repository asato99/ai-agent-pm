import { test, expect } from '@playwright/test'

/**
 * Integration Test: Task Approval Flow (UC017)
 *
 * This test verifies the task approval flow:
 * 1. Manager logs in
 * 2. Manager sees pendingApproval task with visual indicators
 * 3. Manager opens task detail and sees approval UI
 * 4. Manager approves the task
 * 5. Visual indicators disappear, task becomes approved
 *
 * Prerequisites:
 *   - Run: ./e2e/integration/run-uc017-test.sh
 *   - Database seeded with UC017 test data
 */

test.describe('Task Approval Flow - UC017', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc017-manager',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc017-project',
    name: 'Task Approval Test Project',
  }

  const TEST_TASK = {
    id: 'uc017-task-pending',
    title: '承認待ちタスク',
    requesterName: 'Task Worker',
  }

  test.beforeEach(async ({ page }) => {
    // Login as manager
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('Test project exists and is accessible', async ({ page }) => {
      // Verify project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Pending approval task exists with visual indicators', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find the task card
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await expect(taskCard).toBeVisible()

      // Verify approval badge is visible
      await expect(taskCard.getByText('🔔 承認待ち')).toBeVisible()
    })
  })

  test.describe('Task Approval Flow', () => {
    /**
     * Test: Full task approval flow via UI
     *
     * Steps:
     * 1. Navigate to project and find pending approval task
     * 2. Verify visual indicators (orange background, badge)
     * 3. Open task detail panel
     * 4. Verify approval UI elements (badge, requester, buttons)
     * 5. Click approve button
     * 6. Verify UI updates (badge disappears, buttons disappear)
     * 7. Close panel and verify task card updates
     */
    test('Approve task and verify UI updates', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Step 1: Find the pending approval task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await expect(taskCard).toBeVisible()

      // Step 2: Verify pending approval badge on card
      await expect(taskCard.getByText('🔔 承認待ち')).toBeVisible()

      // Step 3: Click to open task detail
      await taskCard.click()
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Step 4: Verify approval UI elements in detail panel
      // - Approval status badge (use exact match to avoid matching title "承認待ちタスク")
      await expect(dialog.getByText('承認待ち', { exact: true })).toBeVisible()
      // - Requester info label is visible (Task Worker appears in both requester and assignee, just check label)
      await expect(dialog.getByText('依頼者:', { exact: false })).toBeVisible()
      // - Approve button
      const approveButton = dialog.getByRole('button', { name: '承認' })
      await expect(approveButton).toBeVisible()
      // - Reject button
      const rejectButton = dialog.getByRole('button', { name: '却下' })
      await expect(rejectButton).toBeVisible()

      // Step 5: Click approve button
      await approveButton.click()

      // Wait for API call and UI update
      await page.waitForTimeout(500)

      // Step 6: Verify approval UI elements disappear
      // Badge should disappear (or change) - use exact match to avoid matching title
      await expect(dialog.getByText('承認待ち', { exact: true })).not.toBeVisible({ timeout: 3000 })
      // Approve/Reject buttons should disappear
      await expect(dialog.getByRole('button', { name: '承認' })).not.toBeVisible()
      await expect(dialog.getByRole('button', { name: '却下' })).not.toBeVisible()

      // Step 7: Close dialog and verify task card
      await page.keyboard.press('Escape')
      await page.waitForTimeout(300)

      // Task card should no longer show pending approval badge
      const updatedTaskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })
      await expect(updatedTaskCard).toBeVisible()
      await expect(updatedTaskCard.getByText('🔔 承認待ち')).not.toBeVisible()
    })
  })

  test.describe('Reset Test Data', () => {
    /**
     * Reset task to pendingApproval state for next test run
     * Note: This requires direct DB access, so we just verify current state
     */
    test('Verify task state after test', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Find the task
      const taskCard = page.locator('[data-testid="task-card"]', {
        has: page.getByText(TEST_TASK.title),
      })

      // Just verify task exists (state may be approved after previous test)
      await expect(taskCard).toBeVisible()
    })
  })
})
