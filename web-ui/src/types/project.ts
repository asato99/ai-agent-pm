export type ProjectStatus = 'active' | 'paused' | 'archived'

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
  /** Working directory for logged-in agent in this project (Phase 2.4: Multi-device support) */
  myWorkingDirectory?: string
}
