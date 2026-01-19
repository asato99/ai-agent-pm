export type TaskStatus =
  | 'backlog'
  | 'todo'
  | 'in_progress'
  | 'blocked'
  | 'done'
  | 'cancelled'

export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent'

export interface TaskContext {
  id: string
  agentId: string
  content: string
  createdAt: string
}

export interface Task {
  id: string
  projectId: string
  title: string
  description: string
  status: TaskStatus
  priority: TaskPriority
  assigneeId: string | null
  creatorId: string
  dependencies: string[]
  contexts: TaskContext[]
  createdAt: string
  updatedAt: string
}

export interface CreateTaskInput {
  title: string
  description?: string
  status?: TaskStatus
  priority?: TaskPriority
  assigneeId?: string
  dependencies?: string[]
}

export interface UpdateTaskInput {
  title?: string
  description?: string
  status?: TaskStatus
  priority?: TaskPriority
  assigneeId?: string | null
  dependencies?: string[]
}

export interface TaskPermissions {
  canEdit: boolean
  canChangeStatus: boolean
  canReassign: boolean
  validStatusTransitions: TaskStatus[]
  reason: string | null
}
