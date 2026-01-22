import type { Agent, AgentType } from '@/types'

interface AssignedAgentsRowProps {
  agents: Agent[]
  sessionCounts: Record<string, number>
  currentAgentId?: string
  subordinateIds?: string[]
  isLoading?: boolean
  onAgentClick?: (agentId: string) => void
}

const agentTypeColors: Record<AgentType, string> = {
  ai: 'bg-purple-500',
  human: 'bg-blue-500',
}

function AgentAvatar({
  agent,
  sessionCount,
  isCurrentUser,
  onClick,
}: {
  agent: Agent
  sessionCount: number
  isCurrentUser?: boolean
  onClick?: () => void
}) {
  // Get initials from agent name
  const initials = agent.name
    .split(' ')
    .map((n) => n[0])
    .join('')
    .slice(0, 2)
    .toUpperCase()

  return (
    <button
      type="button"
      onClick={onClick}
      data-testid={`agent-avatar-${agent.id}`}
      className="relative group focus:outline-none focus:ring-2 focus:ring-purple-500 focus:ring-offset-2 rounded-full flex-shrink-0"
      title={`${agent.name} - ${agent.role}${sessionCount > 0 ? ` (${sessionCount} active session${sessionCount > 1 ? 's' : ''})` : ''}`}
    >
      {/* Avatar */}
      <div
        className={`w-8 h-8 rounded-full ${agentTypeColors[agent.agentType]} flex items-center justify-center text-white text-xs font-medium shadow-sm group-hover:ring-2 group-hover:ring-purple-300 transition-all ${isCurrentUser ? 'ring-2 ring-yellow-400' : ''}`}
      >
        {initials}
      </div>

      {/* Active session badge */}
      {sessionCount > 0 && (
        <span className="absolute -top-1 -right-1 flex h-4 w-4 items-center justify-center rounded-full bg-green-500 text-[10px] font-bold text-white ring-2 ring-white">
          {sessionCount > 9 ? '9+' : sessionCount}
        </span>
      )}

      {/* Pulsing indicator for active sessions */}
      {sessionCount > 0 && (
        <span className="absolute -top-1 -right-1 h-4 w-4 animate-ping rounded-full bg-green-400 opacity-75" />
      )}
    </button>
  )
}

function AgentGroup({
  label,
  agents,
  sessionCounts,
  currentAgentId,
  onAgentClick,
}: {
  label: string
  agents: Agent[]
  sessionCounts: Record<string, number>
  currentAgentId?: string
  onAgentClick?: (agentId: string) => void
}) {
  if (agents.length === 0) return null

  return (
    <div className="flex items-center gap-2 pr-2">
      <span className="text-xs text-gray-400 whitespace-nowrap">{label}</span>
      <div className="flex items-center -space-x-1 overflow-x-auto max-w-[200px] py-2 px-1 scrollbar-thin scrollbar-thumb-gray-300 scrollbar-track-transparent">
        {agents.map((agent) => (
          <AgentAvatar
            key={agent.id}
            agent={agent}
            sessionCount={sessionCounts[agent.id] ?? 0}
            isCurrentUser={agent.id === currentAgentId}
            onClick={() => onAgentClick?.(agent.id)}
          />
        ))}
      </div>
    </div>
  )
}

export function AssignedAgentsRow({
  agents,
  sessionCounts,
  currentAgentId,
  subordinateIds = [],
  isLoading = false,
  onAgentClick,
}: AssignedAgentsRowProps) {
  // Count total active sessions
  const totalActiveSessions = Object.values(sessionCounts).reduce((sum, count) => sum + count, 0)

  // Split agents into 3 groups
  const subordinateIdSet = new Set(subordinateIds)
  const meAgent = agents.filter((a) => a.id === currentAgentId)
  const subordinates = agents.filter((a) => a.id !== currentAgentId && subordinateIdSet.has(a.id))
  const others = agents.filter((a) => a.id !== currentAgentId && !subordinateIdSet.has(a.id))

  return (
    <div
      className="flex items-center gap-3 py-2"
      data-testid="assigned-agents-row"
    >
      {/* Label with icon */}
      <div className="flex items-center gap-1.5 text-sm text-gray-500">
        <svg
          className="w-4 h-4"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
          />
        </svg>
        <span>Agents:</span>
      </div>

      {isLoading ? (
        <div className="flex items-center gap-2">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="w-8 h-8 rounded-full bg-gray-200 animate-pulse"
            />
          ))}
        </div>
      ) : agents.length === 0 ? (
        <span className="text-sm text-gray-400">No agents assigned</span>
      ) : (
        <>
          {/* 3-group layout */}
          <div className="flex items-center gap-3 divide-x divide-gray-200">
            {/* You */}
            <AgentGroup
              label="You"
              agents={meAgent}
              sessionCounts={sessionCounts}
              currentAgentId={currentAgentId}
              onAgentClick={onAgentClick}
            />

            {/* Subordinates */}
            <div className={subordinates.length > 0 ? 'pl-3' : ''}>
              <AgentGroup
                label="Subordinates"
                agents={subordinates}
                sessionCounts={sessionCounts}
                currentAgentId={currentAgentId}
                onAgentClick={onAgentClick}
              />
            </div>

            {/* Others */}
            <div className={others.length > 0 ? 'pl-3' : ''}>
              <AgentGroup
                label="Others"
                agents={others}
                sessionCounts={sessionCounts}
                currentAgentId={currentAgentId}
                onAgentClick={onAgentClick}
              />
            </div>
          </div>

          {/* Total active sessions summary */}
          {totalActiveSessions > 0 && (
            <div className="flex items-center gap-1 text-sm text-green-600">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500" />
              </span>
              <span>
                {totalActiveSessions} active session{totalActiveSessions > 1 ? 's' : ''}
              </span>
            </div>
          )}
        </>
      )}
    </div>
  )
}
