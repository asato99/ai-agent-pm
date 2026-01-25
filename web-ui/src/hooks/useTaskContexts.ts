// web-ui/src/hooks/useTaskContexts.ts
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ContextEntry } from '@/types'

interface ContextsResponse {
  contexts: ContextEntry[]
}

/**
 * Hook to fetch contexts for a specific task
 */
export function useTaskContexts(taskId: string | null) {
  const query = useQuery({
    queryKey: ['task-contexts', taskId],
    queryFn: async () => {
      const result = await api.get<ContextsResponse>(`/tasks/${taskId}/contexts`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!.contexts
    },
    enabled: !!taskId,
  })

  return {
    contexts: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
