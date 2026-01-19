import type { Agent } from './agent'

export interface LoginRequest {
  agentId: string
  passkey: string
}

export interface LoginResponse {
  sessionToken: string
  agent: Agent
  expiresAt: string
}

export interface AuthState {
  isAuthenticated: boolean
  agent: Agent | null
  sessionToken: string | null
}
