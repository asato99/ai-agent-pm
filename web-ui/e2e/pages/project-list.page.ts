import { Page, Locator } from '@playwright/test'

export class ProjectListPage {
  readonly page: Page
  readonly projectCards: Locator
  readonly header: Locator
  readonly agentName: Locator
  readonly logoutButton: Locator
  readonly archivedSection: Locator
  readonly agentCards: Locator
  readonly subordinatesSection: Locator

  constructor(page: Page) {
    this.page = page
    this.projectCards = page.locator('[data-testid="project-card"]')
    this.header = page.locator('header')
    this.agentName = page.getByTestId('agent-name')
    this.logoutButton = page.getByRole('button', { name: 'Log out' })
    this.archivedSection = page.getByTestId('archived-projects')
    this.agentCards = page.locator('[data-testid="agent-card"]')
    this.subordinatesSection = page.getByText('Subordinate Agents').locator('..')
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

  getAgentCard(agentName: string): Locator {
    return this.page.locator(`[data-testid="agent-card"]`, {
      has: this.page.getByText(agentName),
    })
  }

  async clickAgent(agentName: string) {
    await this.getAgentCard(agentName).click()
  }
}
