import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { Agent, AuthState } from '@/types'

interface AuthStore extends AuthState {
  login: (agent: Agent, sessionToken: string) => void
  logout: () => void
}

export const useAuthStore = create<AuthStore>()(
  persist(
    (set) => ({
      isAuthenticated: false,
      agent: null,
      sessionToken: null,

      login: (agent, sessionToken) => {
        localStorage.setItem('sessionToken', sessionToken)
        set({ isAuthenticated: true, agent, sessionToken })
      },

      logout: () => {
        localStorage.removeItem('sessionToken')
        set({ isAuthenticated: false, agent: null, sessionToken: null })
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        isAuthenticated: state.isAuthenticated,
        agent: state.agent,
        sessionToken: state.sessionToken,
      }),
    }
  )
)
