export interface Handoff {
  id: string
  taskId: string
  fromAgentId: string
  toAgentId: string | null
  summary: string
  context: string | null
  recommendations: string | null
  acceptedAt: string | null
  createdAt: string
  isPending: boolean
  isTargeted: boolean
}

export interface CreateHandoffInput {
  taskId: string
  toAgentId?: string | null
  summary: string
  context?: string | null
  recommendations?: string | null
}
