import {
  DndContext,
  DragOverlay,
  MouseSensor,
  TouchSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core'
import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core'
import { useState } from 'react'
import type { Task, TaskStatus } from '@/types'
import { TaskCard } from '../TaskCard'
import { DraggableTaskCard } from './DraggableTaskCard'
import { DroppableColumn } from './DroppableColumn'

interface KanbanBoardProps {
  tasks: Task[]
  onTaskMove: (taskId: string, newStatus: TaskStatus) => void
  onTaskClick: (taskId: string) => void
}

interface ColumnConfig {
  status: TaskStatus
  label: string
}

const columns: ColumnConfig[] = [
  { status: 'backlog', label: 'Backlog' },
  { status: 'todo', label: 'Todo' },
  { status: 'in_progress', label: 'In Progress' },
  { status: 'done', label: 'Done' },
  { status: 'blocked', label: 'Blocked' },
]

export function KanbanBoard({ tasks, onTaskMove, onTaskClick }: KanbanBoardProps) {
  const [activeTask, setActiveTask] = useState<Task | null>(null)

  const sensors = useSensors(
    useSensor(MouseSensor, {
      activationConstraint: {
        distance: 10,
      },
    }),
    useSensor(TouchSensor, {
      activationConstraint: {
        delay: 250,
        tolerance: 5,
      },
    })
  )

  const tasksByStatus = tasks.reduce(
    (acc, task) => {
      acc[task.status].push(task)
      return acc
    },
    {
      backlog: [],
      todo: [],
      in_progress: [],
      blocked: [],
      done: [],
      cancelled: [],
    } as Record<TaskStatus, Task[]>
  )

  const handleDragStart = (event: DragStartEvent) => {
    const task = tasks.find((t) => t.id === event.active.id)
    if (task) {
      setActiveTask(task)
    }
  }

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event
    setActiveTask(null)

    if (!over) return

    const taskId = active.id as string
    const newStatus = over.id as TaskStatus

    const task = tasks.find((t) => t.id === taskId)
    if (task && task.status !== newStatus) {
      onTaskMove(taskId, newStatus)
    }
  }

  return (
    <DndContext
      sensors={sensors}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
    >
      <div className="flex gap-4 overflow-x-auto pb-4">
        {columns.map((column) => (
          <DroppableColumn
            key={column.status}
            status={column.status}
            label={column.label}
            taskCount={tasksByStatus[column.status].length}
          >
            {tasksByStatus[column.status].map((task) => (
              <DraggableTaskCard
                key={task.id}
                task={task}
                onClick={onTaskClick}
              />
            ))}
          </DroppableColumn>
        ))}
      </div>
      <DragOverlay>
        {activeTask ? <TaskCard task={activeTask} /> : null}
      </DragOverlay>
    </DndContext>
  )
}
