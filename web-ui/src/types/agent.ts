export type AgentType = 'ai' | 'human'
export type AgentStatus = 'active' | 'inactive' | 'suspended' | 'archived'
export type AgentHierarchyType = 'manager' | 'worker'

export interface Agent {
  id: string
  name: string
  role: string
  agentType: AgentType
  status: AgentStatus
  hierarchyType: AgentHierarchyType
  parentId: string | null
}
