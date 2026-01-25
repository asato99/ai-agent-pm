// web-ui/src/hooks/useTaskHistory.ts
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md
// Combines execution logs and contexts into a unified timeline

import { useMemo } from 'react'
import { useExecutionLogs } from './useExecutionLogs'
import { useTaskContexts } from './useTaskContexts'
import type { ExecutionLog, ContextEntry, HistoryItem } from '@/types'

/**
 * Hook to fetch and combine execution logs and contexts into a unified history timeline
 * Sorted by timestamp (newest first)
 */
export function useTaskHistory(taskId: string | null) {
  const {
    executionLogs,
    isLoading: logsLoading,
    error: logsError
  } = useExecutionLogs(taskId)

  const {
    contexts,
    isLoading: contextsLoading,
    error: contextsError
  } = useTaskContexts(taskId)

  const history = useMemo(() => {
    const items: HistoryItem[] = []

    // Add execution logs
    executionLogs.forEach((log: ExecutionLog) => {
      items.push({
        type: 'execution_log',
        timestamp: log.startedAt,
        data: log,
      })
    })

    // Add contexts
    contexts.forEach((ctx: ContextEntry) => {
      items.push({
        type: 'context',
        timestamp: ctx.updatedAt,
        data: ctx,
      })
    })

    // Sort by timestamp (newest first)
    items.sort((a, b) => {
      const dateA = new Date(a.timestamp).getTime()
      const dateB = new Date(b.timestamp).getTime()
      return dateB - dateA
    })

    return items
  }, [executionLogs, contexts])

  return {
    history,
    isLoading: logsLoading || contextsLoading,
    error: logsError || contextsError,
  }
}
