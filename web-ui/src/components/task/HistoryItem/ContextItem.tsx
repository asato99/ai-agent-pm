// web-ui/src/components/task/HistoryItem/ContextItem.tsx
// 参照: docs/design/TASK_EXECUTION_LOG_DISPLAY.md

import type { ContextEntry } from '@/types'

interface ContextItemProps {
  context: ContextEntry
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

export function ContextItem({ context }: ContextItemProps) {
  const hasContent = context.progress || context.findings || context.blockers || context.nextSteps

  if (!hasContent) return null

  return (
    <div className="p-3 bg-white rounded-lg border border-gray-200 hover:border-gray-300 transition-colors">
      {/* Header with icon and timestamp */}
      <div className="flex items-center gap-2 mb-2">
        <span className="text-base" title="コンテキスト">📝</span>
        <span className="text-xs text-gray-500">{formatDateTime(context.updatedAt)}</span>
        <span className="text-xs text-gray-500">{context.agentName}</span>
      </div>

      {/* Context content */}
      <div className="space-y-1.5 text-sm">
        {context.progress && (
          <div className="flex items-start gap-2">
            <span className="text-gray-400 shrink-0">進捗:</span>
            <span className="text-gray-700">{context.progress}</span>
          </div>
        )}
        {context.findings && (
          <div className="flex items-start gap-2">
            <span className="text-gray-400 shrink-0">発見:</span>
            <span className="text-gray-700">{context.findings}</span>
          </div>
        )}
        {context.blockers && (
          <div className="flex items-start gap-2">
            <span className="text-orange-500 shrink-0">ブロッカー:</span>
            <span className="text-orange-700">{context.blockers}</span>
          </div>
        )}
        {context.nextSteps && (
          <div className="flex items-start gap-2">
            <span className="text-gray-400 shrink-0">次:</span>
            <span className="text-gray-700">{context.nextSteps}</span>
          </div>
        )}
      </div>
    </div>
  )
}
