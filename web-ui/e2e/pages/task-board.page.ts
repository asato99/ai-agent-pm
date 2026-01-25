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
    this.createTaskButton = page.getByRole('button', { name: 'Create Task' })
    this.backButton = page.getByRole('link', { name: 'Projects' })
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

  async clickTaskById(taskId: string) {
    // Use data-testid to avoid matching the draggable wrapper
    await this.page.locator(`[data-task-id="${taskId}"][data-testid="task-card"]`).click()
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
    await this.page.getByLabel('Title').fill(data.title)
    if (data.description) {
      await this.page.getByLabel('Description').fill(data.description)
    }
    if (data.status) {
      await this.page.getByLabel('Status').selectOption(data.status)
    }
    if (data.priority) {
      await this.page.getByLabel('Priority').selectOption(data.priority)
    }
    if (data.assignee) {
      await this.page.getByLabel('Assignee').selectOption(data.assignee)
    }
  }

  async submitTaskForm() {
    await this.page.getByRole('button', { name: 'Create', exact: true }).click()
  }

  async closeModal() {
    await this.page.getByRole('button', { name: 'Close' }).click()
  }

  // Phase 4: Hierarchy Display Methods

  async getTaskCardDepthColor(taskId: string): Promise<string> {
    const card = this.page.locator(`[data-task-id="${taskId}"] [data-testid="task-card"]`)
    return card.evaluate((el) => {
      const style = window.getComputedStyle(el)
      return style.borderLeftColor
    })
  }

  async getParentBadgeText(taskId: string): Promise<string | null> {
    const badge = this.page.locator(
      `[data-task-id="${taskId}"] [data-testid="parent-badge"]`
    )
    if (await badge.isVisible()) {
      return badge.textContent()
    }
    return null
  }

  async clickParentBadge(taskId: string): Promise<void> {
    await this.page
      .locator(`[data-task-id="${taskId}"] [data-testid="parent-badge"]`)
      .click()
  }

  async getTaskOrderInColumn(status: string): Promise<string[]> {
    const column = this.getColumn(status)
    const cards = column.locator('[data-task-id]')
    const ids: string[] = []
    const count = await cards.count()
    for (let i = 0; i < count; i++) {
      const taskId = await cards.nth(i).getAttribute('data-task-id')
      if (taskId) {
        ids.push(taskId)
      }
    }
    return ids
  }

  async getDependencyIndicators(taskId: string): Promise<{
    upstream: number | null
    downstream: number | null
  }> {
    const card = this.page.locator(`[data-task-id="${taskId}"]`)

    const upstreamEl = card.locator('[data-testid="upstream-indicator"]')
    const downstreamEl = card.locator('[data-testid="downstream-indicator"]')

    const upstreamVisible = await upstreamEl.isVisible()
    const downstreamVisible = await downstreamEl.isVisible()

    const upstream = upstreamVisible
      ? parseInt((await upstreamEl.textContent()) || '0', 10)
      : null
    const downstream = downstreamVisible
      ? parseInt((await downstreamEl.textContent()) || '0', 10)
      : null

    return { upstream, downstream }
  }

  async getBlockedReasonText(taskId: string): Promise<string | null> {
    const blockedSection = this.page.locator(
      `[data-task-id="${taskId}"] [data-testid="blocked-reason"]`
    )
    if (await blockedSection.isVisible()) {
      return blockedSection.textContent()
    }
    return null
  }

  async clickBlockingTask(taskId: string, blockingTaskTitle: string): Promise<void> {
    const blockedSection = this.page.locator(
      `[data-task-id="${taskId}"] [data-testid="blocked-reason"]`
    )
    await blockedSection.getByText(blockingTaskTitle).click()
  }
}
