// web-ui/e2e/tests/task-history.spec.ts
// E2E tests for Task History Tab feature
// Reference: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('Task History Tab', () => {
  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // Navigate to project page
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('Task detail panel displays tab navigation', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID to avoid ambiguity
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Tab buttons should be visible
    await expect(dialog.getByRole('button', { name: '詳細' })).toBeVisible()
    await expect(dialog.getByRole('button', { name: '履歴' })).toBeVisible()
  })

  test('Details tab is active by default', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Details tab should be active (blue border)
    const detailsTab = dialog.getByRole('button', { name: '詳細' })
    await expect(detailsTab).toHaveClass(/text-blue-600/)

    // Task description should be visible (details content)
    await expect(dialog.getByText('REST APIエンドポイントの実装')).toBeVisible()
  })

  test('Can switch to history tab', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Click history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // History tab should be active
    const historyTab = dialog.getByRole('button', { name: '履歴' })
    await expect(historyTab).toHaveClass(/text-blue-600/)

    // Details content should not be visible
    await expect(dialog.getByText('REST APIエンドポイントの実装')).not.toBeVisible()
  })

  test('History tab displays execution logs', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail for task-1 (has execution logs in seed data)
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Execution log items should be visible
    // The mock data has logs with status: completed (完了), failed (失敗), running (実行中)
    // Use exact text match with emoji to avoid matching context text like "エンドポイント設計完了"
    await expect(dialog.getByText('✅ 完了')).toBeVisible()
    await expect(dialog.getByText('❌ 失敗')).toBeVisible()
    await expect(dialog.getByText('🔄 実行中')).toBeVisible()
  })

  test('History tab displays context items', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail for task-1 (has contexts in seed data)
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Context content should be visible
    await expect(dialog.getByText('エンドポイント設計完了')).toBeVisible()
    await expect(dialog.getByText('コントローラー実装中')).toBeVisible()
  })

  test('Can switch back to details tab', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()
    await expect(dialog.getByRole('button', { name: '履歴' })).toHaveClass(/text-blue-600/)

    // Switch back to details tab
    await dialog.getByRole('button', { name: '詳細' }).click()

    // Details tab should be active
    await expect(dialog.getByRole('button', { name: '詳細' })).toHaveClass(/text-blue-600/)

    // Details content should be visible again
    await expect(dialog.getByText('REST APIエンドポイントの実装')).toBeVisible()
  })

  test('Clicking view log button opens log viewer modal', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Click on a view log button (completed log)
    const viewLogButton = dialog.getByRole('button', { name: 'ログ表示' }).first()
    await viewLogButton.click()

    // Log viewer modal should open (nested dialog)
    const logViewerDialog = page.getByRole('dialog').last()
    await expect(logViewerDialog.getByRole('heading', { name: '実行ログ' })).toBeVisible()
  })

  test('Log viewer shows log metadata', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Click on view log button
    const viewLogButton = dialog.getByRole('button', { name: 'ログ表示' }).first()
    await viewLogButton.click()

    // Log viewer should show metadata
    const logViewerDialog = page.getByRole('dialog').last()
    await expect(logViewerDialog.getByText('Worker 1')).toBeVisible() // agent name
    await expect(logViewerDialog.getByText(/claude-sonnet/)).toBeVisible() // model
  })

  test('Can close log viewer modal', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Click on view log button
    const viewLogButton = dialog.getByRole('button', { name: 'ログ表示' }).first()
    await viewLogButton.click()

    // Log viewer should be open
    const logViewerDialog = page.getByRole('dialog').last()
    await expect(logViewerDialog.getByRole('heading', { name: '実行ログ' })).toBeVisible()

    // Close the log viewer
    await logViewerDialog.getByRole('button', { name: '閉じる' }).click()

    // Log viewer should be closed, but task detail panel should still be open
    await expect(page.getByRole('heading', { name: '実行ログ' })).not.toBeVisible()
    await expect(dialog.getByRole('button', { name: '履歴' })).toBeVisible()
  })

  test('History tab shows empty state for task without history', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail for task without execution logs or contexts
    await taskBoard.clickTask('DB設計')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Empty state message should be visible
    await expect(dialog.getByText('履歴がありません')).toBeVisible()
  })

  test('Execution log item displays correct status icons', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Status icons should be displayed (emoji-based)
    // Completed: ✅, Failed: ❌, Running: 🔄
    await expect(dialog.getByText('✅')).toBeVisible()
    await expect(dialog.getByText('❌')).toBeVisible()
    await expect(dialog.getByText('🔄')).toBeVisible()
  })

  test('Context item displays blocker with warning style', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Open task detail using task ID
    await taskBoard.clickTaskById('task-1')
    const dialog = page.getByRole('dialog').first()
    await expect(dialog).toBeVisible()

    // Switch to history tab
    await dialog.getByRole('button', { name: '履歴' }).click()

    // Blocker text should be visible (from seed data ctx-2 and ctx-3)
    await expect(dialog.getByText('テストデータの準備が必要')).toBeVisible()
    await expect(dialog.getByText('Worker-1のテストデータ待ち')).toBeVisible()
  })
})
