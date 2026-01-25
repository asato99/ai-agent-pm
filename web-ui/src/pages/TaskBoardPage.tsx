import { useState, useMemo, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { AppHeader } from '@/components/layout'
import { KanbanBoard, CreateTaskModal, TaskDetailPanel } from '@/components/task'
import { WorkingDirectorySettings } from '@/components/project'
import { AssignedAgentsRow } from '@/components/agent/AssignedAgentsRow'
import { ChatPanel } from '@/components/chat'
import { useProject } from '@/hooks/useProject'
import { useTasks } from '@/hooks/useTasks'
import { useAssignableAgents, useAgentSessions, useAuth, useSubordinates } from '@/hooks'
import { useUnreadCounts } from '@/hooks/useUnreadCounts'
import { api } from '@/api/client'
import { getAncestorPath, getChildTasks, getBlockingTasks } from '@/utils/taskSorting'
import type { Task, TaskStatus, TaskPriority, Agent } from '@/types'

export function TaskBoardPage() {
  const { id: projectId } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const { agent: currentAgent } = useAuth()
  const { project, isLoading: projectLoading } = useProject(projectId || '')
  const { tasks, isLoading: tasksLoading } = useTasks(projectId || '')
  const { agents, isLoading: agentsLoading } = useAssignableAgents(projectId || '')
  const { sessionCounts } = useAgentSessions(projectId || '')
  const { subordinates } = useSubordinates()
  const { unreadCounts } = useUnreadCounts(projectId || '')
  const subordinateIds = subordinates.map((s) => s.id)

  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null)
  const [isDetailPanelOpen, setIsDetailPanelOpen] = useState(false)
  const [selectedChatAgent, setSelectedChatAgent] = useState<Agent | null>(null)
  const [isChatPanelOpen, setIsChatPanelOpen] = useState(false)

  // Derive selectedTask from tasks to ensure reactivity when task data changes
  const selectedTask = useMemo(
    () => (selectedTaskId ? tasks.find((t) => t.id === selectedTaskId) ?? null : null),
    [selectedTaskId, tasks]
  )

  // Compute hierarchy data for the selected task
  const hierarchyData = useMemo(() => {
    if (!selectedTask) {
      return { ancestors: [], childTasks: [], upstreamTasks: [], downstreamTasks: [] }
    }

    // Get ancestors (for hierarchy path)
    const ancestorTitles = getAncestorPath(selectedTask.id, tasks)
    const ancestors: { id: string; title: string; status: TaskStatus }[] = []
    let currentParentId = selectedTask.parentTaskId
    for (const title of ancestorTitles) {
      const parent = tasks.find((t) => t.id === currentParentId)
      if (parent) {
        ancestors.push({ id: parent.id, title: parent.title, status: parent.status })
        currentParentId = parent.parentTaskId
      }
    }
    // Reverse to get root-first order
    ancestors.reverse()

    // Get child tasks
    const children = getChildTasks(selectedTask.id, tasks)
    const childTasks = children.map((t) => ({
      id: t.id,
      title: t.title,
      status: t.status,
    }))

    // Get upstream dependencies (tasks this task depends on)
    const upstreamTasks = (selectedTask.dependencies ?? [])
      .map((depId) => tasks.find((t) => t.id === depId))
      .filter((t): t is Task => t !== undefined)
      .map((t) => ({ id: t.id, title: t.title, status: t.status }))

    // Get downstream dependencies (tasks that depend on this task)
    const downstreamTasks = (selectedTask.dependentTasks ?? [])
      .map((depId) => tasks.find((t) => t.id === depId))
      .filter((t): t is Task => t !== undefined)
      .map((t) => ({ id: t.id, title: t.title, status: t.status }))

    return { ancestors, childTasks, upstreamTasks, downstreamTasks }
  }, [selectedTask, tasks])

  const handleTaskSelect = useCallback((taskId: string) => {
    setSelectedTaskId(taskId)
  }, [])

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

  const handleAgentClick = (agentId: string) => {
    const agent = agents.find((a) => a.id === agentId)
    if (agent) {
      setSelectedChatAgent(agent)
      setIsChatPanelOpen(true)
    }
  }

  const handleCloseChatPanel = () => {
    setIsChatPanelOpen(false)
    setSelectedChatAgent(null)
  }

  const isLoading = projectLoading || tasksLoading || agentsLoading

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

        {/* Agent session status display - similar to native app */}
        <AssignedAgentsRow
          agents={agents}
          sessionCounts={sessionCounts}
          currentAgentId={currentAgent?.id}
          subordinateIds={subordinateIds}
          isLoading={agentsLoading}
          onAgentClick={handleAgentClick}
          unreadCounts={unreadCounts}
        />

        {/* Phase 2.4: Multi-device support - Working directory settings */}
        {projectId && (
          <WorkingDirectorySettings
            projectId={projectId}
            currentWorkingDirectory={project?.myWorkingDirectory}
          />
        )}

        <KanbanBoard
          tasks={tasks}
          agents={agents}
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
        ancestors={hierarchyData.ancestors}
        childTasks={hierarchyData.childTasks}
        upstreamTasks={hierarchyData.upstreamTasks}
        downstreamTasks={hierarchyData.downstreamTasks}
        onTaskSelect={handleTaskSelect}
      />

      {/* Chat Panel - opens when clicking on an agent avatar */}
      {isChatPanelOpen && selectedChatAgent && projectId && (
        <div className="fixed right-0 top-0 h-full w-96 shadow-xl z-50">
          <ChatPanel
            projectId={projectId}
            agent={selectedChatAgent}
            onClose={handleCloseChatPanel}
          />
        </div>
      )}
    </div>
  )
}
