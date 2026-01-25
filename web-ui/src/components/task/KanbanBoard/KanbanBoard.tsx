import {
  DndContext,
  DragOverlay,
  MouseSensor,
  TouchSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core'
import type { DragEndEvent, DragStartEvent } from '@dnd-kit/core'
import { useMemo, useState } from 'react'
import type { Task, TaskStatus, Agent } from '@/types'
import { TaskCard } from '../TaskCard'
import { DraggableTaskCard } from './DraggableTaskCard'
import { DroppableColumn } from './DroppableColumn'
import {
  sortTasksWithHierarchy,
  calculateTaskDepth,
  getParentTask,
  getBlockingTasks,
} from '@/utils/taskSorting'

interface KanbanBoardProps {
  tasks: Task[]
  agents?: Agent[]
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
  { status: 'blocked', label: 'Blocked' },
  { status: 'done', label: 'Done' },
]

export function KanbanBoard({ tasks, agents, onTaskMove, onTaskClick }: KanbanBoardProps) {
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

  // Group tasks by status, then sort hierarchically within each group
  const tasksByStatus = useMemo(() => {
    const grouped = tasks.reduce(
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

    // Sort each status group hierarchically
    for (const status of Object.keys(grouped) as TaskStatus[]) {
      grouped[status] = sortTasksWithHierarchy(grouped[status], tasks)
    }

    return grouped
  }, [tasks])

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
            {tasksByStatus[column.status].map((task) => {
              const depth = calculateTaskDepth(task.id, tasks)
              const parentTask = getParentTask(task.id, tasks) ?? undefined
              const blockingTasks = getBlockingTasks(task, tasks)
              const showBlockedReason = column.status === 'blocked'

              return (
                <DraggableTaskCard
                  key={task.id}
                  task={task}
                  agents={agents}
                  depth={depth}
                  parentTask={parentTask}
                  blockingTasks={blockingTasks}
                  showBlockedReason={showBlockedReason}
                  onClick={onTaskClick}
                  onParentClick={onTaskClick}
                  onTaskClick={onTaskClick}
                />
              )
            })}
          </DroppableColumn>
        ))}
      </div>
      <DragOverlay>
        {activeTask ? <TaskCard task={activeTask} agents={agents} /> : null}
      </DragOverlay>
    </DndContext>
  )
}
