/**
 * Wait for Tasks Created Phase - タスク作成を待機
 */

import { execSync } from 'child_process'
import { PhaseDefinition, PhaseContext } from '../flow-types.js'

interface Options {
  minCount?: number
}

interface TaskRow {
  id: string
  title: string
  status: string
  assignee_id: string
  created_at: string
}

export function waitForTasksCreated(options: Options = {}): PhaseDefinition {
  const minCount = options.minCount ?? 1

  return {
    name: 'タスク作成待機',
    execute: async (ctx: PhaseContext) => {
      const timeout = ctx.scenario.timeouts.task_creation * 1000
      const startTime = Date.now()
      const pollInterval = 5_000
      const projectId = ctx.scenario.project.id
      const dbPath = '/tmp/AIAgentPM_Pilot.db'

      console.log(`Waiting for task creation (timeout: ${timeout / 1000}s, minCount: ${minCount})...`)

      while (Date.now() - startTime < timeout) {
        const tasks = fetchTaskStates(dbPath, projectId)

        if (tasks.length >= minCount) {
          ctx.recorder.recordEvent('tasks_created', {
            count: tasks.length,
            tasks: tasks.map((t) => ({ id: t.id, title: t.title, status: t.status })),
          })
          console.log(`Tasks created: ${tasks.length}`)

          // 共有データに保存
          ctx.shared.tasks = tasks

          return { success: true, data: { count: tasks.length } }
        }

        await ctx.page.waitForTimeout(pollInterval)
      }

      return {
        success: false,
        message: `Task creation timeout after ${timeout / 1000}s`,
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
