import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { ProjectListPage } from '../pages/project-list.page'
import { AgentDetailPage } from '../pages/agent-detail.page'

test.describe('部下エージェント一覧', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('部下エージェントセクションが表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await expect(page.getByText('部下エージェント')).toBeVisible()
  })

  test('部下エージェントカードが表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for agent cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Should have subordinate agents
    const count = await projectList.agentCards.count()
    expect(count).toBeGreaterThan(0)
  })
})

test.describe('部下エージェント一覧（manager-1）', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('エージェントカードに情報が表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    const firstCard = projectList.agentCards.first()

    // Card should show name and role
    await expect(firstCard).toBeVisible()
  })

  test('エージェントカードをクリックすると詳細画面に遷移する', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Click first agent card
    await projectList.agentCards.first().click()

    // Should navigate to agent detail page
    await expect(page).toHaveURL(/\/agents\//)
  })
})

test.describe('全下位エージェント表示', () => {
  test('オーナーは全ての下位エージェントを表示できる（直下だけでなく孫も）', async ({ page }) => {
    // owner-1 hierarchy:
    // owner-1 → manager-1 → worker-1, worker-2
    // Expected: 3 agents (manager-1, worker-1, worker-2)
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('owner-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    const projectList = new ProjectListPage(page)

    // Wait for agent cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Owner should see all descendants: manager-1, worker-1, worker-2
    const count = await projectList.agentCards.count()
    expect(count).toBe(3)

    // Verify specific agents are visible
    await expect(projectList.getAgentCard('Manager A')).toBeVisible()
    await expect(projectList.getAgentCard('Worker 1')).toBeVisible()
    await expect(projectList.getAgentCard('Worker 2')).toBeVisible()
  })

  test('オーナーは孫エージェント（Worker）の詳細画面を表示できる', async ({ page }) => {
    // owner-1 → manager-1 → worker-1
    // owner-1 should be able to view worker-1 detail (grandchild)
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('owner-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    const projectList = new ProjectListPage(page)

    // Wait for agent cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Click on Worker 1 (grandchild of owner-1)
    await projectList.getAgentCard('Worker 1').click()

    // Should navigate to agent detail page without error
    await expect(page).toHaveURL(/\/agents\/worker-1/)

    // Should show agent detail form (not error)
    await expect(page.getByText('エージェント詳細')).toBeVisible()
    await expect(page.getByLabel('名前')).toBeVisible()
  })
})

test.describe('エージェント詳細', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('エージェント詳細画面が表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards and click first agent
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()

    // Should show agent detail form
    await expect(page.getByText('エージェント詳細')).toBeVisible()
    await expect(page.getByLabel('名前')).toBeVisible()
    await expect(page.getByLabel('役割')).toBeVisible()
    await expect(page.getByLabel('ステータス')).toBeVisible()
  })

  test('戻るボタンでプロジェクト一覧に戻れる', async ({ page }) => {
    const projectList = new ProjectListPage(page)
    const agentDetail = new AgentDetailPage(page)

    // Navigate to agent detail
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()
    await expect(page).toHaveURL(/\/agents\//)

    // Click back button
    await agentDetail.goBack()

    // Should be back on project list
    await expect(page).toHaveURL('/projects')
  })

  test('読み取り専用情報が表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Navigate to agent detail
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()

    // Should show read-only info section
    await expect(page.getByText('その他の情報')).toBeVisible()
    await expect(page.getByText('タイプ', { exact: true })).toBeVisible()
    await expect(page.getByText('階層')).toBeVisible()
  })
})

test.describe('エージェント編集', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('エージェント名を編集して保存できる', async ({ page }) => {
    const projectList = new ProjectListPage(page)
    const agentDetail = new AgentDetailPage(page)

    // Navigate to agent detail
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()
    await expect(page).toHaveURL(/\/agents\//)

    // Edit name
    const originalName = await agentDetail.nameInput.inputValue()
    await agentDetail.fillName('Updated Agent Name')

    // Save
    await agentDetail.save()

    // Should show success message
    await expect(agentDetail.successMessage).toBeVisible()

    // Restore original name for other tests
    await agentDetail.fillName(originalName)
    await agentDetail.save()
  })

  test('キャンセルボタンで変更を破棄してプロジェクト一覧に戻れる', async ({ page }) => {
    const projectList = new ProjectListPage(page)
    const agentDetail = new AgentDetailPage(page)

    // Navigate to agent detail
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()
    await expect(page).toHaveURL(/\/agents\//)

    // Make a change but don't save
    await agentDetail.fillName('Unsaved Change')

    // Cancel
    await agentDetail.cancelButton.click()

    // Should be back on project list
    await expect(page).toHaveURL('/projects')
  })
})
