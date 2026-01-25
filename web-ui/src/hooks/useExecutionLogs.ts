// web-ui/src/hooks/useExecutionLogs.ts
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ExecutionLog, ExecutionLogContent } from '@/types'

interface ExecutionLogsResponse {
  executionLogs: ExecutionLog[]
}

/**
 * Hook to fetch execution logs for a specific task
 */
export function useExecutionLogs(taskId: string | null) {
  const query = useQuery({
    queryKey: ['execution-logs', taskId],
    queryFn: async () => {
      const result = await api.get<ExecutionLogsResponse>(`/tasks/${taskId}/execution-logs`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!.executionLogs
    },
    enabled: !!taskId,
  })

  return {
    executionLogs: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

/**
 * Hook to fetch the content of a specific execution log file
 */
export function useExecutionLogContent(logId: string | null) {
  const query = useQuery({
    queryKey: ['execution-log-content', logId],
    queryFn: async () => {
      const result = await api.get<ExecutionLogContent>(`/execution-logs/${logId}/content`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!logId,
  })

  return {
    content: query.data ?? null,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
