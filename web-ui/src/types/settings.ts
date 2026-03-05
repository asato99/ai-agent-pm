export interface AppSettings {
  coordinatorTokenSet: boolean
  coordinatorTokenMasked: string | null
  pendingPurposeTTLSeconds: number
  allowRemoteAccess: boolean
  agentBasePrompt: string | null
  updatedAt: string
}

export interface UpdateSettingsRequest {
  allowRemoteAccess?: boolean
  agentBasePrompt?: string
  pendingPurposeTTLSeconds?: number
}
