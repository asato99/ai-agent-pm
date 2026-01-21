import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { ProjectListPage } from '../pages/project-list.page'
import { AgentDetailPage } from '../pages/agent-detail.page'

test.describe('Subordinate Agent List', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('Subordinate agents section is displayed', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await expect(page.getByText('Subordinate Agents')).toBeVisible()
  })

  test('Subordinate agent cards are displayed', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for agent cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Should have subordinate agents
    const count = await projectList.agentCards.count()
    expect(count).toBeGreaterThan(0)
  })
})

test.describe('Subordinate Agent List (manager-1)', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('Agent card displays information', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    const firstCard = projectList.agentCards.first()

    // Card should show name and role
    await expect(firstCard).toBeVisible()
  })

  test('Clicking agent card navigates to detail page', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards to load
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })

    // Click first agent card
    await projectList.agentCards.first().click()

    // Should navigate to agent detail page
    await expect(page).toHaveURL(/\/agents\//)
  })
})

test.describe('All Descendant Agents Display', () => {
  test('Owner can view all descendant agents (not just direct children but also grandchildren)', async ({ page }) => {
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

  test('Owner can view grandchild agent (Worker) detail page', async ({ page }) => {
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
    await expect(page.getByText('Agent Detail')).toBeVisible()
    await expect(page.getByLabel('Name')).toBeVisible()
  })
})

test.describe('Agent Detail', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('Agent detail page is displayed', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Wait for cards and click first agent
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()

    // Should show agent detail form
    await expect(page.getByText('Agent Detail')).toBeVisible()
    await expect(page.getByLabel('Name')).toBeVisible()
    await expect(page.getByLabel('Role')).toBeVisible()
    await expect(page.getByLabel('Status')).toBeVisible()
  })

  test('Back button returns to project list', async ({ page }) => {
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

  test('Read-only information is displayed', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    // Navigate to agent detail
    await expect(projectList.agentCards.first()).toBeVisible({ timeout: 10000 })
    await projectList.agentCards.first().click()

    // Should show read-only info section (displayed as "Additional Info")
    await expect(page.getByText('Additional Info')).toBeVisible()
    await expect(page.getByText('Type', { exact: true })).toBeVisible()
    await expect(page.getByText('Hierarchy')).toBeVisible()
  })
})

test.describe('Agent Edit', () => {
  test.beforeEach(async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('Can edit and save agent name', async ({ page }) => {
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

  test('Cancel button discards changes and returns to project list', async ({ page }) => {
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
