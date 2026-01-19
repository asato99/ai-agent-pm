import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { ProjectSummary } from '@/types'

export function useProject(projectId: string) {
  const query = useQuery({
    queryKey: ['project', projectId],
    queryFn: async () => {
      const result = await api.get<ProjectSummary>(`/projects/${projectId}`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!projectId,
  })

  return {
    project: query.data,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
