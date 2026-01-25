import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { api } from '@/api/client'
import { useTaskPermissions, useTaskHandoffs, useCreateHandoff, useAssignableAgents } from '@/hooks'
import type { Task, TaskStatus, CreateHandoffInput, ApprovalStatus } from '@/types'
import { StatusPicker } from './StatusPicker'
import { TaskEditForm } from '../TaskEditForm'
import { TaskHistoryTab } from './TaskHistoryTab'

type TabType = 'details' | 'history'

const approvalStatusLabels: Record<ApprovalStatus, string> = {
  approved: '承認済み',
  pending_approval: '承認待ち',
  rejected: '却下',
}

const approvalStatusStyles: Record<ApprovalStatus, string> = {
  approved: 'bg-green-100 text-green-700 border-green-300',
  pending_approval: 'bg-orange-100 text-orange-700 border-orange-300',
  rejected: 'bg-gray-100 text-gray-700 border-gray-300',
}

// Minimal task info for hierarchy display
interface TaskSummary {
  id: string
  title: string
  status: TaskStatus
}

interface TaskDetailPanelProps {
  task: Task | null
  isOpen: boolean
  onClose: () => void
  ancestors?: TaskSummary[]
  childTasks?: TaskSummary[]
  upstreamTasks?: TaskSummary[]
  downstreamTasks?: TaskSummary[]
  onTaskSelect?: (taskId: string) => void
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

const statusIcons: Record<TaskStatus, string> = {
  backlog: '📋',
  todo: '📝',
  in_progress: '🔴',
  blocked: '⏸️',
  done: '✅',
  cancelled: '❌',
}

const statusLabels: Record<TaskStatus, string> = {
  backlog: 'Backlog',
  todo: 'To Do',
  in_progress: 'In Progress',
  blocked: 'Blocked',
  done: 'Done',
  cancelled: 'Cancelled',
}

export function TaskDetailPanel({
  task,
  isOpen,
  onClose,
  ancestors = [],
  childTasks = [],
  upstreamTasks = [],
  downstreamTasks = [],
  onTaskSelect,
}: TaskDetailPanelProps) {
  const queryClient = useQueryClient()
  const { permissions, isLoading: permissionsLoading } = useTaskPermissions(task?.id ?? null)
  const { handoffs, isLoading: handoffsLoading } = useTaskHandoffs(task?.id ?? null)
  const { agents } = useAssignableAgents(task?.projectId ?? '')
  const createHandoffMutation = useCreateHandoff()
  const [error, setError] = useState<string | null>(null)
  const [isEditFormOpen, setIsEditFormOpen] = useState(false)
  const [isHandoffFormOpen, setIsHandoffFormOpen] = useState(false)
  const [activeTab, setActiveTab] = useState<TabType>('details')
  const [handoffSummary, setHandoffSummary] = useState('')
  const [handoffContext, setHandoffContext] = useState('')
  const [handoffToAgentId, setHandoffToAgentId] = useState('')

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

  const approveTaskMutation = useMutation({
    mutationFn: async (taskId: string) => {
      const result = await api.post<Task>(`/tasks/${taskId}/approve`, {})
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

  const rejectTaskMutation = useMutation({
    mutationFn: async ({ taskId, reason }: { taskId: string; reason?: string }) => {
      const result = await api.post<Task>(`/tasks/${taskId}/reject`, { reason })
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
      onClick={onClose}
    >
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/50 pointer-events-none" aria-hidden="true" />

      {/* Panel */}
      <div
        className="relative bg-white rounded-lg shadow-xl w-full max-w-lg max-h-[90vh] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
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

        {/* Tab Navigation */}
        <div className="flex border-b bg-gray-50">
          <button
            type="button"
            onClick={() => setActiveTab('details')}
            className={`px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
              activeTab === 'details'
                ? 'text-blue-600 border-blue-600 bg-white'
                : 'text-gray-500 border-transparent hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            詳細
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('history')}
            className={`px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
              activeTab === 'history'
                ? 'text-blue-600 border-blue-600 bg-white'
                : 'text-gray-500 border-transparent hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            履歴
          </button>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {/* History Tab */}
          {activeTab === 'history' && <TaskHistoryTab taskId={task.id} />}

          {/* Details Tab */}
          {activeTab === 'details' && (
            <>
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

          {/* Approval Section - only show when not approved */}
          {task.approvalStatus !== 'approved' && (
            <div className="p-4 rounded-lg border bg-orange-50 border-orange-200">
              <div className="flex items-center justify-between mb-3">
                <span
                  className={`inline-block px-2 py-1 text-sm font-medium rounded border ${approvalStatusStyles[task.approvalStatus]}`}
                >
                  {approvalStatusLabels[task.approvalStatus]}
                </span>
              </div>

              {/* Requester info */}
              {task.requesterId && (
                <div className="mb-3">
                  <span className="text-sm text-gray-600">依頼者: </span>
                  <span className="text-sm font-medium text-gray-900">
                    {agents.find((a) => a.id === task.requesterId)?.name ?? task.requesterId}
                  </span>
                </div>
              )}

              {/* Rejected reason */}
              {task.approvalStatus === 'rejected' && task.rejectedReason && (
                <div className="mb-3 p-2 bg-gray-100 rounded">
                  <span className="text-sm text-gray-600">却下理由: </span>
                  <span className="text-sm text-gray-900">{task.rejectedReason}</span>
                </div>
              )}

              {/* Approve/Reject buttons - only show when pending */}
              {task.approvalStatus === 'pending_approval' && (
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => approveTaskMutation.mutate(task.id)}
                    disabled={approveTaskMutation.isPending || rejectTaskMutation.isPending}
                    className="px-4 py-2 text-white bg-green-600 rounded-md hover:bg-green-700 disabled:opacity-50 text-sm font-medium"
                  >
                    {approveTaskMutation.isPending ? '処理中...' : '承認'}
                  </button>
                  <button
                    type="button"
                    onClick={() => rejectTaskMutation.mutate({ taskId: task.id })}
                    disabled={approveTaskMutation.isPending || rejectTaskMutation.isPending}
                    className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50 text-sm font-medium"
                  >
                    {rejectTaskMutation.isPending ? '処理中...' : '却下'}
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Description */}
          <div>
            <h3 className="text-sm font-medium text-gray-700 mb-2">Description</h3>
            <p className="text-gray-600 whitespace-pre-wrap">
              {task.description || 'No description'}
            </p>
          </div>

          {/* Task Details */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-1">Created</h3>
              <p className="text-sm text-gray-600">
                {new Date(task.createdAt).toLocaleDateString()}
              </p>
            </div>
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-1">Updated</h3>
              <p className="text-sm text-gray-600">
                {new Date(task.updatedAt).toLocaleDateString()}
              </p>
            </div>
          </div>

          {/* Assignee */}
          <div>
            <h3 className="text-sm font-medium text-gray-700 mb-1">Assignee</h3>
            <p className="text-sm text-gray-600">
              {task.assigneeId
                ? agents.find((a) => a.id === task.assigneeId)?.name ?? task.assigneeId
                : 'Unassigned'}
            </p>
          </div>

          {/* Hierarchy Path - only show for non-root tasks */}
          {ancestors.length > 0 && (
            <div data-testid="hierarchy-path">
              <h3 className="text-sm font-medium text-gray-700 mb-2">階層パス</h3>
              <div className="flex items-center flex-wrap gap-1 text-sm">
                {ancestors.map((ancestor, index) => (
                  <span key={ancestor.id} className="flex items-center gap-1">
                    {index > 0 && <span className="text-gray-400">{'>'}</span>}
                    <button
                      type="button"
                      onClick={() => onTaskSelect?.(ancestor.id)}
                      className="text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      {ancestor.title}
                    </button>
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Child Tasks - only show if there are children */}
          {childTasks.length > 0 && (
            <div data-testid="children-section">
              <h3 className="text-sm font-medium text-gray-700 mb-2">
                子タスク ({childTasks.length}件)
              </h3>
              <div className="space-y-2">
                {childTasks.map((child) => (
                  <div
                    key={child.id}
                    className="flex items-center justify-between p-2 bg-gray-50 rounded"
                  >
                    <button
                      type="button"
                      onClick={() => onTaskSelect?.(child.id)}
                      className="text-sm text-gray-900 hover:text-blue-600 hover:underline"
                    >
                      {child.title}
                    </button>
                    <span className="text-xs text-gray-500">{statusLabels[child.status]}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Upstream Dependencies */}
          {upstreamTasks.length > 0 && (
            <div data-testid="upstream-dependencies">
              <h3 className="text-sm font-medium text-gray-700 mb-2">依存先</h3>
              <div className="space-y-2">
                {upstreamTasks.map((dep) => (
                  <div
                    key={dep.id}
                    className="flex items-center gap-2 p-2 bg-gray-50 rounded"
                  >
                    <span>{statusIcons[dep.status]}</span>
                    <button
                      type="button"
                      onClick={() => onTaskSelect?.(dep.id)}
                      className="text-sm text-gray-900 hover:text-blue-600 hover:underline"
                    >
                      {dep.title}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Downstream Dependencies */}
          {downstreamTasks.length > 0 && (
            <div data-testid="downstream-dependencies">
              <h3 className="text-sm font-medium text-gray-700 mb-2">依存元</h3>
              <div className="space-y-2">
                {downstreamTasks.map((dep) => (
                  <div
                    key={dep.id}
                    className="flex items-center gap-2 p-2 bg-gray-50 rounded"
                  >
                    <span>{statusIcons[dep.status]}</span>
                    <button
                      type="button"
                      onClick={() => onTaskSelect?.(dep.id)}
                      className="text-sm text-gray-900 hover:text-blue-600 hover:underline"
                    >
                      {dep.title}
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Dependencies (legacy - show task IDs) */}
          {task.dependencies.length > 0 && upstreamTasks.length === 0 && (
            <div>
              <h3 className="text-sm font-medium text-gray-700 mb-2">Dependencies</h3>
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

          {/* Handoffs Section */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <h3 className="text-sm font-medium text-gray-700">Handoff History</h3>
              <button
                type="button"
                onClick={() => setIsHandoffFormOpen(!isHandoffFormOpen)}
                className="text-sm text-blue-600 hover:text-blue-700"
              >
                {isHandoffFormOpen ? 'Cancel' : '+ New Handoff'}
              </button>
            </div>

            {/* Create Handoff Form */}
            {isHandoffFormOpen && (
              <div className="mb-4 p-4 bg-gray-50 rounded-lg border">
                <div className="space-y-3">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Target Agent (Optional)
                    </label>
                    <select
                      value={handoffToAgentId}
                      onChange={(e) => setHandoffToAgentId(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                    >
                      <option value="">Not specified (visible to all)</option>
                      {agents.map((agent) => (
                        <option key={agent.id} value={agent.id}>
                          {agent.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Summary <span className="text-red-500">*</span>
                    </label>
                    <input
                      type="text"
                      value={handoffSummary}
                      onChange={(e) => setHandoffSummary(e.target.value)}
                      placeholder="Summary of handoff"
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Context (Optional)
                    </label>
                    <textarea
                      value={handoffContext}
                      onChange={(e) => setHandoffContext(e.target.value)}
                      placeholder="Background or notes"
                      rows={3}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
                    />
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      if (!handoffSummary.trim()) return
                      const input: CreateHandoffInput = {
                        taskId: task.id,
                        summary: handoffSummary,
                        context: handoffContext || null,
                        toAgentId: handoffToAgentId || null,
                      }
                      createHandoffMutation.mutate(input, {
                        onSuccess: () => {
                          setHandoffSummary('')
                          setHandoffContext('')
                          setHandoffToAgentId('')
                          setIsHandoffFormOpen(false)
                        },
                        onError: (err) => {
                          setError(err.message)
                        },
                      })
                    }}
                    disabled={!handoffSummary.trim() || createHandoffMutation.isPending}
                    className="w-full px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700 disabled:opacity-50 text-sm"
                  >
                    {createHandoffMutation.isPending ? 'Creating...' : 'Create Handoff'}
                  </button>
                </div>
              </div>
            )}

            {/* Handoffs List */}
            {handoffsLoading ? (
              <div className="animate-pulse space-y-2">
                <div className="h-16 bg-gray-200 rounded" />
              </div>
            ) : handoffs.length === 0 ? (
              <p className="text-sm text-gray-500">No handoff history</p>
            ) : (
              <div className="space-y-2">
                {handoffs.map((handoff) => (
                  <div
                    key={handoff.id}
                    className={`p-3 rounded-lg border ${
                      handoff.isPending ? 'bg-yellow-50 border-yellow-200' : 'bg-gray-50 border-gray-200'
                    }`}
                  >
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-xs text-gray-500">
                        {new Date(handoff.createdAt).toLocaleString()}
                      </span>
                      <span
                        className={`text-xs px-2 py-0.5 rounded ${
                          handoff.isPending
                            ? 'bg-yellow-100 text-yellow-800'
                            : 'bg-green-100 text-green-800'
                        }`}
                      >
                        {handoff.isPending ? 'Pending' : 'Accepted'}
                      </span>
                    </div>
                    <p className="text-sm font-medium text-gray-900">{handoff.summary}</p>
                    {handoff.context && (
                      <p className="text-xs text-gray-600 mt-1">{handoff.context}</p>
                    )}
                    <div className="text-xs text-gray-500 mt-1">
                      From: {handoff.fromAgentId}
                      {handoff.toAgentId && ` → To: ${handoff.toAgentId}`}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 p-6 border-t bg-gray-50">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Close
          </button>
          {permissions?.canEdit && (
            <button
              type="button"
              onClick={() => setIsEditFormOpen(true)}
              className="px-4 py-2 text-white bg-blue-600 rounded-md hover:bg-blue-700"
            >
              Edit
            </button>
          )}
        </div>
      </div>

      {/* Edit Form Modal */}
      <TaskEditForm
        task={task}
        isOpen={isEditFormOpen}
        onClose={() => setIsEditFormOpen(false)}
      />
    </div>
  )
}
