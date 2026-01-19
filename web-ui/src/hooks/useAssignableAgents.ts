import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { Agent } from '@/types'

export function useAssignableAgents() {
  const query = useQuery({
    queryKey: ['assignable-agents'],
    queryFn: async () => {
      const result = await api.get<Agent[]>('/agents/assignable')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    agents: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
  }
}
