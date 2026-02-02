/**
 * Wait for Tasks Complete Phase - 全タスク完了を待機
 */

import { execSync } from 'child_process'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

interface TaskRow {
  id: string
  title: string
  status: string
  assignee_id: string
  created_at: string
}

export function waitForTasksComplete(): PhaseDefinition {
  return {
    name: 'タスク完了待機',
    execute: async (ctx: PhaseContext) => {
      const timeout = ctx.scenario.timeouts.task_completion * 1000
      const startTime = Date.now()
      const pollInterval = 10_000
      const projectId = ctx.scenario.project.id
      const dbPath = '/tmp/AIAgentPM_Pilot.db'

      console.log(`Waiting for task completion (timeout: ${timeout / 1000}s)...`)

      while (Date.now() - startTime < timeout) {
        const tasks = fetchTaskStates(dbPath, projectId)
        const pendingTasks = tasks.filter(
          (t) => t.status !== 'done' && t.status !== 'cancelled'
        )

        console.log(
          `Task status: ${tasks.length} total, ${pendingTasks.length} pending (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`
        )

        // ステータス変化をイベントとして記録
        for (const task of tasks) {
          ctx.recorder.recordEvent('task_status_check', {
            task_id: task.id,
            title: task.title,
            status: task.status,
          })
        }

        if (pendingTasks.length === 0 && tasks.length > 0) {
          ctx.recorder.recordEvent('all_tasks_completed', {
            tasks: tasks.map((t) => ({ id: t.id, title: t.title, status: t.status })),
          })
          console.log('All tasks completed!')

          // 共有データに保存
          ctx.shared.tasks = tasks

          return { success: true }
        }

        await ctx.page.waitForTimeout(pollInterval)
      }

      // タイムアウトしても続行（結果に記録される）
      console.warn(`Task completion timeout after ${timeout / 1000}s`)
      ctx.recorder.recordEvent('task_completion_timeout', {
        elapsed_seconds: timeout / 1000,
      })

      const tasks = fetchTaskStates(dbPath, projectId)
      ctx.shared.tasks = tasks

      return {
        success: false,
        message: `Task completion timeout after ${timeout / 1000}s`,
      }
    },
  }
}

function fetchTaskStates(dbPath: string, projectId: string): TaskRow[] {
  try {
    const result = execSync(
      `sqlite3 -json "${dbPath}" "SELECT id, title, status, assignee_id, created_at FROM tasks WHERE project_id = '${projectId}'"`,
      { encoding: 'utf8' }
    )

    if (!result.trim()) {
      return []
    }

    return JSON.parse(result)
  } catch {
    return []
  }
}
