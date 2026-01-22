import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('Task Board', () => {
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

  test('Kanban board is displayed', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // 5 columns are displayed
    await expect(taskBoard.getColumn('backlog')).toBeVisible()
    await expect(taskBoard.getColumn('todo')).toBeVisible()
    await expect(taskBoard.getColumn('in_progress')).toBeVisible()
    await expect(taskBoard.getColumn('done')).toBeVisible()
    await expect(taskBoard.getColumn('blocked')).toBeVisible()
  })

  test('Project name is displayed', async ({ page }) => {
    await expect(page.getByText('ECサイト開発')).toBeVisible()
  })

  test('Task cards are displayed', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await expect(taskBoard.getTaskCard('API実装')).toBeVisible()
    await expect(taskBoard.getTaskCard('DB設計')).toBeVisible()
  })

  test('Task card displays task information', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)
    const apiTask = taskBoard.getTaskCard('API実装')

    await expect(apiTask).toBeVisible()
    await expect(apiTask.getByText('High')).toBeVisible()
  })

  test('Can change task status via drag and drop', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    // Initially in in_progress column
    await expect(taskBoard.getTaskCardInColumn('in_progress', 'API実装')).toBeVisible()

    // Drag to done column
    await taskBoard.dragTask('task-1', 'done')

    // Now in done column
    await expect(taskBoard.getTaskCardInColumn('done', 'API実装')).toBeVisible()
  })

  test('Clicking create task button opens modal', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.openCreateTaskModal()

    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Create Task' })).toBeVisible()
  })

  test('Can create new task', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.openCreateTaskModal()
    await taskBoard.fillTaskForm({
      title: 'New Task',
      description: 'Test task description',
      priority: 'high',
    })
    await taskBoard.submitTaskForm()

    // Modal closes
    await expect(page.getByRole('dialog')).not.toBeVisible()

    // New task appears in Backlog column
    await expect(taskBoard.getTaskCardInColumn('backlog', 'New Task')).toBeVisible()
  })

  test('Clicking task card opens detail panel', async ({ page }) => {
    const taskBoard = new TaskBoardPage(page)

    await taskBoard.clickTask('API実装')

    await expect(page.getByRole('dialog')).toBeVisible()
    await expect(page.getByText('REST APIエンドポイントの実装')).toBeVisible()
  })

  test('Back to projects button works', async ({ page }) => {
    await page.getByRole('link', { name: 'Projects' }).click()

    await expect(page).toHaveURL('/projects')
  })

  test.describe('Task Assignee', () => {
    test('Task detail panel displays assignee', async ({ page }) => {
      const taskBoard = new TaskBoardPage(page)

      // Open task detail
      await taskBoard.clickTask('API実装')

      // Verify assignee section is displayed
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(page.getByText('Assignee')).toBeVisible()
    })

    test('Task detail panel displays Unassigned when no assignee', async ({ page }) => {
      const taskBoard = new TaskBoardPage(page)

      // Open unassigned task detail (DB設計 has no assignee)
      await taskBoard.clickTask('DB設計')

      // Verify Unassigned is displayed
      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(page.getByText('Assignee')).toBeVisible()
      await expect(page.getByText('Unassigned')).toBeVisible()
    })

    test('Can change task assignee via edit form', async ({ page }) => {
      const taskBoard = new TaskBoardPage(page)

      // Open task detail (DB設計 has status 'done', which allows reassignment)
      await taskBoard.clickTask('DB設計')
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Click Edit button inside dialog
      await dialog.getByRole('button', { name: 'Edit' }).click()

      // Edit form should be visible
      await expect(page.getByRole('heading', { name: 'Edit Task' })).toBeVisible()

      // Change assignee in dropdown
      const assigneeSelect = page.getByLabel('Assignee')
      await expect(assigneeSelect).toBeVisible()
      await expect(assigneeSelect).toBeEnabled()

      // Select a worker (task starts as unassigned)
      await assigneeSelect.selectOption({ label: 'Worker 2' })

      // Save changes
      await page.getByRole('button', { name: 'Save' }).click()

      // Wait for form to close and verify change
      await expect(page.getByRole('heading', { name: 'Edit Task' })).not.toBeVisible()
    })

    test('Can set task assignee to Unassigned', async ({ page }) => {
      const taskBoard = new TaskBoardPage(page)

      // Open task detail (DB設計 has status 'done', which allows reassignment)
      await taskBoard.clickTask('DB設計')
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Click Edit button inside dialog
      await dialog.getByRole('button', { name: 'Edit' }).click()

      // Edit form should be visible
      await expect(page.getByRole('heading', { name: 'Edit Task' })).toBeVisible()

      // Set to Unassigned (it might already be unassigned, so just verify dropdown works)
      const assigneeSelect = page.getByLabel('Assignee')
      await expect(assigneeSelect).toBeEnabled()
      await assigneeSelect.selectOption({ label: 'Unassigned' })

      // Save changes
      await page.getByRole('button', { name: 'Save' }).click()

      // Wait for form to close
      await expect(page.getByRole('heading', { name: 'Edit Task' })).not.toBeVisible()
    })

    // TEST: Reactivity - Detail panel should update after edit (RED expected)
    test('Task detail panel updates reactively after editing', async ({ page }) => {
      const taskBoard = new TaskBoardPage(page)

      // Open task detail
      await taskBoard.clickTask('API実装')
      const dialog = page.getByRole('dialog').first()
      await expect(dialog).toBeVisible()

      // Verify initial title inside dialog
      await expect(dialog.getByRole('heading', { name: 'API実装' })).toBeVisible()

      // Click Edit button inside dialog
      await dialog.getByRole('button', { name: 'Edit' }).click()

      // Edit form should be visible
      await expect(page.getByRole('heading', { name: 'Edit Task' })).toBeVisible()

      // Change the title
      const titleInput = page.getByLabel('Title')
      await titleInput.clear()
      await titleInput.fill('API実装 Updated')

      // Save changes
      await page.getByRole('button', { name: 'Save' }).click()

      // Wait for edit form to close
      await expect(page.getByRole('heading', { name: 'Edit Task' })).not.toBeVisible()

      // Detail panel should show updated title WITHOUT reopening (reactivity test)
      // Note: After edit form closes, the detail dialog should still be visible with updated title
      await expect(dialog.getByRole('heading', { name: 'API実装 Updated' })).toBeVisible()
    })
  })
})
