import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'

test.describe('Authentication', () => {
  test('Can login with valid credentials', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('manager-1', 'test-passkey')

    await expect(page).toHaveURL('/projects')
    await expect(page.getByText('My Projects')).toBeVisible()
  })

  test('Shows error with invalid credentials', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('invalid-agent', 'wrong-passkey')

    await expect(loginPage.errorMessage).toBeVisible()
    await expect(loginPage.errorMessage).toContainText('Authentication failed')
    await expect(page).toHaveURL('/login')
  })

  test('Redirects to login page when accessing project list without authentication', async ({
    page,
  }) => {
    await page.goto('/projects')

    await expect(page).toHaveURL('/login')
  })

  test('Logout returns to login page', async ({ page }) => {
    // Set up authentication state
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')

    // Click logout button
    await page.getByRole('button', { name: 'Log out' }).click()

    await expect(page).toHaveURL('/login')
  })

  test('Username is displayed after login', async ({ page }) => {
    const loginPage = new LoginPage(page)
    await loginPage.goto()

    await loginPage.login('manager-1', 'test-passkey')

    await expect(page.getByText('Manager A')).toBeVisible()
  })
})
