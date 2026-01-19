import { Page, Locator } from '@playwright/test'
import { BasePage } from './base.page'

export class TaskBoardPage extends BasePage {
  readonly createTaskButton: Locator
  readonly filterBar: Locator

  constructor(page: Page) {
    super(page)
    this.createTaskButton = page.getByRole('button', { name: 'タスク作成' })
    this.filterBar = page.locator('[data-testid="filter-bar"]')
  }

  async goto(projectId: string) {
    await super.goto(`/projects/${projectId}`)
  }

  getColumn(status: string): Locator {
    return this.page.locator(`[data-column="${status}"]`)
  }

  getTask(taskId: string): Locator {
    return this.page.locator(`[data-task-id="${taskId}"]`)
  }

  async dragTask(taskId: string, fromStatus: string, toStatus: string) {
    const task = this.getTask(taskId)
    const targetColumn = this.getColumn(toStatus)
    await task.dragTo(targetColumn)
  }

  async openCreateTaskModal() {
    await this.createTaskButton.click()
  }

  async fillTaskForm(data: {
    title: string
    description?: string
    priority?: string
    assignee?: string
  }) {
    await this.page.getByLabel('タイトル').fill(data.title)
    if (data.description) {
      await this.page.getByLabel('説明').fill(data.description)
    }
    if (data.priority) {
      await this.page.getByLabel('優先度').selectOption(data.priority)
    }
    if (data.assignee) {
      await this.page.getByLabel('担当エージェント').selectOption(data.assignee)
    }
  }

  async submitTaskForm() {
    await this.page.getByRole('button', { name: '作成' }).click()
  }
}
