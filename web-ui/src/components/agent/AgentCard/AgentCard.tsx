import type { Agent, AgentStatus, AgentType, AgentHierarchyType } from '@/types'

interface AgentCardProps {
  agent: Agent
  onClick?: (agentId: string) => void
}

const statusConfig: Record<AgentStatus, { label: string; className: string }> = {
  active: { label: 'アクティブ', className: 'bg-green-100 text-green-800' },
  inactive: { label: '非アクティブ', className: 'bg-gray-100 text-gray-800' },
  suspended: { label: '停止中', className: 'bg-red-100 text-red-800' },
  archived: { label: 'アーカイブ', className: 'bg-gray-100 text-gray-500' },
}

const agentTypeIcon: Record<AgentType, string> = {
  ai: '🤖',
  human: '👤',
}

const hierarchyTypeLabel: Record<AgentHierarchyType, string> = {
  owner: 'オーナー',
  manager: 'マネージャー',
  worker: 'ワーカー',
}

export function AgentCard({ agent, onClick }: AgentCardProps) {
  const status = statusConfig[agent.status]

  const handleClick = () => {
    onClick?.(agent.id)
  }

  return (
    <div
      data-testid="agent-card"
      className="bg-white rounded-lg shadow p-6 hover:shadow-md transition-shadow cursor-pointer"
      onClick={handleClick}
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="text-2xl" role="img" aria-label={agent.agentType === 'ai' ? 'AI' : 'Human'}>
            {agentTypeIcon[agent.agentType]}
          </span>
          <h3 className="text-lg font-semibold text-gray-900">{agent.name}</h3>
        </div>
        <span className={`px-2 py-1 text-xs font-medium rounded-full ${status.className}`}>
          {status.label}
        </span>
      </div>

      <p className="text-sm text-gray-600 mb-3">{agent.role}</p>

      <div className="flex items-center gap-2 text-xs text-gray-500">
        <span className="px-2 py-1 bg-blue-50 text-blue-700 rounded">
          {hierarchyTypeLabel[agent.hierarchyType]}
        </span>
      </div>
    </div>
  )
}
