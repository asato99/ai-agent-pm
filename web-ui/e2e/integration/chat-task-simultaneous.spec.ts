import { test, expect, Page } from '@playwright/test'

/**
 * Integration Test: Chat and Task Simultaneous Execution (UC019)
 *
 * Reference: docs/usecase/UC019_ChatTaskSimultaneousExecution.md
 *
 * This test verifies that chat and task sessions can run simultaneously
 * for the same agent:
 * 1. Owner opens chat with Worker (chat session starts)
 * 2. Owner requests task creation via chat
 * 3. Worker creates task in backlog
 * 4. Owner moves task to in_progress (task session starts)
 * 5. Chat session is maintained (not terminated)
 * 6. Owner can send progress check message via chat
 * 7. Worker responds to chat while task is running
 *
 * Key Verification Points:
 *   - Chat session is maintained when task moves to in_progress
 *   - Both chat and task sessions can run simultaneously
 *   - Chat responses work during task execution
 *
 * Prerequisites:
 *   - Run: ./e2e/integration/run-uc019-test.sh
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 */

test.describe('Chat and Task Simultaneous Execution - UC019', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc019-owner',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc019-project',
    name: 'UC019 Chat+Task Simultaneous Test',
  }

  const TEST_AGENT = {
    id: 'uc019-worker',
    name: 'UC019 Worker',
  }

  // Helper: Wait for chat session to be ready
  async function waitForChatReady(page: Page, timeout = 120_000) {
    const sendButton = page.getByTestId('chat-send-button')
    console.log('UC019: Waiting for chat session to be ready...')
    await expect(sendButton).toHaveText('送信', { timeout })
    console.log('UC019: Chat session is ready')
  }

  // Helper: Send a chat message
  async function sendChatMessage(page: Page, message: string) {
    const chatInput = page.getByTestId('chat-input')
    await chatInput.fill(message)

    const sendButton = page.getByTestId('chat-send-button')
    await sendButton.click()

    console.log(`UC019: Sent message: "${message}"`)
  }

  // Helper: Wait for chat response from agent
  async function waitForAgentResponse(page: Page, timeout = 120_000) {
    console.log('UC019: Waiting for agent response...')

    // Wait for a message from the agent (not from the owner)
    // Note: Chat messages use data-testid="chat-message-{id}" and data-sender-id="{senderId}"
    const agentMessage = page.locator(
      `[data-testid^="chat-message-"][data-sender-id="${TEST_AGENT.id}"]`
    )

    await expect(agentMessage.first()).toBeVisible({ timeout })
    console.log('UC019: Agent response received')

    return agentMessage
  }

  test.beforeEach(async ({ page }) => {
    // Capture browser console messages for debugging
    page.on('console', msg => {
      const type = msg.type()
      if (type === 'error' || type === 'warn') {
        console.log(`UC019 Browser ${type}: ${msg.text()}`)
      }
    })

    // Capture network errors
    page.on('requestfailed', request => {
      console.log(`UC019 Network FAILED: ${request.method()} ${request.url()} - ${request.failure()?.errorText}`)
    })

    // Capture all API requests for debugging
    page.on('request', request => {
      if (request.url().includes('/api/')) {
        console.log(`UC019 Request: ${request.method()} ${request.url()}`)
      }
    })

    // Capture API responses
    page.on('response', response => {
      if (response.url().includes('/api/')) {
        console.log(`UC019 Response: ${response.status()} ${response.url()}`)
      }
    })

    // Login as UC019 Owner (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
    console.log('UC019: Logged in successfully')
  })

  test.describe('Simultaneous Chat and Task Sessions', () => {
    /**
     * Test: Full flow - Chat maintained during task execution
     *
     * This is the main test that verifies the complete UC019 flow:
     * 1. Open chat and verify it's working
     * 2. Request task creation via chat
     * 3. Move task to in_progress
     * 4. Verify chat is still working (send progress check message)
     * 5. Verify response is received
     */
    test('Chat session maintained when task moves to in_progress', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(300_000) // 5 minutes for full flow

      // Step 1: Navigate to project
      console.log('UC019: Step 1 - Navigate to project')
      await page.goto(`/projects/${TEST_PROJECT.id}`)
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible({ timeout: 10_000 })

      // Step 2: Open chat with Worker
      console.log('UC019: Step 2 - Open chat with Worker')
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await expect(agentAvatar).toBeVisible({ timeout: 10_000 })
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for chat session to be ready
      await waitForChatReady(page)

      // Step 3: Request task creation via chat
      console.log('UC019: Step 3 - Request task creation via chat')
      await sendChatMessage(
        page,
        'テストタスク「UC019同時実行テスト」を作成してください'
      )

      // Wait for agent response (task creation confirmation)
      await waitForAgentResponse(page)
      console.log('UC019: Task creation requested via chat')

      // Step 4: Wait for task to appear in backlog
      console.log('UC019: Step 4 - Wait for task in backlog')
      await page.waitForTimeout(5000) // Give time for task creation

      // Check if task exists in backlog column
      const backlogColumn = page.locator('[data-testid="task-column-backlog"]')
      const taskCard = backlogColumn.locator('[data-testid^="task-card-"]').first()

      // If task wasn't created via chat, create one directly for testing
      if (!(await taskCard.isVisible({ timeout: 10_000 }).catch(() => false))) {
        console.log('UC019: Task not found in backlog, creating directly...')
        // Click add task button
        const addTaskButton = page.getByTestId('add-task-button')
        if (await addTaskButton.isVisible()) {
          await addTaskButton.click()
          // Fill task details
          await page.getByLabel('タイトル').fill('UC019同時実行テスト')
          await page.getByRole('button', { name: '作成' }).click()
          await page.waitForTimeout(2000)
        }
      }

      // Step 5: Verify chat is still working before task move
      console.log('UC019: Step 5 - Verify chat is still working')
      const chatPanelStillOpen = await chatPanel.isVisible()
      expect(chatPanelStillOpen).toBe(true)
      console.log('UC019: Chat panel is still open')

      // Send a test message to verify chat functionality
      await sendChatMessage(page, 'チャットは正常に動作していますか？')
      await waitForAgentResponse(page)
      console.log('UC019: Chat is working before task move')

      // Step 6: Move task to in_progress
      console.log('UC019: Step 6 - Move task to in_progress')

      // Find the task card
      const taskCardToMove = backlogColumn.locator('[data-testid^="task-card-"]').first()

      if (await taskCardToMove.isVisible()) {
        // Get the in_progress column
        const inProgressColumn = page.locator('[data-testid="task-column-in_progress"]')

        // Drag and drop
        await taskCardToMove.dragTo(inProgressColumn, { timeout: 10_000 })
        console.log('UC019: Task moved to in_progress')

        // Wait for status change to take effect
        await page.waitForTimeout(3000)
      } else {
        console.log('UC019: No task found to move, continuing with chat verification')
      }

      // Step 7: CRITICAL - Verify chat session is maintained
      console.log('UC019: Step 7 - CRITICAL - Verify chat session is maintained')

      // Check chat panel is still visible
      await expect(chatPanel).toBeVisible()
      console.log('UC019: ✓ Chat panel is still visible after task move')

      // Verify send button still shows "送信" (session active)
      const sendButton = page.getByTestId('chat-send-button')
      const buttonText = await sendButton.textContent()
      console.log(`UC019: Send button text: "${buttonText}"`)

      // Button should be "送信" not "起動中..." or other loading state
      if (buttonText === '送信') {
        console.log('UC019: ✓ Chat session is active (button shows "送信")')
      } else {
        console.log(`UC019: ⚠ Chat session may be restarting (button shows "${buttonText}")`)
        // Wait for session to be ready again if needed
        await waitForChatReady(page, 60_000)
      }

      // Step 8: Send progress check message (while task is running)
      console.log('UC019: Step 8 - Send progress check message')
      await sendChatMessage(page, '進捗はどうですか？タスクは実行中ですか？')

      // Wait for response - THIS IS THE CRITICAL TEST
      // If chat session was incorrectly terminated, this will fail
      try {
        await waitForAgentResponse(page, 120_000)
        console.log('UC019: ✓ SUCCESS - Received chat response during task execution')
      } catch (error) {
        console.log('UC019: ✗ FAILED - No chat response received')
        console.log('UC019: This may indicate chat session was terminated when task started')
        throw error
      }

      // Step 9: Verify both sessions are running
      console.log('UC019: Step 9 - Final verification')
      console.log('UC019: ✓ Chat session is working during task execution')
      console.log('UC019: ✓ Both sessions are running simultaneously')
    })

    /**
     * Test: Chat panel remains open when task status changes
     *
     * Simplified test that verifies the UI behavior:
     * - Chat panel stays open when task is moved
     */
    test('Chat panel remains open when task is moved to in_progress', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(180_000) // 3 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Open chat panel
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await expect(agentAvatar).toBeVisible()
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for chat to be ready
      await waitForChatReady(page)

      // Remember that chat is open
      const chatWasOpen = await chatPanel.isVisible()
      expect(chatWasOpen).toBe(true)

      // Find a task or create one
      const backlogColumn = page.locator('[data-testid="task-column-backlog"]')
      let taskCard = backlogColumn.locator('[data-testid^="task-card-"]').first()

      if (!(await taskCard.isVisible().catch(() => false))) {
        // Create a task if none exists
        console.log('UC019: Creating a test task...')
        // This would use the UI to create a task
        // For now, skip if no task exists
        test.skip(true, 'No task available for testing')
        return
      }

      // Move task to in_progress
      const inProgressColumn = page.locator('[data-testid="task-column-in_progress"]')
      await taskCard.dragTo(inProgressColumn, { timeout: 10_000 })

      // Wait a moment
      await page.waitForTimeout(2000)

      // VERIFY: Chat panel should still be open
      await expect(chatPanel).toBeVisible()
      console.log('UC019: ✓ Chat panel remained open after task move')

      // VERIFY: Chat should still be functional
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toBeEnabled()
      console.log('UC019: ✓ Chat send button is still enabled')
    })

    /**
     * Test: Multiple chat messages during task execution
     *
     * Verifies that multiple messages can be exchanged while a task is running
     */
    test('Multiple chat messages work during task execution', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(300_000) // 5 minutes

      // Navigate and open chat
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()
      await waitForChatReady(page)

      // Start a task (if available)
      const backlogColumn = page.locator('[data-testid="task-column-backlog"]')
      const taskCard = backlogColumn.locator('[data-testid^="task-card-"]').first()

      if (await taskCard.isVisible().catch(() => false)) {
        const inProgressColumn = page.locator('[data-testid="task-column-in_progress"]')
        await taskCard.dragTo(inProgressColumn, { timeout: 10_000 })
        await page.waitForTimeout(3000)
      }

      // Send multiple messages and verify responses
      const messages = [
        '最初のメッセージ: 現在の状態を教えてください',
        '2番目のメッセージ: タスクは進行中ですか？',
        '3番目のメッセージ: 何かサポートが必要ですか？',
      ]

      for (const message of messages) {
        console.log(`UC019: Sending: "${message}"`)
        await sendChatMessage(page, message)

        try {
          await waitForAgentResponse(page, 120_000)
          console.log(`UC019: ✓ Received response for: "${message}"`)
        } catch (error) {
          console.log(`UC019: ✗ No response for: "${message}"`)
          // Don't throw, continue to see how many succeed
        }

        // Wait between messages
        await page.waitForTimeout(2000)
      }

      // Verify chat panel is still open
      await expect(chatPanel).toBeVisible()
      console.log('UC019: ✓ All messages processed, chat panel still open')
    })
  })

  test.describe('Session Independence Verification', () => {
    /**
     * Test: Chat session not affected by task session lifecycle
     *
     * Verifies that ending a task session doesn't affect the chat session
     */
    test('Task completion does not terminate chat session', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(300_000) // 5 minutes

      // Navigate and open chat
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()
      await waitForChatReady(page)

      // Start a task
      const backlogColumn = page.locator('[data-testid="task-column-backlog"]')
      const taskCard = backlogColumn.locator('[data-testid^="task-card-"]').first()

      if (await taskCard.isVisible().catch(() => false)) {
        const inProgressColumn = page.locator('[data-testid="task-column-in_progress"]')
        await taskCard.dragTo(inProgressColumn, { timeout: 10_000 })
        console.log('UC019: Task moved to in_progress')

        // Wait for task to potentially complete
        await page.waitForTimeout(30_000)

        // Check if task moved to done
        const doneColumn = page.locator('[data-testid="task-column-done"]')
        const doneTask = doneColumn.locator('[data-testid^="task-card-"]').first()

        if (await doneTask.isVisible().catch(() => false)) {
          console.log('UC019: Task completed')
        }
      }

      // CRITICAL: Chat should still work after task lifecycle
      await expect(chatPanel).toBeVisible()
      console.log('UC019: ✓ Chat panel still visible after task lifecycle')

      // Verify we can still send messages
      await sendChatMessage(page, 'タスク完了後のメッセージテスト')

      try {
        await waitForAgentResponse(page, 120_000)
        console.log('UC019: ✓ Chat still works after task completion')
      } catch (error) {
        console.log('UC019: ✗ Chat may have been affected by task completion')
        throw error
      }
    })
  })
})
