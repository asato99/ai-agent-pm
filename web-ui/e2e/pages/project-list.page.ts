import { Page, Locator } from '@playwright/test'

export class ProjectListPage {
  readonly page: Page
  readonly projectCards: Locator
  readonly header: Locator
  readonly agentName: Locator
  readonly logoutButton: Locator
  readonly archivedSection: Locator

  constructor(page: Page) {
    this.page = page
    this.projectCards = page.locator('[data-testid="project-card"]')
    this.header = page.locator('header')
    this.agentName = page.getByTestId('agent-name')
    this.logoutButton = page.getByRole('button', { name: 'ログアウト' })
    this.archivedSection = page.getByTestId('archived-projects')
  }

  async goto() {
    await this.page.goto('/projects')
  }

  getProjectCard(projectName: string): Locator {
    return this.page.locator(`[data-testid="project-card"]`, {
      has: this.page.getByText(projectName),
    })
  }

  async clickProject(projectName: string) {
    await this.getProjectCard(projectName).click()
  }

  async toggleArchivedSection() {
    await this.archivedSection.getByRole('button').click()
  }
}
