import type { Task, TaskPriority, Agent } from '@/types'

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

export function TaskCard({ task, agents, onClick }: TaskCardProps) {
  const handleClick = () => {
    onClick?.(task.id)
  }

  // Find assignee name from agents list
  const assigneeName = task.assigneeId
    ? agents?.find((a) => a.id === task.assigneeId)?.name ?? null
    : null

  return (
    <div
      data-testid="task-card"
      data-task-id={task.id}
      className="bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer"
      onClick={handleClick}
    >
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
