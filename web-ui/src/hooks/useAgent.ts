import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { AgentDetail, UpdateAgentRequest } from '@/types'

export function useAgent(agentId: string | null) {
  const query = useQuery({
    queryKey: ['agent', agentId],
    queryFn: async () => {
      const result = await api.get<AgentDetail>(`/agents/${agentId}`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!agentId,
  })

  return {
    agent: query.data,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

export function useUpdateAgent() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      agentId,
      data,
    }: {
      agentId: string
      data: UpdateAgentRequest
    }) => {
      const result = await api.patch<AgentDetail>(`/agents/${agentId}`, data)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['agent', data.id] })
      queryClient.invalidateQueries({ queryKey: ['agents', 'subordinates'] })
    },
  })
}
