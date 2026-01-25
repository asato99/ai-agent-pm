import type { Task, TaskPriority, TaskStatus, ApprovalStatus, Agent } from '@/types'

interface TaskCardProps {
  task: Task
  agents?: Agent[]
  depth?: number
  parentTask?: Task
  blockingTasks?: Task[]
  showBlockedReason?: boolean
  onClick?: (taskId: string) => void
  onParentClick?: (taskId: string) => void
  onTaskClick?: (taskId: string) => void
}

const priorityLabels: Record<TaskPriority, string> = {
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  urgent: 'Urgent',
}

const priorityStyles: Record<TaskPriority, string> = {
  low: 'bg-gray-100 text-gray-700',
  medium: 'bg-blue-100 text-blue-700',
  high: 'bg-orange-100 text-orange-700',
  urgent: 'bg-red-100 text-red-700',
}

const approvalBadgeConfig: Record<ApprovalStatus, { text: string; className: string } | null> = {
  approved: null,
  pending_approval: {
    text: '🔔 承認待ち',
    className: 'bg-orange-100 text-orange-700 border border-orange-300',
  },
  rejected: {
    text: '❌ 却下',
    className: 'bg-gray-100 text-gray-700 border border-gray-300',
  },
}

const cardBackgroundStyles: Record<ApprovalStatus, string> = {
  approved: 'bg-white',
  pending_approval: 'bg-orange-50 border-orange-200',
  rejected: 'bg-gray-50 border-gray-200',
}

// Depth indicator colors (left border)
// L0=blue, L1=green, L2=yellow, L3=orange, L4+=red
const depthColors: Record<number, string> = {
  0: 'border-l-blue-500',
  1: 'border-l-green-500',
  2: 'border-l-yellow-500',
  3: 'border-l-orange-500',
  4: 'border-l-red-500',
}

const getDepthClass = (depth: number): string => {
  return depthColors[Math.min(depth, 4)] || depthColors[0]
}

const statusLabels: Record<TaskStatus, string> = {
  backlog: 'backlog',
  todo: 'todo',
  in_progress: 'in_progress',
  blocked: 'blocked',
  done: 'done',
  cancelled: 'cancelled',
}

export function TaskCard({
  task,
  agents,
  depth = 0,
  parentTask,
  blockingTasks,
  showBlockedReason,
  onClick,
  onParentClick,
  onTaskClick,
}: TaskCardProps) {
  const handleClick = () => {
    onClick?.(task.id)
  }

  const handleParentClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    if (parentTask) {
      onParentClick?.(parentTask.id)
    }
  }

  const handleBlockingTaskClick = (e: React.MouseEvent, taskId: string) => {
    e.stopPropagation()
    onTaskClick?.(taskId)
  }

  // Find assignee name from agents list
  const assigneeName = task.assigneeId
    ? agents?.find((a) => a.id === task.assigneeId)?.name ?? null
    : null

  const approvalBadge = approvalBadgeConfig[task.approvalStatus]
  const cardBackground = cardBackgroundStyles[task.approvalStatus]
  const depthClass = getDepthClass(depth)

  // Dependency counts
  const upstreamCount = task.dependencies?.length || 0
  const downstreamCount = task.dependentTasks?.length || 0

  // Blocked status check
  const isBlocked = task.status === 'blocked'

  return (
    <div
      data-testid="task-card"
      data-task-id={task.id}
      className={`rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer border border-l-4 ${depthClass} ${cardBackground}`}
      onClick={handleClick}
    >
      {approvalBadge && (
        <span
          className={`inline-block px-2 py-0.5 text-xs font-medium rounded mb-2 ${approvalBadge.className}`}
        >
          {approvalBadge.text}
        </span>
      )}
      <h4 className="text-sm font-medium text-gray-900 mb-2">{task.title}</h4>

      {/* Parent badge */}
      {parentTask && (
        <div
          data-testid="parent-badge"
          className="inline-flex items-center gap-1 px-2 py-0.5 text-xs bg-gray-100 text-gray-600 rounded mb-2 cursor-pointer hover:bg-gray-200"
          onClick={handleParentClick}
        >
          <span>📁</span>
          <span className="truncate max-w-[120px]">{parentTask.title}</span>
        </div>
      )}

      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span
            className={`inline-block px-2 py-1 text-xs font-medium rounded ${priorityStyles[task.priority]}`}
          >
            {priorityLabels[task.priority]}
          </span>

          {/* Dependency indicators */}
          {upstreamCount > 0 && (
            <span
              data-testid="upstream-indicator"
              className="inline-flex items-center text-xs text-gray-500"
              title="Dependencies (waiting on)"
            >
              ⬆️{upstreamCount}
            </span>
          )}
          {downstreamCount > 0 && (
            <span
              data-testid="downstream-indicator"
              className="inline-flex items-center text-xs text-gray-500"
              title="Dependents (blocking)"
            >
              ⬇️{downstreamCount}
            </span>
          )}
        </div>

        {assigneeName && (
          <span className="text-xs text-gray-500 truncate max-w-[100px]" title={assigneeName}>
            {assigneeName}
          </span>
        )}
      </div>

      {/* Blocked reason section */}
      {isBlocked && showBlockedReason && blockingTasks && blockingTasks.length > 0 && (
        <div data-testid="blocked-reason" className="mt-2 pt-2 border-t border-gray-200">
          <div className="text-xs text-red-600 font-medium mb-1">⛔ Blocked by:</div>
          <ul className="text-xs text-gray-600 space-y-0.5">
            {blockingTasks.map((blockingTask) => (
              <li
                key={blockingTask.id}
                className="cursor-pointer hover:text-blue-600"
                onClick={(e) => handleBlockingTaskClick(e, blockingTask.id)}
              >
                • {blockingTask.title}{' '}
                <span className="text-gray-400">({statusLabels[blockingTask.status]})</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
