export type AgentType = 'ai' | 'human'
export type AgentStatus = 'active' | 'inactive' | 'busy'
export type HierarchyType = 'owner' | 'manager' | 'worker'

export interface Agent {
  id: string
  name: string
  role: string
  agentType: AgentType
  status: AgentStatus
  hierarchyType: HierarchyType
  parentId: string | null
}
