// web-ui/src/components/task/HistoryItem/ExecutionLogItem.tsx
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import type { ExecutionLog, ExecutionLogStatus } from '@/types'

interface ExecutionLogItemProps {
  log: ExecutionLog
  onViewLog: (logId: string) => void
}

const statusConfig: Record<ExecutionLogStatus, { icon: string; label: string; className: string }> = {
  running: {
    icon: '🔄',
    label: '実行中',
    className: 'text-blue-600',
  },
  completed: {
    icon: '✅',
    label: '完了',
    className: 'text-green-600',
  },
  failed: {
    icon: '❌',
    label: '失敗',
    className: 'text-red-600',
  },
}

function formatDuration(seconds: number | null): string {
  if (seconds === null) return '-'
  if (seconds < 60) return `${Math.round(seconds)}秒`
  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = Math.round(seconds % 60)
  return `${minutes}分${remainingSeconds}秒`
}

function formatDateTime(dateStr: string): string {
  const date = new Date(dateStr)
  return date.toLocaleDateString('ja-JP', {
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function ExecutionLogItem({ log, onViewLog }: ExecutionLogItemProps) {
  const status = statusConfig[log.status]

  return (
    <div className="p-3 bg-white rounded-lg border border-gray-200 hover:border-gray-300 transition-colors">
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          {/* Header with icon and timestamp */}
          <div className="flex items-center gap-2 mb-1">
            <span className="text-base" title="実行ログ">📋</span>
            <span className="text-xs text-gray-500">{formatDateTime(log.startedAt)}</span>
            <span className="text-xs text-gray-500">{log.agentName}</span>
          </div>

          {/* Status and duration */}
          <div className="flex items-center gap-2">
            <span className={`text-sm font-medium ${status.className}`}>
              {status.icon} {status.label}
            </span>
            {log.durationSeconds !== null && (
              <span className="text-xs text-gray-500">
                {formatDuration(log.durationSeconds)}
              </span>
            )}
          </div>

          {/* Model info */}
          {log.reportedModel && (
            <div className="text-xs text-gray-500 mt-1">
              {log.reportedModel}
            </div>
          )}

          {/* Error message */}
          {log.errorMessage && (
            <div className="text-xs text-red-600 mt-1 truncate">
              {log.errorMessage}
            </div>
          )}
        </div>

        {/* View log button */}
        {log.hasLogFile && (
          <button
            type="button"
            onClick={() => onViewLog(log.id)}
            className="ml-2 px-2 py-1 text-xs text-blue-600 hover:text-blue-800 hover:bg-blue-50 rounded transition-colors"
          >
            ログ表示
          </button>
        )}
      </div>
    </div>
  )
}
