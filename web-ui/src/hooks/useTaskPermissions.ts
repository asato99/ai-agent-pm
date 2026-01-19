import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { TaskPermissions } from '@/types'

export function useTaskPermissions(taskId: string | null) {
  const query = useQuery({
    queryKey: ['task-permissions', taskId],
    queryFn: async () => {
      const result = await api.get<TaskPermissions>(`/tasks/${taskId}/permissions`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!taskId,
  })

  return {
    permissions: query.data ?? null,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
