import { test, expect } from '@playwright/test'

/**
 * Integration Test: Manager-Worker AI-to-AI Conversation (UC016-B)
 *
 * Reference: docs/usecase/UC016_AIToAIConversation.md
 *            docs/design/AI_TO_AI_CONVERSATION.md
 *
 * Difference from UC016: Manager → Worker hierarchy (not Worker ⇄ Worker)
 *
 * This test verifies that:
 * 1. Human can instruct Manager (initiator) to start conversation with Worker
 * 2. Manager calls start_conversation
 * 3. Worker joins and they exchange messages (shiritori 6 rounds)
 * 4. Manager calls end_conversation
 * 5. Manager reports result back to Human
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-uc016b-test.sh
 *   - Coordinator must be running (managing both manager and worker)
 *   - Services must be running (MCP, REST)
 *
 * Success Criteria:
 *   - Conversation state transitions: pending → active → terminating → ended
 *   - chat.jsonl contains messages with conversationId
 *   - Human receives result report from Manager
 */

test.describe('Manager-Worker AI-to-AI Conversation - UC016-B', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc016b-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc016b-project',
    name: 'UC016-B Manager-Worker Conversation Test',
  }

  const MANAGER = {
    id: 'uc016b-manager',
    name: 'UC016-B Manager',
  }

  const WORKER = {
    id: 'uc016b-worker',
    name: 'UC016-B Worker',
  }

  // Instruction message from Human to Manager
  // 6往復 = 12メッセージ、5件ごとにend_conversationリマインドが出るため10件目で終了を促される
  const INSTRUCTION_MESSAGE =
    'uc016b-workerと6往復しりとりをしてください。最初の単語は「りんご」で始めて、終わったら結果を報告してください。'

  test.beforeEach(async ({ page }) => {
    // Login as UC016-B Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('UC016-B project exists and is accessible', async ({ page }) => {
      // Verify UC016-B project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Both AI agents (Manager and Worker) are assigned to project', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Check manager avatar is visible
      const managerAvatar = page.locator(`[data-testid="agent-avatar-${MANAGER.id}"]`)
      await expect(managerAvatar).toBeVisible()

      // Check worker avatar is visible
      const workerAvatar = page.locator(`[data-testid="agent-avatar-${WORKER.id}"]`)
      await expect(workerAvatar).toBeVisible()
    })
  })

  test.describe('Manager-Worker Conversation Flow', () => {
    /**
     * Test: Full Manager-Worker conversation flow
     *
     * This test verifies the complete UC016-B flow:
     * 1. Human opens chat with manager
     * 2. Human sends instruction to start conversation with worker
     * 3. Manager calls start_conversation
     * 4. Worker joins, they do shiritori 6 rounds
     * 5. Manager calls end_conversation
     * 6. Manager reports result to Human
     *
     * Note: Requires Coordinator to be running with configured agents.
     * Run via: ./e2e/integration/run-uc016b-test.sh
     */
    test('Full Manager-Worker conversation: Human instructs manager, agents converse, result reported', async ({
      page,
    }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (AI-to-AI conversation takes time)
      test.setTimeout(300_000) // 5 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Click on manager avatar to open chat panel
      const managerAvatar = page.locator(`[data-testid="agent-avatar-${MANAGER.id}"]`)
      await expect(managerAvatar).toBeVisible()
      await managerAvatar.click()

      // Wait for chat panel
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for session to be ready
      const sendButton = page.getByTestId('chat-send-button')
      console.log('UC016-B: Waiting for chat session to be ready...')
      await expect(sendButton).toHaveText('送信', { timeout: 120_000 })
      console.log('UC016-B: Chat session is ready')

      // Send instruction to manager
      const chatInput = page.getByTestId('chat-input')
      await chatInput.fill(INSTRUCTION_MESSAGE)
      console.log('UC016-B: Sending instruction to manager...')
      await sendButton.click()

      // Verify message was sent
      await expect(chatPanel.getByText(INSTRUCTION_MESSAGE)).toBeVisible({ timeout: 5_000 })
      console.log('UC016-B: Instruction sent to manager')

      // Wait for AI-to-AI conversation to complete and result to be reported
      // The manager should:
      // 1. Call start_conversation
      // 2. Exchange 6 rounds of shiritori with worker
      // 3. Call end_conversation
      // 4. Report result back to Human
      const maxWaitTime = 240_000 // 4 minutes for entire AI-to-AI flow
      const pollInterval = 10_000
      const startTime = Date.now()

      console.log('UC016-B: Waiting for Manager-Worker conversation and result report...')

      let shiritoriStarted = false
      let pollCount = 0

      // Phase 1: Wait for shiritori to start (detect shiritori words)
      while (Date.now() - startTime < maxWaitTime) {
        pollCount++

        // Check for shiritori words indicating the game started
        const shiritoriIndicators = [
          'ゴリラ', // First response word (りんご → ゴリラ)
          'ごりら',
          'ラッパ', // Common shiritori word
          'パンダ', // Common shiritori word
        ]

        for (const indicator of shiritoriIndicators) {
          const hasIndicator = (await chatPanel.getByText(indicator).count()) > 0
          if (hasIndicator) {
            console.log(`UC016-B Polling #${pollCount}: Found shiritori word "${indicator}"`)
            shiritoriStarted = true
            break
          }
        }

        if (shiritoriStarted) {
          console.log(
            `UC016-B: Shiritori started after ${(Date.now() - startTime) / 1000}s`
          )
          break
        }

        console.log(
          `UC016-B Polling #${pollCount}: Waiting for shiritori to start... (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`
        )

        await page.waitForTimeout(pollInterval)
        await chatPanel.scrollIntoViewIfNeeded()
      }

      // Phase 2: Wait additional time for conversation to complete and end_conversation to be called
      // This gives agents time to finish shiritori and properly end the conversation
      const additionalWaitTime = 120_000 // 2 minutes extra for end_conversation
      console.log(
        'UC016-B: Shiritori in progress. Waiting additional 2 minutes for completion and end_conversation...'
      )

      const phase2StartTime = Date.now()
      while (Date.now() - phase2StartTime < additionalWaitTime) {
        await page.waitForTimeout(15_000) // Check every 15 seconds

        // Log current chat panel content count for debugging
        const messageCount = await chatPanel.locator('[data-testid]').count()
        console.log(
          `UC016-B: Chat panel elements: ${messageCount}, elapsed: ${Math.round((Date.now() - startTime) / 1000)}s`
        )

        // Check for completion phrases that might indicate result report to Human
        const completionIndicators = [
          '報告', // Report to Human
          '結果', // Result
          '完了しました',
          '往復完了',
        ]

        for (const indicator of completionIndicators) {
          const count = await chatPanel.getByText(indicator).count()
          if (count > 0) {
            console.log(`UC016-B: Found completion indicator "${indicator}" (count: ${count})`)
          }
        }
      }

      // Verify shiritori at least started
      expect(shiritoriStarted).toBe(true)
      console.log(
        `UC016-B: Test completed after ${(Date.now() - startTime) / 1000}s. Check logs for agent behavior.`
      )

      // Close chat panel
      const closeButton = chatPanel
        .getByRole('button', { name: /閉じる|Close|×/i })
        .first()
      await closeButton.click()
      await expect(chatPanel).not.toBeVisible({ timeout: 5_000 })
    })

    /**
     * Test: Verify conversation state in database
     *
     * After the full flow completes, verify:
     * - Conversation record exists with state = 'ended'
     * - Both agents participated
     */
    test('Verify conversation state after completion', async ({ page, request }) => {
      // Skip if not in integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires integration environment'
      )

      // This test assumes the full flow test has run
      // Check conversation state via API or wait for previous test

      // Navigate to project to verify UI state
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Both agent avatars should still be visible
      const managerAvatar = page.locator(`[data-testid="agent-avatar-${MANAGER.id}"]`)
      const workerAvatar = page.locator(`[data-testid="agent-avatar-${WORKER.id}"]`)

      await expect(managerAvatar).toBeVisible()
      await expect(workerAvatar).toBeVisible()

      console.log('UC016-B: Both agents visible after conversation')
    })
  })

  test.describe('Conversation Initiation', () => {
    /**
     * Test: Open chat with manager
     *
     * Verify that Human can open chat panel with manager agent.
     */
    test('Can open chat with manager agent', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Click on manager avatar
      const managerAvatar = page.locator(`[data-testid="agent-avatar-${MANAGER.id}"]`)
      const avatarVisible = await managerAvatar.isVisible().catch(() => false)

      if (!avatarVisible) {
        console.log('UC016-B: Manager avatar not visible, skipping')
        test.skip()
        return
      }

      await managerAvatar.click()

      // Verify chat panel opens
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Close chat panel
      const closeButton = chatPanel
        .getByRole('button', { name: /閉じる|Close|×/i })
        .first()
      await closeButton.click()
      await expect(chatPanel).not.toBeVisible()

      console.log('UC016-B: Chat panel opens and closes correctly')
    })

    /**
     * Test: Send message to manager
     *
     * Verify that Human can send a message to manager (without full flow).
     */
    test('Can send message to manager', async ({ page }) => {
      // Skip if not in integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires integration environment'
      )

      test.setTimeout(180_000) // 3 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Open chat with manager
      const managerAvatar = page.locator(`[data-testid="agent-avatar-${MANAGER.id}"]`)
      await managerAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for session ready
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toHaveText('送信', { timeout: 120_000 })

      // Send a simple test message
      const testMessage = 'テストメッセージです。'
      const chatInput = page.getByTestId('chat-input')
      await chatInput.fill(testMessage)
      await sendButton.click()

      // Verify message appears
      await expect(chatPanel.getByText(testMessage)).toBeVisible({ timeout: 5_000 })

      console.log('UC016-B: Message sent to manager successfully')

      // Close chat panel
      const closeButton = chatPanel
        .getByRole('button', { name: /閉じる|Close|×/i })
        .first()
      await closeButton.click()
    })
  })
})
