import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ProjectSummary, ProjectStatus } from '@/types'

interface UseProjectsOptions {
  status?: ProjectStatus
}

export function useProjects(options: UseProjectsOptions = {}) {
  const { status } = options

  const query = useQuery({
    queryKey: ['projects', status],
    queryFn: async () => {
      const params: Record<string, string> = {}
      if (status) {
        params.status = status
      }
      const result = await api.get<ProjectSummary[]>('/projects', params)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    projects: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
