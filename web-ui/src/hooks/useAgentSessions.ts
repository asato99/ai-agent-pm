import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'

/**
 * Chat session status
 * 参照: docs/design/CHAT_SESSION_STATUS.md
 */
export type ChatSessionStatus = 'connected' | 'connecting' | 'disconnected'

/**
 * Chat session info including count and status
 * 参照: docs/design/CHAT_SESSION_STATUS.md
 */
export interface ChatSessionInfo {
  count: number
  status: ChatSessionStatus
}

/**
 * Task session info (count only)
 * 参照: docs/design/CHAT_SESSION_STATUS.md
 */
export interface TaskSessionInfo {
  count: number
}

/**
 * Session info by purpose (chat/task)
 * 参照: docs/design/CHAT_SESSION_STATUS.md
 */
export interface AgentSessionPurposeCounts {
  chat: ChatSessionInfo
  task: TaskSessionInfo
}

/**
 * Response type for agent session counts API
 * 参照: docs/design/CHAT_SESSION_STATUS.md - セッション状態表示
 */
export interface AgentSessionCountsResponse {
  agentSessions: Record<string, AgentSessionPurposeCounts>
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

  const agentSessions = query.data?.agentSessions ?? {}

  /**
   * Get chat session status for an agent
   * 参照: docs/design/CHAT_SESSION_STATUS.md
   */
  const getChatStatus = (agentId: string): ChatSessionStatus => {
    return agentSessions[agentId]?.chat?.status ?? 'disconnected'
  }

  // Helper to check if agent has active chat session
  const hasChatSession = (agentId: string): boolean => {
    return (agentSessions[agentId]?.chat?.count ?? 0) > 0
  }

  // Helper to check if agent has any active session (for backward compatibility)
  const hasAnySession = (agentId: string): boolean => {
    const sessions = agentSessions[agentId]
    if (!sessions) return false
    return (sessions.chat?.count ?? 0) > 0 || (sessions.task?.count ?? 0) > 0
  }

  // Backward compatible sessionCounts (total sessions per agent)
  const sessionCounts: Record<string, number> = {}
  for (const [agentId, counts] of Object.entries(agentSessions)) {
    sessionCounts[agentId] = (counts.chat?.count ?? 0) + (counts.task?.count ?? 0)
  }

  return {
    /** Session info by purpose for each agent */
    agentSessions,
    /** Total session counts per agent (backward compatible) */
    sessionCounts,
    /** Get chat status: 'connected' | 'connecting' | 'disconnected' */
    getChatStatus,
    /** Check if agent has active chat session */
    hasChatSession,
    /** Check if agent has any active session */
    hasAnySession,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
