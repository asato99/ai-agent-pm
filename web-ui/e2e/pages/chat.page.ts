// web-ui/e2e/pages/chat.page.ts
// チャット機能のPage Object
// 参照: docs/design/CHAT_WEBUI_IMPLEMENTATION_PLAN.md - Phase 7

import { Page, Locator } from '@playwright/test'
import { BasePage } from './base.page'

export class ChatPage extends BasePage {
  readonly chatPanel: Locator
  readonly chatInput: Locator
  readonly sendButton: Locator
  readonly closeButton: Locator
  readonly loadingIndicator: Locator
  readonly emptyState: Locator
  readonly messages: Locator

  constructor(page: Page) {
    super(page)
    this.chatPanel = page.getByTestId('chat-panel')
    this.chatInput = page.getByTestId('chat-input')
    this.sendButton = page.getByTestId('chat-send-button')
    this.closeButton = page.getByRole('button', { name: /Close/i })
    this.loadingIndicator = page.getByTestId('chat-loading')
    this.emptyState = page.getByText('No messages yet')
    this.messages = page.getByTestId('chat-message')
  }

  /**
   * チャットパネルが表示されるのを待つ
   */
  async waitForPanelVisible() {
    await this.chatPanel.waitFor({ state: 'visible' })
  }

  /**
   * チャットパネルを閉じる
   */
  async closePanel() {
    await this.closeButton.click()
    await this.chatPanel.waitFor({ state: 'hidden' })
  }

  /**
   * メッセージを送信する
   * @param content メッセージ内容
   */
  async sendMessage(content: string) {
    await this.chatInput.fill(content)
    await this.sendButton.click()
  }

  /**
   * 特定のメッセージが表示されているかを確認
   * @param content メッセージ内容
   */
  getMessage(content: string): Locator {
    return this.chatPanel.getByText(content, { exact: true })
  }

  /**
   * メッセージ数を取得
   */
  async getMessageCount(): Promise<number> {
    return this.messages.count()
  }

  /**
   * エージェント名がヘッダーに表示されているかを確認
   * @param agentName エージェント名
   */
  getAgentHeader(agentName: string): Locator {
    return this.chatPanel.getByText(agentName)
  }

  /**
   * 読み込み完了を待つ
   */
  async waitForMessagesLoaded() {
    // Wait for loading indicator to disappear
    await this.loadingIndicator.waitFor({ state: 'hidden', timeout: 10000 }).catch(() => {
      // Ignore if loading indicator never appeared
    })
  }

  /**
   * 新しいメッセージが表示されるのを待つ
   * @param expectedCount 期待するメッセージ数
   */
  async waitForMessageCount(expectedCount: number, timeout = 5000) {
    const startTime = Date.now()
    while (Date.now() - startTime < timeout) {
      const count = await this.getMessageCount()
      if (count >= expectedCount) return
      await this.page.waitForTimeout(100)
    }
    throw new Error(`Expected ${expectedCount} messages but found ${await this.getMessageCount()}`)
  }
}
