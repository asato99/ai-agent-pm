import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api } from '@/api/client'
import { useTaskPermissions } from '@/hooks'
import type { Task, TaskStatus } from '@/types'
import { StatusPicker } from './StatusPicker'

interface TaskDetailPanelProps {
  task: Task | null
  isOpen: boolean
  onClose: () => void
}

const priorityLabels: Record<string, string> = {
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  urgent: 'Urgent',
}

const priorityStyles: Record<string, string> = {
  low: 'bg-gray-100 text-gray-700',
  medium: 'bg-blue-100 text-blue-700',
  high: 'bg-orange-100 text-orange-700',
  urgent: 'bg-red-100 text-red-700',
}

export function TaskDetailPanel({ task, isOpen, onClose }: TaskDetailPanelProps) {
  const queryClient = useQueryClient()
  const { permissions, isLoading: permissionsLoading } = useTaskPermissions(task?.id ?? null)
  const [error, setError] = useState<string | null>(null)

  const updateStatusMutation = useMutation({
    mutationFn: async ({ taskId, status }: { taskId: string; status: TaskStatus }) => {
      const result = await api.patch<Task>(`/tasks/${taskId}`, { status })
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      setError(null)
      queryClient.invalidateQueries({ queryKey: ['tasks'] })
      queryClient.invalidateQueries({ queryKey: ['task-permissions', task?.id] })
    },
    onError: (err: Error) => {
      setError(err.message)
    },
  })

  if (!isOpen || !task) return null

  const handleStatusChange = (newStatus: TaskStatus) => {
    if (task && newStatus !== task.status) {
      updateStatusMutation.mutate({ taskId: task.id, status: newStatus })
    }
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center"
    >
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      {/* Panel */}
      <div className="relative bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-start justify-between p-6 border-b">
          <div className="flex-1 min-w-0">
            <h2 className="text-xl font-bold text-gray-900 truncate">{task.title}</h2>
            <span
              className={`inline-block mt-2 px-2 py-1 text-xs font-medium rounded ${priorityStyles[task.priority]}`}
            >
              {priorityLabels[task.priority]}
            </span>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="ml-4 p-1 text-gray-400 hover:text-gray-600 rounded"
            aria-label="閉じる"
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

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {/* Error message */}
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-md">
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

          {/* Status picker */}
          <div>
            {permissionsLoading ? (
              <div className="animate-pulse h-8 bg-gray-200 rounded w-48" />
            ) : (
              <StatusPicker
                value={task.status}
                validTransitions={permissions?.validStatusTransitions ?? []}
                disabled={!permissions?.canChangeStatus || updateStatusMutation.isPending}
                onChange={handleStatusChange}
              />
            )}
            {permissions?.reason && !permissions.canChangeStatus && (
              <p className="mt-1 text-xs text-gray-500">{permissions.reason}</p>
            )}
          </div>

          {/* Description */}
          <div>
            <h3 className="text-sm font-medium text-gray-700 mb-2">説明</h3>
            <p className="text-gray-600 whitespace-pre-wrap">
              {task.description || '説明がありません'}
            </p>
          </div>

          {/* Task Details */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-1">作成日</h3>
              <p className="text-sm text-gray-600">
                {new Date(task.createdAt).toLocaleDateString('ja-JP')}
              </p>
            </div>
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-1">更新日</h3>
              <p className="text-sm text-gray-600">
                {new Date(task.updatedAt).toLocaleDateString('ja-JP')}
              </p>
            </div>
          </div>

          {/* Dependencies */}
          {task.dependencies.length > 0 && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">依存タスク</h3>
              <div className="flex flex-wrap gap-2">
                {task.dependencies.map((depId) => (
                  <span
                    key={depId}
                    className="px-2 py-1 text-xs bg-gray-100 text-gray-700 rounded"
                  >
                    {depId}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 p-6 border-t bg-gray-50">
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
