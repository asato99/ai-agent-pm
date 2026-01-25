export type TaskStatus =
  | 'backlog'
  | 'todo'
  | 'in_progress'
  | 'blocked'
  | 'done'
  | 'cancelled'

export type TaskPriority = 'low' | 'medium' | 'high' | 'urgent'

// Note: Values match Domain/Entities/Task.swift ApprovalStatus rawValue
export type ApprovalStatus = 'approved' | 'pending_approval' | 'rejected'

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

  // Parent-child relationship
  parentTaskId: string | null

  // Dependencies
  dependencies: string[]
  dependentTasks: string[]

  // Block info
  blockedReason: string | null

  // Time tracking
  estimatedMinutes: number | null
  actualMinutes: number | null

  // Approval (existing)
  approvalStatus: ApprovalStatus
  requesterId: string | null
  rejectedReason: string | null

  // Other
  contexts: TaskContext[]
  createdAt: string
  updatedAt: string
}

// Task depth info for display
export interface TaskDepthInfo {
  level: number           // 0 = root, 1 = first level, ...
  parentTitle: string | null
  ancestorPath: string[]  // ['Auth Feature', 'Login', 'UI Implementation']
}

// Dependency display info
export interface DependencyDisplayInfo {
  id: string
  title: string
  status: TaskStatus
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
