import { useDroppable } from '@dnd-kit/core'
import type { TaskStatus } from '@/types'

interface DroppableColumnProps {
  status: TaskStatus
  label: string
  taskCount: number
  children: React.ReactNode
}

export function DroppableColumn({ status, label, taskCount, children }: DroppableColumnProps) {
  const { isOver, setNodeRef } = useDroppable({
    id: status,
  })

  return (
    <div
      ref={setNodeRef}
      data-testid="kanban-column"
      data-column={status}
      className={`flex-shrink-0 w-72 bg-gray-100 rounded-lg p-4 ${
        isOver ? 'ring-2 ring-blue-500 bg-blue-50' : ''
      }`}
    >
      <h3 className="font-semibold text-gray-700 mb-4">
        {label}
        <span data-testid="task-count" className="text-gray-500 font-normal ml-1">
          ({taskCount})
        </span>
      </h3>
      <div className="space-y-3">{children}</div>
    </div>
  )
}
