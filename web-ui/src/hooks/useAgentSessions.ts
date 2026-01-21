import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'

/**
 * Response type for agent session counts API
 * 参照: docs/design/CHAT_FEATURE.md - セッション状態表示
 */
export interface AgentSessionCountsResponse {
  agentSessionCounts: Record<string, number>
}

/**
 * Fetches active session counts for agents assigned to a specific project.
 * Polls every 3 seconds to keep the UI updated (similar to native app).
 *
 * @param projectId - The project ID to get agent session counts for
 */
export function useAgentSessions(projectId: string) {
  const query = useQuery({
    queryKey: ['agent-sessions', projectId],
    queryFn: async () => {
      const result = await api.get<AgentSessionCountsResponse>(
        `/projects/${projectId}/agent-sessions`
      )
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!projectId,
    // Poll every 3 seconds (same as native app)
    refetchInterval: 3000,
    // Don't refetch when window regains focus since we have interval
    refetchOnWindowFocus: false,
  })

  return {
    sessionCounts: query.data?.agentSessionCounts ?? {},
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
