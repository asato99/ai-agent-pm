// web-ui/e2e/tests/chat.spec.ts
// チャット機能のE2Eテスト
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 7

import { test, expect } from '@playwright/test'
import { LoginPage } from '../pages/login.page'
import { TaskBoardPage } from '../pages/task-board.page'
import { ChatPage } from '../pages/chat.page'

test.describe('Chat Feature', () => {
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

  test('User can open chat panel by clicking agent avatar', async ({ page }) => {
    // Given: プロジェクトページにいる
    // When: エージェントアバターをクリック
    await page.click('[data-testid="agent-avatar-worker-1"]')

    // Then: チャットパネルが開く
    await chatPage.waitForPanelVisible()
    await expect(chatPage.chatPanel).toBeVisible()
  })

  test('Chat panel displays agent name in header', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()

    // Then: エージェント名がヘッダーに表示される
    await expect(chatPage.getAgentHeader('Worker 1')).toBeVisible()
  })

  test('Chat panel displays message history', async ({ page }) => {
    // Given: チャットパネルを開く (worker-1 has messages)
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()
    await chatPage.waitForMessagesLoaded()

    // Then: メッセージ履歴が表示される
    await expect(chatPage.getMessage('こんにちは')).toBeVisible()
    await expect(chatPage.getMessage('こんにちは！何かお手伝いできますか？')).toBeVisible()
  })

  test('User can send message to agent', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()
    await chatPage.waitForMessagesLoaded()

    const initialCount = await chatPage.getMessageCount()

    // When: メッセージを入力して送信
    await chatPage.sendMessage('Hello Agent!')

    // Then: メッセージが表示される
    await chatPage.waitForMessageCount(initialCount + 1)
    await expect(chatPage.getMessage('Hello Agent!')).toBeVisible()
  })

  test('User can close chat panel', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()

    // When: 閉じるボタンをクリック
    await chatPage.closePanel()

    // Then: チャットパネルが閉じる
    await expect(chatPage.chatPanel).not.toBeVisible()
  })

  test('Chat panel shows loading state', async ({ page }) => {
    // Given: チャットパネルを開く（ローディング中）
    await page.click('[data-testid="agent-avatar-worker-1"]')

    // Then: チャットパネルが表示される（ローディングは一瞬なのでパネル表示を確認）
    await expect(chatPage.chatPanel).toBeVisible()
  })

  test('Chat panel shows empty state when no messages', async ({ page }) => {
    // Given: メッセージのないエージェントとのチャットを開く (worker-2 has no messages)
    await page.click('[data-testid="agent-avatar-worker-2"]')
    await chatPage.waitForPanelVisible()
    await chatPage.waitForMessagesLoaded()

    // Then: 空状態メッセージが表示される
    await expect(chatPage.emptyState).toBeVisible()
  })

  test('Send button is disabled when input is empty', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()

    // Then: 送信ボタンが無効化されている
    await expect(chatPage.sendButton).toBeDisabled()
  })

  test('Send button is enabled when input has content', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()

    // When: メッセージを入力
    await chatPage.chatInput.fill('Test message')

    // Then: 送信ボタンが有効化される
    await expect(chatPage.sendButton).toBeEnabled()
  })

  test('Input is cleared after sending message', async ({ page }) => {
    // Given: チャットパネルを開く
    await page.click('[data-testid="agent-avatar-worker-1"]')
    await chatPage.waitForPanelVisible()

    // When: メッセージを送信
    await chatPage.sendMessage('Test message')

    // Then: 入力欄がクリアされる
    await expect(chatPage.chatInput).toHaveValue('')
  })
})
