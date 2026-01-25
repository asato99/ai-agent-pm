// web-ui/src/components/task/ExecutionLogViewer/ExecutionLogViewer.tsx
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import { useExecutionLogContent } from '@/hooks'
import type { ExecutionLog, ExecutionLogStatus } from '@/types'

interface ExecutionLogViewerProps {
  log: ExecutionLog | null
  isOpen: boolean
  onClose: () => void
}

const statusConfig: Record<ExecutionLogStatus, { icon: string; label: string; className: string }> = {
  running: {
    icon: '🔄',
    label: '実行中',
    className: 'text-blue-600',
  },
  completed: {
    icon: '✅',
    label: '正常終了',
    className: 'text-green-600',
  },
  failed: {
    icon: '❌',
    label: '失敗',
    className: 'text-red-600',
  },
}

function formatDateTime(dateStr: string): string {
  const date = new Date(dateStr)
  return date.toLocaleString('ja-JP', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function ExecutionLogViewer({ log, isOpen, onClose }: ExecutionLogViewerProps) {
  const { content, isLoading, error } = useExecutionLogContent(isOpen && log ? log.id : null)

  if (!isOpen || !log) return null

  const status = statusConfig[log.status]

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-[60] flex items-center justify-center"
      onClick={onClose}
    >
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50 pointer-events-none" aria-hidden="true" />

      {/* Modal */}
      <div
        className="relative bg-white rounded-lg shadow-xl w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start justify-between p-4 border-b">
          <div className="flex-1 min-w-0">
            <h2 className="text-lg font-bold text-gray-900">実行ログ</h2>
            <div className="mt-1 text-sm text-gray-500">
              {log.agentName}
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="ml-4 p-1 text-gray-400 hover:text-gray-600 rounded"
            aria-label="Close"
          >
            <svg className="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        {/* Meta info */}
        <div className="p-4 bg-gray-50 border-b space-y-2">
          <div className="flex items-center gap-4 text-sm">
            <span className="text-gray-500">📅 {formatDateTime(log.startedAt)}</span>
            {log.completedAt && (
              <span className="text-gray-500">- {formatDateTime(log.completedAt)}</span>
            )}
          </div>
          {log.reportedModel && (
            <div className="text-sm text-gray-500">
              🤖 {log.reportedModel}
              {log.reportedProvider && ` (${log.reportedProvider})`}
            </div>
          )}
          <div className={`text-sm font-medium ${status.className}`}>
            {status.icon} {status.label}
            {log.exitCode !== null && ` (exit: ${log.exitCode})`}
          </div>
        </div>

        {/* Log content */}
        <div className="flex-1 overflow-y-auto p-4">
          {isLoading ? (
            <div className="flex items-center justify-center h-32">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
            </div>
          ) : error ? (
            <div className="p-4 bg-red-50 border border-red-200 rounded-md">
              <p className="text-sm text-red-700">
                ログファイルの読み込みに失敗しました: {error.message}
              </p>
            </div>
          ) : content ? (
            <div>
              <div className="flex items-center justify-between mb-2 text-xs text-gray-500">
                <span>{content.filename}</span>
                <span>{formatFileSize(content.fileSize)}</span>
              </div>
              <pre className="p-4 bg-gray-900 text-gray-100 rounded-lg overflow-x-auto text-xs font-mono whitespace-pre-wrap break-all">
                {content.content}
              </pre>
            </div>
          ) : (
            <div className="text-center text-gray-500">
              ログファイルがありません
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end p-4 border-t bg-gray-50">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  )
}
