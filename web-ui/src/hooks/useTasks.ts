import { useQuery } from '@tanstack/react-query'
import { useMemo } from 'react'
import { api } from '@/api/client'
import type { Task, TaskStatus } from '@/types'

export function useTasks(projectId: string) {
  const query = useQuery({
    queryKey: ['tasks', projectId],
    queryFn: async () => {
      const result = await api.get<Task[]>(`/projects/${projectId}/tasks`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!projectId,
  })

  const tasksByStatus = useMemo(() => {
    const grouped: Record<TaskStatus, Task[]> = {
      backlog: [],
      todo: [],
      in_progress: [],
      blocked: [],
      done: [],
      cancelled: [],
    }

    if (query.data) {
      for (const task of query.data) {
        grouped[task.status].push(task)
      }
    }

    return grouped
  }, [query.data])

  return {
    tasks: query.data ?? [],
    tasksByStatus,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
