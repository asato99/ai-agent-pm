/**
 * Send Message Phase - チャットでメッセージを送信
 */

import { expect } from '@playwright/test'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

export function sendMessage(): PhaseDefinition {
  return {
    name: '初期アクション送信',
    execute: async (ctx: PhaseContext) => {
      const action = ctx.scenario.initial_action
      const project = ctx.scenario.project

      await ctx.page.goto(`${ctx.baseUrl}/projects/${project.id}`)

      // Managerのアバターをクリックしてチャットを開く
      const managerAvatar = ctx.page.locator(`[data-testid="agent-avatar-${action.to}"]`)
      await expect(managerAvatar).toBeVisible({ timeout: 10_000 })
      await managerAvatar.click()

      // チャットパネルが表示されるのを待機
      const chatPanel = ctx.page.getByTestId('chat-panel')
      await expect(chatPanel).toBeVisible()

      // セッション準備完了を待機
      const sendButton = ctx.page.getByTestId('chat-send-button')
      console.log('Waiting for chat session to be ready...')
      await expect(sendButton).toHaveText('送信', { timeout: 180_000 })
      console.log('Chat session is ready')

      // メッセージを送信
      const chatInput = ctx.page.getByTestId('chat-input')
      await chatInput.fill(action.message)
      await sendButton.click()

      // メッセージが送信されたことを確認
      await expect(chatPanel.getByText(action.message)).toBeVisible({ timeout: 5_000 })

      ctx.recorder.recordEvent('initial_action_sent', {
        from: action.from,
        to: action.to,
        message: action.message,
      })

      console.log(`Sent initial message: "${action.message}"`)

      return { success: true }
    },
  }
}
