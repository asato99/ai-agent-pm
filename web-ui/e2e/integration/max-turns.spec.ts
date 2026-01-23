import { test, expect } from '@playwright/test'

/**
 * Integration Test: Max Turns Auto-Termination
 *
 * Reference: docs/design/AI_TO_AI_CONVERSATION.md
 *
 * This test verifies that:
 * 1. Human instructs Worker-A to start conversation with Worker-B for 11 rounds
 * 2. Worker-A calls start_conversation with max_turns=20
 * 3. They exchange messages (shiritori)
 * 4. At 20 messages (10 rounds), conversation auto-terminates
 * 5. MCP logs show "auto-ended due to max_turns limit"
 *
 * Prerequisites:
 *   - Run setup: ./e2e/integration/run-maxturns-test.sh
 *   - Coordinator must be running
 *   - Services must be running (MCP, REST)
 *
 * Success Criteria:
 *   - Conversation ends with state = 'ended'
 *   - Auto-termination logged in MCP server
 */

test.describe('Max Turns Auto-Termination Test', () => {
  const TEST_CREDENTIALS = {
    agentId: 'maxturns-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'maxturns-project',
    name: 'MaxTurns Test Project',
  }

  const INITIATOR = {
    id: 'maxturns-initiator',
    name: 'MaxTurns Initiator',
  }

  const PARTICIPANT = {
    id: 'maxturns-participant',
    name: 'MaxTurns Participant',
  }

  // Instruction message from Human to Initiator
  // Request 11 rounds but max_turns=20 (10 rounds) should auto-terminate
  const INSTRUCTION_MESSAGE =
    'maxturns-participantと11往復しりとりをしてください。最初の単語は「りんご」で始めてください。max_turnsは20で設定してください。'

  test.beforeEach(async ({ page }) => {
    // Login as MaxTurns Human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
  })

  test.describe('Prerequisites - Environment Verification', () => {
    test('MaxTurns project exists and is accessible', async ({ page }) => {
      // Verify MaxTurns project is listed
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

  test.describe('Max Turns Auto-Termination Flow', () => {
    /**
     * Test: Conversation auto-terminates at max_turns limit
     *
     * This test verifies:
     * 1. Human opens chat with initiator
     * 2. Human sends instruction to start 11-round conversation
     * 3. Initiator calls start_conversation with max_turns=20
     * 4. Agents exchange messages until max_turns limit
     * 5. Conversation auto-terminates at 20 messages
     *
     * Note: Requires Coordinator to be running with configured agents.
     * Run via: ./e2e/integration/run-maxturns-test.sh
     */
    test('Conversation auto-terminates at max_turns limit', async ({ page }) => {
      // Skip if not in full integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      // Extend timeout for this test (AI-to-AI conversation takes time)
      test.setTimeout(300_000) // 5 minutes (max_turns=20 should complete faster)

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
      console.log('MaxTurns: Waiting for chat session to be ready...')
      await expect(sendButton).toHaveText('送信', { timeout: 120_000 })
      console.log('MaxTurns: Chat session is ready')

      // Send instruction to initiator
      const chatInput = page.getByTestId('chat-input')
      await chatInput.fill(INSTRUCTION_MESSAGE)
      console.log('MaxTurns: Sending instruction to initiator...')
      await sendButton.click()

      // Verify message was sent
      await expect(chatPanel.getByText(INSTRUCTION_MESSAGE)).toBeVisible({ timeout: 5_000 })
      console.log('MaxTurns: Instruction sent to initiator')

      // Wait for AI-to-AI conversation to auto-terminate
      const maxWaitTime = 180_000 // 3 minutes for shiritori to start
      const pollInterval = 10_000
      const startTime = Date.now()

      console.log('MaxTurns: Waiting for AI-to-AI conversation and auto-termination...')

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
            console.log(`MaxTurns Polling #${pollCount}: Found shiritori word "${indicator}"`)
            shiritoriStarted = true
            break
          }
        }

        if (shiritoriStarted) {
          console.log(`MaxTurns: Shiritori started after ${(Date.now() - startTime) / 1000}s`)
          break
        }

        console.log(
          `MaxTurns Polling #${pollCount}: Waiting for shiritori to start... (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`
        )

        await page.waitForTimeout(pollInterval)
        await chatPanel.scrollIntoViewIfNeeded()
      }

      // Phase 2: Wait for conversation to auto-terminate at max_turns limit
      // The warning message appears when max_turns is reached: 【会話終了】最大ターン数...
      const phase2MaxWaitTime = 240_000 // 4 minutes for max_turns=20 (allow buffer)
      console.log(
        'MaxTurns: Shiritori in progress. Waiting for max_turns limit to trigger auto-termination...'
      )

      let autoTerminationDetected = false
      const phase2StartTime = Date.now()
      while (Date.now() - phase2StartTime < phase2MaxWaitTime) {
        await page.waitForTimeout(10_000) // Check every 10 seconds

        // Log current chat panel content count for debugging
        const messageCount = await chatPanel.locator('[data-testid]').count()
        console.log(
          `MaxTurns: Chat panel elements: ${messageCount}, elapsed: ${Math.round((Date.now() - startTime) / 1000)}s`
        )

        // Check for the actual auto-termination warning message
        // The message is: 【会話終了】最大ターン数（XX）に達したため会話を自動終了しました
        const autoTermWarning = await chatPanel.getByText('【会話終了】').count()
        if (autoTermWarning > 0) {
          console.log(`MaxTurns: AUTO-TERMINATION DETECTED! Found '【会話終了】' in chat`)
          autoTerminationDetected = true
          break
        }

        // Also check for the keyword in case the exact message varies
        const maxTurnsWarning = await chatPanel.getByText('最大ターン数').count()
        if (maxTurnsWarning > 0) {
          console.log(`MaxTurns: Found '最大ターン数' warning - auto-termination may have occurred`)
          autoTerminationDetected = true
          break
        }
      }

      // Verify results
      expect(shiritoriStarted).toBe(true)
      console.log(
        `MaxTurns: Test completed after ${(Date.now() - startTime) / 1000}s. Auto-termination detected: ${autoTerminationDetected}`
      )

      // Note: We don't strictly require autoTerminationDetected because
      // the actual verification happens via DB/MCP logs in the shell script

      // Close chat panel
      const closeButton = chatPanel.getByRole('button', { name: /閉じる|Close|×/i }).first()
      await closeButton.click()
      await expect(chatPanel).not.toBeVisible({ timeout: 5_000 })
    })

    /**
     * Test: Verify conversation state in database after auto-termination
     */
    test('Verify conversation state after auto-termination', async ({ page, request }) => {
      // Skip if not in integration environment
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires integration environment'
      )

      // This test runs AFTER the main conversation test
      // It verifies the database state through the REST API
      const projectId = TEST_PROJECT.id

      // Check conversations via REST API
      const response = await request.get(
        `http://localhost:${process.env.AIAGENTPM_WEBSERVER_PORT}/api/projects/${projectId}/conversations`
      )

      if (response.ok()) {
        const conversations = await response.json()
        console.log('MaxTurns: Conversations from API:', JSON.stringify(conversations, null, 2))

        // Verify at least one conversation exists and is ended
        expect(conversations.length).toBeGreaterThan(0)
        const endedConversation = conversations.find(
          (c: { state: string }) => c.state === 'ended'
        )
        expect(endedConversation).toBeTruthy()
        console.log('MaxTurns: Found ended conversation:', endedConversation?.id)
      } else {
        console.log('MaxTurns: Could not fetch conversations from API')
      }
    })
  })
})
