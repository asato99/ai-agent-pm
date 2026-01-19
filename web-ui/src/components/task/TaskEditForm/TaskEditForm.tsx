import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState, useEffect } from 'react'
import { api } from '@/api/client'
import { useTaskPermissions, useAssignableAgents } from '@/hooks'
import type { Task, TaskPriority, UpdateTaskInput } from '@/types'

interface TaskEditFormProps {
  task: Task
  isOpen: boolean
  onClose: () => void
}

export function TaskEditForm({ task, isOpen, onClose }: TaskEditFormProps) {
  const queryClient = useQueryClient()
  const { permissions, isLoading: permissionsLoading } = useTaskPermissions(task.id)
  const { agents, isLoading: agentsLoading } = useAssignableAgents()

  const [title, setTitle] = useState(task.title)
  const [description, setDescription] = useState(task.description)
  const [priority, setPriority] = useState<TaskPriority>(task.priority)
  const [assigneeId, setAssigneeId] = useState<string>(task.assigneeId ?? '')
  const [error, setError] = useState<string | null>(null)

  // Reset form when task changes
  useEffect(() => {
    setTitle(task.title)
    setDescription(task.description)
    setPriority(task.priority)
    setAssigneeId(task.assigneeId ?? '')
    setError(null)
  }, [task])

  const updateTaskMutation = useMutation({
    mutationFn: async (data: UpdateTaskInput) => {
      const result = await api.patch<Task>(`/tasks/${task.id}`, data)
      if (result.error) {
        throw new Error(result.error.message)
      }
      return result.data!
    },
    onSuccess: () => {
      setError(null)
      queryClient.invalidateQueries({ queryKey: ['tasks'] })
      queryClient.invalidateQueries({ queryKey: ['task-permissions', task.id] })
      onClose()
    },
    onError: (err: Error) => {
      setError(err.message)
    },
  })

  if (!isOpen) return null

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()

    const updates: UpdateTaskInput = {}

    if (title !== task.title) {
      updates.title = title
    }
    if (description !== task.description) {
      updates.description = description
    }
    if (priority !== task.priority) {
      updates.priority = priority
    }
    // Only include assigneeId if it changed and user has permission
    const newAssigneeId = assigneeId === '' ? null : assigneeId
    if (newAssigneeId !== task.assigneeId && permissions?.canReassign) {
      updates.assigneeId = newAssigneeId
    }

    // Only submit if there are changes
    if (Object.keys(updates).length > 0) {
      updateTaskMutation.mutate(updates)
    } else {
      onClose()
    }
  }

  const isLoading = permissionsLoading || agentsLoading

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center"
    >
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      {/* Form */}
      <div className="relative bg-white rounded-lg shadow-xl p-6 w-full max-w-md max-h-[90vh] overflow-y-auto">
        <h2 className="text-xl font-bold text-gray-900 mb-4">タスク編集</h2>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-md">
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="space-y-4">
            {/* Title */}
            <div>
              <label htmlFor="edit-title" className="block text-sm font-medium text-gray-700 mb-1">
                タイトル
              </label>
              <input
                type="text"
                id="edit-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                required
              />
            </div>

            {/* Description */}
            <div>
              <label
                htmlFor="edit-description"
                className="block text-sm font-medium text-gray-700 mb-1"
              >
                説明
              </label>
              <textarea
                id="edit-description"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={4}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* Priority */}
            <div>
              <label
                htmlFor="edit-priority"
                className="block text-sm font-medium text-gray-700 mb-1"
              >
                優先度
              </label>
              <select
                id="edit-priority"
                value={priority}
                onChange={(e) => setPriority(e.target.value as TaskPriority)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option value="low">Low</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
                <option value="urgent">Urgent</option>
              </select>
            </div>

            {/* Assignee */}
            <div>
              <label
                htmlFor="edit-assignee"
                className="block text-sm font-medium text-gray-700 mb-1"
              >
                担当エージェント
              </label>
              <select
                id="edit-assignee"
                value={assigneeId}
                onChange={(e) => setAssigneeId(e.target.value)}
                disabled={isLoading || !permissions?.canReassign}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100 disabled:cursor-not-allowed"
              >
                <option value="">未割り当て</option>
                {agents.map((agent) => (
                  <option key={agent.id} value={agent.id}>
                    {agent.name}
                  </option>
                ))}
              </select>
              {!permissions?.canReassign && permissions?.reason && (
                <p className="mt-1 text-xs text-amber-600">{permissions.reason}</p>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex justify-end gap-3 mt-6">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
            >
              キャンセル
            </button>
            <button
              type="submit"
              disabled={updateTaskMutation.isPending}
              className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50"
            >
              {updateTaskMutation.isPending ? '保存中...' : '保存'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
