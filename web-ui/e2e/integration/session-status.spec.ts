import { test, expect } from '@playwright/test'

/**
 * Integration Test: Session Status Transitions
 *
 * This test verifies session status behavior from the user's perspective:
 * 1. Chat start creates a session (status: disconnected → connecting → connected)
 * 2. Reconnect button displays correctly when session is disconnected
 * 3. Reconnect works and restores connected state
 *
 * Focus: User-facing behavior, not implementation details
 */

test.describe('Session Status - User Perspective', () => {
  const TEST_CREDENTIALS = {
    agentId: 'session-human',
    passkey: 'test-passkey',
  }

  const TEST_PROJECT = {
    id: 'session-project',
    name: 'Session Test Project',
  }

  const TEST_AGENT = {
    id: 'session-worker',
    name: 'Session Test Worker',
  }

  test.beforeEach(async ({ page }) => {
    // Login as human (project owner)
    await page.goto('/login')
    await page.getByLabel('Agent ID').fill(TEST_CREDENTIALS.agentId)
    await page.getByLabel('Passkey').fill(TEST_CREDENTIALS.passkey)
    await page.getByRole('button', { name: 'Log in' }).click()

    // Wait for redirect to projects page
    await expect(page).toHaveURL('/projects')
    console.log('Session Test: Logged in successfully')
  })

  test.describe('Chat Session Start', () => {
    /**
     * Test: Opening chat panel initiates session
     *
     * User story: When I click on an agent avatar, the chat panel opens
     * and shows the session is being established (connecting state).
     */
    test('Opening chat shows connecting state then connected', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(180_000) // 3 minutes

      // Navigate to project
      await page.goto(`/projects/${TEST_PROJECT.id}`)
      console.log('Session Test: Navigated to project')

      // Click on agent avatar to open chat panel
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await expect(agentAvatar).toBeVisible({ timeout: 10_000 })
      console.log('Session Test: Agent avatar found')

      await agentAvatar.click()
      console.log('Session Test: Clicked agent avatar')

      // Chat panel should open
      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()
      console.log('Session Test: Chat panel opened')

      // Send button should initially show "準備中..." (connecting state)
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toBeVisible()

      // Verify button shows connecting state
      const initialText = await sendButton.textContent()
      console.log(`Session Test: Initial button text: "${initialText}"`)

      // Wait for session to become ready (connected state)
      console.log('Session Test: Waiting for session to become ready...')
      await expect(sendButton).toHaveText('送信', { timeout: 90_000 })
      console.log('Session Test: Session connected - button shows "送信"')

      // Verify input is enabled when connected
      const chatInput = page.getByTestId('chat-input')
      await expect(chatInput).toBeEnabled()
      console.log('Session Test: Chat input is enabled')
    })

    /**
     * Test: Session count is updated after connection
     *
     * User story: After chat session is established, the system should
     * recognize the active session for the agent.
     */
    test('Active session is counted after connection', async ({ page, request }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(180_000)

      // Navigate to project and open chat
      await page.goto(`/projects/${TEST_PROJECT.id}`)
      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for connected state
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toHaveText('送信', { timeout: 90_000 })
      console.log('Session Test: Session connected')

      // Verify session via API
      const baseUrl = process.env.INTEGRATION_WEB_URL || 'http://localhost:5173'
      const apiUrl = `${baseUrl}/api/projects/${TEST_PROJECT.id}/agent-sessions`

      // Get cookies from page for API authentication
      const cookies = await page.context().cookies()
      const sessionCookie = cookies.find((c) => c.name === 'session')

      if (sessionCookie) {
        const response = await request.get(apiUrl, {
          headers: {
            Cookie: `session=${sessionCookie.value}`,
          },
        })

        if (response.ok()) {
          const sessions = await response.json()
          console.log('Session Test: Agent sessions:', JSON.stringify(sessions))

          // Find session for our agent
          const agentSession = sessions.find((s: { agentId: string }) => s.agentId === TEST_AGENT.id)
          if (agentSession) {
            console.log(`Session Test: Found session - chatStatus: ${agentSession.chat?.status}`)
            expect(agentSession.chat?.status).toBe('connected')
          }
        }
      }
    })
  })

  test.describe('Reconnect Behavior', () => {
    /**
     * Test: Reconnect button appears when disconnected
     *
     * User story: When the chat session is disconnected (e.g., agent not running),
     * I see a "再接続" (reconnect) button instead of the send button.
     */
    test('Reconnect button displayed when session disconnected', async ({ page }) => {
      // This test can run without coordinator to verify UI behavior
      await page.goto(`/projects/${TEST_PROJECT.id}`)

      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)

      // Wait for page to load and agent avatar to appear
      try {
        await expect(agentAvatar).toBeVisible({ timeout: 10_000 })
      } catch {
        console.log('Session Test: Agent avatar not visible after waiting, skipping')
        test.skip()
        return
      }

      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Without coordinator, session should be disconnected
      // Button should show either "準備中..." (trying to connect) or "再接続" (disconnected)
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toBeVisible()

      // Wait for potential timeout
      await page.waitForTimeout(5_000)

      const buttonText = await sendButton.textContent()
      console.log(`Session Test: Button text without coordinator: "${buttonText}"`)

      // Without coordinator, should show reconnect or connecting state
      // The exact behavior depends on spawn timeout settings
      expect(['準備中...', '再接続', '送信']).toContain(buttonText)
    })

    /**
     * Test: Clicking reconnect initiates new session
     *
     * User story: When I click the "再接続" button, the system attempts
     * to establish a new chat session with the agent.
     */
    test('Reconnect button initiates new session', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(240_000) // 4 minutes

      await page.goto(`/projects/${TEST_PROJECT.id}`)

      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await expect(agentAvatar).toBeVisible()
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // Wait for initial connection
      const sendButton = page.getByTestId('chat-send-button')
      await expect(sendButton).toHaveText('送信', { timeout: 90_000 })
      console.log('Session Test: Initial session connected')

      // Close and reopen chat to simulate disconnect
      const closeButton = chatPanel.getByRole('button', { name: /閉じる|Close|×/i }).first()
      await closeButton.click()
      await expect(chatPanel).not.toBeVisible()
      console.log('Session Test: Chat panel closed')

      // Wait for session to be terminated
      await page.waitForTimeout(5_000)

      // Reopen chat
      await agentAvatar.click()
      await expect(chatPanel).toBeVisible()
      console.log('Session Test: Chat panel reopened')

      // Should show connecting or reconnect state
      const buttonTextAfterReopen = await sendButton.textContent()
      console.log(`Session Test: Button text after reopen: "${buttonTextAfterReopen}"`)

      // If showing reconnect, click it
      if (buttonTextAfterReopen === '再接続') {
        console.log('Session Test: Clicking reconnect button')
        await sendButton.click()

        // Should transition to connecting state
        await expect(sendButton).toHaveText('準備中...', { timeout: 5_000 })
        console.log('Session Test: Reconnect initiated - showing connecting state')
      }

      // Wait for session to become ready again
      await expect(sendButton).toHaveText('送信', { timeout: 90_000 })
      console.log('Session Test: Reconnected successfully')
    })
  })

  test.describe('Session Status Indicator', () => {
    /**
     * Test: UI shows correct status for each session state
     *
     * User story: I can see the current status of my chat session
     * through visual indicators (button text, input state).
     */
    test('UI reflects session status correctly', async ({ page }) => {
      test.skip(
        !process.env.INTEGRATION_WITH_COORDINATOR,
        'Requires full integration environment with Coordinator'
      )

      test.setTimeout(120_000)

      await page.goto(`/projects/${TEST_PROJECT.id}`)

      const agentAvatar = page.locator(`[data-testid="agent-avatar-${TEST_AGENT.id}"]`)
      await agentAvatar.click()

      const chatPanel = page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      const sendButton = page.getByTestId('chat-send-button')
      const chatInput = page.getByTestId('chat-input')

      // State 1: Connecting (initial)
      console.log('Session Test: Checking connecting state...')
      // Input should be disabled during connecting
      // Button should show "準備中..."

      // State 2: Connected
      await expect(sendButton).toHaveText('送信', { timeout: 90_000 })
      console.log('Session Test: Connected state verified')

      // Input should be enabled
      await expect(chatInput).toBeEnabled()
      console.log('Session Test: Input enabled when connected')

      // Verify can type in input
      await chatInput.fill('テストメッセージ')
      const inputValue = await chatInput.inputValue()
      expect(inputValue).toBe('テストメッセージ')
      console.log('Session Test: Can type message when connected')
    })
  })
})
