import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { ProjectListPage } from '../pages/project-list.page'

test.describe('プロジェクト一覧', () => {
  test.beforeEach(async ({ page }) => {
    // ログイン
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')
  })

  test('参加プロジェクト一覧が表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await expect(page.getByText('参加プロジェクト')).toBeVisible()
    await expect(projectList.projectCards).toHaveCount(2)
  })

  test('プロジェクトカードにプロジェクト情報が表示される', async ({ page }) => {
    const projectList = new ProjectListPage(page)
    const ecProject = projectList.getProjectCard('ECサイト開発')

    await expect(ecProject).toBeVisible()
    await expect(ecProject.getByText('ECサイトの新規開発プロジェクト')).toBeVisible()
    await expect(ecProject.getByText('タスク: 12')).toBeVisible()
    await expect(ecProject.getByText('あなたの担当: 3件')).toBeVisible()
  })

  test('プロジェクトをクリックするとタスクボードに遷移する', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await projectList.clickProject('ECサイト開発')

    await expect(page).toHaveURL(/\/projects\/project-1/)
  })

  test('ヘッダーにログイン中のエージェント名が表示される', async ({ page }) => {
    await expect(page.getByText('Manager A')).toBeVisible()
  })

  test('ログアウトボタンが機能する', async ({ page }) => {
    const projectList = new ProjectListPage(page)

    await projectList.logoutButton.click()

    await expect(page).toHaveURL('/login')
  })
})
