import { Page, Locator } from '@playwright/test'
import { BasePage } from './base.page'

export class LoginPage extends BasePage {
  readonly agentIdInput: Locator
  readonly passkeyInput: Locator
  readonly loginButton: Locator
  readonly errorMessage: Locator

  constructor(page: Page) {
    super(page)
    this.agentIdInput = page.getByLabel('Agent ID')
    this.passkeyInput = page.getByLabel('Passkey')
    this.loginButton = page.getByRole('button', { name: 'ログイン' })
    this.errorMessage = page.getByRole('alert')
  }

  async goto() {
    await super.goto('/login')
  }

  async login(agentId: string, passkey: string) {
    await this.agentIdInput.fill(agentId)
    await this.passkeyInput.fill(passkey)
    await this.loginButton.click()
  }
}
