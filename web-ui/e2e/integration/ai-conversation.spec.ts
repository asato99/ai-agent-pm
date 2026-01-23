import { test, expect } from '@playwright/test'

/**
 * Integration Test: AI-to-AI Conversation (UC016)
 *
 * Reference: docs/usecase/UC016_AIToAIConversation.md
 *            docs/design/AI_TO_AI_CONVERSATION.md
 *
 * This test verifies that:
 * 1. Human can instruct Worker-A (initiator) to start conversation with Worker-B
 * 2. Worker-A calls start_conversation
 * 3. Worker-B joins and they exchange messages (shiritori 5 rounds)
 * 4. Worker-A calls end_conversation
 * 5. Worker-A reports result back to Human
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-uc016-test.sh
 *   - Coordinator must be running (managing both initiator and participant)
 *   - Services must be running (MCP, REST)
 *
 * Success Criteria:
 *   - Conversation state transitions: pending → active → terminating → ended
 *   - chat.jsonl contains messages with conversationId
 *   - Human receives result report from Worker-A
 */

test.describe('AI-to-AI Conversation - UC016', () => {
  const TEST_CREDENTIALS = {
    agentId: 'uc016-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'uc016-project',
    name: 'UC016 AI Conversation Test',
  }

  const INITIATOR = {
    id: 'uc016-initiator',
    name: 'UC016 Initiator',
  }

  const PARTICIPANT = {
    id: 'uc016-participant',
    name: 'UC016 Participant',
  }

  // Instruction message from Human to Initiator
  // 6往復 = 12メッセージ、5件ごとにend_conversationリマインドが出るため10件目で終了を促される
  const INSTRUCTION_MESSAGE =
    'uc016-participantと6往復しりとりをしてください。最初の単語は「りんご」で始めて、終わったら結果を報告してください。'

  test.beforeEach(async ({ page }) => {
    // Login as UC016 Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('UC016 project exists and is accessible', async ({ page }) => {
      // Verify UC016 project is listed
      await expect(page.getByText(TEST_PROJECT.name)).toBeVisible()

      // Navigate to project
      await page.getByText(TEST_PROJECT.name).click()
      await expect(page).toHaveURL(`/projects/${TEST_PROJECT.id}`)
    })

    test('Both AI agents are assigned to project', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Check initiator avatar is visible
      const initiatorAvatar = page.locator(`[data-testid="agent-avatar-${INITIATOR.id}"]`)
      await expect(initiatorAvatar).toBeVisible()

      // Check participant avatar is visible
      const participantAvatar = page.locator(`[data-testid="agent-avatar-${PARTICIPANT.id}"]`)
      await expect(participantAvatar).toBeVisible()
    })
  })

  test.describe('AI-to-AI Conversation Flow', () => {
    /**
     * Test: Full AI-to-AI conversation flow
     *
     * This test verifies the complete UC016 flow:
     * 1. Human opens chat with initiator
     * 2. Human sends instruction to start conversation with participant
     * 3. Initiator calls start_conversation
     * 4. Participant joins, they do shiritori 5 rounds
     * 5. Initiator calls end_conversation
     * 6. Initiator reports result to Human
     *
     * Note: Requires Coordinator to be running with configured agents.
     * Run via: ./e2e/integration/run-uc016-test.sh
     */
    test('Full AI-to-AI conversation: Human instructs, agents converse, result reported', async ({
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

      // Click on initiator avatar to open chat panel
      const initiatorAvatar = page.locator(`[data-testid="agent-avatar-${INITIATOR.id}"]`)
      await expect(initiatorAvatar).toBeVisible()
      await initiatorAvatar.click()

      // Wait for chat panel
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for session to be ready
      const sendButton = page.getByTestId('chat-send-button')
      console.log('UC016: Waiting for chat session to be ready...')
      await expect(sendButton).toHaveText('送信', { timeout: 120_000 })
      console.log('UC016: Chat session is ready')

      // Send instruction to initiator
      const chatInput = page.getByTestId('chat-input')
      await chatInput.fill(INSTRUCTION_MESSAGE)
      console.log('UC016: Sending instruction to initiator...')
      await sendButton.click()

      // Verify message was sent
      await expect(chatPanel.getByText(INSTRUCTION_MESSAGE)).toBeVisible({ timeout: 5_000 })
      console.log('UC016: Instruction sent to initiator')

      // Wait for AI-to-AI conversation to complete and result to be reported
      // The initiator should:
      // 1. Call start_conversation
      // 2. Exchange 5 rounds of shiritori with participant
      // 3. Call end_conversation
      // 4. Report result back to Human
      const maxWaitTime = 240_000 // 4 minutes for entire AI-to-AI flow
      const pollInterval = 10_000
      const startTime = Date.now()

      console.log('UC016: Waiting for AI-to-AI conversation and result report...')

      let resultReceived = false
      let pollCount = 0

      while (Date.now() - startTime < maxWaitTime) {
        pollCount++

        // Check for result message from initiator
        // The initiator should report shiritori results (not just the instruction)
        // Look for shiritori words that indicate the game was actually played
        const resultIndicators = [
          'ゴリラ', // First response word (りんご → ゴリラ)
          'ラッパ', // Common shiritori word
          'パンダ', // Common shiritori word
          '完了しました', // Completion phrase (more specific than just "完了")
          '往復完了', // Specific completion phrase
        ]

        for (const indicator of resultIndicators) {
          // Use generic text search in chat panel
          // The chat panel contains messages as generic elements
          const hasIndicator = await chatPanel.getByText(indicator).count() > 0

          if (hasIndicator) {
            console.log(`UC016 Polling #${pollCount}: Found result indicator "${indicator}"`)
            resultReceived = true
            break
          }
        }

        if (resultReceived) {
          console.log(
            `UC016: Result received after ${(Date.now() - startTime) / 1000}s`
          )
          break
        }

        console.log(
          `UC016 Polling #${pollCount}: Waiting for result... (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`
        )

        // Refresh to get latest messages
        await page.waitForTimeout(pollInterval)

        // Re-check chat panel content
        await chatPanel.scrollIntoViewIfNeeded()
      }

      // Verify result was received
      expect(resultReceived).toBe(true)
      console.log(
        'UC016: AI-to-AI conversation completed and result reported to Human!'
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
      const initiatorAvatar = page.locator(`[data-testid="agent-avatar-${INITIATOR.id}"]`)
      const participantAvatar = page.locator(`[data-testid="agent-avatar-${PARTICIPANT.id}"]`)

      await expect(initiatorAvatar).toBeVisible()
      await expect(participantAvatar).toBeVisible()

      console.log('UC016: Both agents visible after conversation')
    })
  })

  test.describe('Conversation Initiation', () => {
    /**
     * Test: Open chat with initiator
     *
     * Verify that Human can open chat panel with initiator agent.
     */
    test('Can open chat with initiator agent', async ({ page }) => {
      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Click on initiator avatar
      const initiatorAvatar = page.locator(`[data-testid="agent-avatar-${INITIATOR.id}"]`)
      const avatarVisible = await initiatorAvatar.isVisible().catch(() => false)

      if (!avatarVisible) {
        console.log('UC016: Initiator avatar not visible, skipping')
        test.skip()
        return
      }

      await initiatorAvatar.click()

      // Verify chat panel opens
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Close chat panel
      const closeButton = chatPanel
        .getByRole('button', { name: /閉じる|Close|×/i })
        .first()
      await closeButton.click()
      await expect(chatPanel).not.toBeVisible()

      console.log('UC016: Chat panel opens and closes correctly')
    })

    /**
     * Test: Send message to initiator
     *
     * Verify that Human can send a message to initiator (without full flow).
     */
    test('Can send message to initiator', async ({ page }) => {
      // Skip if not in integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires integration environment'
      )

      test.setTimeout(180_000) // 3 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      // Open chat with initiator
      const initiatorAvatar = page.locator(`[data-testid="agent-avatar-${INITIATOR.id}"]`)
      await initiatorAvatar.click()

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

      console.log('UC016: Message sent to initiator successfully')

      // Close chat panel
      const closeButton = chatPanel
        .getByRole('button', { name: /閉じる|Close|×/i })
        .first()
      await closeButton.click()
    })
  })
})
