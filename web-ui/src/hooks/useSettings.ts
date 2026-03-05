import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '@/api/client'
import type { AppSettings, UpdateSettingsRequest } from '@/types'

export function useSettings() {
  const query = useQuery({
    queryKey: ['settings'],
    queryFn: async () => {
      const result = await api.get<AppSettings>('/settings')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
  })

  return {
    settings: query.data,
    isLoading: query.isLoading,
    error: query.error,
    refetch: query.refetch,
  }
}

export function useUpdateSettings() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (data: UpdateSettingsRequest) => {
      const result = await api.patch<AppSettings>('/settings', data)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] })
    },
  })
}

export function useRegenerateToken() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async () => {
      const result = await api.post<AppSettings>('/settings/regenerate-token')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] })
    },
  })
}

export function useClearToken() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async () => {
      const result = await api.delete<AppSettings>('/settings/coordinator-token')
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] })
    },
  })
}
