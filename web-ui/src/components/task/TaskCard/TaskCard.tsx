import type { Task, TaskPriority } from '@/types'

interface TaskCardProps {
  task: Task
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

export function TaskCard({ task, onClick }: TaskCardProps) {
  const handleClick = () => {
    onClick?.(task.id)
  }

  return (
    <div
      data-testid="task-card"
      data-task-id={task.id}
      className="bg-white rounded-lg shadow p-4 hover:shadow-md transition-shadow cursor-pointer"
      onClick={handleClick}
    >
      <h4 className="text-sm font-medium text-gray-900 mb-2">{task.title}</h4>
      <span
        className={`inline-block px-2 py-1 text-xs font-medium rounded ${priorityStyles[task.priority]}`}
      >
        {priorityLabels[task.priority]}
      </span>
    </div>
  )
}
