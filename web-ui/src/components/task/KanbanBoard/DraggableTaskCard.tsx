import { useDraggable } from '@dnd-kit/core'
import type { Task, Agent } from '@/types'
import { TaskCard } from '../TaskCard'

interface DraggableTaskCardProps {
  task: Task
  agents?: Agent[]
  onClick: (taskId: string) => void
}

export function DraggableTaskCard({ task, agents, onClick }: DraggableTaskCardProps) {
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
      <TaskCard task={task} agents={agents} onClick={onClick} />
    </div>
  )
}
