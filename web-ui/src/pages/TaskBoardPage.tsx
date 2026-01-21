import { useState, useMemo } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { AppHeader } from '@/components/layout'
import { KanbanBoard, CreateTaskModal, TaskDetailPanel } from '@/components/task'
import { WorkingDirectorySettings } from '@/components/project'
import { useProject } from '@/hooks/useProject'
import { useTasks } from '@/hooks/useTasks'
import { api } from '@/api/client'
import type { Task, TaskStatus, TaskPriority } from '@/types'

export function TaskBoardPage() {
  const { id: projectId } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const { project, isLoading: projectLoading } = useProject(projectId || '')
  const { tasks, isLoading: tasksLoading } = useTasks(projectId || '')

  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null)
  const [isDetailPanelOpen, setIsDetailPanelOpen] = useState(false)

  // Derive selectedTask from tasks to ensure reactivity when task data changes
  const selectedTask = useMemo(
    () => (selectedTaskId ? tasks.find((t) => t.id === selectedTaskId) ?? null : null),
    [selectedTaskId, tasks]
  )

  const createTaskMutation = useMutation({
    mutationFn: async (data: { title: string; description: string; priority: TaskPriority; assigneeId?: string }) => {
      const result = await api.post<Task>(`/projects/${projectId}/tasks`, data)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks', projectId] })
      setIsCreateModalOpen(false)
    },
  })

  const updateTaskStatusMutation = useMutation({
    mutationFn: async ({ taskId, status }: { taskId: string; status: TaskStatus }) => {
      const result = await api.patch<Task>(`/tasks/${taskId}`, { status })
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tasks', projectId] })
    },
  })

  const handleTaskMove = (taskId: string, newStatus: TaskStatus) => {
    updateTaskStatusMutation.mutate({ taskId, status: newStatus })
  }

  const handleTaskClick = (taskId: string) => {
    setSelectedTaskId(taskId)
    setIsDetailPanelOpen(true)
  }

  const handleCreateTask = (data: { title: string; description: string; priority: TaskPriority; assigneeId?: string }) => {
    createTaskMutation.mutate(data)
  }

  const isLoading = projectLoading || tasksLoading

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50">
        <AppHeader />
        <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
          <div className="animate-pulse">
            <div className="h-8 bg-gray-200 rounded w-1/4 mb-6"></div>
            <div className="flex gap-4">
              {[...Array(5)].map((_, i) => (
                <div key={i} className="w-72 h-64 bg-gray-200 rounded"></div>
              ))}
            </div>
          </div>
        </main>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <AppHeader />
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-4">
            <Link
              to="/projects"
              className="text-blue-600 hover:text-blue-800 flex items-center gap-1"
            >
              <span>←</span>
              <span>Projects</span>
            </Link>
            <h2 data-testid="project-title" className="text-2xl font-bold text-gray-900">
              {project?.name}
            </h2>
          </div>
          <button
            onClick={() => setIsCreateModalOpen(true)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            Create Task
          </button>
        </div>

        {/* Phase 2.4: Multi-device support - Working directory settings */}
        {projectId && (
          <WorkingDirectorySettings
            projectId={projectId}
            currentWorkingDirectory={project?.myWorkingDirectory}
          />
        )}

        <KanbanBoard
          tasks={tasks}
          onTaskMove={handleTaskMove}
          onTaskClick={handleTaskClick}
        />
      </main>

      <CreateTaskModal
        projectId={projectId || ''}
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onSubmit={handleCreateTask}
      />

      <TaskDetailPanel
        task={selectedTask}
        isOpen={isDetailPanelOpen}
        onClose={() => {
          setIsDetailPanelOpen(false)
          setSelectedTaskId(null)
        }}
      />
    </div>
  )
}
