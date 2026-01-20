import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { ProjectListPage } from '../pages/project-list.page'

test.describe('Project List', () => {
  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('Project list is displayed', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await expect(page.getByText('My Projects')).toBeVisible()
    await expect(projectList.projectCards).toHaveCount(2)
  })

  test('Project card displays project information', async ({ page }) => {
    const projectList = new ProjectListPage(page)
    const ecProject = projectList.getProjectCard('ECサイト開発')

    await expect(ecProject).toBeVisible()
    await expect(ecProject.getByText('ECサイトの新規開発プロジェクト')).toBeVisible()
    await expect(ecProject.getByText('Tasks: 12')).toBeVisible()
    await expect(ecProject.getByText('My Tasks: 3')).toBeVisible()
  })

  test('Clicking project navigates to task board', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await projectList.clickProject('ECサイト開発')

    await expect(page).toHaveURL(/\/projects\/project-1/)
  })

  test('Header displays logged-in agent name', async ({ page }) => {
    await expect(page.getByText('Manager A')).toBeVisible()
  })

  test('Logout button works', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await projectList.logoutButton.click()

    await expect(page).toHaveURL('/login')
  })
})
