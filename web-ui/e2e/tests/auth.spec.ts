import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'

test.describe('認証', () => {
  test('正しい認証情報でログインできる', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('manager-1', 'test-passkey')

    await expect(page).toHaveURL('/projects')
    await expect(page.getByText('参加プロジェクト')).toBeVisible()
  })

  test('不正な認証情報でエラーが表示される', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('invalid-agent', 'wrong-passkey')

    await expect(loginPage.errorMessage).toBeVisible()
    await expect(loginPage.errorMessage).toContainText('認証に失敗しました')
    await expect(page).toHaveURL('/login')
  })

  test('未認証状態でプロジェクト一覧にアクセスするとログイン画面にリダイレクトされる', async ({
    page,
  }) => {
    await page.goto('/projects')

    await expect(page).toHaveURL('/login')
  })

  test('ログアウトするとログイン画面に戻る', async ({ page }) => {
    // 事前に認証状態を設定
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')

    // ログアウトボタンをクリック
    await page.getByRole('button', { name: 'ログアウト' }).click()

    await expect(page).toHaveURL('/login')
  })

  test('ログイン後にユーザー名が表示される', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('manager-1', 'test-passkey')

    await expect(page.getByText('Manager A')).toBeVisible()
  })
})
