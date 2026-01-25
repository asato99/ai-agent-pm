// web-ui/src/components/task/TaskDetailPanel/TaskHistoryTab.tsx
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import { useState } from 'react'
import { useTaskHistory } from '@/hooks'
import { ExecutionLogItem, ContextItem } from '../HistoryItem'
import { ExecutionLogViewer } from '../ExecutionLogViewer'
import type { ExecutionLog, ContextEntry, HistoryItem } from '@/types'

interface TaskHistoryTabProps {
  taskId: string | null
}

export function TaskHistoryTab({ taskId }: TaskHistoryTabProps) {
  const { history, isLoading, error } = useTaskHistory(taskId)
  const [selectedLog, setSelectedLog] = useState<ExecutionLog | null>(null)
  const [isLogViewerOpen, setIsLogViewerOpen] = useState(false)

  const handleViewLog = (logId: string) => {
    const log = history.find(
      (item): item is HistoryItem & { data: ExecutionLog } =>
        item.type === 'execution_log' && item.data.id === logId
    )
    if (log) {
      setSelectedLog(log.data)
      setIsLogViewerOpen(true)
    }
  }

  const handleCloseLogViewer = () => {
    setIsLogViewerOpen(false)
    setSelectedLog(null)
  }

  if (isLoading) {
    return (
      <div className="space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="animate-pulse h-20 bg-gray-100 rounded-lg" />
        ))}
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-4 bg-red-50 border border-red-200 rounded-md">
        <p className="text-sm text-red-700">
          履歴の読み込みに失敗しました: {error.message}
        </p>
      </div>
    )
  }

  if (history.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        <p>履歴がありません</p>
      </div>
    )
  }

  return (
    <>
      <div className="space-y-3">
        {history.map((item) => {
          if (item.type === 'execution_log') {
            return (
              <ExecutionLogItem
                key={`log-${item.data.id}`}
                log={item.data as ExecutionLog}
                onViewLog={handleViewLog}
              />
            )
          }
          if (item.type === 'context') {
            return (
              <ContextItem
                key={`ctx-${item.data.id}`}
                context={item.data as ContextEntry}
              />
            )
          }
          return null
        })}
      </div>

      <ExecutionLogViewer
        log={selectedLog}
        isOpen={isLogViewerOpen}
        onClose={handleCloseLogViewer}
      />
    </>
  )
}
