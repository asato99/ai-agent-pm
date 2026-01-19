import { useDraggable } from '@dnd-kit/core'
import type { Task } from '@/types'
import { TaskCard } from '../TaskCard'

interface DraggableTaskCardProps {
  task: Task
  onClick: (taskId: string) => void
  onDelete?: (taskId: string) => void
}

export function DraggableTaskCard({ task, onClick, onDelete }: DraggableTaskCardProps) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: task.id,
  })

  const style = transform
    ? {
        transform: `translate3d(${transform.x}px, ${transform.y}px, 0)`,
      }
    : undefined

  return (
    <div
      ref={setNodeRef}
      style={style}
      data-task-id={task.id}
      className={isDragging ? 'opacity-50' : ''}
      {...listeners}
      {...attributes}
    >
      <TaskCard task={task} onClick={onClick} onDelete={onDelete} />
    </div>
  )
}
