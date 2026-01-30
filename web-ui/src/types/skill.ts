// スキル関連の型定義
// 参照: docs/design/AGENT_SKILLS.md

export interface Skill {
  id: string
  name: string
  description: string
  directoryName: string
  createdAt: string
  updatedAt: string
}

export interface AgentSkillsResponse {
  agentId: string
  skills: Skill[]
}

export interface AssignSkillsRequest {
  skillIds: string[]
}
