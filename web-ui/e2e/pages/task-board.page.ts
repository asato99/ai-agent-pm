import { Page, Locator } from '@playwright/test'
import { BasePage } from './base.page'

export class TaskBoardPage extends BasePage {
  readonly projectTitle: Locator
  readonly createTaskButton: Locator
  readonly backButton: Locator
  readonly filterBar: Locator
  readonly columns: Locator
  readonly taskCards: Locator

  constructor(page: Page) {
    super(page)
    this.projectTitle = page.getByTestId('project-title')
    this.createTaskButton = page.getByRole('button', { name: 'タスク作成' })
    this.backButton = page.getByRole('link', { name: 'プロジェクト一覧' })
    this.filterBar = page.locator('[data-testid="filter-bar"]')
    this.columns = page.locator('[data-testid="kanban-column"]')
    this.taskCards = page.locator('[data-testid="task-card"]')
  }

  async goto(projectId: string) {
    await super.goto(`/projects/${projectId}`)
  }

  getColumn(status: string): Locator {
    return this.page.locator(`[data-column="${status}"]`)
  }

  getColumnTaskCount(status: string): Locator {
    return this.getColumn(status).getByTestId('task-count')
  }

  getTask(taskId: string): Locator {
    // Select the draggable element (dnd-kit adds aria-roledescription="draggable")
    return this.page.locator(`[data-task-id="${taskId}"][aria-roledescription="draggable"]`)
  }

  getTaskCard(taskTitle: string): Locator {
    return this.page.locator('[data-testid="task-card"]', {
      has: this.page.getByText(taskTitle),
    })
  }

  getTaskCardInColumn(status: string, taskTitle: string): Locator {
    return this.getColumn(status).locator('[data-testid="task-card"]', {
      has: this.page.getByText(taskTitle),
    })
  }

  async dragTask(taskId: string, toStatus: string) {
    const task = this.getTask(taskId)
    const targetColumn = this.getColumn(toStatus)

    // dnd-kit uses pointer events, so we need to use mouse API
    const taskBounds = await task.boundingBox()
    const targetBounds = await targetColumn.boundingBox()

    if (!taskBounds || !targetBounds) {
      throw new Error('Could not get element bounds')
    }

    const startX = taskBounds.x + taskBounds.width / 2
    const startY = taskBounds.y + taskBounds.height / 2
    const endX = targetBounds.x + targetBounds.width / 2
    const endY = targetBounds.y + 100 // Drop in upper part of column

    // Perform drag with mouse API
    await this.page.mouse.move(startX, startY)
    await this.page.mouse.down()
    // Move in steps to trigger dnd-kit's activation constraint (10px distance)
    await this.page.mouse.move(startX + 15, startY)
    await this.page.mouse.move(endX, endY, { steps: 10 })
    await this.page.mouse.up()
  }

  async clickTask(taskTitle: string) {
    await this.getTaskCard(taskTitle).click()
  }

  async openCreateTaskModal() {
    await this.createTaskButton.click()
  }

  async fillTaskForm(data: {
    title: string
    description?: string
    status?: string
    priority?: string
    assignee?: string
  }) {
    await this.page.getByLabel('タイトル').fill(data.title)
    if (data.description) {
      await this.page.getByLabel('説明').fill(data.description)
    }
    if (data.status) {
      await this.page.getByLabel('ステータス').selectOption(data.status)
    }
    if (data.priority) {
      await this.page.getByLabel('優先度').selectOption(data.priority)
    }
    if (data.assignee) {
      await this.page.getByLabel('担当エージェント').selectOption(data.assignee)
    }
  }

  async submitTaskForm() {
    await this.page.getByRole('button', { name: '作成', exact: true }).click()
  }

  async closeModal() {
    await this.page.getByRole('button', { name: '閉じる' }).click()
  }

  async openTaskMenu(taskTitle: string) {
    const taskCard = this.getTaskCard(taskTitle)
    const menuButton = taskCard.getByRole('button', { name: 'メニュー' })
    await menuButton.click()
  }
}
