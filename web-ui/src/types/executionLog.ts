// web-ui/src/types/executionLog.ts
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

export type ExecutionLogStatus = 'running' | 'completed' | 'failed'

export interface ExecutionLog {
  id: string
  taskId: string
  agentId: string
  agentName: string
  status: ExecutionLogStatus
  startedAt: string
  completedAt: string | null
  exitCode: number | null
  durationSeconds: number | null
  hasLogFile: boolean
  errorMessage: string | null
  reportedProvider: string | null
  reportedModel: string | null
}

export interface ExecutionLogContent {
  content: string
  filename: string
  fileSize: number
}

// Context entry with progress/findings/blockers
// Note: Renamed from TaskContext to avoid conflict with types/task.ts
export interface ContextEntry {
  id: string
  agentId: string
  agentName: string
  sessionId: string
  progress: string | null
  findings: string | null
  blockers: string | null
  nextSteps: string | null
  createdAt: string
  updatedAt: string
}

// Unified history item for timeline display
export type HistoryItemType = 'execution_log' | 'context'

export interface HistoryItem {
  type: HistoryItemType
  timestamp: string  // For sorting
  data: ExecutionLog | ContextEntry
}
