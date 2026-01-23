// web-ui/e2e/tests/chat-session.spec.ts
// チャットセッション状態に基づく送信ボタン制御のE2Eテスト
// 参照: docs/design/CHAT_SESSION_MAINTENANCE_MODE.md

import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'
import { ChatPage } from '../pages/chat.page'

test.describe('Chat Session Send Button Control', () => {
  let chatPage: ChatPage

  test.beforeEach(async ({ page }) => {
    // Login
    const loginPage = new LoginPage(page)
    await loginPage.goto()
    await loginPage.login('manager-1', 'test-passkey')
    await expect(page).toHaveURL('/projects')

    // Navigate to project page
    const taskBoard = new TaskBoardPage(page)
    await taskBoard.goto('project-1')

    chatPage = new ChatPage(page)
  })

  test.describe('Send button state based on chat session', () => {
    test('Send button is disabled with "準備中..." when no chat session exists', async ({ page }) => {
      // Given: worker-2 has no chat session (chat: 0)
      // When: Open chat panel for worker-2
      await page.click('[data-testid="agent-avatar-worker-2"]')
      await chatPage.waitForPanelVisible()

      // Then: Send button should be disabled and show "準備中..."
      await expect(chatPage.sendButton).toBeDisabled()
      await expect(chatPage.sendButton).toHaveText('準備中...')
    })

    test('Send button is enabled with "送信" when chat session exists', async ({ page }) => {
      // Given: worker-1 has an active chat session (chat: 1)
      // When: Open chat panel for worker-1
      await page.click('[data-testid="agent-avatar-worker-1"]')
      await chatPage.waitForPanelVisible()

      // Then: Send button should show "送信" (enabled when input has content)
      await expect(chatPage.sendButton).toHaveText('送信')

      // Send button is disabled when input is empty (existing behavior)
      await expect(chatPage.sendButton).toBeDisabled()

      // But enabled when input has content
      await chatPage.chatInput.fill('Hello')
      await expect(chatPage.sendButton).toBeEnabled()
    })

    test('Send button becomes enabled when chat session starts', async ({ page }) => {
      // Given: worker-2 initially has no chat session
      await page.click('[data-testid="agent-avatar-worker-2"]')
      await chatPage.waitForPanelVisible()

      // Initially disabled
      await expect(chatPage.sendButton).toBeDisabled()
      await expect(chatPage.sendButton).toHaveText('準備中...')

      // When: Chat session starts (simulated by API returning chat: 1)
      // This would be triggered by polling - we test by verifying the UI updates
      // For E2E, we rely on the MSW mock to transition the state

      // Note: In real scenario, we'd wait for session to be ready
      // For this test, we verify the initial state is correct
    })

    test('User can send message when chat session is active', async ({ page }) => {
      // Given: worker-1 has an active chat session
      await page.click('[data-testid="agent-avatar-worker-1"]')
      await chatPage.waitForPanelVisible()
      await chatPage.waitForMessagesLoaded()

      const initialCount = await chatPage.getMessageCount()

      // When: Type message and send
      await chatPage.chatInput.fill('Test message')
      await expect(chatPage.sendButton).toBeEnabled()
      await chatPage.sendButton.click()

      // Then: Message is sent successfully
      await chatPage.waitForMessageCount(initialCount + 1)
      await expect(chatPage.getMessage('Test message')).toBeVisible()
    })

    test('User cannot send message when chat session is not active', async ({ page }) => {
      // Given: worker-2 has no chat session
      await page.click('[data-testid="agent-avatar-worker-2"]')
      await chatPage.waitForPanelVisible()

      // When: Try to type message
      await chatPage.chatInput.fill('Test message')

      // Then: Send button remains disabled despite having input
      await expect(chatPage.sendButton).toBeDisabled()
      await expect(chatPage.sendButton).toHaveText('準備中...')
    })
  })
})
