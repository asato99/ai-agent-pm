export type AgentType = 'ai' | 'human'
export type AgentStatus = 'active' | 'inactive' | 'suspended' | 'archived'
export type AgentHierarchyType = 'owner' | 'manager' | 'worker'
export type RoleType = 'owner' | 'manager' | 'general'
export type KickMethod = 'mcp' | 'stdio' | 'cli'

// List view (simple)
export interface Agent {
  id: string
  name: string
  role: string
  agentType: AgentType
  status: AgentStatus
  hierarchyType: AgentHierarchyType
  parentAgentId: string | null
}

// Detail view (full info)
export interface AgentDetail extends Agent {
  roleType: RoleType
  maxParallelTasks: number
  capabilities: string[]
  systemPrompt: string | null
  kickMethod: KickMethod
  provider: string | null
  modelId: string | null
  isLocked: boolean
  createdAt: string
  updatedAt: string
}

// Update request
export interface UpdateAgentRequest {
  name?: string
  role?: string
  status?: AgentStatus
  maxParallelTasks?: number
  capabilities?: string[]
  systemPrompt?: string
}
