import { test as base, Page } from '@playwright/test'

interface AuthFixtures {
  authenticatedPage: Page
}

export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    // Mock authentication by setting localStorage
    await page.goto('/')
    await page.evaluate(() => {
      localStorage.setItem('sessionToken', 'test-session-token')
      localStorage.setItem(
        'auth-storage',
        JSON.stringify({
          state: {
            isAuthenticated: true,
            agent: {
              id: 'manager-1',
              name: 'Manager A',
              role: 'Backend Manager',
              agentType: 'ai',
              status: 'active',
              hierarchyType: 'manager',
              parentId: 'owner-1',
            },
            sessionToken: 'test-session-token',
          },
          version: 0,
        })
      )
    })
    await use(page)
  },
})

export { expect } from '@playwright/test'
