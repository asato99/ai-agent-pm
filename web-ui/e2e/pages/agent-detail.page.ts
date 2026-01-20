import { Page, Locator } from '@playwright/test'

export class AgentDetailPage {
  readonly page: Page
  readonly backButton: Locator
  readonly nameInput: Locator
  readonly roleInput: Locator
  readonly statusSelect: Locator
  readonly maxParallelTasksInput: Locator
  readonly systemPromptTextarea: Locator
  readonly saveButton: Locator
  readonly cancelButton: Locator
  readonly successMessage: Locator
  readonly errorMessage: Locator
  readonly lockedWarning: Locator

  constructor(page: Page) {
    this.page = page
    this.backButton = page.getByRole('button', { name: /戻る/ })
    this.nameInput = page.getByLabel('名前')
    this.roleInput = page.getByLabel('役割')
    this.statusSelect = page.getByLabel('ステータス')
    this.maxParallelTasksInput = page.getByLabel('最大並列タスク数')
    this.systemPromptTextarea = page.getByLabel('システムプロンプト')
    this.saveButton = page.getByRole('button', { name: '保存' })
    this.cancelButton = page.getByRole('button', { name: 'キャンセル' })
    this.successMessage = page.getByText('保存しました')
    this.errorMessage = page.locator('.bg-red-50')
    this.lockedWarning = page.getByText('ロックされているため編集できません')
  }

  async goto(agentId: string) {
    await this.page.goto(`/agents/${agentId}`)
  }

  async fillName(name: string) {
    await this.nameInput.clear()
    await this.nameInput.fill(name)
  }

  async fillRole(role: string) {
    await this.roleInput.clear()
    await this.roleInput.fill(role)
  }

  async selectStatus(status: string) {
    await this.statusSelect.selectOption(status)
  }

  async fillMaxParallelTasks(count: number) {
    await this.maxParallelTasksInput.clear()
    await this.maxParallelTasksInput.fill(count.toString())
  }

  async fillSystemPrompt(prompt: string) {
    await this.systemPromptTextarea.clear()
    await this.systemPromptTextarea.fill(prompt)
  }

  async save() {
    await this.saveButton.click()
  }

  async goBack() {
    await this.backButton.click()
  }

  getInfoValue(label: string): Locator {
    return this.page.locator('dt', { hasText: label }).locator('+ dd')
  }
}
