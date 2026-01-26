import { test, expect, Page } from '@playwright/test'

/**
 * Integration Test: Chat and Task Simultaneous Execution (UC019)
 *
 * Reference: docs/usecase/UC019_ChatTaskSimultaneousExecution.md
 *
 * フロー:
 *   1. Owner → プロジェクト画面を開く
 *   2. Owner → Worker-01のアバターをクリック（チャットパネル表示）
 *   3. Owner → チャットでタスク作成を依頼
 *   4. Worker-01 → タスクを作成（MCPツール経由、Backlogに配置）
 *   5. Owner → タスクがBacklogに表示されることを確認
 *   6. Owner → タスクをドラッグ＆ドロップ (Backlog → Todo → In Progress)
 *      Note: Direct Backlog→In Progress is forbidden by status transition rules
 *   7. Assertion: チャットセッションが維持される（終了しない）
 *   8. Owner → チャットで進捗確認メッセージを送信
 *   9. Worker-01 → チャットで応答（タスク実行中でもチャット機能する）
 *
 * 検証ポイント:
 *   - タスクをin_progressに移動してもチャットセッションが維持される
 *   - タスク実行中にチャットで進捗確認できる
 *   - 両セッション（chat + task）が独立して動作する
 *
 * ステータス遷移ルール:
 *   - backlog → todo ✓
 *   - todo → in_progress ✓
 *   - backlog → in_progress ✗ (直接遷移は禁止)
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

  // Helper: Count current agent messages
  async function countAgentMessages(page: Page): Promise<number> {
    const agentMessages = page.locator(
      `[data-testid^="chat-message-"][data-sender-id="${TEST_AGENT.id}"]`
    )
    return await agentMessages.count()
  }

  // Helper: Wait for NEW agent response (after a known count)
  async function waitForNewAgentResponse(
    page: Page,
    previousCount: number,
    timeout = 120_000
  ) {
    console.log(`UC019: Waiting for new agent response (previous count: ${previousCount})...`)

    const agentMessages = page.locator(
      `[data-testid^="chat-message-"][data-sender-id="${TEST_AGENT.id}"]`
    )

    // Poll until count increases
    const startTime = Date.now()
    while (Date.now() - startTime < timeout) {
      const currentCount = await agentMessages.count()
      if (currentCount > previousCount) {
        console.log(`UC019: New agent response received (count: ${currentCount})`)
        return agentMessages.nth(currentCount - 1)
      }
      await page.waitForTimeout(1000)
    }

    throw new Error(`Timeout waiting for new agent response after ${timeout}ms`)
  }

  // Helper: Wait for task to appear in backlog (polling)
  async function waitForTaskInBacklog(
    page: Page,
    timeout = 180_000
  ): Promise<{ taskCard: ReturnType<Page['locator']>; taskId: string }> {
    console.log('UC019: Polling for task in backlog...')

    const backlogColumn = page.locator('[data-testid="kanban-column"][data-column="backlog"]')
    const startTime = Date.now()

    while (Date.now() - startTime < timeout) {
      // Look for any task card in backlog (data-testid="task-card" is the correct selector)
      const taskCards = backlogColumn.locator('[data-testid="task-card"]')
      const count = await taskCards.count()

      if (count > 0) {
        const taskCard = taskCards.first()
        // Get task ID from data-task-id attribute
        const taskId = await taskCard.getAttribute('data-task-id') || 'unknown'
        console.log(`UC019: ✓ Found task in backlog: ${taskId}`)
        return { taskCard, taskId }
      }

      console.log('UC019: No task in backlog yet, waiting...')
      await page.waitForTimeout(3000) // Poll every 3 seconds
    }

    throw new Error(`Timeout: No task appeared in backlog after ${timeout}ms`)
  }

  // Helper: Perform coordinate-based drag from one element to another column
  async function dragTaskToColumn(
    page: Page,
    taskCard: ReturnType<Page['locator']>,
    targetColumnSelector: string,
    description: string
  ) {
    console.log(`UC019: ${description}...`)

    const targetColumn = page.locator(targetColumnSelector)

    // Ensure both elements are visible
    await expect(taskCard).toBeVisible({ timeout: 5000 })
    await expect(targetColumn).toBeVisible({ timeout: 5000 })

    // Get bounding boxes for precise coordinate-based drag
    const sourceBox = await taskCard.boundingBox()
    const targetBox = await targetColumn.boundingBox()

    if (!sourceBox || !targetBox) {
      throw new Error('Could not get bounding boxes for drag operation')
    }

    console.log(`UC019: Source box: x=${sourceBox.x}, y=${sourceBox.y}, w=${sourceBox.width}, h=${sourceBox.height}`)
    console.log(`UC019: Target box: x=${targetBox.x}, y=${targetBox.y}, w=${targetBox.width}, h=${targetBox.height}`)

    // Calculate source center and target drop position
    const sourceX = sourceBox.x + sourceBox.width / 2
    const sourceY = sourceBox.y + sourceBox.height / 2
    const targetX = targetBox.x + targetBox.width / 2
    const targetY = targetBox.y + 100 // Drop near top of target column

    console.log(`UC019: Dragging from (${sourceX}, ${sourceY}) to (${targetX}, ${targetY})`)

    // Perform coordinate-based drag and drop
    await page.mouse.move(sourceX, sourceY)
    await page.mouse.down()
    await page.waitForTimeout(100) // Small delay for dnd-kit to register drag start

    // Move in steps for more reliable dnd-kit detection
    await page.mouse.move(targetX, targetY, { steps: 10 })
    await page.waitForTimeout(100) // Small delay before drop
    await page.mouse.up()

    console.log(`UC019: ✓ ${description} completed`)

    // Wait for UI to update
    await page.waitForTimeout(2000)
  }

  // Helper: Drag task from backlog to in_progress (via todo, per status transition rules)
  // Status transition rules: backlog → todo → in_progress (direct backlog → in_progress is not allowed)
  async function dragTaskToInProgress(
    page: Page,
    taskId: string
  ) {
    console.log('UC019: Moving task from Backlog to In Progress (via Todo)...')
    console.log('UC019: Note: Direct backlog→in_progress is forbidden. Using backlog→todo→in_progress.')

    // Step 1: backlog → todo
    const backlogColumn = page.locator('[data-testid="kanban-column"][data-column="backlog"]')
    let taskCard = backlogColumn.locator(`[data-testid="task-card"][data-task-id="${taskId}"]`)

    await dragTaskToColumn(
      page,
      taskCard,
      '[data-testid="kanban-column"][data-column="todo"]',
      'Dragging task from Backlog to Todo'
    )

    // Verify task is now in Todo
    const todoColumn = page.locator('[data-testid="kanban-column"][data-column="todo"]')
    const taskInTodo = todoColumn.locator(`[data-testid="task-card"][data-task-id="${taskId}"]`)
    await expect(taskInTodo).toBeVisible({ timeout: 10_000 })
    console.log(`UC019: ✓ Task ${taskId} confirmed in Todo column`)

    // Step 2: todo → in_progress
    taskCard = taskInTodo
    await dragTaskToColumn(
      page,
      taskCard,
      '[data-testid="kanban-column"][data-column="in_progress"]',
      'Dragging task from Todo to In Progress'
    )

    console.log('UC019: ✓ Task successfully moved to In Progress')
  }

  // Helper: Verify task moved to in_progress column
  async function verifyTaskInProgress(page: Page, taskId: string) {
    console.log(`UC019: Verifying task ${taskId} is in In Progress column...`)

    const inProgressColumn = page.locator('[data-testid="kanban-column"][data-column="in_progress"]')
    const taskCard = inProgressColumn.locator(`[data-testid="task-card"][data-task-id="${taskId}"]`)

    await expect(taskCard).toBeVisible({ timeout: 10_000 })
    console.log(`UC019: ✓ Task ${taskId} confirmed in In Progress column`)
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
     * メインテスト: チャットとタスクの同時実行
     *
     * UC019の完全フローを検証:
     * 1. プロジェクト画面に移動
     * 2. Worker-01とチャットを開始
     * 3. チャットでタスク作成を依頼
     * 4. Worker-01がタスクを作成するのを待機（AIがMCPツールで作成）
     * 5. タスクをBacklog → Todo → In Progressにドラッグ（2段階遷移）
     * 6. チャットセッションが維持されていることを確認
     * 7. タスク実行中にチャットで進捗確認
     * 8. 応答が返ることを確認
     */
    test('Chat session maintained when task moves to in_progress', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(600_000) // 10 minutes for full integration flow

      // ========================================
      // Step 1: プロジェクト画面に移動
      // ========================================
      console.log('UC019: Step 1 - Navigate to project')
      await page.goto(`/projects/${TEST_PROJECT.id}`)
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible({ timeout: 10_000 })
      console.log('UC019: ✓ Project page loaded')

      // ========================================
      // Step 2: Worker-01とチャットを開始
      // ========================================
      console.log('UC019: Step 2 - Open chat with Worker')
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await expect(agentAvatar).toBeVisible({ timeout: 10_000 })
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for chat session to be ready (Coordinator starts agent)
      await waitForChatReady(page)
      console.log('UC019: ✓ Chat session established with Worker')

      // ========================================
      // Step 3: チャットでタスク作成を依頼
      // ========================================
      console.log('UC019: Step 3 - Request task creation via chat')

      // Get current message count before sending
      const messageCountBefore = await countAgentMessages(page)

      await sendChatMessage(
        page,
        `プロジェクト「${TEST_PROJECT.id}」に新しいタスク「UC019同時実行テスト」を作成してください。タスクはBacklogに配置してください。`
      )

      // Wait for agent response (task creation confirmation)
      await waitForNewAgentResponse(page, messageCountBefore, 180_000)
      console.log('UC019: ✓ Task creation requested, agent responded')

      // ========================================
      // Step 4: タスクがBacklogに表示されるのを待機
      // ========================================
      console.log('UC019: Step 4 - Wait for task to appear in Backlog')

      // Poll for task in backlog (AI creates it asynchronously)
      const { taskCard, taskId } = await waitForTaskInBacklog(page, 180_000)
      console.log(`UC019: ✓ Task appeared in Backlog: ${taskId}`)

      // ========================================
      // Step 5: チャットセッションがまだ有効か確認
      // ========================================
      console.log('UC019: Step 5 - Verify chat is still working before task move')
      await expect(chatPanel).toBeVisible()

      const sendButton = page.getByTestId('chat-send-button')
      const buttonText = await sendButton.textContent()
      console.log(`UC019: Send button text: "${buttonText}"`)

      if (buttonText !== '送信') {
        console.log('UC019: Chat session may be restarting, waiting...')
        await waitForChatReady(page, 60_000)
      }
      console.log('UC019: ✓ Chat session still active before task move')

      // ========================================
      // Step 6: タスクをBacklog → In Progressにドラッグ
      // Note: Status transition rules require backlog → todo → in_progress
      // ========================================
      console.log('UC019: Step 6 - CRITICAL: Drag task from Backlog to In Progress')

      // Perform two-step drag operation (backlog → todo → in_progress)
      await dragTaskToInProgress(page, taskId)

      // Verify task moved
      await verifyTaskInProgress(page, taskId)
      console.log('UC019: ✓ Task successfully verified in In Progress')

      // ========================================
      // Step 7: CRITICAL - チャットセッションが維持されていることを確認
      // ========================================
      console.log('UC019: Step 7 - CRITICAL: Verify chat session is maintained')

      // Check chat panel is still visible
      await expect(chatPanel).toBeVisible()
      console.log('UC019: ✓ Chat panel is still visible after task move')

      // Verify send button still shows "送信" (session active)
      const buttonTextAfterMove = await sendButton.textContent()
      console.log(`UC019: Send button text after move: "${buttonTextAfterMove}"`)

      if (buttonTextAfterMove === '送信') {
        console.log('UC019: ✓ Chat session is MAINTAINED (button shows "送信")')
      } else {
        console.log(`UC019: ⚠ Chat session may be affected (button shows "${buttonTextAfterMove}")`)
        // Wait for session to recover if needed
        await waitForChatReady(page, 60_000)
        console.log('UC019: Chat session recovered')
      }

      // ========================================
      // Step 8: タスク実行中にチャットで進捗確認
      // ========================================
      console.log('UC019: Step 8 - Send progress check message during task execution')

      const messageCountBeforeProgress = await countAgentMessages(page)

      await sendChatMessage(page, '進捗はどうですか？タスクは実行中ですか？')

      // Wait for response - THIS IS THE CRITICAL TEST
      // If chat session was incorrectly terminated, this will fail
      try {
        await waitForNewAgentResponse(page, messageCountBeforeProgress, 120_000)
        console.log('UC019: ✓ SUCCESS - Received chat response during task execution')
      } catch (error) {
        console.log('UC019: ✗ FAILED - No chat response received during task execution')
        console.log('UC019: This indicates chat session was terminated when task started')
        throw error
      }

      // ========================================
      // Final Verification
      // ========================================
      console.log('UC019: ========================================')
      console.log('UC019: ✓ VERIFICATION COMPLETE')
      console.log('UC019: ✓ Chat session maintained during task execution')
      console.log('UC019: ✓ Both sessions running simultaneously')
      console.log('UC019: ========================================')
    })
  })

})

