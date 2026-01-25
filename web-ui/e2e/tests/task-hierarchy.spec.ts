import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'

test.describe('Task Hierarchy Display', () => {
  let taskBoard: TaskBoardPage

  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // Navigate to project page
    taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('displays depth indicator colors correctly', async ({ page }) => {
    // L0 task (blue) - API実装 (task-1) - check for blue border class
    const task1Card = page.locator('[data-task-id="task-1"] [data-testid="task-card"]')
    await expect(task1Card).toHaveClass(/border-l-blue-500/)

    // L1 task (green) - エンドポイント実装 (task-3, child of task-1)
    const task3Card = page.locator('[data-task-id="task-3"] [data-testid="task-card"]')
    await expect(task3Card).toHaveClass(/border-l-green-500/)

    // L2 task (yellow) - ユーザーAPI (task-4, grandchild)
    const task4Card = page.locator('[data-task-id="task-4"] [data-testid="task-card"]')
    await expect(task4Card).toHaveClass(/border-l-yellow-500/)
  })

  test('displays parent badge for child tasks', async ({ page }) => {
    // task-3 has parent task-1 (API実装)
    const card = page.locator('[data-task-id="task-3"][data-testid="task-card"]')
    const badge = card.locator('[data-testid="parent-badge"]')
    await expect(badge).toBeVisible()
    await expect(badge).toContainText('API実装')
  })

  test('navigates to parent task when badge clicked', async ({ page }) => {
    // Click parent badge on task-3
    await taskBoard.clickParentBadge('task-3')

    // Parent task detail panel should open
    await expect(page.locator('[role="dialog"]')).toContainText('API実装')
  })

  test('sorts tasks hierarchically within column', async ({ page }) => {
    // Wait for the todo column to be visible with task-3
    await page.waitForSelector('[data-column="todo"] [data-task-id="task-3"]')

    // In todo column: task-3 should be visible
    const order = await taskBoard.getTaskOrderInColumn('todo')

    // task-3 (child of task-1) should be in todo
    expect(order).toContain('task-3')
  })

  test('displays dependency indicators', async ({ page }) => {
    // task-1 has 1 dependency (task-2) and 1 dependent (task-3)
    const card = page.locator('[data-task-id="task-1"]')

    // Check upstream indicator is visible and shows "1"
    const upstreamIndicator = card.locator('[data-testid="upstream-indicator"]')
    await expect(upstreamIndicator).toBeVisible()
    await expect(upstreamIndicator).toContainText('1')

    // Check downstream indicator is visible and shows "1"
    const downstreamIndicator = card.locator('[data-testid="downstream-indicator"]')
    await expect(downstreamIndicator).toBeVisible()
    await expect(downstreamIndicator).toContainText('1')
  })
})

test.describe('Blocked Task Display', () => {
  let taskBoard: TaskBoardPage

  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // Navigate to project page
    taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('shows blocking reason in blocked column', async ({ page }) => {
    // task-5 is in blocked column with blocking dependencies
    const card = page.locator('[data-task-id="task-5"][data-testid="task-card"]')
    await expect(card).toBeVisible()

    // Check blocked reason section
    const blockedSection = card.locator('[data-testid="blocked-reason"]')
    await expect(blockedSection).toBeVisible()
    await expect(blockedSection).toContainText('Blocked by:')
    await expect(blockedSection).toContainText('API実装') // task-1 title
  })

  test('navigates to blocking task when clicked', async ({ page }) => {
    // Click on blocking task in blocked reason section
    await taskBoard.clickBlockingTask('task-5', 'API実装')

    // Blocking task detail panel should open
    await expect(page.locator('[role="dialog"]')).toContainText('API実装')
  })
})

test.describe('Task Detail Panel - Hierarchy', () => {
  let taskBoard: TaskBoardPage

  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // Navigate to project page
    taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')
  })

  test('displays hierarchy path for nested task', async ({ page }) => {
    // Click on grandchild task (task-4 - ユーザーAPI)
    // Click on the task title specifically to avoid hitting the parent badge
    const task4Card = page.locator('[data-task-id="task-4"][data-testid="task-card"]')
    await task4Card.locator('h4').click()

    // Detail panel should show hierarchy path with ancestors
    const path = page.locator('[data-testid="hierarchy-path"]')
    await expect(path).toBeVisible()
    // task-4's ancestors: task-3 (parent) → task-1 (grandparent)
    await expect(path).toContainText('API実装')  // grandparent
    await expect(path).toContainText('エンドポイント実装')  // parent
  })

  test('displays child tasks list', async ({ page }) => {
    // Click on parent task (task-1) by data-task-id
    // Use combined selector to avoid dnd-kit wrapper element conflict
    await page.locator('[data-task-id="task-1"][data-testid="task-card"]').click()

    // Detail panel should show children section
    const childSection = page.locator('[data-testid="children-section"]')
    await expect(childSection).toBeVisible()
    await expect(childSection).toContainText('子タスク')
    await expect(childSection).toContainText('エンドポイント実装')
  })

  test('displays upstream and downstream dependencies', async ({ page }) => {
    // Click on task-1 by data-task-id
    // Use combined selector to avoid dnd-kit wrapper element conflict
    await page.locator('[data-task-id="task-1"][data-testid="task-card"]').click()

    // Check upstream dependencies (depends on task-2 DB設計)
    const upstream = page.locator('[data-testid="upstream-dependencies"]')
    await expect(upstream).toBeVisible()
    await expect(upstream).toContainText('依存先')
    await expect(upstream).toContainText('DB設計')

    // Check downstream dependencies (task-3 depends on this)
    const downstream = page.locator('[data-testid="downstream-dependencies"]')
    await expect(downstream).toBeVisible()
    await expect(downstream).toContainText('依存元')
    await expect(downstream).toContainText('エンドポイント実装')
  })
})
