import { useState, useCallback } from 'react'
import { useAuthStore } from '@/stores/authStore'
import { api } from '@/api/client'
import type { Agent } from '@/types'

interface LoginResponse {
  sessionToken: string
  agent: Agent
  expiresAt: string
}

export function useAuth() {
  const { isAuthenticated, agent, login: storeLogin, logout: storeLogout } = useAuthStore()
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const login = useCallback(async (agentId: string, passkey: string) => {
    setIsLoading(true)
    setError(null)

    const result = await api.post<LoginResponse>('/auth/login', {
      agentId,
      passkey,
    })

    if (result.error) {
      setIsLoading(false)
      setError(result.error?.message || '認証に失敗しました')
      return
    }

    if (result.data) {
      storeLogin(result.data.agent, result.data.sessionToken)
      setIsLoading(false)
    }
  }, [storeLogin])

  const logout = useCallback(async () => {
    await api.post('/auth/logout')
    storeLogout()
  }, [storeLogout])

  return {
    isAuthenticated,
    agent,
    isLoading,
    error,
    login,
    logout,
  }
}
