import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { Handoff, CreateHandoffInput } from '@/types'

export function useHandoffs() {
  const query = useQuery({
    queryKey: ['handoffs'],
    queryFn: async () => {
      const result = await api.get<Handoff[]>('/handoffs')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    handoffs: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

export function useTaskHandoffs(taskId: string | null) {
  const query = useQuery({
    queryKey: ['task-handoffs', taskId],
    queryFn: async () => {
      const result = await api.get<Handoff[]>(`/tasks/${taskId}/handoffs`)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    enabled: !!taskId,
  })

  return {
    handoffs: query.data ?? [],
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

export function useCreateHandoff() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (input: CreateHandoffInput) => {
      const result = await api.post<Handoff>('/handoffs', input)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['handoffs'] })
      queryClient.invalidateQueries({ queryKey: ['task-handoffs', data.taskId] })
    },
  })
}

export function useAcceptHandoff() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (handoffId: string) => {
      const result = await api.post<Handoff>(`/handoffs/${handoffId}/accept`, {})
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['handoffs'] })
      queryClient.invalidateQueries({ queryKey: ['task-handoffs', data.taskId] })
    },
  })
}
