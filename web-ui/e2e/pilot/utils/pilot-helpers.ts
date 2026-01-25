import { Page, expect } from '@playwright/test'

/**
 * Configuration for pilot test timeouts and thresholds
 */
export interface PilotConfig {
  /** Total scenario timeout in milliseconds (default: 30 minutes) */
  scenarioTimeout: number
  /** Individual phase timeout in milliseconds (default: 10 minutes) */
  phaseTimeout: number
  /** Single task completion timeout in milliseconds (default: 5 minutes) */
  taskTimeout: number
  /** Polling interval in milliseconds (default: 5 seconds) */
  pollInterval: number
  /** Time without progress before considering stale in milliseconds (default: 5 minutes) */
  staleThreshold: number
}

export const DEFAULT_PILOT_CONFIG: PilotConfig = {
  scenarioTimeout: 30 * 60 * 1000, // 30 minutes
  phaseTimeout: 10 * 60 * 1000, // 10 minutes
  taskTimeout: 5 * 60 * 1000, // 5 minutes
  pollInterval: 5 * 1000, // 5 seconds
  staleThreshold: 5 * 60 * 1000, // 5 minutes
}

/**
 * Task status information
 */
export interface TaskStatus {
  id: string
  title: string
  status: string
}

/**
 * Result of waiting for task completion
 */
export interface WaitResult {
  success: boolean
  tasks: TaskStatus[]
  reason?: string
}

/**
 * Login as Owner (human role operated by test script)
 */
export async function loginAsOwner(
  page: Page,
  agentId: string,
  passkey: string
): Promise<void> {
  await page.goto('/login')
  await page.getByLabel('Agent ID').fill(agentId)
  await page.getByLabel('Passkey').fill(passkey)
  await page.getByRole('button', { name: 'Log in' }).click()
  await expect(page).toHaveURL('/projects')
}

/**
 * Navigate to a specific project's task board
 */
export async function navigateToProject(
  page: Page,
  projectId: string
): Promise<void> {
  await page.goto(`/projects/${projectId}`)
  // Wait for kanban columns to be visible (indicates task board is loaded)
  await expect(page.locator('[data-testid="kanban-column"]').first()).toBeVisible({
    timeout: 10000,
  })
}

/**
 * Open chat panel and send a message to Manager
 * Note: With real AI agents, the session may take 30-60 seconds to become ready
 * as the Coordinator spawns the agent and the agent establishes the session.
 */
export async function sendRequirementToManager(
  page: Page,
  managerId: string,
  message: string
): Promise<void> {
  // Click on the agent avatar to open chat panel
  const agentAvatar = page.locator(`[data-testid="agent-avatar-${managerId}"]`)
  await expect(agentAvatar).toBeVisible({ timeout: 5000 })
  await agentAvatar.click()

  // Wait for chat panel to be visible
  const chatPanel = page.locator('[data-testid="chat-panel"]')
  await expect(chatPanel).toBeVisible({ timeout: 5000 })

  console.log('[Pilot] Chat panel opened, waiting for session to be ready...')

  // Wait for session to be ready (send button should not show "準備中...")
  // This may take a while as the AI agent needs to be spawned and establish the session
  // Poll for up to 2 minutes (real AI agents can take time to start)
  const chatInput = chatPanel.locator('[data-testid="chat-input"]')
  const sessionTimeout = 120000 // 2 minutes
  const pollInterval = 3000 // 3 seconds
  const startTime = Date.now()

  while (Date.now() - startTime < sessionTimeout) {
    const isEnabled = await chatInput.isEnabled()
    if (isEnabled) {
      console.log('[Pilot] Chat session is ready')
      break
    }
    const elapsed = Math.round((Date.now() - startTime) / 1000)
    console.log(`[Pilot] Waiting for chat session... (${elapsed}s)`)
    await page.waitForTimeout(pollInterval)
  }

  await expect(chatInput).toBeEnabled({ timeout: 5000 })

  // Type message
  await chatInput.fill(message)

  // Click send button
  const sendButton = chatPanel.locator('[data-testid="chat-send-button"]')
  await expect(sendButton).toBeEnabled({ timeout: 5000 })
  await sendButton.click()

  console.log('[Pilot] Message sent to Manager')

  // Wait for message to appear in chat (it should be visible after sending)
  await page.waitForTimeout(1000) // Brief wait for message to be added
  await expect(chatPanel.getByText(message.substring(0, 30))).toBeVisible({ timeout: 5000 })
}

/**
 * Get current task statuses from the task board
 */
export async function getTaskStatuses(page: Page): Promise<TaskStatus[]> {
  const tasks: TaskStatus[] = []

  // Find all task cards
  const taskCards = page.locator('[data-testid="task-card"]')
  const count = await taskCards.count()

  for (let i = 0; i < count; i++) {
    const card = taskCards.nth(i)

    // Get task ID from data attribute
    const id = (await card.getAttribute('data-task-id')) || `unknown-${i}`

    // Get task title
    const titleElement = card.locator('[data-testid="task-title"]')
    const title = (await titleElement.isVisible())
      ? ((await titleElement.textContent()) || '')
      : ''

    // Get status from parent column's data-column attribute
    // The task card is inside a column with data-column="todo|in_progress|done|etc"
    const columnAttribute = await card.evaluate((el) => {
      const column = el.closest('[data-column]')
      return column?.getAttribute('data-column') || ''
    })

    tasks.push({ id, title, status: columnAttribute })
  }

  return tasks
}

/**
 * Wait for all tasks to complete (reach 'done' status)
 * Includes progress monitoring and stale detection
 */
export async function waitForAllTasksComplete(
  page: Page,
  config: PilotConfig = DEFAULT_PILOT_CONFIG
): Promise<WaitResult> {
  const startTime = Date.now()
  let lastProgressTime = Date.now()
  let previousTaskStates = ''

  console.log(
    `[Pilot] Waiting for tasks to complete (timeout: ${config.scenarioTimeout / 1000}s)`
  )

  while (Date.now() - startTime < config.scenarioTimeout) {
    // Refresh page to get latest state
    await page.reload()
    await page.waitForTimeout(1000) // Wait for page to load

    // Get current task states
    const tasks = await getTaskStatuses(page)
    const currentStates = JSON.stringify(tasks)

    // Check if all tasks are done
    const allDone =
      tasks.length > 0 && tasks.every((t) => t.status === 'done')
    if (allDone) {
      console.log(
        `[Pilot] All ${tasks.length} tasks completed in ${(Date.now() - startTime) / 1000}s`
      )
      return { success: true, tasks }
    }

    // Progress check
    if (currentStates !== previousTaskStates) {
      lastProgressTime = Date.now()
      previousTaskStates = currentStates
      const elapsed = Math.round((Date.now() - startTime) / 1000)
      console.log(
        `[Pilot] Progress (${elapsed}s): ${tasks.map((t) => `${t.title || t.id}:${t.status}`).join(', ')}`
      )
    }

    // Stale detection
    const timeSinceProgress = Date.now() - lastProgressTime
    if (timeSinceProgress > config.staleThreshold) {
      console.warn(
        `[Pilot] WARNING: No progress for ${timeSinceProgress / 1000}s`
      )
      // Continue waiting but log warning
    }

    // Wait before next poll
    await page.waitForTimeout(config.pollInterval)
  }

  // Timeout reached
  const tasks = await getTaskStatuses(page)
  console.error(
    `[Pilot] Timeout after ${config.scenarioTimeout / 1000}s. Final state: ${tasks.map((t) => `${t.title || t.id}:${t.status}`).join(', ')}`
  )
  return { success: false, tasks, reason: 'timeout' }
}

/**
 * Wait for at least N tasks to be created
 */
export async function waitForTasksCreated(
  page: Page,
  minTasks: number,
  timeout: number = 5 * 60 * 1000
): Promise<WaitResult> {
  const startTime = Date.now()

  console.log(
    `[Pilot] Waiting for at least ${minTasks} tasks to be created (timeout: ${timeout / 1000}s)`
  )

  while (Date.now() - startTime < timeout) {
    await page.reload()
    await page.waitForTimeout(1000)

    const tasks = await getTaskStatuses(page)

    if (tasks.length >= minTasks) {
      console.log(`[Pilot] ${tasks.length} tasks created`)
      return { success: true, tasks }
    }

    console.log(`[Pilot] Current task count: ${tasks.length}, waiting...`)
    await page.waitForTimeout(5000)
  }

  const tasks = await getTaskStatuses(page)
  return { success: false, tasks, reason: 'timeout waiting for task creation' }
}
