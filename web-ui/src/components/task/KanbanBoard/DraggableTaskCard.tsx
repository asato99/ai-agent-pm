import { useDraggable } from '@dnd-kit/core'
import type { Task, Agent } from '@/types'
import { TaskCard } from '../TaskCard'

interface DraggableTaskCardProps {
  task: Task
  agents?: Agent[]
  depth?: number
  parentTask?: Task
  blockingTasks?: Task[]
  showBlockedReason?: boolean
  onClick: (taskId: string) => void
  onParentClick?: (taskId: string) => void
  onTaskClick?: (taskId: string) => void
}

export function DraggableTaskCard({
  task,
  agents,
  depth = 0,
  parentTask,
  blockingTasks,
  showBlockedReason,
  onClick,
  onParentClick,
  onTaskClick,
}: DraggableTaskCardProps) {
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
      <TaskCard
        task={task}
        agents={agents}
        depth={depth}
        parentTask={parentTask}
        blockingTasks={blockingTasks}
        showBlockedReason={showBlockedReason}
        onClick={onClick}
        onParentClick={onParentClick}
        onTaskClick={onTaskClick}
      />
    </div>
  )
}
