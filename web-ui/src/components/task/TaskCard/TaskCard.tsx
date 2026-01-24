import type { Task, TaskPriority, ApprovalStatus, Agent } from '@/types'

interface TaskCardProps {
  task: Task
  agents?: Agent[]
  onClick?: (taskId: string) => void
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

export function TaskCard({ task, agents, onClick }: TaskCardProps) {
  const handleClick = () => {
    onClick?.(task.id)
  }

  // Find assignee name from agents list
  const assigneeName = task.assigneeId
    ? agents?.find((a) => a.id === task.assigneeId)?.name ?? null
    : null

  const approvalBadge = approvalBadgeConfig[task.approvalStatus]
  const cardBackground = cardBackgroundStyles[task.approvalStatus]

  return (
    <div
      data-testid="task-card"
      data-task-id={task.id}
      className={`rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer border ${cardBackground}`}
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
      <div className="flex items-center justify-between">
        <span
          className={`inline-block px-2 py-1 text-xs font-medium rounded ${priorityStyles[task.priority]}`}
        >
          {priorityLabels[task.priority]}
        </span>
        {assigneeName && (
          <span className="text-xs text-gray-500 truncate max-w-[100px]" title={assigneeName}>
            {assigneeName}
          </span>
        )}
      </div>
    </div>
  )
}
