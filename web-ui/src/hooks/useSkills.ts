// スキル関連のhooks
// 参照: docs/design/AGENT_SKILLS.md

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { Skill, AgentSkillsResponse, AssignSkillsRequest } from '@/types'

/**
 * 利用可能な全スキル一覧を取得
 */
export function useSkills() {
  const query = useQuery({
    queryKey: ['skills'],
    queryFn: async () => {
      const result = await api.get<Skill[]>('/skills')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    skills: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

/**
 * エージェントに割り当てられたスキルを取得
 */
export function useAgentSkills(agentId: string | null) {
  const query = useQuery({
    queryKey: ['agent-skills', agentId],
    queryFn: async () => {
      const result = await api.get<AgentSkillsResponse>(`/agents/${agentId}/skills`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!agentId,
  })

  return {
    agentSkills: query.data?.skills ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

/**
 * エージェントにスキルを割り当て
 */
export function useAssignSkills() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      agentId,
      skillIds,
    }: {
      agentId: string
      skillIds: string[]
    }) => {
      const body: AssignSkillsRequest = { skillIds }
      const result = await api.put<AgentSkillsResponse>(`/agents/${agentId}/skills`, body)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['agent-skills', data.agentId] })
    },
  })
}
