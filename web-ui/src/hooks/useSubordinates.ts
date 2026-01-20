import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { Agent } from '@/types'

export function useSubordinates() {
  const query = useQuery({
    queryKey: ['agents', 'subordinates'],
    queryFn: async () => {
      const result = await api.get<Agent[]>('/agents/subordinates')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    subordinates: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}
