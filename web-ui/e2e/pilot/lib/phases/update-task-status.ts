/**
 * Update Task Status Phase - タスクステータスを手動更新
 *
 * hello-world シナリオ固有: オーナーが手動でステータスを変更
 */

import { PhaseDefinition, PhaseContext } from '../flow-types.js'

type TargetStatus = 'todo' | 'in_progress'

export function updateTaskStatus(targetStatus: TargetStatus): PhaseDefinition {
  return {
    name: `ステータス更新 (${targetStatus})`,
    execute: async (ctx: PhaseContext) => {
      console.log(`Updating task status to ${targetStatus}...`)

      // タスクカードをクリックして詳細ダイアログを開く
      const taskCard = ctx.page.locator('[data-testid="task-card"]').first()
      await taskCard.click()
      await ctx.page.waitForTimeout(1000)

      // ダイアログ内のステータスセレクトボックスを操作
      const dialog = ctx.page.getByRole('dialog')
      const statusSelect = dialog.getByRole('combobox')

      await statusSelect.selectOption(targetStatus)
      await ctx.page.waitForTimeout(1000)

      // ダイアログを閉じる
      await dialog.getByRole('button', { name: 'Close' }).first().click()
      await ctx.page.waitForTimeout(500)

      ctx.recorder.recordEvent('task_status_updated', {
        target_status: targetStatus,
        updated_by: 'owner',
      })
      console.log(`Task status updated to ${targetStatus}`)

      return { success: true }
    },
  }
}
