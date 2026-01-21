import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { Agent } from '@/types'

/**
 * Fetches agents that can be assigned to tasks in a specific project.
 * According to requirements (PROJECTS.md), task assignees must be agents assigned to the project.
 *
 * @param projectId - The project ID to get assignable agents for
 */
export function useAssignableAgents(projectId: string) {
  const query = useQuery({
    queryKey: ['assignable-agents', projectId],
    queryFn: async () => {
      const result = await api.get<Agent[]>(`/projects/${projectId}/assignable-agents`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!projectId,
  })

  return {
    agents: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
  }
}
