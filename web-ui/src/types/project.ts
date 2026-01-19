export type ProjectStatus = 'active' | 'archived'

export interface Project {
  id: string
  name: string
  description: string
  status: ProjectStatus
  createdAt: string
  updatedAt: string
}

export interface ProjectSummary extends Project {
  taskCount: number
  completedCount: number
  inProgressCount: number
  blockedCount: number
  myTaskCount: number
}
